#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Semantic checking for 'parallel'.

# - codegen needs to support mSlice (+)
# - lowerings must not perform unnecessary copies (+)
# - slices should become "nocopy" to openArray (+)
#   - need to perform bound checks (+)
#
# - parallel needs to insert a barrier (+)
# - passed arguments need to be ensured to be "const"
#   - what about 'f(a)'? --> f shouldn't have side effects anyway
# - passed arrays need to be ensured not to alias
# - passed slices need to be ensured to be disjoint (+)
# - output slices need special logic (+)

import
  ast, astalgo, idents, lowerings, magicsys, guards, msgs,
  renderer, types, modulegraphs, options, spawn, lineinfos

from trees import getMagic, getRoot
from std/strutils import `%`

discard """

one major problem:
  spawn f(a[i])
  inc i
  spawn f(a[i])
is valid, but
  spawn f(a[i])
  spawn f(a[i])
  inc i
is not! However,
  spawn f(a[i])
  if guard: inc i
  spawn f(a[i])
is not valid either! --> We need a flow dependent analysis here.

However:
  while foo:
    spawn f(a[i])
    inc i
    spawn f(a[i])

Is not valid either! --> We should really restrict 'inc' to loop endings?

The heuristic that we implement here (that has no false positives) is: Usage
of 'i' in a slice *after* we determined the stride is invalid!
"""

type
  TDirection = enum
    ascending, descending
  MonotonicVar = object
    v, alias: PSym        # to support the ordinary 'countup' iterator
                          # we need to detect aliases
    lower, upper, stride: PNode
    dir: TDirection
    blacklisted: bool     # blacklisted variables that are not monotonic
  AnalysisCtx = object
    locals: seq[MonotonicVar]
    slices: seq[tuple[x,a,b: PNode, spawnId: int, inLoop: bool]]
    guards: TModel      # nested guards
    args: seq[PSym]     # args must be deeply immutable
    spawns: int         # we can check that at last 1 spawn is used in
                        # the 'parallel' section
    currentSpawnId: int
    inLoop: int
    graph: ModuleGraph

proc initAnalysisCtx(g: ModuleGraph): AnalysisCtx =
  result = AnalysisCtx(locals: @[],
    slices: @[],
    args: @[],
    graph: g)
  result.guards.s = @[]
  result.guards.g = g

proc lookupSlot(c: AnalysisCtx; s: PSym): int =
  for i in 0..<c.locals.len:
    if c.locals[i].v == s or c.locals[i].alias == s: return i
  return -1

proc getSlot(c: var AnalysisCtx; v: PSym): ptr MonotonicVar =
  let s = lookupSlot(c, v)
  if s >= 0: return addr(c.locals[s])
  c.locals.setLen(c.locals.len+1)
  c.locals[^1].v = v
  return addr(c.locals[^1])

proc gatherArgs(c: var AnalysisCtx; n: PNode) =
  for i in 0..<n.safeLen:
    let root = getRoot n[i]
    if root != nil:
      block addRoot:
        for r in items(c.args):
          if r == root: break addRoot
        c.args.add root
    gatherArgs(c, n[i])

proc isSingleAssignable(n: PNode): bool =
  n.kind == nkSym and (let s = n.sym;
    s.kind in {skTemp, skForVar, skLet} and
          {sfAddrTaken, sfGlobal} * s.flags == {})

proc isLocal(n: PNode): bool =
  n.kind == nkSym and (let s = n.sym;
    s.kind in {skResult, skTemp, skForVar, skVar, skLet} and
          {sfAddrTaken, sfGlobal} * s.flags == {})

proc checkLocal(c: AnalysisCtx; n: PNode) =
  if isLocal(n):
    let s = c.lookupSlot(n.sym)
    if s >= 0 and c.locals[s].stride != nil:
      localError(c.graph.config, n.info, "invalid usage of counter after increment")
  else:
    for i in 0..<n.safeLen: checkLocal(c, n[i])

template `?`(x): untyped = x.renderTree

proc checkLe(c: AnalysisCtx; a, b: PNode) =
  case proveLe(c.guards, a, b)
  of impUnknown:
    message(c.graph.config, a.info, warnStaticIndexCheck,
      "cannot prove: " & ?a & " <= " & ?b)
  of impYes: discard
  of impNo:
    message(c.graph.config, a.info, warnStaticIndexCheck,
      "can prove: " & ?a & " > " & ?b)

proc checkBounds(c: AnalysisCtx; arr, idx: PNode) =
  checkLe(c, lowBound(c.graph.config, arr), idx)
  checkLe(c, idx, highBound(c.graph.config, arr, c.graph.operators))

proc addLowerBoundAsFacts(c: var AnalysisCtx) =
  for v in c.locals:
    if not v.blacklisted:
      c.guards.addFactLe(v.lower, newSymNode(v.v))

proc addSlice(c: var AnalysisCtx; n: PNode; x, le, ri: PNode) =
  checkLocal(c, n)
  let le = le.canon(c.graph.operators)
  let ri = ri.canon(c.graph.operators)
  # perform static bounds checking here; and not later!
  let oldState = c.guards.s.len
  addLowerBoundAsFacts(c)
  c.checkBounds(x, le)
  c.checkBounds(x, ri)
  c.guards.s.setLen(oldState)
  c.slices.add((x, le, ri, c.currentSpawnId, c.inLoop > 0))

proc overlap(m: TModel; conf: ConfigRef; x,y,c,d: PNode) =
  #  X..Y and C..D overlap iff (X <= D and C <= Y)
  case proveLe(m, c, y)
  of impUnknown:
    case proveLe(m, x, d)
    of impNo: discard
    of impUnknown, impYes:
      message(conf, x.info, warnStaticIndexCheck,
        "cannot prove: $# > $#; required for ($#)..($#) disjoint from ($#)..($#)" %
            [?c, ?y, ?x, ?y, ?c, ?d])
  of impYes:
    case proveLe(m, x, d)
    of impUnknown:
      message(conf, x.info, warnStaticIndexCheck,
        "cannot prove: $# > $#; required for ($#)..($#) disjoint from ($#)..($#)" %
          [?x, ?d, ?x, ?y, ?c, ?d])
    of impYes:
      message(conf, x.info, warnStaticIndexCheck, "($#)..($#) not disjoint from ($#)..($#)" %
                [?c, ?y, ?x, ?y, ?c, ?d])
    of impNo: discard
  of impNo: discard

proc stride(c: AnalysisCtx; n: PNode): BiggestInt =
  if isLocal(n):
    let s = c.lookupSlot(n.sym)
    if s >= 0 and c.locals[s].stride != nil:
      result = c.locals[s].stride.intVal
    else:
      result = 0
  else:
    result = 0
    for i in 0..<n.safeLen: result += stride(c, n[i])

proc subStride(c: AnalysisCtx; n: PNode): PNode =
  # substitute with stride:
  if isLocal(n):
    let s = c.lookupSlot(n.sym)
    if s >= 0 and c.locals[s].stride != nil:
      result = buildAdd(n, c.locals[s].stride.intVal, c.graph.operators)
    else:
      result = n
  elif n.safeLen > 0:
    result = shallowCopy(n)
    for i in 0..<n.len: result[i] = subStride(c, n[i])
  else:
    result = n

proc checkSlicesAreDisjoint(c: var AnalysisCtx) =
  # this is the only thing that we need to perform after we have traversed
  # the whole tree so that the strides are available.
  # First we need to add all the computed lower bounds:
  addLowerBoundAsFacts(c)
  # Every slice used in a loop needs to be disjoint with itself:
  for x,a,b,id,inLoop in items(c.slices):
    if inLoop: overlap(c.guards, c.graph.config, a,b, c.subStride(a), c.subStride(b))
  # Another tricky example is:
  #   while true:
  #     spawn f(a[i])
  #     spawn f(a[i+1])
  #     inc i  # inc i, 2  would be correct here
  #
  # Or even worse:
  #   while true:
  #     spawn f(a[i+1..i+3])
  #     spawn f(a[i+4..i+5])
  #     inc i, 4
  # Prove that i*k*stride + 3 != i*k'*stride + 5
  # For the correct example this amounts to
  #   i*k*2 != i*k'*2 + 1
  # which is true.
  # For now, we don't try to prove things like that at all, even though it'd
  # be feasible for many useful examples. Instead we attach the slice to
  # a spawn and if the attached spawns differ, we bail out:
  for i in 0..high(c.slices):
    for j in i+1..high(c.slices):
      let x = c.slices[i]
      let y = c.slices[j]
      if x.spawnId != y.spawnId and guards.sameTree(x.x, y.x):
        if not x.inLoop or not y.inLoop:
          # XXX strictly speaking, 'or' is not correct here and it needs to
          # be 'and'. However this prevents too many obviously correct programs
          # like f(a[0..x]); for i in x+1..a.high: f(a[i])
          overlap(c.guards, c.graph.config, x.a, x.b, y.a, y.b)
        elif (let k = simpleSlice(x.a, x.b); let m = simpleSlice(y.a, y.b);
              k >= 0 and m >= 0):
          # ah I cannot resist the temptation and add another sweet heuristic:
          # if both slices have the form (i+k)..(i+k)  and (i+m)..(i+m) we
          # check they are disjoint and k < stride and m < stride:
          overlap(c.guards, c.graph.config, x.a, x.b, y.a, y.b)
          let stride = min(c.stride(x.a), c.stride(y.a))
          if k < stride and m < stride:
            discard
          else:
            localError(c.graph.config, x.x.info, "cannot prove ($#)..($#) disjoint from ($#)..($#)" %
              [?x.a, ?x.b, ?y.a, ?y.b])
        else:
          localError(c.graph.config, x.x.info, "cannot prove ($#)..($#) disjoint from ($#)..($#)" %
            [?x.a, ?x.b, ?y.a, ?y.b])

proc analyse(c: var AnalysisCtx; n: PNode)

proc analyseSons(c: var AnalysisCtx; n: PNode) =
  for i in 0..<n.safeLen: analyse(c, n[i])

proc min(a, b: PNode): PNode =
  if a.isNil: result = b
  elif a.intVal < b.intVal: result = a
  else: result = b

template pushSpawnId(c, body) {.dirty.} =
  inc c.spawns
  let oldSpawnId = c.currentSpawnId
  c.currentSpawnId = c.spawns
  body
  c.currentSpawnId = oldSpawnId

proc analyseCall(c: var AnalysisCtx; n: PNode; op: PSym) =
  if op.magic == mSpawn:
    pushSpawnId(c):
      gatherArgs(c, n[1])
      analyseSons(c, n)
  elif op.magic == mInc or (op.name.s == "+=" and op.fromSystem):
    if n[1].isLocal:
      let incr = n[2].skipConv
      if incr.kind in {nkCharLit..nkUInt32Lit} and incr.intVal > 0:
        let slot = c.getSlot(n[1].sym)
        slot.stride = min(slot.stride, incr)
    analyseSons(c, n)
  elif op.name.s == "[]" and op.fromSystem:
    let slice = n[2].skipStmtList
    c.addSlice(n, n[1], slice[1], slice[2])
    analyseSons(c, n)
  elif op.name.s == "[]=" and op.fromSystem:
    let slice = n[2].skipStmtList
    c.addSlice(n, n[1], slice[1], slice[2])
    analyseSons(c, n)
  else:
    analyseSons(c, n)

proc analyseCase(c: var AnalysisCtx; n: PNode) =
  analyse(c, n[0])
  let oldFacts = c.guards.s.len
  for i in 1..<n.len:
    let branch = n[i]
    setLen(c.guards.s, oldFacts)
    addCaseBranchFacts(c.guards, n, i)
    for i in 0..<branch.len:
      analyse(c, branch[i])
  setLen(c.guards.s, oldFacts)

proc analyseIf(c: var AnalysisCtx; n: PNode) =
  analyse(c, n[0][0])
  let oldFacts = c.guards.s.len
  addFact(c.guards, canon(n[0][0], c.graph.operators))

  analyse(c, n[0][1])
  for i in 1..<n.len:
    let branch = n[i]
    setLen(c.guards.s, oldFacts)
    for j in 0..i-1:
      addFactNeg(c.guards, canon(n[j][0], c.graph.operators))
    if branch.len > 1:
      addFact(c.guards, canon(branch[0], c.graph.operators))
    for i in 0..<branch.len:
      analyse(c, branch[i])
  setLen(c.guards.s, oldFacts)

proc analyse(c: var AnalysisCtx; n: PNode) =
  case n.kind
  of nkAsgn, nkFastAsgn, nkSinkAsgn:
    let y = n[1].skipConv
    if n[0].isSingleAssignable and y.isLocal:
      let slot = c.getSlot(y.sym)
      slot.alias = n[0].sym
    elif n[0].isLocal:
      # since we already ensure sfAddrTaken is not in s.flags, we only need to
      # prevent direct assignments to the monotonic variable:
      let slot = c.getSlot(n[0].sym)
      slot.blacklisted = true
    invalidateFacts(c.guards, n[0])
    let value = n[1]
    if getMagic(value) == mSpawn:
      pushSpawnId(c):
        gatherArgs(c, value[1])
        analyseSons(c, value[1])
        analyse(c, n[0])
    else:
      analyseSons(c, n)
    addAsgnFact(c.guards, n[0], y)
  of nkCallKinds:
    # direct call:
    if n[0].kind == nkSym: analyseCall(c, n, n[0].sym)
    else: analyseSons(c, n)
  of nkBracketExpr:
    if n[0].typ != nil and skipTypes(n[0].typ, abstractVar).kind != tyTuple:
      c.addSlice(n, n[0], n[1], n[1])
    analyseSons(c, n)
  of nkReturnStmt, nkRaiseStmt, nkTryStmt, nkHiddenTryStmt:
    localError(c.graph.config, n.info, "invalid control flow for 'parallel'")
    # 'break' that leaves the 'parallel' section is not valid either
    # or maybe we should generate a 'try' XXX
  of nkVarSection, nkLetSection:
    for it in n:
      let value = it.lastSon
      let isSpawned = getMagic(value) == mSpawn
      if isSpawned:
        pushSpawnId(c):
          gatherArgs(c, value[1])
          analyseSons(c, value[1])
      if value.kind != nkEmpty:
        for j in 0..<it.len-2:
          if it[j].isLocal:
            let slot = c.getSlot(it[j].sym)
            if slot.lower.isNil: slot.lower = value
            else: internalError(c.graph.config, it.info, "slot already has a lower bound")
        if not isSpawned: analyse(c, value)
  of nkCaseStmt: analyseCase(c, n)
  of nkWhen, nkIfStmt, nkIfExpr: analyseIf(c, n)
  of nkWhileStmt:
    analyse(c, n[0])
    # 'while true' loop?
    inc c.inLoop
    if isTrue(n[0]):
      analyseSons(c, n[1])
    else:
      # loop may never execute:
      let oldState = c.locals.len
      let oldFacts = c.guards.s.len
      addFact(c.guards, canon(n[0], c.graph.operators))
      analyse(c, n[1])
      setLen(c.locals, oldState)
      setLen(c.guards.s, oldFacts)
      # we know after the loop the negation holds:
      if not hasSubnodeWith(n[1], nkBreakStmt):
        addFactNeg(c.guards, canon(n[0], c.graph.operators))
    dec c.inLoop
  of nkTypeSection, nkProcDef, nkConverterDef, nkMethodDef, nkIteratorDef,
      nkMacroDef, nkTemplateDef, nkConstSection, nkPragma, nkFuncDef,
      nkMixinStmt, nkBindStmt, nkExportStmt:
    discard
  else:
    analyseSons(c, n)

proc transformSlices(g: ModuleGraph; idgen: IdGenerator; n: PNode): PNode =
  if n.kind in nkCallKinds and n[0].kind == nkSym:
    let op = n[0].sym
    if op.name.s == "[]" and op.fromSystem:
      result = copyNode(n)
      var typ = newType(tyOpenArray, idgen, result.typ.owner)
      typ.add result.typ.elementType
      result.typ() = typ
      let opSlice = newSymNode(createMagic(g, idgen, "slice", mSlice))
      opSlice.typ() = getSysType(g, n.info, tyInt)
      result.add opSlice
      result.add n[1]
      let slice = n[2].skipStmtList
      result.add slice[1]
      result.add slice[2]
      return result
  if n.safeLen > 0:
    result = shallowCopy(n)
    for i in 0..<n.len:
      result[i] = transformSlices(g, idgen, n[i])
  else:
    result = n

proc transformSpawn(g: ModuleGraph; idgen: IdGenerator; owner: PSym; n, barrier: PNode): PNode
proc transformSpawnSons(g: ModuleGraph; idgen: IdGenerator; owner: PSym; n, barrier: PNode): PNode =
  result = shallowCopy(n)
  for i in 0..<n.len:
    result[i] = transformSpawn(g, idgen, owner, n[i], barrier)

proc transformSpawn(g: ModuleGraph; idgen: IdGenerator; owner: PSym; n, barrier: PNode): PNode =
  case n.kind
  of nkVarSection, nkLetSection:
    result = nil
    for it in n:
      let b = it.lastSon
      if getMagic(b) == mSpawn:
        if it.len != 3: localError(g.config, it.info, "invalid context for 'spawn'")
        let m = transformSlices(g, idgen, b)
        if result.isNil:
          result = newNodeI(nkStmtList, n.info)
          result.add n
        let t = b[1][0].typ.returnType
        if spawnResult(t, true) == srByVar:
          result.add wrapProcForSpawn(g, idgen, owner, m, b.typ, barrier, it[0])
          it[^1] = newNodeI(nkEmpty, it.info)
        else:
          it[^1] = wrapProcForSpawn(g, idgen, owner, m, b.typ, barrier, nil)
    if result.isNil: result = n
  of nkAsgn, nkFastAsgn, nkSinkAsgn:
    let b = n[1]
    if getMagic(b) == mSpawn and (let t = b[1][0].typ.returnType;
        spawnResult(t, true) == srByVar):
      let m = transformSlices(g, idgen, b)
      return wrapProcForSpawn(g, idgen, owner, m, b.typ, barrier, n[0])
    result = transformSpawnSons(g, idgen, owner, n, barrier)
  of nkCallKinds:
    if getMagic(n) == mSpawn:
      result = transformSlices(g, idgen, n)
      return wrapProcForSpawn(g, idgen, owner, result, n.typ, barrier, nil)
    result = transformSpawnSons(g, idgen, owner, n, barrier)
  elif n.safeLen > 0:
    result = transformSpawnSons(g, idgen, owner, n, barrier)
  else:
    result = n

proc checkArgs(a: var AnalysisCtx; n: PNode) =
  discard "to implement"

proc generateAliasChecks(a: AnalysisCtx; result: PNode) =
  discard "to implement"

proc liftParallel*(g: ModuleGraph; idgen: IdGenerator; owner: PSym; n: PNode): PNode =
  # this needs to be called after the 'for' loop elimination

  # first pass:
  # - detect monotonic local integer variables
  # - detect used slices
  # - detect used arguments
  #echo "PAR ", renderTree(n)

  var a = initAnalysisCtx(g)
  let body = n.lastSon
  analyse(a, body)
  if a.spawns == 0:
    localError(g.config, n.info, "'parallel' section without 'spawn'")
  checkSlicesAreDisjoint(a)
  checkArgs(a, body)

  var varSection = newNodeI(nkVarSection, n.info)
  var temp = newSym(skTemp, getIdent(g.cache, "barrier"), idgen, owner, n.info)
  temp.typ = magicsys.getCompilerProc(g, "Barrier").typ
  incl(temp.flags, sfFromGeneric)
  let tempNode = newSymNode(temp)
  varSection.addVar tempNode

  let barrier = genAddrOf(tempNode, idgen)
  result = newNodeI(nkStmtList, n.info)
  generateAliasChecks(a, result)
  result.add varSection
  result.add callCodegenProc(g, "openBarrier", barrier.info, barrier)
  result.add transformSpawn(g, idgen, owner, body, barrier)
  result.add callCodegenProc(g, "closeBarrier", barrier.info, barrier)

#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import
  ast, astalgo, msgs, renderer, magicsys, types, idents, trees,
  wordrecg, options, guards, lineinfos, semfold, semdata,
  modulegraphs, varpartitions, typeallowed, nilcheck, errorhandling,
  semstrictfuncs, suggestsymdb, pushpoppragmas

import std/[tables, intsets, strutils, sequtils]

when defined(nimPreviewSlimSystem):
  import std/assertions

when defined(useDfa):
  import dfa

import liftdestructors
include sinkparameter_inference

#[ Second semantic checking pass over the AST. Necessary because the old
   way had some inherent problems. Performs:

* effect+exception tracking
* "usage before definition" checking
* also now calls the "lift destructor logic" at strategic positions, this
  is about to be put into the spec:

We treat assignment and sinks and destruction as identical.

In the construct let/var x = expr() x's type is marked.

In x = y the type of x is marked.

For every sink parameter of type T T is marked.

For every call f() the return type of f() is marked.

]#

# ------------------------ exception and tag tracking -------------------------

discard """
  exception tracking:

  a() # raises 'x', 'e'
  try:
    b() # raises 'e'
  except e:
    # must not undo 'e' here; hrm
    c()

 --> we need a stack of scopes for this analysis

  # XXX enhance the algorithm to care about 'dirty' expressions:
  lock a[i].L:
    inc i # mark 'i' dirty
    lock a[j].L:
      access a[i], a[j]  # --> reject a[i]
"""

type
  CaughtExceptionsStack = object
    nodes: seq[seq[PType]]
  TEffects = object
    exc: PNode  # stack of exceptions
    when defined(nimsuggest):
      caughtExceptions: CaughtExceptionsStack
    tags: PNode # list of tags
    forbids: PNode # list of tags
    bottom, inTryStmt, inExceptOrFinallyStmt, leftPartOfAsgn, inIfStmt, currentBlock: int
    owner: PSym
    ownerModule: PSym
    init: seq[int] # list of initialized variables
    scopes: Table[int, int] # maps var-id to its scope (see also `currentBlock`).
    guards: TModel # nested guards
    locked: seq[PNode] # locked locations
    gcUnsafe, isRecursive, isTopLevel, hasSideEffect, inEnforcedGcSafe: bool
    isInnerProc: bool
    inEnforcedNoSideEffects: bool
    currOptions: TOptions
    optionsStack: seq[(TOptions, TNoteKinds)]
    config: ConfigRef
    graph: ModuleGraph
    c: PContext
    escapingParams: IntSet
  PEffects = var TEffects

const
  errXCannotBeAssignedTo = "'$1' cannot be assigned to"
  errLetNeedsInit = "'let' symbol requires an initialization"

proc getObjDepth(t: PType): (int, ItemId) =
  var x = t
  result = (-1, default(ItemId))
  var stack = newSeq[ItemId]()
  while x != nil:
    x = skipTypes(x, skipPtrs)
    if x.kind != tyObject:
      return (-3, default(ItemId))
    stack.add x.itemId
    x = x.baseClass
    inc(result[0])
  result[1] = stack[^2]

proc collectObjectTree(graph: ModuleGraph, n: PNode) =
  for section in n:
    if section.kind == nkTypeDef and section[^1].kind in {nkObjectTy, nkRefTy, nkPtrTy} and section[^1].typ != nil:
      let typ = section[^1].typ.skipTypes(skipPtrs)
      if typ.kind == tyObject and typ.baseClass != nil:
        let (depthLevel, root) = getObjDepth(typ)
        if depthLevel != -3:
          if depthLevel == 1:
            graph.objectTree[root] = @[]
          else:
            if root notin graph.objectTree:
              graph.objectTree[root] = @[(depthLevel, typ)]
            else:
              graph.objectTree[root].add (depthLevel, typ)

proc createTypeBoundOps(tracked: PEffects, typ: PType; info: TLineInfo) =
  if typ == nil or sfGeneratedOp in tracked.owner.flags:
    # don't create type bound ops for anything in a function with a `nodestroy` pragma
    # bug #21987
    return
  when false:
    let realType = typ.skipTypes(abstractInst)
    if realType.kind == tyRef and
        optSeqDestructors in tracked.config.globalOptions:
      createTypeBoundOps(tracked.graph, tracked.c, realType.lastSon, info)

  createTypeBoundOps(tracked.graph, tracked.c, typ, info, tracked.c.idgen)
  if (tfHasAsgn in typ.flags) or
      optSeqDestructors in tracked.config.globalOptions:
    tracked.owner.flags.incl sfInjectDestructors

proc isLocalSym(a: PEffects, s: PSym): bool =
  s.typ != nil and (s.kind in {skLet, skVar, skResult} or (s.kind == skParam and isOutParam(s.typ))) and
    sfGlobal notin s.flags and s.owner == a.owner

proc lockLocations(a: PEffects; pragma: PNode) =
  if pragma.kind != nkExprColonExpr:
    localError(a.config, pragma.info, "locks pragma without argument")
    return
  for x in pragma[1]:
    a.locked.add x

proc guardGlobal(a: PEffects; n: PNode; guard: PSym) =
  # check whether the corresponding lock is held:
  for L in a.locked:
    if L.kind == nkSym and L.sym == guard: return
  # we allow accesses nevertheless in top level statements for
  # easier initialization:
  #if a.isTopLevel:
  #  message(a.config, n.info, warnUnguardedAccess, renderTree(n))
  #else:
  if not a.isTopLevel:
    localError(a.config, n.info, "unguarded access: " & renderTree(n))

# 'guard*' are checks which are concerned with 'guard' annotations
# (var x{.guard: y.}: int)
proc guardDotAccess(a: PEffects; n: PNode) =
  let ri = n[1]
  if ri.kind != nkSym or ri.sym.kind != skField: return
  var g = ri.sym.guard
  if g.isNil or a.isTopLevel: return
  # fixup guard:
  if g.kind == skUnknown:
    var field: PSym = nil
    var ty = n[0].typ.skipTypes(abstractPtrs)
    if ty.kind == tyTuple and not ty.n.isNil:
      field = lookupInRecord(ty.n, g.name)
    else:
      while ty != nil and ty.kind == tyObject:
        field = lookupInRecord(ty.n, g.name)
        if field != nil: break
        ty = ty[0]
        if ty == nil: break
        ty = ty.skipTypes(skipPtrs)
    if field == nil:
      localError(a.config, n.info, "invalid guard field: " & g.name.s)
      return
    g = field
    #ri.sym.guard = field
    # XXX unfortunately this is not correct for generic instantiations!
  if g.kind == skField:
    let dot = newNodeI(nkDotExpr, n.info, 2)
    dot[0] = n[0]
    dot[1] = newSymNode(g)
    dot.typ() = g.typ
    for L in a.locked:
      #if a.guards.sameSubexprs(dot, L): return
      if guards.sameTree(dot, L): return
    localError(a.config, n.info, "unguarded access: " & renderTree(n))
  else:
    guardGlobal(a, n, g)

proc makeVolatile(a: PEffects; s: PSym) {.inline.} =
  if a.inTryStmt > 0 and a.config.exc == excSetjmp:
    incl(s.flags, sfVolatile)

proc varDecl(a: PEffects; n: PNode) {.inline.} =
  if n.kind == nkSym:
    a.scopes[n.sym.id] = a.currentBlock

proc skipHiddenDeref(n: PNode): PNode {.inline.} =
  result = if n.kind == nkHiddenDeref: n[0] else: n


proc initVar(a: PEffects, n: PNode; volatileCheck: bool) =
  let n = skipHiddenDeref(n)
  if n.kind != nkSym: return
  let s = n.sym
  if isLocalSym(a, s):
    if volatileCheck: makeVolatile(a, s)
    for x in a.init:
      if x == s.id:
        if noStrictDefs notin a.c.config.legacyFeatures and s.kind == skLet:
          localError(a.config, n.info, errXCannotBeAssignedTo %
                    renderTree(n, {renderNoComments}
                ))
        return
    a.init.add s.id
    if a.scopes.getOrDefault(s.id) == a.currentBlock:
      #[ Consider this case:

      var x: T
      while true:
        if cond:
          x = T() #1
        else:
          x = T() #2
        use x

      Even though both #1 and #2 are first writes we must use the `=copy`
      here so that the old value is destroyed because `x`'s destructor is
      run outside of the while loop. This is why we need the check here that
      the assignment is done in the same logical block as `x` was declared in.
      ]#
      n.flags.incl nfFirstWrite

proc initVarViaNew(a: PEffects, n: PNode) =
  let n = skipHiddenDeref(n)
  if n.kind != nkSym: return
  let s = n.sym
  if {tfRequiresInit, tfNotNil} * s.typ.flags <= {tfNotNil}:
    # 'x' is not nil, but that doesn't mean its "not nil" children
    # are initialized:
    initVar(a, n, volatileCheck=true)
  elif isLocalSym(a, s):
    makeVolatile(a, s)

proc warnAboutGcUnsafe(n: PNode; conf: ConfigRef) =
  #assert false
  message(conf, n.info, warnGcUnsafe, renderTree(n))

proc markGcUnsafe(a: PEffects; reason: PSym) =
  if not a.inEnforcedGcSafe:
    a.gcUnsafe = true
    if a.owner.kind in routineKinds: a.owner.gcUnsafetyReason = reason

proc markGcUnsafe(a: PEffects; reason: PNode) =
  if not a.inEnforcedGcSafe:
    a.gcUnsafe = true
    if a.owner.kind in routineKinds:
      if reason.kind == nkSym:
        a.owner.gcUnsafetyReason = reason.sym
      else:
        a.owner.gcUnsafetyReason = newSym(skUnknown, a.owner.name, a.c.idgen,
                                          a.owner, reason.info, {})

proc markSideEffect(a: PEffects; reason: PNode | PSym; useLoc: TLineInfo) =
  if not a.inEnforcedNoSideEffects:
    a.hasSideEffect = true
    if a.owner.kind in routineKinds:
      var sym: PSym
      when reason is PNode:
        if reason.kind == nkSym:
          sym = reason.sym
        else:
          let kind = if reason.kind == nkHiddenDeref: skParam else: skUnknown
          sym = newSym(kind, a.owner.name, a.c.idgen, a.owner, reason.info, {})
      else:
        sym = reason
      a.c.sideEffects.mgetOrPut(a.owner.id, @[]).add (useLoc, sym)
    when false: markGcUnsafe(a, reason)

proc listGcUnsafety(s: PSym; onlyWarning: bool; cycleCheck: var IntSet; conf: ConfigRef) =
  let u = s.gcUnsafetyReason
  if u != nil and not cycleCheck.containsOrIncl(u.id):
    let msgKind = if onlyWarning: warnGcUnsafe2 else: errGenerated
    case u.kind
    of skLet, skVar:
      if u.typ.skipTypes(abstractInst).kind == tyProc:
        message(conf, s.info, msgKind,
          "'$#' is not GC-safe as it calls '$#'" %
          [s.name.s, u.name.s])
      else:
        message(conf, s.info, msgKind,
          ("'$#' is not GC-safe as it accesses '$#'" &
          " which is a global using GC'ed memory") % [s.name.s, u.name.s])
    of routineKinds:
      # recursive call *always* produces only a warning so the full error
      # message is printed:
      if u.kind == skMethod and {sfBase, sfThread} * u.flags == {sfBase}:
        message(conf, u.info, msgKind,
          "Base method '$#' requires explicit '{.gcsafe.}' to be GC-safe" %
          [u.name.s])
      else:
        listGcUnsafety(u, true, cycleCheck, conf)
        message(conf, s.info, msgKind,
          "'$#' is not GC-safe as it calls '$#'" %
          [s.name.s, u.name.s])
    of skParam, skForVar:
      message(conf, s.info, msgKind,
        "'$#' is not GC-safe as it performs an indirect call via '$#'" %
        [s.name.s, u.name.s])
    else:
      message(conf, u.info, msgKind,
        "'$#' is not GC-safe as it performs an indirect call here" % s.name.s)

proc listGcUnsafety(s: PSym; onlyWarning: bool; conf: ConfigRef) =
  var cycleCheck = initIntSet()
  listGcUnsafety(s, onlyWarning, cycleCheck, conf)

proc listSideEffects(result: var string; s: PSym; cycleCheck: var IntSet;
                     conf: ConfigRef; context: PContext; indentLevel: int) =
  template addHint(msg; lineInfo; sym; level = indentLevel) =
    result.addf("$# $# Hint: '$#' $#\n", repeat(">", level), conf $ lineInfo, sym, msg)
  if context.sideEffects.hasKey(s.id):
    for (useLineInfo, u) in context.sideEffects[s.id]:
      if u != nil and not cycleCheck.containsOrIncl(u.id):
        case u.kind
        of skLet, skVar:
          addHint("accesses global state '$#'" % u.name.s, useLineInfo, s.name.s)
          addHint("accessed by '$#'" % s.name.s, u.info, u.name.s, indentLevel + 1)
        of routineKinds:
          addHint("calls `.sideEffect` '$#'" % u.name.s, useLineInfo, s.name.s)
          addHint("called by '$#'" % s.name.s, u.info, u.name.s, indentLevel + 1)
          listSideEffects(result, u, cycleCheck, conf, context, indentLevel + 2)
        of skParam, skForVar:
          addHint("calls routine via hidden pointer indirection", useLineInfo, s.name.s)
        else:
          addHint("calls routine via pointer indirection", useLineInfo, s.name.s)

proc listSideEffects(result: var string; s: PSym; conf: ConfigRef; context: PContext) =
  var cycleCheck = initIntSet()
  result.addf("'$#' can have side effects\n", s.name.s)
  listSideEffects(result, s, cycleCheck, conf, context, 1)

proc useVarNoInitCheck(a: PEffects; n: PNode; s: PSym) =
  if {sfGlobal, sfThread} * s.flags != {} and s.kind in {skVar, skLet} and
      s.magic != mNimvm:
    if s.guard != nil: guardGlobal(a, n, s.guard)
    if {sfGlobal, sfThread} * s.flags == {sfGlobal} and
        (tfHasGCedMem in s.typ.flags or s.typ.isGCedMem):
      #if a.config.hasWarn(warnGcUnsafe): warnAboutGcUnsafe(n)
      markGcUnsafe(a, s)
    markSideEffect(a, s, n.info)
  if s.owner != a.owner and s.kind in {skVar, skLet, skForVar, skResult, skParam} and
     {sfGlobal, sfThread} * s.flags == {}:
    a.isInnerProc = true

proc useVar(a: PEffects, n: PNode) =
  let s = n.sym
  if a.inExceptOrFinallyStmt > 0:
    incl s.flags, sfUsedInFinallyOrExcept
  if isLocalSym(a, s):
    if sfNoInit in s.flags:
      # If the variable is explicitly marked as .noinit. do not emit any error
      a.init.add s.id
    elif s.id notin a.init:
      if s.typ.requiresInit:
        message(a.config, n.info, warnProveInit, s.name.s)
      elif a.leftPartOfAsgn <= 0:
        if noStrictDefs notin a.c.config.legacyFeatures:
          if s.kind == skLet:
            localError(a.config, n.info, errLetNeedsInit)
          else:
            message(a.config, n.info, warnUninit, s.name.s)
      # prevent superfluous warnings about the same variable:
      a.init.add s.id
  useVarNoInitCheck(a, n, s)

type
  BreakState = enum
    bsNone
    bsBreakOrReturn
    bsNoReturn

type
  TIntersection = seq[tuple[id, count: int]] # a simple count table

proc addToIntersection(inter: var TIntersection, s: int, state: BreakState) =
  for j in 0..<inter.len:
    if s == inter[j].id:
      if state == bsNone:
        inc inter[j].count
      return
  if state == bsNone:
    inter.add((id: s, count: 1))
  else:
    inter.add((id: s, count: 0))

proc throws(tracked, n, orig: PNode) =
  if n.typ == nil or n.typ.kind != tyError:
    if orig != nil:
      let x = copyTree(orig)
      x.typ() = n.typ
      tracked.add x
    else:
      tracked.add n

proc getEbase*(g: ModuleGraph; info: TLineInfo): PType =
  result = g.sysTypeFromName(info, "Exception")

proc excType(g: ModuleGraph; n: PNode): PType =
  # reraise is like raising E_Base:
  let t = if n.kind == nkEmpty or n.typ.isNil: getEbase(g, n.info) else: n.typ
  result = skipTypes(t, skipPtrs)

proc createRaise(g: ModuleGraph; n: PNode): PNode =
  result = newNode(nkType)
  result.typ() = getEbase(g, n.info)
  if not n.isNil: result.info = n.info

proc createTag(g: ModuleGraph; n: PNode): PNode =
  result = newNode(nkType)
  result.typ() = g.sysTypeFromName(n.info, "RootEffect")
  if not n.isNil: result.info = n.info

proc addRaiseEffect(a: PEffects, e, comesFrom: PNode) =
  #assert e.kind != nkRaiseStmt
  var aa = a.exc
  for i in a.bottom..<aa.len:
    # we only track the first node that can have the effect E in order
    # to safe space and time.
    if sameType(a.graph.excType(aa[i]), a.graph.excType(e)): return

  if e.typ != nil:
    if not isDefectException(e.typ):
      throws(a.exc, e, comesFrom)

proc addTag(a: PEffects, e, comesFrom: PNode) =
  var aa = a.tags
  for i in 0..<aa.len:
    # we only track the first node that can have the effect E in order
    # to safe space and time.
    if sameType(aa[i].typ.skipTypes(skipPtrs), e.typ.skipTypes(skipPtrs)): return
  throws(a.tags, e, comesFrom)

proc addNotTag(a: PEffects, e, comesFrom: PNode) =
  var aa = a.forbids
  for i in 0..<aa.len:
    if sameType(aa[i].typ.skipTypes(skipPtrs), e.typ.skipTypes(skipPtrs)): return
  throws(a.forbids, e, comesFrom)

proc mergeRaises(a: PEffects, b, comesFrom: PNode) =
  if b.isNil:
    addRaiseEffect(a, createRaise(a.graph, comesFrom), comesFrom)
  else:
    for effect in items(b): addRaiseEffect(a, effect, comesFrom)

proc mergeTags(a: PEffects, b, comesFrom: PNode) =
  if b.isNil:
    addTag(a, createTag(a.graph, comesFrom), comesFrom)
  else:
    for effect in items(b): addTag(a, effect, comesFrom)

proc listEffects(a: PEffects) =
  for e in items(a.exc):  message(a.config, e.info, hintUser, typeToString(e.typ))
  for e in items(a.tags): message(a.config, e.info, hintUser, typeToString(e.typ))
  for e in items(a.forbids): message(a.config, e.info, hintUser, typeToString(e.typ))

proc catches(tracked: PEffects, e: PType) =
  let e = skipTypes(e, skipPtrs)
  var L = tracked.exc.len
  var i = tracked.bottom
  while i < L:
    # r supertype of e?
    if safeInheritanceDiff(tracked.graph.excType(tracked.exc[i]), e) <= 0:
      tracked.exc[i] = tracked.exc[L-1]
      dec L
    else:
      inc i
  if tracked.exc.len > 0:
    setLen(tracked.exc.sons, L)
  else:
    assert L == 0

proc catchesAll(tracked: PEffects) =
  if tracked.exc.len > 0:
    setLen(tracked.exc.sons, tracked.bottom)

proc push(s: var CaughtExceptionsStack) =
  s.nodes.add(@[])

proc pop(s: var CaughtExceptionsStack) =
  s.nodes.del(high(s.nodes))

proc addCatch(s: var CaughtExceptionsStack, e: PType) =
  s.nodes[high(s.nodes)].add(e)

proc addCatchAll(s: var CaughtExceptionsStack) =
  s.nodes[high(s.nodes)].add(nil)

proc track(tracked: PEffects, n: PNode)
proc trackTryStmt(tracked: PEffects, n: PNode) =
  let oldBottom = tracked.bottom
  tracked.bottom = tracked.exc.len

  let oldState = tracked.init.len
  var inter: TIntersection = @[]

  when defined(nimsuggest):
    tracked.caughtExceptions.push
    for i in 1..<n.len:
      let b = n[i]
      if b.kind == nkExceptBranch:
        if b.len == 1:
          tracked.caughtExceptions.addCatchAll
        else:
          for j in 0..<b.len - 1:
            if b[j].isInfixAs():
              assert(b[j][1].kind == nkType)
              tracked.caughtExceptions.addCatch(b[j][1].typ)
            else:
              assert(b[j].kind == nkType)
              tracked.caughtExceptions.addCatch(b[j].typ)
      else:
        assert b.kind == nkFinally

  inc tracked.inTryStmt
  track(tracked, n[0])
  dec tracked.inTryStmt
  for i in oldState..<tracked.init.len:
    addToIntersection(inter, tracked.init[i], bsNone)

  when defined(nimsuggest):
    tracked.caughtExceptions.pop

  var branches = 1
  var hasFinally = false
  inc tracked.inExceptOrFinallyStmt

  # Collect the exceptions caught by the except branches
  for i in 1..<n.len:
    let b = n[i]
    if b.kind == nkExceptBranch:
      inc branches
      if b.len == 1:
        catchesAll(tracked)
      else:
        for j in 0..<b.len - 1:
          if b[j].isInfixAs():
            assert(b[j][1].kind == nkType)
            catches(tracked, b[j][1].typ)
            createTypeBoundOps(tracked, b[j][2].typ, b[j][2].info)
          else:
            assert(b[j].kind == nkType)
            catches(tracked, b[j].typ)
    else:
      assert b.kind == nkFinally
  # Add any other exception raised in the except bodies
  for i in 1..<n.len:
    let b = n[i]
    if b.kind == nkExceptBranch:
      setLen(tracked.init, oldState)
      for j in 0..<b.len - 1:
        if b[j].isInfixAs(): # skips initialization checks
          assert(b[j][2].kind == nkSym)
          tracked.init.add b[j][2].sym.id
      track(tracked, b[^1])
      for i in oldState..<tracked.init.len:
        addToIntersection(inter, tracked.init[i], bsNone)
    else:
      setLen(tracked.init, oldState)
      track(tracked, b[^1])
      hasFinally = true

  tracked.bottom = oldBottom
  dec tracked.inExceptOrFinallyStmt
  if not hasFinally:
    setLen(tracked.init, oldState)
  for id, count in items(inter):
    if count == branches: tracked.init.add id

proc isIndirectCall(tracked: PEffects; n: PNode): bool =
  # we don't count f(...) as an indirect call if 'f' is an parameter.
  # Instead we track expressions of type tyProc too. See the manual for
  # details:
  if n.kind != nkSym:
    result = true
  elif n.sym.kind == skParam:
    if laxEffects notin tracked.c.config.legacyFeatures:
      if tracked.owner == n.sym.owner and sfEffectsDelayed in n.sym.flags:
        result = false # it is not a harmful call
      else:
        result = true
    else:
      result = tracked.owner != n.sym.owner or tracked.owner == nil
  elif n.sym.kind notin routineKinds:
    result = true
  else:
    result = false

proc isForwardedProc(n: PNode): bool =
  result = n.kind == nkSym and sfForward in n.sym.flags

proc trackPragmaStmt(tracked: PEffects, n: PNode) =
  for i in 0..<n.len:
    var it = n[i]
    let pragma = whichPragma(it)
    case pragma
    of wEffects:
      # list the computed effects up to here:
      listEffects(tracked)
    of wPush:
      processPushBackendOption(tracked.c.config, tracked.optionsStack, tracked.currOptions, n, i+1)
    of wPop:
      processPopBackendOption(tracked.c.config, tracked.optionsStack, tracked.currOptions)
    else:
      discard

template notGcSafe(t): untyped = {tfGcSafe, tfNoSideEffect} * t.flags == {}

proc importedFromC(n: PNode): bool =
  # when imported from C, we assume GC-safety.
  result = n.kind == nkSym and sfImportc in n.sym.flags

proc propagateEffects(tracked: PEffects, n: PNode, s: PSym) =
  let pragma = s.ast[pragmasPos]
  let spec = effectSpec(pragma, wRaises)
  mergeRaises(tracked, spec, n)

  let tagSpec = effectSpec(pragma, wTags)
  mergeTags(tracked, tagSpec, n)

  if notGcSafe(s.typ) and sfImportc notin s.flags:
    if tracked.config.hasWarn(warnGcUnsafe): warnAboutGcUnsafe(n, tracked.config)
    markGcUnsafe(tracked, s)
  if tfNoSideEffect notin s.typ.flags:
    markSideEffect(tracked, s, n.info)

proc procVarCheck(n: PNode; conf: ConfigRef) =
  if n.kind in nkSymChoices:
    for x in n: procVarCheck(x, conf)
  elif n.kind == nkSym and n.sym.magic != mNone and n.sym.kind in routineKinds:
    localError(conf, n.info, ("'$1' is a built-in and cannot be used as " &
      "a first-class procedure") % n.sym.name.s)

proc notNilCheck(tracked: PEffects, n: PNode, paramType: PType) =
  let n = n.skipConv
  if paramType.isNil or paramType.kind != tyTypeDesc:
    procVarCheck skipConvCastAndClosure(n), tracked.config
  #elif n.kind in nkSymChoices:
  #  echo "came here"
  let paramType = paramType.skipTypesOrNil(abstractInst)
  if paramType != nil and tfNotNil in paramType.flags and n.typ != nil:
    let ntyp = n.typ.skipTypesOrNil({tyVar, tyLent, tySink})
    if ntyp != nil and tfNotNil notin ntyp.flags:
      if n.kind in {nkAddr, nkHiddenAddr}:
        # addr(x[]) can't be proven, but addr(x) can:
        if not containsNode(n, {nkDerefExpr, nkHiddenDeref}): return
      elif (n.kind == nkSym and n.sym.kind in routineKinds) or
          (n.kind in procDefs+{nkObjConstr, nkBracket, nkClosure, nkStrLit..nkTripleStrLit}) or
          (n.kind in nkCallKinds and n[0].kind == nkSym and n[0].sym.magic == mArrToSeq) or
          n.typ.kind == tyTypeDesc:
        # 'p' is not nil obviously:
        return
      case impliesNotNil(tracked.guards, n)
      of impUnknown:
        message(tracked.config, n.info, errGenerated,
                "cannot prove '$1' is not nil" % n.renderTree)
      of impNo:
        message(tracked.config, n.info, errGenerated,
                "'$1' is provably nil" % n.renderTree)
      of impYes: discard

proc assumeTheWorst(tracked: PEffects; n: PNode; op: PType) =
  addRaiseEffect(tracked, createRaise(tracked.graph, n), nil)
  addTag(tracked, createTag(tracked.graph, n), nil)

proc isOwnedProcVar(tracked: PEffects; n: PNode): bool =
  # XXX prove the soundness of this effect system rule
  result = n.kind == nkSym and n.sym.kind == skParam and
    tracked.owner == n.sym.owner
  #if result and sfPolymorphic notin n.sym.flags:
  #  echo tracked.config $ n.info, " different here!"
  if laxEffects notin tracked.c.config.legacyFeatures:
    result = result and sfEffectsDelayed in n.sym.flags

proc isNoEffectList(n: PNode): bool {.inline.} =
  assert n.kind == nkEffectList
  n.len == 0 or (n[tagEffects] == nil and n[exceptionEffects] == nil and n[forbiddenEffects] == nil)

proc isTrival(caller: PNode): bool {.inline.} =
  result = caller.kind == nkSym and caller.sym.magic in {mEqProc, mIsNil, mMove, mWasMoved, mSwap}

proc trackOperandForIndirectCall(tracked: PEffects, n: PNode, formals: PType; argIndex: int; caller: PNode) =
  let a = skipConvCastAndClosure(n)
  let op = a.typ
  let param = if formals != nil and formals.n != nil and argIndex < formals.n.len: formals.n[argIndex].sym else: nil
  # assume indirect calls are taken here:
  if op != nil and op.kind == tyProc and n.skipConv.kind != nkNilLit and
      not isTrival(caller) and
      ((param != nil and sfEffectsDelayed in param.flags) or laxEffects in tracked.c.config.legacyFeatures):

    internalAssert tracked.config, op.n[0].kind == nkEffectList
    var effectList = op.n[0]
    var s = n.skipConv
    if s.kind == nkCast and s[1].typ.kind == tyProc:
      s = s[1]
    if s.kind == nkSym and s.sym.kind in routineKinds and isNoEffectList(effectList):
      propagateEffects(tracked, n, s.sym)
    elif isNoEffectList(effectList):
      if isForwardedProc(n):
        # we have no explicit effects but it's a forward declaration and so it's
        # stated there are no additional effects, so simply propagate them:
        propagateEffects(tracked, n, n.sym)
      elif not isOwnedProcVar(tracked, a):
        # we have no explicit effects so assume the worst:
        assumeTheWorst(tracked, n, op)
      # assume GcUnsafe unless in its type; 'forward' does not matter:
      if notGcSafe(op) and not isOwnedProcVar(tracked, a):
        if tracked.config.hasWarn(warnGcUnsafe): warnAboutGcUnsafe(n, tracked.config)
        markGcUnsafe(tracked, a)
      elif tfNoSideEffect notin op.flags and not isOwnedProcVar(tracked, a):
        markSideEffect(tracked, a, n.info)
    else:
      mergeRaises(tracked, effectList[exceptionEffects], n)
      mergeTags(tracked, effectList[tagEffects], n)
      if notGcSafe(op):
        if tracked.config.hasWarn(warnGcUnsafe): warnAboutGcUnsafe(n, tracked.config)
        markGcUnsafe(tracked, a)
      elif tfNoSideEffect notin op.flags:
        markSideEffect(tracked, a, n.info)
  let paramType = if formals != nil and argIndex < formals.signatureLen: formals[argIndex] else: nil
  if paramType != nil and paramType.kind in {tyVar}:
    invalidateFacts(tracked.guards, n)
    if n.kind == nkSym and isLocalSym(tracked, n.sym):
      makeVolatile(tracked, n.sym)
  if paramType != nil and paramType.kind == tyProc and tfGcSafe in paramType.flags:
    let argtype = skipTypes(a.typ, abstractInst)
    # XXX figure out why this can be a non tyProc here. See httpclient.nim for an
    # example that triggers it.
    if argtype.kind == tyProc and notGcSafe(argtype) and not tracked.inEnforcedGcSafe:
      localError(tracked.config, n.info, $n & " is not GC safe")
  notNilCheck(tracked, n, paramType)


proc breaksBlock(n: PNode): BreakState =
  # semantic check doesn't allow statements after raise, break, return or
  # call to noreturn proc, so it is safe to check just the last statements
  var it = n
  while it.kind in {nkStmtList, nkStmtListExpr} and it.len > 0:
    it = it.lastSon

  case it.kind
  of nkBreakStmt, nkReturnStmt:
    result = bsBreakOrReturn
  of nkRaiseStmt:
    result = bsNoReturn
  of nkCallKinds:
    if it[0].kind == nkSym and sfNoReturn in it[0].sym.flags:
      result = bsNoReturn
    else:
      result = bsNone
  else:
    result = bsNone

proc addIdToIntersection(tracked: PEffects, inter: var TIntersection, resCounter: var int,
            hasBreaksBlock: BreakState, oldState: int, resSym: PSym, hasResult: bool) =
  if hasResult:
    var alreadySatisfy = false

    if hasBreaksBlock == bsNoReturn:
      alreadySatisfy = true
      inc resCounter

    for i in oldState..<tracked.init.len:
      if tracked.init[i] == resSym.id:
        if not alreadySatisfy:
          inc resCounter
          alreadySatisfy = true
      else:
        addToIntersection(inter, tracked.init[i], hasBreaksBlock)
  else:
    for i in oldState..<tracked.init.len:
      addToIntersection(inter, tracked.init[i], hasBreaksBlock)

template hasResultSym(s: PSym): bool =
  s != nil and s.kind in {skProc, skFunc, skConverter, skMethod} and
    not isEmptyType(s.typ.returnType)

proc trackCase(tracked: PEffects, n: PNode) =
  track(tracked, n[0])
  inc tracked.inIfStmt
  let oldState = tracked.init.len
  let oldFacts = tracked.guards.s.len
  let stringCase = n[0].typ != nil and skipTypes(n[0].typ,
        abstractVarRange-{tyTypeDesc}).kind in {tyFloat..tyFloat128, tyString, tyCstring}
  let interesting = not stringCase and interestingCaseExpr(n[0]) and
        (tracked.config.hasWarn(warnProveField) or strictCaseObjects in tracked.c.features)
  var inter: TIntersection = @[]
  var toCover = 0
  let hasResult = hasResultSym(tracked.owner)
  let resSym = if hasResult: tracked.owner.ast[resultPos].sym else: nil
  var resCounter = 0

  for i in 1..<n.len:
    let branch = n[i]
    setLen(tracked.init, oldState)
    if interesting:
      setLen(tracked.guards.s, oldFacts)
      addCaseBranchFacts(tracked.guards, n, i)
    for i in 0..<branch.len:
      track(tracked, branch[i])
    let hasBreaksBlock = breaksBlock(branch.lastSon)
    if hasBreaksBlock == bsNone:
      inc toCover
    addIdToIntersection(tracked, inter, resCounter, hasBreaksBlock, oldState, resSym, hasResult)

  setLen(tracked.init, oldState)
  if not stringCase or lastSon(n).kind == nkElse:
    if hasResult and resCounter == n.len-1:
        tracked.init.add resSym.id
    for id, count in items(inter):
      if count >= toCover: tracked.init.add id
    # else we can't merge
  setLen(tracked.guards.s, oldFacts)
  dec tracked.inIfStmt

proc trackIf(tracked: PEffects, n: PNode) =
  track(tracked, n[0][0])
  inc tracked.inIfStmt
  let oldFacts = tracked.guards.s.len
  addFact(tracked.guards, n[0][0])
  let oldState = tracked.init.len

  let hasResult = hasResultSym(tracked.owner)
  let resSym = if hasResult: tracked.owner.ast[resultPos].sym else: nil
  var resCounter = 0

  var inter: TIntersection = @[]
  var toCover = 0
  track(tracked, n[0][1])
  let hasBreaksBlock = breaksBlock(n[0][1])
  if hasBreaksBlock == bsNone:
    inc toCover
  addIdToIntersection(tracked, inter, resCounter, hasBreaksBlock, oldState, resSym, hasResult)

  for i in 1..<n.len:
    let branch = n[i]
    setLen(tracked.guards.s, oldFacts)
    for j in 0..i-1:
      addFactNeg(tracked.guards, n[j][0])
    if branch.len > 1:
      addFact(tracked.guards, branch[0])
    setLen(tracked.init, oldState)
    for i in 0..<branch.len:
      track(tracked, branch[i])
    let hasBreaksBlock = breaksBlock(branch.lastSon)
    if hasBreaksBlock == bsNone:
      inc toCover
    addIdToIntersection(tracked, inter, resCounter, hasBreaksBlock, oldState, resSym, hasResult)

  setLen(tracked.init, oldState)
  if lastSon(n).len == 1:
    if hasResult and resCounter == n.len:
        tracked.init.add resSym.id
    for id, count in items(inter):
      if count >= toCover: tracked.init.add id
    # else we can't merge as it is not exhaustive
  setLen(tracked.guards.s, oldFacts)
  dec tracked.inIfStmt

proc trackBlock(tracked: PEffects, n: PNode) =
  if n.kind in {nkStmtList, nkStmtListExpr}:
    var oldState = -1
    for i in 0..<n.len:
      if hasSubnodeWith(n[i], nkBreakStmt):
        # block:
        #   x = def
        #   if ...: ... break # some nested break
        #   y = def
        # --> 'y' not defined after block!
        if oldState < 0: oldState = tracked.init.len
      track(tracked, n[i])
    if oldState > 0: setLen(tracked.init, oldState)
  else:
    track(tracked, n)

proc cstringCheck(tracked: PEffects; n: PNode) =
  if n[0].typ.kind == tyCstring and (let a = skipConv(n[1]);
      a.typ.kind == tyString and a.kind notin {nkStrLit..nkTripleStrLit}):
    message(tracked.config, n.info, warnUnsafeCode, renderTree(n))

proc patchResult(c: PEffects; n: PNode) =
  if n.kind == nkSym and n.sym.kind == skResult:
    let fn = c.owner
    if fn != nil and fn.kind in routineKinds and fn.ast != nil and resultPos < fn.ast.len:
      n.sym = fn.ast[resultPos].sym
    else:
      localError(c.config, n.info, "routine has no return type, but .requires contains 'result'")
  else:
    for i in 0..<safeLen(n):
      patchResult(c, n[i])

proc checkLe(c: PEffects; a, b: PNode) =
  case proveLe(c.guards, a, b)
  of impUnknown:
    #for g in c.guards.s:
    #  if g != nil: echo "I Know ", g
    message(c.config, a.info, warnStaticIndexCheck,
      "cannot prove: " & $a & " <= " & $b)
  of impYes:
    discard
  of impNo:
    message(c.config, a.info, warnStaticIndexCheck,
      "can prove: " & $a & " > " & $b)

proc checkBounds(c: PEffects; arr, idx: PNode) =
  checkLe(c, lowBound(c.config, arr), idx)
  checkLe(c, idx, highBound(c.config, arr, c.guards.g.operators))

proc checkRange(c: PEffects; value: PNode; typ: PType) =
  let t = typ.skipTypes(abstractInst - {tyRange})
  if t.kind == tyRange:
    let lowBound = copyTree(t.n[0])
    lowBound.info = value.info
    let highBound = copyTree(t.n[1])
    highBound.info = value.info
    checkLe(c, lowBound, value)
    checkLe(c, value, highBound)

#[
proc passedToEffectsDelayedParam(tracked: PEffects; n: PNode) =
  let t = n.typ.skipTypes(abstractInst)
  if t.kind == tyProc:
    if n.kind == nkSym and tracked.owner == n.sym.owner and sfEffectsDelayed in n.sym.flags:
      discard "the arg is itself a delayed parameter, so do nothing"
    else:
      var effectList = t.n[0]
      if effectList.len == effectListLen:
        mergeRaises(tracked, effectList[exceptionEffects], n)
        mergeTags(tracked, effectList[tagEffects], n)
      if not importedFromC(n):
        if notGcSafe(t):
          if tracked.config.hasWarn(warnGcUnsafe): warnAboutGcUnsafe(n, tracked.config)
          markGcUnsafe(tracked, n)
        if tfNoSideEffect notin t.flags:
          markSideEffect(tracked, n, n.info)
]#

proc checkForSink(tracked: PEffects; n: PNode) =
  if tracked.inIfStmt == 0 and optSinkInference in tracked.config.options:
    checkForSink(tracked.config, tracked.c.idgen, tracked.owner, n)

proc markCaughtExceptions(tracked: PEffects; g: ModuleGraph; info: TLineInfo; s: PSym; usageSym: var PSym) =
  when defined(nimsuggest):
    proc internalMarkCaughtExceptions(tracked: PEffects; q: var SuggestFileSymbolDatabase; info: TLineInfo) =
      var si = q.findSymInfoIndex(info)
      if si != -1:
        q.caughtExceptionsSet[si] = true
        for w1 in tracked.caughtExceptions.nodes:
          for w2 in w1:
            q.caughtExceptions[si].add(w2)

    if optIdeExceptionInlayHints in tracked.config.globalOptions:
      internalMarkCaughtExceptions(tracked, g.suggestSymbols.mgetOrPut(info.fileIndex, newSuggestFileSymbolDatabase(info.fileIndex, true)), info)

proc trackCall(tracked: PEffects; n: PNode) =
  template gcsafeAndSideeffectCheck() =
    if notGcSafe(op) and not importedFromC(a):
      # and it's not a recursive call:
      if not (a.kind == nkSym and a.sym == tracked.owner):
        if tracked.config.hasWarn(warnGcUnsafe): warnAboutGcUnsafe(n, tracked.config)
        markGcUnsafe(tracked, a)
    if tfNoSideEffect notin op.flags and not importedFromC(a):
      # and it's not a recursive call:
      if not (a.kind == nkSym and a.sym == tracked.owner):
        markSideEffect(tracked, a, n.info)
  # p's effects are ours too:
  var a = n[0]
  #if canRaise(a):
  #  echo "this can raise ", tracked.config $ n.info
  let op = a.typ
  if n.typ != nil:
    if tracked.owner.kind != skMacro and n.typ.skipTypes(abstractVar).kind != tyOpenArray:
      createTypeBoundOps(tracked, n.typ, n.info)

  when defined(nimsuggest):
    var actualLoc = a.info
    if n.kind == nkHiddenCallConv:
      actualLoc = n.info
    if a.kind == nkSym:
      markCaughtExceptions(tracked, tracked.graph, actualLoc, a.sym, tracked.graph.usageSym)

  let notConstExpr = getConstExpr(tracked.ownerModule, n, tracked.c.idgen, tracked.graph) == nil
  if notConstExpr:
    if a.kind == nkCast and a[1].typ.kind == tyProc:
      a = a[1]
    # XXX: in rare situations, templates and macros will reach here after
    # calling getAst(templateOrMacro()). Currently, templates and macros
    # are indistinguishable from normal procs (both have tyProc type) and
    # we can detect them only by checking for attached nkEffectList.
    if op != nil and op.kind == tyProc and op.n[0].kind == nkEffectList:
      if a.kind == nkSym:
        if a.sym == tracked.owner: tracked.isRecursive = true
        # even for recursive calls we need to check the lock levels (!):
        if sfSideEffect in a.sym.flags: markSideEffect(tracked, a, n.info)
      else:
        discard
      var effectList = op.n[0]
      if a.kind == nkSym and a.sym.kind == skMethod:
        if {sfBase, sfThread} * a.sym.flags == {sfBase}:
          if tracked.config.hasWarn(warnGcUnsafe): warnAboutGcUnsafe(n, tracked.config)
          markGcUnsafe(tracked, a)
        propagateEffects(tracked, n, a.sym)
      elif isNoEffectList(effectList):
        if isForwardedProc(a):
          propagateEffects(tracked, n, a.sym)
        elif isIndirectCall(tracked, a):
          assumeTheWorst(tracked, n, op)
          gcsafeAndSideeffectCheck()
        else:
          if laxEffects notin tracked.c.config.legacyFeatures and a.kind == nkSym and
              a.sym.kind in routineKinds:
            propagateEffects(tracked, n, a.sym)
      else:
        mergeRaises(tracked, effectList[exceptionEffects], n)
        mergeTags(tracked, effectList[tagEffects], n)
        gcsafeAndSideeffectCheck()
    if a.kind != nkSym or a.sym.magic notin {mNBindSym, mFinished, mExpandToAst, mQuoteAst}:
      for i in 1..<n.len:
        trackOperandForIndirectCall(tracked, n[i], op, i, a)
    if a.kind == nkSym and a.sym.magic in {mNew, mNewFinalize, mNewSeq}:
      # may not look like an assignment, but it is:
      let arg = n[1]
      initVarViaNew(tracked, arg)
      if arg.typ.hasElementType and {tfRequiresInit} * arg.typ.elementType.flags != {}:
        if a.sym.magic == mNewSeq and n[2].kind in {nkCharLit..nkUInt64Lit} and
            n[2].intVal == 0:
          # var s: seq[notnil];  newSeq(s, 0)  is a special case!
          discard
        else:
          message(tracked.config, arg.info, warnProveInit, $arg)

      # check required for 'nim check':
      if n[1].typ.hasElementType:
        createTypeBoundOps(tracked, n[1].typ.elementType, n.info)
        createTypeBoundOps(tracked, n[1].typ, n.info)
        # new(x, finalizer): Problem: how to move finalizer into 'createTypeBoundOps'?

    elif a.kind == nkSym and a.sym.magic in {mArrGet, mArrPut} and
        optStaticBoundsCheck in tracked.currOptions:
      checkBounds(tracked, n[1], n[2])


  if a.kind == nkSym and a.sym.name.s.len > 0 and a.sym.name.s[0] == '=' and
        tracked.owner.kind != skMacro:
    var opKind = find(AttachedOpToStr, a.sym.name.s.normalize)
    if a.sym.name.s == "=": opKind = attachedAsgn.int
    if opKind != -1:
      # rebind type bounds operations after createTypeBoundOps call
      let t = n[1].typ.skipTypes({tyAlias, tyVar})
      if a.sym != getAttachedOp(tracked.graph, t, TTypeAttachedOp(opKind)):
        createTypeBoundOps(tracked, t, n.info)
        let op = getAttachedOp(tracked.graph, t, TTypeAttachedOp(opKind))
        if op != nil:
          n[0].sym = op

  if op != nil and op.kind == tyProc:
    for i in 1..<min(n.safeLen, op.signatureLen):
      let paramType = op[i]
      case paramType.kind
      of tySink:
        createTypeBoundOps(tracked, paramType.elementType, n.info)
        checkForSink(tracked, n[i])
      of tyVar:
        if isOutParam(paramType):
          # consider this case: p(out x, x); we want to remark that 'x' is not
          # initialized until after the call. Since we do this after we analysed the
          # call, this is fine.
          initVar(tracked, n[i].skipHiddenAddr, false)
        if strictFuncs in tracked.c.features and not tracked.inEnforcedNoSideEffects and
           isDangerousLocation(n[i].skipHiddenAddr, tracked.owner):
          if sfNoSideEffect in tracked.owner.flags:
            localError(tracked.config, n[i].info,
              "cannot pass $1 to `var T` parameter within a strict func" % renderTree(n[i]))
          tracked.hasSideEffect = true
      else: discard

  if notConstExpr and (a.kind != nkSym or
      a.sym.magic notin {mRunnableExamples, mNBindSym, mExpandToAst, mQuoteAst}
  ):
    # tracked after out analysis
    for i in 0..<n.safeLen:
      track(tracked, n[i])

type
  PragmaBlockContext = object
    oldLocked: int
    enforcedGcSafety, enforceNoSideEffects: bool
    oldExc, oldTags, oldForbids: int
    exc, tags, forbids: PNode

proc createBlockContext(tracked: PEffects): PragmaBlockContext =
  var oldForbidsLen = 0
  if tracked.forbids != nil: oldForbidsLen = tracked.forbids.len
  result = PragmaBlockContext(oldLocked: tracked.locked.len,
    enforcedGcSafety: false, enforceNoSideEffects: false,
    oldExc: tracked.exc.len, oldTags: tracked.tags.len,
    oldForbids: oldForbidsLen)

proc applyBlockContext(tracked: PEffects, bc: PragmaBlockContext) =
  if bc.enforcedGcSafety: tracked.inEnforcedGcSafe = true
  if bc.enforceNoSideEffects: tracked.inEnforcedNoSideEffects = true

proc unapplyBlockContext(tracked: PEffects; bc: PragmaBlockContext) =
  if bc.enforcedGcSafety: tracked.inEnforcedGcSafe = false
  if bc.enforceNoSideEffects: tracked.inEnforcedNoSideEffects = false
  setLen(tracked.locked, bc.oldLocked)
  if bc.exc != nil:
    # beware that 'raises: []' is very different from not saying
    # anything about 'raises' in the 'cast' at all. Same applies for 'tags'.
    setLen(tracked.exc.sons, bc.oldExc)
    for e in bc.exc:
      addRaiseEffect(tracked, e, e)
  if bc.tags != nil:
    setLen(tracked.tags.sons, bc.oldTags)
    for t in bc.tags:
      addTag(tracked, t, t)
  if bc.forbids != nil:
    setLen(tracked.forbids.sons, bc.oldForbids)
    for t in bc.forbids:
      addNotTag(tracked, t, t)

proc castBlock(tracked: PEffects, pragma: PNode, bc: var PragmaBlockContext) =
  case whichPragma(pragma)
  of wGcSafe:
    bc.enforcedGcSafety = true
  of wNoSideEffect:
    bc.enforceNoSideEffects = true
  of wTags:
    let n = pragma[1]
    if n.kind in {nkCurly, nkBracket}:
      bc.tags = n
    else:
      bc.tags = newNodeI(nkArgList, pragma.info)
      bc.tags.add n
  of wForbids:
    let n = pragma[1]
    if n.kind in {nkCurly, nkBracket}:
      bc.forbids = n
    else:
      bc.forbids = newNodeI(nkArgList, pragma.info)
      bc.forbids.add n
  of wRaises:
    let n = pragma[1]
    if n.kind in {nkCurly, nkBracket}:
      bc.exc = n
    else:
      bc.exc = newNodeI(nkArgList, pragma.info)
      bc.exc.add n
  of wUncheckedAssign:
    discard "handled in sempass1"
  else:
    localError(tracked.config, pragma.info,
        "invalid pragma block: " & $pragma)

proc trackInnerProc(tracked: PEffects, n: PNode) =
  case n.kind
  of nkSym:
    let s = n.sym
    if s.kind == skParam and s.owner == tracked.owner:
      tracked.escapingParams.incl s.id
  of nkNone..pred(nkSym), succ(nkSym)..nkNilLit:
    discard
  of nkProcDef, nkConverterDef, nkMethodDef, nkIteratorDef, nkLambda, nkFuncDef, nkDo:
    if n[0].kind == nkSym and n[0].sym.ast != nil:
      trackInnerProc(tracked, getBody(tracked.graph, n[0].sym))
  of nkTypeSection, nkMacroDef, nkTemplateDef, nkError,
     nkConstSection, nkConstDef, nkIncludeStmt, nkImportStmt,
     nkExportStmt, nkPragma, nkCommentStmt, nkBreakState,
     nkTypeOfExpr, nkMixinStmt, nkBindStmt:
    discard
  else:
    for ch in n: trackInnerProc(tracked, ch)

proc allowCStringConv(n: PNode): bool =
  case n.kind
  of nkStrLit..nkTripleStrLit: result = true
  of nkSym: result = n.sym.kind in {skConst, skParam}
  of nkAddr: result = isCharArrayPtr(n.typ, true)
  of nkCallKinds:
    result = isCharArrayPtr(n.typ, n[0].kind == nkSym and n[0].sym.magic == mAddr)
  else: result = isCharArrayPtr(n.typ, false)

proc track(tracked: PEffects, n: PNode) =
  case n.kind
  of nkSym:
    useVar(tracked, n)
    if n.sym.typ != nil and tfHasAsgn in n.sym.typ.flags:
      tracked.owner.flags.incl sfInjectDestructors
      # bug #15038: ensure consistency
      if n.typ == nil or (not hasDestructor(n.typ) and sameType(n.typ, n.sym.typ)): n.typ() = n.sym.typ
  of nkHiddenAddr, nkAddr:
    if n[0].kind == nkSym and isLocalSym(tracked, n[0].sym) and
          n.typ.kind notin {tyVar, tyLent}:
      useVarNoInitCheck(tracked, n[0], n[0].sym)
    else:
      track(tracked, n[0])
  of nkRaiseStmt:
    if n[0].kind != nkEmpty:
      n[0].info = n.info
      #throws(tracked.exc, n[0])
      addRaiseEffect(tracked, n[0], n)
      for i in 0..<n.safeLen:
        track(tracked, n[i])
      createTypeBoundOps(tracked, n[0].typ, n.info)
    else:
      # A `raise` with no arguments means we're going to re-raise the exception
      # being handled or, if outside of an `except` block, a `ReraiseDefect`.
      # Here we add a `Exception` tag in order to cover both the cases.
      addRaiseEffect(tracked, createRaise(tracked.graph, n), nil)
  of nkCallKinds:
    trackCall(tracked, n)
  of nkDotExpr:
    guardDotAccess(tracked, n)
    let oldLeftPartOfAsgn = tracked.leftPartOfAsgn
    tracked.leftPartOfAsgn = 0
    for i in 0..<n.len: track(tracked, n[i])
    tracked.leftPartOfAsgn = oldLeftPartOfAsgn
  of nkCheckedFieldExpr:
    track(tracked, n[0])
    if tracked.config.hasWarn(warnProveField) or strictCaseObjects in tracked.c.features:
      checkFieldAccess(tracked.guards, n, tracked.config, strictCaseObjects in tracked.c.features)
  of nkTryStmt: trackTryStmt(tracked, n)
  of nkPragma: trackPragmaStmt(tracked, n)
  of nkAsgn, nkFastAsgn, nkSinkAsgn:
    track(tracked, n[1])
    initVar(tracked, n[0], volatileCheck=true)
    invalidateFacts(tracked.guards, n[0])
    inc tracked.leftPartOfAsgn
    track(tracked, n[0])
    dec tracked.leftPartOfAsgn
    addAsgnFact(tracked.guards, n[0], n[1])
    notNilCheck(tracked, n[1], n[0].typ)
    when false: cstringCheck(tracked, n)
    if tracked.owner.kind != skMacro and n[0].typ.kind notin {tyOpenArray, tyVarargs}:
      createTypeBoundOps(tracked, n[0].typ, n.info)
    if n[0].kind != nkSym or not isLocalSym(tracked, n[0].sym):
      checkForSink(tracked, n[1])
      if strictFuncs in tracked.c.features and not tracked.inEnforcedNoSideEffects and
         isDangerousLocation(n[0], tracked.owner):
        tracked.hasSideEffect = true
        if sfNoSideEffect in tracked.owner.flags:
          localError(tracked.config, n[0].info,
              "cannot mutate location $1 within a strict func" % renderTree(n[0]))
  of nkVarSection, nkLetSection:
    for child in n:
      let last = lastSon(child)
      if last.kind != nkEmpty: track(tracked, last)
      if tracked.owner.kind != skMacro:
        if child.kind == nkVarTuple:
          createTypeBoundOps(tracked, child[^1].typ, child.info)
          for i in 0..<child.len-2:
            createTypeBoundOps(tracked, child[i].typ, child.info)
        else:
          createTypeBoundOps(tracked, skipPragmaExpr(child[0]).typ, child.info)
      if child.kind == nkIdentDefs:
        for i in 0..<child.len-2:
          let a = skipPragmaExpr(child[i])
          varDecl(tracked, a)
          if last.kind != nkEmpty:
            initVar(tracked, a, volatileCheck=false)
            addAsgnFact(tracked.guards, a, last)
            notNilCheck(tracked, last, a.typ)
      elif child.kind == nkVarTuple:
        for i in 0..<child.len-1:
          if child[i].kind == nkEmpty or
            child[i].kind == nkSym and child[i].sym.name.id == ord(wUnderscore):
            continue
          varDecl(tracked, child[i])
          if last.kind != nkEmpty:
            initVar(tracked, child[i], volatileCheck=false)
          if last.kind in {nkPar, nkTupleConstr}:
            addAsgnFact(tracked.guards, child[i], last[i])
            notNilCheck(tracked, last[i], child[i].typ)
      # since 'var (a, b): T = ()' is not even allowed, there is always type
      # inference for (a, b) and thus no nil checking is necessary.
  of nkConstSection:
    for child in n:
      let last = lastSon(child)
      track(tracked, last)
  of nkCaseStmt: trackCase(tracked, n)
  of nkWhen: # This should be a "when nimvm" node.
    let oldState = tracked.init.len
    track(tracked, n[0][1])
    tracked.init.setLen(oldState)
    track(tracked, n[1][0])
  of nkIfStmt, nkIfExpr: trackIf(tracked, n)
  of nkBlockStmt, nkBlockExpr: trackBlock(tracked, n[1])
  of nkWhileStmt:
    # 'while true' loop?
    inc tracked.currentBlock
    if isTrue(n[0]):
      trackBlock(tracked, n[1])
    else:
      # loop may never execute:
      let oldState = tracked.init.len
      let oldFacts = tracked.guards.s.len
      addFact(tracked.guards, n[0])
      track(tracked, n[0])
      track(tracked, n[1])
      setLen(tracked.init, oldState)
      setLen(tracked.guards.s, oldFacts)
    dec tracked.currentBlock
  of nkForStmt, nkParForStmt:
    # we are very conservative here and assume the loop is never executed:
    inc tracked.currentBlock
    let oldState = tracked.init.len

    let oldFacts = tracked.guards.s.len
    let iterCall = n[n.len-2]
    if optStaticBoundsCheck in tracked.currOptions and iterCall.kind in nkCallKinds:
      let op = iterCall[0]
      if op.kind == nkSym and fromSystem(op.sym):
        let iterVar = n[0]
        case op.sym.name.s
        of "..", "countup", "countdown":
          let lower = iterCall[1]
          let upper = iterCall[2]
          # for i in 0..n   means  0 <= i and i <= n. Countdown is
          # the same since only the iteration direction changes.
          addFactLe(tracked.guards, lower, iterVar)
          addFactLe(tracked.guards, iterVar, upper)
        of "..<":
          let lower = iterCall[1]
          let upper = iterCall[2]
          addFactLe(tracked.guards, lower, iterVar)
          addFactLt(tracked.guards, iterVar, upper)
        else: discard

    for i in 0..<n.len-2:
      let it = n[i]
      track(tracked, it)
      if tracked.owner.kind != skMacro:
        if it.kind == nkVarTuple:
          for x in it:
            createTypeBoundOps(tracked, x.typ, x.info)
        else:
          createTypeBoundOps(tracked, it.typ, it.info)
    let loopBody = n[^1]
    if tracked.owner.kind != skMacro and iterCall.safeLen > 1:
      # XXX this is a bit hacky:
      if iterCall[1].typ != nil and iterCall[1].typ.skipTypes(abstractVar).kind notin {tyVarargs, tyOpenArray}:
        createTypeBoundOps(tracked, iterCall[1].typ, iterCall[1].info)
    track(tracked, iterCall)
    track(tracked, loopBody)
    setLen(tracked.init, oldState)
    setLen(tracked.guards.s, oldFacts)
    dec tracked.currentBlock

  of nkObjConstr:
    when false: track(tracked, n[0])
    let oldFacts = tracked.guards.s.len
    for i in 1..<n.len:
      let x = n[i]
      track(tracked, x)
      if x[0].kind == nkSym and sfDiscriminant in x[0].sym.flags:
        addDiscriminantFact(tracked.guards, x)
      if tracked.owner.kind != skMacro:
        createTypeBoundOps(tracked, x[1].typ, n.info)

      if x.kind == nkExprColonExpr:
        if x[0].kind == nkSym:
          notNilCheck(tracked, x[1], x[0].sym.typ)
        checkForSink(tracked, x[1])
      else:
        checkForSink(tracked, x)
    setLen(tracked.guards.s, oldFacts)
    if tracked.owner.kind != skMacro:
      # XXX n.typ can be nil in runnableExamples, we need to do something about it.
      if n.typ != nil and n.typ.skipTypes(abstractInst).kind == tyRef:
        createTypeBoundOps(tracked, n.typ.elementType, n.info)
      createTypeBoundOps(tracked, n.typ, n.info)
  of nkTupleConstr:
    for i in 0..<n.len:
      track(tracked, n[i])
      notNilCheck(tracked, n[i].skipColon, n[i].typ)
      if tracked.owner.kind != skMacro:
        if n[i].kind == nkExprColonExpr:
          createTypeBoundOps(tracked, n[i][0].typ, n.info)
        else:
          createTypeBoundOps(tracked, n[i].typ, n.info)
      checkForSink(tracked, n[i])
  of nkPragmaBlock:
    let pragmaList = n[0]
    var bc = createBlockContext(tracked)
    for i in 0..<pragmaList.len:
      let pragma = whichPragma(pragmaList[i])
      case pragma
      of wLocks:
        lockLocations(tracked, pragmaList[i])
      of wGcSafe:
        bc.enforcedGcSafety = true
      of wNoSideEffect:
        bc.enforceNoSideEffects = true
      of wCast:
        castBlock(tracked, pragmaList[i][1], bc)
      else:
        discard
    applyBlockContext(tracked, bc)
    track(tracked, n.lastSon)
    unapplyBlockContext(tracked, bc)

  of nkProcDef, nkConverterDef, nkMethodDef, nkIteratorDef, nkLambda, nkFuncDef, nkDo:
    if n[0].kind == nkSym and n[0].sym.ast != nil:
      trackInnerProc(tracked, getBody(tracked.graph, n[0].sym))
  of nkMacroDef, nkTemplateDef:
    discard
  of nkTypeSection:
    if tracked.isTopLevel:
      collectObjectTree(tracked.graph, n)
  of nkCast:
    if n.len == 2:
      track(tracked, n[1])
      if tracked.owner.kind != skMacro:
        createTypeBoundOps(tracked, n.typ, n.info)
  of nkHiddenStdConv, nkHiddenSubConv, nkConv:
    if n.kind in {nkHiddenStdConv, nkHiddenSubConv} and
        n.typ.skipTypes(abstractInst).kind == tyCstring and
        not allowCStringConv(n[1]):
      message(tracked.config, n.info, warnCstringConv,
        "implicit conversion to 'cstring' from a non-const location: $1; this will become a compile time error in the future" %
          $n[1])
    if n.typ.skipTypes(abstractInst).kind == tyCstring and
        isCharArrayPtr(n[1].typ, true):
      message(tracked.config, n.info, warnPtrToCstringConv,
          $n[1].typ)


    let t = n.typ.skipTypes(abstractInst)
    if t.kind == tyEnum:
      if tfEnumHasHoles in t.flags:
        message(tracked.config, n.info, warnHoleEnumConv, "conversion to enum with holes is unsafe: $1" % $n)
      else:
        message(tracked.config, n.info, warnAnyEnumConv, "enum conversion: $1" % $n)

    if n.len == 2:
      track(tracked, n[1])
      if tracked.owner.kind != skMacro:
        createTypeBoundOps(tracked, n.typ, n.info)
        # This is a hacky solution in order to fix bug #13110. Hopefully
        # a better solution will come up eventually.
        if n[1].typ.kind != tyString:
          createTypeBoundOps(tracked, n[1].typ, n[1].info)
      if optStaticBoundsCheck in tracked.currOptions:
        checkRange(tracked, n[1], n.typ)
  of nkObjUpConv, nkObjDownConv, nkChckRange, nkChckRangeF, nkChckRange64:
    if n.len == 1:
      track(tracked, n[0])
      if tracked.owner.kind != skMacro:
        createTypeBoundOps(tracked, n.typ, n.info)
        createTypeBoundOps(tracked, n[0].typ, n[0].info)
      if optStaticBoundsCheck in tracked.currOptions:
        checkRange(tracked, n[0], n.typ)
  of nkBracket:
    for i in 0..<n.safeLen:
      track(tracked, n[i])
      checkForSink(tracked, n[i])
    if tracked.owner.kind != skMacro:
      createTypeBoundOps(tracked, n.typ, n.info)
  of nkBracketExpr:
    if optStaticBoundsCheck in tracked.currOptions and n.len == 2:
      if n[0].typ != nil and skipTypes(n[0].typ, abstractVar).kind != tyTuple:
        checkBounds(tracked, n[0], n[1])
    track(tracked, n[0])
    dec tracked.leftPartOfAsgn
    for i in 1 ..< n.len: track(tracked, n[i])
    inc tracked.leftPartOfAsgn
  of nkError:
    localError(tracked.config, n.info, errorToString(tracked.config, n))
  else:
    for i in 0..<n.safeLen: track(tracked, n[i])

proc subtypeRelation(g: ModuleGraph; spec, real: PNode): bool =
  if spec.typ.kind == tyOr:
    result = false
    for t in spec.typ.kids:
      if safeInheritanceDiff(g.excType(real), t) <= 0:
        return true
  else:
    return safeInheritanceDiff(g.excType(real), spec.typ) <= 0

proc checkRaisesSpec(g: ModuleGraph; emitWarnings: bool; spec, real: PNode, msg: string, hints: bool;
                     effectPredicate: proc (g: ModuleGraph; a, b: PNode): bool {.nimcall.};
                     hintsArg: PNode = nil; isForbids: bool = false) =
  # check that any real exception is listed in 'spec'; mark those as used;
  # report any unused exception
  var used = initIntSet()
  for r in items(real):
    block search:
      for s in 0..<spec.len:
        if effectPredicate(g, spec[s], r):
          if isForbids: break
          used.incl(s)
          break search
        if isForbids:
          break search
      # XXX call graph analysis would be nice here!
      pushInfoContext(g.config, spec.info)
      var rr = if r.kind == nkRaiseStmt: r[0] else: r
      while rr.kind in {nkStmtList, nkStmtListExpr} and rr.len > 0: rr = rr.lastSon
      message(g.config, r.info, if emitWarnings: warnEffect else: errGenerated,
              renderTree(rr) & " " & msg & typeToString(r.typ))
      popInfoContext(g.config)
  # hint about unnecessarily listed exception types:
  if hints:
    for s in 0..<spec.len:
      if not used.contains(s):
        message(g.config, spec[s].info, hintXCannotRaiseY,
                "'$1' cannot raise '$2'" % [renderTree(hintsArg), renderTree(spec[s])])

proc checkMethodEffects*(g: ModuleGraph; disp, branch: PSym) =
  ## checks for consistent effects for multi methods.
  let actual = branch.typ.n[0]
  if actual.len != effectListLen: return

  let p = disp.ast[pragmasPos]
  let raisesSpec = effectSpec(p, wRaises)
  if not isNil(raisesSpec):
    checkRaisesSpec(g, false, raisesSpec, actual[exceptionEffects],
      "can raise an unlisted exception: ", hints=off, subtypeRelation)
  let tagsSpec = effectSpec(p, wTags)
  if not isNil(tagsSpec):
    checkRaisesSpec(g, false, tagsSpec, actual[tagEffects],
      "can have an unlisted effect: ", hints=off, subtypeRelation)
  let forbidsSpec = effectSpec(p, wForbids)
  if not isNil(forbidsSpec):
    checkRaisesSpec(g, false, forbidsSpec, actual[tagEffects],
      "has an illegal effect: ", hints=off, subtypeRelation, isForbids=true)
  if sfThread in disp.flags and notGcSafe(branch.typ):
    localError(g.config, branch.info, "base method is GC-safe, but '$1' is not" %
                                branch.name.s)
  when defined(drnim):
    if not g.compatibleProps(g, disp.typ, branch.typ):
      localError(g.config, branch.info, "for method '" & branch.name.s &
        "' the `.requires` or `.ensures` properties are incompatible.")

proc setEffectsForProcType*(g: ModuleGraph; t: PType, n: PNode; s: PSym = nil) =
  var effects = t.n[0]
  if t.kind != tyProc or effects.kind != nkEffectList: return
  if n.kind != nkEmpty:
    internalAssert g.config, effects.len == 0
    newSeq(effects.sons, effectListLen)
    let raisesSpec = effectSpec(n, wRaises)
    if not isNil(raisesSpec):
      effects[exceptionEffects] = raisesSpec
    elif s != nil and (s.magic != mNone or {sfImportc, sfExportc} * s.flags == {sfImportc}):
      effects[exceptionEffects] = newNodeI(nkArgList, effects.info)

    let tagsSpec = effectSpec(n, wTags)
    if not isNil(tagsSpec):
      effects[tagEffects] = tagsSpec
    elif s != nil and (s.magic != mNone or {sfImportc, sfExportc} * s.flags == {sfImportc}):
      effects[tagEffects] = newNodeI(nkArgList, effects.info)

    let forbidsSpec = effectSpec(n, wForbids)
    if not isNil(forbidsSpec):
      effects[forbiddenEffects] = forbidsSpec
    elif s != nil and (s.magic != mNone or {sfImportc, sfExportc} * s.flags == {sfImportc}):
      effects[forbiddenEffects] = newNodeI(nkArgList, effects.info)

    let requiresSpec = propSpec(n, wRequires)
    if not isNil(requiresSpec):
      effects[requiresEffects] = requiresSpec
    let ensuresSpec = propSpec(n, wEnsures)
    if not isNil(ensuresSpec):
      effects[ensuresEffects] = ensuresSpec

    effects[pragmasEffects] = n
  if s != nil and s.magic != mNone:
    if s.magic != mEcho:
      t.flags.incl tfNoSideEffect

proc rawInitEffects(g: ModuleGraph; effects: PNode) =
  newSeq(effects.sons, effectListLen)
  effects[exceptionEffects] = newNodeI(nkArgList, effects.info)
  effects[tagEffects] = newNodeI(nkArgList, effects.info)
  effects[forbiddenEffects] = newNodeI(nkArgList, effects.info)
  effects[requiresEffects] = g.emptyNode
  effects[ensuresEffects] = g.emptyNode
  effects[pragmasEffects] = g.emptyNode

proc initEffects(g: ModuleGraph; effects: PNode; s: PSym; c: PContext): TEffects =
  rawInitEffects(g, effects)

  result = TEffects(exc: effects[exceptionEffects], tags: effects[tagEffects],
            forbids: effects[forbiddenEffects], owner: s, ownerModule: s.getModule,
            init: @[], locked: @[], graph: g, config: g.config, c: c,
            currentBlock: 1, optionsStack: @[(g.config.options, g.config.notes)]
  )
  result.guards.s = @[]
  result.guards.g = g
  when defined(drnim):
    result.currOptions = g.config.options + s.options - {optStaticBoundsCheck}
  else:
    result.currOptions = g.config.options + s.options
  result.guards.beSmart = optStaticBoundsCheck in result.currOptions

proc hasRealBody(s: PSym): bool =
  ## also handles importc procs with runnableExamples, which requires `=`,
  ## which is not a real implementation, refs #14314
  result = {sfForward, sfImportc} * s.flags == {}

proc trackProc*(c: PContext; s: PSym, body: PNode) =
  let g = c.graph
  when defined(nimsuggest):
    if g.config.expandDone():
      return
  var effects = s.typ.n[0]
  if effects.kind != nkEffectList: return
  # effects already computed?
  if not s.hasRealBody: return
  let emitWarnings = tfEffectSystemWorkaround in s.typ.flags
  if effects.len == effectListLen and not emitWarnings: return

  var inferredEffects = newNodeI(nkEffectList, s.info)

  var t: TEffects = initEffects(g, inferredEffects, s, c)
  rawInitEffects g, effects

  if not isEmptyType(s.typ.returnType) and
     s.kind in {skProc, skFunc, skConverter, skMethod}:
    var res = s.ast[resultPos].sym # get result symbol
    t.scopes[res.id] = t.currentBlock
    if sfNoInit in s.flags:
      # marks result "noinit"
      incl res.flags, sfNoInit

  track(t, body)

  if s.kind != skMacro:
    let params = s.typ.n
    for i in 1..<params.len:
      let param = params[i].sym
      let typ = param.typ
      if isSinkTypeForParam(typ) or
          (t.config.selectedGC in {gcArc, gcOrc, gcAtomicArc} and
            (isClosure(typ.skipTypes(abstractInst)) or param.id in t.escapingParams)):
        createTypeBoundOps(t, typ, param.info)
      if isOutParam(typ) and param.id notin t.init:
        message(g.config, param.info, warnProveInit, param.name.s)

  if not isEmptyType(s.typ.returnType) and
     (s.typ.returnType.requiresInit or s.typ.returnType.skipTypes(abstractInst).kind == tyVar or
       noStrictDefs notin c.config.legacyFeatures) and
     s.kind in {skProc, skFunc, skConverter, skMethod} and s.magic == mNone and
     sfNoInit notin s.flags:
    var res = s.ast[resultPos].sym # get result symbol
    if res.id notin t.init and breaksBlock(body) != bsNoReturn:
      if tfRequiresInit in s.typ.returnType.flags:
        localError(g.config, body.info, "'$1' requires explicit initialization" % "result")
      else:
        message(g.config, body.info, warnProveInit, "result")
  let p = s.ast[pragmasPos]
  let raisesSpec = effectSpec(p, wRaises)
  if not isNil(raisesSpec):
    let useWarning = s.name.s == "=destroy"
    checkRaisesSpec(g, useWarning, raisesSpec, t.exc, "can raise an unlisted exception: ",
                    hints=on, subtypeRelation, hintsArg=s.ast[0])
    # after the check, use the formal spec:
    effects[exceptionEffects] = raisesSpec
  else:
    effects[exceptionEffects] = t.exc

  let tagsSpec = effectSpec(p, wTags)
  if not isNil(tagsSpec):
    checkRaisesSpec(g, false, tagsSpec, t.tags, "can have an unlisted effect: ",
                    hints=off, subtypeRelation)
    # after the check, use the formal spec:
    effects[tagEffects] = tagsSpec
  else:
    effects[tagEffects] = t.tags

  let forbidsSpec = effectSpec(p, wForbids)
  if not isNil(forbidsSpec):
    checkRaisesSpec(g, false, forbidsSpec, t.tags, "has an illegal effect: ",
                    hints=off, subtypeRelation, isForbids=true)
    # after the check, use the formal spec:
    effects[forbiddenEffects] = forbidsSpec
  else:
    effects[forbiddenEffects] = t.forbids

  let requiresSpec = propSpec(p, wRequires)
  if not isNil(requiresSpec):
    effects[requiresEffects] = requiresSpec
  let ensuresSpec = propSpec(p, wEnsures)
  if not isNil(ensuresSpec):
    patchResult(t, ensuresSpec)
    effects[ensuresEffects] = ensuresSpec

  var mutationInfo = MutationInfo()
  if views in c.features:
    var partitions = computeGraphPartitions(s, body, g, {borrowChecking})
    checkBorrowedLocations(partitions, body, g.config)

  if sfThread in s.flags and t.gcUnsafe:
    if optThreads in g.config.globalOptions and optThreadAnalysis in g.config.globalOptions:
      #localError(s.info, "'$1' is not GC-safe" % s.name.s)
      listGcUnsafety(s, onlyWarning=false, g.config)
    else:
      listGcUnsafety(s, onlyWarning=true, g.config)
      #localError(s.info, warnGcUnsafe2, s.name.s)
  if sfNoSideEffect in s.flags and t.hasSideEffect:
    when false:
      listGcUnsafety(s, onlyWarning=false, g.config)
    else:
      if c.compilesContextId == 0: # don't render extended diagnostic messages in `system.compiles` context
        var msg = ""
        listSideEffects(msg, s, g.config, t.c)
        message(g.config, s.info, errGenerated, msg)
      else:
        localError(g.config, s.info, "") # simple error for `system.compiles` context
  if not t.gcUnsafe:
    s.typ.flags.incl tfGcSafe
  if not t.hasSideEffect and sfSideEffect notin s.flags:
    s.typ.flags.incl tfNoSideEffect
  when defined(drnim):
    if c.graph.strongSemCheck != nil: c.graph.strongSemCheck(c.graph, s, body)
  when defined(useDfa):
    if s.name.s == "testp":
      dataflowAnalysis(s, body)

      when false: trackWrites(s, body)
  if strictNotNil in c.features and s.kind in {skProc, skFunc, skMethod, skConverter}:
    checkNil(s, body, g.config, c.idgen)

proc trackStmt*(c: PContext; module: PSym; n: PNode, isTopLevel: bool) =
  case n.kind
  of {nkPragma, nkMacroDef, nkTemplateDef, nkProcDef, nkFuncDef,
                nkConverterDef, nkMethodDef, nkIteratorDef}:
    discard
  of nkTypeSection:
    if isTopLevel:
      collectObjectTree(c.graph, n)
  else:
    let g = c.graph
    var effects = newNodeI(nkEffectList, n.info)
    var t: TEffects = initEffects(g, effects, module, c)
    t.isTopLevel = isTopLevel
    track(t, n)
    when defined(drnim):
      if c.graph.strongSemCheck != nil: c.graph.strongSemCheck(c.graph, module, n)

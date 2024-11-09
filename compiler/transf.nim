#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# This module implements the transformator. It transforms the syntax tree
# to ease the work of the code generators. Does some transformations:
#
# * inlines iterators
# * inlines constants
# * performs constant folding
# * converts "continue" to "break"; disambiguates "break"
# * introduces method dispatchers
# * performs lambda lifting for closure support
# * transforms 'defer' into a 'try finally' statement

import std / tables

import
  options, ast, astalgo, trees, msgs,
  idents, renderer, types, semfold, magicsys, cgmeth,
  lowerings, liftlocals,
  modulegraphs, lineinfos

when defined(nimPreviewSlimSystem):
  import std/assertions

type
  TransformFlag* = enum
    useCache, keepOpenArrayConversions, force
  TransformFlags* = set[TransformFlag]

proc transformBody*(g: ModuleGraph; idgen: IdGenerator; prc: PSym; flags: TransformFlags): PNode

import closureiters, lambdalifting

type
  PTransCon = ref object # part of TContext; stackable
    mapping: Table[ItemId, PNode]     # mapping from symbols to nodes
    owner: PSym               # current owner
    forStmt: PNode            # current for stmt
    forLoopBody: PNode   # transformed for loop body
    yieldStmts: int           # we count the number of yield statements,
                              # because we need to introduce new variables
                              # if we encounter the 2nd yield statement
    next: PTransCon           # for stacking

  PTransf = ref object
    module: PSym
    transCon: PTransCon      # top of a TransCon stack
    inlining: int            # > 0 if we are in inlining context (copy vars)
    contSyms, breakSyms: seq[PSym]  # to transform 'continue' and 'break'
    deferDetected, tooEarly: bool
    isIntroducingNewLocalVars: bool  # true if we are in `introducingNewLocalVars` (don't transform yields)
    flags: TransformFlags
    graph: ModuleGraph
    idgen: IdGenerator

proc newTransNode(a: PNode): PNode {.inline.} =
  result = shallowCopy(a)

proc newTransNode(kind: TNodeKind, info: TLineInfo,
                  sons: int): PNode {.inline.} =
  var x = newNodeI(kind, info)
  newSeq(x.sons, sons)
  result = x

proc newTransNode(kind: TNodeKind, n: PNode,
                  sons: int): PNode {.inline.} =
  var x = newNodeIT(kind, n.info, n.typ)
  newSeq(x.sons, sons)
#  x.flags = n.flags
  result = x

proc newTransCon(owner: PSym): PTransCon =
  assert owner != nil
  result = PTransCon(mapping: initTable[ItemId, PNode](), owner: owner)

proc pushTransCon(c: PTransf, t: PTransCon) =
  t.next = c.transCon
  c.transCon = t

proc popTransCon(c: PTransf) =
  if (c.transCon == nil): internalError(c.graph.config, "popTransCon")
  c.transCon = c.transCon.next

proc getCurrOwner(c: PTransf): PSym =
  if c.transCon != nil: result = c.transCon.owner
  else: result = c.module

proc newTemp(c: PTransf, typ: PType, info: TLineInfo): PNode =
  let r = newSym(skTemp, getIdent(c.graph.cache, genPrefix), c.idgen, getCurrOwner(c), info)
  r.typ = typ #skipTypes(typ, {tyGenericInst, tyAlias, tySink})
  incl(r.flags, sfFromGeneric)
  let owner = getCurrOwner(c)
  result = newSymNode(r)

proc transform(c: PTransf, n: PNode, noConstFold = false): PNode

proc transformSons(c: PTransf, n: PNode, noConstFold = false): PNode =
  result = newTransNode(n)
  for i in 0..<n.len:
    result[i] = transform(c, n[i], noConstFold)

proc newAsgnStmt(c: PTransf, kind: TNodeKind, le: PNode, ri: PNode; isFirstWrite: bool): PNode =
  result = newTransNode(kind, ri.info, 2)
  result[0] = le
  if isFirstWrite:
    le.flags.incl nfFirstWrite
  result[1] = ri

proc transformSymAux(c: PTransf, n: PNode): PNode =
  let s = n.sym
  if s.typ != nil and s.typ.callConv == ccClosure:
    if s.kind in routineKinds:
      discard transformBody(c.graph, c.idgen, s, {useCache}+c.flags)
    if s.kind == skIterator:
      if c.tooEarly: return n
      else: return liftIterSym(c.graph, n, c.idgen, getCurrOwner(c))
    elif s.kind in {skProc, skFunc, skConverter, skMethod} and not c.tooEarly:
      # top level .closure procs are still somewhat supported for 'Nake':
      return makeClosure(c.graph, c.idgen, s, nil, n.info)
  #elif n.sym.kind in {skVar, skLet} and n.sym.typ.callConv == ccClosure:
  #  echo n.info, " come heer for ", c.tooEarly
  #  if not c.tooEarly:
  var b: PNode
  var tc = c.transCon
  if sfBorrow in s.flags and s.kind in routineKinds:
    # simply exchange the symbol:
    var s = s
    while true:
      # Skips over all borrowed procs getting the last proc symbol without an implementation
      let body = getBody(c.graph, s)
      if body.kind == nkSym and sfBorrow in body.sym.flags and getBody(c.graph, body.sym).kind == nkSym:
        s = body.sym
      else:
        break
    b = getBody(c.graph, s)
    if b.kind != nkSym: internalError(c.graph.config, n.info, "wrong AST for borrowed symbol")
    b = newSymNode(b.sym, n.info)
  elif c.inlining > 0:
    # see bug #13596: we use ref-based equality in the DFA for destruction
    # injections so we need to ensure unique nodes after iterator inlining
    # which can lead to duplicated for loop bodies! Consider:
    #[
      while remaining > 0:
        if ending == nil:
          yield ms
          break
        ...
        yield ms
    ]#
    b = newSymNode(n.sym, n.info)
  else:
    b = n
  while tc != nil:
    result = getOrDefault(tc.mapping, b.sym.itemId)
    if result != nil:
      # this slightly convoluted way ensures the line info stays correct:
      if result.kind == nkSym:
        result = copyNode(result)
        result.info = n.info
      return
    tc = tc.next
  result = b

proc transformSym(c: PTransf, n: PNode): PNode =
  result = transformSymAux(c, n)

proc freshVar(c: PTransf; v: PSym): PNode =
  let owner = getCurrOwner(c)
  var newVar = copySym(v, c.idgen)
  incl(newVar.flags, sfFromGeneric)
  setOwner(newVar, owner)
  result = newSymNode(newVar)

proc transformVarSection(c: PTransf, v: PNode): PNode =
  result = newTransNode(v)
  for i in 0..<v.len:
    var it = v[i]
    if it.kind == nkCommentStmt:
      result[i] = it
    elif it.kind == nkIdentDefs:
      var vn = it[0]
      if vn.kind == nkPragmaExpr: vn = vn[0]
      if vn.kind == nkSym:
        internalAssert(c.graph.config, it.len == 3)
        let x = freshVar(c, vn.sym)
        c.transCon.mapping[vn.sym.itemId] = x
        var defs = newTransNode(nkIdentDefs, it.info, 3)
        if importantComments(c.graph.config):
          # keep documentation information:
          defs.comment = it.comment
        defs[0] = x
        defs[1] = it[1]
        defs[2] = transform(c, it[2])
        if x.kind == nkSym: x.sym.ast = defs[2]
        result[i] = defs
      else:
        # has been transformed into 'param.x' for closure iterators, so just
        # transform it:
        result[i] = transform(c, it)
    else:
      if it.kind != nkVarTuple:
        internalError(c.graph.config, it.info, "transformVarSection: not nkVarTuple")
      var defs = newTransNode(it.kind, it.info, it.len)
      for j in 0..<it.len-2:
        if it[j].kind == nkSym:
          let x = freshVar(c, it[j].sym)
          c.transCon.mapping[it[j].sym.itemId] = x
          defs[j] = x
        else:
          defs[j] = transform(c, it[j])
      assert(it[^2].kind == nkEmpty)
      defs[^2] = newNodeI(nkEmpty, it.info)
      defs[^1] = transform(c, it[^1])
      result[i] = defs

proc transformConstSection(c: PTransf, v: PNode): PNode =
  result = v
  when false:
    result = newTransNode(v)
    for i in 0..<v.len:
      var it = v[i]
      if it.kind == nkCommentStmt:
        result[i] = it
      else:
        if it.kind != nkConstDef: internalError(c.graph.config, it.info, "transformConstSection")
        if it[0].kind != nkSym:
          debug it[0]
          internalError(c.graph.config, it.info, "transformConstSection")

        result[i] = it

proc hasContinue(n: PNode): bool =
  case n.kind
  of nkEmpty..nkNilLit, nkForStmt, nkParForStmt, nkWhileStmt: result = false
  of nkContinueStmt: result = true
  else:
    result = false
    for i in 0..<n.len:
      if hasContinue(n[i]): return true

proc newLabel(c: PTransf, n: PNode): PSym =
  result = newSym(skLabel, getIdent(c.graph.cache, genPrefix), c.idgen, getCurrOwner(c), n.info)

proc transformBlock(c: PTransf, n: PNode): PNode =
  var labl: PSym
  if c.inlining > 0:
    labl = newLabel(c, n[0])
    c.transCon.mapping[n[0].sym.itemId] = newSymNode(labl)
  else:
    labl =
      if n[0].kind != nkEmpty:
        n[0].sym  # already named block? -> Push symbol on the stack
      else:
        newLabel(c, n)
  c.breakSyms.add(labl)
  result = transformSons(c, n)
  discard c.breakSyms.pop
  result[0] = newSymNode(labl)

proc transformLoopBody(c: PTransf, n: PNode): PNode =
  # What if it contains "continue" and "break"? "break" needs
  # an explicit label too, but not the same!

  # We fix this here by making every 'break' belong to its enclosing loop
  # and changing all breaks that belong to a 'block' by annotating it with
  # a label (if it hasn't one already).
  if hasContinue(n):
    let labl = newLabel(c, n)
    c.contSyms.add(labl)

    result = newTransNode(nkBlockStmt, n.info, 2)
    result[0] = newSymNode(labl)
    result[1] = transform(c, n)
    discard c.contSyms.pop()
  else:
    result = transform(c, n)

proc transformWhile(c: PTransf; n: PNode): PNode =
  if c.inlining > 0:
    result = transformSons(c, n)
  else:
    let labl = newLabel(c, n)
    c.breakSyms.add(labl)
    result = newTransNode(nkBlockStmt, n.info, 2)
    result[0] = newSymNode(labl)

    var body = newTransNode(n)
    for i in 0..<n.len-1:
      body[i] = transform(c, n[i])
    body[^1] = transformLoopBody(c, n[^1])
    result[1] = body
    discard c.breakSyms.pop

proc transformBreak(c: PTransf, n: PNode): PNode =
  result = transformSons(c, n)
  if n[0].kind == nkEmpty and c.breakSyms.len > 0:
    let labl = c.breakSyms[c.breakSyms.high]
    result[0] = newSymNode(labl)

proc introduceNewLocalVars(c: PTransf, n: PNode): PNode =
  case n.kind
  of nkSym:
    result = transformSym(c, n)
  of nkEmpty..pred(nkSym), succ(nkSym)..nkNilLit:
    # nothing to be done for leaves:
    result = n
  of nkVarSection, nkLetSection:
    result = transformVarSection(c, n)
  of nkClosure:
    # it can happen that for-loop-inlining produced a fresh
    # set of variables, including some computed environment
    # (bug #2604). We need to patch this environment here too:
    let a = n[1]
    if a.kind == nkSym:
      n[1] = transformSymAux(c, a)
    return n
  of nkProcDef: # todo optimize nosideeffects?
    result = newTransNode(n)
    let x = newSymNode(copySym(n[namePos].sym, c.idgen))
    c.transCon.mapping[n[namePos].sym.itemId] = x
    result[namePos] = x # we have to copy proc definitions for iters
    for i in 1..<n.len:
      result[i] = introduceNewLocalVars(c, n[i])
    result[namePos].sym.ast = result
  else:
    result = newTransNode(n)
    for i in 0..<n.len:
      result[i] = introduceNewLocalVars(c, n[i])

proc transformAsgn(c: PTransf, n: PNode): PNode =
  let rhs = n[1]

  if rhs.kind != nkTupleConstr:
    return transformSons(c, n)

  # Unpack the tuple assignment into N temporary variables and then pack them
  # into a tuple: this allows us to get the correct results even when the rhs
  # depends on the value of the lhs
  let letSection = newTransNode(nkLetSection, n.info, rhs.len)
  let newTupleConstr = newTransNode(nkTupleConstr, n.info, rhs.len)
  for i, field in rhs:
    let val = if field.kind == nkExprColonExpr: field[1] else: field
    let def = newTransNode(nkIdentDefs, field.info, 3)
    def[0] = newTemp(c, val.typ, field.info)
    def[1] = newNodeI(nkEmpty, field.info)
    def[2] = transform(c, val)
    letSection[i] = def
    # NOTE: We assume the constructor fields are in the correct order for the
    # given tuple type
    newTupleConstr[i] = def[0]

  newTupleConstr.typ() = rhs.typ

  let asgnNode = newTransNode(nkAsgn, n.info, 2)
  asgnNode[0] = transform(c, n[0])
  asgnNode[1] = newTupleConstr

  result = newTransNode(nkStmtList, n.info, 2)
  result[0] = letSection
  result[1] = asgnNode

proc transformYield(c: PTransf, n: PNode): PNode =
  proc asgnTo(lhs: PNode, rhs: PNode): PNode =
    # Choose the right assignment instruction according to the given ``lhs``
    # node since it may not be a nkSym (a stack-allocated skForVar) but a
    # nkDotExpr (a heap-allocated slot into the envP block)
    case lhs.kind
    of nkSym:
      internalAssert c.graph.config, lhs.sym.kind == skForVar
      result = newAsgnStmt(c, nkFastAsgn, lhs, rhs, false)
    of nkDotExpr:
      result = newAsgnStmt(c, nkAsgn, lhs, rhs, false)
    else:
      result = nil
      internalAssert c.graph.config, false
  result = newTransNode(nkStmtList, n.info, 0)
  var e = n[0]
  # c.transCon.forStmt.len == 3 means that there is one for loop variable
  # and thus no tuple unpacking:
  if e.typ.isNil: return result # can happen in nimsuggest for unknown reasons
  if c.transCon.forStmt.len != 3:
    e = skipConv(e)
    if e.kind == nkTupleConstr:
      for i in 0..<e.len:
        var v = e[i]
        if v.kind == nkExprColonExpr: v = v[1]
        if c.transCon.forStmt[i].kind == nkVarTuple:
          for j in 0..<c.transCon.forStmt[i].len-1:
            let lhs = c.transCon.forStmt[i][j]
            let rhs = transform(c, newTupleAccess(c.graph, v, j))
            result.add(asgnTo(lhs, rhs))
        else:
          let lhs = c.transCon.forStmt[i]
          let rhs = transform(c, v)
          result.add(asgnTo(lhs, rhs))
    elif e.kind notin {nkAddr, nkHiddenAddr}: # no need to generate temp for address operation
      # TODO do not use temp for nodes which cannot have side-effects
      var tmp = newTemp(c, e.typ, e.info)
      let v = newNodeI(nkVarSection, e.info)
      v.addVar(tmp, e)

      result.add transform(c, v)

      for i in 0..<c.transCon.forStmt.len - 2:
        if c.transCon.forStmt[i].kind == nkVarTuple:
          for j in 0..<c.transCon.forStmt[i].len-1:
            let lhs = c.transCon.forStmt[i][j]
            let rhs = transform(c, newTupleAccess(c.graph, newTupleAccess(c.graph, tmp, i), j))
            result.add(asgnTo(lhs, rhs))
        else:
          let lhs = c.transCon.forStmt[i]
          let rhs = transform(c, newTupleAccess(c.graph, tmp, i))
          result.add(asgnTo(lhs, rhs))
    else:
      for i in 0..<c.transCon.forStmt.len - 2:
        let lhs = c.transCon.forStmt[i]
        let rhs = transform(c, newTupleAccess(c.graph, e, i))
        result.add(asgnTo(lhs, rhs))
  else:
    if c.transCon.forStmt[0].kind == nkVarTuple:
      var notLiteralTuple = false # we don't generate temp for tuples with const value: (1, 2, 3)
      let ev = e.skipConv
      if ev.kind == nkTupleConstr:
        for i in ev:
          if not isConstExpr(i):
            notLiteralTuple = true
            break
      else:
        notLiteralTuple = true

      if e.kind notin {nkAddr, nkHiddenAddr} and notLiteralTuple:
        # TODO do not use temp for nodes which cannot have side-effects
        var tmp = newTemp(c, e.typ, e.info)
        let v = newNodeI(nkVarSection, e.info)
        v.addVar(tmp, e)

        result.add transform(c, v)
        for i in 0..<c.transCon.forStmt[0].len-1:
          let lhs = c.transCon.forStmt[0][i]
          let rhs = transform(c, newTupleAccess(c.graph, tmp, i))
          result.add(asgnTo(lhs, rhs))
      else:
        for i in 0..<c.transCon.forStmt[0].len-1:
          let lhs = c.transCon.forStmt[0][i]
          let rhs = transform(c, newTupleAccess(c.graph, e, i))
          result.add(asgnTo(lhs, rhs))
    else:
      let lhs = c.transCon.forStmt[0]
      let rhs = transform(c, e)
      result.add(asgnTo(lhs, rhs))


  # bug #23536; note that the info of forLoopBody should't change
  for idx in 0 ..< result.len:
    var changeNode = result[idx]
    changeNode.info = c.transCon.forStmt.info
    for i, child in changeNode:
      child.info = changeNode.info

  inc(c.transCon.yieldStmts)
  if c.transCon.yieldStmts <= 1:
    # common case
    result.add(c.transCon.forLoopBody)
  else:
    # we need to introduce new local variables:
    c.isIntroducingNewLocalVars = true # don't transform yields when introducing new local vars
    result.add(introduceNewLocalVars(c, c.transCon.forLoopBody))
    c.isIntroducingNewLocalVars = false

proc transformAddrDeref(c: PTransf, n: PNode, kinds: TNodeKinds, isAddr = false): PNode =
  result = transformSons(c, n, noConstFold = isAddr)
  # inlining of 'var openarray' iterators; bug #19977
  if n.typ.kind != tyOpenArray and (c.graph.config.backend == backendCpp or sfCompileToCpp in c.module.flags): return
  var n = result
  case n[0].kind
  of nkObjUpConv, nkObjDownConv, nkChckRange, nkChckRangeF, nkChckRange64:
    var m = n[0][0]
    if m.kind in kinds:
      # addr ( nkConv ( deref ( x ) ) ) --> nkConv(x)
      n[0][0] = m[0]
      result = n[0]
      if n.typ.skipTypes(abstractVar).kind != tyOpenArray:
        result.typ() = n.typ
      elif n.typ.skipTypes(abstractInst).kind in {tyVar}:
        result.typ() = toVar(result.typ, n.typ.skipTypes(abstractInst).kind, c.idgen)
  of nkHiddenStdConv, nkHiddenSubConv, nkConv:
    var m = n[0][1]
    if m.kind in kinds:
      # addr ( nkConv ( deref ( x ) ) ) --> nkConv(x)
      n[0][1] = m[0]
      result = n[0]
      if n.typ.skipTypes(abstractVar).kind != tyOpenArray:
        result.typ() = n.typ
      elif n.typ.skipTypes(abstractInst).kind in {tyVar}:
        result.typ() = toVar(result.typ, n.typ.skipTypes(abstractInst).kind, c.idgen)
  else:
    if n[0].kind in kinds and
        not (n[0][0].kind == nkSym and n[0][0].sym.kind == skForVar and
          n[0][0].typ.skipTypes(abstractVar).kind == tyTuple
        ) and not (n[0][0].kind == nkSym and n[0][0].sym.kind == skParam and
          n.typ.kind == tyVar and
          n.typ.skipTypes(abstractVar).kind == tyOpenArray and
          n[0][0].typ.skipTypes(abstractVar).kind == tyString) and
          not (isAddr and n.typ.kind == tyVar and n[0][0].typ.kind == tyRef and
              n[0][0].kind == nkObjConstr)
        : # elimination is harmful to `for tuple unpack` because of newTupleAccess
          # it is also harmful to openArrayLoc (var openArray) for strings
      # addr ( deref ( x )) --> x
      result = n[0][0]
      if n.typ.skipTypes(abstractVar).kind != tyOpenArray:
        result.typ() = n.typ

proc generateThunk(c: PTransf; prc: PNode, dest: PType): PNode =
  ## Converts 'prc' into '(thunk, nil)' so that it's compatible with
  ## a closure.

  # we cannot generate a proper thunk here for GC-safety reasons
  # (see internal documentation):
  if jsNoLambdaLifting in c.graph.config.legacyFeatures and c.graph.config.backend == backendJs: return prc
  result = newNodeIT(nkClosure, prc.info, dest)
  var conv = newNodeIT(nkHiddenSubConv, prc.info, dest)
  conv.add(newNodeI(nkEmpty, prc.info))
  conv.add(prc)
  if prc.kind == nkClosure:
    internalError(c.graph.config, prc.info, "closure to closure created")
  result.add(conv)
  result.add(newNodeIT(nkNilLit, prc.info, getSysType(c.graph, prc.info, tyNil)))

proc transformConv(c: PTransf, n: PNode): PNode =
  # numeric types need range checks:
  var dest = skipTypes(n.typ, abstractVarRange)
  var source = skipTypes(n[1].typ, abstractVarRange)
  case dest.kind
  of tyInt..tyInt64, tyEnum, tyChar, tyUInt8..tyUInt32:
    # we don't include uint and uint64 here as these are no ordinal types ;-)
    if not isOrdinalType(source):
      # float -> int conversions. ugh.
      result = transformSons(c, n)
    elif firstOrd(c.graph.config, n.typ) <= firstOrd(c.graph.config, n[1].typ) and
        lastOrd(c.graph.config, n[1].typ) <= lastOrd(c.graph.config, n.typ):
      # BUGFIX: simply leave n as it is; we need a nkConv node,
      # but no range check:
      result = transformSons(c, n)
    else:
      # generate a range check:
      if dest.kind == tyInt64 or source.kind == tyInt64:
        result = newTransNode(nkChckRange64, n, 3)
      else:
        result = newTransNode(nkChckRange, n, 3)
      dest = skipTypes(n.typ, abstractVar)
      result[0] = transform(c, n[1])
      result[1] = newIntTypeNode(firstOrd(c.graph.config, dest), dest)
      result[2] = newIntTypeNode(lastOrd(c.graph.config, dest), dest)
  of tyFloat..tyFloat128:
    # XXX int64 -> float conversion?
    if skipTypes(n.typ, abstractVar).kind == tyRange:
      result = newTransNode(nkChckRangeF, n, 3)
      dest = skipTypes(n.typ, abstractVar)
      result[0] = transform(c, n[1])
      result[1] = copyTree(dest.n[0])
      result[2] = copyTree(dest.n[1])
    else:
      result = transformSons(c, n)
  of tyOpenArray, tyVarargs:
    if keepOpenArrayConversions in c.flags:
      result = transformSons(c, n)
    else:
      result = transform(c, n[1])
      #result = transformSons(c, n)
      result.typ() = takeType(n.typ, n[1].typ, c.graph, c.idgen)
      #echo n.info, " came here and produced ", typeToString(result.typ),
      #   " from ", typeToString(n.typ), " and ", typeToString(n[1].typ)
  of tyCstring:
    if source.kind == tyString:
      result = newTransNode(nkStringToCString, n, 1)
      result[0] = transform(c, n[1])
    else:
      result = transformSons(c, n)
  of tyString:
    if source.kind == tyCstring:
      result = newTransNode(nkCStringToString, n, 1)
      result[0] = transform(c, n[1])
    else:
      result = transformSons(c, n)
  of tyRef, tyPtr:
    dest = skipTypes(dest, abstractPtrs)
    source = skipTypes(source, abstractPtrs)
    if source.kind == tyObject:
      var diff = inheritanceDiff(dest, source)
      if diff < 0:
        result = newTransNode(nkObjUpConv, n, 1)
        result[0] = transform(c, n[1])
      elif diff > 0 and diff != high(int):
        result = newTransNode(nkObjDownConv, n, 1)
        result[0] = transform(c, n[1])
      else:
        result = transform(c, n[1])
        result.typ() = n.typ
    else:
      result = transformSons(c, n)
  of tyObject:
    var diff = inheritanceDiff(dest, source)
    if diff < 0:
      result = newTransNode(nkObjUpConv, n, 1)
      result[0] = transform(c, n[1])
    elif diff > 0 and diff != high(int):
      result = newTransNode(nkObjDownConv, n, 1)
      result[0] = transform(c, n[1])
    else:
      result = transform(c, n[1])
      result.typ() = n.typ
  of tyGenericParam, tyOrdinal:
    result = transform(c, n[1])
    # happens sometimes for generated assignments, etc.
  of tyProc:
    result = transformSons(c, n)
    if dest.callConv == ccClosure and source.callConv == ccNimCall:
      result = generateThunk(c, result[1], dest)
  else:
    result = transformSons(c, n)

type
  TPutArgInto = enum
    paDirectMapping, paFastAsgn, paFastAsgnTakeTypeFromArg
    paVarAsgn, paComplexOpenarray, paViaIndirection

proc putArgInto(arg: PNode, formal: PType): TPutArgInto =
  # This analyses how to treat the mapping "formal <-> arg" in an
  # inline context.
  if formal.kind == tyTypeDesc: return paDirectMapping
  if skipTypes(formal, abstractInst).kind in {tyOpenArray, tyVarargs}:
    case arg.kind
    of nkStmtListExpr:
      return paComplexOpenarray
    of nkCall:
      if skipTypes(arg.typ, abstractInst).kind in {tyOpenArray, tyVarargs}:
        # XXX incorrect, causes #13417 when `arg` has side effects.
        return paDirectMapping
      else:
        return paComplexOpenarray
    of nkBracket:
      return paFastAsgnTakeTypeFromArg
    else:
      # XXX incorrect, causes #13417 when `arg` has side effects.
      return paDirectMapping
  case arg.kind
  of nkEmpty..nkNilLit:
    result = paDirectMapping
  of nkDotExpr, nkDerefExpr, nkHiddenDeref:
    result = putArgInto(arg[0], formal)
  of nkAddr, nkHiddenAddr:
    result = putArgInto(arg[0], formal)
    if result == paViaIndirection: result = paFastAsgn
  of nkCurly, nkBracket:
    for i in 0..<arg.len:
      if putArgInto(arg[i], formal) != paDirectMapping:
        return paFastAsgn
    result = paDirectMapping
  of nkPar, nkTupleConstr, nkObjConstr:
    for i in 0..<arg.len:
      let a = if arg[i].kind == nkExprColonExpr: arg[i][1]
              else: arg[0]
      if putArgInto(a, formal) != paDirectMapping:
        return paFastAsgn
    result = paDirectMapping
  of nkBracketExpr:
    if skipTypes(formal, abstractInst).kind in {tyVar, tyLent}: result = paVarAsgn
    else: result = paViaIndirection
  else:
    if skipTypes(formal, abstractInst).kind in {tyVar, tyLent}: result = paVarAsgn
    else: result = paFastAsgn

proc findWrongOwners(c: PTransf, n: PNode) =
  if n.kind == nkVarSection:
    let x = n[0][0]
    if x.kind == nkSym and x.sym.owner != getCurrOwner(c):
      internalError(c.graph.config, x.info, "bah " & x.sym.name.s & " " &
        x.sym.owner.name.s & " " & getCurrOwner(c).name.s)
  else:
    for i in 0..<n.safeLen: findWrongOwners(c, n[i])

proc isSimpleIteratorVar(c: PTransf; iter: PSym; call: PNode; owner: PSym): bool =
  proc rec(n: PNode; owner: PSym; dangerousYields: var int) =
    case n.kind
    of nkEmpty..nkNilLit: discard
    of nkYieldStmt:
      if n[0].kind == nkSym and n[0].sym.owner == owner:
        discard "good: yield a single variable that we own"
      else:
        inc dangerousYields
    else:
      for c in n: rec(c, owner, dangerousYields)

  proc recSym(n: PNode; owner: PSym; sameOwner: var bool) =
    case n.kind
    of {nkEmpty..nkNilLit} - {nkSym}: discard
    of nkSym:
      if n.sym.owner != owner:
        sameOwner = false
    else:
      for c in n: recSym(c, owner, sameOwner)

  var dangerousYields = 0
  rec(getBody(c.graph, iter), iter, dangerousYields)
  result = dangerousYields == 0
  # the parameters should be owned by the owner
  # bug #22237
  for i in 1..<call.len:
    recSym(call[i], owner, result)

template destructor(t: PType): PSym = getAttachedOp(c.graph, t, attachedDestructor)

proc transformFor(c: PTransf, n: PNode): PNode =
  # generate access statements for the parameters (unless they are constant)
  # put mapping from formal parameters to actual parameters
  if n.kind != nkForStmt: internalError(c.graph.config, n.info, "transformFor")

  var call = n[^2]

  let labl = newLabel(c, n)
  result = newTransNode(nkBlockStmt, n.info, 2)
  result[0] = newSymNode(labl)
  if call.typ.isNil:
    # see bug #3051
    result[1] = newNode(nkEmpty)
    return result
  c.breakSyms.add(labl)
  if call.kind notin nkCallKinds or call[0].kind != nkSym or
      call[0].typ.skipTypes(abstractInst).callConv == ccClosure:
    result[1] = n
    result[1][^1] = transformLoopBody(c, n[^1])
    result[1][^2] = transform(c, n[^2])
    result[1] = lambdalifting.liftForLoop(c.graph, result[1], c.idgen, getCurrOwner(c))
    discard c.breakSyms.pop
    return result

  #echo "transforming: ", renderTree(n)
  var stmtList = newTransNode(nkStmtList, n.info, 0)
  result[1] = stmtList

  var loopBody = transformLoopBody(c, n[^1])

  discard c.breakSyms.pop

  let iter = call[0].sym

  var v = newNodeI(nkVarSection, n.info)
  for i in 0..<n.len - 2:
    if n[i].kind == nkVarTuple:
      for j in 0..<n[i].len-1:
        addVar(v, copyTree(n[i][j])) # declare new vars
    else:
      if n[i].kind == nkSym and isSimpleIteratorVar(c, iter, call, n[i].sym.owner):
        incl n[i].sym.flags, sfCursor
      addVar(v, copyTree(n[i])) # declare new vars
  stmtList.add(v)


  # Bugfix: inlined locals belong to the invoking routine, not to the invoked
  # iterator!
  var newC = newTransCon(getCurrOwner(c))
  newC.forStmt = n
  newC.forLoopBody = loopBody
  # this can fail for 'nimsuggest' and 'check':
  if iter.kind != skIterator: return result
  # generate access statements for the parameters (unless they are constant)
  pushTransCon(c, newC)
  for i in 1..<call.len:
    var arg = transform(c, call[i])
    let ff = skipTypes(iter.typ, abstractInst)
    # can happen for 'nim check':
    if i >= ff.n.len: return result
    var formal = ff.n[i].sym
    let pa = putArgInto(arg, formal.typ)
    case pa
    of paDirectMapping:
      newC.mapping[formal.itemId] = arg
    of paFastAsgn, paFastAsgnTakeTypeFromArg:
      var t = formal.typ
      if pa == paFastAsgnTakeTypeFromArg:
        t = arg.typ
      elif formal.ast != nil and formal.ast.typ.destructor != nil and t.destructor == nil:
        t = formal.ast.typ # better use the type that actually has a destructor.
      elif t.destructor == nil and arg.typ.destructor != nil:
        t = arg.typ
      # generate a temporary and produce an assignment statement:
      var temp = newTemp(c, t, formal.info)
      #incl(temp.sym.flags, sfCursor)
      addVar(v, temp)
      stmtList.add(newAsgnStmt(c, nkFastAsgn, temp, arg, true))
      newC.mapping[formal.itemId] = temp
    of paVarAsgn:
      assert(skipTypes(formal.typ, abstractInst).kind in {tyVar, tyLent})
      newC.mapping[formal.itemId] = arg
      # XXX BUG still not correct if the arg has a side effect!
    of paViaIndirection:
      let t = formal.typ
      let vt = makeVarType(t.owner, t, c.idgen)
      vt.flags.incl tfVarIsPtr
      var temp = newTemp(c, vt, formal.info)
      addVar(v, temp)
      var addrExp = newNodeIT(nkHiddenAddr, formal.info, makeVarType(t.owner, t, c.idgen, tyPtr))
      addrExp.add(arg)
      stmtList.add(newAsgnStmt(c, nkFastAsgn, temp, addrExp, true))
      newC.mapping[formal.itemId] = newDeref(temp)
    of paComplexOpenarray:
      # XXX arrays will deep copy here (pretty bad).
      var temp = newTemp(c, arg.typ, formal.info)
      addVar(v, temp)
      stmtList.add(newAsgnStmt(c, nkFastAsgn, temp, arg, true))
      newC.mapping[formal.itemId] = temp

  let body = transformBody(c.graph, c.idgen, iter, {useCache}+c.flags)
  pushInfoContext(c.graph.config, n.info)
  inc(c.inlining)
  stmtList.add(transform(c, body))
  #findWrongOwners(c, stmtList.PNode)
  dec(c.inlining)
  popInfoContext(c.graph.config)
  popTransCon(c)
  # echo "transformed: ", stmtList.renderTree

proc transformCase(c: PTransf, n: PNode): PNode =
  # removes `elif` branches of a case stmt
  # adds ``else: nil`` if needed for the code generator
  result = newTransNode(nkCaseStmt, n, 0)
  var ifs: PNode = nil
  for it in n:
    var e = transform(c, it)
    case it.kind
    of nkElifBranch:
      if ifs == nil:
        # Generate the right node depending on whether `n` is used as a stmt or
        # as an expr
        let kind = if n.typ != nil: nkIfExpr else: nkIfStmt
        ifs = newTransNode(kind, it.info, 0)
        ifs.typ() = n.typ
      ifs.add(e)
    of nkElse:
      if ifs == nil: result.add(e)
      else: ifs.add(e)
    else:
      result.add(e)
  if ifs != nil:
    var elseBranch = newTransNode(nkElse, n.info, 1)
    elseBranch[0] = ifs
    result.add(elseBranch)
  elif result.lastSon.kind != nkElse and not (
      skipTypes(n[0].typ, abstractVarRange).kind in
        {tyInt..tyInt64, tyChar, tyEnum, tyUInt..tyUInt64}):
    # fix a stupid code gen bug by normalizing:
    var elseBranch = newTransNode(nkElse, n.info, 1)
    elseBranch[0] = newTransNode(nkNilLit, n.info, 0)
    result.add(elseBranch)

proc transformArrayAccess(c: PTransf, n: PNode): PNode =
  # XXX this is really bad; transf should use a proper AST visitor
  if n[0].kind == nkSym and n[0].sym.kind == skType:
    result = n
  else:
    result = transformSons(c, n)
    if n.len >= 2 and result[1].kind in {nkChckRange, nkChckRange64} and
        n[1].kind in {nkHiddenStdConv, nkHiddenSubConv}:
      # implicit conversion, was transformed into range check
      # remove in favor of index check if conversion to array index type
      # has to be done here because the array index type needs to be relaxed
      # i.e. a uint32 index can implicitly convert to range[0..3] but not int
      let arr = skipTypes(n[0].typ, abstractVarRange)
      if arr.kind == tyArray and
          firstOrd(c.graph.config, arr) == getOrdValue(result[1][1]) and
          lastOrd(c.graph.config, arr) == getOrdValue(result[1][2]):
        result[1] = result[1].skipConv

proc getMergeOp(n: PNode): PSym =
  case n.kind
  of nkCall, nkHiddenCallConv, nkCommand, nkInfix, nkPrefix, nkPostfix,
     nkCallStrLit:
    if n[0].kind == nkSym and n[0].sym.magic == mConStrStr:
      result = n[0].sym
    else:
      result = nil
  else: result = nil

proc flattenTreeAux(d, a: PNode, op: PSym) =
  ## Optimizes away the `&` calls in the children nodes and
  ## lifts the leaf nodes to the same level as `op2`.
  let op2 = getMergeOp(a)
  if op2 != nil and
      (op2.id == op.id or op.magic != mNone and op2.magic == op.magic):
    for i in 1..<a.len: flattenTreeAux(d, a[i], op)
  else:
    d.add copyTree(a)

proc flattenTree(root: PNode): PNode =
  let op = getMergeOp(root)
  if op != nil:
    result = copyNode(root)
    result.add copyTree(root[0])
    flattenTreeAux(result, root, op)
  else:
    result = root

proc transformCall(c: PTransf, n: PNode): PNode =
  var n = flattenTree(n)
  let op = getMergeOp(n)
  let magic = getMagic(n)
  if op != nil and op.magic != mNone and n.len >= 3:
    result = newTransNode(nkCall, n, 0)
    result.add(transform(c, n[0]))
    var j = 1
    while j < n.len:
      var a = transform(c, n[j])
      inc(j)
      if isConstExpr(a):
        while (j < n.len):
          let b = transform(c, n[j])
          if not isConstExpr(b): break
          a = evalOp(op.magic, n, a, b, nil, c.idgen, c.graph)
          inc(j)
      result.add(a)
    if result.len == 2: result = result[1]
  elif magic in {mNBindSym, mTypeOf, mRunnableExamples}:
    # for bindSym(myconst) we MUST NOT perform constant folding:
    result = n
  elif magic == mProcCall:
    # but do not change to its dispatcher:
    result = transformSons(c, n[1])
  elif magic == mStrToStr:
    result = transform(c, n[1])
  else:
    let s = transformSons(c, n)
    # bugfix: check after 'transformSons' if it's still a method call:
    # use the dispatcher for the call:
    if s[0].kind == nkSym and s[0].sym.kind == skMethod:
      when false:
        let t = lastSon(s[0].sym.ast)
        if t.kind != nkSym or sfDispatcher notin t.sym.flags:
          methodDef(s[0].sym, false)
      result = methodCall(s, c.graph.config)
    else:
      result = s

proc transformExceptBranch(c: PTransf, n: PNode): PNode =
  if n[0].isInfixAs() and not isImportedException(n[0][1].typ, c.graph.config):
    let excTypeNode = n[0][1]
    let actions = newTransNode(nkStmtListExpr, n[1], 2)
    # Generating `let exc = (excType)(getCurrentException())`
    # -> getCurrentException()
    let excCall = callCodegenProc(c.graph, "getCurrentException")
    # -> (excType)
    let convNode = newTransNode(nkHiddenSubConv, n[1].info, 2)
    convNode[0] = newNodeI(nkEmpty, n.info)
    convNode[1] = excCall
    convNode.typ() = excTypeNode.typ.toRef(c.idgen)
    # -> let exc = ...
    let identDefs = newTransNode(nkIdentDefs, n[1].info, 3)
    identDefs[0] = n[0][2]
    identDefs[1] = newNodeI(nkEmpty, n.info)
    identDefs[2] = convNode

    let letSection = newTransNode(nkLetSection, n[1].info, 1)
    letSection[0] = identDefs
    # Place the let statement and body of the 'except' branch into new stmtList.
    actions[0] = letSection
    actions[1] = transform(c, n[1])
    # Overwrite 'except' branch body with our stmtList.
    result = newTransNode(nkExceptBranch, n[1].info, 2)
    # Replace the `Exception as foobar` with just `Exception`.
    result[0] = transform(c, n[0][1])
    result[1] = actions
  else:
    result = transformSons(c, n)

proc commonOptimizations*(g: ModuleGraph; idgen: IdGenerator; c: PSym, n: PNode): PNode =
  ## Merges adjacent constant expressions of the children of the `&` call into
  ## a single constant expression. It also inlines constant expressions which are not
  ## complex.
  result = n
  for i in 0..<n.safeLen:
    result[i] = commonOptimizations(g, idgen, c, n[i])
  var op = getMergeOp(n)
  if (op != nil) and (op.magic != mNone) and (n.len >= 3):
    result = newNodeIT(nkCall, n.info, n.typ)
    result.add(n[0])
    var args = newNode(nkArgList)
    flattenTreeAux(args, n, op)
    var j = 0
    while j < args.len:
      var a = args[j]
      inc(j)
      if isConstExpr(a):
        while j < args.len:
          let b = args[j]
          if not isConstExpr(b): break
          a = evalOp(op.magic, result, a, b, nil, idgen, g)
          inc(j)
      result.add(a)
    if result.len == 2: result = result[1]
  else:
    var cnst = getConstExpr(c, n, idgen, g)
    # we inline constants if they are not complex constants:
    if cnst != nil and not dontInlineConstant(n, cnst):
      result = cnst
    else:
      result = n

proc transformDerefBlock(c: PTransf, n: PNode): PNode =
  # We transform (block: x)[] to (block: x[])
  let e0 = n[0]
  result = shallowCopy(e0)
  result.typ() = n.typ
  for i in 0 ..< e0.len - 1:
    result[i] = e0[i]
  result[e0.len-1] = newTreeIT(nkHiddenDeref, n.info, n.typ, e0[e0.len-1])

proc transform(c: PTransf, n: PNode, noConstFold = false): PNode =
  when false:
    var oldDeferAnchor: PNode
    if n.kind in {nkElifBranch, nkOfBranch, nkExceptBranch, nkElifExpr,
                  nkElseExpr, nkElse, nkForStmt, nkWhileStmt, nkFinally,
                  nkBlockStmt, nkBlockExpr}:
      oldDeferAnchor = c.deferAnchor
      c.deferAnchor = n
  case n.kind
  of nkSym:
    result = transformSym(c, n)
  of nkEmpty..pred(nkSym), succ(nkSym)..nkNilLit, nkComesFrom:
    # nothing to be done for leaves:
    result = n
  of nkBracketExpr: result = transformArrayAccess(c, n)
  of procDefs:
    var s = n[namePos].sym
    if n.typ != nil and s.typ.callConv == ccClosure:
      result = transformSym(c, n[namePos])
      # use the same node as before if still a symbol:
      if result.kind == nkSym: result = n
    else:
      result = n
  of nkMacroDef:
    # XXX no proper closure support yet:
    when false:
      if n[genericParamsPos].kind == nkEmpty:
        var s = n[namePos].sym
        n[bodyPos] = transform(c, s.getBody)
        if n.kind == nkMethodDef: methodDef(s, false)
    result = n
  of nkForStmt:
    result = transformFor(c, n)
  of nkParForStmt:
    result = transformSons(c, n)
  of nkCaseStmt:
    result = transformCase(c, n)
  of nkWhileStmt: result = transformWhile(c, n)
  of nkBlockStmt, nkBlockExpr:
    result = transformBlock(c, n)
  of nkDefer:
    c.deferDetected = true
    result = transformSons(c, n)
    when false:
      let deferPart = newNodeI(nkFinally, n.info)
      deferPart.add n[0]
      let tryStmt = newNodeI(nkTryStmt, n.info)
      if c.deferAnchor.isNil:
        tryStmt.add c.root
        c.root = tryStmt
        result = tryStmt
      else:
        # modify the corresponding *action*, don't rely on nkStmtList:
        tryStmt.add c.deferAnchor[^1]
        c.deferAnchor[^1] = tryStmt
        result = newTransNode(nkCommentStmt, n.info, 0)
      tryStmt.add deferPart
      # disable the original 'defer' statement:
      n.kind = nkEmpty
  of nkContinueStmt:
    result = newNodeI(nkBreakStmt, n.info)
    var labl = c.contSyms[c.contSyms.high]
    result.add(newSymNode(labl))
  of nkBreakStmt: result = transformBreak(c, n)
  of nkCallKinds:
    result = transformCall(c, n)
  of nkAddr, nkHiddenAddr:
    result = transformAddrDeref(c, n, {nkDerefExpr, nkHiddenDeref}, isAddr = true)
  of nkDerefExpr:
    result = transformAddrDeref(c, n, {nkAddr, nkHiddenAddr})
  of nkHiddenDeref:
    if n[0].kind in {nkBlockExpr, nkBlockStmt}:
      # bug #20107 bug #21540. Watch out to not deref the pointer too late.
      let e = transformDerefBlock(c, n)
      result = transformBlock(c, e)
    else:
      result = transformAddrDeref(c, n, {nkAddr, nkHiddenAddr})
  of nkHiddenStdConv, nkHiddenSubConv, nkConv:
    result = transformConv(c, n)
  of nkDiscardStmt:
    result = n
    if n[0].kind != nkEmpty:
      result = transformSons(c, n)
      if isConstExpr(result[0]):
        # ensure that e.g. discard "some comment" gets optimized away
        # completely:
        result = newNode(nkCommentStmt)
  of nkCommentStmt, nkTemplateDef, nkImportStmt, nkStaticStmt,
      nkExportStmt, nkExportExceptStmt:
    return n
  of nkConstSection:
    # do not replace ``const c = 3`` with ``const 3 = 3``
    return transformConstSection(c, n)
  of nkTypeSection, nkTypeOfExpr, nkMixinStmt, nkBindStmt:
    # no need to transform type sections:
    return n
  of nkVarSection, nkLetSection:
    if c.inlining > 0:
      # we need to copy the variables for multiple yield statements:
      result = transformVarSection(c, n)
    else:
      result = transformSons(c, n)
  of nkYieldStmt:
    if c.inlining > 0 and not c.isIntroducingNewLocalVars:
      result = transformYield(c, n)
    else:
      result = transformSons(c, n)
  of nkAsgn:
    result = transformAsgn(c, n)
  of nkIdentDefs, nkConstDef:
    result = newTransNode(n)
    result[0] = transform(c, skipPragmaExpr(n[0]))
    # Skip the second son since it only contains an unsemanticized copy of the
    # variable type used by docgen
    let last = n.len-1
    for i in 1..<last: result[i] = n[i]
    result[last] = transform(c, n[last])
    # XXX comment handling really sucks:
    if importantComments(c.graph.config):
      result.comment = n.comment
  of nkClosure:
    # it can happen that for-loop-inlining produced a fresh
    # set of variables, including some computed environment
    # (bug #2604). We need to patch this environment here too:
    let a = n[1]
    if a.kind == nkSym:
      result = copyTree(n)
      result[1] = transformSymAux(c, a)
    else:
      result = n
  of nkExceptBranch:
    result = transformExceptBranch(c, n)
  of nkCheckedFieldExpr:
    result = transformSons(c, n)
    if result[0].kind != nkDotExpr:
      # simplfied beyond a dot expression --> simplify further.
      result = result[0]
  else:
    result = transformSons(c, n)
  when false:
    if oldDeferAnchor != nil: c.deferAnchor = oldDeferAnchor

  # Constants can be inlined here, but only if they cannot result in a cast
  # in the back-end (e.g. var p: pointer = someProc)
  let exprIsPointerCast = n.kind in {nkCast, nkConv, nkHiddenStdConv} and
                          n.typ != nil and
                          n.typ.kind == tyPointer
  if not exprIsPointerCast and not noConstFold:
    var cnst = getConstExpr(c.module, result, c.idgen, c.graph)
    # we inline constants if they are not complex constants:
    if cnst != nil and not dontInlineConstant(n, cnst):
      result = cnst # do not miss an optimization

proc processTransf(c: PTransf, n: PNode, owner: PSym): PNode =
  # Note: For interactive mode we cannot call 'passes.skipCodegen' and skip
  # this step! We have to rely that the semantic pass transforms too errornous
  # nodes into an empty node.
  if nfTransf in n.flags: return n
  pushTransCon(c, newTransCon(owner))
  result = transform(c, n)
  popTransCon(c)
  incl(result.flags, nfTransf)

proc openTransf(g: ModuleGraph; module: PSym, filename: string; idgen: IdGenerator; flags: TransformFlags): PTransf =
  result = PTransf(module: module, graph: g, idgen: idgen, flags: flags)

proc flattenStmts(n: PNode) =
  var goOn = true
  while goOn:
    goOn = false
    var i = 0
    while i < n.len:
      let it = n[i]
      if it.kind in {nkStmtList, nkStmtListExpr}:
        n.sons[i..i] = it.sons[0..<it.len]
        goOn = true
      inc i

proc liftDeferAux(n: PNode) =
  if n.kind in {nkStmtList, nkStmtListExpr}:
    flattenStmts(n)
    var goOn = true
    while goOn:
      goOn = false
      let last = n.len-1
      for i in 0..last:
        if n[i].kind == nkDefer:
          let deferPart = newNodeI(nkFinally, n[i].info)
          deferPart.add n[i][0]
          var tryStmt = newNodeIT(nkTryStmt, n[i].info, n.typ)
          var body = newNodeIT(n.kind, n[i].info, n.typ)
          if i < last:
            body.sons = n.sons[(i+1)..last]
          tryStmt.add body
          tryStmt.add deferPart
          n[i] = tryStmt
          n.sons.setLen(i+1)
          n.typ() = tryStmt.typ
          goOn = true
          break
  for i in 0..n.safeLen-1:
    liftDeferAux(n[i])

template liftDefer(c, root) =
  if c.deferDetected:
    liftDeferAux(root)

proc transformBody*(g: ModuleGraph; idgen: IdGenerator; prc: PSym; flags: TransformFlags): PNode =
  assert prc.kind in routineKinds

  if prc.transformedBody != nil:
    result = prc.transformedBody
  elif nfTransf in getBody(g, prc).flags or prc.kind in {skTemplate}:
    result = getBody(g, prc)
  else:
    prc.transformedBody = newNode(nkEmpty) # protects from recursion
    var c = openTransf(g, prc.getModule, "", idgen, flags)
    result = liftLambdas(g, prc, getBody(g, prc), c.tooEarly, c.idgen, flags)
    result = processTransf(c, result, prc)
    liftDefer(c, result)
    result = liftLocalsIfRequested(prc, result, g.cache, g.config, c.idgen)

    if prc.isIterator:
      result = g.transformClosureIterator(c.idgen, prc, result)

    incl(result.flags, nfTransf)

    if useCache in flags or prc.typ.callConv == ccInline:
      # genProc for inline procs will be called multiple times from different modules,
      # it is important to transform exactly once to get sym ids and locations right
      prc.transformedBody = result
    else:
      prc.transformedBody = nil
    # XXX Rodfile support for transformedBody!

  #if prc.name.s == "main":
  #  echo "transformed into ", renderTree(result, {renderIds})

proc transformStmt*(g: ModuleGraph; idgen: IdGenerator; module: PSym, n: PNode; flags: TransformFlags = {}): PNode =
  if nfTransf in n.flags:
    result = n
  else:
    var c = openTransf(g, module, "", idgen, flags)
    result = processTransf(c, n, module)
    liftDefer(c, result)
    #result = liftLambdasForTopLevel(module, result)
    incl(result.flags, nfTransf)

proc transformExpr*(g: ModuleGraph; idgen: IdGenerator; module: PSym, n: PNode; flags: TransformFlags = {}): PNode =
  if nfTransf in n.flags:
    result = n
  else:
    var c = openTransf(g, module, "", idgen, flags)
    result = processTransf(c, n, module)
    liftDefer(c, result)
    # expressions are not to be injected with destructor calls as that
    # the list of top level statements needs to be collected before.
    incl(result.flags, nfTransf)

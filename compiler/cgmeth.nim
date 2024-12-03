#
#
#           The Nim Compiler
#        (c) Copyright 2013 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements code generation for methods.

import
  options, ast, msgs, idents, renderer, types, magicsys,
  sempass2, modulegraphs, lineinfos, astalgo

import std/intsets

when defined(nimPreviewSlimSystem):
  import std/assertions

import std/[tables]

proc genConv(n: PNode, d: PType, downcast: bool; conf: ConfigRef): PNode =
  var dest = skipTypes(d, abstractPtrs)
  var source = skipTypes(n.typ, abstractPtrs)
  if (source.kind == tyObject) and (dest.kind == tyObject):
    var diff = inheritanceDiff(dest, source)
    if diff == high(int):
      # no subtype relation, nothing to do
      result = n
    elif diff < 0:
      result = newNodeIT(nkObjUpConv, n.info, d)
      result.add n
      if downcast: internalError(conf, n.info, "cgmeth.genConv: no upcast allowed")
    elif diff > 0:
      result = newNodeIT(nkObjDownConv, n.info, d)
      result.add n
      if not downcast:
        internalError(conf, n.info, "cgmeth.genConv: no downcast allowed")
    else:
      result = n
  else:
    result = n

proc getDispatcher*(s: PSym): PSym =
  ## can return nil if is has no dispatcher.
  if dispatcherPos < s.ast.len:
    result = s.ast[dispatcherPos].sym
    doAssert sfDispatcher in result.flags
  else:
    result = nil

proc methodCall*(n: PNode; conf: ConfigRef): PNode =
  result = n
  # replace ordinary method by dispatcher method:
  let disp = getDispatcher(result[0].sym)
  if disp != nil:
    result[0].typ() = disp.typ
    result[0].sym = disp
    # change the arguments to up/downcasts to fit the dispatcher's parameters:
    for i in 1..<result.len:
      result[i] = genConv(result[i], disp.typ[i], true, conf)
  else:
    localError(conf, n.info, "'" & $result[0] & "' lacks a dispatcher")

type
  MethodResult = enum No, Invalid, Yes

proc sameMethodBucket(a, b: PSym; multiMethods: bool): MethodResult =
  result = No
  if a.name.id != b.name.id: return
  if a.typ.signatureLen != b.typ.signatureLen:
    return

  var i = 0
  for x, y in paramTypePairs(a.typ, b.typ):
    inc i
    var aa = x
    var bb = y
    while true:
      aa = skipTypes(aa, {tyGenericInst, tyAlias})
      bb = skipTypes(bb, {tyGenericInst, tyAlias})
      if aa.kind == bb.kind and aa.kind in {tyVar, tyPtr, tyRef, tyLent, tySink}:
        aa = aa.elementType
        bb = bb.elementType
      else:
        break
    if sameType(x, y):
      if aa.kind == tyObject and result != Invalid:
        result = Yes
    elif aa.kind == tyObject and bb.kind == tyObject and (i == 1 or multiMethods):
      let diff = inheritanceDiff(bb, aa)
      if diff < 0:
        if result != Invalid:
          result = Yes
        else:
          return No
      elif diff != high(int) and sfFromGeneric notin (a.flags+b.flags):
        result = Invalid
      else:
        return No
    else:
      return No
  if result == Yes:
    # check for return type:
    # ignore flags of return types; # bug #22673
    if not sameTypeOrNil(a.typ.returnType, b.typ.returnType, {IgnoreFlags}):
      if b.typ.returnType != nil and b.typ.returnType.kind == tyUntyped:
        # infer 'auto' from the base to make it consistent:
        b.typ.setReturnType a.typ.returnType
      else:
        return No

proc attachDispatcher(s: PSym, dispatcher: PNode) =
  if dispatcherPos < s.ast.len:
    # we've added a dispatcher already, so overwrite it
    s.ast[dispatcherPos] = dispatcher
  else:
    setLen(s.ast.sons, dispatcherPos+1)
    if s.ast[resultPos] == nil:
      s.ast[resultPos] = newNodeI(nkEmpty, s.info)
    s.ast[dispatcherPos] = dispatcher

proc createDispatcher(s: PSym; g: ModuleGraph; idgen: IdGenerator): PSym =
  var disp = copySym(s, idgen)
  incl(disp.flags, sfDispatcher)
  excl(disp.flags, sfExported)
  let old = disp.typ
  disp.typ = copyType(disp.typ, idgen, disp.typ.owner)
  copyTypeProps(g, idgen.module, disp.typ, old)

  # we can't inline the dispatcher itself (for now):
  if disp.typ.callConv == ccInline: disp.typ.callConv = ccNimCall
  disp.ast = copyTree(s.ast)
  disp.ast[bodyPos] = newNodeI(nkEmpty, s.info)
  disp.loc.snippet = ""
  if s.typ.returnType != nil:
    if disp.ast.len > resultPos:
      disp.ast[resultPos].sym = copySym(s.ast[resultPos].sym, idgen)
    else:
      # We've encountered a method prototype without a filled-in
      # resultPos slot. We put a placeholder in there that will
      # be updated in fixupDispatcher().
      disp.ast.add newNodeI(nkEmpty, s.info)
  attachDispatcher(s, newSymNode(disp))
  # attach to itself to prevent bugs:
  attachDispatcher(disp, newSymNode(disp))
  return disp

proc fixupDispatcher(meth, disp: PSym; conf: ConfigRef) =
  # We may have constructed the dispatcher from a method prototype
  # and need to augment the incomplete dispatcher with information
  # from later definitions, particularly the resultPos slot. Also,
  # the lock level of the dispatcher needs to be updated/checked
  # against that of the method.
  if disp.ast.len > resultPos and meth.ast.len > resultPos and
     disp.ast[resultPos].kind == nkEmpty:
    disp.ast[resultPos] = copyTree(meth.ast[resultPos])

proc methodDef*(g: ModuleGraph; idgen: IdGenerator; s: PSym) =
  var witness: PSym = nil
  if s.typ.firstParamType.owner.getModule != s.getModule and vtables in g.config.features and not
      g.config.isDefined("nimInternalNonVtablesTesting"):
    localError(g.config, s.info, errGenerated, "method `" & s.name.s &
          "` can be defined only in the same module with its type (" & s.typ.firstParamType.typeToString() & ")")
  if sfImportc in s.flags:
    localError(g.config, s.info, errGenerated, "method `" & s.name.s &
          "` is not allowed to have 'importc' pragmas")

  for i in 0..<g.methods.len:
    let disp = g.methods[i].dispatcher
    case sameMethodBucket(disp, s, multimethods = optMultiMethods in g.config.globalOptions)
    of Yes:
      g.methods[i].methods.add(s)
      attachDispatcher(s, disp.ast[dispatcherPos])
      fixupDispatcher(s, disp, g.config)
      #echo "fixup ", disp.name.s, " ", disp.id
      when useEffectSystem: checkMethodEffects(g, disp, s)
      if {sfBase, sfFromGeneric} * s.flags == {sfBase} and
           g.methods[i].methods[0] != s:
        # already exists due to forwarding definition?
        localError(g.config, s.info, "method is not a base")
      return
    of No: discard
    of Invalid:
      if witness.isNil: witness = g.methods[i].methods[0]
  # create a new dispatcher:
  # stores the id and the position
  if s.typ.firstParamType.skipTypes(skipPtrs).itemId notin g.bucketTable:
    g.bucketTable[s.typ.firstParamType.skipTypes(skipPtrs).itemId] = 1
  else:
    g.bucketTable.inc(s.typ.firstParamType.skipTypes(skipPtrs).itemId)
  g.methods.add((methods: @[s], dispatcher: createDispatcher(s, g, idgen)))
  #echo "adding ", s.info
  if witness != nil:
    localError(g.config, s.info, "invalid declaration order; cannot attach '" & s.name.s &
                       "' to method defined here: " & g.config$witness.info)
  elif sfBase notin s.flags:
    message(g.config, s.info, warnUseBase)

proc relevantCol*(methods: seq[PSym], col: int): bool =
  # returns true iff the position is relevant
  result = false
  var t = methods[0].typ[col].skipTypes(skipPtrs)
  if t.kind == tyObject:
    for i in 1..high(methods):
      let t2 = skipTypes(methods[i].typ[col], skipPtrs)
      if not sameType(t2, t):
        return true

proc cmpSignatures(a, b: PSym, relevantCols: IntSet): int =
  result = 0
  for col in FirstParamAt..<a.typ.signatureLen:
    if contains(relevantCols, col):
      var aa = skipTypes(a.typ[col], skipPtrs)
      var bb = skipTypes(b.typ[col], skipPtrs)
      var d = inheritanceDiff(aa, bb)
      if (d != high(int)) and d != 0:
        return d

proc sortBucket*(a: var seq[PSym], relevantCols: IntSet) =
  # we use shellsort here; fast and simple
  var n = a.len
  var h = 1
  while true:
    h = 3 * h + 1
    if h > n: break
  while true:
    h = h div 3
    for i in h..<n:
      var v = a[i]
      var j = i
      while cmpSignatures(a[j - h], v, relevantCols) >= 0:
        a[j] = a[j - h]
        j = j - h
        if j < h: break
      a[j] = v
    if h == 1: break

proc genIfDispatcher*(g: ModuleGraph; methods: seq[PSym], relevantCols: IntSet; idgen: IdGenerator): PSym =
  var base = methods[0].ast[dispatcherPos].sym
  result = base
  var paramLen = base.typ.signatureLen
  var nilchecks = newNodeI(nkStmtList, base.info)
  var disp = newNodeI(nkIfStmt, base.info)
  var ands = getSysMagic(g, unknownLineInfo, "and", mAnd)
  var iss = getSysMagic(g, unknownLineInfo, "of", mOf)
  let boolType = getSysType(g, unknownLineInfo, tyBool)
  for col in FirstParamAt..<paramLen:
    if contains(relevantCols, col):
      let param = base.typ.n[col].sym
      if param.typ.skipTypes(abstractInst).kind in {tyRef, tyPtr}:
        nilchecks.add newTree(nkCall,
            newSymNode(getCompilerProc(g, "chckNilDisp")), newSymNode(param))
  for meth in 0..high(methods):
    var curr = methods[meth]      # generate condition:
    var cond: PNode = nil
    for col in FirstParamAt..<paramLen:
      if contains(relevantCols, col):
        var isn = newNodeIT(nkCall, base.info, boolType)
        isn.add newSymNode(iss)
        let param = base.typ.n[col].sym
        isn.add newSymNode(param)
        isn.add newNodeIT(nkType, base.info, curr.typ[col])
        if cond != nil:
          var a = newNodeIT(nkCall, base.info, boolType)
          a.add newSymNode(ands)
          a.add cond
          a.add isn
          cond = a
        else:
          cond = isn
    let retTyp = base.typ.returnType
    let call = newNodeIT(nkCall, base.info, retTyp)
    call.add newSymNode(curr)
    for col in 1..<paramLen:
      call.add genConv(newSymNode(base.typ.n[col].sym),
                           curr.typ[col], false, g.config)
    var ret: PNode
    if retTyp != nil:
      var a = newNodeI(nkFastAsgn, base.info)
      a.add newSymNode(base.ast[resultPos].sym)
      a.add call
      ret = newNodeI(nkReturnStmt, base.info)
      ret.add a
    else:
      ret = call
    if cond != nil:
      var a = newNodeI(nkElifBranch, base.info)
      a.add cond
      a.add ret
      disp.add a
    else:
      disp = ret
  nilchecks.add disp
  nilchecks.flags.incl nfTransf # should not be further transformed
  result.ast[bodyPos] = nilchecks

proc generateIfMethodDispatchers*(g: ModuleGraph, idgen: IdGenerator) =
  for bucket in 0..<g.methods.len:
    var relevantCols = initIntSet()
    for col in FirstParamAt..<g.methods[bucket].methods[0].typ.signatureLen:
      if relevantCol(g.methods[bucket].methods, col): incl(relevantCols, col)
      if optMultiMethods notin g.config.globalOptions:
        # if multi-methods are not enabled, we are interested only in the first field
        break
    sortBucket(g.methods[bucket].methods, relevantCols)
    g.addDispatchers genIfDispatcher(g, g.methods[bucket].methods, relevantCols, idgen)

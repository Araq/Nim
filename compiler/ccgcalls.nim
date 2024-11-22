#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
#
# included from cgen.nim

proc canRaiseDisp(p: BProc; n: PNode): bool =
  # we assume things like sysFatal cannot raise themselves
  if n.kind == nkSym and {sfNeverRaises, sfImportc, sfCompilerProc} * n.sym.flags != {}:
    result = false
  elif optPanics in p.config.globalOptions or
      (n.kind == nkSym and sfSystemModule in getModule(n.sym).flags and
       sfSystemRaisesDefect notin n.sym.flags):
    # we know we can be strict:
    result = canRaise(n)
  else:
    # we have to be *very* conservative:
    result = canRaiseConservative(n)

proc preventNrvo(p: BProc; dest, le, ri: PNode): bool =
  proc locationEscapes(p: BProc; le: PNode; inTryStmt: bool): bool =
    result = false
    var n = le
    while true:
      # do NOT follow nkHiddenDeref here!
      case n.kind
      of nkSym:
        # we don't own the location so it escapes:
        if n.sym.owner != p.prc:
          return true
        elif inTryStmt and sfUsedInFinallyOrExcept in n.sym.flags:
          # it is also an observable store if the location is used
          # in 'except' or 'finally'
          return true
        return false
      of nkDotExpr, nkBracketExpr, nkObjUpConv, nkObjDownConv,
          nkCheckedFieldExpr:
        n = n[0]
      of nkHiddenStdConv, nkHiddenSubConv, nkConv:
        n = n[1]
      else:
        # cannot analyse the location; assume the worst
        return true

  result = false
  if le != nil:
    for i in 1..<ri.len:
      let r = ri[i]
      if isPartOf(le, r) != arNo: return true
    # we use the weaker 'canRaise' here in order to prevent too many
    # annoying warnings, see #14514
    if canRaise(ri[0]) and
        locationEscapes(p, le, p.nestedTryStmts.len > 0):
      message(p.config, le.info, warnObservableStores, $le)
  # bug #19613 prevent dangerous aliasing too:
  if dest != nil and dest != le:
    for i in 1..<ri.len:
      let r = ri[i]
      if isPartOf(dest, r) != arNo: return true

proc hasNoInit(call: PNode): bool {.inline.} =
  result = call[0].kind == nkSym and sfNoInit in call[0].sym.flags

proc isHarmlessStore(p: BProc; canRaise: bool; d: TLoc): bool =
  if d.k in {locTemp, locNone} or not canRaise:
    result = true
  elif d.k == locLocalVar and p.withinTryWithExcept == 0:
    # we cannot observe a store to a local variable if the current proc
    # has no error handler:
    result = true
  else:
    result = false

proc cleanupTemp(p: BProc; returnType: PType, tmp: TLoc): bool =
  if returnType.kind in {tyVar, tyLent}:
    # we don't need to worry about var/lent return types
    result = false
  elif hasDestructor(returnType) and getAttachedOp(p.module.g.graph, returnType, attachedDestructor) != nil:
    let dtor = getAttachedOp(p.module.g.graph, returnType, attachedDestructor)
    var op = initLocExpr(p, newSymNode(dtor))
    var callee = rdLoc(op)
    let destroyArg =
      if dtor.typ.firstParamType.kind == tyVar:
        cAddr(rdLoc(tmp))
      else:
        rdLoc(tmp)
    let destroy = cCall(callee, destroyArg)
    raiseExitCleanup(p, destroy)
    result = true
  else:
    result = false

proc fixupCall(p: BProc, le, ri: PNode, d: var TLoc,
               result: var Builder, call: var CallBuilder) =
  let canRaise = p.config.exc == excGoto and canRaiseDisp(p, ri[0])
  genLineDir(p, ri)
  # getUniqueType() is too expensive here:
  var typ = skipTypes(ri[0].typ, abstractInst)
  if typ.returnType != nil:
    var flags: TAssignmentFlags = {}
    if typ.returnType.kind in {tyOpenArray, tyVarargs}:
      # perhaps generate no temp if the call doesn't have side effects
      flags.incl needTempForOpenArray
    if isInvalidReturnType(p.config, typ):
      # beware of 'result = p(result)'. We may need to allocate a temporary:
      if d.k in {locTemp, locNone} or not preventNrvo(p, d.lode, le, ri):
        # Great, we can use 'd':
        if d.k == locNone: d = getTemp(p, typ.returnType, needsInit=true)
        elif d.k notin {locTemp} and not hasNoInit(ri):
          # reset before pass as 'result' var:
          discard "resetLoc(p, d)"
        let rad = addrLoc(p.config, d)
        result.addArgument(call):
          result.add(rad)
        result.finishCallBuilder(call)
        p.s(cpsStmts).addStmt():
          p.s(cpsStmts).add(extract(result))
      else:
        var tmp: TLoc = getTemp(p, typ.returnType, needsInit=true)
        let ratmp = addrLoc(p.config, tmp)
        result.addArgument(call):
          result.add(ratmp)
        result.finishCallBuilder(call)
        p.s(cpsStmts).addStmt():
          p.s(cpsStmts).add(extract(result))
        genAssignment(p, d, tmp, {}) # no need for deep copying
      if canRaise: raiseExit(p)
    else:
      result.finishCallBuilder(call)
      if p.module.compileToCpp:
        if lfSingleUse in d.flags:
          # do not generate spurious temporaries for C++! For C we're better off
          # with them to prevent undefined behaviour and because the codegen
          # is free to emit expressions multiple times!
          d.k = locCall
          d.snippet = extract(result)
          excl d.flags, lfSingleUse
        else:
          if d.k == locNone and p.splitDecls == 0:
            d = getTempCpp(p, typ.returnType, extract(result))
          else:
            if d.k == locNone: d = getTemp(p, typ.returnType)
            var list = initLoc(locCall, d.lode, OnUnknown)
            list.snippet = extract(result)
            genAssignment(p, d, list, {needAssignCall}) # no need for deep copying
            if canRaise: raiseExit(p)

      elif isHarmlessStore(p, canRaise, d):
        var useTemp = false
        if d.k == locNone:
          useTemp = true
          d = getTemp(p, typ.returnType)
        assert(d.t != nil)        # generate an assignment to d:
        var list = initLoc(locCall, d.lode, OnUnknown)
        list.snippet = extract(result)
        genAssignment(p, d, list, flags+{needAssignCall}) # no need for deep copying
        if canRaise:
          if not (useTemp and cleanupTemp(p, typ.returnType, d)):
            raiseExit(p)
      else:
        var tmp: TLoc = getTemp(p, typ.returnType, needsInit=true)
        var list = initLoc(locCall, d.lode, OnUnknown)
        list.snippet = extract(result)
        genAssignment(p, tmp, list, flags+{needAssignCall}) # no need for deep copying
        if canRaise:
          if not cleanupTemp(p, typ.returnType, tmp):
            raiseExit(p)
        genAssignment(p, d, tmp, {})
  else:
    finishCallBuilder(result, call)
    p.s(cpsStmts).addStmt():
      p.s(cpsStmts).add(extract(result))
    if canRaise: raiseExit(p)

proc genBoundsCheck(p: BProc; arr, a, b: TLoc; arrTyp: PType)

proc reifiedOpenArray(n: PNode): bool {.inline.} =
  var x = n
  while true:
    case x.kind
    of {nkAddr, nkHiddenAddr, nkHiddenDeref}:
      x = x[0]
    of nkHiddenStdConv:
      x = x[1]
    else:
      break
  if x.kind == nkSym and x.sym.kind == skParam:
    result = false
  else:
    result = true

proc genOpenArraySlice(p: BProc; q: PNode; formalType, destType: PType; prepareForMutation = false): (Rope, Rope) =
  var a = initLocExpr(p, q[1])
  var b = initLocExpr(p, q[2])
  var c = initLocExpr(p, q[3])
  # bug #23321: In the function mapType, ptrs (tyPtr, tyVar, tyLent, tyRef)
  # are mapped into ctPtrToArray, the dereference of which is skipped
  # in the `genDeref`. We need to skip these ptrs here
  let ty = skipTypes(a.t, abstractVar+{tyPtr, tyRef})
  # but first produce the required index checks:
  if optBoundsCheck in p.options:
    genBoundsCheck(p, a, b, c, ty)
  if prepareForMutation:
    let bra = byRefLoc(p, a)
    p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "nimPrepareStrMutationV2"),
      bra)
  let dest = getTypeDesc(p.module, destType)
  let ra = rdLoc(a)
  let rb = rdLoc(b)
  let rc = rdLoc(c)
  let lengthExpr = cOp(Add, NimInt, cOp(Sub, NimInt, rc, rb), cIntValue(1))
  case ty.kind
  of tyArray:
    let first = toInt64(firstOrd(p.config, ty))
    if first == 0:
      result = (cCast(ptrType(dest), cOp(Add, NimInt, ra, rb)), lengthExpr)
    else:
      let lit = cIntLiteral(first)
      result = (cCast(ptrType(dest), cOp(Add, NimInt, ra, cOp(Sub, NimInt, rb, lit))), lengthExpr)
  of tyOpenArray, tyVarargs:
    let data = if reifiedOpenArray(q[1]): dotField(ra, "Field0") else: ra
    result = (cCast(ptrType(dest), cOp(Add, NimInt, data, rb)), lengthExpr)
  of tyUncheckedArray, tyCstring:
    result = (cCast(ptrType(dest), cOp(Add, NimInt, ra, rb)), lengthExpr)
  of tyString, tySequence:
    let atyp = skipTypes(a.t, abstractInst)
    if formalType.skipTypes(abstractInst).kind in {tyVar} and atyp.kind == tyString and
        optSeqDestructors in p.config.globalOptions:
      let bra = byRefLoc(p, a)
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "nimPrepareStrMutationV2"),
        bra)
    var val: Snippet
    if atyp.kind in {tyVar} and not compileToCpp(p.module):
      val = cDeref(ra)
    else:
      val = ra
    result = (
      cIfExpr(dataFieldAccessor(p, val),
        cCast(ptrType(dest), cOp(Add, NimInt, dataField(p, val), rb)),
        NimNil),
      lengthExpr)
  else:
    result = ("", "")
    internalError(p.config, "openArrayLoc: " & typeToString(a.t))

proc openArrayLoc(p: BProc, formalType: PType, n: PNode; result: var Builder) =
  var q = skipConv(n)
  var skipped = false
  while q.kind == nkStmtListExpr and q.len > 0:
    skipped = true
    q = q.lastSon
  if getMagic(q) == mSlice:
    # magic: pass slice to openArray:
    if skipped:
      q = skipConv(n)
      while q.kind == nkStmtListExpr and q.len > 0:
        for i in 0..<q.len-1:
          genStmts(p, q[i])
        q = q.lastSon
    let (x, y) = genOpenArraySlice(p, q, formalType, n.typ.elementType)
    result.add(x)
    result.addArgumentSeparator()
    result.add(y)
  else:
    var a = initLocExpr(p, if n.kind == nkHiddenStdConv: n[1] else: n)
    case skipTypes(a.t, abstractVar+{tyStatic}).kind
    of tyOpenArray, tyVarargs:
      let ra = rdLoc(a)
      if reifiedOpenArray(n):
        if a.t.kind in {tyVar, tyLent}:
          result.add(derefField(ra, "Field0"))
          result.addArgumentSeparator()
          result.add(derefField(ra, "Field1"))
        else:
          result.add(dotField(ra, "Field0"))
          result.addArgumentSeparator()
          result.add(dotField(ra, "Field1"))
      else:
        result.add(ra)
        result.addArgumentSeparator()
        result.add(ra & "Len_0")
    of tyString, tySequence:
      let ntyp = skipTypes(n.typ, abstractInst)
      if formalType.skipTypes(abstractInst).kind in {tyVar} and ntyp.kind == tyString and
          optSeqDestructors in p.config.globalOptions:
        let bra = byRefLoc(p, a)
        p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "nimPrepareStrMutationV2"),
          bra)
      if ntyp.kind in {tyVar} and not compileToCpp(p.module):
        let ra = a.rdLoc
        var t = TLoc(snippet: cDeref(ra))
        let lt = lenExpr(p, t)
        result.add(cIfExpr(dataFieldAccessor(p, t.snippet), dataField(p, t.snippet), NimNil))
        result.addArgumentSeparator()
        result.add(lt)
      else:
        let ra = a.rdLoc
        let la = lenExpr(p, a)
        result.add(cIfExpr(dataFieldAccessor(p, ra), dataField(p, ra), NimNil))
        result.addArgumentSeparator()
        result.add(la)
    of tyArray:
      let ra = rdLoc(a)
      result.add(ra)
      result.addArgumentSeparator()
      result.addIntValue(lengthOrd(p.config, a.t))
    of tyPtr, tyRef:
      case elementType(a.t).kind
      of tyString, tySequence:
        let ra = a.rdLoc
        var t = TLoc(snippet: cDeref(ra))
        let lt = lenExpr(p, t)
        result.add(cIfExpr(dataFieldAccessor(p, t.snippet), dataField(p, t.snippet), NimNil))
        result.addArgumentSeparator()
        result.add(lt)
      of tyArray:
        let ra = rdLoc(a)
        result.add(ra)
        result.addArgumentSeparator()
        result.addIntValue(lengthOrd(p.config, elementType(a.t)))
      else:
        internalError(p.config, "openArrayLoc: " & typeToString(a.t))
    else: internalError(p.config, "openArrayLoc: " & typeToString(a.t))

proc withTmpIfNeeded(p: BProc, a: TLoc, needsTmp: bool): TLoc =
  # Bug https://github.com/status-im/nimbus-eth2/issues/1549
  # Aliasing is preferred over stack overflows.
  # Also don't regress for non ARC-builds, too risky.
  if needsTmp and a.lode.typ != nil and p.config.selectedGC in {gcArc, gcAtomicArc, gcOrc} and
      getSize(p.config, a.lode.typ) < 1024:
    result = getTemp(p, a.lode.typ, needsInit=false)
    genAssignment(p, result, a, {})
  else:
    result = a

proc literalsNeedsTmp(p: BProc, a: TLoc): TLoc =
  result = getTemp(p, a.lode.typ, needsInit=false)
  genAssignment(p, result, a, {})

proc genArgStringToCString(p: BProc, n: PNode; result: var Builder; needsTmp: bool) {.inline.} =
  var a = initLocExpr(p, n[0])
  let ra = withTmpIfNeeded(p, a, needsTmp).rdLoc
  result.addCall(cgsymValue(p.module, "nimToCStringConv"), ra)

proc genArg(p: BProc, n: PNode, param: PSym; call: PNode; result: var Builder; needsTmp = false) =
  var a: TLoc
  if n.kind == nkStringToCString:
    genArgStringToCString(p, n, result, needsTmp)
  elif skipTypes(param.typ, abstractVar).kind in {tyOpenArray, tyVarargs}:
    var n = if n.kind != nkHiddenAddr: n else: n[0]
    openArrayLoc(p, param.typ, n, result)
  elif ccgIntroducedPtr(p.config, param, call[0].typ.returnType) and
    (optByRef notin param.options or not p.module.compileToCpp):
    a = initLocExpr(p, n)
    if n.kind in {nkCharLit..nkNilLit}:
      addAddrLoc(p.config, literalsNeedsTmp(p, a), result)
    else:
      addAddrLoc(p.config, withTmpIfNeeded(p, a, needsTmp), result)
  elif p.module.compileToCpp and param.typ.kind in {tyVar} and
      n.kind == nkHiddenAddr:
    # bug #23748: we need to introduce a temporary here. The expression type
    # will be a reference in C++ and we cannot create a temporary reference
    # variable. Thus, we create a temporary pointer variable instead.
    let needsIndirect = mapType(p.config, n[0].typ, mapTypeChooser(n[0]) == skParam) != ctArray
    if needsIndirect:
      n.typ() = n.typ.exactReplica
      n.typ.flags.incl tfVarIsPtr
    a = initLocExprSingleUse(p, n)
    a = withTmpIfNeeded(p, a, needsTmp)
    if needsIndirect: a.flags.incl lfIndirect
    # if the proc is 'importc'ed but not 'importcpp'ed then 'var T' still
    # means '*T'. See posix.nim for lots of examples that do that in the wild.
    let callee = call[0]
    if callee.kind == nkSym and
        {sfImportc, sfInfixCall, sfCompilerProc} * callee.sym.flags == {sfImportc} and
        {lfHeader, lfNoDecl} * callee.sym.loc.flags != {} and
        needsIndirect:
      addAddrLoc(p.config, a, result)
    else:
      addRdLoc(a, result)
  else:
    a = initLocExprSingleUse(p, n)
    if param.typ.kind in {tyVar, tyPtr, tyRef, tySink}:
      let typ = skipTypes(param.typ, abstractPtrs)
      if not sameBackendTypePickyAliases(typ, n.typ.skipTypes(abstractPtrs)):
        a.snippet = cCast(getTypeDesc(p.module, param.typ), rdCharLoc(a))
    addRdLoc(withTmpIfNeeded(p, a, needsTmp), result)
  #assert result != nil

proc genArgNoParam(p: BProc, n: PNode; result: var Builder; needsTmp = false) =
  var a: TLoc
  if n.kind == nkStringToCString:
    genArgStringToCString(p, n, result, needsTmp)
  else:
    a = initLocExprSingleUse(p, n)
    addRdLoc(withTmpIfNeeded(p, a, needsTmp), result)

import aliasanalysis

proc potentialAlias(n: PNode, potentialWrites: seq[PNode]): bool =
  result = false
  for p in potentialWrites:
    if p.aliases(n) != no or n.aliases(p) != no:
      return true

proc skipTrivialIndirections(n: PNode): PNode =
  result = n
  while true:
    case result.kind
    of nkDerefExpr, nkHiddenDeref, nkAddr, nkHiddenAddr, nkObjDownConv, nkObjUpConv:
      result = result[0]
    of nkHiddenStdConv, nkHiddenSubConv:
      result = result[1]
    else: break

proc getPotentialWrites(n: PNode; mutate: bool; result: var seq[PNode]) =
  case n.kind:
  of nkLiterals, nkIdent, nkFormalParams: discard
  of nkSym:
    if mutate: result.add n
  of nkAsgn, nkFastAsgn, nkSinkAsgn:
    getPotentialWrites(n[0], true, result)
    getPotentialWrites(n[1], mutate, result)
  of nkAddr, nkHiddenAddr:
    getPotentialWrites(n[0], true, result)
  of nkBracketExpr, nkDotExpr, nkCheckedFieldExpr:
    getPotentialWrites(n[0], mutate, result)
  of nkCallKinds:
    case n.getMagic:
    of mIncl, mExcl, mInc, mDec, mAppendStrCh, mAppendStrStr, mAppendSeqElem,
        mAddr, mNew, mNewFinalize, mWasMoved, mDestroy:
      getPotentialWrites(n[1], true, result)
      for i in 2..<n.len:
        getPotentialWrites(n[i], mutate, result)
    of mSwap:
      for i in 1..<n.len:
        getPotentialWrites(n[i], true, result)
    else:
      for i in 1..<n.len:
        getPotentialWrites(n[i], mutate, result)
  else:
    for s in n:
      getPotentialWrites(s, mutate, result)

proc getPotentialReads(n: PNode; result: var seq[PNode]) =
  case n.kind:
  of nkLiterals, nkIdent, nkFormalParams: discard
  of nkSym: result.add n
  else:
    for s in n:
      getPotentialReads(s, result)

proc genParams(p: BProc, ri: PNode, typ: PType; result: var Builder, argBuilder: var CallBuilder) =
  # We must generate temporaries in cases like #14396
  # to keep the strict Left-To-Right evaluation
  var needTmp = newSeq[bool](ri.len - 1)
  var potentialWrites: seq[PNode] = @[]
  for i in countdown(ri.len - 1, 1):
    if ri[i].skipTrivialIndirections.kind == nkSym:
      needTmp[i - 1] = potentialAlias(ri[i], potentialWrites)
    else:
      #if not ri[i].typ.isCompileTimeOnly:
      var potentialReads: seq[PNode] = @[]
      getPotentialReads(ri[i], potentialReads)
      for n in potentialReads:
        if not needTmp[i - 1]:
          needTmp[i - 1] = potentialAlias(n, potentialWrites)
      getPotentialWrites(ri[i], false, potentialWrites)
    when false:
      # this optimization is wrong, see bug #23748
      if ri[i].kind in {nkHiddenAddr, nkAddr}:
        # Optimization: don't use a temp, if we would only take the address anyway
        needTmp[i - 1] = false

  for i in 1..<ri.len:
    if i < typ.n.len:
      assert(typ.n[i].kind == nkSym)
      let paramType = typ.n[i]
      if not paramType.typ.isCompileTimeOnly:
        var arg = newBuilder("")
        genArg(p, ri[i], paramType.sym, ri, arg, needTmp[i-1])
        if arg.buf.len != 0:
          result.addArgument(argBuilder):
            result.add(extract(arg))
    else:
      var arg = newBuilder("")
      genArgNoParam(p, ri[i], arg, needTmp[i-1])
      if arg.buf.len != 0:
        result.addArgument(argBuilder):
          result.add(extract(arg))

proc addActualSuffixForHCR(res: var Rope, module: PSym, sym: PSym) =
  if sym.flags * {sfImportc, sfNonReloadable} == {} and sym.loc.k == locProc and
      (sym.typ.callConv == ccInline or sym.owner.id == module.id):
    res = res & "_actual".rope

proc genPrefixCall(p: BProc, le, ri: PNode, d: var TLoc) =
  # this is a hotspot in the compiler
  var op = initLocExpr(p, ri[0])
  # getUniqueType() is too expensive here:
  var typ = skipTypes(ri[0].typ, abstractInstOwned)
  assert(typ.kind == tyProc)

  var callee = rdLoc(op)
  if p.hcrOn and ri[0].kind == nkSym:
    callee.addActualSuffixForHCR(p.module.module, ri[0].sym)

  var res = newBuilder("")
  var call = initCallBuilder(res, callee)
  genParams(p, ri, typ, res, call)
  fixupCall(p, le, ri, d, res, call)

proc genClosureCall(p: BProc, le, ri: PNode, d: var TLoc) =

  template callProc(rp, params, pTyp: Snippet): Snippet =
    let e = dotField(rp, "ClE_0")
    let p = dotField(rp, "ClP_0")
    let eCall =
      # note `params` here is actually multiple params
      if params.len == 0:
        cCall(p, e)
      else:
        cCall(p, params, e)
    cIfExpr(e,
      eCall, 
      cCall(cCast(pTyp, p), params))

  template callIter(rp, params: Snippet): Snippet =
    # we know the env exists
    let e = dotField(rp, "ClE_0")
    let p = dotField(rp, "ClP_0")
    # note `params` here is actually multiple params
    if params.len == 0:
      cCall(p, e)
    else:
      cCall(p, params, e)

  var op = initLocExpr(p, ri[0])

  # getUniqueType() is too expensive here:
  var typ = skipTypes(ri[0].typ, abstractInstOwned)
  assert(typ.kind == tyProc)

  var params = newBuilder("")
  var argBuilder = default(CallBuilder) # not initCallBuilder, we just want the params
  genParams(p, ri, typ, params, argBuilder)

  template genCallPattern {.dirty.} =
    let rp = rdLoc(op)
    let pars = extract(params)
    p.s(cpsStmts).addStmt():
      if tfIterator in typ.flags:
        p.s(cpsStmts).add(callIter(rp, pars))
      else:
        p.s(cpsStmts).add(callProc(rp, pars, rawProc))

  let rawProc = getClosureType(p.module, typ, clHalf)
  let canRaise = p.config.exc == excGoto and canRaiseDisp(p, ri[0])
  if typ.returnType != nil:
    if isInvalidReturnType(p.config, typ):
      # beware of 'result = p(result)'. We may need to allocate a temporary:
      if d.k in {locTemp, locNone} or not preventNrvo(p, d.lode, le, ri):
        # Great, we can use 'd':
        if d.k == locNone:
          d = getTemp(p, typ.returnType, needsInit=true)
        elif d.k notin {locTemp} and not hasNoInit(ri):
          # reset before pass as 'result' var:
          discard "resetLoc(p, d)"
        params.addArgument(argBuilder):
          params.add(addrLoc(p.config, d))
        genCallPattern()
        if canRaise: raiseExit(p)
      else:
        var tmp: TLoc = getTemp(p, typ.returnType, needsInit=true)
        params.addArgument(argBuilder):
          params.add(addrLoc(p.config, tmp))
        genCallPattern()
        if canRaise: raiseExit(p)
        genAssignment(p, d, tmp, {}) # no need for deep copying
    elif isHarmlessStore(p, canRaise, d):
      if d.k == locNone: d = getTemp(p, typ.returnType)
      assert(d.t != nil)        # generate an assignment to d:
      var list: TLoc = initLoc(locCall, d.lode, OnUnknown)
      let rp = rdLoc(op)
      let pars = extract(params)
      if tfIterator in typ.flags:
        list.snippet = callIter(rp, pars)
      else:
        list.snippet = callProc(rp, pars, rawProc)
      genAssignment(p, d, list, {}) # no need for deep copying
      if canRaise: raiseExit(p)
    else:
      var tmp: TLoc = getTemp(p, typ.returnType)
      assert(d.t != nil)        # generate an assignment to d:
      var list: TLoc = initLoc(locCall, d.lode, OnUnknown)
      let rp = rdLoc(op)
      let pars = extract(params)
      if tfIterator in typ.flags:
        list.snippet = callIter(rp, pars)
      else:
        list.snippet = callProc(rp, pars, rawProc)
      genAssignment(p, tmp, list, {})
      if canRaise: raiseExit(p)
      genAssignment(p, d, tmp, {})
  else:
    genCallPattern()
    if canRaise: raiseExit(p)

proc genOtherArg(p: BProc; ri: PNode; i: int; typ: PType; result: var Builder;
                 argBuilder: var CallBuilder) =
  if i < typ.n.len:
    # 'var T' is 'T&' in C++. This means we ignore the request of
    # any nkHiddenAddr when it's a 'var T'.
    let paramType = typ.n[i]
    assert(paramType.kind == nkSym)
    if paramType.typ.isCompileTimeOnly:
      discard
    elif paramType.typ.kind in {tyVar} and ri[i].kind == nkHiddenAddr:
      result.addArgument(argBuilder):
        genArgNoParam(p, ri[i][0], result)
    else:
      result.addArgument(argBuilder):
        genArgNoParam(p, ri[i], result) #, typ.n[i].sym)
  else:
    if tfVarargs notin typ.flags:
      localError(p.config, ri.info, "wrong argument count")
    else:
      result.addArgument(argBuilder):
        genArgNoParam(p, ri[i], result)

discard """
Dot call syntax in C++
======================

so c2nim translates 'this' sometimes to 'T' and sometimes to 'var T'
both of which are wrong, but often more convenient to use.
For manual wrappers it can also be 'ptr T'

Fortunately we know which parameter is the 'this' parameter and so can fix this
mess in the codegen.
now ... if the *argument* is a 'ptr' the codegen shall emit -> and otherwise .
but this only depends on the argument and not on how the 'this' was declared
however how the 'this' was declared affects whether we end up with
wrong 'addr' and '[]' ops...

Since I'm tired I'll enumerate all the cases here:

var
  x: ptr T
  y: T

proc t(x: T)
x[].t()  --> (*x).t()  is correct.
y.t()    --> y.t()  is correct

proc u(x: ptr T)
x.u()          --> needs to become  x->u()
(addr y).u()   --> needs to become  y.u()

proc v(x: var T)
--> first skip the implicit 'nkAddr' node
x[].v()        --> (*x).v()  is correct, but might have been eliminated due
                   to the nkAddr node! So for this case we need to generate '->'
y.v()          --> y.v() is correct

"""

proc skipAddrDeref(node: PNode): PNode =
  var n = node
  var isAddr = false
  case n.kind
  of nkAddr, nkHiddenAddr:
    n = n[0]
    isAddr = true
  of nkDerefExpr, nkHiddenDeref:
    n = n[0]
  else: return n
  if n.kind == nkObjDownConv: n = n[0]
  if isAddr and n.kind in {nkDerefExpr, nkHiddenDeref}:
    result = n[0]
  elif n.kind in {nkAddr, nkHiddenAddr}:
    result = n[0]
  else:
    result = node

proc genThisArg(p: BProc; ri: PNode; i: int; typ: PType; result: var Builder) =
  # for better or worse c2nim translates the 'this' argument to a 'var T'.
  # However manual wrappers may also use 'ptr T'. In any case we support both
  # for convenience.
  internalAssert p.config, i < typ.n.len
  assert(typ.n[i].kind == nkSym)
  # if the parameter is lying (tyVar) and thus we required an additional deref,
  # skip the deref:
  var ri = ri[i]
  while ri.kind == nkObjDownConv: ri = ri[0]
  let t = typ[i].skipTypes({tyGenericInst, tyAlias, tySink})
  if t.kind in {tyVar}:
    let x = if ri.kind == nkHiddenAddr: ri[0] else: ri
    if x.typ.kind == tyPtr:
      genArgNoParam(p, x, result)
      result.add("->")
    elif x.kind in {nkHiddenDeref, nkDerefExpr} and x[0].typ.kind == tyPtr:
      genArgNoParam(p, x[0], result)
      result.add("->")
    else:
      genArgNoParam(p, x, result)
      result.add(".")
  elif t.kind == tyPtr:
    if ri.kind in {nkAddr, nkHiddenAddr}:
      genArgNoParam(p, ri[0], result)
      result.add(".")
    else:
      genArgNoParam(p, ri, result)
      result.add("->")
  else:
    ri = skipAddrDeref(ri)
    if ri.kind in {nkAddr, nkHiddenAddr}: ri = ri[0]
    genArgNoParam(p, ri, result) #, typ.n[i].sym)
    result.add(".")

proc genPatternCall(p: BProc; ri: PNode; pat: string; typ: PType; result: var Builder) =
  var i = 0
  var j = 1
  while i < pat.len:
    case pat[i]
    of '@':
      var callBuilder = default(CallBuilder) # not init call builder
      for k in j..<ri.len:
        genOtherArg(p, ri, k, typ, result, callBuilder)
      inc i
    of '#':
      if i+1 < pat.len and pat[i+1] in {'+', '@'}:
        let ri = ri[j]
        if ri.kind in nkCallKinds:
          let typ = skipTypes(ri[0].typ, abstractInst)
          if pat[i+1] == '+': genArgNoParam(p, ri[0], result)
          result.add("(")
          if 1 < ri.len:
            var callBuilder: CallBuilder = default(CallBuilder)
            genOtherArg(p, ri, 1, typ, result, callBuilder)
          for k in j+1..<ri.len:
            var callBuilder: CallBuilder = default(CallBuilder)
            genOtherArg(p, ri, k, typ, result, callBuilder)
          result.add(")")
        else:
          localError(p.config, ri.info, "call expression expected for C++ pattern")
        inc i
      elif i+1 < pat.len and pat[i+1] == '.':
        genThisArg(p, ri, j, typ, result)
        inc i
      elif i+1 < pat.len and pat[i+1] == '[':
        var arg = ri[j].skipAddrDeref
        while arg.kind in {nkAddr, nkHiddenAddr, nkObjDownConv}: arg = arg[0]
        genArgNoParam(p, arg, result)
        #result.add debugTree(arg, 0, 10)
      else:
        var callBuilder = default(CallBuilder) # not init call builder
        genOtherArg(p, ri, j, typ, result, callBuilder)
      inc j
      inc i
    of '\'':
      var idx, stars: int = 0
      if scanCppGenericSlot(pat, i, idx, stars):
        var t = resolveStarsInCppType(typ, idx, stars)
        if t == nil: result.add(CVoid)
        else: result.add(getTypeDesc(p.module, t))
    else:
      let start = i
      while i < pat.len:
        if pat[i] notin {'@', '#', '\''}: inc(i)
        else: break
      if i - 1 >= start:
        result.add(substr(pat, start, i - 1))

proc genInfixCall(p: BProc, le, ri: PNode, d: var TLoc) =
  var op = initLocExpr(p, ri[0])
  # getUniqueType() is too expensive here:
  var typ = skipTypes(ri[0].typ, abstractInst)
  assert(typ.kind == tyProc)
  # don't call '$' here for efficiency:
  let pat = $ri[0].sym.loc.snippet
  internalAssert p.config, pat.len > 0
  if pat.contains({'#', '(', '@', '\''}):
    var pl = newBuilder("")
    genPatternCall(p, ri, pat, typ, pl)
    # simpler version of 'fixupCall' that works with the pl+params combination:
    var typ = skipTypes(ri[0].typ, abstractInst)
    if typ.returnType != nil:
      if p.module.compileToCpp and lfSingleUse in d.flags:
        # do not generate spurious temporaries for C++! For C we're better off
        # with them to prevent undefined behaviour and because the codegen
        # is free to emit expressions multiple times!
        d.k = locCall
        d.snippet = extract(pl)
        excl d.flags, lfSingleUse
      else:
        if d.k == locNone: d = getTemp(p, typ.returnType)
        assert(d.t != nil)        # generate an assignment to d:
        var list: TLoc = initLoc(locCall, d.lode, OnUnknown)
        list.snippet = extract(pl)
        genAssignment(p, d, list, {}) # no need for deep copying
    else:
      p.s(cpsStmts).addStmt():
        p.s(cpsStmts).add(extract(pl))
  else:
    var pl = newBuilder("")
    if 1 < ri.len:
      genThisArg(p, ri, 1, typ, pl)
    pl.add(op.snippet)
    var res = newBuilder("")
    var call = initCallBuilder(res, extract(pl))
    for i in 2..<ri.len:
      genOtherArg(p, ri, i, typ, res, call)
    fixupCall(p, le, ri, d, res, call)

proc genNamedParamCall(p: BProc, ri: PNode, d: var TLoc) =
  # generates a crappy ObjC call
  var op = initLocExpr(p, ri[0])
  var pl = newBuilder("[")
  # getUniqueType() is too expensive here:
  var typ = skipTypes(ri[0].typ, abstractInst)
  assert(typ.kind == tyProc)

  # don't call '$' here for efficiency:
  let pat = $ri[0].sym.loc.snippet
  internalAssert p.config, pat.len > 0
  var start = 3
  if ' ' in pat:
    start = 1
    pl.add(op.snippet)
    if ri.len > 1:
      pl.add(": ")
      genArg(p, ri[1], typ.n[1].sym, ri, pl)
      start = 2
  else:
    if ri.len > 1:
      genArg(p, ri[1], typ.n[1].sym, ri, pl)
      pl.add(" ")
    pl.add(op.snippet)
    if ri.len > 2:
      pl.add(": ")
      genArg(p, ri[2], typ.n[2].sym, ri, pl)
  for i in start..<ri.len:
    if i >= typ.n.len:
      internalError(p.config, ri.info, "varargs for objective C method?")
    assert(typ.n[i].kind == nkSym)
    var param = typ.n[i].sym
    pl.add(" ")
    pl.add(param.name.s)
    pl.add(": ")
    genArg(p, ri[i], param, ri, pl)
  if typ.returnType != nil:
    if isInvalidReturnType(p.config, typ):
      if ri.len > 1: pl.add(" ")
      # beware of 'result = p(result)'. We always allocate a temporary:
      if d.k in {locTemp, locNone}:
        # We already got a temp. Great, special case it:
        if d.k == locNone: d = getTemp(p, typ.returnType, needsInit=true)
        pl.add("Result: ")
        pl.add(addrLoc(p.config, d))
        pl.add("]")
        p.s(cpsStmts).addStmt():
          p.s(cpsStmts).add(extract(pl))
      else:
        var tmp: TLoc = getTemp(p, typ.returnType, needsInit=true)
        pl.add(addrLoc(p.config, tmp))
        pl.add("]")
        p.s(cpsStmts).addStmt():
          p.s(cpsStmts).add(extract(pl))
        genAssignment(p, d, tmp, {}) # no need for deep copying
    else:
      pl.add("]")
      if d.k == locNone: d = getTemp(p, typ.returnType)
      assert(d.t != nil)        # generate an assignment to d:
      var list: TLoc = initLoc(locCall, ri, OnUnknown)
      list.snippet = extract(pl)
      genAssignment(p, d, list, {}) # no need for deep copying
  else:
    pl.add("]")
    p.s(cpsStmts).addStmt():
      p.s(cpsStmts).add(extract(pl))

proc notYetAlive(n: PNode): bool {.inline.} =
  let r = getRoot(n)
  result = r != nil and r.loc.lode == nil

proc isInactiveDestructorCall(p: BProc, e: PNode): bool =
  #[ Consider this example.

    var :tmpD_3281815
    try:
      if true:
        return
      let args_3280013 =
        wasMoved_3281816(:tmpD_3281815)
        `=_3280036`(:tmpD_3281815, [1])
        :tmpD_3281815
    finally:
      `=destroy_3280027`(args_3280013)

  We want to return early but the 'finally' section is traversed before
  the 'let args = ...' statement. We exploit this to generate better
  code for 'return'. ]#
  result = e.len == 2 and e[0].kind == nkSym and
    e[0].sym.name.s == "=destroy" and notYetAlive(e[1].skipAddr)

proc genAsgnCall(p: BProc, le, ri: PNode, d: var TLoc) =
  if p.withinBlockLeaveActions > 0 and isInactiveDestructorCall(p, ri):
    return
  if ri[0].typ.skipTypes({tyGenericInst, tyAlias, tySink, tyOwned}).callConv == ccClosure:
    genClosureCall(p, le, ri, d)
  elif ri[0].kind == nkSym and sfInfixCall in ri[0].sym.flags:
    genInfixCall(p, le, ri, d)
  elif ri[0].kind == nkSym and sfNamedParamCall in ri[0].sym.flags:
    genNamedParamCall(p, ri, d)
  else:
    genPrefixCall(p, le, ri, d)

proc genCall(p: BProc, e: PNode, d: var TLoc) = genAsgnCall(p, nil, e, d)

#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# included from cgen.nim
const
  RangeExpandLimit = 256      # do not generate ranges
                              # over 'RangeExpandLimit' elements
  stringCaseThreshold = 8
    # above X strings a hash-switch for strings is generated

proc registerTraverseProc(p: BProc, v: PSym) =
  var traverseProc = ""
  if p.config.selectedGC in {gcMarkAndSweep, gcHooks, gcRefc} and
      optOwnedRefs notin p.config.globalOptions and
      containsGarbageCollectedRef(v.loc.t):
    # we register a specialized marked proc here; this has the advantage
    # that it works out of the box for thread local storage then :-)
    traverseProc = genTraverseProcForGlobal(p.module, v, v.info)

  if traverseProc.len != 0 and not p.hcrOn:
    p.module.preInitProc.procSec(cpsInit).add("\n\t")
    let fnName = cgsymValue(p.module,
      if sfThread in v.flags: "nimRegisterThreadLocalMarker"
      else: "nimRegisterGlobalMarker")
    p.module.preInitProc.procSec(cpsInit).addCallStmt(fnName, traverseProc)
    p.module.preInitProc.procSec(cpsInit).add("\n")

proc isAssignedImmediately(conf: ConfigRef; n: PNode): bool {.inline.} =
  if n.kind == nkEmpty:
    result = false
  elif n.kind in nkCallKinds and n[0] != nil and n[0].typ != nil and n[0].typ.skipTypes(abstractInst).kind == tyProc:
    if n[0].kind == nkSym and sfConstructor in n[0].sym.flags:
      result = true
    elif isInvalidReturnType(conf, n[0].typ, true):
      # var v = f()
      # is transformed into: var v;  f(addr v)
      # where 'f' **does not** initialize the result!
      result = false
    else:
      result = true
  elif isInvalidReturnType(conf, n.typ, false):
    result = false
  else:
    result = true

proc inExceptBlockLen(p: BProc): int =
  result = 0
  for x in p.nestedTryStmts:
    if x.inExcept: result.inc

proc startBlockInside(p: BProc): int {.discardable.} =
  inc(p.labels)
  result = p.blocks.len

  p.blocks.add initBlock()

  p.blocks[result].id = p.labels
  p.blocks[result].nestedTryStmts = p.nestedTryStmts.len.int16
  p.blocks[result].nestedExceptStmts = p.inExceptBlockLen.int16

template startBlockWith(p: BProc, body: typed): int =
  body
  startBlockInside(p)

proc blockBody(b: var TBlock; result: var Builder) =
  result.add extract(b.sections[cpsLocals])
  if b.frameLen > 0:
    result.addInPlaceOp(Add, "NI", dotField("FR_", "len"), b.frameLen.rope)
  result.add(extract(b.sections[cpsInit]))
  result.add(extract(b.sections[cpsStmts]))
  if b.frameLen > 0:
    result.addInPlaceOp(Sub, "NI", dotField("FR_", "len"), b.frameLen.rope)

proc endBlockInside(p: BProc) =
  let topBlock = p.blocks.len-1
  # the block is merged into the parent block
  p.blocks[topBlock].blockBody(p.blocks[topBlock-1].sections[cpsStmts])
  setLen(p.blocks, topBlock)

proc endBlockOutside(p: BProc, label: TLabel) =
  if label.len != 0:
    let topBlock = p.blocks.len - 1
    p.blocks[topBlock].sections[cpsStmts].addLabel(label)

template endBlockWith(p: BProc, body: typed) =
  let label = p.blocks[p.blocks.len - 1].label
  endBlockInside(p)
  body
  endBlockOutside(p, label)

proc genVarTuple(p: BProc, n: PNode) =
  if n.kind != nkVarTuple: internalError(p.config, n.info, "genVarTuple")

  # if we have a something that's been captured, use the lowering instead:
  for i in 0..<n.len-2:
    if n[i].kind != nkSym:
      genStmts(p, lowerTupleUnpacking(p.module.g.graph, n, p.module.idgen, p.prc))
      return

  # check only the first son
  var forHcr = treatGlobalDifferentlyForHCR(p.module, n[0].sym)
  let hcrCond = if forHcr: getTempName(p.module) else: ""
  var hcrGlobals: seq[tuple[loc: TLoc, tp: Rope]] = @[]
  # determine if the tuple is constructed at top-level scope or inside of a block (if/while/block)
  let isGlobalInBlock = forHcr and p.blocks.len > 2
  # do not close and reopen blocks if this is a 'global' but inside of a block (if/while/block)
  forHcr = forHcr and not isGlobalInBlock

  var hcrIf = default(IfBuilder)
  if forHcr:
    startBlockWith(p):
      # check with the boolean if the initializing code for the tuple should be ran
      hcrIf = initIfStmt(p.s(cpsStmts))
      initElifBranch(p.s(cpsStmts), hcrIf, hcrCond)

  genLineDir(p, n)
  var tup = initLocExpr(p, n[^1])
  var t = tup.t.skipTypes(abstractInst)
  for i in 0..<n.len-2:
    let vn = n[i]
    let v = vn.sym
    if sfCompileTime in v.flags: continue
    if sfGlobal in v.flags:
      assignGlobalVar(p, vn, "")
      genObjectInit(p, cpsInit, v.typ, v.loc, constructObj)
      registerTraverseProc(p, v)
    else:
      assignLocalVar(p, vn)
      initLocalVar(p, v, immediateAsgn=isAssignedImmediately(p.config, n[^1]))
    var field = initLoc(locExpr, vn, tup.storage)
    let rtup = rdLoc(tup)
    let fieldName = 
      if t.kind == tyTuple:
        "Field" & $i
      else:
        if t.n[i].kind != nkSym: internalError(p.config, n.info, "genVarTuple")
        mangleRecFieldName(p.module, t.n[i].sym)
    field.snippet = dotField(rtup, fieldName)
    putLocIntoDest(p, v.loc, field)
    if forHcr or isGlobalInBlock:
      hcrGlobals.add((loc: v.loc, tp: "NULL"))

  if forHcr:
    # end the block where the tuple gets initialized
    endBlockWith(p):
      finishBranch(p.s(cpsStmts), hcrIf)
      finishIfStmt(p.s(cpsStmts), hcrIf)

  if forHcr or isGlobalInBlock:
    # insert the registration of the globals for the different parts of the tuple at the
    # start of the current scope (after they have been iterated) and init a boolean to
    # check if any of them is newly introduced and the initializing code has to be ran
    p.s(cpsLocals).addVar(kind = Local,
      name = hcrCond,
      typ = "NIM_BOOL",
      initializer = "NIM_FALSE")
    for curr in hcrGlobals:
      let rc = rdLoc(curr.loc)
      p.s(cpsLocals).addInPlaceOp(BitOr, "NIM_BOOL",
        hcrCond,
        cCall("hcrRegisterGlobal",
          getModuleDllPath(p.module, n[0].sym),
          '"' & curr.loc.snippet & '"',
          cSizeof(rc),
          curr.tp,
          cCast("void**", cAddr(curr.loc.snippet))))


proc loadInto(p: BProc, le, ri: PNode, a: var TLoc) {.inline.} =
  if ri.kind in nkCallKinds and (ri[0].kind != nkSym or
                                 ri[0].sym.magic == mNone):
    genAsgnCall(p, le, ri, a)
  else:
    # this is a hacky way to fix #1181 (tmissingderef)::
    #
    #  var arr1 = cast[ptr array[4, int8]](addr foo)[]
    #
    # However, fixing this properly really requires modelling 'array' as
    # a 'struct' in C to preserve dereferencing semantics completely. Not
    # worth the effort until version 1.0 is out.
    a.flags.incl(lfEnforceDeref)
    expr(p, ri, a)

proc assignLabel(b: var TBlock; result: var TLabel) {.inline.} =
  b.label = "LA" & b.id.rope
  result = b.label

proc startSimpleBlock(p: BProc, scope: out ScopeBuilder): int {.discardable, inline.} =
  startBlockWith(p):
    scope = initScope(p.s(cpsStmts))

proc endSimpleBlock(p: BProc, scope: var ScopeBuilder) {.inline.} =
  endBlockWith(p):
    finishScope(p.s(cpsStmts), scope)

proc genSimpleBlock(p: BProc, stmts: PNode) {.inline.} =
  var scope: ScopeBuilder
  startSimpleBlock(p, scope)
  genStmts(p, stmts)
  endSimpleBlock(p, scope)

proc exprBlock(p: BProc, n: PNode, d: var TLoc) =
  var scope: ScopeBuilder
  startSimpleBlock(p, scope)
  expr(p, n, d)
  endSimpleBlock(p, scope)

template preserveBreakIdx(body: untyped): untyped =
  var oldBreakIdx = p.breakIdx
  body
  p.breakIdx = oldBreakIdx

proc genState(p: BProc, n: PNode) =
  internalAssert p.config, n.len == 1
  let n0 = n[0]
  if n0.kind == nkIntLit:
    let idx = n[0].intVal
    p.s(cpsStmts).addLabel("STATE" & $idx)
  elif n0.kind == nkStrLit:
    p.s(cpsStmts).addLabel(n0.strVal)

proc blockLeaveActions(p: BProc, howManyTrys, howManyExcepts: int) =
  # Called by return and break stmts.
  # Deals with issues faced when jumping out of try/except/finally stmts.

  var stack = newSeq[tuple[fin: PNode, inExcept: bool, label: Natural]](0)

  inc p.withinBlockLeaveActions
  for i in 1..howManyTrys:
    let tryStmt = p.nestedTryStmts.pop
    if p.config.exc == excSetjmp:
      # Pop safe points generated by try
      if not tryStmt.inExcept:
        p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "popSafePoint"))

    # Pop this try-stmt of the list of nested trys
    # so we don't infinite recurse on it in the next step.
    stack.add(tryStmt)

    # Find finally-stmt for this try-stmt
    # and generate a copy of its sons
    var finallyStmt = tryStmt.fin
    if finallyStmt != nil:
      genStmts(p, finallyStmt[0])

  dec p.withinBlockLeaveActions

  # push old elements again:
  for i in countdown(howManyTrys-1, 0):
    p.nestedTryStmts.add(stack[i])

  # Pop exceptions that was handled by the
  # except-blocks we are in
  if noSafePoints notin p.flags:
    for i in countdown(howManyExcepts-1, 0):
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "popCurrentException"))

proc genGotoState(p: BProc, n: PNode) =
  # we resist the temptation to translate it into duff's device as it later
  # will be translated into computed gotos anyway for GCC at least:
  # switch (x.state) {
  #   case 0: goto STATE0;
  # ...
  var a: TLoc = initLocExpr(p, n[0])
  let ra = rdLoc(a)
  p.s(cpsStmts).addSwitchStmt(ra):
    p.flags.incl beforeRetNeeded
    p.s(cpsStmts).addSingleSwitchCase(cIntValue(-1)):
      blockLeaveActions(p,
        howManyTrys    = p.nestedTryStmts.len,
        howManyExcepts = p.inExceptBlockLen)
      p.s(cpsStmts).addGoto("BeforeRet_")
    var statesCounter = lastOrd(p.config, n[0].typ)
    if n.len >= 2 and n[1].kind == nkIntLit:
      statesCounter = getInt(n[1])
    let prefix = if n.len == 3 and n[2].kind == nkStrLit: n[2].strVal.rope
                else: rope"STATE"
    for i in 0i64..toInt64(statesCounter):
      p.s(cpsStmts).addSingleSwitchCase(cIntValue(i)):
        p.s(cpsStmts).addGoto(prefix & $i)

proc genBreakState(p: BProc, n: PNode, d: var TLoc) =
  var a: TLoc
  d = initLoc(locExpr, n, OnUnknown)

  if n[0].kind == nkClosure:
    a = initLocExpr(p, n[0][1])
    let ra = a.rdLoc
    d.snippet = cOp(LessThan,
      subscript(
        cCast(ptrType("NI"), ra),
        cIntValue(1)),
      cIntValue(0))
  else:
    a = initLocExpr(p, n[0])
    let ra = a.rdLoc
    # the environment is guaranteed to contain the 'state' field at offset 1:
    d.snippet = cOp(LessThan,
      subscript(
        cCast(ptrType("NI"), dotField(ra, "ClE_0")),
        cIntValue(1)),
      cIntValue(0))

proc genGotoVar(p: BProc; value: PNode) =
  if value.kind notin {nkCharLit..nkUInt64Lit}:
    localError(p.config, value.info, "'goto' target must be a literal value")
  else:
    p.s(cpsStmts).addGoto("NIMSTATE_" & $value.intVal)

proc genBracedInit(p: BProc, n: PNode; isConst: bool; optionalType: PType; result: var Builder)

proc potentialValueInit(p: BProc; v: PSym; value: PNode; result: var Builder) =
  if lfDynamicLib in v.loc.flags or sfThread in v.flags or p.hcrOn:
    discard "nothing to do"
  elif sfGlobal in v.flags and value != nil and isDeepConstExpr(value, p.module.compileToCpp) and
      p.withinLoop == 0 and not containsGarbageCollectedRef(v.typ):
    #echo "New code produced for ", v.name.s, " ", p.config $ value.info
    genBracedInit(p, value, isConst = false, v.typ, result)

proc genCppParamsForCtor(p: BProc; call: PNode; didGenTemp: var bool): Snippet =
  var res = newBuilder("")
  var argBuilder = default(CallBuilder) # not init, only building params
  let typ = skipTypes(call[0].typ, abstractInst)
  assert(typ.kind == tyProc)
  for i in 1..<call.len:
    #if it's a type we can just generate here another initializer as we are in an initializer context
    if call[i].kind == nkCall and call[i][0].kind == nkSym and call[i][0].sym.kind == skType:
      res.addArgument(argBuilder):
        res.add genCppInitializer(p.module, p, call[i][0].sym.typ, didGenTemp)
    else:
      #We need to test for temp in globals, see: #23657
      let param =
        if typ[i].kind in {tyVar} and call[i].kind == nkHiddenAddr:
          call[i][0]
        else:
          call[i]
      if param.kind != nkBracketExpr or param.typ.kind in
        {tyRef, tyPtr, tyUncheckedArray, tyArray, tyOpenArray,
          tyVarargs, tySequence, tyString, tyCstring, tyTuple}:
        let tempLoc = initLocExprSingleUse(p, param)
        didGenTemp = didGenTemp or tempLoc.k == locTemp
      genOtherArg(p, call, i, typ, res, argBuilder)
  result = extract(res)

proc genCppVarForCtor(p: BProc; call: PNode; decl: var Rope, didGenTemp: var bool) =
  let params = genCppParamsForCtor(p, call, didGenTemp)
  if params.len == 0:
    decl = runtimeFormat("$#;\n", [decl])
  else:
    decl = runtimeFormat("$#($#);\n", [decl, params])

proc genSingleVar(p: BProc, v: PSym; vn, value: PNode) =
  if sfGoto in v.flags:
    # translate 'var state {.goto.} = X' into 'goto LX':
    genGotoVar(p, value)
    return
  let imm = isAssignedImmediately(p.config, value)
  let isCppCtorCall = p.module.compileToCpp and imm and
    value.kind in nkCallKinds and value[0].kind == nkSym and
    v.typ.kind != tyPtr and sfConstructor in value[0].sym.flags
  var targetProc = p
  var valueBuilder = newBuilder("")
  potentialValueInit(p, v, value, valueBuilder)
  let valueAsRope = extract(valueBuilder)
  if sfGlobal in v.flags:
    if v.flags * {sfImportc, sfExportc} == {sfImportc} and
        value.kind == nkEmpty and
        v.loc.flags * {lfHeader, lfNoDecl} != {}:
      return
    if sfPure in v.flags:
      # v.owner.kind != skModule:
      targetProc = p.module.preInitProc
    if isCppCtorCall and not containsHiddenPointer(v.typ):
      var didGenTemp = false
      callGlobalVarCppCtor(targetProc, v, vn, value, didGenTemp)
      if didGenTemp:
        message(p.config, vn.info, warnGlobalVarConstructorTemporary, vn.sym.name.s)
        #We fail to call the constructor in the global scope so we do the call inside the main proc
        assignGlobalVar(targetProc, vn, valueAsRope)
        var loc = initLocExprSingleUse(targetProc, value)
        genAssignment(targetProc, v.loc, loc, {})
    else:
      assignGlobalVar(targetProc, vn, valueAsRope)

    # XXX: be careful here.
    # Global variables should not be zeromem-ed within loops
    # (see bug #20).
    # That's why we are doing the construction inside the preInitProc.
    # genObjectInit relies on the C runtime's guarantees that
    # global variables will be initialized to zero.
    if valueAsRope.len == 0:
      var loc = v.loc
      # When the native TLS is unavailable, a global thread-local variable needs
      # one more layer of indirection in order to access the TLS block.
      # Only do this for complex types that may need a call to `objectInit`
      if sfThread in v.flags and emulatedThreadVars(p.config) and
        isComplexValueType(v.typ):
        loc = initLocExprSingleUse(p.module.preInitProc, vn)
      genObjectInit(p.module.preInitProc, cpsInit, v.typ, loc, constructObj)
    # Alternative construction using default constructor (which may zeromem):
    # if sfImportc notin v.flags: constructLoc(p.module.preInitProc, v.loc)
    if sfExportc in v.flags and p.module.g.generatedHeader != nil:
      genVarPrototype(p.module.g.generatedHeader, vn)
    registerTraverseProc(p, v)
  else:
    if imm and p.module.compileToCpp and p.splitDecls == 0 and
        not containsHiddenPointer(v.typ) and
        nimErrorFlagAccessed notin p.flags:
      # C++ really doesn't like things like 'Foo f; f = x' as that invokes a
      # parameterless constructor followed by an assignment operator. So we
      # generate better code here: 'Foo f = x;'
      genLineDir(p, vn)
      var decl = localVarDecl(p, vn)
      var tmp: TLoc
      if isCppCtorCall:
        var didGenTemp = false
        genCppVarForCtor(p, value, decl, didGenTemp)
        line(p, cpsStmts, decl)
      else:
        tmp = initLocExprSingleUse(p, value)
        if value.kind == nkEmpty:
          lineF(p, cpsStmts, "$#;\n", [decl])
        else:
          lineF(p, cpsStmts, "$# = $#;\n", [decl, tmp.rdLoc])
      return
    assignLocalVar(p, vn)
    initLocalVar(p, v, imm)

  let traverseProc = "NULL"
  # If the var is in a block (control flow like if/while or a block) in global scope just
  # register the so called "global" so it can be used later on. There is no need to close
  # and reopen of if (nim_hcr_do_init_) blocks because we are in one already anyway.
  var forHcr = treatGlobalDifferentlyForHCR(p.module, v)
  if forHcr and targetProc.blocks.len > 3 and v.owner.kind == skModule:
    # put it in the locals section - mainly because of loops which
    # use the var in a call to resetLoc() in the statements section
    let rv = rdLoc(v.loc)
    p.s(cpsLocals).addCallStmt("hcrRegisterGlobal",
      getModuleDllPath(p.module, v),
      '"' & v.loc.snippet & '"',
      cSizeof(rv),
      traverseProc,
      cCast("void**", cAddr(v.loc.snippet)))
    # nothing special left to do later on - let's avoid closing and reopening blocks
    forHcr = false

  # we close and reopen the global if (nim_hcr_do_init_) blocks in the main Init function
  # for the module so we can have globals and top-level code be interleaved and still
  # be able to re-run it but without the top level code - just the init of globals
  var hcrInit = default(IfBuilder)
  if forHcr:
    startBlockWith(targetProc):
      hcrInit = initIfStmt(p.s(cpsStmts))
      initElifBranch(p.s(cpsStmts), hcrInit, cCall("hcrRegisterGlobal",
        getModuleDllPath(p.module, v),
        '"' & v.loc.snippet & '"',
        cSizeof(rdLoc(v.loc)),
        traverseProc,
        cCast("void**", cAddr(v.loc.snippet))))
  if value.kind != nkEmpty and valueAsRope.len == 0:
    genLineDir(targetProc, vn)
    if not isCppCtorCall:
      loadInto(targetProc, vn, value, v.loc)
  if forHcr:
    endBlockWith(targetProc):
      finishBranch(p.s(cpsStmts), hcrInit)
      finishIfStmt(p.s(cpsStmts), hcrInit)

proc genSingleVar(p: BProc, a: PNode) =
  let v = a[0].sym
  if sfCompileTime in v.flags:
    # fix issue #12640
    # {.global, compileTime.} pragma in proc
    if sfGlobal in v.flags and p.prc != nil and p.prc.kind == skProc:
      discard
    else:
      return
  genSingleVar(p, v, a[0], a[2])

proc genClosureVar(p: BProc, a: PNode) =
  var immediateAsgn = a[2].kind != nkEmpty
  var v: TLoc = initLocExpr(p, a[0])
  genLineDir(p, a)
  if immediateAsgn:
    loadInto(p, a[0], a[2], v)
  elif sfNoInit notin a[0][1].sym.flags:
    constructLoc(p, v)

proc genVarStmt(p: BProc, n: PNode) =
  for it in n.sons:
    if it.kind == nkCommentStmt: continue
    if it.kind == nkIdentDefs:
      # can be a lifted var nowadays ...
      if it[0].kind == nkSym:
        genSingleVar(p, it)
      else:
        genClosureVar(p, it)
    else:
      genVarTuple(p, it)

proc genIf(p: BProc, n: PNode, d: var TLoc) =
  #
  #  { if (!expr1) goto L1;
  #   thenPart }
  #  goto LEnd
  #  L1:
  #  { if (!expr2) goto L2;
  #   thenPart2 }
  #  goto LEnd
  #  L2:
  #  { elsePart }
  #  Lend:
  var
    a: TLoc
    lelse: TLabel
  if not isEmptyType(n.typ) and d.k == locNone:
    d = getTemp(p, n.typ)
  genLineDir(p, n)
  let lend = getLabel(p)
  for it in n.sons:
    # bug #4230: avoid false sharing between branches:
    if d.k == locTemp and isEmptyType(n.typ): d.k = locNone
    if it.len == 2:
      var scope: ScopeBuilder
      startSimpleBlock(p, scope)
      a = initLocExprSingleUse(p, it[0])
      lelse = getLabel(p)
      inc(p.labels)
      let ra = rdLoc(a)
      p.s(cpsStmts).addSingleIfStmt(cOp(Not, ra)):
        p.s(cpsStmts).addGoto(lelse)
      if p.module.compileToCpp:
        # avoid "jump to label crosses initialization" error:
        p.s(cpsStmts).addScope():
          expr(p, it[1], d)
      else:
        expr(p, it[1], d)
      endSimpleBlock(p, scope)
      if n.len > 1:
        p.s(cpsStmts).addGoto(lend)
      fixLabel(p, lelse)
    elif it.len == 1:
      var scope: ScopeBuilder
      startSimpleBlock(p, scope)
      expr(p, it[0], d)
      endSimpleBlock(p, scope)
    else: internalError(p.config, n.info, "genIf()")
  if n.len > 1: fixLabel(p, lend)

proc genReturnStmt(p: BProc, t: PNode) =
  if nfPreventCg in t.flags: return
  p.flags.incl beforeRetNeeded
  genLineDir(p, t)
  if (t[0].kind != nkEmpty): genStmts(p, t[0])
  blockLeaveActions(p,
    howManyTrys    = p.nestedTryStmts.len,
    howManyExcepts = p.inExceptBlockLen)
  if (p.finallySafePoints.len > 0) and noSafePoints notin p.flags:
    # If we're in a finally block, and we came here by exception
    # consume it before we return.
    var safePoint = p.finallySafePoints[^1]
    p.s(cpsStmts).addSingleIfStmt(
      cOp(NotEqual,
        dotField(safePoint, "status"),
        cIntValue(0))):
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "popCurrentException"))
  p.s(cpsStmts).addGoto("BeforeRet_")

proc genGotoForCase(p: BProc; caseStmt: PNode) =
  for i in 1..<caseStmt.len:
    var scope: ScopeBuilder
    startSimpleBlock(p, scope)
    let it = caseStmt[i]
    for j in 0..<it.len-1:
      if it[j].kind == nkRange:
        localError(p.config, it.info, "range notation not available for computed goto")
        return
      let val = getOrdValue(it[j])
      p.s(cpsStmts).addLabel("NIMSTATE_" & $val)
    genStmts(p, it.lastSon)
    endSimpleBlock(p, scope)


iterator fieldValuePairs(n: PNode): tuple[memberSym, valueSym: PNode] =
  assert(n.kind in {nkLetSection, nkVarSection})
  for identDefs in n:
    if identDefs.kind == nkIdentDefs:
      let valueSym = identDefs[^1]
      for i in 0..<identDefs.len-2:
        let memberSym = identDefs[i]
        yield((memberSym: memberSym, valueSym: valueSym))

proc genComputedGoto(p: BProc; n: PNode) =
  # first pass: Generate array of computed labels:

  # flatten the loop body because otherwise let and var sections
  # wrapped inside stmt lists by inject destructors won't be recognised
  let n = n.flattenStmts()
  var casePos = -1
  var arraySize: int = 0
  for i in 0..<n.len:
    let it = n[i]
    if it.kind == nkCaseStmt:
      if lastSon(it).kind != nkOfBranch:
        localError(p.config, it.info,
            "case statement must be exhaustive for computed goto"); return
      casePos = i
      if enumHasHoles(it[0].typ):
        localError(p.config, it.info,
            "case statement cannot work on enums with holes for computed goto"); return
      let aSize = lengthOrd(p.config, it[0].typ)
      if aSize > 10_000:
        localError(p.config, it.info,
            "case statement has too many cases for computed goto"); return
      arraySize = toInt(aSize)
      if firstOrd(p.config, it[0].typ) != 0:
        localError(p.config, it.info,
            "case statement has to start at 0 for computed goto"); return
  if casePos < 0:
    localError(p.config, n.info, "no case statement found for computed goto"); return
  var id = p.labels+1
  inc p.labels, arraySize+1
  let tmp = "TMP$1_" % [id.rope]
  p.s(cpsStmts).addArrayVarWithInitializer(kind = Global,
      name = tmp,
      elementType = "void*",
      len = arraySize):
    var labelsInit: StructInitializer
    p.s(cpsStmts).addStructInitializer(labelsInit, kind = siArray):
      for i in 1..arraySize:
        p.s(cpsStmts).addField(labelsInit, ""):
          p.s(cpsStmts).add(cLabelAddr("TMP" & $(id+i) & "_"))

  for j in 0..<casePos:
    genStmts(p, n[j])

  let caseStmt = n[casePos]
  var a: TLoc = initLocExpr(p, caseStmt[0])
  let ra = a.rdLoc
  # first goto:
  p.s(cpsStmts).addComputedGoto(subscript(tmp, ra))

  for i in 1..<caseStmt.len:
    var scope: ScopeBuilder
    startSimpleBlock(p, scope)
    let it = caseStmt[i]
    for j in 0..<it.len-1:
      if it[j].kind == nkRange:
        localError(p.config, it.info, "range notation not available for computed goto")
        return

      let val = getOrdValue(it[j])
      let lit = cIntLiteral(toInt64(val)+id+1)
      p.s(cpsStmts).addLabel("TMP" & lit & "_")

    genStmts(p, it.lastSon)

    for j in casePos+1..<n.len:
      genStmts(p, n[j])

    for j in 0..<casePos:
      # prevent new local declarations
      # compile declarations as assignments
      let it = n[j]
      if it.kind in {nkLetSection, nkVarSection}:
        let asgn = copyNode(it)
        asgn.transitionSonsKind(nkAsgn)
        asgn.sons.setLen 2
        for sym, value in it.fieldValuePairs:
          if value.kind != nkEmpty:
            asgn[0] = sym
            asgn[1] = value
            genStmts(p, asgn)
      else:
        genStmts(p, it)

    var a: TLoc = initLocExpr(p, caseStmt[0])
    let ra = a.rdLoc
    p.s(cpsStmts).addComputedGoto(subscript(tmp, ra))
    endSimpleBlock(p, scope)

  for j in casePos+1..<n.len:
    genStmts(p, n[j])


proc genWhileStmt(p: BProc, t: PNode) =
  # we don't generate labels here as for example GCC would produce
  # significantly worse code
  var
    a: TLoc
  assert(t.len == 2)
  inc(p.withinLoop)
  genLineDir(p, t)

  preserveBreakIdx:
    var loopBody = t[1]
    if loopBody.stmtsContainPragma(wComputedGoto) and
       hasComputedGoto in CC[p.config.cCompiler].props:
         # for closure support weird loop bodies are generated:
      if loopBody.len == 2 and loopBody[0].kind == nkEmpty:
        loopBody = loopBody[1]
      genComputedGoto(p, loopBody)
    else:
      var stmt: WhileBuilder
      p.breakIdx = startBlockWith(p):
        stmt = initWhileStmt(p.s(cpsStmts), cIntValue(1))
      p.blocks[p.breakIdx].isLoop = true
      a = initLocExpr(p, t[0])
      if (t[0].kind != nkIntLit) or (t[0].intVal == 0):
        let ra = a.rdLoc
        var label: TLabel = ""
        assignLabel(p.blocks[p.breakIdx], label)
        p.s(cpsStmts).addSingleIfStmt(cOp(Not, ra)):
          p.s(cpsStmts).addGoto(label)
      genStmts(p, loopBody)

      if optProfiler in p.options:
        # invoke at loop body exit:
        p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "nimProfile"))
      endBlockWith(p):
        finishWhileStmt(p.s(cpsStmts), stmt)

  dec(p.withinLoop)

proc genBlock(p: BProc, n: PNode, d: var TLoc) =
  if not isEmptyType(n.typ):
    # bug #4505: allocate the temp in the outer scope
    # so that it can escape the generated {}:
    if d.k == locNone:
      d = getTemp(p, n.typ)
    d.flags.incl(lfEnforceDeref)
  preserveBreakIdx:
    var scope: ScopeBuilder
    p.breakIdx = startSimpleBlock(p, scope)
    if n[0].kind != nkEmpty:
      # named block?
      assert(n[0].kind == nkSym)
      var sym = n[0].sym
      sym.loc.k = locOther
      sym.position = p.breakIdx+1
    expr(p, n[1], d)
    endSimpleBlock(p, scope)

proc genParForStmt(p: BProc, t: PNode) =
  assert(t.len == 3)
  inc(p.withinLoop)
  genLineDir(p, t)

  preserveBreakIdx:
    let forLoopVar = t[0].sym
    assignLocalVar(p, t[0])
    #initLoc(forLoopVar.loc, locLocalVar, forLoopVar.typ, onStack)
    #discard mangleName(forLoopVar)
    let call = t[1]
    assert(call.len == 4 or call.len == 5)
    var rangeA = initLocExpr(p, call[1])
    var rangeB = initLocExpr(p, call[2])

    var stepNode: PNode = nil
    # $n at the beginning because of #9710
    if call.len == 4: # procName(a, b, annotation)
      if call[0].sym.name.s == "||":  # `||`(a, b, annotation)
        p.s(cpsStmts).addCPragma("omp " & call[3].getStr)
      else:
        p.s(cpsStmts).addCPragma(call[3].getStr)
    else: # `||`(a, b, step, annotation)
      stepNode = call[3]
      p.s(cpsStmts).addCPragma("omp " & call[4].getStr)

    p.breakIdx = startBlockWith(p):
      if stepNode == nil:
        initForRange(p.s(cpsStmts), forLoopVar.loc.rdLoc, rangeA.rdLoc, rangeB.rdLoc, true)
      else:
        var step: TLoc = initLocExpr(p, stepNode)
        initForStep(p.s(cpsStmts), forLoopVar.loc.rdLoc, rangeA.rdLoc, rangeB.rdLoc, step.rdLoc, true)
    p.blocks[p.breakIdx].isLoop = true
    genStmts(p, t[2])
    endBlockWith(p):
      finishFor(p.s(cpsStmts))

  dec(p.withinLoop)

proc genBreakStmt(p: BProc, t: PNode) =
  var idx = p.breakIdx
  if t[0].kind != nkEmpty:
    # named break?
    assert(t[0].kind == nkSym)
    var sym = t[0].sym
    doAssert(sym.loc.k == locOther)
    idx = sym.position-1
  else:
    # an unnamed 'break' can only break a loop after 'transf' pass:
    while idx >= 0 and not p.blocks[idx].isLoop: dec idx
    if idx < 0 or not p.blocks[idx].isLoop:
      internalError(p.config, t.info, "no loop to break")
  p.blocks[idx].label = "LA" & p.blocks[idx].id.rope
  blockLeaveActions(p,
    p.nestedTryStmts.len - p.blocks[idx].nestedTryStmts,
    p.inExceptBlockLen - p.blocks[idx].nestedExceptStmts)
  genLineDir(p, t)
  p.s(cpsStmts).addGoto(p.blocks[idx].label)

proc raiseExit(p: BProc) =
  assert p.config.exc == excGoto
  if nimErrorFlagDisabled notin p.flags:
    p.flags.incl nimErrorFlagAccessed
    p.s(cpsStmts).addSingleIfStmt(cUnlikely(cDeref("nimErr_"))):
      if p.nestedTryStmts.len == 0:
        p.flags.incl beforeRetNeeded
        # easy case, simply goto 'ret':
        p.s(cpsStmts).addGoto("BeforeRet_")
      else:
        p.s(cpsStmts).addGoto("LA" & $p.nestedTryStmts[^1].label & "_")

proc raiseExitCleanup(p: BProc, destroy: string) =
  assert p.config.exc == excGoto
  if nimErrorFlagDisabled notin p.flags:
    p.flags.incl nimErrorFlagAccessed
    p.s(cpsStmts).addSingleIfStmt(cUnlikely(cDeref("nimErr_"))):
      p.s(cpsStmts).addStmt():
        p.s(cpsStmts).add(destroy)
      if p.nestedTryStmts.len == 0:
        p.flags.incl beforeRetNeeded
        # easy case, simply goto 'ret':
        p.s(cpsStmts).addGoto("BeforeRet_")
      else:
        p.s(cpsStmts).addGoto("LA" & $p.nestedTryStmts[^1].label & "_")

proc finallyActions(p: BProc) =
  if p.config.exc != excGoto and p.nestedTryStmts.len > 0 and p.nestedTryStmts[^1].inExcept:
    # if the current try stmt have a finally block,
    # we must execute it before reraising
    let finallyBlock = p.nestedTryStmts[^1].fin
    if finallyBlock != nil:
      genSimpleBlock(p, finallyBlock[0])

proc raiseInstr(p: BProc; result: var Builder) =
  if p.config.exc == excGoto:
    let L = p.nestedTryStmts.len
    if L == 0:
      p.flags.incl beforeRetNeeded
      # easy case, simply goto 'ret':
      result.addGoto("BeforeRet_")
    else:
      # raise inside an 'except' must go to the finally block,
      # raise outside an 'except' block must go to the 'except' list.
      result.addGoto("LA" & $p.nestedTryStmts[L-1].label & "_")
      # + ord(p.nestedTryStmts[L-1].inExcept)])

proc genRaiseStmt(p: BProc, t: PNode) =
  if t[0].kind != nkEmpty:
    var a: TLoc = initLocExprSingleUse(p, t[0])
    finallyActions(p)
    var e = rdLoc(a)
    discard getTypeDesc(p.module, t[0].typ)
    var typ = skipTypes(t[0].typ, abstractPtrs)
    case p.config.exc
    of excCpp:
      blockLeaveActions(p, howManyTrys = 0, howManyExcepts = p.inExceptBlockLen)
    of excGoto:
      blockLeaveActions(p, howManyTrys = 0,
        howManyExcepts = (if p.nestedTryStmts.len > 0 and p.nestedTryStmts[^1].inExcept: 1 else: 0))
    else:
      discard
    genLineDir(p, t)
    if isImportedException(typ, p.config):
      lineF(p, cpsStmts, "throw $1;$n", [e])
    else:
      let eName = makeCString(typ.sym.name.s)
      let pName = makeCString(if p.prc != nil: p.prc.name.s else: p.module.module.name.s)
      let fName = quotedFilename(p.config, t.info)
      let ln = toLinenumber(t.info)
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "raiseExceptionEx"),
        cCast(ptrType(cgsymValue(p.module, "Exception")), e),
        eName,
        pName,
        fName,
        cIntValue(ln))
      if optOwnedRefs in p.config.globalOptions:
        p.s(cpsStmts).addAssignment(e, "NIM_NIL")
  else:
    finallyActions(p)
    genLineDir(p, t)
    p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "reraiseException"))
  raiseInstr(p, p.s(cpsStmts))

template genCaseGenericBranch(p: BProc, b: PNode, e: TLoc,
                          rangeFormat, eqFormat: FormatStr, labl: TLabel) =
  var x, y: TLoc
  for i in 0..<b.len - 1:
    if b[i].kind == nkRange:
      x = initLocExpr(p, b[i][0])
      y = initLocExpr(p, b[i][1])
      lineCg(p, cpsStmts, rangeFormat,
           [rdCharLoc(e), rdCharLoc(x), rdCharLoc(y), labl])
    else:
      x = initLocExpr(p, b[i])
      lineCg(p, cpsStmts, eqFormat, [rdCharLoc(e), rdCharLoc(x), labl])

proc genCaseSecondPass(p: BProc, t: PNode, d: var TLoc,
                       labId, until: int): TLabel =
  var lend = getLabel(p)
  for i in 1..until:
    # bug #4230: avoid false sharing between branches:
    if d.k == locTemp and isEmptyType(t.typ): d.k = locNone
    p.s(cpsStmts).addLabel("LA" & $(labId + i) & "_")
    if t[i].kind == nkOfBranch:
      exprBlock(p, t[i][^1], d)
      p.s(cpsStmts).addGoto(lend)
    else:
      exprBlock(p, t[i][0], d)
  result = lend

template genIfForCaseUntil(p: BProc, t: PNode, d: var TLoc,
                       rangeFormat, eqFormat: FormatStr,
                       until: int, a: TLoc): TLabel =
  # XXX doesn't work with cbuilder
  # generate a C-if statement for a Nim case statement
  var res: TLabel
  var labId = p.labels
  for i in 1..until:
    inc(p.labels)
    let lab = "LA" & $p.labels & "_"
    if t[i].kind == nkOfBranch: # else statement
      genCaseGenericBranch(p, t[i], a, rangeFormat, eqFormat, lab)
    else:
      p.s(cpsStmts).addGoto(lab)
  if until < t.len-1:
    inc(p.labels)
    var gotoTarget = "LA" & $p.labels & "_"
    p.s(cpsStmts).addGoto(gotoTarget)
    res = genCaseSecondPass(p, t, d, labId, until)
    p.s(cpsStmts).addLabel(gotoTarget)
  else:
    res = genCaseSecondPass(p, t, d, labId, until)
  res

template genCaseGeneric(p: BProc, t: PNode, d: var TLoc,
                    rangeFormat, eqFormat: FormatStr) =
  # XXX doesn't work with cbuilder
  var a: TLoc = initLocExpr(p, t[0])
  var lend = genIfForCaseUntil(p, t, d, rangeFormat, eqFormat, t.len-1, a)
  fixLabel(p, lend)

proc genCaseStringBranch(p: BProc, b: PNode, e: TLoc, labl: TLabel,
                         stringKind: TTypeKind,
                         branches: var openArray[Builder]) =
  var x: TLoc
  for i in 0..<b.len - 1:
    assert(b[i].kind != nkRange)
    x = initLocExpr(p, b[i])
    var j: int = 0
    case b[i].kind
    of nkStrLit..nkTripleStrLit:
      j = int(hashString(p.config, b[i].strVal) and high(branches))
    of nkNilLit: j = 0
    else:
      assert false, "invalid string case branch node kind"
    let re = rdLoc(e)
    let rx = rdLoc(x)
    branches[j].addSingleIfStmtWithCond():
      let eqName = if stringKind == tyCstring: "eqCstrings" else: "eqStrings"
      branches[j].addCall(cgsymValue(p.module, eqName), re, rx)
    do:
      branches[j].addGoto(labl)

proc genStringCase(p: BProc, t: PNode, stringKind: TTypeKind, d: var TLoc) =
  # count how many constant strings there are in the case:
  var strings = 0
  for i in 1..<t.len:
    if t[i].kind == nkOfBranch: inc(strings, t[i].len - 1)
  if strings > stringCaseThreshold:
    var bitMask = math.nextPowerOfTwo(strings) - 1
    var branches: seq[Builder]
    newSeq(branches, bitMask + 1)
    var a: TLoc = initLocExpr(p, t[0]) # first pass: generate ifs+goto:
    var labId = p.labels
    for i in 1..<t.len:
      inc(p.labels)
      if t[i].kind == nkOfBranch:
        genCaseStringBranch(p, t[i], a, "LA" & rope(p.labels) & "_",
                            stringKind, branches)
      else:
        # else statement: nothing to do yet
        # but we reserved a label, which we use later
        discard
    let fnName = if stringKind == tyCstring: "hashCstring" else: "hashString"
    let ra = rdLoc(a)
    p.s(cpsStmts).addSwitchStmt(
      cOp(BitAnd, "NI",
        cCall(cgsymValue(p.module, fnName), ra),
        cIntValue(bitMask))):
      for j in 0..high(branches):
        if branches[j].buf.len != 0:
          let lit = cIntLiteral(j)
          p.s(cpsStmts).addSingleSwitchCase(lit):
            p.s(cpsStmts).add(extract(branches[j]))
            p.s(cpsStmts).addBreak()
    # else statement:
    if t[^1].kind != nkOfBranch:
      p.s(cpsStmts).addGoto("LA" & rope(p.labels) & "_")
    # third pass: generate statements
    var lend = genCaseSecondPass(p, t, d, labId, t.len-1)
    fixLabel(p, lend)
  else:
    if stringKind == tyCstring:
      genCaseGeneric(p, t, d, "", "if (#eqCstrings($1, $2)) goto $3;$n")
    else:
      genCaseGeneric(p, t, d, "", "if (#eqStrings($1, $2)) goto $3;$n")

proc branchHasTooBigRange(b: PNode): bool =
  result = false
  for it in b:
    # last son is block
    if (it.kind == nkRange) and
        it[1].intVal - it[0].intVal > RangeExpandLimit:
      return true

proc ifSwitchSplitPoint(p: BProc, n: PNode): int =
  result = 0
  for i in 1..<n.len:
    var branch = n[i]
    var stmtBlock = lastSon(branch)
    if stmtBlock.stmtsContainPragma(wLinearScanEnd):
      result = i
    elif hasSwitchRange notin CC[p.config.cCompiler].props:
      if branch.kind == nkOfBranch and branchHasTooBigRange(branch):
        result = i

proc genCaseRange(p: BProc, branch: PNode, info: var SwitchCaseBuilder) =
  for j in 0..<branch.len-1:
    if branch[j].kind == nkRange:
      if hasSwitchRange in CC[p.config.cCompiler].props:
        var litA = newBuilder("")
        var litB = newBuilder("")
        genLiteral(p, branch[j][0], litA)
        genLiteral(p, branch[j][1], litB)
        p.s(cpsStmts).addCaseRange(info, extract(litA), extract(litB))
      else:
        var v = copyNode(branch[j][0])
        while v.intVal <= branch[j][1].intVal:
          var litA = newBuilder("")
          genLiteral(p, v, litA)
          p.s(cpsStmts).addCase(info, extract(litA))
          inc(v.intVal)
    else:
      var litA = newBuilder("")
      genLiteral(p, branch[j], litA)
      p.s(cpsStmts).addCase(info, extract(litA))

proc genOrdinalCase(p: BProc, n: PNode, d: var TLoc) =
  # analyse 'case' statement:
  var splitPoint = ifSwitchSplitPoint(p, n)

  # generate if part (might be empty):
  var a: TLoc = initLocExpr(p, n[0])
  var lend = if splitPoint > 0: genIfForCaseUntil(p, n, d,
                    rangeFormat = "if ($1 >= $2 && $1 <= $3) goto $4;$n",
                    eqFormat = "if ($1 == $2) goto $3;$n",
                    splitPoint, a) else: ""

  # generate switch part (might be empty):
  if splitPoint+1 < n.len:
    let rca = rdCharLoc(a)
    p.s(cpsStmts).addSwitchStmt(rca):
      var hasDefault = false
      for i in splitPoint+1..<n.len:
        # bug #4230: avoid false sharing between branches:
        if d.k == locTemp and isEmptyType(n.typ): d.k = locNone
        var branch = n[i]
        var caseBuilder: SwitchCaseBuilder
        p.s(cpsStmts).addSwitchCase(caseBuilder):
          if branch.kind == nkOfBranch:
            genCaseRange(p, branch, caseBuilder)
          else:
            # else part of case statement:
            hasDefault = true
            p.s(cpsStmts).addCaseElse(caseBuilder)
        do:
          exprBlock(p, branch.lastSon, d)
          p.s(cpsStmts).addBreak()
      if not hasDefault:
        if hasBuiltinUnreachable in CC[p.config.cCompiler].props:
          p.s(cpsStmts).addSwitchElse():
            p.s(cpsStmts).addCallStmt("__builtin_unreachable")
        elif hasAssume in CC[p.config.cCompiler].props:
          p.s(cpsStmts).addSwitchElse():
            p.s(cpsStmts).addCallStmt("__assume", cIntValue(0))
  if lend != "": fixLabel(p, lend)

proc genCase(p: BProc, t: PNode, d: var TLoc) =
  genLineDir(p, t)
  if not isEmptyType(t.typ) and d.k == locNone:
    d = getTemp(p, t.typ)
  case skipTypes(t[0].typ, abstractVarRange).kind
  of tyString:
    genStringCase(p, t, tyString, d)
  of tyCstring:
    genStringCase(p, t, tyCstring, d)
  of tyFloat..tyFloat128:
    genCaseGeneric(p, t, d, "if ($1 >= $2 && $1 <= $3) goto $4;$n",
                            "if ($1 == $2) goto $3;$n")
  else:
    if t[0].kind == nkSym and sfGoto in t[0].sym.flags:
      genGotoForCase(p, t)
    else:
      genOrdinalCase(p, t, d)

proc genRestoreFrameAfterException(p: BProc) =
  if optStackTrace in p.module.config.options:
    if hasCurFramePointer notin p.flags:
      p.flags.incl hasCurFramePointer
      p.procSec(cpsLocals).add('\t')
      p.procSec(cpsLocals).addVar(kind = Local, name = "_nimCurFrame", typ = ptrType("TFrame"))
      p.procSec(cpsInit).add('\t')
      p.procSec(cpsInit).addAssignmentWithValue("_nimCurFrame"):
        p.procSec(cpsInit).addCall(cgsymValue(p.module, "getFrame"))
    p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "setFrame"), "_nimCurFrame")

proc genTryCpp(p: BProc, t: PNode, d: var TLoc) =
  #[ code to generate:

    std::exception_ptr error;
    try {
      body;
    } catch (Exception e) {
      error = std::current_exception();
      if (ofExpr(e, TypeHere)) {

        error = nullptr; // handled
      } else if (...) {

      } else {
        throw;
      }
    } catch(...) {
      // C++ exception occured, not under Nim's control.
    }
    {
      /* finally: */
      printf('fin!\n');
      if (error) std::rethrow_exception(error); // re-raise the exception
    }
  ]#
  p.module.includeHeader("<exception>")

  if not isEmptyType(t.typ) and d.k == locNone:
    d = getTemp(p, t.typ)
  genLineDir(p, t)

  inc(p.labels, 2)
  let etmp = p.labels
  #init on locals, fixes #23306
  lineCg(p, cpsLocals, "std::exception_ptr T$1_;$n", [etmp])

  let fin = if t[^1].kind == nkFinally: t[^1] else: nil
  p.nestedTryStmts.add((fin, false, 0.Natural))

  if t.kind == nkHiddenTryStmt:
    lineCg(p, cpsStmts, "try {$n", [])
    expr(p, t[0], d)
    lineCg(p, cpsStmts, "}$n", [])
  else:
    startBlockWith(p):
      p.s(cpsStmts).add("try {\n")
    expr(p, t[0], d)
    endBlockWith(p):
      p.s(cpsStmts).add("}\n")

  # First pass: handle Nim based exceptions:
  lineCg(p, cpsStmts, "catch (#Exception* T$1_) {$n", [etmp+1])
  genRestoreFrameAfterException(p)
  # an unhandled exception happened!
  lineCg(p, cpsStmts, "T$1_ = std::current_exception();$n", [etmp])
  p.nestedTryStmts[^1].inExcept = true
  var hasImportedCppExceptions = false
  var i = 1
  var ifStmt = default(IfBuilder)
  var hasIf = false
  var hasElse = false
  while (i < t.len) and (t[i].kind == nkExceptBranch):
    # bug #4230: avoid false sharing between branches:
    if d.k == locTemp and isEmptyType(t.typ): d.k = locNone
    if t[i].len == 1:
      hasImportedCppExceptions = true
      hasElse = true
      # general except section:
      var scope = default(ScopeBuilder)
      startBlockWith(p):
        if hasIf:
          initElseBranch(p.s(cpsStmts), ifStmt)
        else:
          scope = initScope(p.s(cpsStmts))
      # we handled the error:
      expr(p, t[i][0], d)
      linefmt(p, cpsStmts, "#popCurrentException();$n", [])
      endBlockWith(p):
        if hasIf:
          finishBranch(p.s(cpsStmts), ifStmt)
        else:
          finishScope(p.s(cpsStmts), scope)
    else:
      var orExpr = newRopeAppender()
      var exvar = PNode(nil)
      for j in 0..<t[i].len - 1:
        var typeNode = t[i][j]
        if t[i][j].isInfixAs():
          typeNode = t[i][j][1]
          exvar = t[i][j][2] # ex1 in `except ExceptType as ex1:`
        assert(typeNode.kind == nkType)
        if isImportedException(typeNode.typ, p.config):
          hasImportedCppExceptions = true
        else:
          if orExpr.len != 0: orExpr.add("||")
          let memberName = if p.module.compileToCpp: "m_type" else: "Sup.m_type"
          if optTinyRtti in p.config.globalOptions:
            let checkFor = $getObjDepth(typeNode.typ)
            appcg(p.module, orExpr, "#isObjDisplayCheck(#nimBorrowCurrentException()->$1, $2, $3)", [memberName, checkFor, $genDisplayElem(MD5Digest(hashType(typeNode.typ, p.config)))])
          else:
            let checkFor = genTypeInfoV1(p.module, typeNode.typ, typeNode.info)
            appcg(p.module, orExpr, "#isObj(#nimBorrowCurrentException()->$1, $2)", [memberName, checkFor])

      if orExpr.len != 0:
        if not hasIf:
          hasIf = true
          ifStmt = initIfStmt(p.s(cpsStmts))
        startBlockWith(p):
          initElifBranch(p.s(cpsStmts), ifStmt, orExpr)
        if exvar != nil:
          fillLocalName(p, exvar.sym)
          fillLoc(exvar.sym.loc, locTemp, exvar, OnStack)
          linefmt(p, cpsStmts, "$1 $2 = T$3_;$n", [getTypeDesc(p.module, exvar.sym.typ),
            rdLoc(exvar.sym.loc), rope(etmp+1)])
        # we handled the error:
        linefmt(p, cpsStmts, "T$1_ = nullptr;$n", [etmp])
        expr(p, t[i][^1], d)
        linefmt(p, cpsStmts, "#popCurrentException();$n", [])
        endBlockWith(p):
          finishBranch(p.s(cpsStmts), ifStmt)
    inc(i)
  if hasIf and not hasElse:
    p.s(cpsStmts).addElseBranch(ifStmt):
      p.s(cpsStmts).add("throw;\n")
  if hasIf:
    finishIfStmt(p.s(cpsStmts), ifStmt)
  linefmt(p, cpsStmts, "}$n", [])

  # Second pass: handle C++ based exceptions:
  template genExceptBranchBody(body: PNode) {.dirty.} =
    genRestoreFrameAfterException(p)
    #linefmt(p, cpsStmts, "T$1_ = std::current_exception();$n", [etmp])
    expr(p, body, d)

  var catchAllPresent = false
  incl p.flags, noSafePoints # mark as not needing 'popCurrentException'
  if hasImportedCppExceptions:
    for i in 1..<t.len:
      if t[i].kind != nkExceptBranch: break

      # bug #4230: avoid false sharing between branches:
      if d.k == locTemp and isEmptyType(t.typ): d.k = locNone

      if t[i].len == 1:
        # general except section:
        startBlockWith(p):
          p.s(cpsStmts).add("catch (...) {\n")
        genExceptBranchBody(t[i][0])
        endBlockWith(p):
          p.s(cpsStmts).add("}\n")
        catchAllPresent = true
      else:
        for j in 0..<t[i].len-1:
          var typeNode = t[i][j]
          if t[i][j].isInfixAs():
            typeNode = t[i][j][1]
            if isImportedException(typeNode.typ, p.config):
              let exvar = t[i][j][2] # ex1 in `except ExceptType as ex1:`
              fillLocalName(p, exvar.sym)
              fillLoc(exvar.sym.loc, locTemp, exvar, OnStack)
              startBlockWith(p):
                lineCg(p, cpsStmts, "catch ($1& $2) {$n", [getTypeDesc(p.module, typeNode.typ), rdLoc(exvar.sym.loc)])
              genExceptBranchBody(t[i][^1])  # exception handler body will duplicated for every type
              endBlockWith(p):
                p.s(cpsStmts).add("}\n")
          elif isImportedException(typeNode.typ, p.config):
            startBlockWith(p):
              lineCg(p, cpsStmts, "catch ($1&) {$n", [getTypeDesc(p.module, t[i][j].typ)])
            genExceptBranchBody(t[i][^1])  # exception handler body will duplicated for every type
            endBlockWith(p):
              p.s(cpsStmts).add("}\n")

  excl p.flags, noSafePoints
  discard pop(p.nestedTryStmts)
  # general finally block:
  if t.len > 0 and t[^1].kind == nkFinally:
    if not catchAllPresent:
      startBlockWith(p):
        p.s(cpsStmts).add("catch (...) {\n")
      genRestoreFrameAfterException(p)
      linefmt(p, cpsStmts, "T$1_ = std::current_exception();$n", [etmp])
      endBlockWith(p):
        p.s(cpsStmts).add("}\n")

    var scope: ScopeBuilder
    startSimpleBlock(p, scope)
    genStmts(p, t[^1][0])
    linefmt(p, cpsStmts, "if (T$1_) std::rethrow_exception(T$1_);$n", [etmp])
    endSimpleBlock(p, scope)

proc genTryCppOld(p: BProc, t: PNode, d: var TLoc) =
  # There are two versions we generate, depending on whether we
  # catch C++ exceptions, imported via .importcpp or not. The
  # code can be easier if there are no imported C++ exceptions
  # to deal with.

  # code to generate:
  #
  #   try
  #   {
  #      myDiv(4, 9);
  #   } catch (NimExceptionType1&) {
  #      body
  #   } catch (NimExceptionType2&) {
  #      finallyPart()
  #      raise;
  #   }
  #   catch(...) {
  #     general_handler_body
  #   }
  #   finallyPart();

  template genExceptBranchBody(body: PNode) {.dirty.} =
    genRestoreFrameAfterException(p)
    expr(p, body, d)

  if not isEmptyType(t.typ) and d.k == locNone:
    d = getTemp(p, t.typ)
  genLineDir(p, t)
  cgsym(p.module, "popCurrentExceptionEx")
  let fin = if t[^1].kind == nkFinally: t[^1] else: nil
  p.nestedTryStmts.add((fin, false, 0.Natural))
  startBlockWith(p):
    p.s(cpsStmts).add("try {\n")
  expr(p, t[0], d)
  endBlockWith(p):
    p.s(cpsStmts).add("}\n")

  var catchAllPresent = false

  p.nestedTryStmts[^1].inExcept = true
  for i in 1..<t.len:
    if t[i].kind != nkExceptBranch: break

    # bug #4230: avoid false sharing between branches:
    if d.k == locTemp and isEmptyType(t.typ): d.k = locNone

    if t[i].len == 1:
      # general except section:
      catchAllPresent = true
      startBlockWith(p):
        p.s(cpsStmts).add("catch (...) {\n")
      genExceptBranchBody(t[i][0])
      endBlockWith(p):
        p.s(cpsStmts).add("}\n")
    else:
      for j in 0..<t[i].len-1:
        if t[i][j].isInfixAs():
          let exvar = t[i][j][2] # ex1 in `except ExceptType as ex1:`
          fillLocalName(p, exvar.sym)
          fillLoc(exvar.sym.loc, locTemp, exvar, OnUnknown)
          startBlockWith(p):
            lineCg(p, cpsStmts, "catch ($1& $2) {$n", [getTypeDesc(p.module, t[i][j][1].typ), rdLoc(exvar.sym.loc)])
        else:
          startBlockWith(p):
            lineCg(p, cpsStmts, "catch ($1&) {$n", [getTypeDesc(p.module, t[i][j].typ)])
        genExceptBranchBody(t[i][^1])  # exception handler body will duplicated for every type
        endBlockWith(p):
          p.s(cpsStmts).add("}\n")

  discard pop(p.nestedTryStmts)

  if t[^1].kind == nkFinally:
    # c++ does not have finally, therefore code needs to be generated twice
    if not catchAllPresent:
      # finally requires catch all presence
      startBlockWith(p):
        p.s(cpsStmts).add("catch (...) {\n")
      genStmts(p, t[^1][0])
      line(p, cpsStmts, "throw;\n")
      endBlockWith(p):
        p.s(cpsStmts).add("}\n")

    genSimpleBlock(p, t[^1][0])

proc bodyCanRaise(p: BProc; n: PNode): bool =
  case n.kind
  of nkCallKinds:
    result = canRaiseDisp(p, n[0])
    if not result:
      # also check the arguments:
      for i in 1 ..< n.len:
        if bodyCanRaise(p, n[i]): return true
  of nkRaiseStmt:
    result = true
  of nkTypeSection, nkProcDef, nkConverterDef, nkMethodDef, nkIteratorDef,
      nkMacroDef, nkTemplateDef, nkLambda, nkDo, nkFuncDef:
    result = false
  else:
    for i in 0 ..< safeLen(n):
      if bodyCanRaise(p, n[i]): return true
    result = false

proc genTryGoto(p: BProc; t: PNode; d: var TLoc) =
  let fin = if t[^1].kind == nkFinally: t[^1] else: nil
  inc p.labels
  let lab = p.labels
  let hasExcept = t[1].kind == nkExceptBranch
  if hasExcept: inc p.withinTryWithExcept
  p.nestedTryStmts.add((fin, false, Natural lab))

  p.flags.incl nimErrorFlagAccessed

  if not isEmptyType(t.typ) and d.k == locNone:
    d = getTemp(p, t.typ)

  expr(p, t[0], d)

  var ifStmt = default(IfBuilder)
  var scope = default(ScopeBuilder)
  var isIf = false
  if 1 < t.len and t[1].kind == nkExceptBranch:
    startBlockWith(p):
      isIf = true
      ifStmt = initIfStmt(p.s(cpsStmts))
      initElifBranch(p.s(cpsStmts), ifStmt, cUnlikely(cDeref("nimErr_")))
  else:
    startBlockWith(p):
      scope = initScope(p.s(cpsStmts))
  p.s(cpsStmts).addLabel("LA" & $lab & "_")

  p.nestedTryStmts[^1].inExcept = true
  var i = 1
  var innerIfStmt = default(IfBuilder)
  var innerScope = default(ScopeBuilder)
  var innerIsIf = false
  while (i < t.len) and (t[i].kind == nkExceptBranch):

    inc p.labels
    let nextExcept = p.labels
    p.nestedTryStmts[^1].label = nextExcept

    var isScope = false
    # bug #4230: avoid false sharing between branches:
    if d.k == locTemp and isEmptyType(t.typ): d.k = locNone
    if t[i].len == 1:
      # general except section:
      startBlockWith(p):
        if innerIsIf:
          initElseBranch(p.s(cpsStmts), innerIfStmt)
        else:
          isScope = true
          innerScope = initScope(p.s(cpsStmts))
      # we handled the exception, remember this:
      p.s(cpsStmts).addAssignment(cDeref("nimErr_"), "NIM_FALSE")
      expr(p, t[i][0], d)
    else:
      if not innerIsIf:
        innerIsIf = true
        innerIfStmt = initIfStmt(p.s(cpsStmts))
      var orExpr: Snippet = ""
      for j in 0..<t[i].len - 1:
        assert(t[i][j].kind == nkType)
        var excVal = cCall(cgsymValue(p.module, "nimBorrowCurrentException"))
        let member =
          if p.module.compileToCpp:
            derefField(excVal, "m_type")
          else:
            dotField(derefField(excVal, "Sup"), "m_type")
        var branch: Snippet = ""
        if optTinyRtti in p.config.globalOptions:
          let checkFor = $getObjDepth(t[i][j].typ)
          branch = cCall(cgsymValue(p.module, "isObjDisplayCheck"),
            member,
            checkFor,
            $genDisplayElem(MD5Digest(hashType(t[i][j].typ, p.config))))
        else:
          let checkFor = genTypeInfoV1(p.module, t[i][j].typ, t[i][j].info)
          branch = cCall(cgsymValue(p.module, "isObj"),
            member,
            checkFor)
        if orExpr.len == 0:
          orExpr = branch
        else:
          orExpr = cOp(Or, orExpr, branch)

      startBlockWith(p):
        initElifBranch(p.s(cpsStmts), innerIfStmt, orExpr)
      # we handled the exception, remember this:
      p.s(cpsStmts).addAssignment(cDeref("nimErr_"), "NIM_FALSE")
      expr(p, t[i][^1], d)

    p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "popCurrentException"))
    p.s(cpsStmts).addLabel("LA" & $nextExcept & "_")
    endBlockWith(p):
      if isScope:
        finishScope(p.s(cpsStmts), innerScope)
      else:
        finishBranch(p.s(cpsStmts), innerIfStmt)

    inc(i)
  if innerIsIf:
    finishIfStmt(p.s(cpsStmts), innerIfStmt)
  discard pop(p.nestedTryStmts)
  endBlockWith(p):
    if isIf:
      finishBranch(p.s(cpsStmts), ifStmt)
      finishIfStmt(p.s(cpsStmts), ifStmt)
    else:
      finishScope(p.s(cpsStmts), scope)

  if i < t.len and t[i].kind == nkFinally:
    var finallyScope: ScopeBuilder
    startSimpleBlock(p, finallyScope)
    if not bodyCanRaise(p, t[i][0]):
      # this is an important optimization; most destroy blocks are detected not to raise an
      # exception and so we help the C optimizer by not mutating nimErr_ pointlessly:
      genStmts(p, t[i][0])
    else:
      # pretend we did handle the error for the safe execution of the 'finally' section:
      p.procSec(cpsLocals).addVar(kind = Local, name = "oldNimErrFin" & $lab & "_", typ = "NIM_BOOL")
      p.s(cpsStmts).addAssignment("oldNimErrFin" & $lab & "_", cDeref("nimErr_"))
      p.s(cpsStmts).addAssignment(cDeref("nimErr_"), "NIM_FALSE")
      genStmts(p, t[i][0])
      # this is correct for all these cases:
      # 1. finally is run during ordinary control flow
      # 2. finally is run after 'except' block handling: these however set the
      #    error back to nil.
      # 3. finally is run for exception handling code without any 'except'
      #    handler present or only handlers that did not match.
      p.s(cpsStmts).addAssignment(cDeref("nimErr_"), "oldNimErrFin" & $lab & "_")
    endSimpleBlock(p, finallyScope)
  raiseExit(p)
  if hasExcept: inc p.withinTryWithExcept

proc genTrySetjmp(p: BProc, t: PNode, d: var TLoc) =
  # code to generate:
  #
  # XXX: There should be a standard dispatch algorithm
  # that's used both here and with multi-methods
  #
  #  TSafePoint sp;
  #  pushSafePoint(&sp);
  #  sp.status = setjmp(sp.context);
  #  if (sp.status == 0) {
  #    myDiv(4, 9);
  #    popSafePoint();
  #  } else {
  #    popSafePoint();
  #    /* except DivisionByZero: */
  #    if (sp.status == DivisionByZero) {
  #      printf('Division by Zero\n');
  #      clearException();
  #    } else {
  #      clearException();
  #    }
  #  }
  #  {
  #    /* finally: */
  #    printf('fin!\n');
  #  }
  #  if (exception not cleared)
  #    propagateCurrentException();
  #
  if not isEmptyType(t.typ) and d.k == locNone:
    d = getTemp(p, t.typ)
  let quirkyExceptions = p.config.exc == excQuirky or
      (t.kind == nkHiddenTryStmt and sfSystemModule in p.module.module.flags)
  if not quirkyExceptions:
    p.module.includeHeader("<setjmp.h>")
  else:
    p.flags.incl noSafePoints
  genLineDir(p, t)
  cgsym(p.module, "Exception")
  var safePoint: Rope = ""
  var nonQuirkyIf = default(IfBuilder)
  if not quirkyExceptions:
    safePoint = getTempName(p.module)
    p.s(cpsLocals).addVar(name = safePoint, typ = cgsymValue(p.module, "TSafePoint"))
    p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "pushSafePoint"), cAddr(safePoint))
    if isDefined(p.config, "nimStdSetjmp"):
      p.s(cpsStmts).addFieldAssignmentWithValue(safePoint, "status"):
        p.s(cpsStmts).addCall("setjmp", dotField(safePoint, "context"))
    elif isDefined(p.config, "nimSigSetjmp"):
      p.s(cpsStmts).addFieldAssignmentWithValue(safePoint, "status"):
        p.s(cpsStmts).addCall("sigsetjmp", dotField(safePoint, "context"), cIntValue(0))
    elif isDefined(p.config, "nimBuiltinSetjmp"):
      p.s(cpsStmts).addFieldAssignmentWithValue(safePoint, "status"):
        p.s(cpsStmts).addCall("__builtin_setjmp", dotField(safePoint, "context"))
    elif isDefined(p.config, "nimRawSetjmp"):
      if isDefined(p.config, "mswindows"):
        if isDefined(p.config, "vcc") or isDefined(p.config, "clangcl"):
          # For the vcc compiler, use `setjmp()` with one argument.
          # See https://docs.microsoft.com/en-us/cpp/c-runtime-library/reference/setjmp?view=msvc-170
          p.s(cpsStmts).addFieldAssignmentWithValue(safePoint, "status"):
            p.s(cpsStmts).addCall("setjmp", dotField(safePoint, "context"))
        else:
          # The Windows `_setjmp()` takes two arguments, with the second being an
          # undocumented buffer used by the SEH mechanism for stack unwinding.
          # Mingw-w64 has been trying to get it right for years, but it's still
          # prone to stack corruption during unwinding, so we disable that by setting
          # it to NULL.
          # More details: https://github.com/status-im/nimbus-eth2/issues/3121
          p.s(cpsStmts).addFieldAssignmentWithValue(safePoint, "status"):
            p.s(cpsStmts).addCall("_setjmp", dotField(safePoint, "context"), cIntValue(0))
      else:
          p.s(cpsStmts).addFieldAssignmentWithValue(safePoint, "status"):
            p.s(cpsStmts).addCall("_setjmp", dotField(safePoint, "context"))
    else:
      p.s(cpsStmts).addFieldAssignmentWithValue(safePoint, "status"):
        p.s(cpsStmts).addCall("setjmp", dotField(safePoint, "context"))
    nonQuirkyIf = initIfStmt(p.s(cpsStmts))
    initElifBranch(p.s(cpsStmts), nonQuirkyIf, removeSinglePar(
      cOp(Equal, dotField(safePoint, "status"), cIntValue(0))))
  let fin = if t[^1].kind == nkFinally: t[^1] else: nil
  p.nestedTryStmts.add((fin, quirkyExceptions, 0.Natural))
  expr(p, t[0], d)
  var quirkyIf = default(IfBuilder)
  var quirkyScope = default(ScopeBuilder)
  var isScope = false
  if not quirkyExceptions:
    p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "popSafePoint"))
    finishBranch(p.s(cpsStmts), nonQuirkyIf)
    startBlockWith(p):
      initElseBranch(p.s(cpsStmts), nonQuirkyIf)
    p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "popSafePoint"))
    genRestoreFrameAfterException(p)
  elif 1 < t.len and t[1].kind == nkExceptBranch:
    startBlockWith(p):
      quirkyIf = initIfStmt(p.s(cpsStmts))
      initElifBranch(p.s(cpsStmts), quirkyIf,
        cCall(cgsymValue(p.module, "nimBorrowCurrentException")))
  else:
    isScope = true
    startBlockWith(p):
      quirkyScope = initScope(p.s(cpsStmts))
  p.nestedTryStmts[^1].inExcept = true
  var i = 1
  var exceptIf = default(IfBuilder)
  var exceptIfInited = false
  while (i < t.len) and (t[i].kind == nkExceptBranch):
    # bug #4230: avoid false sharing between branches:
    if d.k == locTemp and isEmptyType(t.typ): d.k = locNone
    if t[i].len == 1:
      # general except section:
      var scope = default(ScopeBuilder)
      startBlockWith(p):
        if exceptIfInited:
          initElseBranch(p.s(cpsStmts), exceptIf)
        else:
          scope = initScope(p.s(cpsStmts))
      if not quirkyExceptions:
        p.s(cpsStmts).addFieldAssignment(safePoint, "status", cIntValue(0))
      expr(p, t[i][0], d)
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "popCurrentException"))
      endBlockWith(p):
        if exceptIfInited:
          finishBranch(p.s(cpsStmts), exceptIf)
        else:
          finishScope(p.s(cpsStmts), scope)
    else:
      var orExpr: Snippet = ""
      for j in 0..<t[i].len - 1:
        assert(t[i][j].kind == nkType)
        var excVal = cCall(cgsymValue(p.module, "nimBorrowCurrentException"))
        let member =
          if p.module.compileToCpp:
            derefField(excVal, "m_type")
          else:
            dotField(derefField(excVal, "Sup"), "m_type")
        var branch: Snippet = ""
        if optTinyRtti in p.config.globalOptions:
          let checkFor = $getObjDepth(t[i][j].typ)
          branch = cCall(cgsymValue(p.module, "isObjDisplayCheck"),
            member,
            checkFor,
            $genDisplayElem(MD5Digest(hashType(t[i][j].typ, p.config))))
        else:
          let checkFor = genTypeInfoV1(p.module, t[i][j].typ, t[i][j].info)
          branch = cCall(cgsymValue(p.module, "isObj"),
            member,
            checkFor)
        if orExpr.len == 0:
          orExpr = branch
        else:
          orExpr = cOp(Or, orExpr, branch)

      if not exceptIfInited:
        exceptIf = initIfStmt(p.s(cpsStmts))
        exceptIfInited = true
      startBlockWith(p):
        initElifBranch(p.s(cpsStmts), exceptIf, orExpr)
      if not quirkyExceptions:
        p.s(cpsStmts).addFieldAssignment(safePoint, "status", cIntValue(0))
      expr(p, t[i][^1], d)
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "popCurrentException"))
      endBlockWith(p):
        finishBranch(p.s(cpsStmts), exceptIf)
    inc(i)
  if exceptIfInited:
    finishIfStmt(p.s(cpsStmts), exceptIf)
  discard pop(p.nestedTryStmts)
  endBlockWith(p):
    # end of else block
    if not quirkyExceptions:
      finishBranch(p.s(cpsStmts), nonQuirkyIf)
      finishIfStmt(p.s(cpsStmts), nonQuirkyIf)
    elif isScope:
      finishScope(p.s(cpsStmts), quirkyScope)
    else:
      finishBranch(p.s(cpsStmts), quirkyIf)
      finishIfStmt(p.s(cpsStmts), quirkyIf)
  if i < t.len and t[i].kind == nkFinally:
    p.finallySafePoints.add(safePoint)
    var finallyScope: ScopeBuilder
    startSimpleBlock(p, finallyScope)
    genStmts(p, t[i][0])
    # pretend we handled the exception in a 'finally' so that we don't
    # re-raise the unhandled one but instead keep the old one (it was
    # not popped either):
    if not quirkyExceptions and getCompilerProc(p.module.g.graph, "nimLeaveFinally") != nil:
      p.s(cpsStmts).addSingleIfStmt(
        cOp(NotEqual,
          dotField(safePoint, "status"),
          cIntValue(0))):
        p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "nimLeaveFinally"))
    endSimpleBlock(p, finallyScope)
    discard pop(p.finallySafePoints)
  if not quirkyExceptions:
    p.s(cpsStmts).addSingleIfStmt(
      cOp(NotEqual,
        dotField(safePoint, "status"),
        cIntValue(0))):
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "reraiseException"))

proc genAsmOrEmitStmt(p: BProc, t: PNode, isAsmStmt=false; result: var Rope) =
  var res = ""
  let offset =
    if isAsmStmt: 1 # first son is pragmas
    else: 0

  for i in offset..<t.len:
    let it = t[i]
    case it.kind
    of nkStrLit..nkTripleStrLit:
      res.add(it.strVal)
    of nkSym:
      var sym = it.sym
      if sym.kind in {skProc, skFunc, skIterator, skMethod}:
        var a: TLoc = initLocExpr(p, it)
        res.add($rdLoc(a))
      elif sym.kind == skType:
        res.add($getTypeDesc(p.module, sym.typ))
      else:
        discard getTypeDesc(p.module, skipTypes(sym.typ, abstractPtrs))
        fillBackendName(p.module, sym)
        res.add($sym.loc.snippet)
    of nkTypeOfExpr:
      res.add($getTypeDesc(p.module, it.typ))
    else:
      discard getTypeDesc(p.module, skipTypes(it.typ, abstractPtrs))
      var a: TLoc = initLocExpr(p, it)
      res.add($a.rdLoc)

  if isAsmStmt and hasGnuAsm in CC[p.config.cCompiler].props:
    for x in splitLines(res):
      var j = 0
      while j < x.len and x[j] in {' ', '\t'}: inc(j)
      if j < x.len:
        if x[j] in {'"', ':'}:
          # don't modify the line if already in quotes or
          # some clobber register list:
          result.add(x); result.add("\L")
        else:
          # ignore empty lines
          result.add("\"")
          result.add(x.replace("\"", "\\\""))
          result.add("\\n\"\n")
  else:
    res.add("\L")
    result.add res.rope

proc genAsmStmt(p: BProc, t: PNode) =
  assert(t.kind == nkAsmStmt)
  genLineDir(p, t)
  var s = newRopeAppender()

  var asmSyntax = ""
  if (let p = t[0]; p.kind == nkPragma):
    for i in p:
      if whichPragma(i) == wAsmSyntax:
        asmSyntax = i[1].strVal

  if asmSyntax != "" and
     not (
      asmSyntax == "gcc" and hasGnuAsm in CC[p.config.cCompiler].props or
      asmSyntax == "vcc" and hasGnuAsm notin CC[p.config.cCompiler].props):
    localError(
      p.config, t.info,
      "Your compiler does not support the specified inline assembler")

  genAsmOrEmitStmt(p, t, isAsmStmt=true, s)
  # see bug #2362, "top level asm statements" seem to be a mis-feature
  # but even if we don't do this, the example in #2362 cannot possibly
  # work:
  if p.prc == nil:
    # top level asm statement?
    p.module.s[cfsProcHeaders].add runtimeFormat(CC[p.config.cCompiler].asmStmtFrmt, [s])
  else:
    addIndent p, p.s(cpsStmts)
    p.s(cpsStmts).add runtimeFormat(CC[p.config.cCompiler].asmStmtFrmt, [s])

proc determineSection(n: PNode): TCFileSection =
  result = cfsProcHeaders
  if n.len >= 1 and n[0].kind in {nkStrLit..nkTripleStrLit}:
    let sec = n[0].strVal
    if sec.startsWith("/*TYPESECTION*/"): result = cfsForwardTypes # TODO WORKAROUND
    elif sec.startsWith("/*VARSECTION*/"): result = cfsVars
    elif sec.startsWith("/*INCLUDESECTION*/"): result = cfsHeaders

proc genEmit(p: BProc, t: PNode) =
  var s = newRopeAppender()
  genAsmOrEmitStmt(p, t[1], false, s)
  if p.prc == nil:
    # top level emit pragma?
    let section = determineSection(t[1])
    genCLineDir(p.module.s[section], t.info, p.config)
    p.module.s[section].add(s)
  else:
    genLineDir(p, t)
    line(p, cpsStmts, s)

proc genPragma(p: BProc, n: PNode) =
  for i in 0..<n.len:
    let it = n[i]
    case whichPragma(it)
    of wEmit: genEmit(p, it)
    of wPush:
      processPushBackendOption(p.config, p.optionsStack, p.options, n, i+1)
    of wPop:
      processPopBackendOption(p.config, p.optionsStack, p.options)
    else: discard


proc genDiscriminantCheck(p: BProc, a, tmp: TLoc, objtype: PType,
                          field: PSym) =
  var t = skipTypes(objtype, abstractVar)
  assert t.kind == tyObject
  discard genTypeInfoV1(p.module, t, a.lode.info)
  if not containsOrIncl(p.module.declaredThings, field.id):
    p.module.s[cfsVars].addDeclWithVisibility(Extern):
      discriminatorTableDecl(p.module, t, field, p.module.s[cfsVars])
  let lit = cIntLiteral(toInt64(lengthOrd(p.config, field.typ))+1)
  let ra = rdLoc(a)
  let rtmp = rdLoc(tmp)
  let dn = discriminatorTableName(p.module, t, field)
  p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "FieldDiscriminantCheck"),
    cCast("NI", cCast("NU", ra)),
    cCast("NI", cCast("NU", rtmp)),
    dn,
    lit)
  if p.config.exc == excGoto:
    raiseExit(p)

when false:
  proc genCaseObjDiscMapping(p: BProc, e: PNode, t: PType, field: PSym; d: var TLoc) =
    const ObjDiscMappingProcSlot = -5
    var theProc: PSym = nil
    for idx, p in items(t.methods):
      if idx == ObjDiscMappingProcSlot:
        theProc = p
        break
    if theProc == nil:
      theProc = genCaseObjDiscMapping(t, field, e.info, p.module.g.graph, p.module.idgen)
      t.methods.add((ObjDiscMappingProcSlot, theProc))
    var call = newNodeIT(nkCall, e.info, getSysType(p.module.g.graph, e.info, tyUInt8))
    call.add newSymNode(theProc)
    call.add e
    expr(p, call, d)

proc asgnFieldDiscriminant(p: BProc, e: PNode) =
  var dotExpr = e[0]
  if dotExpr.kind == nkCheckedFieldExpr: dotExpr = dotExpr[0]
  var a = initLocExpr(p, e[0])
  var tmp: TLoc = getTemp(p, a.t)
  expr(p, e[1], tmp)
  if p.inUncheckedAssignSection == 0:
    let field = dotExpr[1].sym
    genDiscriminantCheck(p, a, tmp, dotExpr[0].typ, field)
    message(p.config, e.info, warnCaseTransition)
  genAssignment(p, a, tmp, {})

proc genAsgn(p: BProc, e: PNode, fastAsgn: bool) =
  if e[0].kind == nkSym and sfGoto in e[0].sym.flags:
    genLineDir(p, e)
    genGotoVar(p, e[1])
  elif optFieldCheck in p.options and isDiscriminantField(e[0]):
    genLineDir(p, e)
    asgnFieldDiscriminant(p, e)
  else:
    let le = e[0]
    let ri = e[1]
    var a: TLoc = initLoc(locNone, le, OnUnknown)
    discard getTypeDesc(p.module, le.typ.skipTypes(skipPtrs), dkVar)
    a.flags.incl(lfEnforceDeref)
    a.flags.incl(lfPrepareForMutation)
    genLineDir(p, le) # it can be a nkBracketExpr, which may raise
    expr(p, le, a)
    a.flags.excl(lfPrepareForMutation)
    if fastAsgn: incl(a.flags, lfNoDeepCopy)
    assert(a.t != nil)
    genLineDir(p, ri)
    loadInto(p, le, ri, a)

proc genStmts(p: BProc, t: PNode) =
  var a: TLoc = default(TLoc)

  let isPush = p.config.hasHint(hintExtendedContext)
  if isPush: pushInfoContext(p.config, t.info)
  expr(p, t, a)
  if isPush: popInfoContext(p.config)
  internalAssert p.config, a.k in {locNone, locTemp, locLocalVar, locExpr}

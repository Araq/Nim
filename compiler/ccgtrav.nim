#
#
#           The Nim Compiler
#        (c) Copyright 2013 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Generates traversal procs for the C backend.

# included from cgen.nim

type
  TTraversalClosure = object
    p: BProc
    visitorFrmt: string


proc genTraverseProc(c: TTraversalClosure, accessor: Rope, typ: PType)
proc genCaseRange(p: BProc, branch: PNode, info: var SwitchCaseBuilder)
proc getTemp(p: BProc, t: PType, needsInit=false): TLoc

proc visit(p: BProc, data, visitor: Snippet) =
  p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "nimGCvisit"),
    cCast(CPointer, data),
    visitor)

proc genTraverseProc(c: TTraversalClosure, accessor: Rope, n: PNode;
                     typ: PType) =
  if n == nil: return
  case n.kind
  of nkRecList:
    for i in 0..<n.len:
      genTraverseProc(c, accessor, n[i], typ)
  of nkRecCase:
    if (n[0].kind != nkSym): internalError(c.p.config, n.info, "genTraverseProc")
    var p = c.p
    let disc = n[0].sym
    if disc.loc.snippet == "": fillObjectFields(c.p.module, typ)
    if disc.loc.t == nil:
      internalError(c.p.config, n.info, "genTraverseProc()")
    let discField = dotField(accessor, disc.loc.snippet)
    p.s(cpsStmts).addSwitchStmt(discField):
      for i in 1..<n.len:
        let branch = n[i]
        assert branch.kind in {nkOfBranch, nkElse}
        var caseBuilder: SwitchCaseBuilder
        p.s(cpsStmts).addSwitchCase(caseBuilder):
          if branch.kind == nkOfBranch:
            genCaseRange(c.p, branch, caseBuilder)
          else:
            p.s(cpsStmts).addCaseElse(caseBuilder)
        do:
          genTraverseProc(c, accessor, lastSon(branch), typ)
          p.s(cpsStmts).addBreak()
  of nkSym:
    let field = n.sym
    if field.typ.kind == tyVoid: return
    if field.loc.snippet == "": fillObjectFields(c.p.module, typ)
    if field.loc.t == nil:
      internalError(c.p.config, n.info, "genTraverseProc()")
    genTraverseProc(c, dotField(accessor, field.loc.snippet), field.loc.t)
  else: internalError(c.p.config, n.info, "genTraverseProc()")

proc parentObj(accessor: Rope; m: BModule): Rope {.inline.} =
  if not m.compileToCpp:
    result = dotField(accessor, "Sup")
  else:
    result = accessor

proc genTraverseProcSeq(c: TTraversalClosure, accessor: Rope, typ: PType)
proc genTraverseProc(c: TTraversalClosure, accessor: Rope, typ: PType) =
  if typ == nil: return

  var p = c.p
  case typ.kind
  of tyGenericInst, tyGenericBody, tyTypeDesc, tyAlias, tyDistinct, tyInferred,
     tySink, tyOwned:
    genTraverseProc(c, accessor, skipModifier(typ))
  of tyArray:
    let arraySize = lengthOrd(c.p.config, typ.indexType)
    var i: TLoc = getTemp(p, getSysType(c.p.module.g.graph, unknownLineInfo, tyInt))
    var oldCode = p.s(cpsStmts)
    var oldLen, newLen: int
    p.s(cpsStmts).addForRangeExclusive(i.snippet, cIntValue(0), cIntValue(arraySize)):
      oldLen = p.s(cpsStmts).buf.len
      genTraverseProc(c, subscript(accessor, i.snippet), typ.elementType)
      newLen = p.s(cpsStmts).buf.len
    if oldLen == newLen:
      # do not emit dummy long loops for faster debug builds:
      p.s(cpsStmts) = oldCode
  of tyObject:
    var x = typ.baseClass
    if x != nil: x = x.skipTypes(skipPtrs)
    genTraverseProc(c, accessor.parentObj(c.p.module), x)
    if typ.n != nil: genTraverseProc(c, accessor, typ.n, typ)
  of tyTuple:
    let typ = getUniqueType(typ)
    for i, a in typ.ikids:
      genTraverseProc(c, dotField(accessor, "Field" & $i), a)
  of tyRef:
    visit(p, accessor, c.visitorFrmt)
  of tySequence:
    if optSeqDestructors notin c.p.module.config.globalOptions:
      visit(p, accessor, c.visitorFrmt)
    elif containsGarbageCollectedRef(typ.elementType):
      # destructor based seqs are themselves not traced but their data is, if
      # they contain a GC'ed type:
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "nimGCvisitSeq"),
        cCast(CPointer, accessor),
        c.visitorFrmt)
      #genTraverseProcSeq(c, accessor, typ)
  of tyString:
    if tfHasAsgn notin typ.flags:
      visit(p, accessor, c.visitorFrmt)
  of tyProc:
    if typ.callConv == ccClosure:
      visit(p, dotField(accessor, "ClE_0"), c.visitorFrmt)
  else:
    discard

proc genTraverseProcSeq(c: TTraversalClosure, accessor: Rope, typ: PType) =
  var p = c.p
  assert typ.kind == tySequence
  var i = getTemp(p, getSysType(c.p.module.g.graph, unknownLineInfo, tyInt))
  var oldCode = p.s(cpsStmts)
  var oldLen, newLen: int
  var a = TLoc(snippet: accessor)
  let le = lenExpr(c.p, a)

  p.s(cpsStmts).addForRangeExclusive(i.snippet, cIntValue(0), le):
    oldLen = p.s(cpsStmts).buf.len
    genTraverseProc(c, subscript(dataField(c.p, accessor), i.snippet), typ.elementType)
    newLen = p.s(cpsStmts).buf.len
  if newLen == oldLen:
    # do not emit dummy long loops for faster debug builds:
    p.s(cpsStmts) = oldCode

proc genTraverseProc(m: BModule, origTyp: PType; sig: SigHash): Rope =
  var p = newProc(nil, m)
  result = "Marker_" & getTypeName(m, origTyp, sig)
  let
    hcrOn = m.hcrOn
    typ = origTyp.skipTypes(abstractInstOwned)
    markerName = if hcrOn: result & "_actual" else: result
    t = getTypeDesc(m, typ)

  p.s(cpsLocals).addVar(kind = Local, name = "a", typ = t)
  p.s(cpsInit).addAssignment("a", cCast(t, "p"))

  var c = TTraversalClosure(p: p,
    visitorFrmt: "op" # "#nimGCvisit((void*)$1, op);$n"
    )

  assert typ.kind != tyTypeDesc
  if typ.kind == tySequence:
    genTraverseProcSeq(c, "a".rope, typ)
  else:
    if skipTypes(typ.elementType, typedescInst+{tyOwned}).kind == tyArray:
      # C's arrays are broken beyond repair:
      genTraverseProc(c, "a".rope, typ.elementType)
    else:
      genTraverseProc(c, cDeref("a"), typ.elementType)

  var headerBuilder = newBuilder("")
  headerBuilder.addProcHeaderWithParams(ccNimCall, markerName, CVoid):
    var paramBuilder: ProcParamBuilder
    headerBuilder.addProcParams(paramBuilder):
      headerBuilder.addParam(paramBuilder, name = "p", typ = CPointer)
      headerBuilder.addParam(paramBuilder, name = "op", typ = NimInt)
  let header = extract(headerBuilder)

  m.s[cfsProcHeaders].addDeclWithVisibility(StaticProc):
    m.s[cfsProcHeaders].add(header)
    m.s[cfsProcHeaders].finishProcHeaderAsProto()
  m.s[cfsProcs].addDeclWithVisibility(StaticProc):
    m.s[cfsProcs].add(header)
    m.s[cfsProcs].finishProcHeaderWithBody():
      m.s[cfsProcs].add(extract(p.s(cpsLocals)))
      m.s[cfsProcs].add(extract(p.s(cpsInit)))
      m.s[cfsProcs].add(extract(p.s(cpsStmts)))

  if hcrOn:
    var desc = newBuilder("")
    var unnamedParamBuilder: ProcParamBuilder
    desc.addProcParams(unnamedParamBuilder):
      desc.addUnnamedParam(unnamedParamBuilder, CPointer)
      desc.addUnnamedParam(unnamedParamBuilder, NimInt)
    let unnamedParams = extract(desc)
    m.s[cfsProcHeaders].addProcVar(ccNimCall, result, unnamedParams, CVoid)
    m.s[cfsDynLibInit].addAssignmentWithValue(result):
      m.s[cfsDynLibInit].addCast(procPtrTypeUnnamed(ccNimCall, CVoid, unnamedParams)):
        m.s[cfsDynLibInit].addCall("hcrRegisterProc",
          getModuleDllPath(m),
          '"' & result & '"',
          cCast(CPointer, markerName))

proc genTraverseProcForGlobal(m: BModule, s: PSym; info: TLineInfo): Rope =
  discard genTypeInfoV1(m, s.loc.t, info)

  var p = newProc(nil, m)
  var sLoc = rdLoc(s.loc)
  result = getTempName(m)

  if sfThread in s.flags and emulatedThreadVars(m.config):
    accessThreadLocalVar(p, s)
    sLoc = derefField("NimTV_", sLoc)

  var c = TTraversalClosure(p: p,
    visitorFrmt: cIntValue(0) # "#nimGCvisit((void*)$1, 0);$n"
  )

  genTraverseProc(c, sLoc, s.loc.t)

  var headerBuilder = newBuilder("")
  headerBuilder.addProcHeaderWithParams(ccNimCall, result, CVoid):
    var paramBuilder: ProcParamBuilder
    headerBuilder.addProcParams(paramBuilder):
      # (void)
      discard
  let header = extract(headerBuilder)

  m.s[cfsProcHeaders].addDeclWithVisibility(StaticProc):
    m.s[cfsProcHeaders].add(header)
    m.s[cfsProcHeaders].finishProcHeaderAsProto()
  m.s[cfsProcs].addDeclWithVisibility(StaticProc):
    m.s[cfsProcs].add(header)
    m.s[cfsProcs].finishProcHeaderWithBody():
      m.s[cfsProcs].add(extract(p.s(cpsLocals)))
      m.s[cfsProcs].add(extract(p.s(cpsInit)))
      m.s[cfsProcs].add(extract(p.s(cpsStmts)))

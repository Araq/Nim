#
#
#           The Nim Compiler
#        (c) Copyright 2017 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# included from cgen.nim

# ------------------------- Name Mangling --------------------------------

import sighashes, modulegraphs, std/strscans
import ../dist/checksums/src/checksums/md5
import std/sequtils

type
  TypeDescKind = enum
    dkParam #skParam
    dkRefParam #param passed by ref when {.byref.} is used. Cpp only. C goes straight to dkParam and is handled as a regular pointer
    dkRefGenericParam #param passed by ref when {.byref.} is used that is also a generic. Cpp only. C goes straight to dkParam and is handled as a regular pointer
    dkVar #skVar
    dkField #skField
    dkResult #skResult
    dkConst #skConst
    dkOther #skType, skTemp, skLet and skForVar so far

proc descKindFromSymKind(kind: TSymKind): TypeDescKind =
  case kind
  of skParam: dkParam
  of skVar: dkVar
  of skField: dkField
  of skResult: dkResult
  of skConst: dkConst
  else: dkOther

proc isKeyword(w: PIdent): bool =
  # Nim and C++ share some keywords
  # it's more efficient to test the whole Nim keywords range
  case w.id
  of ccgKeywordsLow..ccgKeywordsHigh,
     nimKeywordsLow..nimKeywordsHigh,
     ord(wInline): return true
  else: return false

proc mangleField(m: BModule; name: PIdent): string =
  result = mangle(name.s)
  # fields are tricky to get right and thanks to generic types producing
  # duplicates we can end up mangling the same field multiple times. However
  # if we do so, the 'cppDefines' table might be modified in the meantime
  # meaning we produce inconsistent field names (see bug #5404).
  # Hence we do not check for ``m.g.config.cppDefines.contains(result)`` here
  # anymore:
  if isKeyword(name):
    result.add "_0"

proc mangleProc(m: BModule; s: PSym; makeUnique: bool): string =
  result = "_Z"  # Common prefix in Itanium ABI
  result.add encodeSym(m, s, makeUnique)
  if s.typ.len > 1: #we dont care about the return param
    for i in 1..<s.typ.len:
      if s.typ[i].isNil: continue
      result.add encodeType(m, s.typ[i])

  if result in m.g.mangledPrcs:
    result = mangleProc(m, s, true)
  else:
    m.g.mangledPrcs.incl(result)

proc fillBackendName(m: BModule; s: PSym) =
  if s.loc.snippet == "":
    var result: Rope
    if not m.compileToCpp and s.kind in routineKinds and optCDebug in m.g.config.globalOptions and
      m.g.config.symbolFiles == disabledSf:
      result = mangleProc(m, s, false).rope
    else:
      result = s.name.s.mangle.rope
      result.add mangleProcNameExt(m.g.graph, s)
    if m.hcrOn:
      result.add '_'
      result.add(idOrSig(s, m.module.name.s.mangle, m.sigConflicts, m.config))
    s.loc.snippet = result

proc fillParamName(m: BModule; s: PSym) =
  if s.loc.snippet == "":
    var res = s.name.s.mangle
    res.add mangleParamExt(s)
    #res.add idOrSig(s, res, m.sigConflicts, m.config)
    # Take into account if HCR is on because of the following scenario:
    #   if a module gets imported and it has some more importc symbols in it,
    # some param names might receive the "_0" suffix to distinguish from what
    # is newly available. That might lead to changes in the C code in nimcache
    # that contain only a parameter name change, but that is enough to mandate
    # recompilation of that source file and thus a new shared object will be
    # relinked. That may lead to a module getting reloaded which wasn't intended
    # and that may be fatal when parts of the current active callstack when
    # performCodeReload() was called are from the module being reloaded
    # unintentionally - example (3 modules which import one another):
    #   main => proxy => reloadable
    # we call performCodeReload() in proxy to reload only changes in reloadable
    # but there is a new import which introduces an importc symbol `socket`
    # and a function called in main or proxy uses `socket` as a parameter name.
    # That would lead to either needing to reload `proxy` or to overwrite the
    # executable file for the main module, which is running (or both!) -> error.
    s.loc.snippet = res.rope

proc fillLocalName(p: BProc; s: PSym) =
  assert s.kind in skLocalVars+{skTemp}
  #assert sfGlobal notin s.flags
  if s.loc.snippet == "":
    var key = s.name.s.mangle
    let counter = p.sigConflicts.getOrDefault(key)
    var result = key.rope
    if s.kind == skTemp:
      # speed up conflict search for temps (these are quite common):
      if counter != 0: result.add "_" & rope(counter+1)
    elif counter != 0 or isKeyword(s.name) or p.module.g.config.cppDefines.contains(key):
      result.add "_" & rope(counter+1)
    p.sigConflicts.inc(key)
    s.loc.snippet = result

proc scopeMangledParam(p: BProc; param: PSym) =
  ## parameter generation only takes BModule, not a BProc, so we have to
  ## remember these parameter names are already in scope to be able to
  ## generate unique identifiers reliably (consider that ``var a = a`` is
  ## even an idiom in Nim).
  var key = param.name.s.mangle
  p.sigConflicts.inc(key)

const
  irrelevantForBackend = {tyGenericBody, tyGenericInst, tyGenericInvocation,
                          tyDistinct, tyRange, tyStatic, tyAlias, tySink,
                          tyInferred, tyOwned}

proc typeName(typ: PType; result: var Rope) =
  let typ = typ.skipTypes(irrelevantForBackend)
  result.add $typ.kind
  if typ.sym != nil and typ.kind in {tyObject, tyEnum}:
    result.add "_"
    result.add typ.sym.name.s.mangle

proc getTypeName(m: BModule; typ: PType; sig: SigHash): Rope =
  var t = typ
  while true:
    if t.sym != nil and {sfImportc, sfExportc} * t.sym.flags != {}:
      return t.sym.loc.snippet

    if t.kind in irrelevantForBackend:
      t = t.skipModifier
    else:
      break
  let typ = if typ.kind in {tyAlias, tySink, tyOwned}: typ.elementType else: typ
  if typ.loc.snippet == "":
    typ.typeName(typ.loc.snippet)
    typ.loc.snippet.add $sig
  else:
    when defined(debugSigHashes):
      # check consistency:
      var tn = newRopeAppender()
      typ.typeName(tn)
      assert($typ.loc.snippet == $(tn & $sig))
  result = typ.loc.snippet
  if result == "": internalError(m.config, "getTypeName: " & $typ.kind)

proc mapSetType(conf: ConfigRef; typ: PType): TCTypeKind =
  case int(getSize(conf, typ))
  of 1: result = ctInt8
  of 2: result = ctInt16
  of 4: result = ctInt32
  of 8: result = ctInt64
  else: result = ctArray

proc mapType(conf: ConfigRef; typ: PType; isParam: bool): TCTypeKind =
  ## Maps a Nim type to a C type
  case typ.kind
  of tyNone, tyTyped: result = ctVoid
  of tyBool: result = ctBool
  of tyChar: result = ctChar
  of tyNil: result = ctPtr
  of tySet: result = mapSetType(conf, typ)
  of tyOpenArray, tyVarargs:
    if isParam: result = ctArray
    else: result = ctStruct
  of tyArray, tyUncheckedArray: result = ctArray
  of tyObject, tyTuple: result = ctStruct
  of tyUserTypeClasses:
    doAssert typ.isResolvedUserTypeClass
    result = mapType(conf, typ.skipModifier, isParam)
  of tyGenericBody, tyGenericInst, tyGenericParam, tyDistinct, tyOrdinal,
     tyTypeDesc, tyAlias, tySink, tyInferred, tyOwned:
    result = mapType(conf, skipModifier(typ), isParam)
  of tyEnum:
    if firstOrd(conf, typ) < 0:
      result = ctInt32
    else:
      case int(getSize(conf, typ))
      of 1: result = ctUInt8
      of 2: result = ctUInt16
      of 4: result = ctInt32
      of 8: result = ctInt64
      else: result = ctInt32
  of tyRange: result = mapType(conf, typ.elementType, isParam)
  of tyPtr, tyVar, tyLent, tyRef:
    var base = skipTypes(typ.elementType, typedescInst)
    case base.kind
    of tyOpenArray, tyArray, tyVarargs, tyUncheckedArray: result = ctPtrToArray
    of tySet:
      if mapSetType(conf, base) == ctArray: result = ctPtrToArray
      else: result = ctPtr
    else: result = ctPtr
  of tyPointer: result = ctPtr
  of tySequence: result = ctNimSeq
  of tyProc: result = if typ.callConv != ccClosure: ctProc else: ctStruct
  of tyString: result = ctNimStr
  of tyCstring: result = ctCString
  of tyInt..tyUInt64:
    result = TCTypeKind(ord(typ.kind) - ord(tyInt) + ord(ctInt))
  of tyStatic:
    if typ.n != nil: result = mapType(conf, typ.skipModifier, isParam)
    else:
      result = ctVoid
      doAssert(false, "mapType: " & $typ.kind)
  else:
    result = ctVoid
    doAssert(false, "mapType: " & $typ.kind)


proc mapReturnType(conf: ConfigRef; typ: PType): TCTypeKind =
  #if skipTypes(typ, typedescInst).kind == tyArray: result = ctPtr
  #else:
  result = mapType(conf, typ, false)

proc isImportedType(t: PType): bool =
  result = t.sym != nil and sfImportc in t.sym.flags

proc isImportedCppType(t: PType): bool =
  let x = t.skipTypes(irrelevantForBackend)
  result = (t.sym != nil and sfInfixCall in t.sym.flags) or
           (x.sym != nil and sfInfixCall in x.sym.flags)

proc isOrHasImportedCppType(typ: PType): bool =
  searchTypeFor(typ.skipTypes({tyRef}), isImportedCppType)

proc hasNoInit(t: PType): bool =
  result = t.sym != nil and sfNoInit in t.sym.flags

proc getTypeDescAux(m: BModule; origTyp: PType, check: var IntSet; kind: TypeDescKind): Rope

proc isObjLackingTypeField(typ: PType): bool {.inline.} =
  result = (typ.kind == tyObject) and ((tfFinal in typ.flags) and
      (typ.baseClass == nil) or isPureObject(typ))

proc isInvalidReturnType(conf: ConfigRef; typ: PType, isProc = true): bool =
  # Arrays and sets cannot be returned by a C procedure, because C is
  # such a poor programming language.
  # We exclude records with refs too. This enhances efficiency and
  # is necessary for proper code generation of assignments.
  var rettype = typ
  var isAllowedCall = true
  if isProc:
    rettype = rettype[0]
    isAllowedCall = typ.callConv in {ccClosure, ccInline, ccNimCall}
  if rettype == nil or (isAllowedCall and
                    getSize(conf, rettype) > conf.target.floatSize*3):
    result = true
  else:
    case mapType(conf, rettype, false)
    of ctArray:
      result = not (skipTypes(rettype, typedescInst).kind in
          {tyVar, tyLent, tyRef, tyPtr})
    of ctStruct:
      let t = skipTypes(rettype, typedescInst)
      if rettype.isImportedCppType or t.isImportedCppType or
          (typ.callConv == ccCDecl and conf.selectedGC in {gcArc, gcAtomicArc, gcOrc}):
        # prevents nrvo for cdecl procs; # bug #23401
        result = false
      else:
        result = containsGarbageCollectedRef(t) or
            (t.kind == tyObject and not isObjLackingTypeField(t)) or
            (getSize(conf, rettype) == szUnknownSize and (t.sym == nil or sfImportc notin t.sym.flags))

    else: result = false

proc cacheGetType(tab: TypeCache; sig: SigHash): Rope =
  # returns nil if we need to declare this type
  # since types are now unique via the ``getUniqueType`` mechanism, this slow
  # linear search is not necessary anymore:
  result = tab.getOrDefault(sig)

proc addAbiCheck(m: BModule; t: PType, name: Rope) =
  if isDefined(m.config, "checkAbi") and (let size = getSize(m.config, t); size != szUnknownSize):
    var msg = "backend & Nim disagree on size for: "
    msg.addTypeHeader(m.config, t)
    var msg2 = ""
    msg2.addQuoted msg # not a hostspot so extra allocation doesn't matter
    m.s[cfsTypeInfo].addf("NIM_STATIC_ASSERT(sizeof($1) == $2, $3);$n", [name, rope(size), msg2.rope])
    # see `testCodegenABICheck` for example error message it generates


proc fillResult(conf: ConfigRef; param: PNode, proctype: PType) =
  fillLoc(param.sym.loc, locParam, param, "Result",
          OnStack)
  let t = param.sym.typ
  if mapReturnType(conf, t) != ctArray and isInvalidReturnType(conf, proctype):
    incl(param.sym.loc.flags, lfIndirect)
    param.sym.loc.storage = OnUnknown

proc typeNameOrLiteral(m: BModule; t: PType, literal: string): Rope =
  if t.sym != nil and sfImportc in t.sym.flags and t.sym.magic == mNone:
    useHeader(m, t.sym)
    result = t.sym.loc.snippet
  else:
    result = rope(literal)

proc getSimpleTypeDesc(m: BModule; typ: PType): Rope =
  const
    NumericalTypeToStr: array[tyInt..tyUInt64, string] = [
      NimInt, NimInt8, NimInt16, NimInt32, NimInt64,
      NimFloat, NimFloat32, NimFloat64, NimFloat128,
      NimUint, NimUint8, NimUint16, NimUint32, NimUint64]
  case typ.kind
  of tyPointer:
    result = typeNameOrLiteral(m, typ, CPointer)
  of tyString:
    case detectStrVersion(m)
    of 2:
      cgsym(m, "NimStrPayload")
      cgsym(m, "NimStringV2")
      result = typeNameOrLiteral(m, typ, "NimStringV2")
    else:
      cgsym(m, "NimStringDesc")
      result = typeNameOrLiteral(m, typ, "NimStringDesc*")
  of tyCstring: result = typeNameOrLiteral(m, typ, NimCstring)
  of tyBool: result = typeNameOrLiteral(m, typ, NimBool)
  of tyChar: result = typeNameOrLiteral(m, typ, NimChar)
  of tyNil: result = typeNameOrLiteral(m, typ, CPointer)
  of tyInt..tyUInt64:
    result = typeNameOrLiteral(m, typ, NumericalTypeToStr[typ.kind])
  of tyRange, tyOrdinal: result = getSimpleTypeDesc(m, typ.skipModifier)
  of tyDistinct:
    result = getSimpleTypeDesc(m, typ.skipModifier)
    if isImportedType(typ) and result != "":
      useHeader(m, typ.sym)
      result = typ.sym.loc.snippet
  of tyStatic:
    if typ.n != nil: result = getSimpleTypeDesc(m, skipModifier typ)
    else:
      result = ""
      internalError(m.config, "tyStatic for getSimpleTypeDesc")
  of tyGenericInst, tyAlias, tySink, tyOwned:
    result = getSimpleTypeDesc(m, skipModifier typ)
  else: result = ""

  if result != "" and typ.isImportedType():
    let sig = hashType(typ, m.config)
    if cacheGetType(m.typeCache, sig) == "":
      m.typeCache[sig] = result

proc pushType(m: BModule; typ: PType) =
  for i in 0..high(m.typeStack):
    # pointer equality is good enough here:
    if m.typeStack[i] == typ: return
  m.typeStack.add(typ)

proc getTypePre(m: BModule; typ: PType; sig: SigHash): Rope =
  if typ == nil: result = CVoid
  else:
    result = getSimpleTypeDesc(m, typ)
    if result == "": result = cacheGetType(m.typeCache, sig)

proc addForwardStructFormat(m: BModule; structOrUnion: Rope, typename: Rope) =
  # XXX should be no-op in NIFC
  if m.compileToCpp:
    m.s[cfsForwardTypes].addf "$1 $2;$n", [structOrUnion, typename]
  else:
    m.s[cfsForwardTypes].addf "typedef $1 $2 $2;$n", [structOrUnion, typename]

proc seqStar(m: BModule): string =
  if optSeqDestructors in m.config.globalOptions: result = ""
  else: result = "*"

proc getTypeForward(m: BModule; typ: PType; sig: SigHash): Rope =
  result = cacheGetType(m.forwTypeCache, sig)
  if result != "": return
  result = getTypePre(m, typ, sig)
  if result != "": return
  let concrete = typ.skipTypes(abstractInst)
  case concrete.kind
  of tySequence, tyTuple, tyObject:
    result = getTypeName(m, typ, sig)
    m.forwTypeCache[sig] = result
    if not isImportedType(concrete):
      addForwardStructFormat(m, structOrUnion(typ), result)
    else:
      pushType(m, concrete)
    doAssert m.forwTypeCache[sig] == result
  else: internalError(m.config, "getTypeForward(" & $typ.kind & ')')

proc getTypeDescWeak(m: BModule; t: PType; check: var IntSet; kind: TypeDescKind): Rope =
  ## like getTypeDescAux but creates only a *weak* dependency. In other words
  ## we know we only need a pointer to it so we only generate a struct forward
  ## declaration:
  let etB = t.skipTypes(abstractInst)
  case etB.kind
  of tyObject, tyTuple:
    if isImportedCppType(etB) and t.kind == tyGenericInst:
      result = getTypeDescAux(m, t, check, kind)
    else:
      result = getTypeForward(m, t, hashType(t, m.config))
      pushType(m, t)
  of tySequence:
    let sig = hashType(t, m.config)
    if optSeqDestructors in m.config.globalOptions:
      if skipTypes(etB[0], typedescInst).kind == tyEmpty:
        internalError(m.config, "cannot map the empty seq type to a C type")

      result = cacheGetType(m.forwTypeCache, sig)
      if result == "":
        result = getTypeName(m, t, sig)
        if not isImportedType(t):
          m.forwTypeCache[sig] = result
          addForwardStructFormat(m, rope"struct", result)
          let payload = result & "_Content"
          addForwardStructFormat(m, rope"struct", payload)

      if cacheGetType(m.typeCache, sig) == "":
        m.typeCache[sig] = result
        #echo "adding ", sig, " ", typeToString(t), " ", m.module.name.s
        m.s[cfsTypes].addSimpleStruct(m, name = result, baseType = ""):
          m.s[cfsTypes].addField(name = "len", typ = NimInt)
          m.s[cfsTypes].addField(name = "p", typ = ptrType(result & "_Content"))
        pushType(m, t)
    else:
      result = getTypeForward(m, t, sig) & seqStar(m)
      pushType(m, t)
  else:
    result = getTypeDescAux(m, t, check, kind)

proc getSeqPayloadType(m: BModule; t: PType): Rope =
  var check = initIntSet()
  result = getTypeDescWeak(m, t, check, dkParam) & "_Content"
  #result = getTypeForward(m, t, hashType(t)) & "_Content"

proc seqV2ContentType(m: BModule; t: PType; check: var IntSet) =
  let sig = hashType(t, m.config)
  let result = cacheGetType(m.typeCache, sig)
  if result == "":
    discard getTypeDescAux(m, t, check, dkVar)
  else:
    let dataTyp = getTypeDescAux(m, t.skipTypes(abstractInst)[0], check, dkVar)
    m.s[cfsTypes].addSimpleStruct(m, name = result & "_Content", baseType = ""):
      m.s[cfsTypes].addField(name = "cap", typ = NimInt)
      m.s[cfsTypes].addField(name = "data",
        typ = dataTyp,
        isFlexArray = true)

proc paramStorageLoc(param: PSym): TStorageLoc =
  if param.typ.skipTypes({tyVar, tyLent, tyTypeDesc}).kind notin {
          tyArray, tyOpenArray, tyVarargs}:
    result = OnStack
  else:
    result = OnUnknown

macro unrollChars(x: static openArray[char], name, body: untyped) =
  result = newStmtList()
  for a in x:
    result.add(newBlockStmt(newStmtList(
      newConstStmt(name, newLit(a)),
      copy body
    )))

proc multiFormat*(frmt: var string, chars: static openArray[char], args: openArray[seq[string]]) =
  var res: string
  unrollChars(chars, c):
    res = ""
    let arg = args[find(chars, c)]
    var i = 0
    var num = 0
    while i < frmt.len:
      if frmt[i] == c:
        inc(i)
        case frmt[i]
        of c:
          res.add(c)
          inc(i)
        of '0'..'9':
          var j = 0
          while true:
            j = j * 10 + ord(frmt[i]) - ord('0')
            inc(i)
            if i >= frmt.len or frmt[i] notin {'0'..'9'}: break
          num = j
          if j > high(arg) + 1:
            raiseAssert "invalid format string: " & frmt
          else:
            res.add(arg[j-1])
        else:
          raiseAssert "invalid format string: " & frmt
      var start = i
      while i < frmt.len:
        if frmt[i] != c: inc(i)
        else: break
      if i - 1 >= start:
        res.add(substr(frmt, start, i - 1))
    frmt = res

proc genMemberProcParams(m: BModule; prc: PSym, superCall, rettype, name, params: var string,
                   check: var IntSet, declareEnvironment=true;
                   weakDep=false;) =
  let t = prc.typ
  let isCtor = sfConstructor in prc.flags
  if isCtor or (name[0] == '~' and sfMember in prc.flags):
    # destructors can't have void
    rettype = ""
  elif t.returnType == nil or isInvalidReturnType(m.config, t):
    rettype = CVoid
  else:
    if rettype == "":
      rettype = getTypeDescAux(m, t.returnType, check, dkResult)
    else:
      rettype = runtimeFormat(rettype.replace("'0", "$1"), [getTypeDescAux(m, t.returnType, check, dkResult)])
  var types, names, args: seq[string] = @[]
  if not isCtor:
    var this = t.n[1].sym
    fillParamName(m, this)
    fillLoc(this.loc, locParam, t.n[1],
            this.paramStorageLoc)
    if this.typ.kind == tyPtr:
      this.loc.snippet = "this"
    else:
      this.loc.snippet = "(*this)"
    names.add this.loc.snippet
    types.add getTypeDescWeak(m, this.typ, check, dkParam)

  let firstParam = if isCtor: 1 else: 2
  for i in firstParam..<t.n.len:
    if t.n[i].kind != nkSym: internalError(m.config, t.n.info, "genMemberProcParams")
    var param = t.n[i].sym
    var descKind = dkParam
    if optByRef in param.options:
      if param.typ.kind == tyGenericInst:
        descKind = dkRefGenericParam
      else:
        descKind = dkRefParam
    var typ, name: string
    fillParamName(m, param)
    fillLoc(param.loc, locParam, t.n[i],
            param.paramStorageLoc)
    if ccgIntroducedPtr(m.config, param, t.returnType) and descKind == dkParam:
      typ = getTypeDescWeak(m, param.typ, check, descKind) & "*"
      incl(param.loc.flags, lfIndirect)
      param.loc.storage = OnUnknown
    elif weakDep:
      typ = getTypeDescWeak(m, param.typ, check, descKind)
    else:
      typ = getTypeDescAux(m, param.typ, check, descKind)
    if sfNoalias in param.flags:
      typ.add("NIM_NOALIAS ")

    name = param.loc.snippet
    types.add typ
    names.add name
    if sfCodegenDecl notin param.flags:
      args.add types[^1] & " " & names[^1]
    else:
      args.add runtimeFormat(param.cgDeclFrmt, [types[^1], names[^1]])

  multiFormat(params, @['\'', '#'], [types, names])
  multiFormat(superCall, @['\'', '#'], [types, names])
  multiFormat(name, @['\'', '#'], [types, names]) #so we can ~'1 on members
  if params == "()":
    if types.len == 0:
      params = "(void)"
    else:
      params = "(" & args.join(", ") & ")"
  if tfVarargs in t.flags:
    if params != "(":
      params[^1] = ','
    else:
      params.delete(params.len()-1..params.len()-1)
    params.add("...)")

proc genProcParams(m: BModule; t: PType, rettype: var Rope, params: var Builder,
                   check: var IntSet, declareEnvironment=true;
                   weakDep=false;) =
  if t.returnType == nil or isInvalidReturnType(m.config, t):
    rettype = CVoid
  else:
    rettype = getTypeDescAux(m, t.returnType, check, dkResult)
  var paramBuilder: ProcParamBuilder
  params.addProcParams(paramBuilder):
    for i in 1..<t.n.len:
      if t.n[i].kind != nkSym: internalError(m.config, t.n.info, "genProcParams")
      var param = t.n[i].sym
      var descKind = dkParam
      if m.config.backend == backendCpp and optByRef in param.options:
        if param.typ.kind == tyGenericInst:
          descKind = dkRefGenericParam
        else:
          descKind = dkRefParam
      if isCompileTimeOnly(param.typ): continue
      fillParamName(m, param)
      fillLoc(param.loc, locParam, t.n[i],
              param.paramStorageLoc)
      var typ: Rope
      if ccgIntroducedPtr(m.config, param, t.returnType) and descKind == dkParam:
        typ = ptrType(getTypeDescWeak(m, param.typ, check, descKind))
        incl(param.loc.flags, lfIndirect)
        param.loc.storage = OnUnknown
      elif weakDep:
        typ = (getTypeDescWeak(m, param.typ, check, descKind))
      else:
        typ = (getTypeDescAux(m, param.typ, check, descKind))
      params.addParam(paramBuilder, param, typ = typ)
      # declare the len field for open arrays:
      var arr = param.typ.skipTypes({tyGenericInst})
      if arr.kind in {tyVar, tyLent, tySink}: arr = arr.elementType
      var j = 0
      while arr.kind in {tyOpenArray, tyVarargs}:
        # this fixes the 'sort' bug:
        if param.typ.kind in {tyVar, tyLent}: param.loc.storage = OnUnknown
        # need to pass hidden parameter:
        params.addParam(paramBuilder, name = param.loc.snippet & "Len_" & $j, typ = NimInt)
        inc(j)
        arr = arr[0].skipTypes({tySink})
    if t.returnType != nil and isInvalidReturnType(m.config, t):
      var arr = t.returnType
      var typ: Snippet
      if mapReturnType(m.config, arr) != ctArray:
        if isHeaderFile in m.flags:
          # still generates types for `--header`
          typ = ptrType(getTypeDescAux(m, arr, check, dkResult))
        else:
          typ = ptrType(getTypeDescWeak(m, arr, check, dkResult))
      else:
        typ = getTypeDescAux(m, arr, check, dkResult)
      params.addParam(paramBuilder, name = "Result", typ = typ)
    if t.callConv == ccClosure and declareEnvironment:
      params.addParam(paramBuilder, name = "ClE_0", typ = CPointer)
    if tfVarargs in t.flags:
      params.addVarargsParam(paramBuilder)

proc mangleRecFieldName(m: BModule; field: PSym): Rope =
  if {sfImportc, sfExportc} * field.flags != {}:
    result = field.loc.snippet
  else:
    result = rope(mangleField(m, field.name))
  if result == "": internalError(m.config, field.info, "mangleRecFieldName")

proc hasCppCtor(m: BModule; typ: PType): bool =
  result = false
  if m.compileToCpp and typ != nil and typ.itemId in m.g.graph.memberProcsPerType:
    for prc in m.g.graph.memberProcsPerType[typ.itemId]:
      if sfConstructor in prc.flags:
        return true

proc genCppParamsForCtor(p: BProc; call: PNode; didGenTemp: var bool): string

proc genCppInitializer(m: BModule, prc: BProc; typ: PType; didGenTemp: var bool): string =
  #To avoid creating a BProc per test when called inside a struct nil BProc is allowed
  result = "{}"
  if typ.itemId in m.g.graph.initializersPerType:
    let call = m.g.graph.initializersPerType[typ.itemId]
    if call != nil:
      var p = prc
      if p == nil:
        p = BProc(module: m)
      result = "{" & genCppParamsForCtor(p, call, didGenTemp) & "}"
      if prc == nil:
        assert p.blocks.len == 0, "BProc belongs to a struct doesnt have blocks"

proc genRecordFieldsAux(m: BModule; n: PNode,
                        rectype: PType,
                        check: var IntSet; result: var Builder; unionPrefix = "") =
  case n.kind
  of nkRecList:
    for i in 0..<n.len:
      genRecordFieldsAux(m, n[i], rectype, check, result, unionPrefix)
  of nkRecCase:
    if n[0].kind != nkSym: internalError(m.config, n.info, "genRecordFieldsAux")
    genRecordFieldsAux(m, n[0], rectype, check, result, unionPrefix)
    # prefix mangled name with "_U" to avoid clashes with other field names,
    # since identifiers are not allowed to start with '_'
    var unionBody = newBuilder("")
    for i in 1..<n.len:
      case n[i].kind
      of nkOfBranch, nkElse:
        let k = lastSon(n[i])
        if k.kind != nkSym:
          let structName = "_" & mangleRecFieldName(m, n[0].sym) & "_" & $i
          var a = newBuilder("")
          genRecordFieldsAux(m, k, rectype, check, a, unionPrefix & $structName & ".")
          if a.buf.len != 0:
            unionBody.addFieldWithStructType(m, rectype, structName):
              unionBody.add(extract(a))
        else:
          genRecordFieldsAux(m, k, rectype, check, unionBody, unionPrefix)
      else: internalError(m.config, "genRecordFieldsAux(record case branch)")
    if unionBody.buf.len != 0:
      result.addAnonUnion:
        # XXX this has to be a named field for NIFC
        result.add(extract(unionBody))
  of nkSym:
    let field = n.sym
    if field.typ.kind == tyVoid: return
    #assert(field.ast == nil)
    let sname = mangleRecFieldName(m, field)
    fillLoc(field.loc, locField, n, unionPrefix & sname, OnUnknown)
    # for importcpp'ed objects, we only need to set field.loc, but don't
    # have to recurse via 'getTypeDescAux'. And not doing so prevents problems
    # with heavily templatized C++ code:
    if not isImportedCppType(rectype):
      let fieldType = field.loc.lode.typ.skipTypes(abstractInst)
      var typ: Rope = ""
      var isFlexArray = false
      var initializer = ""
      if fieldType.kind == tyUncheckedArray:
        typ = getTypeDescAux(m, fieldType.elemType, check, dkField)
        isFlexArray = true
      elif fieldType.kind == tySequence:
        # we need to use a weak dependency here for trecursive_table.
        typ = getTypeDescWeak(m, field.loc.t, check, dkField)
      else:
        typ = getTypeDescAux(m, field.loc.t, check, dkField)
        # don't use fieldType here because we need the
        # tyGenericInst for C++ template support
        let noInit = sfNoInit in field.flags or (field.typ.sym != nil and sfNoInit in field.typ.sym.flags)
        if not noInit and (fieldType.isOrHasImportedCppType() or hasCppCtor(m, field.owner.typ)):
          var didGenTemp = false
          initializer = genCppInitializer(m, nil, fieldType, didGenTemp)
      result.addField(field, sname, typ, isFlexArray, initializer)
  else: internalError(m.config, n.info, "genRecordFieldsAux()")

proc genMemberProcHeader(m: BModule; prc: PSym; result: var Builder; asPtr: bool = false, isFwdDecl:bool = false)

proc addRecordFields(result: var Builder; m: BModule; typ: PType, check: var IntSet) =
  genRecordFieldsAux(m, typ.n, typ, check, result)
  if typ.itemId in m.g.graph.memberProcsPerType:
    let procs = m.g.graph.memberProcsPerType[typ.itemId]
    var isDefaultCtorGen, isCtorGen: bool = false
    for prc in procs:
      if sfConstructor in prc.flags:
        isCtorGen = true
        if prc.typ.n.len == 1:
          isDefaultCtorGen = true
      if lfNoDecl in prc.loc.flags: continue
      var header = newBuilder("")
      genMemberProcHeader(m, prc, header, false, true)
      result.addStmt():
        result.add(extract(header))
    if isCtorGen and not isDefaultCtorGen:
      var ch: IntSet = default(IntSet)
      result.addf "$1() = default;$n", [getTypeDescAux(m, typ, ch, dkOther)]

proc fillObjectFields*(m: BModule; typ: PType) =
  # sometimes generic objects are not consistently merged. We patch over
  # this fact here.
  var check = initIntSet()
  var ignored = newBuilder("")
  addRecordFields(ignored, m, typ, check)

proc mangleDynLibProc(sym: PSym): Rope

proc getRecordDesc(m: BModule; typ: PType, name: Rope,
                   check: var IntSet): Rope =
  # declare the record:
  var baseType: string = ""
  if typ.baseClass != nil:
    baseType = getTypeDescAux(m, typ.baseClass.skipTypes(skipPtrs), check, dkField)
  if typ.sym == nil or sfCodegenDecl notin typ.sym.flags:
    var res = newBuilder("")
    res.addStruct(m, typ, name, baseType):
      res.addRecordFields(m, typ, check)
    result = extract(res)
  else:
    var desc = newBuilder("")
    desc.addRecordFields(m, typ, check)
    result = runtimeFormat(typ.sym.cgDeclFrmt, [name, extract(desc), baseType])

proc getTupleDesc(m: BModule; typ: PType, name: Rope,
                  check: var IntSet): Rope =
  var res = newBuilder("")
  res.addStruct(m, typ, name, ""):
    for i, a in typ.ikids:
      res.addField(
        name = "Field" & $i,
        typ = getTypeDescAux(m, a, check, dkField))
  result = extract(res)

proc scanCppGenericSlot(pat: string, cursor, outIdx, outStars: var int): bool =
  # A helper proc for handling cppimport patterns, involving numeric
  # placeholders for generic types (e.g. '0, '**2, etc).
  # pre: the cursor must be placed at the ' symbol
  # post: the cursor will be placed after the final digit
  # false will returned if the input is not recognized as a placeholder
  inc cursor
  let begin = cursor
  while pat[cursor] == '*': inc cursor
  if pat[cursor] in Digits:
    outIdx = pat[cursor].ord - '0'.ord
    outStars = cursor - begin
    inc cursor
    return true
  else:
    return false

proc resolveStarsInCppType(typ: PType, idx, stars: int): PType =
  # Make sure the index refers to one of the generic params of the type.
  # XXX: we should catch this earlier and report it as a semantic error.
  if idx >= typ.kidsLen:
    raiseAssert "invalid apostrophe type parameter index"

  result = typ[idx]
  for i in 1..stars:
    if result != nil and result.kidsLen > 0:
      result = if result.kind == tyGenericInst: result[FirstGenericParamAt]
               else: result.elemType

proc getOpenArrayDesc(m: BModule; t: PType, check: var IntSet; kind: TypeDescKind): Rope =
  let sig = hashType(t, m.config)
  if kind == dkParam:
    result = getTypeDescWeak(m, t.elementType, check, kind) & "*"
  else:
    result = cacheGetType(m.typeCache, sig)
    if result == "":
      result = getTypeName(m, t, sig)
      m.typeCache[sig] = result
      let elemType = getTypeDescWeak(m, t.elementType, check, kind)
      m.s[cfsTypes].addTypedef(name = result):
        m.s[cfsTypes].addSimpleStruct(m, name = "", baseType = ""):
          m.s[cfsTypes].addField(name = "Field0", typ = ptrType(elemType))
          m.s[cfsTypes].addField(name = "Field1", typ = NimInt)

proc getTypeDescAux(m: BModule; origTyp: PType, check: var IntSet; kind: TypeDescKind): Rope =
  # returns only the type's name
  var t = origTyp.skipTypes(irrelevantForBackend-{tyOwned})
  if containsOrIncl(check, t.id):
    if not (isImportedCppType(origTyp) or isImportedCppType(t)):
      internalError(m.config, "cannot generate C type for: " & typeToString(origTyp))
    # XXX: this BUG is hard to fix -> we need to introduce helper structs,
    # but determining when this needs to be done is hard. We should split
    # C type generation into an analysis and a code generation phase somehow.
  if t.sym != nil: useHeader(m, t.sym)
  if t != origTyp and origTyp.sym != nil: useHeader(m, origTyp.sym)
  let sig = hashType(origTyp, m.config)

  # tyDistinct matters if it is an importc type
  result = getTypePre(m, origTyp.skipTypes(irrelevantForBackend-{tyOwned, tyDistinct}), sig)
  defer: # defer is the simplest in this case
    if isImportedType(t) and not m.typeABICache.containsOrIncl(sig):
      addAbiCheck(m, t, result)

  if result != "" and t.kind != tyOpenArray:
    excl(check, t.id)
    if kind == dkRefParam or kind == dkRefGenericParam and origTyp.kind == tyGenericInst:
      result.add("&")
    return
  case t.kind
  of tyRef, tyPtr, tyVar, tyLent:
    var star = if t.kind in {tyVar} and tfVarIsPtr notin origTyp.flags and
                    compileToCpp(m): "&" else: "*"
    var et = origTyp.skipTypes(abstractInst).elementType
    var etB = et.skipTypes(abstractInst)
    if mapType(m.config, t, kind == dkParam) == ctPtrToArray and (etB.kind != tyOpenArray or kind == dkParam):
      if etB.kind == tySet:
        et = getSysType(m.g.graph, unknownLineInfo, tyUInt8)
      else:
        et = elemType(etB)
      etB = et.skipTypes(abstractInst)
      star[0] = '*'
    case etB.kind
    of tyObject, tyTuple:
      if isImportedCppType(etB) and et.kind == tyGenericInst:
        result = getTypeDescAux(m, et, check, kind) & star
      else:
        # no restriction! We have a forward declaration for structs
        let name = getTypeForward(m, et, hashType(et, m.config))
        result = name & star
        m.typeCache[sig] = result
    of tySequence:
      if optSeqDestructors in m.config.globalOptions:
        result = getTypeDescWeak(m, et, check, kind) & star
        m.typeCache[sig] = result
      else:
        # no restriction! We have a forward declaration for structs
        let name = getTypeForward(m, et, hashType(et, m.config))
        result = name & seqStar(m) & star
        m.typeCache[sig] = result
        pushType(m, et)
    else:
      # else we have a strong dependency  :-(
      result = getTypeDescAux(m, et, check, kind) & star
      m.typeCache[sig] = result
  of tyOpenArray, tyVarargs:
    result = getOpenArrayDesc(m, t, check, kind)
  of tyEnum:
    result = cacheGetType(m.typeCache, sig)
    if result == "":
      result = getTypeName(m, origTyp, sig)
      if not (isImportedCppType(t) or
          (sfImportc in t.sym.flags and t.sym.magic == mNone)):
        m.typeCache[sig] = result
        var size: int
        if firstOrd(m.config, t) < 0:
          m.s[cfsTypes].addTypedef(name = result):
            m.s[cfsTypes].add(NimInt32)
          size = 4
        else:
          size = int(getSize(m.config, t))
          case size
          of 1:
            m.s[cfsTypes].addTypedef(name = result):
              m.s[cfsTypes].add(NimUint8)
          of 2:
            m.s[cfsTypes].addTypedef(name = result):
              m.s[cfsTypes].add(NimUint16)
          of 4:
            m.s[cfsTypes].addTypedef(name = result):
              m.s[cfsTypes].add(NimInt32)
          of 8:
            m.s[cfsTypes].addTypedef(name = result):
              m.s[cfsTypes].add(NimInt64)
          else: internalError(m.config, t.sym.info, "getTypeDescAux: enum")
        when false:
          let owner = hashOwner(t.sym)
          if not gDebugInfo.hasEnum(t.sym.name.s, t.sym.info.line, owner):
            var vals: seq[(string, int)] = @[]
            for i in 0..<t.n.len:
              assert(t.n[i].kind == nkSym)
              let field = t.n[i].sym
              vals.add((field.name.s, field.position.int))
            gDebugInfo.registerEnum(EnumDesc(size: size, owner: owner, id: t.sym.id,
              name: t.sym.name.s, values: vals))
  of tyProc:
    result = getTypeName(m, origTyp, sig)
    m.typeCache[sig] = result
    var rettype: Snippet = ""
    var desc = newBuilder("")
    genProcParams(m, t, rettype, desc, check, true, true)
    let params = extract(desc)
    if not isImportedType(t):
      if t.callConv != ccClosure: # procedure vars may need a closure!
        m.s[cfsTypes].addProcTypedef(callConv = t.callConv, name = result, rettype = rettype, params = params)
      else:
        m.s[cfsTypes].addTypedef(name = result):
          m.s[cfsTypes].addSimpleStruct(m, name = "", baseType = ""):
            m.s[cfsTypes].addProcField(name = "ClP_0", callConv = ccNimCall, rettype = rettype, params = params)
            m.s[cfsTypes].addField(name = "ClE_0", typ = CPointer)
  of tySequence:
    if optSeqDestructors in m.config.globalOptions:
      result = getTypeDescWeak(m, t, check, kind)
    else:
      # we cannot use getTypeForward here because then t would be associated
      # with the name of the struct, not with the pointer to the struct:
      result = cacheGetType(m.forwTypeCache, sig)
      if result == "":
        result = getTypeName(m, origTyp, sig)
        if not isImportedType(t):
          addForwardStructFormat(m, structOrUnion(t), result)
        m.forwTypeCache[sig] = result
      assert(cacheGetType(m.typeCache, sig) == "")
      m.typeCache[sig] = result & seqStar(m)
      if not isImportedType(t):
        if skipTypes(t.elementType, typedescInst).kind != tyEmpty:
          let et = getTypeDescAux(m, t.elementType, check, kind)
          let baseType = cgsymValue(m, "TGenericSeq")
          m.s[cfsSeqTypes].addSimpleStruct(m, name = result, baseType = baseType):
            m.s[cfsSeqTypes].addField(
              name = "data",
              typ = et,
              isFlexArray = true)
        else:
          result = rope("TGenericSeq")
      result.add(seqStar(m))
  of tyUncheckedArray:
    result = getTypeName(m, origTyp, sig)
    m.typeCache[sig] = result
    if not isImportedType(t):
      let et = getTypeDescAux(m, t.elementType, check, kind)
      m.s[cfsTypes].addArrayTypedef(name = result, len = 1):
        m.s[cfsTypes].add(et)
  of tyArray:
    var n: BiggestInt = toInt64(lengthOrd(m.config, t))
    if n <= 0: n = 1   # make an array of at least one element
    result = getTypeName(m, origTyp, sig)
    m.typeCache[sig] = result
    if not isImportedType(t):
      let e = getTypeDescAux(m, t.elementType, check, kind)
      m.s[cfsTypes].addArrayTypedef(name = result, len = n):
        m.s[cfsTypes].add(e)
  of tyObject, tyTuple:
    let tt = origTyp.skipTypes({tyDistinct})
    if isImportedCppType(t) and tt.kind == tyGenericInst:
      let cppNameAsRope = getTypeName(m, t, sig)
      let cppName = $cppNameAsRope
      var i = 0
      var chunkStart = 0

      template addResultType(ty: untyped) =
        if ty == nil or ty.kind == tyVoid:
          result.add(CVoid)
        elif ty.kind == tyStatic:
          internalAssert m.config, ty.n != nil
          result.add ty.n.renderTree
        else:
          result.add getTypeDescAux(m, ty, check, kind)

      while i < cppName.len:
        if cppName[i] == '\'':
          var chunkEnd = i-1
          var idx, stars: int = 0
          if scanCppGenericSlot(cppName, i, idx, stars):
            result.add cppName.substr(chunkStart, chunkEnd)
            chunkStart = i

            let typeInSlot = resolveStarsInCppType(tt, idx + 1, stars)
            addResultType(typeInSlot)
        else:
          inc i

      if chunkStart != 0:
        result.add cppName.substr(chunkStart)
      else:
        result = cppNameAsRope & "<"
        for needsComma, a in tt.genericInstParams:
          if needsComma: result.add(" COMMA ")
          addResultType(a)
        result.add("> ")
      # always call for sideeffects:
      assert t.kind != tyTuple
      discard getRecordDesc(m, t, result, check)
      # The resulting type will include commas and these won't play well
      # with the C macros for defining procs such as N_NIMCALL. We must
      # create a typedef for the type and use it in the proc signature:
      let typedefName = "TY" & $sig
      m.s[cfsTypes].addTypedef(name = typedefName):
        m.s[cfsTypes].add(result)
      m.typeCache[sig] = typedefName
      result = typedefName
    else:
      result = cacheGetType(m.forwTypeCache, sig)
      if result == "":
        result = getTypeName(m, origTyp, sig)
        m.forwTypeCache[sig] = result
        if not isImportedType(t):
          addForwardStructFormat(m, structOrUnion(t), result)
        assert m.forwTypeCache[sig] == result
      m.typeCache[sig] = result # always call for sideeffects:
      if not incompleteType(t):
        let recdesc = if t.kind != tyTuple: getRecordDesc(m, t, result, check)
                      else: getTupleDesc(m, t, result, check)
        if not isImportedType(t):
          m.s[cfsTypes].add(recdesc)
        elif tfIncompleteStruct notin t.flags:
          discard # addAbiCheck(m, t, result) # already handled elsewhere
  of tySet:
    # Don't use the imported name as it may be scoped: 'Foo::SomeKind'
    result = rope("tySet_")
    t.elementType.typeName(result)
    result.add $t.elementType.hashType(m.config)
    m.typeCache[sig] = result
    if not isImportedType(t):
      let s = int(getSize(m.config, t))
      case s
      of 1, 2, 4, 8:
        m.s[cfsTypes].addTypedef(name = result):
          m.s[cfsTypes].add(cUintType(s*8))
      else:
        m.s[cfsTypes].addArrayTypedef(name = result, len = s):
          m.s[cfsTypes].add(NimUint8)
  of tyGenericInst, tyDistinct, tyOrdinal, tyTypeDesc, tyAlias, tySink, tyOwned,
     tyUserTypeClass, tyUserTypeClassInst, tyInferred:
    result = getTypeDescAux(m, skipModifier(t), check, kind)
  else:
    internalError(m.config, "getTypeDescAux(" & $t.kind & ')')
    result = ""
  # fixes bug #145:
  excl(check, t.id)


proc getTypeDesc(m: BModule; typ: PType; kind = dkParam): Rope =
  var check = initIntSet()
  result = getTypeDescAux(m, typ, check, kind)

type
  TClosureTypeKind = enum ## In C closures are mapped to 3 different things.
    clHalf,           ## fn(args) type without the trailing 'void* env' parameter
    clHalfWithEnv,    ## fn(args, void* env) type with trailing 'void* env' parameter
    clFull            ## struct {fn(args, void* env), env}

proc getClosureType(m: BModule; t: PType, kind: TClosureTypeKind): Rope =
  assert t.kind == tyProc
  var check = initIntSet()
  result = getTempName(m)
  var rettype: Snippet = ""
  var desc = newBuilder("")
  genProcParams(m, t, rettype, desc, check, declareEnvironment=kind != clHalf)
  let params = extract(desc)
  if not isImportedType(t):
    if t.callConv != ccClosure or kind != clFull:
      m.s[cfsTypes].addProcTypedef(callConv = t.callConv, name = result, rettype = rettype, params = params)
    else:
      m.s[cfsTypes].addTypedef(name = result):
        m.s[cfsTypes].addSimpleStruct(m, name = "", baseType = ""):
          m.s[cfsTypes].addProcField(name = "ClP_0", callConv = ccNimCall, rettype = rettype, params = params)
          m.s[cfsTypes].addField(name = "ClE_0", typ = CPointer)

proc finishTypeDescriptions(m: BModule) =
  var i = 0
  var check = initIntSet()
  while i < m.typeStack.len:
    let t = m.typeStack[i]
    if optSeqDestructors in m.config.globalOptions and t.skipTypes(abstractInst).kind == tySequence:
      seqV2ContentType(m, t, check)
    else:
      discard getTypeDescAux(m, t, check, dkParam)
    inc(i)
  m.typeStack.setLen 0

proc isReloadable(m: BModule; prc: PSym): bool =
  return m.hcrOn and sfNonReloadable notin prc.flags

proc isNonReloadable(m: BModule; prc: PSym): bool =
  return m.hcrOn and sfNonReloadable in prc.flags

proc parseVFunctionDecl(val: string; name, params, retType, superCall: var string; isFnConst, isOverride, isMemberVirtual, isStatic: var bool; isCtor: bool, isFunctor=false) =
  var afterParams: string = ""
  if scanf(val, "$*($*)$s$*", name, params, afterParams):
    if name.strip() == "operator" and params == "": #isFunctor?
      parseVFunctionDecl(afterParams, name, params, retType, superCall, isFnConst, isOverride, isMemberVirtual, isStatic, isCtor, true)
      return
    if name.find("static ") > -1:
      isStatic = true
      name = name.replace("static ", "")
    isFnConst = afterParams.find("const") > -1
    isOverride = afterParams.find("override") > -1
    isMemberVirtual = name.find("virtual ") > -1
    if isMemberVirtual:
      name = name.replace("virtual ", "")
    if isFunctor:
      name = "operator ()"
    if isCtor:
      discard scanf(afterParams, ":$s$*", superCall)
    else:
      discard scanf(afterParams, "->$s$* ", retType)

  params = "(" & params & ")"

proc genMemberProcHeader(m: BModule; prc: PSym; result: var Builder; asPtr: bool = false, isFwdDecl: bool = false) =
  assert sfCppMember * prc.flags != {}
  let isCtor = sfConstructor in prc.flags
  var check = initIntSet()
  fillBackendName(m, prc)
  fillLoc(prc.loc, locProc, prc.ast[namePos], OnUnknown)
  var memberOp = "#." #only virtual
  var typ: PType
  if isCtor:
    typ = prc.typ.returnType
  else:
    typ = prc.typ.firstParamType
  if typ.kind == tyPtr:
    typ = typ.elementType
    memberOp = "#->"
  var typDesc = getTypeDescWeak(m, typ, check, dkParam)
  let asPtrStr = rope(if asPtr: "_PTR" else: "")
  var name, params, rettype, superCall: string = ""
  var isFnConst, isOverride, isMemberVirtual, isStatic: bool = false
  parseVFunctionDecl(prc.constraint.strVal, name, params, rettype, superCall, isFnConst, isOverride, isMemberVirtual, isStatic, isCtor)
  genMemberProcParams(m, prc, superCall, rettype, name, params, check, true, false)
  let isVirtual = sfVirtual in prc.flags or isMemberVirtual
  var fnConst, override: string = ""
  if isCtor:
    name = typDesc
  if isFnConst:
    fnConst = " const"
  if isFwdDecl:
    if isStatic:
      result.add "static "
    if isVirtual:
      rettype = "virtual " & rettype
      if isOverride:
        override = " override"
    superCall = ""
  else:
    if not isCtor:
      prc.loc.snippet = "$1$2(@)" % [memberOp, name]
    elif superCall != "":
      superCall = " : " & superCall

    name = "$1::$2" % [typDesc, name]

  result.add "N_LIB_PRIVATE "
  result.addf("$1$2($3, $4)$5$6$7$8",
        [rope(CallingConvToStr[prc.typ.callConv]), asPtrStr, rettype, name,
        params, fnConst, override, superCall])

proc genProcHeader(m: BModule; prc: PSym; result: var Builder; visibility: var DeclVisibility, asPtr: bool, addAttributes: bool) =
  # using static is needed for inline procs
  var check = initIntSet()
  fillBackendName(m, prc)
  fillLoc(prc.loc, locProc, prc.ast[namePos], OnUnknown)
  var rettype: Snippet = ""
  var desc = newBuilder("")
  genProcParams(m, prc.typ, rettype, desc, check, true, false)
  let params = extract(desc)
  # handle the 2 options for hotcodereloading codegen - function pointer
  # (instead of forward declaration) or header for function body with "_actual" postfix
  var name = prc.loc.snippet
  if not asPtr and isReloadable(m, prc):
    name.add("_actual")
  # careful here! don't access ``prc.ast`` as that could reload large parts of
  # the object graph!
  if sfCodegenDecl notin prc.flags:
    var isStaticVar = false
    if lfExportLib in prc.loc.flags:
      if isHeaderFile in m.flags:
        visibility = ImportLib
      else:
        visibility = ExportLib
    elif asPtr:
      isStaticVar = true
    elif prc.typ.callConv == ccInline or isNonReloadable(m, prc):
      visibility = StaticProc
    elif sfImportc notin prc.flags:
      visibility = Private
    if asPtr:
      result.addProcVar(m, prc, name, params, rettype, isStatic = isStaticVar, ignoreAttributes = true)
    else:
      result.addProcHeader(m, prc, name, params, rettype, addAttributes)
  else:
    let asPtrStr = if asPtr: (rope("(*") & name & ")") else: name
    result.add runtimeFormat(prc.cgDeclFrmt, [rettype, asPtrStr, params])


# ------------------ type info generation -------------------------------------

proc genTypeInfoV1(m: BModule; t: PType; info: TLineInfo): Rope
proc getNimNode(m: BModule): Rope =
  result = subscript(m.typeNodesName, cIntValue(m.typeNodes))
  inc(m.typeNodes)

proc tiNameForHcr(m: BModule; name: Rope): Rope =
  return if m.hcrOn: cDeref(name) else: name

proc genTypeInfoAuxBase(m: BModule; typ, origType: PType;
                        name, base: Rope; info: TLineInfo) =
  var nimtypeKind: int
  #allocMemTI(m, typ, name)
  if isObjLackingTypeField(typ):
    nimtypeKind = ord(tyPureObject)
  else:
    nimtypeKind = ord(typ.kind)

  let nameHcr = tiNameForHcr(m, name)

  var size: Rope
  if tfIncompleteStruct in typ.flags:
    size = CPointer
  else:
    size = getTypeDesc(m, origType, dkVar)
  m.s[cfsTypeInit3].addFieldAssignmentWithValue(nameHcr, "size"):
    m.s[cfsTypeInit3].addSizeof(size)
  m.s[cfsTypeInit3].addFieldAssignmentWithValue(nameHcr, "align"):
    m.s[cfsTypeInit3].addAlignof(size)
  m.s[cfsTypeInit3].addFieldAssignment(nameHcr, "kind", nimtypeKind)
  m.s[cfsTypeInit3].addFieldAssignment(nameHcr, "base", base)
  # compute type flags for GC optimization
  var flags = 0
  if not containsGarbageCollectedRef(typ): flags = flags or 1
  if not canFormAcycle(m.g.graph, typ): flags = flags or 2
  #else echo("can contain a cycle: " & typeToString(typ))
  if flags != 0:
    m.s[cfsTypeInit3].addFieldAssignment(nameHcr, "flags", cIntValue(flags))
  cgsym(m, "TNimType")
  if isDefined(m.config, "nimTypeNames"):
    var typename = typeToString(if origType.typeInst != nil: origType.typeInst
                                else: origType, preferName)
    if typename == "ref object" and origType.skipTypes(skipPtrs).sym != nil:
      typename = "anon ref object from " & m.config$origType.skipTypes(skipPtrs).sym.info
    m.s[cfsTypeInit3].addFieldAssignment(nameHcr, "name", makeCString typename)
    cgsym(m, "nimTypeRoot")
    m.s[cfsTypeInit3].addFieldAssignment(nameHcr, "nextType", "nimTypeRoot")
    m.s[cfsTypeInit3].addAssignment("nimTypeRoot", cAddr(nameHcr))

  if m.hcrOn:
    m.s[cfsStrData].addVar(kind = Global, name = name, typ = ptrType("TNimType"))
    m.hcrCreateTypeInfosProc.add('\t')
    var registerHcr: CallBuilder
    m.hcrCreateTypeInfosProc.addStmt():
      m.hcrCreateTypeInfosProc.addCall(registerHcr, callee = "hcrRegisterGlobal"):
        m.hcrCreateTypeInfosProc.addArgument(registerHcr):
          m.hcrCreateTypeInfosProc.add(getModuleDllPath(m, m.module))
        m.hcrCreateTypeInfosProc.addArgument(registerHcr):
          m.hcrCreateTypeInfosProc.add(makeCString(name))
        m.hcrCreateTypeInfosProc.addArgument(registerHcr):
          m.hcrCreateTypeInfosProc.addSizeof("TNimType")
        m.hcrCreateTypeInfosProc.addArgument(registerHcr):
          m.hcrCreateTypeInfosProc.add(CNil)
        m.hcrCreateTypeInfosProc.addArgument(registerHcr):
          m.hcrCreateTypeInfosProc.addCast(typ = ptrType(CPointer)):
            m.hcrCreateTypeInfosProc.add(cAddr(name))
  else:
    m.s[cfsStrData].addDeclWithVisibility(Private):
      m.s[cfsStrData].addVar(kind = Local, name = name, typ = "TNimType")

proc genTypeInfoAux(m: BModule; typ, origType: PType, name: Rope;
                    info: TLineInfo) =
  var base: Rope
  if typ.hasElementType and typ.last != nil:
    var x = typ.last
    if typ.kind == tyObject: x = x.skipTypes(skipPtrs)
    if typ.kind == tyPtr and x.kind == tyObject and incompleteType(x):
      base = cIntValue(0)
    else:
      base = genTypeInfoV1(m, x, info)
  else:
    base = cIntValue(0)
  genTypeInfoAuxBase(m, typ, origType, name, base, info)

proc discriminatorTableName(m: BModule; objtype: PType, d: PSym): Rope =
  # bugfix: we need to search the type that contains the discriminator:
  var objtype = objtype.skipTypes(abstractPtrs)
  while lookupInRecord(objtype.n, d.name) == nil:
    objtype = objtype[0].skipTypes(abstractPtrs)
  if objtype.sym == nil:
    internalError(m.config, d.info, "anonymous obj with discriminator")
  result = "NimDT_$1_$2" % [rope($hashType(objtype, m.config)), rope(d.name.s.mangle)]

proc rope(arg: Int128): Rope = rope($arg)

proc discriminatorTableDecl(m: BModule; objtype: PType, d: PSym, result: var Builder) =
  cgsym(m, "TNimNode")
  var tmp = discriminatorTableName(m, objtype, d)
  result.addArrayVar(kind = Local,
    name = tmp,
    elementType = ptrType("TNimNode"),
    len = toInt(lengthOrd(m.config, d.typ)) + 1)

proc genTNimNodeArray(m: BModule; name: Rope, size: int) =
  if m.hcrOn:
    m.s[cfsData].addVar(kind = Global, name = name, typ = ptrType(ptrType("TNimNode")))
    var registerHcr: CallBuilder
    m.hcrCreateTypeInfosProc.addStmt():
      m.hcrCreateTypeInfosProc.addCall(registerHcr, callee = "hcrRegisterGlobal"):
        m.hcrCreateTypeInfosProc.addArgument(registerHcr):
          m.hcrCreateTypeInfosProc.add(getModuleDllPath(m, m.module))
        m.hcrCreateTypeInfosProc.addArgument(registerHcr):
          m.hcrCreateTypeInfosProc.add(makeCString(name))
        m.hcrCreateTypeInfosProc.addArgument(registerHcr):
          m.hcrCreateTypeInfosProc.addOp(Mul, NimInt, cSizeof(ptrType("TNimNode")), cIntValue(size))
        m.hcrCreateTypeInfosProc.addArgument(registerHcr):
          m.hcrCreateTypeInfosProc.add(CNil)
        m.hcrCreateTypeInfosProc.addArgument(registerHcr):
          m.hcrCreateTypeInfosProc.addCast(typ = ptrType(CPointer)):
            m.hcrCreateTypeInfosProc.add(cAddr(name))
  else:
    m.s[cfsTypeInit1].addArrayVar(kind = Global, name = name,
      elementType = ptrType("TNimNode"), len = size)

proc genObjectFields(m: BModule; typ, origType: PType, n: PNode, expr: Rope;
                     info: TLineInfo) =
  case n.kind
  of nkRecList:
    if n.len == 1:
      genObjectFields(m, typ, origType, n[0], expr, info)
    elif n.len > 0:
      var tmp = getTempName(m) & "_" & $n.len
      genTNimNodeArray(m, tmp, n.len)
      for i in 0..<n.len:
        var tmp2 = getNimNode(m)
        m.s[cfsTypeInit3].addSubscriptAssignment(tmp, cIntValue(i), cAddr(tmp2))
        genObjectFields(m, typ, origType, n[i], tmp2, info)
      m.s[cfsTypeInit3].addFieldAssignment(expr, "len", n.len)
      m.s[cfsTypeInit3].addFieldAssignment(expr, "kind", 2)
      m.s[cfsTypeInit3].addFieldAssignment(expr, "sons",
        cAddr(subscript(tmp, cIntValue(0))))
    else:
      m.s[cfsTypeInit3].addFieldAssignment(expr, "len", n.len)
      m.s[cfsTypeInit3].addFieldAssignment(expr, "kind", 2)
  of nkRecCase:
    assert(n[0].kind == nkSym)
    var field = n[0].sym
    var tmp = discriminatorTableName(m, typ, field)
    var L = lengthOrd(m.config, field.typ)
    assert L > 0
    if field.loc.snippet == "": fillObjectFields(m, typ)
    if field.loc.t == nil:
      internalError(m.config, n.info, "genObjectFields")
    let fieldTypInfo = genTypeInfoV1(m, field.typ, info)
    m.s[cfsTypeInit3].addFieldAssignment(expr, "kind", 3)
    m.s[cfsTypeInit3].addFieldAssignmentWithValue(expr, "offset"):
      m.s[cfsTypeInit3].addOffsetof(getTypeDesc(m, origType, dkVar), field.loc.snippet)
    m.s[cfsTypeInit3].addFieldAssignment(expr, "typ", fieldTypInfo)
    m.s[cfsTypeInit3].addFieldAssignment(expr, "name", makeCString(field.name.s))
    m.s[cfsTypeInit3].addFieldAssignment(expr, "sons", cAddr(subscript(tmp, cIntValue(0))))
    m.s[cfsTypeInit3].addFieldAssignment(expr, "len", L)
    m.s[cfsData].addArrayVar(kind = Local, name = tmp,
      elementType = ptrType("TNimNode"), len = toInt(L)+1)
    for i in 1..<n.len:
      var b = n[i]           # branch
      var tmp2 = getNimNode(m)
      genObjectFields(m, typ, origType, lastSon(b), tmp2, info)
      case b.kind
      of nkOfBranch:
        if b.len < 2:
          internalError(m.config, b.info, "genObjectFields; nkOfBranch broken")
        for j in 0..<b.len - 1:
          if b[j].kind == nkRange:
            var x = toInt(getOrdValue(b[j][0]))
            var y = toInt(getOrdValue(b[j][1]))
            while x <= y:
              m.s[cfsTypeInit3].addSubscriptAssignment(tmp, cIntValue(x), cAddr(tmp2))
              inc(x)
          else:
            m.s[cfsTypeInit3].addSubscriptAssignment(tmp, cIntValue(getOrdValue(b[j])), cAddr(tmp2))
      of nkElse:
        m.s[cfsTypeInit3].addSubscriptAssignment(tmp, cIntValue(L), cAddr(tmp2))
      else: internalError(m.config, n.info, "genObjectFields(nkRecCase)")
  of nkSym:
    var field = n.sym
    # Do not produce code for void types
    if isEmptyType(field.typ): return
    if field.bitsize == 0:
      if field.loc.snippet == "": fillObjectFields(m, typ)
      if field.loc.t == nil:
        internalError(m.config, n.info, "genObjectFields")
      let fieldTypInfo = genTypeInfoV1(m, field.typ, info)
      m.s[cfsTypeInit3].addFieldAssignment(expr, "kind", 1)
      m.s[cfsTypeInit3].addFieldAssignmentWithValue(expr, "offset"):
        m.s[cfsTypeInit3].addOffsetof(getTypeDesc(m, origType, dkVar), field.loc.snippet)
      m.s[cfsTypeInit3].addFieldAssignment(expr, "typ", fieldTypInfo)
      m.s[cfsTypeInit3].addFieldAssignment(expr, "name", makeCString(field.name.s))
  else: internalError(m.config, n.info, "genObjectFields")

proc genObjectInfo(m: BModule; typ, origType: PType, name: Rope; info: TLineInfo) =
  assert typ.kind == tyObject
  if incompleteType(typ):
    localError(m.config, info, "request for RTTI generation for incomplete object: " &
                      typeToString(typ))
  genTypeInfoAux(m, typ, origType, name, info)
  var tmp = getNimNode(m)
  if (not isImportedType(typ)) or tfCompleteStruct in typ.flags:
    genObjectFields(m, typ, origType, typ.n, tmp, info)
  m.s[cfsTypeInit3].addFieldAssignment(tiNameForHcr(m, name), "node", cAddr(tmp))
  var t = typ.baseClass
  while t != nil:
    t = t.skipTypes(skipPtrs)
    t.flags.incl tfObjHasKids
    t = t.baseClass

proc genTupleInfo(m: BModule; typ, origType: PType, name: Rope; info: TLineInfo) =
  genTypeInfoAuxBase(m, typ, typ, name, cIntValue(0), info)
  var expr = getNimNode(m)
  if not typ.isEmptyTupleType:
    var tmp = getTempName(m) & "_" & $typ.kidsLen
    genTNimNodeArray(m, tmp, typ.kidsLen)
    for i, a in typ.ikids:
      var tmp2 = getNimNode(m)
      let fieldTypInfo = genTypeInfoV1(m, a, info)
      m.s[cfsTypeInit3].addSubscriptAssignment(tmp, cIntValue(i), cAddr(tmp2))
      m.s[cfsTypeInit3].addFieldAssignment(tmp2, "kind", 1)
      m.s[cfsTypeInit3].addFieldAssignmentWithValue(tmp2, "offset"):
        m.s[cfsTypeInit3].addOffsetof(getTypeDesc(m, origType, dkVar), "Field" & $i)
      m.s[cfsTypeInit3].addFieldAssignment(tmp2, "typ", fieldTypInfo)
      m.s[cfsTypeInit3].addFieldAssignment(tmp2, "name", "\"Field" & $i & "\"")
    m.s[cfsTypeInit3].addFieldAssignment(expr, "len", typ.kidsLen)
    m.s[cfsTypeInit3].addFieldAssignment(expr, "kind", 2)
    m.s[cfsTypeInit3].addFieldAssignment(expr, "sons",
      cAddr(subscript(tmp, cIntValue(0))))
  else:
    m.s[cfsTypeInit3].addFieldAssignment(expr, "len", typ.kidsLen)
    m.s[cfsTypeInit3].addFieldAssignment(expr, "kind", 2)
  m.s[cfsTypeInit3].addFieldAssignment(tiNameForHcr(m, name), "node", cAddr(expr))

proc genEnumInfo(m: BModule; typ: PType, name: Rope; info: TLineInfo) =
  # Type information for enumerations is quite heavy, so we do some
  # optimizations here: The ``typ`` field is never set, as it is redundant
  # anyway. We generate a cstring array and a loop over it. Exceptional
  # positions will be reset after the loop.
  genTypeInfoAux(m, typ, typ, name, info)
  var nodePtrs = getTempName(m) & "_" & $typ.n.len
  genTNimNodeArray(m, nodePtrs, typ.n.len)
  var enumNames = newBuilder("")
  var enumNamesInit: StructInitializer
  var specialCases = newBuilder("")
  var firstNimNode = m.typeNodes
  var hasHoles = false
  enumNames.addStructInitializer(enumNamesInit, kind = siArray):
    for i in 0..<typ.n.len:
      assert(typ.n[i].kind == nkSym)
      var field = typ.n[i].sym
      var elemNode = getNimNode(m)
      enumNames.addField(enumNamesInit, name = ""):
        if field.ast == nil:
          # no explicit string literal for the enum field, so use field.name:
          enumNames.add(makeCString(field.name.s))
        else:
          enumNames.add(makeCString(field.ast.strVal))
      if field.position != i or tfEnumHasHoles in typ.flags:
        specialCases.addFieldAssignment(elemNode, "offset", field.position)
        hasHoles = true
  var enumArray = getTempName(m)
  var counter = getTempName(m)
  m.s[cfsTypeInit1].addVar(kind = Local, name = counter, typ = NimInt)
  m.s[cfsTypeInit1].addArrayVarWithInitializer(
      kind = Global,
      name = enumArray,
      elementType = constPtrType(CChar),
      len = typ.n.len):
    m.s[cfsTypeInit1].add(extract(enumNames))
  m.s[cfsTypeInit3].addForRangeExclusive(i = counter,
      start = cIntValue(0),
      bound = cIntValue(typ.n.len)):
    let nodeLoc = subscript(m.typeNodesName,
      cOp(Add, NimInt, counter, cIntValue(firstNimNode)))
    m.s[cfsTypeInit3].addFieldAssignment(nodeLoc, "kind", cIntValue(1))
    m.s[cfsTypeInit3].addFieldAssignment(nodeLoc, "offset", counter)
    m.s[cfsTypeInit3].addFieldAssignment(nodeLoc, "name",
      subscript(enumArray, counter))
    m.s[cfsTypeInit3].addSubscriptAssignment(nodePtrs, counter,
      cAddr(nodeLoc))
  m.s[cfsTypeInit3].add(extract(specialCases))
  let n = getNimNode(m)
  m.s[cfsTypeInit3].addFieldAssignment(n, "len", typ.n.len)
  m.s[cfsTypeInit3].addFieldAssignment(n, "kind", 0)
  m.s[cfsTypeInit3].addFieldAssignment(n, "sons",
    cAddr(subscript(nodePtrs, cIntValue(0))))
  m.s[cfsTypeInit3].addFieldAssignment(tiNameForHcr(m, name), "node", cAddr(n))
  if hasHoles:
    m.s[cfsTypeInit3].addFieldAssignment(tiNameForHcr(m, name), "flags",
      # 1 << 2 is {ntfEnumHole}
      cOp(Shl, NimUint8, cIntValue(1), cIntValue(2)))

proc genSetInfo(m: BModule; typ: PType, name: Rope; info: TLineInfo) =
  assert(typ.elementType != nil)
  genTypeInfoAux(m, typ, typ, name, info)
  var tmp = getNimNode(m)
  m.s[cfsTypeInit3].addFieldAssignment(tmp, "len", firstOrd(m.config, typ))
  m.s[cfsTypeInit3].addFieldAssignment(tmp, "kind", 0)
  m.s[cfsTypeInit3].addFieldAssignment(tiNameForHcr(m, name), "node", cAddr(tmp))

proc genArrayInfo(m: BModule; typ: PType, name: Rope; info: TLineInfo) =
  genTypeInfoAuxBase(m, typ, typ, name, genTypeInfoV1(m, typ.elementType, info), info)

proc fakeClosureType(m: BModule; owner: PSym): PType =
  # we generate the same RTTI as for a tuple[pointer, ref tuple[]]
  result = newType(tyTuple, m.idgen, owner)
  result.rawAddSon(newType(tyPointer, m.idgen, owner))
  var r = newType(tyRef, m.idgen, owner)
  let obj = createObj(m.g.graph, m.idgen, owner, owner.info, final=false)
  r.rawAddSon(obj)
  result.rawAddSon(r)

include ccgtrav

proc genDeepCopyProc(m: BModule; s: PSym; result: Rope) =
  genProc(m, s)
  var desc = newBuilder("")
  var paramBuilder: ProcParamBuilder
  desc.addProcParams(paramBuilder):
    desc.addUnnamedParam(paramBuilder, typ = CPointer)
  let params = extract(desc)
  let pt = procPtrTypeUnnamedNimCall(rettype = CPointer, params = params)
  m.s[cfsTypeInit3].addFieldAssignmentWithValue(result, "deepcopy"):
    m.s[cfsTypeInit3].add(cCast(pt, s.loc.snippet))

proc declareNimType(m: BModule; name: string; str: Rope, module: int) =
  let nr = rope(name)
  if m.hcrOn:
    m.s[cfsStrData].addVar(kind = Global, name = str, typ = ptrType(nr))
    m.s[cfsTypeInit1].add('\t')
    m.s[cfsTypeInit1].addAssignmentWithValue(str):
      m.s[cfsTypeInit1].addCast(typ = ptrType(nr)):
        var hcrGlobal: CallBuilder
        m.s[cfsTypeInit1].addCall(hcrGlobal, "hcrGetGlobal"):
          m.s[cfsTypeInit1].addArgument(hcrGlobal):
            m.s[cfsTypeInit1].add(getModuleDllPath(m, module))
          m.s[cfsTypeInit1].addArgument(hcrGlobal):
            m.s[cfsTypeInit1].add("\"" & str & "\"")
  else:
    m.s[cfsStrData].addDeclWithVisibility(Extern):
      m.s[cfsStrData].addVar(kind = Local, name = str, typ = nr)

proc genTypeInfo2Name(m: BModule; t: PType): Rope =
  var it = t
  it = it.skipTypes(skipPtrs)
  if it.sym != nil and tfFromGeneric notin it.flags:
    var m = it.sym.owner
    while m != nil and m.kind != skModule: m = m.owner
    if m == nil or sfSystemModule in m.flags:
      # produce short names for system types:
      result = it.sym.name.s
    else:
      var p = m.owner
      result = ""
      if p != nil and p.kind == skPackage:
        result.add p.name.s & "."
      result.add m.name.s & "."
      result.add it.sym.name.s
  else:
    result = $hashType(it, m.config)
  result = makeCString(result)

proc isTrivialProc(g: ModuleGraph; s: PSym): bool {.inline.} = getBody(g, s).len == 0

proc generateRttiDestructor(g: ModuleGraph; typ: PType; owner: PSym; kind: TTypeAttachedOp;
              info: TLineInfo; idgen: IdGenerator; theProc: PSym): PSym =
  # the wrapper is roughly like:
  # proc rttiDestroy(x: pointer) =
  #   `=destroy`(cast[ptr T](x)[])
  let procname = getIdent(g.cache, "rttiDestroy")
  result = newSym(skProc, procname, idgen, owner, info)
  let dest = newSym(skParam, getIdent(g.cache, "dest"), idgen, result, info)

  dest.typ = getSysType(g, info, tyPointer)

  result.typ = newProcType(info, idgen, owner)
  result.typ.addParam dest

  var n = newNodeI(nkProcDef, info, bodyPos+1)
  for i in 0..<n.len: n[i] = newNodeI(nkEmpty, info)
  n[namePos] = newSymNode(result)
  n[paramsPos] = result.typ.n
  let body = newNodeI(nkStmtList, info)
  let castType = makePtrType(typ, idgen)
  if theProc.typ.firstParamType.kind != tyVar:
    body.add newTreeI(nkCall, info, newSymNode(theProc), newDeref(newTreeIT(
      nkCast, info, castType, newNodeIT(nkType, info, castType),
      newSymNode(dest)
    ))
    )
  else:
    let addrOf = newNodeIT(nkHiddenAddr, info, theProc.typ.firstParamType)
    addrOf.add newDeref(newTreeIT(
      nkCast, info, castType, newNodeIT(nkType, info, castType),
      newSymNode(dest)
    ))
    body.add newTreeI(nkCall, info, newSymNode(theProc),
      addrOf
    )
  n[bodyPos] = body
  result.ast = n

  incl result.flags, sfFromGeneric
  incl result.flags, sfGeneratedOp

proc genHook(m: BModule; t: PType; info: TLineInfo; op: TTypeAttachedOp; result: var Builder) =
  let theProc = getAttachedOp(m.g.graph, t, op)
  if theProc != nil and not isTrivialProc(m.g.graph, theProc):
    # the prototype of a destructor is ``=destroy(x: var T)`` and that of a
    # finalizer is: ``proc (x: ref T) {.nimcall.}``. We need to check the calling
    # convention at least:
    if theProc.typ == nil or theProc.typ.callConv != ccNimCall:
      localError(m.config, info,
        theProc.name.s & " needs to have the 'nimcall' calling convention")

    if op == attachedDestructor:
      let wrapper = generateRttiDestructor(m.g.graph, t, theProc.owner, attachedDestructor,
                theProc.info, m.idgen, theProc)
      genProc(m, wrapper)
      result.add wrapper.loc.snippet
    else:
      genProc(m, theProc)
      result.add theProc.loc.snippet

    when false:
      if not canFormAcycle(m.g.graph, t) and op == attachedTrace:
        echo "ayclic but has this =trace ", t, " ", theProc.ast
  else:
    when false:
      if op == attachedTrace and m.config.selectedGC == gcOrc and
          containsGarbageCollectedRef(t):
        # unfortunately this check is wrong for an object type that only contains
        # .cursor fields like 'Node' inside 'cycleleak'.
        internalError(m.config, info, "no attached trace proc found")
    result.add NimNil

proc getObjDepth(t: PType): int16 =
  var x = t
  result = -1
  while x != nil:
    x = skipTypes(x, skipPtrs)
    x = x[0]
    inc(result)

proc genDisplayElem(d: MD5Digest): uint32 =
  result = 0
  for i in 0..3:
    result += uint32(d[i])
    result = result shl 8

proc genDisplay(result: var Builder, m: BModule; t: PType, depth: int) =
  var x = t
  var seqs = newSeq[Snippet](depth+1)
  var i = 0
  while x != nil:
    x = skipTypes(x, skipPtrs)
    seqs[i] = cIntValue(genDisplayElem(MD5Digest(hashType(x, m.config))))
    x = x[0]
    inc i

  var arr: StructInitializer
  result.addStructInitializer(arr, siArray):
    for i in countdown(depth, 1):
      result.addField(arr, ""):
        result.add(seqs[i])
    result.addField(arr, ""):
      result.add(seqs[0])

proc genVTable(result: var Builder, seqs: seq[PSym]) =
  var table: StructInitializer
  result.addStructInitializer(table, siArray):
    for i in 0..<seqs.len:
      result.addField(table, ""):
        result.add(cCast(CPointer, seqs[i].loc.snippet))

proc genTypeInfoV2OldImpl(m: BModule; t, origType: PType, name: Rope; info: TLineInfo) =
  cgsym(m, "TNimTypeV2")
  m.s[cfsStrData].addDeclWithVisibility(Private):
    m.s[cfsStrData].addVar(kind = Local, name = name, typ = "TNimTypeV2")

  var flags = 0
  if not canFormAcycle(m.g.graph, t): flags = flags or 1

  var typeEntry = newBuilder("")
  typeEntry.addFieldAssignmentWithValue(name, "destructor"):
    typeEntry.addCast(CPointer):
      genHook(m, t, info, attachedDestructor, typeEntry)
  typeEntry.addFieldAssignmentWithValue(name, "traceImpl"):
    typeEntry.addCast(CPointer):
      genHook(m, t, info, attachedTrace, typeEntry)

  let objDepth = if t.kind == tyObject: getObjDepth(t) else: -1

  if t.kind in {tyObject, tyDistinct} and incompleteType(t):
    localError(m.config, info, "request for RTTI generation for incomplete object: " &
              typeToString(t))

  if isDefined(m.config, "nimTypeNames"):
    var typeName: Snippet
    if t.kind in {tyObject, tyDistinct}:
      typeName = genTypeInfo2Name(m, t)
    else:
      typeName = NimNil
    typeEntry.addFieldAssignment(name, "name", typeName)
  let sizeTyp = getTypeDesc(m, t)
  typeEntry.addFieldAssignmentWithValue(name, "size"):
    typeEntry.addSizeof(sizeTyp)
  typeEntry.addFieldAssignmentWithValue(name, "align"):
    typeEntry.addCast(typ = NimInt16):
      typeEntry.addAlignof(sizeTyp)
  typeEntry.addFieldAssignment(name, "depth", objDepth)
  typeEntry.addFieldAssignment(name, "flags", flags)

  if objDepth >= 0:
    let objDisplayStore = getTempName(m)
    m.s[cfsVars].addArrayVarWithInitializer(kind = Global,
        name = objDisplayStore,
        elementType = getTypeDesc(m, getSysType(m.g.graph, unknownLineInfo, tyUInt32), dkVar),
        len = objDepth + 1):
      genDisplay(m.s[cfsVars], m, t, objDepth)
    typeEntry.addFieldAssignment(name, "display", objDisplayStore)

  let dispatchMethods = toSeq(getMethodsPerType(m.g.graph, t))
  if dispatchMethods.len > 0:
    let vTablePointerName = getTempName(m)
    m.s[cfsVars].addArrayVarWithInitializer(kind = Global,
        name = vTablePointerName,
        elementType = CPointer,
        len = dispatchMethods.len):
      genVTable(m.s[cfsVars], dispatchMethods)
    for i in dispatchMethods:
      genProcPrototype(m, i)
    typeEntry.addFieldAssignment(name, "vTable", vTablePointerName)

  m.s[cfsTypeInit3].add extract(typeEntry)

  if t.kind == tyObject and t.baseClass != nil and optEnableDeepCopy in m.config.globalOptions:
    discard genTypeInfoV1(m, t, info)

proc genTypeInfoV2Impl(m: BModule; t, origType: PType, name: Rope; info: TLineInfo) =
  cgsym(m, "TNimTypeV2")
  m.s[cfsStrData].addDeclWithVisibility(Private):
    m.s[cfsStrData].addVar(kind = Local, name = name, typ = "TNimTypeV2")

  var flags = 0
  if not canFormAcycle(m.g.graph, t): flags = flags or 1

  var typeEntry = newBuilder("")
  typeEntry.addDeclWithVisibility(Private):
    typeEntry.addVarWithInitializer(kind = Local, name = name, typ = "TNimTypeV2"):
      var typeInit: StructInitializer
      typeEntry.addStructInitializer(typeInit, kind = siNamedStruct):
        typeEntry.addField(typeInit, name = "destructor"):
          typeEntry.addCast(CPointer):
            genHook(m, t, info, attachedDestructor, typeEntry)

        let objDepth = if t.kind == tyObject: getObjDepth(t) else: -1

        if t.kind in {tyObject, tyDistinct} and incompleteType(t):
          localError(m.config, info, "request for RTTI generation for incomplete object: " &
                    typeToString(t))

        let sizeType = getTypeDesc(m, t)
        typeEntry.addField(typeInit, name = "size"):
          typeEntry.addSizeof(sizeType)
        typeEntry.addField(typeInit, name = "align"):
          typeEntry.addCast(NimInt16):
            typeEntry.addAlignof(sizeType)
        typeEntry.addField(typeInit, name = "depth"):
          typeEntry.addIntValue(objDepth)

        if objDepth >= 0:
          let objDisplayStore = getTempName(m)
          m.s[cfsVars].addArrayVarWithInitializer(kind = Const,
              name = objDisplayStore,
              elementType = getTypeDesc(m, getSysType(m.g.graph, unknownLineInfo, tyUInt32), dkVar),
              len = objDepth + 1):
            genDisplay(m.s[cfsVars], m, t, objDepth)
          typeEntry.addField(typeInit, name = "display"):
            typeEntry.add(objDisplayStore)
        if isDefined(m.config, "nimTypeNames"):
          var typeName: Rope
          if t.kind in {tyObject, tyDistinct}:
            typeName = genTypeInfo2Name(m, t)
          else:
            typeName = NimNil
          typeEntry.addField(typeInit, name = "name"):
            typeEntry.add(typeName)
        typeEntry.addField(typeInit, name = "traceImpl"):
          typeEntry.addCast(CPointer):
            genHook(m, t, info, attachedTrace, typeEntry)

        let dispatchMethods = toSeq(getMethodsPerType(m.g.graph, t))
        if dispatchMethods.len > 0:
          typeEntry.addField(typeInit, name = "flags"):
            typeEntry.addIntValue(flags)
          for i in dispatchMethods:
            genProcPrototype(m, i)
          typeEntry.addField(typeInit, name = "vTable"):
            genVTable(typeEntry, dispatchMethods)
        else:
          typeEntry.addField(typeInit, name = "flags"):
            typeEntry.addIntValue(flags)
  m.s[cfsVars].add extract(typeEntry)

  if t.kind == tyObject and t.baseClass != nil and optEnableDeepCopy in m.config.globalOptions:
    discard genTypeInfoV1(m, t, info)

proc genTypeInfoV2(m: BModule; t: PType; info: TLineInfo): Rope =
  let origType = t
  # distinct types can have their own destructors
  var t = skipTypes(origType, irrelevantForBackend + tyUserTypeClasses - {tyDistinct})

  template prefixTI(x: Snippet): Snippet =
    if m.hcrOn:
      wrapPar(x)
    else:
      cAddr(x)

  let sig = hashType(origType, m.config)
  result = m.typeInfoMarkerV2.getOrDefault(sig)
  if result != "":
    return prefixTI(result)

  let marker = m.g.typeInfoMarkerV2.getOrDefault(sig)
  if marker.str != "":
    cgsym(m, "TNimTypeV2")
    declareNimType(m, "TNimTypeV2", marker.str, marker.owner)
    # also store in local type section:
    m.typeInfoMarkerV2[sig] = marker.str
    return prefixTI(marker.str)

  result = "NTIv2$1_" % [rope($sig)]
  m.typeInfoMarkerV2[sig] = result

  let owner = t.skipTypes(typedescPtrs).itemId.module
  if owner != m.module.position and moduleOpenForCodegen(m.g.graph, FileIndex owner):
    # make sure the type info is created in the owner module
    discard genTypeInfoV2(m.g.modules[owner], origType, info)
    # reference the type info as extern here
    cgsym(m, "TNimTypeV2")
    declareNimType(m, "TNimTypeV2", result, owner)
    return prefixTI(result)

  m.g.typeInfoMarkerV2[sig] = (str: result, owner: owner)
  if m.compileToCpp or m.hcrOn:
    genTypeInfoV2OldImpl(m, t, origType, result, info)
  else:
    genTypeInfoV2Impl(m, t, origType, result, info)
  result = prefixTI(result)

proc openArrayToTuple(m: BModule; t: PType): PType =
  result = newType(tyTuple, m.idgen, t.owner)
  let p = newType(tyPtr, m.idgen, t.owner)
  let a = newType(tyUncheckedArray, m.idgen, t.owner)
  a.add t.elementType
  p.add a
  result.add p
  result.add getSysType(m.g.graph, t.owner.info, tyInt)

proc typeToC(t: PType): string =
  ## Just for more readable names, the result doesn't have
  ## to be unique.
  let s = typeToString(t)
  result = newStringOfCap(s.len)
  for c in s:
    case c
    of 'a'..'z':
      result.add c
    of 'A'..'Z':
      result.add toLowerAscii(c)
    of ' ':
      discard
    of ',':
      result.add '_'
    of '.':
      result.add 'O'
    of '[', '(', '{':
      result.add 'L'
    of ']', ')', '}':
      result.add 'T'
    else:
      # We mangle upper letters and digits too so that there cannot
      # be clashes with our special meanings
      result.addInt ord(c)

proc genTypeInfoV1(m: BModule; t: PType; info: TLineInfo): Rope =
  let origType = t
  var t = skipTypes(origType, irrelevantForBackend + tyUserTypeClasses)

  template prefixTI(x: Snippet): Snippet =
    if m.hcrOn:
      wrapPar(x)
    else:
      cAddr(x)

  let sig = hashType(origType, m.config)
  result = m.typeInfoMarker.getOrDefault(sig)
  if result != "":
    return prefixTI(result)

  let marker = m.g.typeInfoMarker.getOrDefault(sig)
  if marker.str != "":
    cgsym(m, "TNimType")
    cgsym(m, "TNimNode")
    declareNimType(m, "TNimType", marker.str, marker.owner)
    # also store in local type section:
    m.typeInfoMarker[sig] = marker.str
    return prefixTI(marker.str)

  result = "NTI$1$2_" % [rope(typeToC(t)), rope($sig)]
  m.typeInfoMarker[sig] = result

  let old = m.g.graph.emittedTypeInfo.getOrDefault($result)
  if old != FileIndex(0):
    cgsym(m, "TNimType")
    cgsym(m, "TNimNode")
    declareNimType(m, "TNimType", result, old.int)
    return prefixTI(result)

  var owner = t.skipTypes(typedescPtrs).itemId.module
  if owner != m.module.position and moduleOpenForCodegen(m.g.graph, FileIndex owner):
    # make sure the type info is created in the owner module
    discard genTypeInfoV1(m.g.modules[owner], origType, info)
    # reference the type info as extern here
    cgsym(m, "TNimType")
    cgsym(m, "TNimNode")
    declareNimType(m, "TNimType", result, owner)
    return prefixTI(result)
  else:
    owner = m.module.position.int32

  m.g.typeInfoMarker[sig] = (str: result, owner: owner)
  rememberEmittedTypeInfo(m.g.graph, FileIndex(owner), $result)

  case t.kind
  of tyEmpty, tyVoid: result = cIntValue(0)
  of tyPointer, tyBool, tyChar, tyCstring, tyString, tyInt..tyUInt64, tyVar, tyLent:
    genTypeInfoAuxBase(m, t, t, result, cIntValue(0), info)
  of tyStatic:
    if t.n != nil: result = genTypeInfoV1(m, skipModifier t, info)
    else: internalError(m.config, "genTypeInfoV1(" & $t.kind & ')')
  of tyUserTypeClasses:
    internalAssert m.config, t.isResolvedUserTypeClass
    return genTypeInfoV1(m, t.skipModifier, info)
  of tyProc:
    if t.callConv != ccClosure:
      genTypeInfoAuxBase(m, t, t, result, cIntValue(0), info)
    else:
      let x = fakeClosureType(m, t.owner)
      genTupleInfo(m, x, x, result, info)
  of tySequence:
    genTypeInfoAux(m, t, t, result, info)
    if m.config.selectedGC in {gcMarkAndSweep, gcRefc, gcGo}:
      let markerProc = genTraverseProc(m, origType, sig)
      m.s[cfsTypeInit3].addFieldAssignment(tiNameForHcr(m, result), "marker", markerProc)
  of tyRef:
    genTypeInfoAux(m, t, t, result, info)
    if m.config.selectedGC in {gcMarkAndSweep, gcRefc, gcGo}:
      let markerProc = genTraverseProc(m, origType, sig)
      m.s[cfsTypeInit3].addFieldAssignment(tiNameForHcr(m, result), "marker", markerProc)
  of tyPtr, tyRange, tyUncheckedArray: genTypeInfoAux(m, t, t, result, info)
  of tyArray: genArrayInfo(m, t, result, info)
  of tySet: genSetInfo(m, t, result, info)
  of tyEnum: genEnumInfo(m, t, result, info)
  of tyObject:
    genObjectInfo(m, t, origType, result, info)
  of tyTuple:
    # if t.n != nil: genObjectInfo(m, t, result)
    # else:
    # BUGFIX: use consistently RTTI without proper field names; otherwise
    # results are not deterministic!
    genTupleInfo(m, t, origType, result, info)
  of tyOpenArray:
    let x = openArrayToTuple(m, t)
    genTupleInfo(m, x, origType, result, info)
  else: internalError(m.config, "genTypeInfoV1(" & $t.kind & ')')

  var op = getAttachedOp(m.g.graph, t, attachedDeepCopy)
  if op == nil:
    op = getAttachedOp(m.g.graph, origType, attachedDeepCopy)
  if op != nil:
    genDeepCopyProc(m, op, result)

  if optTinyRtti in m.config.globalOptions and t.kind == tyObject and sfImportc notin t.sym.flags:
    let v2info = genTypeInfoV2(m, origType, info)
    m.s[cfsTypeInit3].addDerefFieldAssignment(v2info, "typeInfoV1", cCast(CPointer, cAddr(result)))
    m.s[cfsTypeInit3].addFieldAssignment(result, "typeInfoV2", cCast(CPointer, v2info))

  result = prefixTI(result)

proc genTypeInfo*(config: ConfigRef, m: BModule; t: PType; info: TLineInfo): Rope =
  if optTinyRtti in config.globalOptions:
    result = genTypeInfoV2(m, t, info)
  else:
    result = genTypeInfoV1(m, t, info)

proc genTypeSection(m: BModule, n: PNode) =
  var intSet = initIntSet()
  for i in 0..<n.len:
    if len(n[i]) == 0: continue
    if n[i][0].kind != nkPragmaExpr: continue
    for p in 0..<n[i][0].len:
      if (n[i][0][p].kind notin {nkSym, nkPostfix}): continue
      var s = n[i][0][p]
      if s.kind == nkPostfix:
        s = n[i][0][p][1]
      if {sfExportc, sfCompilerProc} * s.sym.flags == {sfExportc}:
        discard getTypeDescAux(m, s.typ, intSet, descKindFromSymKind(s.sym.kind))
        if m.g.generatedHeader != nil:
          discard getTypeDescAux(m.g.generatedHeader, s.typ, intSet, descKindFromSymKind(s.sym.kind))

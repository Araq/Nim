#
#
#           The Nim Compiler
#        (c) Copyright 2013 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# included from cgen.nim

when defined(nimCompilerStacktraceHints):
  import std/stackframes

proc getNullValueAuxT(p: BProc; orig, t: PType; obj, constOrNil: PNode,
                      result: var Builder; init: var StructInitializer;
                      isConst: bool, info: TLineInfo)

# -------------------------- constant expressions ------------------------

proc rdSetElemLoc(conf: ConfigRef; a: TLoc, typ: PType; result: var Rope)

proc genLiteral(p: BProc, n: PNode, ty: PType; result: var Builder) =
  case n.kind
  of nkCharLit..nkUInt64Lit:
    var k: TTypeKind
    if ty != nil:
      k = skipTypes(ty, abstractVarRange).kind
    else:
      case n.kind
      of nkCharLit: k = tyChar
      of nkUInt64Lit: k = tyUInt64
      of nkInt64Lit: k = tyInt64
      else: k = tyNil # don't go into the case variant that uses 'ty'
    case k
    of tyChar, tyNil:
      result.addIntLiteral(n.intVal)
    of tyBool:
      if n.intVal != 0: result.add "NIM_TRUE"
      else: result.add "NIM_FALSE"
    of tyInt64: result.addInt64Literal(n.intVal)
    of tyUInt64: result.addUint64Literal(uint64(n.intVal))
    else:
      result.addCast(getTypeDesc(p.module, ty)):
        result.addIntLiteral(n.intVal)
  of nkNilLit:
    let k = if ty == nil: tyPointer else: skipTypes(ty, abstractVarRange).kind
    if k == tyProc and skipTypes(ty, abstractVarRange).callConv == ccClosure:
      let id = nodeTableTestOrSet(p.module.dataCache, n, p.module.labels)
      let tmpName = p.module.tmpBase & rope(id)
      if id == p.module.labels:
        # not found in cache:
        inc(p.module.labels)
        let t = getTypeDesc(p.module, ty)
        p.module.s[cfsStrData].addVarWithInitializer(kind = Const, name = tmpName, typ = t):
          var closureInit: StructInitializer
          p.module.s[cfsStrData].addStructInitializer(closureInit, kind = siOrderedStruct):
            p.module.s[cfsStrData].addField(closureInit, name = "ClP_0"):
              p.module.s[cfsStrData].add("NIM_NIL")
            p.module.s[cfsStrData].addField(closureInit, name = "ClE_0"):
              p.module.s[cfsStrData].add("NIM_NIL")
      result.add tmpName
    elif k in {tyPointer, tyNil, tyProc}:
      result.add rope("NIM_NIL")
    else:
      result.add cCast(getTypeDesc(p.module, ty), "NIM_NIL")
  of nkStrLit..nkTripleStrLit:
    let k = if ty == nil: tyString
            else: skipTypes(ty, abstractVarRange + {tyStatic, tyUserTypeClass, tyUserTypeClassInst}).kind
    case k
    of tyNil:
      genNilStringLiteral(p.module, n.info, result)
    of tyString:
      # with the new semantics for not 'nil' strings, we can map "" to nil and
      # save tons of allocations:
      if n.strVal.len == 0 and optSeqDestructors notin p.config.globalOptions:
        genNilStringLiteral(p.module, n.info, result)
      else:
        genStringLiteral(p.module, n, result)
    else:
      result.add makeCString(n.strVal)
  of nkFloatLit, nkFloat64Lit:
    if ty.kind == tyFloat32:
      result.add rope(n.floatVal.float32.toStrMaxPrecision)
    else:
      result.add rope(n.floatVal.toStrMaxPrecision)
  of nkFloat32Lit:
    result.add rope(n.floatVal.float32.toStrMaxPrecision)
  else:
    internalError(p.config, n.info, "genLiteral(" & $n.kind & ')')

proc genLiteral(p: BProc, n: PNode; result: var Builder) =
  genLiteral(p, n, n.typ, result)

proc genRawSetData(cs: TBitSet, size: int; result: var Builder) =
  if size > 8:
    var setInit: StructInitializer
    result.addStructInitializer(setInit, kind = siArray):
      for i in 0..<size:
        if i mod 8 == 0:
          result.addNewline()
        result.addField(setInit, name = ""):
          result.add "0x"
          result.add "0123456789abcdef"[cs[i] div 16]
          result.add "0123456789abcdef"[cs[i] mod 16]
  else:
    result.addIntLiteral(cast[BiggestInt](bitSetToWord(cs, size)))

proc genSetNode(p: BProc, n: PNode; result: var Builder) =
  var size = int(getSize(p.config, n.typ))
  let cs = toBitSet(p.config, n)
  if size > 8:
    let id = nodeTableTestOrSet(p.module.dataCache, n, p.module.labels)
    let tmpName = p.module.tmpBase & rope(id)
    if id == p.module.labels:
      # not found in cache:
      inc(p.module.labels)
      let td = getTypeDesc(p.module, n.typ)
      p.module.s[cfsStrData].addVarWithInitializer(kind = Const, name = tmpName, typ = td):
        genRawSetData(cs, size, p.module.s[cfsStrData])
    result.add tmpName
  else:
    genRawSetData(cs, size, result)

proc getStorageLoc(n: PNode): TStorageLoc =
  ## deadcode
  case n.kind
  of nkSym:
    case n.sym.kind
    of skParam, skTemp:
      result = OnStack
    of skVar, skForVar, skResult, skLet:
      if sfGlobal in n.sym.flags: result = OnHeap
      else: result = OnStack
    of skConst:
      if sfGlobal in n.sym.flags: result = OnHeap
      else: result = OnUnknown
    else: result = OnUnknown
  of nkDerefExpr, nkHiddenDeref:
    case n[0].typ.kind
    of tyVar, tyLent: result = OnUnknown
    of tyPtr: result = OnStack
    of tyRef: result = OnHeap
    else:
      result = OnUnknown
      doAssert(false, "getStorageLoc")
  of nkBracketExpr, nkDotExpr, nkObjDownConv, nkObjUpConv:
    result = getStorageLoc(n[0])
  else: result = OnUnknown

proc canMove(p: BProc, n: PNode; dest: TLoc): bool =
  # for now we're conservative here:
  if n.kind == nkBracket:
    # This needs to be kept consistent with 'const' seq code
    # generation!
    if not isDeepConstExpr(n) or n.len == 0:
      if skipTypes(n.typ, abstractVarRange).kind == tySequence:
        return true
  elif n.kind in nkStrKinds and n.strVal.len == 0:
    # Empty strings are codegen'd as NIM_NIL so it's just a pointer copy
    return true
  result = n.kind in nkCallKinds
  #if not result and dest.k == locTemp:
  #  return true

  #if result:
  #  echo n.info, " optimized ", n
  #  result = false

template simpleAsgn(builder: var Builder, dest, src: TLoc) =
  let rd = rdLoc(dest)
  let rs = rdLoc(src)
  builder.addAssignment(rd, rs) 

proc genRefAssign(p: BProc, dest, src: TLoc) =
  if (dest.storage == OnStack and p.config.selectedGC != gcGo) or not usesWriteBarrier(p.config):
    simpleAsgn(p.s(cpsStmts), dest, src)
  else:
    let fnName =
      if dest.storage == OnHeap: cgsymValue(p.module, "asgnRef")
      else: cgsymValue(p.module, "unsureAsgnRef")
    let rad = addrLoc(p.config, dest)
    let rs = rdLoc(src)
    p.s(cpsStmts).addCallStmt(fnName, cCast("void**", rad), rs)

proc asgnComplexity(n: PNode): int =
  if n != nil:
    case n.kind
    of nkSym: result = 1
    of nkRecCase:
      # 'case objects' are too difficult to inline their assignment operation:
      result = 100
    of nkRecList:
      result = 0
      for t in items(n):
        result += asgnComplexity(t)
    else: result = 0
  else:
    result = 0

proc optAsgnLoc(a: TLoc, t: PType, field: Rope): TLoc =
  assert field != ""
  result = TLoc(k: locField,
    storage: a.storage,
    lode: lodeTyp t,
    snippet: rdLoc(a) & "." & field
  )

proc genOptAsgnTuple(p: BProc, dest, src: TLoc, flags: TAssignmentFlags) =
  let newflags =
    if src.storage == OnStatic:
      flags + {needToCopy}
    elif tfShallow in dest.t.flags:
      flags - {needToCopy}
    else:
      flags
  let t = skipTypes(dest.t, abstractInst).getUniqueType()
  for i, t in t.ikids:
    let field = "Field$1" % [i.rope]
    genAssignment(p, optAsgnLoc(dest, t, field),
                     optAsgnLoc(src, t, field), newflags)

proc genOptAsgnObject(p: BProc, dest, src: TLoc, flags: TAssignmentFlags,
                      t: PNode, typ: PType) =
  if t == nil: return
  let newflags =
    if src.storage == OnStatic:
      flags + {needToCopy}
    elif tfShallow in dest.t.flags:
      flags - {needToCopy}
    else:
      flags
  case t.kind
  of nkSym:
    let field = t.sym
    if field.loc.snippet == "": fillObjectFields(p.module, typ)
    genAssignment(p, optAsgnLoc(dest, field.typ, field.loc.snippet),
                     optAsgnLoc(src, field.typ, field.loc.snippet), newflags)
  of nkRecList:
    for child in items(t): genOptAsgnObject(p, dest, src, newflags, child, typ)
  else: discard

proc genGenericAsgn(p: BProc, dest, src: TLoc, flags: TAssignmentFlags) =
  # Consider:
  # type TMyFastString {.shallow.} = string
  # Due to the implementation of pragmas this would end up to set the
  # tfShallow flag for the built-in string type too! So we check only
  # here for this flag, where it is reasonably safe to do so
  # (for objects, etc.):
  if optSeqDestructors in p.config.globalOptions:
    simpleAsgn(p.s(cpsStmts), dest, src)
  elif needToCopy notin flags or
      tfShallow in skipTypes(dest.t, abstractVarRange).flags:
    if (dest.storage == OnStack and p.config.selectedGC != gcGo) or not usesWriteBarrier(p.config):
      let rad = addrLoc(p.config, dest)
      let ras = addrLoc(p.config, src)
      let rd = rdLoc(dest)
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "nimCopyMem"),
        cCast("void*", rad),
        cCast(ptrConstType("void"), ras),
        cSizeof(rd))
    else:
      let rad = addrLoc(p.config, dest)
      let ras = addrLoc(p.config, src)
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "genericShallowAssign"),
        cCast("void*", rad),
        cCast("void*", ras),
        genTypeInfoV1(p.module, dest.t, dest.lode.info))
  else:
    let rad = addrLoc(p.config, dest)
    let ras = addrLoc(p.config, src)
    p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "genericAssign"),
      cCast("void*", rad),
      cCast("void*", ras),
      genTypeInfoV1(p.module, dest.t, dest.lode.info))

proc genOpenArrayConv(p: BProc; d: TLoc; a: TLoc; flags: TAssignmentFlags) =
  assert d.k != locNone
  #  getTemp(p, d.t, d)

  case a.t.skipTypes(abstractVar).kind
  of tyOpenArray, tyVarargs:
    if reifiedOpenArray(a.lode):
      if needTempForOpenArray in flags:
        var tmp: TLoc = getTemp(p, a.t)
        let rtmp = tmp.rdLoc
        let ra = a.rdLoc
        p.s(cpsStmts).addAssignment(rtmp, ra)
        let rd = d.rdLoc
        p.s(cpsStmts).addMutualFieldAssignment(rd, rtmp, "Field0")
        p.s(cpsStmts).addMutualFieldAssignment(rd, rtmp, "Field1")
      else:
        let rd = d.rdLoc
        let ra = a.rdLoc
        p.s(cpsStmts).addMutualFieldAssignment(rd, ra, "Field0")
        p.s(cpsStmts).addMutualFieldAssignment(rd, ra, "Field1")
    else:
      let rd = d.rdLoc
      let ra = a.rdLoc
      p.s(cpsStmts).addFieldAssignment(rd, "Field0", ra)
      p.s(cpsStmts).addFieldAssignment(rd, "Field1", ra & "Len_0")
  of tySequence:
    let rd = d.rdLoc
    let ra = a.rdLoc
    let la = lenExpr(p, a)
    p.s(cpsStmts).addFieldAssignment(rd, "Field0",
      cIfExpr(dataFieldAccessor(p, ra), dataField(p, ra), "NIM_NIL"))
    p.s(cpsStmts).addFieldAssignment(rd, "Field1", la)
  of tyArray:
    let rd = d.rdLoc
    let ra = a.rdLoc
    p.s(cpsStmts).addFieldAssignment(rd, "Field0", ra)
    p.s(cpsStmts).addFieldAssignment(rd, "Field1", lengthOrd(p.config, a.t))
  of tyString:
    let etyp = skipTypes(a.t, abstractInst)
    if etyp.kind in {tyVar} and optSeqDestructors in p.config.globalOptions:
      let bra = byRefLoc(p, a)
      p.s(cpsStmts).addCallStmt(
        cgsymValue(p.module, "nimPrepareStrMutationV2"),
        bra)

    let rd = d.rdLoc
    let ra = a.rdLoc
    p.s(cpsStmts).addFieldAssignment(rd, "Field0",
      cIfExpr(dataFieldAccessor(p, ra), dataField(p, ra), "NIM_NIL"))
    let la = lenExpr(p, a)
    p.s(cpsStmts).addFieldAssignment(rd, "Field1", la)
  else:
    internalError(p.config, a.lode.info, "cannot handle " & $a.t.kind)

template cgCall(p: BProc, name: string, args: varargs[untyped]): untyped =
  cCall(cgsymValue(p.module, name), args)

proc genAssignment(p: BProc, dest, src: TLoc, flags: TAssignmentFlags) =
  # This function replaces all other methods for generating
  # the assignment operation in C.
  if src.t != nil and src.t.kind == tyPtr:
    # little HACK to support the new 'var T' as return type:
    simpleAsgn(p.s(cpsStmts), dest, src)
    return
  let ty = skipTypes(dest.t, abstractRange + tyUserTypeClasses + {tyStatic})
  case ty.kind
  of tyRef:
    genRefAssign(p, dest, src)
  of tySequence:
    if optSeqDestructors in p.config.globalOptions:
      genGenericAsgn(p, dest, src, flags)
    elif (needToCopy notin flags and src.storage != OnStatic) or canMove(p, src.lode, dest):
      genRefAssign(p, dest, src)
    else:
      let rad = addrLoc(p.config, dest)
      let rs = rdLoc(src)
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "genericSeqAssign"),
        rad,
        rs,
        genTypeInfoV1(p.module, dest.t, dest.lode.info))
  of tyString:
    if optSeqDestructors in p.config.globalOptions:
      genGenericAsgn(p, dest, src, flags)
    elif ({needToCopy, needToCopySinkParam} * flags == {} and src.storage != OnStatic) or canMove(p, src.lode, dest):
      genRefAssign(p, dest, src)
    else:
      if (dest.storage == OnStack and p.config.selectedGC != gcGo) or not usesWriteBarrier(p.config):
        let rd = rdLoc(dest)
        let rs = rdLoc(src)
        p.s(cpsStmts).addAssignmentWithValue(rd):
          p.s(cpsStmts).addCall(cgsymValue(p.module, "copyString"), rs)
      elif dest.storage == OnHeap:
        let rd = rdLoc(dest)
        let rs = rdLoc(src)
        # we use a temporary to care for the dreaded self assignment:
        var tmp: TLoc = getTemp(p, ty)
        let rtmp = rdLoc(tmp)
        p.s(cpsStmts).addAssignment(rtmp, rd)
        p.s(cpsStmts).addAssignmentWithValue(rd):
          p.s(cpsStmts).addCall(cgsymValue(p.module, "copyStringRC1"), rs)
        p.s(cpsStmts).addSingleIfStmt(rtmp):
          p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "nimGCunrefNoCycle"), rtmp)
      else:
        let rad = addrLoc(p.config, dest)
        let rs = rdLoc(src)
        p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "unsureAsgnRef"),
          cCast("void**", rad),
          cgCall(p, "copyString", rs))
  of tyProc:
    if containsGarbageCollectedRef(dest.t):
      # optimize closure assignment:
      let a = optAsgnLoc(dest, dest.t, "ClE_0".rope)
      let b = optAsgnLoc(src, dest.t, "ClE_0".rope)
      genRefAssign(p, a, b)
      let rd = rdLoc(dest)
      let rs = rdLoc(src)
      p.s(cpsStmts).addMutualFieldAssignment(rd, rs, "ClP_0")
    else:
      simpleAsgn(p.s(cpsStmts), dest, src)
  of tyTuple:
    if containsGarbageCollectedRef(dest.t):
      if dest.t.kidsLen <= 4: genOptAsgnTuple(p, dest, src, flags)
      else: genGenericAsgn(p, dest, src, flags)
    else:
      simpleAsgn(p.s(cpsStmts), dest, src)
  of tyObject:
    # XXX: check for subtyping?
    if ty.isImportedCppType:
      simpleAsgn(p.s(cpsStmts), dest, src)
    elif not isObjLackingTypeField(ty):
      genGenericAsgn(p, dest, src, flags)
    elif containsGarbageCollectedRef(ty):
      if ty[0].isNil and asgnComplexity(ty.n) <= 4 and
            needAssignCall notin flags: # calls might contain side effects
        discard getTypeDesc(p.module, ty)
        internalAssert p.config, ty.n != nil
        genOptAsgnObject(p, dest, src, flags, ty.n, ty)
      else:
        genGenericAsgn(p, dest, src, flags)
    else:
      simpleAsgn(p.s(cpsStmts), dest, src)
  of tyArray:
    if containsGarbageCollectedRef(dest.t) and p.config.selectedGC notin {gcArc, gcAtomicArc, gcOrc, gcHooks}:
      genGenericAsgn(p, dest, src, flags)
    else:
      let rd = rdLoc(dest)
      let rs = rdLoc(src)
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "nimCopyMem"),
        cCast("void*", rd),
        cCast(ptrConstType("void"), rs),
        cSizeof(getTypeDesc(p.module, dest.t)))
  of tyOpenArray, tyVarargs:
    # open arrays are always on the stack - really? What if a sequence is
    # passed to an open array?
    if reifiedOpenArray(dest.lode):
      genOpenArrayConv(p, dest, src, flags)
    elif containsGarbageCollectedRef(dest.t):
      let rad = addrLoc(p.config, dest)
      let ras = addrLoc(p.config, src)
      # XXX: is this correct for arrays?
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "genericAssignOpenArray"),
        cCast("void*", rad),
        cCast("void*", ras),
        rad & "Len_0",
        genTypeInfoV1(p.module, dest.t, dest.lode.info))
    else:
      simpleAsgn(p.s(cpsStmts), dest, src)
      #linefmt(p, cpsStmts,
           # bug #4799, keep the nimCopyMem for a while
           #"#nimCopyMem((void*)$1, (NIM_CONST void*)$2, sizeof($1[0])*$1Len_0);\n")
  of tySet:
    if mapSetType(p.config, ty) == ctArray:
      let rd = rdLoc(dest)
      let rs = rdLoc(src)
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "nimCopyMem"),
        cCast("void*", rd),
        cCast(ptrConstType("void"), rs),
        cIntValue(getSize(p.config, dest.t)))
    else:
      simpleAsgn(p.s(cpsStmts), dest, src)
  of tyPtr, tyPointer, tyChar, tyBool, tyEnum, tyCstring,
     tyInt..tyUInt64, tyRange, tyVar, tyLent, tyNil:
    simpleAsgn(p.s(cpsStmts), dest, src)
  else: internalError(p.config, "genAssignment: " & $ty.kind)

  if optMemTracker in p.options and dest.storage in {OnHeap, OnUnknown}:
    #writeStackTrace()
    #echo p.currLineInfo, " requesting"
    let rad = addrLoc(p.config, dest)
    p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "memTrackerWrite"),
      cCast("void*", rad),
      cIntValue(getSize(p.config, dest.t)),
      makeCString(toFullPath(p.config, p.currLineInfo)),
      cIntValue(p.currLineInfo.safeLineNm))

proc genDeepCopy(p: BProc; dest, src: TLoc) =
  template addrLocOrTemp(a: TLoc): Rope =
    if a.k == locExpr:
      var tmp: TLoc = getTemp(p, a.t)
      genAssignment(p, tmp, a, {})
      addrLoc(p.config, tmp)
    else:
      addrLoc(p.config, a)

  var ty = skipTypes(dest.t, abstractVarRange + {tyStatic})
  case ty.kind
  of tyPtr, tyRef, tyProc, tyTuple, tyObject, tyArray:
    # XXX optimize this
    let rad = addrLoc(p.config, dest)
    let rats = addrLocOrTemp(src)
    p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "genericDeepCopy"),
      cCast("void*", rad),
      cCast("void*", rats),
      genTypeInfoV1(p.module, dest.t, dest.lode.info))
  of tySequence, tyString:
    if optTinyRtti in p.config.globalOptions:
      let rad = addrLoc(p.config, dest)
      let rats = addrLocOrTemp(src)
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "genericDeepCopy"),
        cCast("void*", rad),
        cCast("void*", rats),
        genTypeInfoV1(p.module, dest.t, dest.lode.info))
    else:
      let rad = addrLoc(p.config, dest)
      let rs = rdLoc(src)
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "genericSeqDeepCopy"),
        rad,
        rs,
        genTypeInfoV1(p.module, dest.t, dest.lode.info))
  of tyOpenArray, tyVarargs:
    let source = addrLocOrTemp(src)
    let rad = addrLoc(p.config, dest)
    p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "genericDeepCopyOpenArray"),
      cCast("void*", rad),
      cCast("void*", source),
      derefField(source, "Field1"),
      genTypeInfoV1(p.module, dest.t, dest.lode.info))
  of tySet:
    if mapSetType(p.config, ty) == ctArray:
      let rd = rdLoc(dest)
      let rs = rdLoc(src)
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "nimCopyMem"),
        cCast("void*", rd),
        cCast(ptrConstType("void"), rs),
        cIntValue(getSize(p.config, dest.t)))
    else:
      simpleAsgn(p.s(cpsStmts), dest, src)
  of tyPointer, tyChar, tyBool, tyEnum, tyCstring,
     tyInt..tyUInt64, tyRange, tyVar, tyLent:
    simpleAsgn(p.s(cpsStmts), dest, src)
  else: internalError(p.config, "genDeepCopy: " & $ty.kind)

proc putLocIntoDest(p: BProc, d: var TLoc, s: TLoc) =
  if d.k != locNone:
    if lfNoDeepCopy in d.flags: genAssignment(p, d, s, {})
    else: genAssignment(p, d, s, {needToCopy})
  else:
    d = s # ``d`` is free, so fill it with ``s``

proc putDataIntoDest(p: BProc, d: var TLoc, n: PNode, r: Rope) =
  if d.k != locNone:
    var a: TLoc = initLoc(locData, n, OnStatic)
    # need to generate an assignment here
    a.snippet = r
    if lfNoDeepCopy in d.flags: genAssignment(p, d, a, {})
    else: genAssignment(p, d, a, {needToCopy})
  else:
    # we cannot call initLoc() here as that would overwrite
    # the flags field!
    d.k = locData
    d.lode = n
    d.snippet = r

proc putIntoDest(p: BProc, d: var TLoc, n: PNode, r: Rope; s=OnUnknown) =
  if d.k != locNone:
    # need to generate an assignment here
    var a: TLoc = initLoc(locExpr, n, s)
    a.snippet = r
    if lfNoDeepCopy in d.flags: genAssignment(p, d, a, {})
    else: genAssignment(p, d, a, {needToCopy})
  else:
    # we cannot call initLoc() here as that would overwrite
    # the flags field!
    d.k = locExpr
    d.lode = n
    d.snippet = r

proc binaryStmt(p: BProc, e: PNode, d: var TLoc, op: TypedBinaryOp) =
  if d.k != locNone: internalError(p.config, e.info, "binaryStmt")
  var a = initLocExpr(p, e[1])
  var b = initLocExpr(p, e[2])
  let ra = rdLoc(a)
  let rb = rdLoc(b)
  p.s(cpsStmts).addInPlaceOp(op, getSimpleTypeDesc(p.module, e[1].typ), ra, rb)

proc binaryStmtAddr(p: BProc, e: PNode, d: var TLoc, cpname: string) =
  if d.k != locNone: internalError(p.config, e.info, "binaryStmtAddr")
  var a = initLocExpr(p, e[1])
  var b = initLocExpr(p, e[2])
  let bra = byRefLoc(p, a)
  let rb = rdLoc(b)
  p.s(cpsStmts).addCallStmt(cgsymValue(p.module, cpname), bra, rb)

template binaryExpr(p: BProc, e: PNode, d: var TLoc, frmt: untyped) =
  assert(e[1].typ != nil)
  assert(e[2].typ != nil)
  block:
    var a = initLocExpr(p, e[1])
    var b = initLocExpr(p, e[2])
    let ra {.inject.} = rdLoc(a)
    let rb {.inject.} = rdLoc(b)
    putIntoDest(p, d, e, frmt)

template binaryExprChar(p: BProc, e: PNode, d: var TLoc, frmt: untyped) =
  assert(e[1].typ != nil)
  assert(e[2].typ != nil)
  block:
    var a = initLocExpr(p, e[1])
    var b = initLocExpr(p, e[2])
    let ra {.inject.} = rdCharLoc(a)
    let rb {.inject.} = rdCharLoc(b)
    putIntoDest(p, d, e, frmt)

template unaryExpr(p: BProc, e: PNode, d: var TLoc, frmt: untyped) =
  block:
    var a: TLoc = initLocExpr(p, e[1])
    let ra {.inject.} = rdLoc(a)
    putIntoDest(p, d, e, frmt)

template unaryExprChar(p: BProc, e: PNode, d: var TLoc, frmt: untyped) =
  block:
    var a: TLoc = initLocExpr(p, e[1])
    let ra {.inject.} = rdCharLoc(a)
    putIntoDest(p, d, e, frmt)

template binaryArithOverflowRaw(p: BProc, t: PType, a, b: TLoc;
                            cpname: string): Rope =
  var size = getSize(p.config, t)
  let storage = if size < p.config.target.intSize: rope("NI")
                else: getTypeDesc(p.module, t)
  var result = getTempName(p.module)
  p.s(cpsLocals).addVar(kind = Local, name = result, typ = storage)
  let rca = rdCharLoc(a)
  let rcb = rdCharLoc(b)
  p.s(cpsStmts).addSingleIfStmtWithCond():
    p.s(cpsStmts).addCall(cgsymValue(p.module, cpname),
      rca,
      rcb,
      cAddr(result))
  do:
    p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "raiseOverflow"))
    raiseInstr(p, p.s(cpsStmts))

  if size < p.config.target.intSize or t.kind in {tyRange, tyEnum}:
    let first = cIntLiteral(firstOrd(p.config, t))
    let last = cIntLiteral(lastOrd(p.config, t))
    p.s(cpsStmts).addSingleIfStmtWithCond():
      p.s(cpsStmts).addOp(Or,
        cOp(LessThan, result, first),
        cOp(GreaterThan, result, last))
    do:
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "raiseOverflow"))
      raiseInstr(p, p.s(cpsStmts))

  result

proc binaryArithOverflow(p: BProc, e: PNode, d: var TLoc, m: TMagic) =
  const
    prc: array[mAddI..mPred, string] = [
      "nimAddInt", "nimSubInt",
      "nimMulInt", "nimDivInt", "nimModInt",
      "nimAddInt", "nimSubInt"
    ]
    prc64: array[mAddI..mPred, string] = [
      "nimAddInt64", "nimSubInt64",
      "nimMulInt64", "nimDivInt64", "nimModInt64",
      "nimAddInt64", "nimSubInt64"
    ]
    opr: array[mAddI..mPred, TypedBinaryOp] = [Add, Sub, Mul, Div, Mod, Add, Sub]
  assert(e[1].typ != nil)
  assert(e[2].typ != nil)
  var a = initLocExpr(p, e[1])
  var b = initLocExpr(p, e[2])
  # skipping 'range' is correct here as we'll generate a proper range check
  # later via 'chckRange'
  let t = e.typ.skipTypes(abstractRange)
  if optOverflowCheck notin p.options or (m in {mSucc, mPred} and t.kind in {tyUInt..tyUInt64}):
    let typ = getTypeDesc(p.module, e.typ)
    let res = cCast(typ, cOp(opr[m], typ, rdLoc(a), rdLoc(b)))
    putIntoDest(p, d, e, res)
  else:
    # we handle div by zero here so that we know that the compilerproc's
    # result is only for overflows.
    var needsOverflowCheck = true
    if m in {mDivI, mModI}:
      var canBeZero = true
      if e[2].kind in {nkIntLit..nkUInt64Lit}:
        canBeZero = e[2].intVal == 0
      if e[2].kind in {nkIntLit..nkInt64Lit}:
        needsOverflowCheck = e[2].intVal == -1
      if canBeZero:
        # remove extra paren from `==` op here to avoid Wparentheses-equality: 
        p.s(cpsStmts).addSingleIfStmt(removeSinglePar(cOp(Equal, rdLoc(b), cIntValue(0)))):
          p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "raiseDivByZero"))
          raiseInstr(p, p.s(cpsStmts))
    if needsOverflowCheck:
      let res = binaryArithOverflowRaw(p, t, a, b,
        if t.kind == tyInt64: prc64[m] else: prc[m])
      putIntoDest(p, d, e, cCast(getTypeDesc(p.module, e.typ), res))
    else:
      let typ = getTypeDesc(p.module, e.typ)
      let res = cCast(typ, cOp(opr[m], typ, wrapPar(rdLoc(a)), wrapPar(rdLoc(b))))
      putIntoDest(p, d, e, res)

proc unaryArithOverflow(p: BProc, e: PNode, d: var TLoc, m: TMagic) =
  var t: PType
  assert(e[1].typ != nil)
  var a: TLoc = initLocExpr(p, e[1])
  t = skipTypes(e.typ, abstractRange)
  let ra = rdLoc(a)
  if optOverflowCheck in p.options:
    let first = cIntLiteral(firstOrd(p.config, t))
    # remove extra paren from `==` op here to avoid Wparentheses-equality: 
    p.s(cpsStmts).addSingleIfStmt(removeSinglePar(cOp(Equal, ra, first))):
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "raiseOverflow"))
      raiseInstr(p, p.s(cpsStmts))

  case m
  of mUnaryMinusI:
    let typ = "NI" & rope(getSize(p.config, t) * 8)
    putIntoDest(p, d, e, cCast(typ, cOp(Neg, typ, ra)))
  of mUnaryMinusI64:
    putIntoDest(p, d, e, cOp(Neg, getTypeDesc(p.module, t), ra))
  of mAbsI:
    putIntoDest(p, d, e,
      cIfExpr(cOp(GreaterThan, ra, cIntValue(0)),
        wrapPar(ra),
        cOp(Neg, getTypeDesc(p.module, t), ra)))
  else:
    assert(false, $m)

proc binaryArith(p: BProc, e: PNode, d: var TLoc, op: TMagic) =
  var
    s, k: BiggestInt = 0
  assert(e[1].typ != nil)
  assert(e[2].typ != nil)
  var a = initLocExpr(p, e[1])
  var b = initLocExpr(p, e[2])
  # BUGFIX: cannot use result-type here, as it may be a boolean
  s = max(getSize(p.config, a.t), getSize(p.config, b.t)) * 8
  k = getSize(p.config, a.t) * 8

  var res = ""
  template getType(): untyped =
    getSimpleTypeDesc(p.module, e.typ)
  let ra = rdLoc(a)
  let rb = rdLoc(b)

  case op
  of mAddF64:
    let t = getType()
    res = cOp(Add, t, cCast(t, ra), cCast(t, rb))
  of mSubF64:
    let t = getType()
    res = cOp(Sub, t, cCast(t, ra), cCast(t, rb))
  of mMulF64:
    let t = getType()
    res = cOp(Mul, t, cCast(t, ra), cCast(t, rb))
  of mDivF64:
    let t = getType()
    res = cOp(Div, t, cCast(t, ra), cCast(t, rb))
  of mShrI:
    let t = getType()
    let at = "NU" & $k
    let bt = "NU" & $s
    res = cCast(t, cOp(Shr, at, cCast(at, ra), cCast(bt, rb)))
  of mShlI:
    let t = getType()
    let at = "NU" & $s
    res = cCast(t, cOp(Shl, at, cCast(at, ra), cCast(at, rb)))
  of mAshrI:
    let t = getType()
    let at = "NI" & $s
    let bt = "NU" & $s
    res = cCast(t, cOp(Shr, at, cCast(at, ra), cCast(bt, rb)))
  of mBitandI:
    let t = getType()
    res = cCast(t, cOp(BitAnd, t, ra, rb))
  of mBitorI:
    let t = getType()
    res = cCast(t, cOp(BitOr, t, ra, rb))
  of mBitxorI:
    let t = getType()
    res = cCast(t, cOp(BitXor, t, ra, rb))
  of mMinI:
    res = cIfExpr(cOp(LessEqual, ra, rb), ra, rb)
  of mMaxI:
    res = cIfExpr(cOp(GreaterEqual, ra, rb), ra, rb)
  of mAddU:
    let t = getType()
    let ot = "NU" & $s
    res = cCast(t, cOp(Add, ot, cCast(ot, ra), cCast(ot, rb)))
  of mSubU:
    let t = getType()
    let ot = "NU" & $s
    res = cCast(t, cOp(Sub, ot, cCast(ot, ra), cCast(ot, rb)))
  of mMulU:
    let t = getType()
    let ot = "NU" & $s
    res = cCast(t, cOp(Mul, ot, cCast(ot, ra), cCast(ot, rb)))
  of mDivU:
    let t = getType()
    let ot = "NU" & $s
    res = cCast(t, cOp(Div, ot, cCast(ot, ra), cCast(ot, rb)))
  of mModU:
    let t = getType()
    let ot = "NU" & $s
    res = cCast(t, cOp(Mod, ot, cCast(ot, ra), cCast(ot, rb)))
  of mEqI:
    res = cOp(Equal, ra, rb)
  of mLeI:
    res = cOp(LessEqual, ra, rb)
  of mLtI:
    res = cOp(LessThan, ra, rb)
  of mEqF64:
    res = cOp(Equal, ra, rb)
  of mLeF64:
    res = cOp(LessEqual, ra, rb)
  of mLtF64:
    res = cOp(LessThan, ra, rb)
  of mLeU:
    let ot = "NU" & $s
    res = cOp(LessEqual, cCast(ot, ra), cCast(ot, rb))
  of mLtU:
    let ot = "NU" & $s
    res = cOp(LessThan, cCast(ot, ra), cCast(ot, rb))
  of mEqEnum:
    res = cOp(Equal, ra, rb)
  of mLeEnum:
    res = cOp(LessEqual, ra, rb)
  of mLtEnum:
    res = cOp(LessThan, ra, rb)
  of mEqCh:
    res = cOp(Equal, cCast("NU8", ra), cCast("NU8", rb))
  of mLeCh:
    res = cOp(LessEqual, cCast("NU8", ra), cCast("NU8", rb))
  of mLtCh:
    res = cOp(LessThan, cCast("NU8", ra), cCast("NU8", rb))
  of mEqB:
    res = cOp(Equal, ra, rb)
  of mLeB:
    res = cOp(LessEqual, ra, rb)
  of mLtB:
    res = cOp(LessThan, ra, rb)
  of mEqRef:
    res = cOp(Equal, ra, rb)
  of mLePtr:
    res = cOp(LessEqual, ra, rb)
  of mLtPtr:
    res = cOp(LessThan, ra, rb)
  of mXor:
    res = cOp(NotEqual, ra, rb)
  else:
    assert(false, $op)
  putIntoDest(p, d, e, res)

proc genEqProc(p: BProc, e: PNode, d: var TLoc) =
  assert(e[1].typ != nil)
  assert(e[2].typ != nil)
  var a = initLocExpr(p, e[1])
  var b = initLocExpr(p, e[2])
  let ra = rdLoc(a)
  let rb = rdLoc(b)
  if a.t.skipTypes(abstractInstOwned).callConv == ccClosure:
    putIntoDest(p, d, e, cOp(And,
      cOp(Equal, dotField(ra, "ClP_0"), dotField(rb, "ClP_0")),
      cOp(Equal, dotField(ra, "ClE_0"), dotField(rb, "ClE_0"))))
  else:
    putIntoDest(p, d, e, cOp(Equal, ra, rb))

proc genIsNil(p: BProc, e: PNode, d: var TLoc) =
  let t = skipTypes(e[1].typ, abstractRange)
  var a: TLoc = initLocExpr(p, e[1])
  let ra = rdLoc(a)
  var res = ""
  if t.kind == tyProc and t.callConv == ccClosure:
    res = cOp(Equal, dotField(ra, "ClP_0"), cIntValue(0))
  else:
    res = cOp(Equal, ra, cIntValue(0))
  putIntoDest(p, d, e, res)

proc unaryArith(p: BProc, e: PNode, d: var TLoc, op: TMagic) =
  var
    t: PType
  assert(e[1].typ != nil)
  var a = initLocExpr(p, e[1])
  t = skipTypes(e.typ, abstractRange)

  var res = ""
  let ra = rdLoc(a)

  case op
  of mNot:
    res = cOp(Not, ra)
  of mUnaryPlusI:
    res = ra
  of mBitnotI:
    let at = "NU" & $(getSize(p.config, t) * 8)
    let t = getSimpleTypeDesc(p.module, e.typ)
    res = cCast(t, cCast(at, cOp(BitNot, t, ra)))
  of mUnaryPlusF64:
    res = ra
  of mUnaryMinusF64:
    res = cOp(Neg, getSimpleTypeDesc(p.module, e.typ), ra)
  else:
    assert false, $op
  putIntoDest(p, d, e, res)

proc isCppRef(p: BProc; typ: PType): bool {.inline.} =
  result = p.module.compileToCpp and
      skipTypes(typ, abstractInstOwned).kind in {tyVar} and
      tfVarIsPtr notin skipTypes(typ, abstractInstOwned).flags

proc genDeref(p: BProc, e: PNode, d: var TLoc) =
  let mt = mapType(p.config, e[0].typ, mapTypeChooser(e[0]) == skParam)
  if mt in {ctArray, ctPtrToArray} and lfEnforceDeref notin d.flags:
    # XXX the amount of hacks for C's arrays is incredible, maybe we should
    # simply wrap them in a struct? --> Losing auto vectorization then?
    expr(p, e[0], d)
    if e[0].typ.skipTypes(abstractInstOwned).kind == tyRef:
      d.storage = OnHeap
  else:
    var a: TLoc
    var typ = e[0].typ
    if typ.kind in {tyUserTypeClass, tyUserTypeClassInst} and typ.isResolvedUserTypeClass:
      typ = typ.last
    typ = typ.skipTypes(abstractInstOwned)
    if typ.kind in {tyVar} and tfVarIsPtr notin typ.flags and
        p.module.compileToCpp and e[0].kind == nkHiddenAddr and
        # don't override existing location:
        d.k == locNone:
      d = initLocExprSingleUse(p, e[0][0])
      return
    else:
      a = initLocExprSingleUse(p, e[0])
    if d.k == locNone:
      # dest = *a;  <-- We do not know that 'dest' is on the heap!
      # It is completely wrong to set 'd.storage' here, unless it's not yet
      # been assigned to.
      case typ.kind
      of tyRef:
        d.storage = OnHeap
      of tyVar, tyLent:
        d.storage = OnUnknown
        if tfVarIsPtr notin typ.flags and p.module.compileToCpp and
            e.kind == nkHiddenDeref:
          putIntoDest(p, d, e, rdLoc(a), a.storage)
          return
      of tyPtr:
        d.storage = OnUnknown         # BUGFIX!
      else:
        internalError(p.config, e.info, "genDeref " & $typ.kind)
    elif p.module.compileToCpp:
      if typ.kind in {tyVar} and tfVarIsPtr notin typ.flags and
           e.kind == nkHiddenDeref:
        putIntoDest(p, d, e, rdLoc(a), a.storage)
        return
    if mt == ctPtrToArray and lfEnforceDeref in d.flags:
      # we lie about the type for better C interop: 'ptr array[3,T]' is
      # translated to 'ptr T', but for deref'ing this produces wrong code.
      # See tmissingderef. So we get rid of the deref instead. The codegen
      # ends up using 'memcpy' for the array assignment,
      # so the '&' and '*' cancel out:
      putIntoDest(p, d, e, rdLoc(a), a.storage)
    else:
      putIntoDest(p, d, e, cDeref(rdLoc(a)), a.storage)

proc cowBracket(p: BProc; n: PNode) =
  if n.kind == nkBracketExpr and optSeqDestructors in p.config.globalOptions:
    let strCandidate = n[0]
    if strCandidate.typ.skipTypes(abstractInst).kind == tyString:
      var a: TLoc = initLocExpr(p, strCandidate)
      let raa = byRefLoc(p, a)
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "nimPrepareStrMutationV2"), raa)

proc cow(p: BProc; n: PNode) {.inline.} =
  if n.kind == nkHiddenAddr: cowBracket(p, n[0])

proc genAddr(p: BProc, e: PNode, d: var TLoc) =
  # careful  'addr(myptrToArray)' needs to get the ampersand:
  if e[0].typ.skipTypes(abstractInstOwned).kind in {tyRef, tyPtr}:
    var a: TLoc = initLocExpr(p, e[0])
    putIntoDest(p, d, e, cAddr(a.snippet), a.storage)
    #Message(e.info, warnUser, "HERE NEW &")
  elif mapType(p.config, e[0].typ, mapTypeChooser(e[0]) == skParam) == ctArray or isCppRef(p, e.typ):
    expr(p, e[0], d)
    # bug #19497
    d.lode = e
  else:
    var a: TLoc = initLocExpr(p, e[0])
    putIntoDest(p, d, e, addrLoc(p.config, a), a.storage)

template inheritLocation(d: var TLoc, a: TLoc) =
  if d.k == locNone: d.storage = a.storage

proc genRecordFieldAux(p: BProc, e: PNode, d: var TLoc, a: var TLoc) =
  a = initLocExpr(p, e[0])
  if e[1].kind != nkSym: internalError(p.config, e.info, "genRecordFieldAux")
  d.inheritLocation(a)
  discard getTypeDesc(p.module, a.t) # fill the record's fields.loc

proc genTupleElem(p: BProc, e: PNode, d: var TLoc) =
  var
    i: int = 0
  var a: TLoc = initLocExpr(p, e[0])
  let tupType = a.t.skipTypes(abstractInst+{tyVar})
  assert tupType.kind == tyTuple
  d.inheritLocation(a)
  discard getTypeDesc(p.module, a.t) # fill the record's fields.loc
  var r = rdLoc(a)
  case e[1].kind
  of nkIntLit..nkUInt64Lit: i = int(e[1].intVal)
  else: internalError(p.config, e.info, "genTupleElem")
  r = dotField(r, "Field" & $i)
  putIntoDest(p, d, e, r, a.storage)

proc lookupFieldAgain(p: BProc, ty: PType; field: PSym; r: var Rope;
                      resTyp: ptr PType = nil): PSym =
  result = nil
  var ty = ty
  assert r != ""
  while ty != nil:
    ty = ty.skipTypes(skipPtrs)
    assert(ty.kind in {tyTuple, tyObject})
    result = lookupInRecord(ty.n, field.name)
    if result != nil:
      if resTyp != nil: resTyp[] = ty
      break
    if not p.module.compileToCpp:
      r = dotField(r, "Sup")
    ty = ty[0]
  if result == nil: internalError(p.config, field.info, "genCheckedRecordField")

proc genRecordField(p: BProc, e: PNode, d: var TLoc) =
  var a: TLoc = default(TLoc)
  if p.module.compileToCpp and e.kind == nkDotExpr and e[1].kind == nkSym and e[1].typ.kind == tyPtr:
    # special case for C++: we need to pull the type of the field as member and friends require the complete type.
    let typ = e[1].typ.elementType
    if typ.itemId in p.module.g.graph.memberProcsPerType:
      discard getTypeDesc(p.module, typ)

  genRecordFieldAux(p, e, d, a)
  var r = rdLoc(a)
  var f = e[1].sym
  let ty = skipTypes(a.t, abstractInstOwned + tyUserTypeClasses)
  if ty.kind == tyTuple:
    # we found a unique tuple type which lacks field information
    # so we use Field$i
    r = dotField(r, "Field" & $f.position)
    putIntoDest(p, d, e, r, a.storage)
  else:
    var rtyp: PType = nil
    let field = lookupFieldAgain(p, ty, f, r, addr rtyp)
    if field.loc.snippet == "" and rtyp != nil: fillObjectFields(p.module, rtyp)
    if field.loc.snippet == "": internalError(p.config, e.info, "genRecordField 3 " & typeToString(ty))
    r = dotField(r, field.loc.snippet)
    putIntoDest(p, d, e, r, a.storage)
  r.freeze

proc genInExprAux(p: BProc, e: PNode, a, b, d: var TLoc)

proc genFieldCheck(p: BProc, e: PNode, obj: Rope, field: PSym) =
  var test, u, v: TLoc
  for i in 1..<e.len:
    var it = e[i]
    assert(it.kind in nkCallKinds)
    assert(it[0].kind == nkSym)
    let op = it[0].sym
    if op.magic == mNot: it = it[1]
    let disc = it[2].skipConv
    assert(disc.kind == nkSym)
    test = initLoc(locNone, it, OnStack)
    u = initLocExpr(p, it[1])
    v = initLoc(locExpr, disc, OnUnknown)
    v.snippet = dotField(obj, disc.sym.loc.snippet)
    genInExprAux(p, it, u, v, test)
    var msg = ""
    if optDeclaredLocs in p.config.globalOptions:
      # xxx this should be controlled by a separate flag, and
      # used for other similar defects so that location information is shown
      # even without the expensive `--stacktrace`; binary size could be optimized
      # by encoding the file names separately from `file(line:col)`, essentially
      # passing around `TLineInfo` + the set of files in the project.
      msg.add toFileLineCol(p.config, e.info) & " "
    msg.add genFieldDefect(p.config, field.name.s, disc.sym)
    var strLitBuilder = newBuilder("")
    genStringLiteral(p.module, newStrNode(nkStrLit, msg), strLitBuilder)
    let strLit = extract(strLitBuilder)

    ## discriminant check
    let rt = rdLoc(test)
    let cond = if op.magic == mNot: rt else: cOp(Not, rt)
    p.s(cpsStmts).addSingleIfStmt(cond):
      ## call raiseFieldError2 on failure
      var discIndex = newRopeAppender()
      rdSetElemLoc(p.config, v, u.t, discIndex)
      if optTinyRtti in p.config.globalOptions:
        let base = disc.typ.skipTypes(abstractInst+{tyRange})
        case base.kind
        of tyEnum:
          let toStrProc = getToStringProc(p.module.g.graph, base)
          # XXX need to modify this logic for IC.
          # need to analyze nkFieldCheckedExpr and marks procs "used" like range checks in dce
          var toStr: TLoc = default(TLoc)
          expr(p, newSymNode(toStrProc), toStr)
          let rToStr = rdLoc(toStr)
          let rv = rdLoc(v)
          var raiseCall: CallBuilder
          p.s(cpsStmts).addStmt():
            p.s(cpsStmts).addCall(raiseCall, cgsymValue(p.module, "raiseFieldErrorStr")):
              p.s(cpsStmts).addArgument(raiseCall):
                p.s(cpsStmts).add(strLit)
              p.s(cpsStmts).addArgument(raiseCall):
                p.s(cpsStmts).addCall(rToStr, rv)
        else:
          p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "raiseFieldError2"),
            strLit,
            cCast("NI", discIndex))

      else:
        # complication needed for signed types
        let first = p.config.firstOrd(disc.sym.typ)
        let firstLit = cInt64Literal(cast[int](first))
        let discName = genTypeInfo(p.config, p.module, disc.sym.typ, e.info)
        var raiseCall: CallBuilder
        p.s(cpsStmts).addStmt():
          p.s(cpsStmts).addCall(raiseCall, cgsymValue(p.module, "raiseFieldError2")):
            p.s(cpsStmts).addArgument(raiseCall):
              p.s(cpsStmts).add(strLit)
            p.s(cpsStmts).addArgument(raiseCall):
              p.s(cpsStmts).addCall(cgsymValue(p.module, "reprDiscriminant"),
                cOp(Add, "NI", cCast("NI", discIndex), cCast("NI", firstLit)),
                discName)

      raiseInstr(p, p.s(cpsStmts))

proc genCheckedRecordField(p: BProc, e: PNode, d: var TLoc) =
  assert e[0].kind == nkDotExpr
  if optFieldCheck in p.options:
    var a: TLoc = default(TLoc)
    genRecordFieldAux(p, e[0], d, a)
    let ty = skipTypes(a.t, abstractInst + tyUserTypeClasses)
    var r = rdLoc(a)
    let f = e[0][1].sym
    let field = lookupFieldAgain(p, ty, f, r)
    if field.loc.snippet == "": fillObjectFields(p.module, ty)
    if field.loc.snippet == "":
      internalError(p.config, e.info, "genCheckedRecordField") # generate the checks:
    genFieldCheck(p, e, r, field)
    r = dotField(r, field.loc.snippet)
    putIntoDest(p, d, e[0], r, a.storage)
    r.freeze
  else:
    genRecordField(p, e[0], d)

proc genUncheckedArrayElem(p: BProc, n, x, y: PNode, d: var TLoc) =
  var a = initLocExpr(p, x)
  var b = initLocExpr(p, y)
  d.inheritLocation(a)
  putIntoDest(p, d, n, subscript(rdLoc(a), rdCharLoc(b)),
              a.storage)

proc genArrayElem(p: BProc, n, x, y: PNode, d: var TLoc) =
  var a = initLocExpr(p, x)
  var b = initLocExpr(p, y)
  var ty = skipTypes(a.t, abstractVarRange + abstractPtrs + tyUserTypeClasses)
  let first = cIntLiteral(firstOrd(p.config, ty))
  # emit range check:
  if optBoundsCheck in p.options and ty.kind != tyUncheckedArray:
    if not isConstExpr(y):
      # semantic pass has already checked for const index expressions
      if firstOrd(p.config, ty) == 0 and lastOrd(p.config, ty) >= 0:
        if (firstOrd(p.config, b.t) < firstOrd(p.config, ty)) or (lastOrd(p.config, b.t) > lastOrd(p.config, ty)):
          let last = cIntLiteral(lastOrd(p.config, ty))
          let rcb = rdCharLoc(b)
          p.s(cpsStmts).addSingleIfStmt(
              cOp(GreaterThan, cCast("NU", rcb), cCast("NU", last))):
            p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "raiseIndexError2"),
              rcb,
              last)
            raiseInstr(p, p.s(cpsStmts))
      else:
        let last = cIntLiteral(lastOrd(p.config, ty))
        let rcb = rdCharLoc(b)
        p.s(cpsStmts).addSingleIfStmt(
            cOp(Or, cOp(LessThan, rcb, first), cOp(GreaterThan, rcb, last))):
          p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "raiseIndexError3"),
            rcb,
            first,
            last)
          raiseInstr(p, p.s(cpsStmts))

    else:
      let idx = getOrdValue(y)
      if idx < firstOrd(p.config, ty) or idx > lastOrd(p.config, ty):
        localError(p.config, x.info, formatErrorIndexBound(idx, firstOrd(p.config, ty), lastOrd(p.config, ty)))
  d.inheritLocation(a)
  let ra = rdLoc(a)
  let rcb = rdCharLoc(b)
  putIntoDest(p, d, n, subscript(ra, cOp(Sub, "NI", rcb, first)), a.storage)

proc genCStringElem(p: BProc, n, x, y: PNode, d: var TLoc) =
  var a = initLocExpr(p, x)
  var b = initLocExpr(p, y)
  inheritLocation(d, a)
  let ra = rdLoc(a)
  let rcb = rdLoc(b)
  putIntoDest(p, d, n, subscript(ra, rcb), a.storage)

proc genBoundsCheck(p: BProc; arr, a, b: TLoc; arrTyp: PType) =
  let ty = arrTyp
  case ty.kind
  of tyOpenArray, tyVarargs:
    let ra = rdLoc(a)
    let rb = rdLoc(b)
    let rarr = rdLoc(arr)
    let arrlen =
      if reifiedOpenArray(arr.lode):
        dotField(rarr, "Field1")
      else:
        rarr & "Len_0"
    p.s(cpsStmts).addSingleIfStmt(cOp(And,
      cOp(NotEqual, cOp(Sub, "NI", rb, ra), cIntValue(-1)),
      cOp(Or,
        cOp(Or, cOp(LessThan, ra, cIntValue(0)), cOp(GreaterEqual, ra, arrlen)),
        cOp(Or, cOp(LessThan, rb, cIntValue(0)), cOp(GreaterEqual, rb, arrlen))))):
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "raiseIndexError4"),
        ra, rb, arrlen)
      raiseInstr(p, p.s(cpsStmts))

  of tyArray:
    let first = cIntLiteral(firstOrd(p.config, ty))
    let last = cIntLiteral(lastOrd(p.config, ty))
    let rca = rdCharLoc(a)
    let rcb = rdCharLoc(b)
    p.s(cpsStmts).addSingleIfStmt(cOp(And,
      cOp(NotEqual, cOp(Sub, "NI", rcb, rca), cIntValue(-1)),
      cOp(Or,
        cOp(LessThan, cOp(Sub, "NI", rcb, rca), cIntValue(-1)),
        cOp(Or,
          cOp(Or, cOp(LessThan, rca, first), cOp(GreaterThan, rca, last)),
          cOp(Or, cOp(LessThan, rcb, first), cOp(GreaterThan, rcb, last)))))):
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "raiseIndexError"))
      raiseInstr(p, p.s(cpsStmts))

  of tySequence, tyString:
    let ra = rdLoc(a)
    let rb = rdLoc(b)
    let arrlen = lenExpr(p, arr)
    p.s(cpsStmts).addSingleIfStmt(cOp(And,
      cOp(NotEqual, cOp(Sub, "NI", rb, ra), cIntValue(-1)),
      cOp(Or,
        cOp(Or, cOp(LessThan, ra, cIntValue(0)), cOp(GreaterEqual, ra, arrlen)),
        cOp(Or, cOp(LessThan, rb, cIntValue(0)), cOp(GreaterEqual, rb, arrlen))))):
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "raiseIndexError4"),
        ra, rb, arrlen)
      raiseInstr(p, p.s(cpsStmts))

  else: discard

proc genOpenArrayElem(p: BProc, n, x, y: PNode, d: var TLoc) =
  var a = initLocExpr(p, x)
  var b = initLocExpr(p, y)
  let ra = rdLoc(a)
  let rcb = rdCharLoc(b)
  var arrData, arrLen: Snippet
  if not reifiedOpenArray(x):
    arrData = ra
    arrLen = ra & "Len_0"
  else:
    arrData = dotField(ra, "Field0")
    arrLen = dotField(ra, "Field1")

  # emit range check:
  if optBoundsCheck in p.options:
    p.s(cpsStmts).addSingleIfStmt(cOp(Or,
        cOp(LessThan, rcb, cIntValue(0)),
        cOp(GreaterEqual, rcb, arrLen))): # BUGFIX: ``>=`` and not ``>``!
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "raiseIndexError2"),
        rcb,
        cOp(Sub, "NI", arrLen, cIntValue(1)))
      raiseInstr(p, p.s(cpsStmts))

  inheritLocation(d, a)
  putIntoDest(p, d, n, subscript(arrData, rcb), a.storage)

proc genSeqElem(p: BProc, n, x, y: PNode, d: var TLoc) =
  var a = initLocExpr(p, x)
  var b = initLocExpr(p, y)
  var ty = skipTypes(a.t, abstractVarRange)
  if ty.kind in {tyRef, tyPtr}:
    ty = skipTypes(ty.elementType, abstractVarRange)
  let rcb = rdCharLoc(b)
  # emit range check:
  if optBoundsCheck in p.options:
    let arrLen = lenExpr(p, a)
    p.s(cpsStmts).addSingleIfStmt(cOp(Or,
        cOp(LessThan, rcb, cIntValue(0)),
        cOp(GreaterEqual, rcb, arrLen))):
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "raiseIndexError2"),
        rcb,
        cOp(Sub, "NI", arrLen, cIntValue(1)))
      raiseInstr(p, p.s(cpsStmts))

  if d.k == locNone: d.storage = OnHeap
  if skipTypes(a.t, abstractVar).kind in {tyRef, tyPtr}:
    a.snippet = cDeref(a.snippet)

  if lfPrepareForMutation in d.flags and ty.kind == tyString and
      optSeqDestructors in p.config.globalOptions:
    let bra = byRefLoc(p, a)
    p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "nimPrepareStrMutationV2"),
      bra)
  let ra = rdLoc(a)
  putIntoDest(p, d, n, subscript(dataField(p, ra), rcb), a.storage)

proc genBracketExpr(p: BProc; n: PNode; d: var TLoc) =
  var ty = skipTypes(n[0].typ, abstractVarRange + tyUserTypeClasses)
  if ty.kind in {tyRef, tyPtr}: ty = skipTypes(ty.elementType, abstractVarRange)
  case ty.kind
  of tyUncheckedArray: genUncheckedArrayElem(p, n, n[0], n[1], d)
  of tyArray: genArrayElem(p, n, n[0], n[1], d)
  of tyOpenArray, tyVarargs: genOpenArrayElem(p, n, n[0], n[1], d)
  of tySequence, tyString: genSeqElem(p, n, n[0], n[1], d)
  of tyCstring: genCStringElem(p, n, n[0], n[1], d)
  of tyTuple: genTupleElem(p, n, d)
  else: internalError(p.config, n.info, "expr(nkBracketExpr, " & $ty.kind & ')')
  discard getTypeDesc(p.module, n.typ)

proc isSimpleExpr(n: PNode): bool =
  # calls all the way down --> can stay expression based
  case n.kind
  of nkCallKinds, nkDotExpr, nkPar, nkTupleConstr,
      nkObjConstr, nkBracket, nkCurly, nkHiddenDeref, nkDerefExpr, nkHiddenAddr,
      nkHiddenStdConv, nkHiddenSubConv, nkConv, nkAddr:
    for c in n:
      if not isSimpleExpr(c): return false
    result = true
  of nkStmtListExpr:
    for i in 0..<n.len-1:
      if n[i].kind notin {nkCommentStmt, nkEmpty}: return false
    result = isSimpleExpr(n.lastSon)
  else:
    result = n.isAtom

proc genAndOr(p: BProc, e: PNode, d: var TLoc, m: TMagic) =
  # how to generate code?
  #  'expr1 and expr2' becomes:
  #     result = expr1
  #     fjmp result, end
  #     result = expr2
  #  end:
  #  ... (result computed)
  # BUGFIX:
  #   a = b or a
  # used to generate:
  # a = b
  # if a: goto end
  # a = a
  # end:
  # now it generates:
  # tmp = b
  # if tmp: goto end
  # tmp = a
  # end:
  # a = tmp
  when false:
    #if isSimpleExpr(e) and p.module.compileToCpp:
    #getTemp(p, e.typ, tmpA)
    #getTemp(p, e.typ, tmpB)
    var tmpA = initLocExprSingleUse(p, e[1])
    var tmpB = initLocExprSingleUse(p, e[2])
    tmpB.k = locExpr
    if m == mOr:
      tmpB.snippet = cOp(Or, rdLoc(tmpA), rdLoc(tmpB))
    else:
      tmpB.snippet = cOp(And, rdLoc(tmpA), rdLoc(tmpB))
    if d.k == locNone:
      d = tmpB
    else:
      genAssignment(p, d, tmpB, {})
  else:
    var
      L: TLabel
    var tmp: TLoc = getTemp(p, e.typ)      # force it into a temp!
    inc p.splitDecls
    expr(p, e[1], tmp)
    L = getLabel(p)
    let rtmp = rdLoc(tmp)
    let cond = if m == mOr: rtmp else: cOp(Not, rtmp)
    p.s(cpsStmts).addSingleIfStmt(cond):
      p.s(cpsStmts).addGoto(L)
    expr(p, e[2], tmp)
    fixLabel(p, L)
    if d.k == locNone:
      d = tmp
    else:
      genAssignment(p, d, tmp, {}) # no need for deep copying
    dec p.splitDecls

proc genEcho(p: BProc, n: PNode) =
  # this unusual way of implementing it ensures that e.g. ``echo("hallo", 45)``
  # is threadsafe.
  internalAssert p.config, n.kind == nkBracket
  if p.config.target.targetOS == osGenode:
    # echo directly to the Genode LOG session
    p.module.includeHeader("<base/log.h>")
    p.module.includeHeader("<util/string.h>")
    var a: TLoc
    let logName = "Genode::log"
    var logCall: CallBuilder
    p.s(cpsStmts).addStmt():
      p.s(cpsStmts).addCall(logCall, logName):
        for it in n.sons:
          if it.skipConv.kind == nkNilLit:
            p.s(cpsStmts).addArgument(logCall):
              p.s(cpsStmts).add("\"\"")
          elif n.len != 0:
            a = initLocExpr(p, it)
            let ra = a.rdLoc
            let fnName = "Genode::Cstring"
            p.s(cpsStmts).addArgument(logCall):
              case detectStrVersion(p.module)
              of 2:
                p.s(cpsStmts).addCall(fnName,
                  dotField(derefField(ra, "p"), "data"),
                  dotField(ra, "len"))
              else:
                p.s(cpsStmts).addCall(fnName,
                  derefField(ra, "data"),
                  derefField(ra, "len"))
  else:
    if n.len == 0:
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "echoBinSafe"),
        "NIM_NIL",
        cIntValue(n.len))
    else:
      var a: TLoc = initLocExpr(p, n)
      let ra = a.rdLoc
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "echoBinSafe"),
        ra,
        cIntValue(n.len))
    when false:
      p.module.includeHeader("<stdio.h>")
      linefmt(p, cpsStmts, "printf($1$2);$n",
              makeCString(repeat("%s", n.len) & "\L"), [args])
      linefmt(p, cpsStmts, "fflush(stdout);$n", [])

proc gcUsage(conf: ConfigRef; n: PNode) =
  if conf.selectedGC == gcNone: message(conf, n.info, warnGcMem, n.renderTree)

proc strLoc(p: BProc; d: TLoc): Rope =
  if optSeqDestructors in p.config.globalOptions:
    result = byRefLoc(p, d)
  else:
    result = rdLoc(d)

proc genStrConcat(p: BProc, e: PNode, d: var TLoc) =
  #   <Nim code>
  #   s = "Hello " & name & ", how do you feel?" & 'z'
  #
  #   <generated C code>
  #  {
  #    string tmp0;
  #    ...
  #    tmp0 = rawNewString(6 + 17 + 1 + s2->len);
  #    // we cannot generate s = rawNewString(...) here, because
  #    // ``s`` may be used on the right side of the expression
  #    appendString(tmp0, strlit_1);
  #    appendString(tmp0, name);
  #    appendString(tmp0, strlit_2);
  #    appendChar(tmp0, 'z');
  #    asgn(s, tmp0);
  #  }
  var a: TLoc
  var tmp: TLoc = getTemp(p, e.typ)
  var L = 0
  var appends: seq[Snippet] = @[]
  var lens: seq[Snippet] = @[]
  for i in 0..<e.len - 1:
    # compute the length expression:
    a = initLocExpr(p, e[i + 1])
    let rstmp = strLoc(p, tmp)
    let ra = rdLoc(a)
    if skipTypes(e[i + 1].typ, abstractVarRange).kind == tyChar:
      inc(L)
      appends.add(cgCall(p, "appendChar", rstmp, ra))
    else:
      if e[i + 1].kind in {nkStrLit..nkTripleStrLit}:
        inc(L, e[i + 1].strVal.len)
      else:
        lens.add(lenExpr(p, a))
      appends.add(cgCall(p, "appendString", rstmp, ra))
  var exprL = cIntValue(L)
  for len in lens:
    exprL = cOp(Add, "NI", exprL, len)
  p.s(cpsStmts).addAssignmentWithValue(tmp.snippet):
    p.s(cpsStmts).addCall(cgsymValue(p.module, "rawNewString"), exprL)
  for append in appends:
    p.s(cpsStmts).addStmt():
      p.s(cpsStmts).add(append)
  if d.k == locNone:
    d = tmp
  else:
    genAssignment(p, d, tmp, {}) # no need for deep copying
  gcUsage(p.config, e)

proc genStrAppend(p: BProc, e: PNode, d: var TLoc) =
  #  <Nim code>
  #  s &= "Hello " & name & ", how do you feel?" & 'z'
  #  // BUG: what if s is on the left side too?
  #  <generated C code>
  #  {
  #    s = resizeString(s, 6 + 17 + 1 + name->len);
  #    appendString(s, strlit_1);
  #    appendString(s, name);
  #    appendString(s, strlit_2);
  #    appendChar(s, 'z');
  #  }
  var
    a, call: TLoc
    appends: seq[Snippet] = @[]
  assert(d.k == locNone)
  var L = 0
  var lens: seq[Snippet] = @[]
  var dest = initLocExpr(p, e[1])
  let rsd = strLoc(p, dest)
  for i in 0..<e.len - 2:
    # compute the length expression:
    a = initLocExpr(p, e[i + 2])
    let ra = rdLoc(a)
    if skipTypes(e[i + 2].typ, abstractVarRange).kind == tyChar:
      inc(L)
      appends.add(cgCall(p, "appendChar", rsd, ra))
    else:
      if e[i + 2].kind in {nkStrLit..nkTripleStrLit}:
        inc(L, e[i + 2].strVal.len)
      else:
        lens.add(lenExpr(p, a))
      appends.add(cgCall(p, "appendString", rsd, ra))
  var exprL = cIntValue(L)
  for len in lens:
    exprL = cOp(Add, "NI", exprL, len)
  if optSeqDestructors in p.config.globalOptions:
    let brd = byRefLoc(p, dest)
    p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "prepareAdd"),
      brd,
      exprL)
  else:
    call = initLoc(locCall, e, OnHeap)
    let rd = rdLoc(dest)
    call.snippet = cgCall(p, "resizeString",
      rd,
      exprL)
    genAssignment(p, dest, call, {})
    gcUsage(p.config, e)
  for append in appends:
    p.s(cpsStmts).addStmt():
      p.s(cpsStmts).add(append)

proc genSeqElemAppend(p: BProc, e: PNode, d: var TLoc) =
  # seq &= x  -->
  #    seq = (typeof seq) incrSeq(&seq->Sup, sizeof(x));
  #    seq->data[seq->len-1] = x;
  var a = initLocExpr(p, e[1])
  var b = initLocExpr(p, e[2])
  let seqType = skipTypes(e[1].typ, {tyVar})
  var call = initLoc(locCall, e, OnHeap)
  let ra = rdLoc(a)
  call.snippet = cCast(getTypeDesc(p.module, e[1].typ),
    cgCall(p, "incrSeqV3",
      if not p.module.compileToCpp: cCast(ptrType("TGenericSeq"), ra) else: ra,
      genTypeInfoV1(p.module, seqType, e.info)))
  # emit the write barrier if required, but we can always move here, so
  # use 'genRefAssign' for the seq.
  genRefAssign(p, a, call)
  #if bt != b.t:
  #  echo "YES ", e.info, " new: ", typeToString(bt), " old: ", typeToString(b.t)
  var dest = initLoc(locExpr, e[2], OnHeap)
  var tmpL = getIntTemp(p)
  p.s(cpsStmts).addAssignment(tmpL.snippet, lenField(p, ra))
  p.s(cpsStmts).addIncr(lenField(p, ra))
  dest.snippet = subscript(dataField(p, ra), tmpL.snippet)
  genAssignment(p, dest, b, {needToCopy})
  gcUsage(p.config, e)

proc genDefault(p: BProc; n: PNode; d: var TLoc) =
  if d.k == locNone: d = getTemp(p, n.typ, needsInit=true)
  else: resetLoc(p, d)

proc rawGenNew(p: BProc, a: var TLoc, sizeExpr: Rope; needsInit: bool) =
  var sizeExpr = sizeExpr
  let typ = a.t
  var b: TLoc = initLoc(locExpr, a.lode, OnHeap)
  let refType = typ.skipTypes(abstractInstOwned)
  assert refType.kind == tyRef
  let bt = refType.elementType
  if sizeExpr == "":
    sizeExpr = cSizeof(getTypeDesc(p.module, bt))

  if optTinyRtti in p.config.globalOptions:
    let fnName = cgsymValue(p.module, if needsInit: "nimNewObj" else: "nimNewObjUninit")
    b.snippet = cCast(getTypeDesc(p.module, typ),
      cCall(fnName,
        sizeExpr,
        cAlignof(getTypeDesc(p.module, bt))))
    genAssignment(p, a, b, {})
  else:
    let ti = genTypeInfoV1(p.module, typ, a.lode.info)
    let op = getAttachedOp(p.module.g.graph, bt, attachedDestructor)
    if op != nil and not isTrivialProc(p.module.g.graph, op):
      # the prototype of a destructor is ``=destroy(x: var T)`` and that of a
      # finalizer is: ``proc (x: ref T) {.nimcall.}``. We need to check the calling
      # convention at least:
      if op.typ == nil or op.typ.callConv != ccNimCall:
        localError(p.module.config, a.lode.info,
          "the destructor that is turned into a finalizer needs " &
          "to have the 'nimcall' calling convention")
      var f: TLoc = initLocExpr(p, newSymNode(op))
      let rf = rdLoc(f)
      p.module.s[cfsTypeInit3].addDerefFieldAssignment(ti, "finalizer",
        cCast("void*", rf))

    if a.storage == OnHeap and usesWriteBarrier(p.config):
      let unrefFnName = cgsymValue(p.module,
        if canFormAcycle(p.module.g.graph, a.t):
          "nimGCunrefRC1"
        else:
          "nimGCunrefNoCycle")
      let ra = a.rdLoc
      p.s(cpsStmts).addSingleIfStmt(ra):
        p.s(cpsStmts).addCallStmt(unrefFnName, ra)
        p.s(cpsStmts).addAssignment(ra, "NIM_NIL")
      if p.config.selectedGC == gcGo:
        # newObjRC1() would clash with unsureAsgnRef() - which is used by gcGo to
        # implement the write barrier
        b.snippet = cCast(getTypeDesc(p.module, typ),
          cgCall(p, "newObj",
            ti,
            sizeExpr))
        let raa = addrLoc(p.config, a)
        let rb = b.rdLoc
        p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "unsureAsgnRef"),
          cCast("void**", raa),
          rb)
      else:
        # use newObjRC1 as an optimization
        b.snippet = cCast(getTypeDesc(p.module, typ),
          cgCall(p, "newObjRC1",
            ti,
            sizeExpr))
        let ra = a.rdLoc
        let rb = b.rdLoc
        p.s(cpsStmts).addAssignment(ra, rb)
    else:
      b.snippet = cCast(getTypeDesc(p.module, typ),
        cgCall(p, "newObj",
          ti,
          sizeExpr))
      genAssignment(p, a, b, {})
  # set the object type:
  genObjectInit(p, cpsStmts, bt, a, constructRefObj)

proc genNew(p: BProc, e: PNode) =
  var a: TLoc = initLocExpr(p, e[1])
  # 'genNew' also handles 'unsafeNew':
  if e.len == 3:
    var se: TLoc = initLocExpr(p, e[2])
    rawGenNew(p, a, se.rdLoc, needsInit = true)
  else:
    rawGenNew(p, a, "", needsInit = true)
  gcUsage(p.config, e)

proc genNewSeqAux(p: BProc, dest: TLoc, length: Rope; lenIsZero: bool) =
  let seqtype = skipTypes(dest.t, abstractVarRange)
  var call: TLoc = initLoc(locExpr, dest.lode, OnHeap)
  if dest.storage == OnHeap and usesWriteBarrier(p.config):
    let unrefFnName = cgsymValue(p.module,
      if canFormAcycle(p.module.g.graph, dest.t):
        "nimGCunrefRC1"
      else:
        "nimGCunrefNoCycle")
    let rd = dest.rdLoc
    p.s(cpsStmts).addSingleIfStmt(rd):
      p.s(cpsStmts).addCallStmt(unrefFnName, rd)
      p.s(cpsStmts).addAssignment(rd, "NIM_NIL")
    if not lenIsZero:
      let st = getTypeDesc(p.module, seqtype)
      let typinfo = genTypeInfoV1(p.module, seqtype, dest.lode.info)
      if p.config.selectedGC == gcGo:
        # we need the write barrier
        call.snippet = cCast(st,
          cgCall(p, "newSeq", typinfo, length))
        let rad = addrLoc(p.config, dest)
        let rc = call.rdLoc
        p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "unsureAsgnRef"),
          cCast("void**", rad),
          rc)
      else:
        call.snippet = cCast(st,
          cgCall(p, "newSeqRC1", typinfo, length))
        let rd = dest.rdLoc
        let rc = call.rdLoc
        p.s(cpsStmts).addAssignment(rd, rc)
  else:
    if lenIsZero:
      call.snippet = rope"NIM_NIL"
    else:
      let st = getTypeDesc(p.module, seqtype)
      let typinfo = genTypeInfoV1(p.module, seqtype, dest.lode.info)
      call.snippet = cCast(st,
        cgCall(p, "newSeq", typinfo, length))
    genAssignment(p, dest, call, {})

proc genNewSeq(p: BProc, e: PNode) =
  var a = initLocExpr(p, e[1])
  var b = initLocExpr(p, e[2])
  if optSeqDestructors in p.config.globalOptions:
    let seqtype = skipTypes(e[1].typ, abstractVarRange)
    let ra = a.rdLoc
    let rb = b.rdLoc
    let et = getTypeDesc(p.module, seqtype.elementType)
    let pt = getSeqPayloadType(p.module, seqtype)
    p.s(cpsStmts).addFieldAssignment(ra, "len", rb)
    p.s(cpsStmts).addFieldAssignmentWithValue(ra, "p"):
      p.s(cpsStmts).addCast(ptrType(pt)):
        p.s(cpsStmts).addCall(cgsymValue(p.module, "newSeqPayload"),
          rb,
          cSizeof(et),
          cAlignof(et))
  else:
    let lenIsZero = e[2].kind == nkIntLit and e[2].intVal == 0
    genNewSeqAux(p, a, b.rdLoc, lenIsZero)
    gcUsage(p.config, e)

proc genNewSeqOfCap(p: BProc; e: PNode; d: var TLoc) =
  let seqtype = skipTypes(e.typ, abstractVarRange)
  var a: TLoc = initLocExpr(p, e[1])
  if optSeqDestructors in p.config.globalOptions:
    if d.k == locNone: d = getTemp(p, e.typ, needsInit=false)
    let rd = d.rdLoc
    let ra = a.rdLoc
    let et = getTypeDesc(p.module, seqtype.elementType)
    let pt = getSeqPayloadType(p.module, seqtype)
    p.s(cpsStmts).addFieldAssignment(rd, "len", cIntValue(0))
    p.s(cpsStmts).addFieldAssignmentWithValue(rd, "p"):
      p.s(cpsStmts).addCast(ptrType(pt)):
        p.s(cpsStmts).addCall(cgsymValue(p.module, "newSeqPayloadUninit"),
          ra,
          cSizeof(et),
          cAlignof(et))
  else:
    if d.k == locNone: d = getTemp(p, e.typ, needsInit=false) # bug #22560
    let ra = a.rdLoc
    let dres = cCast(getTypeDesc(p.module, seqtype),
      cgCall(p, "nimNewSeqOfCap",
        genTypeInfoV1(p.module, seqtype, e.info),
        ra))
    putIntoDest(p, d, e, dres)
    gcUsage(p.config, e)

proc rawConstExpr(p: BProc, n: PNode; d: var TLoc) =
  let t = n.typ
  discard getTypeDesc(p.module, t) # so that any fields are initialized
  let id = nodeTableTestOrSet(p.module.dataCache, n, p.module.labels)
  fillLoc(d, locData, n, p.module.tmpBase & rope(id), OnStatic)
  if id == p.module.labels:
    # expression not found in the cache:
    inc(p.module.labels)
    let td = getTypeDesc(p.module, t)
    var data = newBuilder("")
    data.addVarWithInitializer(kind = Const, name = d.snippet, typ = td):
      # bug #23627; when generating const object fields, it's likely that
      # we need to generate type infos for the object, which may be an object with
      # custom hooks. We need to generate potential consts in the hooks first.
      genBracedInit(p, n, isConst = true, t, data)
    p.module.s[cfsData].add(extract(data))

proc handleConstExpr(p: BProc, n: PNode, d: var TLoc): bool =
  if d.k == locNone and n.len > ord(n.kind == nkObjConstr) and n.isDeepConstExpr:
    rawConstExpr(p, n, d)
    result = true
  else:
    result = false


proc genFieldObjConstr(p: BProc; ty: PType; useTemp, isRef: bool; nField, val, check: PNode; d: var TLoc; r: Rope; info: TLineInfo) =
  var tmp2 = TLoc(snippet: r)
  let field = lookupFieldAgain(p, ty, nField.sym, tmp2.snippet)
  if field.loc.snippet == "": fillObjectFields(p.module, ty)
  if field.loc.snippet == "": internalError(p.config, info, "genFieldObjConstr")
  if check != nil and optFieldCheck in p.options:
    genFieldCheck(p, check, r, field)
  tmp2.snippet = dotField(tmp2.snippet, field.loc.snippet)
  if useTemp:
    tmp2.k = locTemp
    tmp2.storage = if isRef: OnHeap else: OnStack
  else:
    tmp2.k = d.k
    tmp2.storage = if isRef: OnHeap else: d.storage
  tmp2.lode = val
  if nField.typ.skipTypes(abstractVar).kind in {tyOpenArray, tyVarargs}:
    var tmp3 = getTemp(p, val.typ)
    expr(p, val, tmp3)
    genOpenArrayConv(p, tmp2, tmp3, {})
  else:
    expr(p, val, tmp2)

proc genObjConstr(p: BProc, e: PNode, d: var TLoc) =
  # inheritance in C++ does not allow struct initialization so
  # we skip this step here:
  if not p.module.compileToCpp and optSeqDestructors notin p.config.globalOptions:
    # disabled optimization: it is wrong for C++ and now also
    # causes trouble for --gc:arc, see bug #13240
    #[
      var box: seq[Thing]
      for i in 0..3:
        box.add Thing(s1: "121") # pass by sink can mutate Thing.
    ]#
    if handleConstExpr(p, e, d): return
  var t = e.typ.skipTypes(abstractInstOwned)
  let isRef = t.kind == tyRef

  # check if we need to construct the object in a temporary
  var useTemp =
        isRef or
        (d.k notin {locTemp,locLocalVar,locGlobalVar,locParam,locField}) or
        (isPartOf(d.lode, e) != arNo)

  var tmp: TLoc = default(TLoc)
  var r: Rope
  let needsZeroMem = p.config.selectedGC notin {gcArc, gcAtomicArc, gcOrc} or nfAllFieldsSet notin e.flags
  if useTemp:
    tmp = getTemp(p, t)
    r = rdLoc(tmp)
    if isRef:
      rawGenNew(p, tmp, "", needsInit = nfAllFieldsSet notin e.flags)
      t = t.elementType.skipTypes(abstractInstOwned)
      r = cDeref(r)
      gcUsage(p.config, e)
    elif needsZeroMem:
      constructLoc(p, tmp)
    else:
      genObjectInit(p, cpsStmts, t, tmp, constructObj)
  else:
    if needsZeroMem: resetLoc(p, d)
    else: genObjectInit(p, cpsStmts, d.t, d, if isRef: constructRefObj else: constructObj)
    r = rdLoc(d)
  discard getTypeDesc(p.module, t)
  let ty = getUniqueType(t)
  for i in 1..<e.len:
    if nfPreventCg in e[i].flags:
      # this is an object constructor node generated by the VM and
      # this field is in an inactive case branch, don't generate assignment
      continue
    var check: PNode = nil
    if e[i].len == 3 and optFieldCheck in p.options:
      check = e[i][2]
    genFieldObjConstr(p, ty, useTemp, isRef, e[i][0], e[i][1], check, d, r, e.info)

  if useTemp:
    if d.k == locNone:
      d = tmp
    else:
      genAssignment(p, d, tmp, {})

proc lhsDoesAlias(a, b: PNode): bool =
  result = false
  for y in b:
    if isPartOf(a, y) != arNo: return true

proc genSeqConstr(p: BProc, n: PNode, d: var TLoc) =
  var arr: TLoc
  var tmp: TLoc = default(TLoc)
  # bug #668
  let doesAlias = lhsDoesAlias(d.lode, n)
  let dest = if doesAlias: addr(tmp) else: addr(d)
  if doesAlias:
    tmp = getTemp(p, n.typ)
  elif d.k == locNone:
    d = getTemp(p, n.typ)

  let lit = cIntLiteral(n.len)
  if optSeqDestructors in p.config.globalOptions:
    let seqtype = n.typ
    let rd = rdLoc dest[]
    let et = getTypeDesc(p.module, seqtype.elementType)
    let pt = getSeqPayloadType(p.module, seqtype)
    p.s(cpsStmts).addFieldAssignment(rd, "len", lit)
    p.s(cpsStmts).addFieldAssignmentWithValue(rd, "p"):
      p.s(cpsStmts).addCast(ptrType(pt)):
        p.s(cpsStmts).addCall(cgsymValue(p.module, "newSeqPayload"),
          lit,
          cSizeof(et),
          cAlignof(et))
  else:
    # generate call to newSeq before adding the elements per hand:
    genNewSeqAux(p, dest[], lit, n.len == 0)
  for i in 0..<n.len:
    arr = initLoc(locExpr, n[i], OnHeap)
    let lit = cIntLiteral(i)
    let rd = rdLoc dest[]
    arr.snippet = subscript(dataField(p, rd), lit)
    arr.storage = OnHeap            # we know that sequences are on the heap
    expr(p, n[i], arr)
  gcUsage(p.config, n)
  if doesAlias:
    if d.k == locNone:
      d = tmp
    else:
      genAssignment(p, d, tmp, {})

proc genArrToSeq(p: BProc, n: PNode, d: var TLoc) =
  var elem, arr: TLoc
  if n[1].kind == nkBracket:
    n[1].typ() = n.typ
    genSeqConstr(p, n[1], d)
    return
  if d.k == locNone:
    d = getTemp(p, n.typ)
  var a = initLocExpr(p, n[1])
  # generate call to newSeq before adding the elements per hand:
  let L = toInt(lengthOrd(p.config, n[1].typ))
  if optSeqDestructors in p.config.globalOptions:
    let seqtype = n.typ
    let rd = rdLoc d
    let valL = cIntValue(L)
    let et = getTypeDesc(p.module, seqtype.elementType)
    let pt = getSeqPayloadType(p.module, seqtype)
    p.s(cpsStmts).addFieldAssignment(rd, "len", valL)
    p.s(cpsStmts).addFieldAssignmentWithValue(rd, "p"):
      p.s(cpsStmts).addCast(ptrType(pt)):
        p.s(cpsStmts).addCall(cgsymValue(p.module, "newSeqPayload"),
          valL,
          cSizeof(et),
          cAlignof(et))
  else:
    let lit = cIntLiteral(L)
    genNewSeqAux(p, d, lit, L == 0)
  # bug #5007; do not produce excessive C source code:
  if L < 10:
    for i in 0..<L:
      elem = initLoc(locExpr, lodeTyp elemType(skipTypes(n.typ, abstractInst)), OnHeap)
      let lit = cIntLiteral(i)
      elem.snippet = subscript(dataField(p, rdLoc(d)), lit)
      elem.storage = OnHeap # we know that sequences are on the heap
      arr = initLoc(locExpr, lodeTyp elemType(skipTypes(n[1].typ, abstractInst)), a.storage)
      arr.snippet = subscript(rdLoc(a), lit)
      genAssignment(p, elem, arr, {needToCopy})
  else:
    var i: TLoc = getTemp(p, getSysType(p.module.g.graph, unknownLineInfo, tyInt))
    p.s(cpsStmts).addForRangeExclusive(i.snippet, cIntValue(0), cIntValue(L)):
      elem = initLoc(locExpr, lodeTyp elemType(skipTypes(n.typ, abstractInst)), OnHeap)
      elem.snippet = subscript(dataField(p, rdLoc(d)), rdLoc(i))
      elem.storage = OnHeap # we know that sequences are on the heap
      arr = initLoc(locExpr, lodeTyp elemType(skipTypes(n[1].typ, abstractInst)), a.storage)
      arr.snippet = subscript(rdLoc(a), rdLoc(i))
      genAssignment(p, elem, arr, {needToCopy})


proc genNewFinalize(p: BProc, e: PNode) =
  var
    b: TLoc
    refType, bt: PType
    ti: Rope
  refType = skipTypes(e[1].typ, abstractVarRange)
  var a = initLocExpr(p, e[1])
  var f = initLocExpr(p, e[2])
  b = initLoc(locExpr, a.lode, OnHeap)
  ti = genTypeInfo(p.config, p.module, refType, e.info)
  p.module.s[cfsTypeInit3].addDerefFieldAssignment(ti, "finalizer", cCast("void*", rdLoc(f)))
  b.snippet = cCast(getTypeDesc(p.module, refType),
    cgCall(p, "newObj",
      ti,
      cSizeof(getTypeDesc(p.module, skipTypes(refType.elementType, abstractRange)))))
  genAssignment(p, a, b, {})  # set the object type:
  bt = skipTypes(refType.elementType, abstractRange)
  genObjectInit(p, cpsStmts, bt, a, constructRefObj)
  gcUsage(p.config, e)

proc genOfHelper(p: BProc; dest: PType; a: Rope; info: TLineInfo; result: var Builder) =
  if optTinyRtti in p.config.globalOptions:
    let token = $genDisplayElem(MD5Digest(hashType(dest, p.config)))
    result.addCall(cgsymValue(p.module, "isObjDisplayCheck"),
      dotField(a, "m_type"),
      cIntValue(int(getObjDepth(dest))),
      token)
  else:
    # unfortunately 'genTypeInfoV1' sets tfObjHasKids as a side effect, so we
    # have to call it here first:
    let ti = genTypeInfoV1(p.module, dest, info)
    if tfFinal in dest.flags or (objHasKidsValid in p.module.flags and
                                tfObjHasKids notin dest.flags):
      result.addOp(Equal, dotField(a, "m_type"), ti)
    else:
      cgsym(p.module, "TNimType")
      inc p.module.labels
      let cache = "Nim_OfCheck_CACHE" & p.module.labels.rope
      p.module.s[cfsVars].addArrayVar(kind = Global,
        name = cache,
        elementType = ptrType("TNimType"),
        len = 2)
      result.addCall(cgsymValue(p.module, "isObjWithCache"),
        dotField(a, "m_type"),
        ti,
        cache)

proc genOf(p: BProc, x: PNode, typ: PType, d: var TLoc) =
  var a: TLoc = initLocExpr(p, x)
  var dest = skipTypes(typ, typedescPtrs)
  var r = rdLoc(a)
  var nilCheck: Rope = ""
  var t = skipTypes(a.t, abstractInstOwned)
  while t.kind in {tyVar, tyLent, tyPtr, tyRef}:
    if t.kind notin {tyVar, tyLent}: nilCheck = r
    if t.kind notin {tyVar, tyLent} or not p.module.compileToCpp:
      r = cDeref(r)
    t = skipTypes(t.elementType, typedescInst+{tyOwned})
  discard getTypeDesc(p.module, t)
  if not p.module.compileToCpp:
    while t.kind == tyObject and t.baseClass != nil:
      r = dotField(r, "Sup")
      t = skipTypes(t.baseClass, skipPtrs)
  if isObjLackingTypeField(t):
    globalError(p.config, x.info,
      "no 'of' operator available for pure objects")

  var ro = newBuilder("")
  genOfHelper(p, dest, r, x.info, ro)
  var ofExpr = extract(ro)
  if nilCheck != "":
    ofExpr = cOp(And, nilCheck, ofExpr)

  putIntoDest(p, d, x, ofExpr, a.storage)

proc genOf(p: BProc, n: PNode, d: var TLoc) =
  genOf(p, n[1], n[2].typ, d)

proc genRepr(p: BProc, e: PNode, d: var TLoc) =
  if optTinyRtti in p.config.globalOptions:
    localError(p.config, e.info, "'repr' is not available for --newruntime")
  var a: TLoc = initLocExpr(p, e[1])
  var t = skipTypes(e[1].typ, abstractVarRange)
  template cgCall(name: string, args: varargs[untyped]): untyped =
    cCall(cgsymValue(p.module, name), args)
  case t.kind
  of tyInt..tyInt64, tyUInt..tyUInt64:
    let ra = rdLoc(a)
    putIntoDest(p, d, e, cgCall("reprInt", cCast("NI64", ra)), a.storage)
  of tyFloat..tyFloat128:
    let ra = rdLoc(a)
    putIntoDest(p, d, e, cgCall("reprFloat", ra), a.storage)
  of tyBool:
    let ra = rdLoc(a)
    putIntoDest(p, d, e, cgCall("reprBool", ra), a.storage)
  of tyChar:
    let ra = rdLoc(a)
    putIntoDest(p, d, e, cgCall("reprChar", ra), a.storage)
  of tyEnum, tyOrdinal:
    let ra = rdLoc(a)
    let rti = genTypeInfoV1(p.module, t, e.info)
    putIntoDest(p, d, e, cgCall("reprEnum", cCast("NI", ra), rti), a.storage)
  of tyString:
    let ra = rdLoc(a)
    putIntoDest(p, d, e, cgCall("reprStr", ra), a.storage)
  of tySet:
    let raa = addrLoc(p.config, a)
    let rti = genTypeInfoV1(p.module, t, e.info)
    putIntoDest(p, d, e, cgCall("reprSet", raa, rti), a.storage)
  of tyOpenArray, tyVarargs:
    var b: TLoc = default(TLoc)
    case skipTypes(a.t, abstractVarRange).kind
    of tyOpenArray, tyVarargs:
      let ra = rdLoc(a)
      putIntoDest(p, b, e, ra & cArgumentSeparator & ra & "Len_0", a.storage)
    of tyString, tySequence:
      let ra = rdLoc(a)
      let la = lenExpr(p, a)
      putIntoDest(p, b, e,
        cIfExpr(dataFieldAccessor(p, ra), dataField(p, ra), "NIM_NIL") &
          cArgumentSeparator & la,
        a.storage)
    of tyArray:
      let ra = rdLoc(a)
      let la = cIntValue(lengthOrd(p.config, a.t))
      putIntoDest(p, b, e, ra & cArgumentSeparator & la, a.storage)
    else: internalError(p.config, e[0].info, "genRepr()")
    let rb = rdLoc(b)
    let rti = genTypeInfoV1(p.module, elemType(t), e.info)
    putIntoDest(p, d, e, cgCall("reprOpenArray", rb, rti), a.storage)
  of tyCstring, tyArray, tyRef, tyPtr, tyPointer, tyNil, tySequence:
    let ra = rdLoc(a)
    let rti = genTypeInfoV1(p.module, t, e.info)
    putIntoDest(p, d, e, cgCall("reprAny", ra, rti), a.storage)
  of tyEmpty, tyVoid:
    localError(p.config, e.info, "'repr' doesn't support 'void' type")
  else:
    let raa = addrLoc(p.config, a)
    let rti = genTypeInfoV1(p.module, t, e.info)
    putIntoDest(p, d, e, cgCall("reprAny", raa, rti), a.storage)
  gcUsage(p.config, e)

proc rdMType(p: BProc; a: TLoc; nilCheck: var Rope; result: var Snippet; enforceV1 = false) =
  var derefs = rdLoc(a)
  var t = skipTypes(a.t, abstractInst)
  while t.kind in {tyVar, tyLent, tyPtr, tyRef}:
    if t.kind notin {tyVar, tyLent}: nilCheck = derefs
    if t.kind notin {tyVar, tyLent} or not p.module.compileToCpp:
      derefs = cDeref(derefs)
    t = skipTypes(t.elementType, abstractInst)
  result.add derefs
  discard getTypeDesc(p.module, t)
  if not p.module.compileToCpp:
    while t.kind == tyObject and t.baseClass != nil:
      result = dotField(result, "Sup")
      t = skipTypes(t.baseClass, skipPtrs)
  result = dotField(result, "m_type")
  if optTinyRtti in p.config.globalOptions and enforceV1:
    result = derefField(result, "typeInfoV1")

proc genGetTypeInfo(p: BProc, e: PNode, d: var TLoc) =
  cgsym(p.module, "TNimType")
  let t = e[1].typ
  # ordinary static type information
  putIntoDest(p, d, e, genTypeInfoV1(p.module, t, e.info))

proc genGetTypeInfoV2(p: BProc, e: PNode, d: var TLoc) =
  let t = e[1].typ
  if isFinal(t) or e[0].sym.name.s != "getDynamicTypeInfo":
    # ordinary static type information
    putIntoDest(p, d, e, genTypeInfoV2(p.module, t, e.info))
  else:
    var a: TLoc = initLocExpr(p, e[1])
    var nilCheck = ""
    # use the dynamic type stored at offset 0:
    var rt: Snippet = ""
    rdMType(p, a, nilCheck, rt)
    putIntoDest(p, d, e, rt)

proc genAccessTypeField(p: BProc; e: PNode; d: var TLoc) =
  var a: TLoc = initLocExpr(p, e[1])
  var nilCheck = ""
  # use the dynamic type stored at offset 0:
  var rt: Snippet = ""
  rdMType(p, a, nilCheck, rt)
  putIntoDest(p, d, e, rt)

template genDollarIt(p: BProc, n: PNode, d: var TLoc, frmt: untyped) =
  block:
    var a: TLoc = initLocExpr(p, n[1])
    let it {.inject.} = rdLoc(a)
    a.snippet = frmt
    a.flags.excl lfIndirect # this flag should not be propagated here (not just for HCR)
    if d.k == locNone: d = getTemp(p, n.typ)
    genAssignment(p, d, a, {})
    gcUsage(p.config, n)

proc genArrayLen(p: BProc, e: PNode, d: var TLoc, op: TMagic) =
  var a = e[1]
  if a.kind == nkHiddenAddr: a = a[0]
  var typ = skipTypes(a.typ, abstractVar + tyUserTypeClasses)
  case typ.kind
  of tyOpenArray, tyVarargs:
    # Bug #9279, len(toOpenArray()) has to work:
    if a.kind in nkCallKinds and a[0].kind == nkSym and a[0].sym.magic == mSlice:
      # magic: pass slice to openArray:
      var m = initLocExpr(p, a[1])
      var b = initLocExpr(p, a[2])
      var c = initLocExpr(p, a[3])
      if optBoundsCheck in p.options:
        genBoundsCheck(p, m, b, c, skipTypes(m.t, abstractVarRange))
      if op == mHigh:
        putIntoDest(p, d, e, cOp(Sub, "NI", rdLoc(c), rdLoc(b)))
      else:
        putIntoDest(p, d, e, cOp(Add, "NI", cOp(Sub, "NI", rdLoc(c), rdLoc(b)), cIntValue(1)))
    else:
      if not reifiedOpenArray(a):
        if op == mHigh: unaryExpr(p, e, d, cOp(Sub, "NI", ra & "Len_0", cIntValue(1)))
        else: unaryExpr(p, e, d, ra & "Len_0")
      else:
        let isDeref = a.kind in {nkHiddenDeref, nkDerefExpr}
        template lenA: untyped =
          if isDeref:
            derefField(ra, "Field1")
          else:
            dotField(ra, "Field1")
        if op == mHigh:
          unaryExpr(p, e, d, cOp(Sub, "NI", lenA, cIntValue(1)))
        else:
          unaryExpr(p, e, d, lenA)
  of tyCstring:
    if op == mHigh:
      unaryExpr(p, e, d, cOp(Sub, "NI", cgCall(p, "nimCStrLen", ra), cIntValue(1)))
    else:
      unaryExpr(p, e, d, cgCall(p, "nimCStrLen", ra))
  of tyString:
    var a: TLoc = initLocExpr(p, e[1])
    var x = lenExpr(p, a)
    if op == mHigh: x = cOp(Sub, "NI", x, cIntValue(1))
    putIntoDest(p, d, e, x)
  of tySequence:
    # we go through a temporary here because people write bullshit code.
    var tmp: TLoc = getIntTemp(p)
    var a = initLocExpr(p, e[1])
    var x = lenExpr(p, a)
    if op == mHigh: x = cOp(Sub, "NI", x, cIntValue(1))
    p.s(cpsStmts).addAssignment(tmp.snippet, x)
    putIntoDest(p, d, e, tmp.snippet)
  of tyArray:
    # YYY: length(sideeffect) is optimized away incorrectly?
    if op == mHigh: putIntoDest(p, d, e, cIntValue(lastOrd(p.config, typ)))
    else: putIntoDest(p, d, e, cIntValue(lengthOrd(p.config, typ)))
  else: internalError(p.config, e.info, "genArrayLen()")

proc genSetLengthSeq(p: BProc, e: PNode, d: var TLoc) =
  if optSeqDestructors in p.config.globalOptions:
    e[1] = makeAddr(e[1], p.module.idgen)
    genCall(p, e, d)
    return
  assert(d.k == locNone)
  var x = e[1]
  if x.kind in {nkAddr, nkHiddenAddr}: x = x[0]
  var a = initLocExpr(p, x)
  var b = initLocExpr(p, e[2])
  let t = skipTypes(e[1].typ, {tyVar})

  var call = initLoc(locCall, e, OnHeap)
  let ra = rdLoc(a)
  let rb = rdLoc(b)
  let rt = getTypeDesc(p.module, t)
  let rti = genTypeInfoV1(p.module, t.skipTypes(abstractInst), e.info)
  var pExpr: Snippet
  if not p.module.compileToCpp:
    pExpr = cIfExpr(ra, cAddr(derefField(ra, "Sup")), "NIM_NIL")
  else:
    pExpr = ra
  call.snippet = cCast(rt, cgCall(p, "setLengthSeqV2", pExpr, rti, rb))

  genAssignment(p, a, call, {})
  gcUsage(p.config, e)

proc genSetLengthStr(p: BProc, e: PNode, d: var TLoc) =
  if optSeqDestructors in p.config.globalOptions:
    binaryStmtAddr(p, e, d, "setLengthStrV2")
  else:
    if d.k != locNone: internalError(p.config, e.info, "genSetLengthStr")
    var a = initLocExpr(p, e[1])
    var b = initLocExpr(p, e[2])

    var call = initLoc(locCall, e, OnHeap)
    call.snippet = cgCall(p, "setLengthStr", rdLoc(a), rdLoc(b))
    genAssignment(p, a, call, {})
    gcUsage(p.config, e)

proc genSwap(p: BProc, e: PNode, d: var TLoc) =
  # swap(a, b) -->
  # temp = a
  # a = b
  # b = temp
  cowBracket(p, e[1])
  cowBracket(p, e[2])
  var tmp: TLoc = getTemp(p, skipTypes(e[1].typ, abstractVar))
  var a = initLocExpr(p, e[1]) # eval a
  var b = initLocExpr(p, e[2]) # eval b
  genAssignment(p, tmp, a, {})
  genAssignment(p, a, b, {})
  genAssignment(p, b, tmp, {})

proc rdSetElemLoc(conf: ConfigRef; a: TLoc, typ: PType; result: var Snippet) =
  # read a location of an set element; it may need a subtraction operation
  # before the set operation
  result = rdCharLoc(a)
  let setType = typ.skipTypes(abstractPtrs)
  assert(setType.kind == tySet)
  if firstOrd(conf, setType) != 0:
    result = cOp(Sub, "NU", result, cIntValue(firstOrd(conf, setType)))

proc fewCmps(conf: ConfigRef; s: PNode): bool =
  # this function estimates whether it is better to emit code
  # for constructing the set or generating a bunch of comparisons directly
  if s.kind != nkCurly: return false
  if (getSize(conf, s.typ) <= conf.target.intSize) and (nfAllConst in s.flags):
    result = false            # it is better to emit the set generation code
  elif elemType(s.typ).kind in {tyInt, tyInt16..tyInt64}:
    result = true             # better not emit the set if int is basetype!
  else:
    result = s.len <= 8  # 8 seems to be a good value

template binaryExprIn(p: BProc, e: PNode, a, b, d: var TLoc, frmt: untyped) =
  var elem {.inject.}: Snippet = ""
  rdSetElemLoc(p.config, b, a.t, elem)
  let ra {.inject.} = rdLoc(a)
  putIntoDest(p, d, e, frmt)

proc genInExprAux(p: BProc, e: PNode, a, b, d: var TLoc) =
  let s = int(getSize(p.config, skipTypes(e[1].typ, abstractVar)))
  case s
  of 1, 2, 4, 8:
    let mask = s * 8 - 1
    let rt = "NU" & $(s * 8)
    binaryExprIn(p, e, a, b, d,
      # ((a & ((NU8) 1 << ((NU) elem & 7U))) != 0)
      # ((a & ((NU16) 1 << ((NU) elem & 15U))) != 0)
      # ((a & ((NU32) 1 << ((NU) elem & 31U))) != 0)
      # ((a & ((NU64) 1 << ((NU) elem & 63U))) != 0)
      cOp(NotEqual,
        cOp(BitAnd, rt, ra,
          cOp(Shl, rt, cCast(rt, cIntValue(1)),
            cOp(BitAnd, "NU", cCast("NU", elem), cUintValue(mask.uint)))),
        cIntValue(0)))
  else:
    # ((a[(NU)(elem)>>3] &(1U<<((NU)(elem)&7U)))!=0)
    binaryExprIn(p, e, a, b, d,
      cOp(NotEqual,
        cOp(BitAnd, "NU8",
          subscript(ra, cOp(Shr, "NU", cCast("NU", elem), cIntValue(3))),
          cOp(Shl, "NU8",
            cUintValue(1),
            cOp(BitAnd, "NU",
              cCast("NU", elem),
              cUintValue(7)))),
        cIntValue(0)))

template binaryStmtInExcl(p: BProc, e: PNode, d: var TLoc, frmt: untyped) =
  assert(d.k == locNone)
  var a = initLocExpr(p, e[1])
  var b = initLocExpr(p, e[2])
  var elem {.inject.}: Snippet = ""
  rdSetElemLoc(p.config, b, a.t, elem)
  let ra {.inject.} = rdLoc(a)
  p.s(cpsStmts).add(frmt)

proc genInOp(p: BProc, e: PNode, d: var TLoc) =
  var a, b, x, y: TLoc
  if (e[1].kind == nkCurly) and fewCmps(p.config, e[1]):
    # a set constructor but not a constant set:
    # do not emit the set, but generate a bunch of comparisons; and if we do
    # so, we skip the unnecessary range check: This is a semantical extension
    # that code now relies on. :-/ XXX
    let ea = if e[2].kind in {nkChckRange, nkChckRange64}:
               e[2][0]
             else:
               e[2]
    a = initLocExpr(p, ea)
    b = initLoc(locExpr, e, OnUnknown)
    if e[1].len > 0:
      var val: Snippet = ""
      for i in 0..<e[1].len:
        let it = e[1][i]
        var currentExpr: Snippet
        if it.kind == nkRange:
          x = initLocExpr(p, it[0])
          y = initLocExpr(p, it[1])
          let rca = rdCharLoc(a)
          let rcx = rdCharLoc(x)
          let rcy = rdCharLoc(y)
          currentExpr = cOp(And,
            cOp(GreaterEqual, rca, rcx),
            cOp(LessEqual, rca, rcy))
        else:
          x = initLocExpr(p, it)
          let rca = rdCharLoc(a)
          let rcx = rdCharLoc(x)
          currentExpr = cOp(Equal, rca, rcx)
        if val.len == 0:
          val = currentExpr
        else:
          val = cOp(Or, val, currentExpr)
      b.snippet = val
    else:
      # handle the case of an empty set
      b.snippet = cIntValue(0)
    putIntoDest(p, d, e, b.snippet)
  else:
    assert(e[1].typ != nil)
    assert(e[2].typ != nil)
    a = initLocExpr(p, e[1])
    b = initLocExpr(p, e[2])
    genInExprAux(p, e, a, b, d)

proc genSetOp(p: BProc, e: PNode, d: var TLoc, op: TMagic) =
  var a, b: TLoc
  var i: TLoc
  var setType = skipTypes(e[1].typ, abstractVar)
  var size = int(getSize(p.config, setType))
  case size
  of 1, 2, 4, 8:
    let bits = size * 8
    let rt = "NU" & $bits
    case op
    of mIncl:
      let mask = bits - 1
      binaryStmtInExcl(p, e, d,
        cInPlaceOp(BitOr, rt, ra,
          cOp(Shl, rt, cCast(rt, cIntValue(1)),
            cOp(BitAnd, "NU", elem, cIntValue(mask)))))
    of mExcl:
      let mask = bits - 1
      binaryStmtInExcl(p, e, d,
        cInPlaceOp(BitAnd, rt, ra, cOp(BitNot, rt,
          cOp(Shl, rt, cCast(rt, cIntValue(1)),
            cOp(BitAnd, "NU", elem, cIntValue(mask))))))
    of mCard:
      let name = if size <= 4: "countBits32" else: "countBits64"
      unaryExprChar(p, e, d, cgCall(p, name, ra))
    of mLtSet:
      binaryExprChar(p, e, d, cOp(And,
        cOp(Equal, cOp(BitAnd, rt, ra, cOp(BitNot, rt, rb)), cIntValue(0)),
        cOp(NotEqual, ra, rb)))
    of mLeSet:
      binaryExprChar(p, e, d,
        cOp(Equal, cOp(BitAnd, rt, ra, cOp(BitNot, rt, rb)), cIntValue(0)))
    of mEqSet: binaryExpr(p, e, d, cOp(Equal, ra, rb))
    of mMulSet: binaryExpr(p, e, d, cOp(BitAnd, rt, ra, rb))
    of mPlusSet: binaryExpr(p, e, d, cOp(BitOr, rt, ra, rb))
    of mMinusSet: binaryExpr(p, e, d, cOp(BitAnd, rt, ra, cOp(BitNot, rt, rb)))
    of mXorSet: binaryExpr(p, e, d, cOp(BitXor, rt, ra, rb))
    of mInSet:
      genInOp(p, e, d)
    else: internalError(p.config, e.info, "genSetOp()")
  else:
    case op
    of mIncl:
      binaryStmtInExcl(p, e, d, cInPlaceOp(BitOr, "NU8",
        subscript(ra, cOp(Shr, "NU", cCast("NU", elem), cIntValue(3))),
        cOp(Shl, "NU8", cUintValue(1), cOp(BitAnd, "NU", elem, cUintValue(7)))))
    of mExcl:
      binaryStmtInExcl(p, e, d, cInPlaceOp(BitAnd, "NU8",
        subscript(ra, cOp(Shr, "NU", cCast("NU", elem), cIntValue(3))),
        cOp(BitNot, "NU8",
          cOp(Shl, "NU8", cUintValue(1), cOp(BitAnd, "NU", elem, cUintValue(7))))))
    of mCard:
      var a: TLoc = initLocExpr(p, e[1])
      let rca = rdCharLoc(a)
      putIntoDest(p, d, e, cgCall(p, "cardSet", rca, cIntValue(size)))
    of mLtSet, mLeSet:
      i = getTemp(p, getSysType(p.module.g.graph, unknownLineInfo, tyInt)) # our counter
      a = initLocExpr(p, e[1])
      b = initLocExpr(p, e[2])
      if d.k == locNone: d = getTemp(p, getSysType(p.module.g.graph, unknownLineInfo, tyBool))
      discard "for ($1 = 0; $1 < $2; $1++) { $n" &
        "  $3 = (($4[$1] & ~ $5[$1]) == 0);$n" &
        "  if (!$3) break;}$n"
      let ri = rdLoc(i)
      let rd = rdLoc(d)
      let ra = rdLoc(a)
      let rb = rdLoc(b)
      p.s(cpsStmts).addForRangeExclusive(ri, cIntValue(0), cIntValue(size)):
        p.s(cpsStmts).addAssignment(rd, cOp(Equal,
          cOp(BitAnd, "NU8",
            subscript(ra, ri),
            cOp(BitNot, "NU8", subscript(rb, ri))),
          cIntValue(0)))
        p.s(cpsStmts).addSingleIfStmt(cOp(Not, rd)):
          p.s(cpsStmts).addBreak()
      if op == mLtSet:
        discard "if ($3) $3 = (#nimCmpMem($4, $5, $2) != 0);$n"
        p.s(cpsStmts).addSingleIfStmt(rd):
          p.s(cpsStmts).addAssignment(rd, cOp(NotEqual,
            cgCall(p, "nimCmpMem", ra, rb, cIntValue(size)),
            cIntValue(0)))
    of mEqSet:
      assert(e[1].typ != nil)
      assert(e[2].typ != nil)
      var a = initLocExpr(p, e[1])
      var b = initLocExpr(p, e[2])
      let rca = a.rdCharLoc
      let rcb = b.rdCharLoc
      putIntoDest(p, d, e, cOp(Equal,
        cgCall(p, "nimCmpMem", rca, rcb, cIntValue(size)),
        cIntValue(0)))
    of mMulSet, mPlusSet, mMinusSet, mXorSet:
      # we inline the simple for loop for better code generation:
      i = getTemp(p, getSysType(p.module.g.graph, unknownLineInfo, tyInt)) # our counter
      a = initLocExpr(p, e[1])
      b = initLocExpr(p, e[2])
      if d.k == locNone: d = getTemp(p, setType)
      let ri = rdLoc(i)
      let rd = rdLoc(d)
      let ra = rdLoc(a)
      let rb = rdLoc(b)
      p.s(cpsStmts).addForRangeExclusive(ri, cIntValue(0), cIntValue(size)):
        p.s(cpsStmts).addAssignmentWithValue(subscript(rd, ri)):
          let x = subscript(ra, ri)
          let y = subscript(rb, ri)
          let lookup =
            case op
            of mMulSet: cOp(BitAnd, "NU8", x, y)
            of mPlusSet: cOp(BitOr, "NU8", x, y)
            of mMinusSet: cOp(BitAnd, "NU8", x, cOp(BitNot, "NU8", y))
            of mXorSet: cOp(BitXor, "NU8", x, y)
            else: "" # unreachable
          p.s(cpsStmts).add(lookup)
    of mInSet: genInOp(p, e, d)
    else: internalError(p.config, e.info, "genSetOp")

proc genOrd(p: BProc, e: PNode, d: var TLoc) =
  unaryExprChar(p, e, d, ra)

proc genSomeCast(p: BProc, e: PNode, d: var TLoc) =
  const
    ValueTypes = {tyTuple, tyObject, tyArray, tyOpenArray, tyVarargs, tyUncheckedArray}
  # we use whatever C gives us. Except if we have a value-type, we need to go
  # through its address:
  var a: TLoc = initLocExpr(p, e[1])
  let etyp = skipTypes(e.typ, abstractRange+{tyOwned})
  let srcTyp = skipTypes(e[1].typ, abstractRange)
  if etyp.kind in ValueTypes and lfIndirect notin a.flags:
    let destTyp = getTypeDesc(p.module, e.typ)
    let val = addrLoc(p.config, a)
    # (* (destType*) val)
    putIntoDest(p, d, e,
      cDeref(
        cCast(
          ptrType(destTyp),
          wrapPar(val))),
      a.storage)
  elif etyp.kind == tyProc and etyp.callConv == ccClosure and srcTyp.callConv != ccClosure:
    let destTyp = getClosureType(p.module, etyp, clHalfWithEnv)
    let val = rdCharLoc(a)
    # (destTyp) val
    putIntoDest(p, d, e, cCast(destTyp, wrapPar(val)), a.storage)
  else:
    # C++ does not like direct casts from pointer to shorter integral types
    if srcTyp.kind in {tyPtr, tyPointer} and etyp.kind in IntegralTypes:
      let destTyp = getTypeDesc(p.module, e.typ)
      let val = rdCharLoc(a)
      # (destTyp) (ptrdiff_t) val
      putIntoDest(p, d, e, cCast(destTyp, cCast("ptrdiff_t", wrapPar(val))), a.storage)
    elif optSeqDestructors in p.config.globalOptions and etyp.kind in {tySequence, tyString}:
      let destTyp = getTypeDesc(p.module, e.typ)
      let val = rdCharLoc(a)
      # (* (destType*) (&val))
      putIntoDest(p, d, e, cDeref(cCast(ptrType(destTyp), wrapPar(cAddr(val)))), a.storage)
    elif etyp.kind == tyBool and srcTyp.kind in IntegralTypes:
      putIntoDest(p, d, e, cOp(NotEqual, rdCharLoc(a), cIntValue(0)), a.storage)
    else:
      if etyp.kind == tyPtr:
        # generates the definition of structs for casts like cast[ptr object](addr x)[]
        let internalType = etyp.skipTypes({tyPtr})
        if internalType.kind == tyObject:
          discard getTypeDesc(p.module, internalType)
      let destTyp = getTypeDesc(p.module, e.typ)
      let val = rdCharLoc(a)
      putIntoDest(p, d, e, cCast(destTyp, wrapPar(val)), a.storage)

proc genCast(p: BProc, e: PNode, d: var TLoc) =
  const ValueTypes = {tyFloat..tyFloat128, tyTuple, tyObject, tyArray}
  let
    destt = skipTypes(e.typ, abstractRange)
    srct = skipTypes(e[1].typ, abstractRange)
  if destt.kind in ValueTypes or srct.kind in ValueTypes:
    # 'cast' and some float type involved? --> use a union.
    inc(p.labels)
    var lbl = p.labels.rope
    var tmp: TLoc = default(TLoc)
    tmp.snippet = dotField("LOC" & lbl, "source")
    let destsize = getSize(p.config, destt)
    let srcsize = getSize(p.config, srct)

    let srcTyp = getTypeDesc(p.module, e[1].typ)
    let destTyp = getTypeDesc(p.module, e.typ)
    if destsize > srcsize:
      p.s(cpsLocals).addVarWithType(kind = Local, name = "LOC" & lbl):
        p.s(cpsLocals).addUnionType():
          p.s(cpsLocals).addField(name = "dest", typ = destTyp)
          p.s(cpsLocals).addField(name = "source", typ = srcTyp)
      p.s(cpsLocals).addCallStmt(cgsymValue(p.module, "nimZeroMem"),
        cAddr("LOC" & lbl),
        cSizeof("LOC" & lbl))
    else:
      p.s(cpsLocals).addVarWithType(kind = Local, name = "LOC" & lbl):
        p.s(cpsLocals).addUnionType():
          p.s(cpsLocals).addField(name = "source", typ = srcTyp)
          p.s(cpsLocals).addField(name = "dest", typ = destTyp)
    tmp.k = locExpr
    tmp.lode = lodeTyp srct
    tmp.storage = OnStack
    tmp.flags = {}
    expr(p, e[1], tmp)
    putIntoDest(p, d, e, dotField("LOC" & lbl, "dest"), tmp.storage)
  else:
    # I prefer the shorter cast version for pointer types -> generate less
    # C code; plus it's the right thing to do for closures:
    genSomeCast(p, e, d)

proc genRangeChck(p: BProc, n: PNode, d: var TLoc) =
  var a: TLoc = initLocExpr(p, n[0])
  var dest = skipTypes(n.typ, abstractVar)
  if optRangeCheck notin p.options or (dest.kind in {tyUInt..tyUInt64} and
      checkUnsignedConversions notin p.config.legacyFeatures):
    discard "no need to generate a check because it was disabled"
  else:
    let n0t = n[0].typ

    # emit range check:
    if n0t.kind in {tyUInt, tyUInt64}:
      var first = newBuilder("")
      genLiteral(p, n[1], dest, first)
      var last = newBuilder("")
      genLiteral(p, n[2], dest, last)
      let rca = rdCharLoc(a)
      let rt = getTypeDesc(p.module, n0t)
      p.s(cpsStmts).addSingleIfStmt(cOp(GreaterThan, rca, cCast(rt, extract(last)))):
        p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "raiseRangeErrorNoArgs"))
        raiseInstr(p, p.s(cpsStmts))

    else:
      let raiser =
        case skipTypes(n.typ, abstractVarRange).kind
        of tyUInt..tyUInt64, tyChar: "raiseRangeErrorU"
        of tyFloat..tyFloat128: "raiseRangeErrorF"
        else: "raiseRangeErrorI"
      cgsym(p.module, raiser)

      var first = newBuilder("")
      genLiteral(p, n[1], dest, first)
      var last = newBuilder("")
      genLiteral(p, n[2], dest, last)
      let rca = rdCharLoc(a)
      let boundRca =
        if n0t.skipTypes(abstractVarRange).kind in {tyUInt, tyUInt32, tyUInt64}:
          cCast("NI64", rca)
        else:
          rca
      let firstVal = extract(first)
      let lastVal = extract(last)
      p.s(cpsStmts).addSingleIfStmt(cOp(Or,
        cOp(LessThan, boundRca, firstVal),
        cOp(GreaterThan, boundRca, lastVal))):
        p.s(cpsStmts).addCallStmt(raiser, rca, firstVal, lastVal)
        raiseInstr(p, p.s(cpsStmts))

  if sameBackendTypeIgnoreRange(dest, n[0].typ):
    # don't cast so an address can be taken for `var` conversions
    let val = rdCharLoc(a)
    putIntoDest(p, d, n, wrapPar(val), a.storage)
  else:
    let destType = getTypeDesc(p.module, dest)
    let val = rdCharLoc(a)
    putIntoDest(p, d, n, cCast(destType, wrapPar(val)), a.storage)

proc genConv(p: BProc, e: PNode, d: var TLoc) =
  let destType = e.typ.skipTypes({tyVar, tyLent, tyGenericInst, tyAlias, tySink})
  if sameBackendTypeIgnoreRange(destType, e[1].typ):
    expr(p, e[1], d)
  else:
    genSomeCast(p, e, d)

proc convStrToCStr(p: BProc, n: PNode, d: var TLoc) =
  var a: TLoc = initLocExpr(p, n[0])
  putIntoDest(p, d, n,
    cgCall(p, "nimToCStringConv", rdLoc(a)),
#   "($1 ? $1->data : (NCSTRING)\"\")" % [a.rdLoc],
    a.storage)

proc convCStrToStr(p: BProc, n: PNode, d: var TLoc) =
  var a: TLoc = initLocExpr(p, n[0])
  if p.module.compileToCpp:
    # fixes for const qualifier; bug #12703; bug #19588
    putIntoDest(p, d, n,
      cgCall(p, "cstrToNimstr", cCast("NCSTRING", rdLoc(a))),
      a.storage)
  else:
    putIntoDest(p, d, n,
      cgCall(p, "cstrToNimstr", rdLoc(a)),
      a.storage)
  gcUsage(p.config, n)

proc genStrEquals(p: BProc, e: PNode, d: var TLoc) =
  var x: TLoc
  var a = e[1]
  var b = e[2]
  if a.kind in {nkStrLit..nkTripleStrLit} and a.strVal == "":
    x = initLocExpr(p, e[2])
    let lx = lenExpr(p, x)
    putIntoDest(p, d, e, cOp(Equal, lx, cIntValue(0)))
  elif b.kind in {nkStrLit..nkTripleStrLit} and b.strVal == "":
    x = initLocExpr(p, e[1])
    let lx = lenExpr(p, x)
    putIntoDest(p, d, e, cOp(Equal, lx, cIntValue(0)))
  else:
    binaryExpr(p, e, d, cgCall(p, "eqStrings", ra, rb))

proc binaryFloatArith(p: BProc, e: PNode, d: var TLoc, m: TMagic) =
  if {optNaNCheck, optInfCheck} * p.options != {}:
    const opr: array[mAddF64..mDivF64, TypedBinaryOp] = [Add, Sub, Mul, Div]
    assert(e[1].typ != nil)
    assert(e[2].typ != nil)
    var a = initLocExpr(p, e[1])
    var b = initLocExpr(p, e[2])
    let ra = rdLoc(a)
    let rb = rdLoc(b)
    let rt = getSimpleTypeDesc(p.module, e[1].typ)
    putIntoDest(p, d, e, cOp(opr[m], rt, cCast(rt, ra), cCast(rt, rb)))
    if optNaNCheck in p.options:
      let rd = rdLoc(d)
      p.s(cpsStmts).addSingleIfStmt(cOp(NotEqual, rd, rd)):
        p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "raiseFloatInvalidOp"))
        raiseInstr(p, p.s(cpsStmts))

    if optInfCheck in p.options:
      let rd = rdLoc(d)
      p.s(cpsStmts).addSingleIfStmt(cOp(And,
          cOp(NotEqual, rd, cFloatValue(0.0)),
          cOp(Equal, cOp(Mul, rt, rd, cFloatValue(0.5)), rd))):
        p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "raiseFloatOverflow"), rd)
        raiseInstr(p, p.s(cpsStmts))

  else:
    binaryArith(p, e, d, m)

proc genWasMoved(p: BProc; n: PNode) =
  var a: TLoc
  let n1 = n[1].skipAddr
  if p.withinBlockLeaveActions > 0 and notYetAlive(n1):
    discard
  else:
    a = initLocExpr(p, n1, {lfEnforceDeref})
    resetLoc(p, a)
    #linefmt(p, cpsStmts, "#nimZeroMem((void*)$1, sizeof($2));$n",
    #  [addrLoc(p.config, a), getTypeDesc(p.module, a.t)])

proc genMove(p: BProc; n: PNode; d: var TLoc) =
  var a: TLoc = initLocExpr(p, n[1].skipAddr, {lfEnforceDeref})
  if n.len == 4:
    # generated by liftdestructors:
    var src: TLoc = initLocExpr(p, n[2])
    let destVal = rdLoc(a)
    let srcVal = rdLoc(src)
    p.s(cpsStmts).addSingleIfStmt(
      cOp(NotEqual,
        dotField(destVal, "p"),
        dotField(srcVal, "p"))):
      genStmts(p, n[3])
    p.s(cpsStmts).addFieldAssignment(destVal, "len", dotField(srcVal, "len"))
    p.s(cpsStmts).addFieldAssignment(destVal, "p", dotField(srcVal, "p"))
  else:
    if d.k == locNone: d = getTemp(p, n.typ)
    if p.config.selectedGC in {gcArc, gcAtomicArc, gcOrc}:
      genAssignment(p, d, a, {})
      var op = getAttachedOp(p.module.g.graph, n.typ, attachedWasMoved)
      if op == nil:
        resetLoc(p, a)
      else:
        var b = initLocExpr(p, newSymNode(op))
        case skipTypes(a.t, abstractVar+{tyStatic}).kind
        of tyOpenArray, tyVarargs: # todo fixme generated `wasMoved` hooks for
                                   # openarrays, but it probably shouldn't?
          let ra = rdLoc(a)
          var s: string
          if reifiedOpenArray(a.lode):
            if a.t.kind in {tyVar, tyLent}:
              s = derefField(ra, "Field0") & cArgumentSeparator & derefField(ra, "Field1")
            else:
              s = dotField(ra, "Field0") & cArgumentSeparator & dotField(ra, "Field1")
          else:
            s = ra & cArgumentSeparator & ra & "Len_0"
          p.s(cpsStmts).addCallStmt(rdLoc(b), s)
        else:
          let val = if p.module.compileToCpp: rdLoc(a) else: byRefLoc(p, a)
          p.s(cpsStmts).addCallStmt(rdLoc(b), val)
    else:
      if n[1].kind == nkSym and isSinkParam(n[1].sym):
        var tmp = getTemp(p, n[1].typ.skipTypes({tySink}))
        genAssignment(p, tmp, a, {needToCopySinkParam})
        genAssignment(p, d, tmp, {})
        resetLoc(p, tmp)
      else:
        genAssignment(p, d, a, {})
      resetLoc(p, a)

proc genDestroy(p: BProc; n: PNode) =
  if optSeqDestructors in p.config.globalOptions:
    let arg = n[1].skipAddr
    let t = arg.typ.skipTypes(abstractInst)
    case t.kind
    of tyString:
      var a: TLoc = initLocExpr(p, arg)
      let ra = rdLoc(a)
      let rp = dotField(ra, "p")
      p.s(cpsStmts).addSingleIfStmt(
        cOp(And, rp,
          cOp(Not, cOp(BitAnd, "NI",
            derefField(rp, "cap"),
            "NIM_STRLIT_FLAG")))):
        let fn = if optThreads in p.config.globalOptions: "deallocShared" else: "dealloc"
        p.s(cpsStmts).addCallStmt(cgsymValue(p.module, fn), rp)
    of tySequence:
      var a: TLoc = initLocExpr(p, arg)
      let ra = rdLoc(a)
      let rp = dotField(ra, "p")
      let rt = getTypeDesc(p.module, t.elementType)
      p.s(cpsStmts).addSingleIfStmt(
        cOp(And, rp,
          cOp(Not, cOp(BitAnd, "NI",
            derefField(rp, "cap"),
            "NIM_STRLIT_FLAG")))):
        p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "alignedDealloc"),
          rp,
          cAlignof(rt))
    else: discard "nothing to do"
  else:
    let t = n[1].typ.skipTypes(abstractVar)
    let op = getAttachedOp(p.module.g.graph, t, attachedDestructor)
    if op != nil and getBody(p.module.g.graph, op).len != 0:
      internalError(p.config, n.info, "destructor turned out to be not trivial")
    discard "ignore calls to the default destructor"

proc genDispose(p: BProc; n: PNode) =
  when false:
    let elemType = n[1].typ.skipTypes(abstractVar).elementType

    var a: TLoc = initLocExpr(p, n[1].skipAddr)

    if isFinal(elemType):
      if elemType.destructor != nil:
        var destroyCall = newNodeI(nkCall, n.info)
        genStmts(p, destroyCall)
      lineFmt(p, cpsStmts, "#nimRawDispose($1, NIM_ALIGNOF($2))", [rdLoc(a), getTypeDesc(p.module, elemType)])
    else:
      # ``nimRawDisposeVirtual`` calls the ``finalizer`` which is the same as the
      # destructor, but it uses the runtime type. Afterwards the memory is freed:
      lineCg(p, cpsStmts, ["#nimDestroyAndDispose($#)", rdLoc(a)])

proc genSlice(p: BProc; e: PNode; d: var TLoc) =
  let (x, y) = genOpenArraySlice(p, e, e.typ, e.typ.elementType,
    prepareForMutation = e[1].kind == nkHiddenDeref and
                         e[1].typ.skipTypes(abstractInst).kind == tyString and
                         p.config.selectedGC in {gcArc, gcAtomicArc, gcOrc})
  if d.k == locNone: d = getTemp(p, e.typ)
  let dest = rdLoc(d)
  p.s(cpsStmts).addFieldAssignment(dest, "Field0", x)
  p.s(cpsStmts).addFieldAssignment(dest, "Field1", y)
  when false:
    localError(p.config, e.info, "invalid context for 'toOpenArray'; " &
      "'toOpenArray' is only valid within a call expression")

proc genEnumToStr(p: BProc, e: PNode, d: var TLoc) =
  let t = e[1].typ.skipTypes(abstractInst+{tyRange})
  let toStrProc = getToStringProc(p.module.g.graph, t)
  # XXX need to modify this logic for IC.
  var n = copyTree(e)
  n[0] = newSymNode(toStrProc)
  expr(p, n, d)

proc genMagicExpr(p: BProc, e: PNode, d: var TLoc, op: TMagic) =
  case op
  of mOr, mAnd: genAndOr(p, e, d, op)
  of mNot..mUnaryMinusF64: unaryArith(p, e, d, op)
  of mUnaryMinusI..mAbsI: unaryArithOverflow(p, e, d, op)
  of mAddF64..mDivF64: binaryFloatArith(p, e, d, op)
  of mShrI..mXor: binaryArith(p, e, d, op)
  of mEqProc: genEqProc(p, e, d)
  of mAddI..mPred: binaryArithOverflow(p, e, d, op)
  of mRepr: genRepr(p, e, d)
  of mGetTypeInfo: genGetTypeInfo(p, e, d)
  of mGetTypeInfoV2: genGetTypeInfoV2(p, e, d)
  of mSwap: genSwap(p, e, d)
  of mInc, mDec:
    const opr: array[mInc..mDec, TypedBinaryOp] = [Add, Sub]
    const fun64: array[mInc..mDec, string] = ["nimAddInt64", "nimSubInt64"]
    const fun: array[mInc..mDec, string] = ["nimAddInt","nimSubInt"]
    let underlying = skipTypes(e[1].typ, {tyGenericInst, tyAlias, tySink, tyVar, tyLent, tyRange, tyDistinct})
    if optOverflowCheck notin p.options or underlying.kind in {tyUInt..tyUInt64}:
      binaryStmt(p, e, d, opr[op])
    else:
      assert(e[1].typ != nil)
      assert(e[2].typ != nil)
      var a = initLocExpr(p, e[1])
      var b = initLocExpr(p, e[2])

      let ranged = skipTypes(e[1].typ, {tyGenericInst, tyAlias, tySink, tyVar, tyLent, tyDistinct})
      let res = binaryArithOverflowRaw(p, ranged, a, b,
        if underlying.kind == tyInt64: fun64[op] else: fun[op])

      let destTyp = getTypeDesc(p.module, ranged)
      putIntoDest(p, a, e[1], cCast(destTyp, wrapPar(res)))

  of mConStrStr: genStrConcat(p, e, d)
  of mAppendStrCh:
    if optSeqDestructors in p.config.globalOptions:
      binaryStmtAddr(p, e, d, "nimAddCharV1")
    else:
      var call = initLoc(locCall, e, OnHeap)
      var dest = initLocExpr(p, e[1])
      var b = initLocExpr(p, e[2])
      call.snippet = cgCall(p, "addChar", rdLoc(dest), rdLoc(b))
      genAssignment(p, dest, call, {})
  of mAppendStrStr: genStrAppend(p, e, d)
  of mAppendSeqElem:
    if optSeqDestructors in p.config.globalOptions:
      e[1] = makeAddr(e[1], p.module.idgen)
      genCall(p, e, d)
    else:
      genSeqElemAppend(p, e, d)
  of mEqStr: genStrEquals(p, e, d)
  of mLeStr:
    binaryExpr(p, e, d, cOp(LessEqual,
      cgCall(p, "cmpStrings", ra, rb),
      cIntValue(0)))
  of mLtStr:
    binaryExpr(p, e, d, cOp(LessThan,
      cgCall(p, "cmpStrings", ra, rb),
      cIntValue(0)))
  of mIsNil: genIsNil(p, e, d)
  of mBoolToStr:
    genDollarIt(p, e, d, cgCall(p, "nimBoolToStr", it))
  of mCharToStr:
    genDollarIt(p, e, d, cgCall(p, "nimCharToStr", it))
  of mCStrToStr:
    if p.module.compileToCpp:
      # fixes for const qualifier; bug #12703; bug #19588
      genDollarIt(p, e, d, cgCall(p, "cstrToNimstr", cCast("NCSTRING", it)))
    else:
      genDollarIt(p, e, d, cgCall(p, "cstrToNimstr", it))
  of mStrToStr, mUnown: expr(p, e[1], d)
  of generatedMagics: genCall(p, e, d)
  of mEnumToStr:
    if optTinyRtti in p.config.globalOptions:
      genEnumToStr(p, e, d)
    else:
      genRepr(p, e, d)
  of mOf: genOf(p, e, d)
  of mNew: genNew(p, e)
  of mNewFinalize:
    if optTinyRtti in p.config.globalOptions:
      var a: TLoc = initLocExpr(p, e[1])
      rawGenNew(p, a, "", needsInit = true)
      gcUsage(p.config, e)
    else:
      genNewFinalize(p, e)
  of mNewSeq:
    if optSeqDestructors in p.config.globalOptions:
      e[1] = makeAddr(e[1], p.module.idgen)
      genCall(p, e, d)
    else:
      genNewSeq(p, e)
  of mNewSeqOfCap: genNewSeqOfCap(p, e, d)
  of mSizeOf:
    let t = e[1].typ.skipTypes({tyTypeDesc})
    putIntoDest(p, d, e, cCast("NI", cSizeof(getTypeDesc(p.module, t, dkVar))))
  of mAlignOf:
    let t = e[1].typ.skipTypes({tyTypeDesc})
    putIntoDest(p, d, e, cCast("NI", cAlignof(getTypeDesc(p.module, t, dkVar))))
  of mOffsetOf:
    var dotExpr: PNode
    if e[1].kind == nkDotExpr:
      dotExpr = e[1]
    elif e[1].kind == nkCheckedFieldExpr:
      dotExpr = e[1][0]
    else:
      dotExpr = nil
      internalError(p.config, e.info, "unknown ast")
    let t = dotExpr[0].typ.skipTypes({tyTypeDesc})
    let tname = getTypeDesc(p.module, t, dkVar)
    let member =
      if t.kind == tyTuple:
        "Field" & rope(dotExpr[1].sym.position)
      else: dotExpr[1].sym.loc.snippet
    putIntoDest(p,d,e, cCast("NI", cOffsetof(tname, member)))
  of mChr: genSomeCast(p, e, d)
  of mOrd: genOrd(p, e, d)
  of mLengthArray, mHigh, mLengthStr, mLengthSeq, mLengthOpenArray:
    genArrayLen(p, e, d, op)
  of mGCref:
    # only a magic for the old GCs
    var a: TLoc = initLocExpr(p, e[1])
    let ra = rdLoc(a)
    p.s(cpsStmts).addSingleIfStmt(ra):
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "nimGCref"), ra)
  of mGCunref:
    # only a magic for the old GCs
    var a: TLoc = initLocExpr(p, e[1])
    let ra = rdLoc(a)
    p.s(cpsStmts).addSingleIfStmt(ra):
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "nimGCunref"), ra)
  of mSetLengthStr: genSetLengthStr(p, e, d)
  of mSetLengthSeq: genSetLengthSeq(p, e, d)
  of mIncl, mExcl, mCard, mLtSet, mLeSet, mEqSet, mMulSet, mPlusSet, mMinusSet,
     mInSet, mXorSet:
    genSetOp(p, e, d, op)
  of mNewString, mNewStringOfCap, mExit, mParseBiggestFloat:
    var opr = e[0].sym
    # Why would anyone want to set nodecl to one of these hardcoded magics?
    # - not sure, and it wouldn't work if the symbol behind the magic isn't
    #   somehow forward-declared from some other usage, but it is *possible*
    if lfNoDecl notin opr.loc.flags:
      let prc = magicsys.getCompilerProc(p.module.g.graph, $opr.loc.snippet)
      assert prc != nil, $opr.loc.snippet
      # HACK:
      # Explicitly add this proc as declared here so the cgsym call doesn't
      # add a forward declaration - without this we could end up with the same
      # 2 forward declarations. That happens because the magic symbol and the original
      # one that shall be used have different ids (even though a call to one is
      # actually a call to the other) so checking into m.declaredProtos with the 2 different ids doesn't work.
      # Why would 2 identical forward declarations be a problem?
      # - in the case of hot code-reloading we generate function pointers instead
      #   of forward declarations and in C++ it is an error to redefine a global
      let wasDeclared = containsOrIncl(p.module.declaredProtos, prc.id)
      # Make the function behind the magic get actually generated - this will
      # not lead to a forward declaration! The genCall will lead to one.
      cgsym(p.module, $opr.loc.snippet)
      # make sure we have pointer-initialising code for hot code reloading
      if not wasDeclared and p.hcrOn:
        let name = mangleDynLibProc(prc)
        let rt = getTypeDesc(p.module, prc.loc.t)
        p.module.s[cfsDynLibInit].add('\t')
        p.module.s[cfsDynLibInit].addAssignmentWithValue(name):
          p.module.s[cfsDynLibInit].addCast(rt):
            p.module.s[cfsDynLibInit].addCall("hcrGetProc",
              getModuleDllPath(p.module, prc),
              '"' & name & '"')
    genCall(p, e, d)
  of mDefault, mZeroDefault: genDefault(p, e, d)
  of mEcho: genEcho(p, e[1].skipConv)
  of mArrToSeq: genArrToSeq(p, e, d)
  of mNLen..mNError, mSlurp..mQuoteAst:
    localError(p.config, e.info, strutils.`%`(errXMustBeCompileTime, e[0].sym.name.s))
  of mSpawn:
    when defined(leanCompiler):
      p.config.quitOrRaise "compiler built without support for the 'spawn' statement"
    else:
      let n = spawn.wrapProcForSpawn(p.module.g.graph, p.module.idgen, p.module.module, e, e.typ, nil, nil)
      expr(p, n, d)
  of mParallel:
    when defined(leanCompiler):
      p.config.quitOrRaise "compiler built without support for the 'parallel' statement"
    else:
      let n = semparallel.liftParallel(p.module.g.graph, p.module.idgen, p.module.module, e)
      expr(p, n, d)
  of mDeepCopy:
    if p.config.selectedGC in {gcArc, gcAtomicArc, gcOrc} and optEnableDeepCopy notin p.config.globalOptions:
      localError(p.config, e.info,
        "for --mm:arc|atomicArc|orc 'deepcopy' support has to be enabled with --deepcopy:on")

    let x = if e[1].kind in {nkAddr, nkHiddenAddr}: e[1][0] else: e[1]
    var a = initLocExpr(p, x)
    var b = initLocExpr(p, e[2])
    genDeepCopy(p, a, b)
  of mDotDot, mEqCString: genCall(p, e, d)
  of mWasMoved: genWasMoved(p, e)
  of mMove: genMove(p, e, d)
  of mDestroy: genDestroy(p, e)
  of mAccessEnv: unaryExpr(p, e, d, dotField(ra, "ClE_0"))
  of mAccessTypeField: genAccessTypeField(p, e, d)
  of mSlice: genSlice(p, e, d)
  of mTrace: discard "no code to generate"
  of mEnsureMove:
    expr(p, e[1], d)
  of mDup:
    expr(p, e[1], d)
  else:
    when defined(debugMagics):
      echo p.prc.name.s, " ", p.prc.id, " ", p.prc.flags, " ", p.prc.ast[genericParamsPos].kind
    internalError(p.config, e.info, "genMagicExpr: " & $op)

proc genSetConstr(p: BProc, e: PNode, d: var TLoc) =
  # example: { a..b, c, d, e, f..g }
  # we have to emit an expression of the form:
  # nimZeroMem(tmp, sizeof(tmp)); inclRange(tmp, a, b); incl(tmp, c);
  # incl(tmp, d); incl(tmp, e); inclRange(tmp, f, g);
  var
    a, b: TLoc
  var idx: TLoc
  if nfAllConst in e.flags:
    var elem = newBuilder("")
    genSetNode(p, e, elem)
    putIntoDest(p, d, e, extract(elem))
  else:
    if d.k == locNone: d = getTemp(p, e.typ)
    if getSize(p.config, e.typ) > 8:
      # big set:
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "nimZeroMem"),
        rdLoc(d),
        cSizeof(getTypeDesc(p.module, e.typ)))
      for it in e.sons:
        if it.kind == nkRange:
          idx = getTemp(p, getSysType(p.module.g.graph, unknownLineInfo, tyInt)) # our counter
          a = initLocExpr(p, it[0])
          b = initLocExpr(p, it[1])
          var aa: Snippet = ""
          rdSetElemLoc(p.config, a, e.typ, aa)
          var bb: Snippet = ""
          rdSetElemLoc(p.config, b, e.typ, bb)
          let ri = rdLoc(idx)
          let rd = rdLoc(d)
          p.s(cpsStmts).addForRangeInclusive(ri, aa, bb):
            p.s(cpsStmts).addInPlaceOp(BitOr, "NU8",
              subscript(rd, cOp(Shr, "NU", cCast("NU", ri), cIntValue(3))),
              cOp(Shl, "NU8", cUintValue(1),
                cOp(BitAnd, "NU", cCast("NU", ri), cUintValue(7))))
        else:
          a = initLocExpr(p, it)
          var aa: Snippet = ""
          rdSetElemLoc(p.config, a, e.typ, aa)
          let rd = rdLoc(d)
          p.s(cpsStmts).addInPlaceOp(BitOr, "NU8",
            subscript(rd, cOp(Shr, "NU", cCast("NU", aa), cIntValue(3))),
            cOp(Shl, "NU8", cUintValue(1),
              cOp(BitAnd, "NU", cCast("NU", aa), cUintValue(7))))
    else:
      # small set
      var ts = "NU" & $(getSize(p.config, e.typ) * 8)
      p.s(cpsStmts).addAssignment(rdLoc(d), cIntValue(0))
      for it in e.sons:
        if it.kind == nkRange:
          idx = getTemp(p, getSysType(p.module.g.graph, unknownLineInfo, tyInt)) # our counter
          a = initLocExpr(p, it[0])
          b = initLocExpr(p, it[1])
          var aa: Snippet = ""
          rdSetElemLoc(p.config, a, e.typ, aa)
          var bb: Snippet = ""
          rdSetElemLoc(p.config, b, e.typ, bb)
          let ri = rdLoc(idx)
          let rd = rdLoc(d)
          p.s(cpsStmts).addForRangeInclusive(ri, aa, bb):
            p.s(cpsStmts).addInPlaceOp(BitOr, ts, rd,
              cOp(Shl, ts, cCast(ts, cIntValue(1)),
                cOp(Mod, ts, ri, cOp(Mul, ts, cSizeof(ts), cIntValue(8)))))
        else:
          a = initLocExpr(p, it)
          var aa: Snippet = ""
          rdSetElemLoc(p.config, a, e.typ, aa)
          let rd = rdLoc(d)
          p.s(cpsStmts).addInPlaceOp(BitOr, ts, rd,
            cOp(Shl, ts, cCast(ts, cIntValue(1)),
              cOp(Mod, ts, aa, cOp(Mul, ts, cSizeof(ts), cIntValue(8)))))

proc genTupleConstr(p: BProc, n: PNode, d: var TLoc) =
  var rec: TLoc
  if not handleConstExpr(p, n, d):
    let t = n.typ
    discard getTypeDesc(p.module, t) # so that any fields are initialized

    var tmp: TLoc = default(TLoc)
    # bug #16331
    let doesAlias = lhsDoesAlias(d.lode, n)
    let dest = if doesAlias: addr(tmp) else: addr(d)
    if doesAlias:
      tmp = getTemp(p, n.typ)
    elif d.k == locNone:
      d = getTemp(p, n.typ)

    for i in 0..<n.len:
      var it = n[i]
      if it.kind == nkExprColonExpr: it = it[1]
      rec = initLoc(locExpr, it, dest[].storage)
      rec.snippet = dotField(rdLoc(dest[]), "Field" & rope(i))
      rec.flags.incl(lfEnforceDeref)
      expr(p, it, rec)

    if doesAlias:
      if d.k == locNone:
        d = tmp
      else:
        genAssignment(p, d, tmp, {})

proc isConstClosure(n: PNode): bool {.inline.} =
  result = n[0].kind == nkSym and isRoutine(n[0].sym) and
      n[1].kind == nkNilLit

proc genClosure(p: BProc, n: PNode, d: var TLoc) =
  assert n.kind in {nkPar, nkTupleConstr, nkClosure}

  if isConstClosure(n):
    inc(p.module.labels)
    var tmp = "CNSTCLOSURE" & rope(p.module.labels)
    let td = getTypeDesc(p.module, n.typ)
    var data = newBuilder("")
    data.addVarWithInitializer(kind = Const, name = tmp, typ = td):
      genBracedInit(p, n, isConst = true, n.typ, data)
    p.module.s[cfsData].add(extract(data))
    putIntoDest(p, d, n, tmp, OnStatic)
  else:
    var tmp: TLoc
    var a = initLocExpr(p, n[0])
    var b = initLocExpr(p, n[1])
    if n[0].skipConv.kind == nkClosure:
      internalError(p.config, n.info, "closure to closure created")
    # tasyncawait.nim breaks with this optimization:
    when false:
      if d.k != locNone:
        let dest = d.rdLoc
        p.s(cpsStmts).addFieldAssignment(dest, "ClP_0", a.rdLoc)
        p.s(cpsStmts).addFieldAssignment(dest, "ClE_0", b.rdLoc)
    else:
      tmp = getTemp(p, n.typ)
      let dest = tmp.rdLoc
      p.s(cpsStmts).addFieldAssignment(dest, "ClP_0", a.rdLoc)
      p.s(cpsStmts).addFieldAssignment(dest, "ClE_0", b.rdLoc)
      putLocIntoDest(p, d, tmp)

proc genArrayConstr(p: BProc, n: PNode, d: var TLoc) =
  var arr: TLoc
  if not handleConstExpr(p, n, d):
    if d.k == locNone: d = getTemp(p, n.typ)
    for i in 0..<n.len:
      arr = initLoc(locExpr, lodeTyp elemType(skipTypes(n.typ, abstractInst)), d.storage)
      let lit = cIntLiteral(i)
      arr.snippet = subscript(rdLoc(d), lit)
      expr(p, n[i], arr)

proc genComplexConst(p: BProc, sym: PSym, d: var TLoc) =
  requestConstImpl(p, sym)
  assert((sym.loc.snippet != "") and (sym.loc.t != nil))
  putLocIntoDest(p, d, sym.loc)

template genStmtListExprImpl(exprOrStmt) {.dirty.} =
  #let hasNimFrame = magicsys.getCompilerProc("nimFrame") != nil
  let hasNimFrame = p.prc != nil and
      sfSystemModule notin p.module.module.flags and
      optStackTrace in p.prc.options
  var frameName: Rope = ""
  for i in 0..<n.len - 1:
    let it = n[i]
    if it.kind == nkComesFrom:
      if hasNimFrame and frameName == "":
        inc p.labels
        frameName = "FR" & rope(p.labels) & "_"
        let theMacro = it[0].sym
        add p.s(cpsStmts), initFrameNoDebug(p, frameName,
           makeCString theMacro.name.s,
           quotedFilename(p.config, theMacro.info), it.info.line.int)
    else:
      genStmts(p, it)
  if n.len > 0: exprOrStmt
  if frameName != "":
    p.s(cpsStmts).add deinitFrameNoDebug(p, frameName)

proc genStmtListExpr(p: BProc, n: PNode, d: var TLoc) =
  genStmtListExprImpl:
    expr(p, n[^1], d)

proc genStmtList(p: BProc, n: PNode) =
  genStmtListExprImpl:
    genStmts(p, n[^1])

from parampatterns import isLValue

proc upConv(p: BProc, n: PNode, d: var TLoc) =
  var a: TLoc = initLocExpr(p, n[0])
  let dest = skipTypes(n.typ, abstractPtrs)
  if optObjCheck in p.options and not isObjLackingTypeField(dest):
    var nilCheck = ""
    var r: Snippet = ""
    rdMType(p, a, nilCheck, r)
    if optTinyRtti in p.config.globalOptions:
      let checkFor = $getObjDepth(dest)
      let token = $genDisplayElem(MD5Digest(hashType(dest, p.config)))
      let objCheck = cOp(Not, cgCall(p, "isObjDisplayCheck", r, checkFor, token))
      let check = if nilCheck != "": cOp(And, nilCheck, objCheck) else: objCheck
      p.s(cpsStmts).addSingleIfStmt(check):
        p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "raiseObjectConversionError"))
        raiseInstr(p, p.s(cpsStmts))
    else:
      let checkFor = genTypeInfoV1(p.module, dest, n.info)
      let objCheck = cOp(Not, cgCall(p, "isObj", r, checkFor))
      let check = if nilCheck != "": cOp(And, nilCheck, objCheck) else: objCheck
      p.s(cpsStmts).addSingleIfStmt(check):
        p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "raiseObjectConversionError"))
        raiseInstr(p, p.s(cpsStmts))

  if n[0].typ.kind != tyObject:
    let destTyp = getTypeDesc(p.module, n.typ)
    let val = rdLoc(a)
    if n.isLValue:
      # (*((destType) (&(val))))"
      putIntoDest(p, d, n,
        cDeref(
          cCast(ptrType(destTyp),
            wrapPar(cAddr(wrapPar(val))))),
        a.storage)
    else:
      # ((destType) (val))"
      putIntoDest(p, d, n, cCast(destTyp, wrapPar(val)), a.storage)
  else:
    let destTyp = getTypeDesc(p.module, dest)
    let val = addrLoc(p.config, a)
    # (* (destType*) val)
    putIntoDest(p, d, n,
      cDeref(
        cCast(ptrType(destTyp),
          wrapPar(val))),
      a.storage)

proc downConv(p: BProc, n: PNode, d: var TLoc) =
  var arg = n[0]
  while arg.kind == nkObjDownConv: arg = arg[0]

  let dest = skipTypes(n.typ, abstractPtrs)
  let src = skipTypes(arg.typ, abstractPtrs)
  discard getTypeDesc(p.module, src)
  let isRef = skipTypes(arg.typ, abstractInstOwned).kind in {tyRef, tyPtr, tyVar, tyLent}
  if isRef and d.k == locNone and n.typ.skipTypes(abstractInstOwned).kind in {tyRef, tyPtr} and n.isLValue:
    # it can happen that we end up generating '&&x->Sup' here, so we pack
    # the '&x->Sup' into a temporary and then those address is taken
    # (see bug #837). However sometimes using a temporary is not correct:
    # init(TFigure(my)) # where it is passed to a 'var TFigure'. We test
    # this by ensuring the destination is also a pointer:
    var a: TLoc = initLocExpr(p, arg)
    let destType = getTypeDesc(p.module, n.typ)
    let val = rdLoc(a)
    # (* ((destType*) (&(val))))
    putIntoDest(p, d, n,
      cDeref(
        cCast(ptrType(destType),
          wrapPar(cAddr(wrapPar(val))))),
      a.storage)
  elif p.module.compileToCpp:
    # C++ implicitly downcasts for us
    expr(p, arg, d)
  else:
    var a: TLoc = initLocExpr(p, arg)
    var r = rdLoc(a)
    if isRef:
      r = derefField(r, "Sup")
    else:
      r = dotField(r, "Sup")
    for i in 2..abs(inheritanceDiff(dest, src)):
      r = dotField(r, "Sup")
    if isRef:
      r = cAddr(r)
    putIntoDest(p, d, n, r, a.storage)

proc exprComplexConst(p: BProc, n: PNode, d: var TLoc) =
  let t = n.typ
  discard getTypeDesc(p.module, t) # so that any fields are initialized
  let id = nodeTableTestOrSet(p.module.dataCache, n, p.module.labels)
  let tmp = p.module.tmpBase & rope(id)

  if id == p.module.labels:
    # expression not found in the cache:
    inc(p.module.labels)
    let td = getTypeDesc(p.module, t, dkConst)
    var data = newBuilder("")
    data.addVarWithInitializer(
        kind = Const, name = tmp, typ = td):
      genBracedInit(p, n, isConst = true, t, data)
    p.module.s[cfsData].add(extract(data))

  if d.k == locNone:
    fillLoc(d, locData, n, tmp, OnStatic)
  else:
    putDataIntoDest(p, d, n, tmp)
    # This fixes bug #4551, but we really need better dataflow
    # analysis to make this 100% safe.
    if t.kind notin {tySequence, tyString}:
      d.storage = OnStatic

proc genConstSetup(p: BProc; sym: PSym): bool =
  let m = p.module
  useHeader(m, sym)
  if sym.loc.k == locNone:
    fillBackendName(p.module, sym)
    fillLoc(sym.loc, locData, sym.astdef, OnStatic)
  if m.hcrOn: incl(sym.loc.flags, lfIndirect)
  result = lfNoDecl notin sym.loc.flags

proc genConstHeader(m, q: BModule; p: BProc, sym: PSym) =
  if sym.loc.snippet == "":
    if not genConstSetup(p, sym): return
  assert(sym.loc.snippet != "", $sym.name.s & $sym.itemId)
  if m.hcrOn:
    m.s[cfsVars].addVar(kind = Global, name = sym.loc.snippet,
      typ = ptrType(getTypeDesc(m, sym.loc.t, dkVar)))
    m.initProc.procSec(cpsLocals).add('\t')
    m.initProc.procSec(cpsLocals).addAssignmentWithValue(sym.loc.snippet):
      m.initProc.procSec(cpsLocals).addCast(ptrType(getTypeDesc(m, sym.loc.t, dkVar))):
        var getGlobalCall: CallBuilder
        m.initProc.procSec(cpsLocals).addCall("hcrGetGlobal",
          getModuleDllPath(q, sym),
          '"' & sym.loc.snippet & '"')
  else:
    var headerDecl = newBuilder("")
    headerDecl.addDeclWithVisibility(Extern):
      headerDecl.addVar(kind = Local, name = sym.loc.snippet,
        typ = constType(getTypeDesc(m, sym.loc.t, dkVar)))
    m.s[cfsData].add(extract(headerDecl))
    if sfExportc in sym.flags and p.module.g.generatedHeader != nil:
      p.module.g.generatedHeader.s[cfsData].add(extract(headerDecl))

proc genConstDefinition(q: BModule; p: BProc; sym: PSym) =
  # add a suffix for hcr - will later init the global pointer with this data
  let actualConstName = if q.hcrOn: sym.loc.snippet & "_const" else: sym.loc.snippet
  let td = constType(getTypeDesc(q, sym.typ))
  var data = newBuilder("")
  data.addDeclWithVisibility(Private):
    data.addVarWithInitializer(Local, actualConstName, typ = td):
      genBracedInit(q.initProc, sym.astdef, isConst = true, sym.typ, data)
  q.s[cfsData].add(extract(data))
  if q.hcrOn:
    # generate the global pointer with the real name
    q.s[cfsVars].addVar(kind = Global, name = sym.loc.snippet,
      typ = ptrType(getTypeDesc(q, sym.loc.t, dkVar)))
    # register it (but ignore the boolean result of hcrRegisterGlobal)
    q.initProc.procSec(cpsLocals).add('\t')
    q.initProc.procSec(cpsLocals).addStmt():
      var registerCall: CallBuilder
      q.initProc.procSec(cpsLocals).addCall(registerCall, "hcrRegisterGlobal"):
        q.initProc.procSec(cpsLocals).addArgument(registerCall):
          q.initProc.procSec(cpsLocals).add(getModuleDllPath(q, sym))
        q.initProc.procSec(cpsLocals).addArgument(registerCall):
          q.initProc.procSec(cpsLocals).add('"' & sym.loc.snippet & '"')
        q.initProc.procSec(cpsLocals).addArgument(registerCall):
          q.initProc.procSec(cpsLocals).addSizeof(rdLoc(sym.loc))
        q.initProc.procSec(cpsLocals).addArgument(registerCall):
          q.initProc.procSec(cpsLocals).add("NULL")
        q.initProc.procSec(cpsLocals).addArgument(registerCall):
          q.initProc.procSec(cpsLocals).addCast("void**"):
            q.initProc.procSec(cpsLocals).add(cAddr(sym.loc.snippet))
    # always copy over the contents of the actual constant with the _const
    # suffix ==> this means that the constant is reloadable & updatable!
    q.initProc.procSec(cpsLocals).add('\t')
    q.initProc.procSec(cpsLocals).addStmt():
      var copyCall: CallBuilder
      q.initProc.procSec(cpsLocals).addCall(copyCall, cgsymValue(q, "nimCopyMem")):
        q.initProc.procSec(cpsLocals).addArgument(copyCall):
          q.initProc.procSec(cpsLocals).add(cCast("void*", sym.loc.snippet))
        q.initProc.procSec(cpsLocals).addArgument(copyCall):
          q.initProc.procSec(cpsLocals).add(cCast(ptrConstType("void"), cAddr(actualConstName)))
        q.initProc.procSec(cpsLocals).addArgument(copyCall):
          q.initProc.procSec(cpsLocals).addSizeof(rdLoc(sym.loc))

proc genConstStmt(p: BProc, n: PNode) =
  # This code is only used in the new DCE implementation.
  assert useAliveDataFromDce in p.module.flags
  let m = p.module
  for it in n:
    if it[0].kind == nkSym:
      let sym = it[0].sym
      if not isSimpleConst(sym.typ) and sym.itemId.item in m.alive and genConstSetup(p, sym):
        genConstDefinition(m, p, sym)

proc expr(p: BProc, n: PNode, d: var TLoc) =
  when defined(nimCompilerStacktraceHints):
    setFrameMsg p.config$n.info & " " & $n.kind
  p.currLineInfo = n.info

  case n.kind
  of nkSym:
    var sym = n.sym
    case sym.kind
    of skMethod:
      if useAliveDataFromDce in p.module.flags or {sfDispatcher, sfForward} * sym.flags != {}:
        # we cannot produce code for the dispatcher yet:
        fillProcLoc(p.module, n)
        genProcPrototype(p.module, sym)
      else:
        genProc(p.module, sym)
      putLocIntoDest(p, d, sym.loc)
    of skProc, skConverter, skIterator, skFunc:
      #if sym.kind == skIterator:
      #  echo renderTree(sym.getBody, {renderIds})
      if sfCompileTime in sym.flags:
        localError(p.config, n.info, "request to generate code for .compileTime proc: " &
           sym.name.s)
      if useAliveDataFromDce in p.module.flags and sym.typ.callConv != ccInline:
        fillProcLoc(p.module, n)
        genProcPrototype(p.module, sym)
      else:
        genProc(p.module, sym)
      if sym.loc.snippet == "" or sym.loc.lode == nil:
        internalError(p.config, n.info, "expr: proc not init " & sym.name.s)
      putLocIntoDest(p, d, sym.loc)
    of skConst:
      if isSimpleConst(sym.typ):
        var lit = newBuilder("")
        genLiteral(p, sym.astdef, sym.typ, lit)
        putIntoDest(p, d, n, extract(lit), OnStatic)
      elif useAliveDataFromDce in p.module.flags:
        genConstHeader(p.module, p.module, p, sym)
        assert((sym.loc.snippet != "") and (sym.loc.t != nil))
        putLocIntoDest(p, d, sym.loc)
      else:
        genComplexConst(p, sym, d)
    of skEnumField:
      # we never reach this case - as of the time of this comment,
      # skEnumField is folded to an int in semfold.nim, but this code
      # remains for robustness
      putIntoDest(p, d, n, rope(sym.position))
    of skVar, skForVar, skResult, skLet:
      if {sfGlobal, sfThread} * sym.flags != {}:
        genVarPrototype(p.module, n)
        if sfCompileTime in sym.flags:
          genSingleVar(p, sym, n, astdef(sym))

      if sym.loc.snippet == "" or sym.loc.t == nil:
        #echo "FAILED FOR PRCO ", p.prc.name.s
        #echo renderTree(p.prc.ast, {renderIds})
        internalError p.config, n.info, "expr: var not init " & sym.name.s & "_" & $sym.id
      if sfThread in sym.flags:
        accessThreadLocalVar(p, sym)
        if emulatedThreadVars(p.config):
          putIntoDest(p, d, sym.loc.lode, derefField("NimTV_", sym.loc.snippet))
        else:
          putLocIntoDest(p, d, sym.loc)
      else:
        putLocIntoDest(p, d, sym.loc)
    of skTemp:
      when false:
        # this is more harmful than helpful.
        if sym.loc.snippet == "":
          # we now support undeclared 'skTemp' variables for easier
          # transformations in other parts of the compiler:
          assignLocalVar(p, n)
      if sym.loc.snippet == "" or sym.loc.t == nil:
        #echo "FAILED FOR PRCO ", p.prc.name.s
        #echo renderTree(p.prc.ast, {renderIds})
        internalError(p.config, n.info, "expr: temp not init " & sym.name.s & "_" & $sym.id)
      putLocIntoDest(p, d, sym.loc)
    of skParam:
      if sym.loc.snippet == "" or sym.loc.t == nil:
        # echo "FAILED FOR PRCO ", p.prc.name.s
        # debug p.prc.typ.n
        # echo renderTree(p.prc.ast, {renderIds})
        internalError(p.config, n.info, "expr: param not init " & sym.name.s & "_" & $sym.id)
      putLocIntoDest(p, d, sym.loc)
    else: internalError(p.config, n.info, "expr(" & $sym.kind & "); unknown symbol")
  of nkNilLit:
    if not isEmptyType(n.typ):
      var lit = newBuilder("")
      genLiteral(p, n, lit)
      putIntoDest(p, d, n, extract(lit))
  of nkStrLit..nkTripleStrLit:
    var lit = newBuilder("")
    genLiteral(p, n, lit)
    putDataIntoDest(p, d, n, extract(lit))
  of nkIntLit..nkUInt64Lit, nkFloatLit..nkFloat128Lit, nkCharLit:
    var lit = newBuilder("")
    genLiteral(p, n, lit)
    putIntoDest(p, d, n, extract(lit))
  of nkCall, nkHiddenCallConv, nkInfix, nkPrefix, nkPostfix, nkCommand,
     nkCallStrLit:
    genLineDir(p, n) # may be redundant, it is generated in fixupCall as well
    let op = n[0]
    if n.typ.isNil:
      # discard the value:
      var a: TLoc = default(TLoc)
      if op.kind == nkSym and op.sym.magic != mNone:
        genMagicExpr(p, n, a, op.sym.magic)
      else:
        genCall(p, n, a)
    else:
      # load it into 'd':
      if op.kind == nkSym and op.sym.magic != mNone:
        genMagicExpr(p, n, d, op.sym.magic)
      else:
        genCall(p, n, d)
  of nkCurly:
    if isDeepConstExpr(n) and n.len != 0:
      var lit = newBuilder("")
      genSetNode(p, n, lit)
      putIntoDest(p, d, n, extract(lit))
    else:
      genSetConstr(p, n, d)
  of nkBracket:
    if isDeepConstExpr(n) and n.len != 0:
      exprComplexConst(p, n, d)
    elif skipTypes(n.typ, abstractVarRange).kind == tySequence:
      genSeqConstr(p, n, d)
    else:
      genArrayConstr(p, n, d)
  of nkPar, nkTupleConstr:
    if n.typ != nil and n.typ.kind == tyProc and n.len == 2:
      genClosure(p, n, d)
    elif isDeepConstExpr(n) and n.len != 0:
      exprComplexConst(p, n, d)
    else:
      genTupleConstr(p, n, d)
  of nkObjConstr: genObjConstr(p, n, d)
  of nkCast: genCast(p, n, d)
  of nkHiddenStdConv, nkHiddenSubConv, nkConv: genConv(p, n, d)
  of nkAddr, nkHiddenAddr: genAddr(p, n, d)
  of nkBracketExpr: genBracketExpr(p, n, d)
  of nkDerefExpr, nkHiddenDeref: genDeref(p, n, d)
  of nkDotExpr: genRecordField(p, n, d)
  of nkCheckedFieldExpr: genCheckedRecordField(p, n, d)
  of nkBlockExpr, nkBlockStmt: genBlock(p, n, d)
  of nkStmtListExpr: genStmtListExpr(p, n, d)
  of nkStmtList: genStmtList(p, n)
  of nkIfExpr, nkIfStmt: genIf(p, n, d)
  of nkWhen:
    # This should be a "when nimvm" node.
    expr(p, n[1][0], d)
  of nkObjDownConv: downConv(p, n, d)
  of nkObjUpConv: upConv(p, n, d)
  of nkChckRangeF, nkChckRange64, nkChckRange: genRangeChck(p, n, d)
  of nkStringToCString: convStrToCStr(p, n, d)
  of nkCStringToString: convCStrToStr(p, n, d)
  of nkLambdaKinds:
    var sym = n[namePos].sym
    genProc(p.module, sym)
    if sym.loc.snippet == "" or sym.loc.lode == nil:
      internalError(p.config, n.info, "expr: proc not init " & sym.name.s)
    putLocIntoDest(p, d, sym.loc)
  of nkClosure: genClosure(p, n, d)

  of nkEmpty: discard
  of nkWhileStmt: genWhileStmt(p, n)
  of nkVarSection, nkLetSection: genVarStmt(p, n)
  of nkConstSection:
    if useAliveDataFromDce in p.module.flags:
      genConstStmt(p, n)
    # else: consts generated lazily on use
  of nkForStmt: internalError(p.config, n.info, "for statement not eliminated")
  of nkCaseStmt: genCase(p, n, d)
  of nkReturnStmt: genReturnStmt(p, n)
  of nkBreakStmt: genBreakStmt(p, n)
  of nkAsgn:
    cow(p, n[1])
    if nfPreventCg notin n.flags:
      genAsgn(p, n, fastAsgn=false)
  of nkFastAsgn, nkSinkAsgn:
    cow(p, n[1])
    if nfPreventCg notin n.flags:
      # transf is overly aggressive with 'nkFastAsgn', so we work around here.
      # See tests/run/tcnstseq3 for an example that would fail otherwise.
      genAsgn(p, n, fastAsgn=p.prc != nil)
  of nkDiscardStmt:
    let ex = n[0]
    if ex.kind != nkEmpty:
      genLineDir(p, n)
      var a: TLoc = initLocExprSingleUse(p, ex)
      p.s(cpsStmts).addStmt():
        p.s(cpsStmts).add(cCast("void", a.snippet))
  of nkAsmStmt: genAsmStmt(p, n)
  of nkTryStmt, nkHiddenTryStmt:
    case p.config.exc
    of excGoto:
      genTryGoto(p, n, d)
    of excCpp:
      genTryCpp(p, n, d)
    else:
      genTrySetjmp(p, n, d)
  of nkRaiseStmt: genRaiseStmt(p, n)
  of nkTypeSection:
    # we have to emit the type information for object types here to support
    # separate compilation:
    genTypeSection(p.module, n)
  of nkCommentStmt, nkIteratorDef, nkIncludeStmt,
     nkImportStmt, nkImportExceptStmt, nkExportStmt, nkExportExceptStmt,
     nkFromStmt, nkTemplateDef, nkMacroDef, nkStaticStmt:
    discard
  of nkPragma: genPragma(p, n)
  of nkPragmaBlock:
    var inUncheckedAssignSection = 0
    let pragmaList = n[0]
    for pi in pragmaList:
      if whichPragma(pi) == wCast:
        case whichPragma(pi[1])
        of wUncheckedAssign:
          inUncheckedAssignSection = 1
        else:
          discard

    inc p.inUncheckedAssignSection, inUncheckedAssignSection
    expr(p, n.lastSon, d)
    dec p.inUncheckedAssignSection, inUncheckedAssignSection

  of nkProcDef, nkFuncDef, nkMethodDef, nkConverterDef:
    if n[genericParamsPos].kind == nkEmpty:
      var prc = n[namePos].sym
      if useAliveDataFromDce in p.module.flags:
        if p.module.alive.contains(prc.itemId.item) and
            prc.magic in generatedMagics:
          genProc(p.module, prc)
      elif prc.skipGenericOwner.kind == skModule and sfCompileTime notin prc.flags:
        if ({sfExportc, sfCompilerProc} * prc.flags == {sfExportc}) or
            (sfExportc in prc.flags and lfExportLib in prc.loc.flags) or
            (prc.kind == skMethod):
          # due to a bug/limitation in the lambda lifting, unused inner procs
          # are not transformed correctly. We work around this issue (#411) here
          # by ensuring it's no inner proc (owner is a module).
          # Generate proc even if empty body, bugfix #11651.
          genProc(p.module, prc)
  of nkParForStmt: genParForStmt(p, n)
  of nkState: genState(p, n)
  of nkGotoState:
    # simply never set it back to 0 here from here on...
    inc p.splitDecls
    genGotoState(p, n)
  of nkBreakState: genBreakState(p, n, d)
  of nkMixinStmt, nkBindStmt: discard
  else: internalError(p.config, n.info, "expr(" & $n.kind & "); unknown node kind")

proc getDefaultValue(p: BProc; typ: PType; info: TLineInfo; result: var Builder) =
  var t = skipTypes(typ, abstractRange+{tyOwned}-{tyTypeDesc})
  case t.kind
  of tyBool: result.add rope"NIM_FALSE"
  of tyEnum, tyChar, tyInt..tyInt64, tyUInt..tyUInt64: result.addIntValue(0)
  of tyFloat..tyFloat128: result.addFloatValue(0.0)
  of tyCstring, tyVar, tyLent, tyPointer, tyPtr, tyUntyped,
     tyTyped, tyTypeDesc, tyStatic, tyRef, tyNil:
    result.add rope"NIM_NIL"
  of tyString, tySequence:
    if optSeqDestructors in p.config.globalOptions:
      var seqInit: StructInitializer
      result.addStructInitializer(seqInit, kind = siOrderedStruct):
        result.addField(seqInit, name = "len"):
          result.addIntValue(0)
        result.addField(seqInit, name = "p"):
          result.add("NIM_NIL")
    else:
      result.add "NIM_NIL"
  of tyProc:
    if t.callConv != ccClosure:
      result.add "NIM_NIL"
    else:
      var closureInit: StructInitializer
      result.addStructInitializer(closureInit, kind = siOrderedStruct):
        result.addField(closureInit, name = "ClP_0"):
          result.add("NIM_NIL")
        result.addField(closureInit, name = "ClE_0"):
          result.add("NIM_NIL")
  of tyObject:
    var objInit: StructInitializer
    result.addStructInitializer(objInit, kind = siOrderedStruct):
      getNullValueAuxT(p, t, t, t.n, nil, result, objInit, true, info)
  of tyTuple:
    var tupleInit: StructInitializer
    result.addStructInitializer(tupleInit, kind = siOrderedStruct):
      if p.vccAndC and t.isEmptyTupleType:
        result.addField(tupleInit, name = "dummy"):
          result.addIntValue(0)
      for i, a in t.ikids:
        result.addField(tupleInit, name = "Field" & $i):
          getDefaultValue(p, a, info, result)
  of tyArray:
    var arrInit: StructInitializer
    result.addStructInitializer(arrInit, kind = siArray):
      for i in 0..<toInt(lengthOrd(p.config, t.indexType)):
        result.addField(arrInit, name = ""):
          getDefaultValue(p, t.elementType, info, result)
    #result = rope"{}"
  of tyOpenArray, tyVarargs:
    var openArrInit: StructInitializer
    result.addStructInitializer(openArrInit, kind = siOrderedStruct):
      result.addField(openArrInit, name = "Field0"):
        result.add("NIM_NIL")
      result.addField(openArrInit, name = "Field1"):
        result.addIntValue(0)
  of tySet:
    if mapSetType(p.config, t) == ctArray:
      var setInit: StructInitializer
      result.addStructInitializer(setInit, kind = siArray):
        discard
    else: result.addIntValue(0)
  else:
    globalError(p.config, info, "cannot create null element for: " & $t.kind)

proc isEmptyCaseObjectBranch(n: PNode): bool =
  for it in n:
    if it.kind == nkSym and not isEmptyType(it.sym.typ): return false
  return true

proc getNullValueAux(p: BProc; t: PType; obj, constOrNil: PNode,
                     result: var Builder; init: var StructInitializer;
                     isConst: bool, info: TLineInfo) =
  case obj.kind
  of nkRecList:
    let isUnion = tfUnion in t.flags
    for it in obj.sons:
      getNullValueAux(p, t, it, constOrNil, result, init, isConst, info)
      if isUnion:
        # generate only 1 field for default value of union
        return
  of nkRecCase:
    getNullValueAux(p, t, obj[0], constOrNil, result, init, isConst, info)
    var branch = Zero
    if constOrNil != nil:
      ## find kind value, default is zero if not specified
      for i in 1..<constOrNil.len:
        if constOrNil[i].kind == nkExprColonExpr:
          if constOrNil[i][0].sym.name.id == obj[0].sym.name.id:
            branch = getOrdValue(constOrNil[i][1])
            break
        elif i == obj[0].sym.position:
          branch = getOrdValue(constOrNil[i])
          break

    let selectedBranch = caseObjDefaultBranch(obj, branch)
    let b = lastSon(obj[selectedBranch])
    # designated initilization is the only way to init non first element of unions
    # branches are allowed to have no members (b.len == 0), in this case they don't need initializer
    var fieldName: string = ""
    if b.kind == nkRecList and not isEmptyCaseObjectBranch(b):
      fieldName = "_" & mangleRecFieldName(p.module, obj[0].sym) & "_" & $selectedBranch
      result.addField(init, name = "<anonymous union>"):
        # XXX figure out name for the union, see use of `addAnonUnion`
        var branchInit: StructInitializer
        result.addStructInitializer(branchInit, kind = siNamedStruct):
          result.addField(branchInit, name = fieldName):
            var branchObjInit: StructInitializer
            result.addStructInitializer(branchObjInit, kind = siOrderedStruct):
              getNullValueAux(p, t, b, constOrNil, result, branchObjInit, isConst, info)
    elif b.kind == nkSym:
      fieldName = mangleRecFieldName(p.module, b.sym)
      result.addField(init, name = "<anonymous union>"):
        # XXX figure out name for the union, see use of `addAnonUnion`
        var branchInit: StructInitializer
        result.addStructInitializer(branchInit, kind = siNamedStruct):
          result.addField(branchInit, name = fieldName):
            # we need to generate the default value of the single sym,
            # to do this create a dummy wrapper initializer and recurse
            var branchFieldInit: StructInitializer
            result.addStructInitializer(branchFieldInit, kind = siWrapper):
              getNullValueAux(p, t, b, constOrNil, result, branchFieldInit, isConst, info)
    else:
      # no fields, don't initialize
      return

  of nkSym:
    let field = obj.sym
    let sname = mangleRecFieldName(p.module, field)
    result.addField(init, name = sname):
      block fieldInit:
        if constOrNil != nil:
          for i in 1..<constOrNil.len:
            if constOrNil[i].kind == nkExprColonExpr:
              assert constOrNil[i][0].kind == nkSym, "illformed object constr; the field is not a sym"
              if constOrNil[i][0].sym.name.id == field.name.id:
                genBracedInit(p, constOrNil[i][1], isConst, field.typ, result)
                break fieldInit
            elif i == field.position:
              genBracedInit(p, constOrNil[i], isConst, field.typ, result)
              break fieldInit
        # not found, produce default value:
        getDefaultValue(p, field.typ, info, result)
  else:
    localError(p.config, info, "cannot create null element for: " & $obj)

proc getNullValueAuxT(p: BProc; orig, t: PType; obj, constOrNil: PNode,
                      result: var Builder; init: var StructInitializer;
                      isConst: bool, info: TLineInfo) =
  var base = t.baseClass
  when false:
    let oldRes = result
    let oldcount = count
  if base != nil:
    base = skipTypes(base, skipPtrs)
    result.addField(init, name = "Sup"):
      var baseInit: StructInitializer
      result.addStructInitializer(baseInit, kind = siOrderedStruct):
        getNullValueAuxT(p, orig, base, base.n, constOrNil, result, baseInit, isConst, info)
  elif not isObjLackingTypeField(t):
    result.addField(init, name = "m_type"):
      if optTinyRtti in p.config.globalOptions:
        result.add genTypeInfoV2(p.module, orig, obj.info)
      else:
        result.add genTypeInfoV1(p.module, orig, obj.info)
  getNullValueAux(p, t, obj, constOrNil, result, init, isConst, info)
  when false: # referring to Sup field, hopefully not a problem
    # do not emit '{}' as that is not valid C:
    if oldcount == count: result = oldRes

proc genConstObjConstr(p: BProc; n: PNode; isConst: bool; result: var Builder) =
  let t = n.typ.skipTypes(abstractInstOwned)
  #if not isObjLackingTypeField(t) and not p.module.compileToCpp:
  #  result.addf("{$1}", [genTypeInfo(p.module, t)])
  #  inc count
  var objInit: StructInitializer
  result.addStructInitializer(objInit, kind = siOrderedStruct):
    if t.kind == tyObject:
      getNullValueAuxT(p, t, t, t.n, n, result, objInit, isConst, n.info)

proc genConstSimpleList(p: BProc, n: PNode; isConst: bool; result: var Builder) =
  var arrInit: StructInitializer
  result.addStructInitializer(arrInit, kind = siArray):
    if p.vccAndC and n.len == 0 and n.typ.kind == tyArray:
      result.addField(arrInit, name = ""):
        getDefaultValue(p, n.typ.elementType, n.info, result)
    for i in 0..<n.len:
      let it = n[i]
      var ind, val: PNode
      if it.kind == nkExprColonExpr:
        ind = it[0]
        val = it[1]
      else:
        ind = it
        val = it
      result.addField(arrInit, name = ""):
        genBracedInit(p, val, isConst, ind.typ, result)

proc genConstTuple(p: BProc, n: PNode; isConst: bool; tup: PType; result: var Builder) =
  var tupleInit: StructInitializer
  result.addStructInitializer(tupleInit, kind = siOrderedStruct):
    if p.vccAndC and n.len == 0:
      result.addField(tupleInit, name = "dummy"):
        result.addIntValue(0)
    for i in 0..<n.len:
      var it = n[i]
      if it.kind == nkExprColonExpr:
        it = it[1]
      result.addField(tupleInit, name = "Field" & $i):
        genBracedInit(p, it, isConst, tup[i], result)

proc genConstSeq(p: BProc, n: PNode, t: PType; isConst: bool; result: var Builder) =
  let base = t.skipTypes(abstractInst)[0]
  let tmpName = getTempName(p.module)

  # genBracedInit can modify cfsStrData, we need an intermediate builder:
  var def = newBuilder("")
  def.addVarWithTypeAndInitializer(
      if isConst: Const else: Global,
      name = tmpName):
    def.addSimpleStruct(p.module, name = "", baseType = ""):
      def.addField(name = "sup", typ = cgsymValue(p.module, "TGenericSeq"))
      def.addArrayField(name = "data", elementType = getTypeDesc(p.module, base), len = n.len)
  do:
    var structInit: StructInitializer
    def.addStructInitializer(structInit, kind = siOrderedStruct):
      def.addField(structInit, name = "sup"):
        var supInit: StructInitializer
        def.addStructInitializer(supInit, kind = siOrderedStruct):
          def.addField(supInit, name = "len"):
            def.add(n.len.rope)
          def.addField(supInit, name = "reserved"):
            def.add(bitOr(rope(n.len), "NIM_STRLIT_FLAG"))
      if n.len > 0:
        def.addField(structInit, name = "data"):
          var arrInit: StructInitializer
          def.addStructInitializer(arrInit, kind = siArray):
            for i in 0..<n.len:
              def.addField(arrInit, name = ""):
                genBracedInit(p, n[i], isConst, base, def)
  p.module.s[cfsStrData].add extract(def)

  result.add cCast(typ = getTypeDesc(p.module, t), value = cAddr(tmpName))

proc genConstSeqV2(p: BProc, n: PNode, t: PType; isConst: bool; result: var Builder) =
  let base = t.skipTypes(abstractInst)[0]
  let payload = getTempName(p.module)

  # genBracedInit can modify cfsStrData, we need an intermediate builder:
  var def = newBuilder("")
  def.addVarWithTypeAndInitializer(
      if isConst: AlwaysConst else: Global,
      name = payload):
    def.addSimpleStruct(p.module, name = "", baseType = ""):
      def.addField(name = "cap", typ = "NI")
      def.addArrayField(name = "data", elementType = getTypeDesc(p.module, base), len = n.len)
  do:
    var structInit: StructInitializer
    def.addStructInitializer(structInit, kind = siOrderedStruct):
      def.addField(structInit, name = "cap"):
        def.add(bitOr(rope(n.len), "NIM_STRLIT_FLAG"))
      if n.len > 0:
        def.addField(structInit, name = "data"):
          var arrInit: StructInitializer
          def.addStructInitializer(arrInit, kind = siArray):
            for i in 0..<n.len:
              def.addField(arrInit, name = ""):
                genBracedInit(p, n[i], isConst, base, def)
  p.module.s[cfsStrData].add extract(def)

  var resultInit: StructInitializer
  result.addStructInitializer(resultInit, kind = siOrderedStruct):
    result.addField(resultInit, name = "len"):
      result.addIntValue(n.len)
    result.addField(resultInit, name = "p"):
      result.add cCast(typ = ptrType(getSeqPayloadType(p.module, t)), value = cAddr(payload))

proc genBracedInit(p: BProc, n: PNode; isConst: bool; optionalType: PType; result: var Builder) =
  case n.kind
  of nkHiddenStdConv, nkHiddenSubConv:
    genBracedInit(p, n[1], isConst, n.typ, result)
  else:
    var ty = tyNone
    var typ: PType = nil
    if optionalType == nil:
      if n.kind in nkStrKinds:
        ty = tyString
      else:
        internalError(p.config, n.info, "node has no type")
    else:
      typ = skipTypes(optionalType, abstractInstOwned + {tyStatic})
      ty = typ.kind
    case ty
    of tySet:
      let cs = toBitSet(p.config, n)
      genRawSetData(cs, int(getSize(p.config, n.typ)), result)
    of tySequence:
      if optSeqDestructors in p.config.globalOptions:
        genConstSeqV2(p, n, typ, isConst, result)
      else:
        genConstSeq(p, n, typ, isConst, result)
    of tyProc:
      if typ.callConv == ccClosure and n.safeLen > 1 and n[1].kind == nkNilLit:
        # n.kind could be: nkClosure, nkTupleConstr and maybe others; `n.safeLen`
        # guards against the case of `nkSym`, refs bug #14340.
        # Conversion: nimcall -> closure.
        # this hack fixes issue that nkNilLit is expanded to {NIM_NIL,NIM_NIL}
        # this behaviour is needed since closure_var = nil must be
        # expanded to {NIM_NIL,NIM_NIL}
        # in VM closures are initialized with nkPar(nkNilLit, nkNilLit)
        # leading to duplicate code like this:
        # "{NIM_NIL,NIM_NIL}, {NIM_NIL,NIM_NIL}"
        var closureInit: StructInitializer
        result.addStructInitializer(closureInit, kind = siOrderedStruct):
          result.addField(closureInit, name = "ClP_0"):
            if n[0].kind == nkNilLit:
              result.add("NIM_NIL")
            else:
              var d: TLoc = initLocExpr(p, n[0])
              result.add(cCast(typ = getClosureType(p.module, typ, clHalfWithEnv), value = rdLoc(d)))
          result.addField(closureInit, name = "ClE_0"):
            result.add("NIM_NIL")
      else:
        var d: TLoc = initLocExpr(p, n)
        result.add rdLoc(d)
    of tyArray, tyVarargs:
      genConstSimpleList(p, n, isConst, result)
    of tyTuple:
      genConstTuple(p, n, isConst, typ, result)
    of tyOpenArray:
      if n.kind != nkBracket:
        internalError(p.config, n.info, "const openArray expression is not an array construction")

      let payload = getTempName(p.module)
      let ctype = getTypeDesc(p.module, typ.elementType)
      let arrLen = n.len
      # genConstSimpleList can modify cfsStrData, we need an intermediate builder:
      var data = newBuilder("")
      data.addArrayVarWithInitializer(
          kind = if isConst: AlwaysConst else: Global,
          name = payload, elementType = ctype, len = arrLen):
        genConstSimpleList(p, n, isConst, data)
      p.module.s[cfsStrData].add(extract(data))
      var openArrInit: StructInitializer
      result.addStructInitializer(openArrInit, kind = siOrderedStruct):
        result.addField(openArrInit, name = "Field0"):
          result.add(cCast(typ = ptrType(ctype), value = cAddr(payload)))
        result.addField(openArrInit, name = "Field1"):
          result.addIntValue(arrLen)

    of tyObject:
      genConstObjConstr(p, n, isConst, result)
    of tyString, tyCstring:
      if optSeqDestructors in p.config.globalOptions and n.kind != nkNilLit and ty == tyString:
        genStringLiteralV2Const(p.module, n, isConst, result)
      else:
        var d: TLoc = initLocExpr(p, n)
        result.add rdLoc(d)
    else:
      var d: TLoc = initLocExpr(p, n)
      result.add rdLoc(d)

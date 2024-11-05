#
#
#           The Nim Compiler
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# Built-in types and compilerprocs are registered here.

import
  ast, astalgo, msgs, platform, idents,
  modulegraphs, lineinfos

export createMagic

proc nilOrSysInt*(g: ModuleGraph): PType = g.sysTypes[tyInt]

proc newSysType(g: ModuleGraph; kind: TTypeKind, size: int): PType =
  result = newType(kind, g.idgen, g.systemModule)
  result.size = size
  result.align = size.int16

proc getSysSym*(g: ModuleGraph; info: TLineInfo; name: string): PSym =
  result = systemModuleSym(g, getIdent(g.cache, name))
  if result == nil:
    localError(g.config, info, "system module needs: " & name)
    result = newSym(skError, getIdent(g.cache, name), g.idgen, g.systemModule, g.systemModule.info, {})
    result.typ = newType(tyError, g.idgen, g.systemModule)

proc getSysMagic*(g: ModuleGraph; info: TLineInfo; name: string, m: TMagic): PSym =
  result = nil
  let id = getIdent(g.cache, name)
  for r in systemModuleSyms(g, id):
    if r.magic == m:
      # prefer the tyInt variant:
      if r.typ.returnType != nil and r.typ.returnType.kind == tyInt: return r
      result = r
  if result != nil: return result
  localError(g.config, info, "system module needs: " & name)
  result = newSym(skError, id, g.idgen, g.systemModule, g.systemModule.info, {})
  result.typ = newType(tyError, g.idgen, g.systemModule)

proc sysTypeFromName*(g: ModuleGraph; info: TLineInfo; name: string): PType =
  result = getSysSym(g, info, name).typ

proc getSysType*(g: ModuleGraph; info: TLineInfo; kind: TTypeKind): PType =
  template sysTypeFromName(s: string): untyped = sysTypeFromName(g, info, s)
  result = g.sysTypes[kind]
  if result == nil:
    case kind
    of tyVoid: result = sysTypeFromName("void")
    of tyInt: result = sysTypeFromName("int")
    of tyInt8: result = sysTypeFromName("int8")
    of tyInt16: result = sysTypeFromName("int16")
    of tyInt32: result = sysTypeFromName("int32")
    of tyInt64: result = sysTypeFromName("int64")
    of tyUInt: result = sysTypeFromName("uint")
    of tyUInt8: result = sysTypeFromName("uint8")
    of tyUInt16: result = sysTypeFromName("uint16")
    of tyUInt32: result = sysTypeFromName("uint32")
    of tyUInt64: result = sysTypeFromName("uint64")
    of tyFloat: result = sysTypeFromName("float")
    of tyFloat32: result = sysTypeFromName("float32")
    of tyFloat64: result = sysTypeFromName("float64")
    of tyFloat128: result = sysTypeFromName("float128")
    of tyBool: result = sysTypeFromName("bool")
    of tyChar: result = sysTypeFromName("char")
    of tyString: result = sysTypeFromName("string")
    of tyCstring: result = sysTypeFromName("cstring")
    of tyPointer: result = sysTypeFromName("pointer")
    of tyNil: result = newSysType(g, tyNil, g.config.target.ptrSize)
    else: internalError(g.config, "request for typekind: " & $kind)
    g.sysTypes[kind] = result
  if result.kind != kind:
    if kind == tyFloat64 and result.kind == tyFloat: discard # because of aliasing
    else:
      internalError(g.config, "wanted: " & $kind & " got: " & $result.kind)
  if result == nil: internalError(g.config, "type not found: " & $kind)

proc resetSysTypes*(g: ModuleGraph) =
  g.systemModule = nil
  g.compilerprocs = initStrTable()
  g.exposed = initStrTable()
  for i in low(g.sysTypes)..high(g.sysTypes):
    g.sysTypes[i] = nil

proc getFloatLitType*(g: ModuleGraph; literal: PNode): PType =
  # for now we do not cache these:
  result = newSysType(g, tyFloat, size=8)
  result.n = literal

proc skipIntLit*(t: PType; id: IdGenerator): PType {.inline.} =
  if t.n != nil and t.kind in {tyInt, tyFloat}:
    result = copyType(t, id, t.owner)
    result.n = nil
  else:
    result = t

proc addSonSkipIntLit*(father, son: PType; id: IdGenerator) =
  let s = son.skipIntLit(id)
  father.add(s)
  propagateToOwner(father, s)

proc makeVarType*(owner: PSym; baseType: PType; idgen: IdGenerator; kind = tyVar): PType =
  if baseType.kind == kind:
    result = baseType
  else:
    result = newType(kind, idgen, owner)
    addSonSkipIntLit(result, baseType, idgen)

proc getCompilerProc*(g: ModuleGraph; name: string): PSym =
  let ident = getIdent(g.cache, name)
  result = strTableGet(g.compilerprocs, ident)
  if result == nil:
    result = loadCompilerProc(g, name)

proc registerCompilerProc*(g: ModuleGraph; s: PSym) =
  strTableAdd(g.compilerprocs, s)

proc registerNimScriptSymbol*(g: ModuleGraph; s: PSym) =
  # Nimscript symbols must be al unique:
  let conflict = strTableGet(g.exposed, s.name)
  if conflict == nil:
    strTableAdd(g.exposed, s)
  else:
    localError(g.config, s.info,
      "symbol conflicts with other .exportNims symbol at: " & g.config$conflict.info)

proc getNimScriptSymbol*(g: ModuleGraph; name: string): PSym =
  strTableGet(g.exposed, getIdent(g.cache, name))

proc resetNimScriptSymbols*(g: ModuleGraph) = g.exposed = initStrTable()

proc getMagicEqSymForType*(g: ModuleGraph; t: PType; info: TLineInfo): PSym =
  case t.kind
  of tyInt,  tyInt8, tyInt16, tyInt32, tyInt64,
     tyUInt, tyUInt8, tyUInt16, tyUInt32, tyUInt64:
    result = getSysMagic(g, info, "==", mEqI)
  of tyEnum:
    result = getSysMagic(g, info, "==", mEqEnum)
  of tyBool:
    result = getSysMagic(g, info, "==", mEqB)
  of tyRef, tyPtr, tyPointer:
    result = getSysMagic(g, info, "==", mEqRef)
  of tyString:
    result = getSysMagic(g, info, "==", mEqStr)
  of tyChar:
    result = getSysMagic(g, info, "==", mEqCh)
  of tySet:
    result = getSysMagic(g, info, "==", mEqSet)
  of tyProc:
    result = getSysMagic(g, info, "==", mEqProc)
  else:
    result = nil
    globalError(g.config, info,
      "can't find magic equals operator for type kind " & $t.kind)

proc makePtrType*(baseType: PType; idgen: IdGenerator): PType =
  result = newType(tyPtr, idgen, baseType.owner)
  addSonSkipIntLit(result, baseType, idgen)

proc makeAddr*(n: PNode; idgen: IdGenerator): PNode =
  if n.kind == nkHiddenAddr:
    result = n
  else:
    result = newTree(nkHiddenAddr, n)
    result.typ() = makePtrType(n.typ, idgen)

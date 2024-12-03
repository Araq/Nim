#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This file implements the FFI part of the evaluator for Nim code.

import ast, types, options, msgs, lineinfos
from std/os import getAppFilename
import libffi/libffi

import std/[tables, dynlib]

when defined(windows):
  const libcDll = "msvcrt.dll"
elif defined(linux):
  const libcDll = "libc.so(.6|.5|)"
elif defined(openbsd):
  const libcDll = "/usr/lib/libc.so(.95.1|)"
elif defined(bsd):
  const libcDll = "/lib/libc.so.7"
elif defined(osx):
  const libcDll = "/usr/lib/libSystem.dylib"
else:
  {.error: "`libcDll` not implemented on this platform".}

type
  TDllCache = tables.Table[string, LibHandle]
var
  gDllCache = initTable[string, LibHandle]()

when defined(windows):
  var gExeHandle = loadLib(getAppFilename())
else:
  var gExeHandle = loadLib()

proc getDll(conf: ConfigRef, cache: var TDllCache; dll: string; info: TLineInfo): pointer =
  result = nil
  if dll in cache:
    return cache[dll]
  var libs: seq[string] = @[]
  libCandidates(dll, libs)
  for c in libs:
    result = loadLib(c)
    if not result.isNil: break
  if result.isNil:
    globalError(conf, info, "cannot load: " & dll)
  cache[dll] = result

const
  nkPtrLit = nkIntLit # hopefully we can get rid of this hack soon

proc importcSymbol*(conf: ConfigRef, sym: PSym): PNode =
  let name = sym.cname # $sym.loc.r would point to internal name
  # the AST does not support untyped pointers directly, so we use an nkIntLit
  # that contains the address instead:
  result = newNodeIT(nkPtrLit, sym.info, sym.typ)
  when true:
    var libPathMsg = ""
    let lib = sym.annex
    if lib != nil and lib.path.kind notin {nkStrLit..nkTripleStrLit}:
      globalError(conf, sym.info, "dynlib needs to be a string lit")
    var theAddr: pointer = nil
    if (lib.isNil or lib.kind == libHeader) and not gExeHandle.isNil:
      libPathMsg = "current exe: " & getAppFilename() & " nor libc: " & libcDll
      # first try this exe itself:
      theAddr = gExeHandle.symAddr(name.cstring)
      # then try libc:
      if theAddr.isNil:
        let dllhandle = getDll(conf, gDllCache, libcDll, sym.info)
        theAddr = dllhandle.symAddr(name.cstring)
    elif not lib.isNil:
      let dll = if lib.kind == libHeader: libcDll else: lib.path.strVal
      libPathMsg = dll
      let dllhandle = getDll(conf, gDllCache, dll, sym.info)
      theAddr = dllhandle.symAddr(name.cstring)
    if theAddr.isNil: globalError(conf, sym.info,
      "cannot import symbol: " & name & " from " & libPathMsg)
    result.intVal = cast[int](theAddr)

proc mapType(conf: ConfigRef, t: ast.PType): ptr libffi.Type =
  if t == nil: return addr libffi.type_void

  case t.kind
  of tyBool, tyEnum, tyChar, tyInt..tyInt64, tyUInt..tyUInt64, tySet:
    case getSize(conf, t)
    of 1: result = addr libffi.type_uint8
    of 2: result = addr libffi.type_sint16
    of 4: result = addr libffi.type_sint32
    of 8: result = addr libffi.type_sint64
    else: result = nil
  of tyFloat, tyFloat64: result = addr libffi.type_double
  of tyFloat32: result = addr libffi.type_float
  of tyVar, tyLent, tyPointer, tyPtr, tyRef, tyCstring, tySequence, tyString, tyUntyped,
     tyTyped, tyTypeDesc, tyProc, tyArray, tyStatic, tyNil:
    result = addr libffi.type_pointer
  of tyDistinct, tyAlias, tySink:
    result = mapType(conf, t.skipModifier)
  else:
    result = nil
  # too risky:
  #of tyFloat128: result = addr libffi.type_longdouble

proc mapCallConv(conf: ConfigRef, cc: TCallingConvention, info: TLineInfo): TABI =
  case cc
  of ccNimCall: result = DEFAULT_ABI
  of ccStdCall: result = when defined(windows) and defined(x86): STDCALL else: DEFAULT_ABI
  of ccCDecl: result = DEFAULT_ABI
  else:
    result = default(TABI)
    globalError(conf, info, "cannot map calling convention to FFI")

template rd(typ, p: untyped): untyped = (cast[ptr typ](p))[]
template wr(typ, p, v: untyped): untyped = (cast[ptr typ](p))[] = v
template `+!`(x, y: untyped): untyped =
  cast[pointer](cast[int](x) + y)

proc packSize(conf: ConfigRef, v: PNode, typ: PType): int =
  ## computes the size of the blob
  case typ.kind
  of tyPtr, tyRef, tyVar, tyLent:
    if v.kind in {nkNilLit, nkPtrLit}:
      result = sizeof(pointer)
    else:
      result = sizeof(pointer) + packSize(conf, v[0], typ.elementType)
  of tyDistinct, tyGenericInst, tyAlias, tySink:
    result = packSize(conf, v, typ.skipModifier)
  of tyArray:
    # consider: ptr array[0..1000_000, int] which is common for interfacing;
    # we use the real length here instead
    if v.kind in {nkNilLit, nkPtrLit}:
      result = sizeof(pointer)
    elif v.len != 0:
      result = v.len * packSize(conf, v[0], typ.elementType)
    else:
      result = 0
  else:
    result = getSize(conf, typ).int

proc pack(conf: ConfigRef, v: PNode, typ: PType, res: pointer)

proc getField(conf: ConfigRef, n: PNode; position: int): PSym =
  case n.kind
  of nkRecList:
    result = nil
    for i in 0..<n.len:
      result = getField(conf, n[i], position)
      if result != nil: return
  of nkRecCase:
    result = getField(conf, n[0], position)
    if result != nil: return
    for i in 1..<n.len:
      case n[i].kind
      of nkOfBranch, nkElse:
        result = getField(conf, lastSon(n[i]), position)
        if result != nil: return
      else: internalError(conf, n.info, "getField(record case branch)")
  of nkSym:
    if n.sym.position == position: result = n.sym
    else: result = nil
  else: result = nil

proc packObject(conf: ConfigRef, x: PNode, typ: PType, res: pointer) =
  internalAssert conf, x.kind in {nkObjConstr, nkPar, nkTupleConstr}
  # compute the field's offsets:
  discard getSize(conf, typ)
  for i in ord(x.kind == nkObjConstr)..<x.len:
    var it = x[i]
    if it.kind == nkExprColonExpr:
      internalAssert conf, it[0].kind == nkSym
      let field = it[0].sym
      pack(conf, it[1], field.typ, res +! field.offset)
    elif typ.n != nil:
      let field = getField(conf, typ.n, i)
      pack(conf, it, field.typ, res +! field.offset)
    else:
      # XXX: todo
      globalError(conf, x.info, "cannot pack unnamed tuple")

const maxPackDepth = 20
var packRecCheck = 0

proc pack(conf: ConfigRef, v: PNode, typ: PType, res: pointer) =
  template awr(typ, v: untyped): untyped =
    wr(typ, res, v)

  case typ.kind
  of tyBool: awr(bool, v.intVal != 0)
  of tyChar: awr(char, v.intVal.chr)
  of tyInt:  awr(int, v.intVal.int)
  of tyInt8: awr(int8, v.intVal.int8)
  of tyInt16: awr(int16, v.intVal.int16)
  of tyInt32: awr(int32, v.intVal.int32)
  of tyInt64: awr(int64, v.intVal.int64)
  of tyUInt: awr(uint, v.intVal.uint)
  of tyUInt8: awr(uint8, v.intVal.uint8)
  of tyUInt16: awr(uint16, v.intVal.uint16)
  of tyUInt32: awr(uint32, v.intVal.uint32)
  of tyUInt64: awr(uint64, v.intVal.uint64)
  of tyEnum, tySet:
    case getSize(conf, v.typ)
    of 1: awr(uint8, v.intVal.uint8)
    of 2: awr(uint16, v.intVal.uint16)
    of 4: awr(int32, v.intVal.int32)
    of 8: awr(int64, v.intVal.int64)
    else:
      globalError(conf, v.info, "cannot map value to FFI (tyEnum, tySet)")
  of tyFloat: awr(float, v.floatVal)
  of tyFloat32: awr(float32, v.floatVal)
  of tyFloat64: awr(float64, v.floatVal)

  of tyPointer, tyProc,  tyCstring, tyString:
    if v.kind == nkNilLit:
      # nothing to do since the memory is 0 initialized anyway
      discard
    elif v.kind == nkPtrLit:
      awr(pointer, cast[pointer](v.intVal))
    elif v.kind in {nkStrLit..nkTripleStrLit}:
      awr(cstring, cstring(v.strVal))
    else:
      globalError(conf, v.info, "cannot map pointer/proc value to FFI")
  of tyPtr, tyRef, tyVar, tyLent:
    if v.kind == nkNilLit:
      # nothing to do since the memory is 0 initialized anyway
      discard
    elif v.kind == nkPtrLit:
      awr(pointer, cast[pointer](v.intVal))
    else:
      if packRecCheck > maxPackDepth:
        packRecCheck = 0
        globalError(conf, v.info, "cannot map value to FFI " & typeToString(v.typ))
      inc packRecCheck
      pack(conf, v[0], typ.elementType, res +! sizeof(pointer))
      dec packRecCheck
      awr(pointer, res +! sizeof(pointer))
  of tyArray:
    let baseSize = getSize(conf, typ.elementType)
    for i in 0..<v.len:
      pack(conf, v[i], typ.elementType, res +! i * baseSize)
  of tyObject, tyTuple:
    packObject(conf, v, typ, res)
  of tyNil:
    discard
  of tyDistinct, tyGenericInst, tyAlias, tySink:
    pack(conf, v, typ.skipModifier, res)
  else:
    globalError(conf, v.info, "cannot map value to FFI " & typeToString(v.typ))

proc unpack(conf: ConfigRef, x: pointer, typ: PType, n: PNode): PNode

proc unpackObjectAdd(conf: ConfigRef, x: pointer, n, result: PNode) =
  case n.kind
  of nkRecList:
    for i in 0..<n.len:
      unpackObjectAdd(conf, x, n[i], result)
  of nkRecCase:
    globalError(conf, result.info, "case objects cannot be unpacked")
  of nkSym:
    var pair = newNodeI(nkExprColonExpr, result.info, 2)
    pair[0] = n
    pair[1] = unpack(conf, x +! n.sym.offset, n.sym.typ, nil)
    #echo "offset: ", n.sym.name.s, " ", n.sym.offset
    result.add pair
  else: discard

proc unpackObject(conf: ConfigRef, x: pointer, typ: PType, n: PNode): PNode =
  # compute the field's offsets:
  discard getSize(conf, typ)

  # iterate over any actual field of 'n' ... if n is nil we need to create
  # the nkPar node:
  if n.isNil:
    result = newNode(nkTupleConstr)
    result.typ() = typ
    if typ.n.isNil:
      internalError(conf, "cannot unpack unnamed tuple")
    unpackObjectAdd(conf, x, typ.n, result)
  else:
    result = n
    if result.kind notin {nkObjConstr, nkPar, nkTupleConstr}:
      globalError(conf, n.info, "cannot map value from FFI")
    if typ.n.isNil:
      globalError(conf, n.info, "cannot unpack unnamed tuple")
    for i in ord(n.kind == nkObjConstr)..<n.len:
      var it = n[i]
      if it.kind == nkExprColonExpr:
        internalAssert conf, it[0].kind == nkSym
        let field = it[0].sym
        it[1] = unpack(conf, x +! field.offset, field.typ, it[1])
      else:
        let field = getField(conf, typ.n, i)
        n[i] = unpack(conf, x +! field.offset, field.typ, it)

proc unpackArray(conf: ConfigRef, x: pointer, typ: PType, n: PNode): PNode =
  if n.isNil:
    result = newNode(nkBracket)
    result.typ() = typ
    newSeq(result.sons, lengthOrd(conf, typ).toInt)
  else:
    result = n
    if result.kind != nkBracket:
      globalError(conf, n.info, "cannot map value from FFI")
  let baseSize = getSize(conf, typ.elementType)
  for i in 0..<result.len:
    result[i] = unpack(conf, x +! i * baseSize, typ.elementType, result[i])

proc canonNodeKind(k: TNodeKind): TNodeKind =
  case k
  of nkCharLit..nkUInt64Lit: result = nkIntLit
  of nkFloatLit..nkFloat128Lit: result = nkFloatLit
  of nkStrLit..nkTripleStrLit: result = nkStrLit
  else: result = k

proc unpack(conf: ConfigRef, x: pointer, typ: PType, n: PNode): PNode =
  template aw(k, v, field: untyped): untyped =
    if n.isNil:
      result = newNode(k)
      result.typ() = typ
    else:
      # check we have the right field:
      result = n
      if result.kind.canonNodeKind != k.canonNodeKind:
        #echo "expected ", k, " but got ", result.kind
        #debug result
        return newNodeI(nkExceptBranch, n.info)
        #globalError(conf, n.info, "cannot map value from FFI")
    result.field = v

  template setNil() =
    if n.isNil:
      result = newNode(nkNilLit)
      result.typ() = typ
    else:
      reset n[]
      result = n
      result[] = TNode(kind: nkNilLit)
      result.typ() = typ

  template awi(kind, v: untyped): untyped = aw(kind, v, intVal)
  template awf(kind, v: untyped): untyped = aw(kind, v, floatVal)
  template aws(kind, v: untyped): untyped = aw(kind, v, strVal)

  case typ.kind
  of tyBool: awi(nkIntLit, rd(bool, x).ord)
  of tyChar: awi(nkCharLit, rd(char, x).ord)
  of tyInt:  awi(nkIntLit, rd(int, x))
  of tyInt8: awi(nkInt8Lit, rd(int8, x))
  of tyInt16: awi(nkInt16Lit, rd(int16, x))
  of tyInt32: awi(nkInt32Lit, rd(int32, x))
  of tyInt64: awi(nkInt64Lit, rd(int64, x))
  of tyUInt: awi(nkUIntLit, rd(uint, x).BiggestInt)
  of tyUInt8: awi(nkUInt8Lit, rd(uint8, x).BiggestInt)
  of tyUInt16: awi(nkUInt16Lit, rd(uint16, x).BiggestInt)
  of tyUInt32: awi(nkUInt32Lit, rd(uint32, x).BiggestInt)
  of tyUInt64: awi(nkUInt64Lit, rd(uint64, x).BiggestInt)
  of tyEnum:
    case getSize(conf, typ)
    of 1: awi(nkIntLit, rd(uint8, x).BiggestInt)
    of 2: awi(nkIntLit, rd(uint16, x).BiggestInt)
    of 4: awi(nkIntLit, rd(int32, x).BiggestInt)
    of 8: awi(nkIntLit, rd(int64, x).BiggestInt)
    else:
      result = nil
      globalError(conf, n.info, "cannot map value from FFI (tyEnum, tySet)")
  of tyFloat: awf(nkFloatLit, rd(float, x))
  of tyFloat32: awf(nkFloat32Lit, rd(float32, x))
  of tyFloat64: awf(nkFloat64Lit, rd(float64, x))
  of tyPointer, tyProc:
    let p = rd(pointer, x)
    if p.isNil:
      setNil()
    elif n != nil and n.kind == nkStrLit:
      # we passed a string literal as a pointer; however strings are already
      # in their unboxed representation so nothing it to be unpacked:
      result = n
    else:
      awi(nkPtrLit, cast[int](p))
  of tyPtr, tyRef, tyVar, tyLent:
    let p = rd(pointer, x)
    if p.isNil:
      setNil()
    elif n == nil or n.kind == nkPtrLit:
      awi(nkPtrLit, cast[int](p))
    elif n != nil and n.len == 1:
      internalAssert(conf, n.kind == nkRefTy)
      n[0] = unpack(conf, p, typ.elementType, n[0])
      result = n
    else:
      result = nil
      globalError(conf, n.info, "cannot map value from FFI " & typeToString(typ))
  of tyObject, tyTuple:
    result = unpackObject(conf, x, typ, n)
  of tyArray:
    result = unpackArray(conf, x, typ, n)
  of tyCstring, tyString:
    let p = rd(cstring, x)
    if p.isNil:
      setNil()
    else:
      aws(nkStrLit, $p)
  of tyNil:
    setNil()
  of tyDistinct, tyGenericInst, tyAlias, tySink:
    result = unpack(conf, x, typ.skipModifier, n)
  else:
    # XXX what to do with 'array' here?
    result = nil
    globalError(conf, n.info, "cannot map value from FFI " & typeToString(typ))

proc fficast*(conf: ConfigRef, x: PNode, destTyp: PType): PNode =
  if x.kind == nkPtrLit and x.typ.kind in {tyPtr, tyRef, tyVar, tyLent, tyPointer,
                                           tyProc, tyCstring, tyString,
                                           tySequence}:
    result = newNodeIT(x.kind, x.info, destTyp)
    result.intVal = x.intVal
  elif x.kind == nkNilLit:
    result = newNodeIT(x.kind, x.info, destTyp)
  else:
    # we play safe here and allocate the max possible size:
    let size = max(packSize(conf, x, x.typ), packSize(conf, x, destTyp))
    var a = alloc0(size)
    pack(conf, x, x.typ, a)
    # cast through a pointer needs a new inner object:
    let y = if x.kind == nkRefTy: newNodeI(nkRefTy, x.info, 1)
            else: x.copyTree
    y.typ() = x.typ
    result = unpack(conf, a, destTyp, y)
    dealloc a

proc callForeignFunction*(conf: ConfigRef, call: PNode): PNode =
  internalAssert conf, call[0].kind == nkPtrLit

  var cif: TCif = default(TCif)
  var sig: ParamList = default(ParamList)
  # use the arguments' types for varargs support:
  for i in 1..<call.len:
    sig[i-1] = mapType(conf, call[i].typ)
    if sig[i-1].isNil:
      globalError(conf, call.info, "cannot map FFI type")

  let typ = call[0].typ
  if prep_cif(cif, mapCallConv(conf, typ.callConv, call.info), cuint(call.len-1),
              mapType(conf, typ.returnType), sig) != OK:
    globalError(conf, call.info, "error in FFI call")

  var args: ArgList = default(ArgList)
  let fn = cast[pointer](call[0].intVal)
  for i in 1..<call.len:
    var t = call[i].typ
    args[i-1] = alloc0(packSize(conf, call[i], t))
    pack(conf, call[i], t, args[i-1])
  let retVal = if isEmptyType(typ.returnType): pointer(nil)
               else: alloc(getSize(conf, typ.returnType).int)

  libffi.call(cif, fn, retVal, args)

  if retVal.isNil:
    result = newNode(nkEmpty)
  else:
    result = unpack(conf, retVal, typ.returnType, nil)
    result.info = call.info

  if retVal != nil: dealloc retVal
  for i in 1..<call.len:
    call[i] = unpack(conf, args[i-1], typ[i], call[i])
    dealloc args[i-1]

proc callForeignFunction*(conf: ConfigRef, fn: PNode, fntyp: PType,
                          args: var TNodeSeq, start, len: int,
                          info: TLineInfo): PNode =
  internalAssert conf, fn.kind == nkPtrLit

  var cif: TCif = default(TCif)
  var sig: ParamList = default(ParamList)
  for i in 0..len-1:
    var aTyp = args[i+start].typ
    if aTyp.isNil:
      internalAssert conf, i+1 < fntyp.len
      aTyp = fntyp[i+1]
      args[i+start].typ() = aTyp
    sig[i] = mapType(conf, aTyp)
    if sig[i].isNil: globalError(conf, info, "cannot map FFI type")

  if prep_cif(cif, mapCallConv(conf, fntyp.callConv, info), cuint(len),
              mapType(conf, fntyp[0]), sig) != OK:
    globalError(conf, info, "error in FFI call")

  var cargs: ArgList = default(ArgList)
  let fn = cast[pointer](fn.intVal)
  for i in 0..len-1:
    let t = args[i+start].typ
    cargs[i] = alloc0(packSize(conf, args[i+start], t))
    pack(conf, args[i+start], t, cargs[i])
  let retVal = if isEmptyType(fntyp[0]): pointer(nil)
               else: alloc(getSize(conf, fntyp[0]).int)

  libffi.call(cif, fn, retVal, cargs)

  if retVal.isNil:
    result = newNode(nkEmpty)
  else:
    result = unpack(conf, retVal, fntyp[0], nil)
    result.info = info

  if retVal != nil: dealloc retVal
  for i in 0..len-1:
    let t = args[i+start].typ
    args[i+start] = unpack(conf, cargs[i], t, args[i+start])
    dealloc cargs[i]

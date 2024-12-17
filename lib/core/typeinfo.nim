#
#
#            Nim's Runtime Library
#        (c) Copyright 2013 Dominik Picheta, Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements an interface to Nim's `runtime type information`:idx:
## (`RTTI`:idx:). See the `marshal <marshal.html>`_ module for an example of
## what this allows you to do.
##
## .. note:: Even though `Any` and its operations hide the nasty low level
##   details from its users, it remains inherently unsafe! Also, Nim's
##   runtime type information will evolve and may eventually be deprecated.
##   As an alternative approach to programmatically understanding and
##   manipulating types, consider using the `macros <macros.html>`_ module to
##   work with the types' AST representation at compile time. See for example
##   the `getTypeImpl proc <macros.html#getTypeImpl,NimNode>`_. As an alternative
##   approach to storing arbitrary types at runtime, consider using generics.

runnableExamples:
  var x: Any

  var i = 42
  x = i.toAny
  assert x.kind == akInt
  assert x.getInt == 42

  var s = @[1, 2, 3]
  x = s.toAny
  assert x.kind == akSequence
  assert x.len == 3

{.push hints: off.}

include "system/inclrtl.nim"
include "system/hti.nim"

{.pop.}

when defined(nimPreviewSlimSystem):
  import std/assertions


type
  AnyKind* = enum       ## The kind of `Any`.
    akNone = 0,         ## invalid
    akBool = 1,         ## bool
    akChar = 2,         ## char
    akEnum = 14,        ## enum
    akArray = 16,       ## array
    akObject = 17,      ## object
    akTuple = 18,       ## tuple
    akSet = 19,         ## set
    akRange = 20,       ## range
    akPtr = 21,         ## ptr
    akRef = 22,         ## ref
    akSequence = 24,    ## sequence
    akProc = 25,        ## proc
    akPointer = 26,     ## pointer
    akString = 28,      ## string
    akCString = 29,     ## cstring
    akInt = 31,         ## int
    akInt8 = 32,        ## int8
    akInt16 = 33,       ## int16
    akInt32 = 34,       ## int32
    akInt64 = 35,       ## int64
    akFloat = 36,       ## float
    akFloat32 = 37,     ## float32
    akFloat64 = 38,     ## float64
    akFloat128 = 39,    ## float128
    akUInt = 40,        ## uint
    akUInt8 = 41,       ## uint8
    akUInt16 = 42,      ## uin16
    akUInt32 = 43,      ## uint32
    akUInt64 = 44,      ## uint64
#    akOpt = 44+18       ## the builtin 'opt' type.

  Any* = object
    ## A type that can represent any nim value.
    ##
    ## .. danger:: The wrapped value can be modified with its wrapper! This means
    ##   that `Any` keeps a non-traced pointer to its wrapped value and
    ##   **must not** live longer than its wrapped value.
    value: pointer
    when defined(js):
      rawType: PNimType
    else:
      rawTypePtr: pointer

  ppointer = ptr pointer
  pbyteArray = ptr array[0xffff, uint8]

when not defined(gcDestructors):
  type
    TGenericSeq {.importc.} = object
      len, space: int
      when defined(gogc):
        elemSize: int
    PGenSeq = ptr TGenericSeq

  when defined(gogc):
    const GenericSeqSize = 3 * sizeof(int)
  else:
    const GenericSeqSize = 2 * sizeof(int)

else:
  include system/seqs_v2_reimpl

from std/private/strimpl import cmpNimIdentifier

when not defined(js):
  template rawType(x: Any): PNimType =
    cast[PNimType](x.rawTypePtr)

  template `rawType=`(x: var Any, p: PNimType) =
    x.rawTypePtr = cast[pointer](p)

proc genericAssign(dest, src: pointer, mt: PNimType) {.importCompilerProc.}

when not defined(gcDestructors):
  proc genericShallowAssign(dest, src: pointer, mt: PNimType) {.importCompilerProc.}
  proc incrSeq(seq: PGenSeq, elemSize, elemAlign: int): PGenSeq {.importCompilerProc.}
  proc newObj(typ: PNimType, size: int): pointer {.importCompilerProc.}
  proc newSeq(typ: PNimType, len: int): pointer {.importCompilerProc.}
  proc objectInit(dest: pointer, typ: PNimType) {.importCompilerProc.}
else:
  proc nimNewObj(size, align: int): pointer {.importCompilerProc.}
  proc newSeqPayload(cap, elemSize, elemAlign: int): pointer {.importCompilerProc.}
  proc prepareSeqAddUninit(len: int; p: pointer; addlen, elemSize, elemAlign: int): pointer {.
    importCompilerProc.}
  proc zeroNewElements(len: int; p: pointer; addlen, elemSize, elemAlign: int) {.
    importCompilerProc.}

template `+!!`(a, b): untyped = cast[pointer](cast[int](a) + b)

proc getDiscriminant(aa: pointer, n: ptr TNimNode): int =
  assert(n.kind == nkCase)
  var d: int
  let a = cast[int](aa)
  case n.typ.size
  of 1: d = int(cast[ptr uint8](a +% n.offset)[])
  of 2: d = int(cast[ptr uint16](a +% n.offset)[])
  of 4: d = int(cast[ptr uint32](a +% n.offset)[])
  of 8: d = int(cast[ptr uint64](a +% n.offset)[])
  else: raiseAssert "unreachable"
  return d

proc selectBranch(aa: pointer, n: ptr TNimNode): ptr TNimNode =
  let discr = getDiscriminant(aa, n)
  if discr <% n.len:
    result = n.sons[discr]
    if result == nil: result = n.sons[n.len]
    # n.sons[n.len] contains the `else` part (but may be nil)
  else:
    result = n.sons[n.len]

proc newAny(value: pointer, rawType: PNimType): Any {.inline.} =
  result = Any(value: value)
  result.rawType = rawType

proc toAny*[T](x: var T): Any {.inline.} =
  ## Constructs an `Any` object from `x`. This captures `x`'s address, so
  ## `x` can be modified with its `Any` wrapper! The caller needs to ensure
  ## that the wrapper **does not** live longer than `x`!
  newAny(addr(x), cast[PNimType](getTypeInfo(x)))

proc kind*(x: Any): AnyKind {.inline.} =
  ## Gets the type kind.
  result = cast[AnyKind](ord(x.rawType.kind))

proc size*(x: Any): int {.inline.} =
  ## Returns the size of `x`'s type.
  result = x.rawType.size

proc baseTypeKind*(x: Any): AnyKind {.inline.} =
  ## Gets the base type's kind. If `x` has no base type, `akNone` is returned.
  if x.rawType.base != nil:
    result = cast[AnyKind](ord(x.rawType.base.kind))
  else:
    result = akNone

proc baseTypeSize*(x: Any): int {.inline.} =
  ## Returns the size of `x`'s base type. If `x` has no base type, 0 is returned.
  if x.rawType.base != nil:
    result = x.rawType.base.size
  else:
    result = 0

proc invokeNew*(x: Any) =
  ## Performs `new(x)`. `x` needs to represent a `ref`.
  assert x.rawType.kind == tyRef
  when defined(gcDestructors):
    cast[ppointer](x.value)[] = nimNewObj(x.rawType.base.size, x.rawType.base.align)
  else:
    var z = newObj(x.rawType, x.rawType.base.size)
    genericAssign(x.value, addr(z), x.rawType)

proc invokeNewSeq*(x: Any, len: int) =
  ## Performs `newSeq(x, len)`. `x` needs to represent a `seq`.
  assert x.rawType.kind == tySequence
  when defined(gcDestructors):
    var s = cast[ptr NimSeqV2Reimpl](x.value)
    s.len = len
    let elem = x.rawType.base
    s.p = cast[ptr NimSeqPayloadReimpl](newSeqPayload(len, elem.size, elem.align))
  else:
    var z = newSeq(x.rawType, len)
    genericShallowAssign(x.value, addr(z), x.rawType)

proc extendSeq*(x: Any) =
  ## Performs `setLen(x, x.len+1)`. `x` needs to represent a `seq`.
  assert x.rawType.kind == tySequence
  when defined(gcDestructors):
    var s = cast[ptr NimSeqV2Reimpl](x.value)
    let elem = x.rawType.base
    if s.p == nil or s.p.cap < s.len+1:
      s.p = cast[ptr NimSeqPayloadReimpl](prepareSeqAddUninit(s.len, s.p, 1, elem.size, elem.align))
    zeroNewElements(s.len, s.p, 1, elem.size, elem.align)
    inc s.len
  else:
    var y = cast[ptr PGenSeq](x.value)[]
    var z = incrSeq(y, x.rawType.base.size, x.rawType.base.align)
    # 'incrSeq' already freed the memory for us and copied over the RC!
    # So we simply copy the raw pointer into 'x.value':
    cast[ppointer](x.value)[] = z
    #genericShallowAssign(x.value, addr(z), x.rawType)

proc setObjectRuntimeType*(x: Any) =
  ## This needs to be called to set `x`'s runtime object type field.
  assert x.rawType.kind == tyObject
  when defined(gcDestructors):
    cast[ppointer](x.value)[] = x.rawType.typeInfoV2
  else:
    objectInit(x.value, x.rawType)

proc skipRange(x: PNimType): PNimType {.inline.} =
  result = x
  if result.kind == tyRange: result = result.base

proc align(address, alignment: int): int =
  result = (address + (alignment - 1)) and not (alignment - 1)

proc `[]`*(x: Any, i: int): Any =
  ## Accessor for an any `x` that represents an array or a sequence.
  case x.rawType.kind
  of tyArray:
    let bs = x.rawType.base.size
    if i >=% x.rawType.size div bs:
      raise newException(IndexDefect, formatErrorIndexBound(i, x.rawType.size div bs))
    return newAny(x.value +!! i*bs, x.rawType.base)
  of tySequence:
    when defined(gcDestructors):
      var s = cast[ptr NimSeqV2Reimpl](x.value)
      if i >=% s.len:
        raise newException(IndexDefect, formatErrorIndexBound(i, s.len-1))
      let bs = x.rawType.base.size
      let ba = x.rawType.base.align
      let headerSize = align(sizeof(int), ba)
      return newAny(s.p +!! (headerSize+i*bs), x.rawType.base)
    else:
      var s = cast[ppointer](x.value)[]
      if s == nil: raise newException(ValueError, "sequence is nil")
      let bs = x.rawType.base.size
      if i >=% cast[PGenSeq](s).len:
        raise newException(IndexDefect, formatErrorIndexBound(i, cast[PGenSeq](s).len-1))
      return newAny(s +!! (align(GenericSeqSize, x.rawType.base.align)+i*bs), x.rawType.base)
  else: raiseAssert "unreachable"

proc `[]=`*(x: Any, i: int, y: Any) =
  ## Accessor for an any `x` that represents an array or a sequence.
  case x.rawType.kind
  of tyArray:
    var bs = x.rawType.base.size
    if i >=% x.rawType.size div bs:
      raise newException(IndexDefect, formatErrorIndexBound(i, x.rawType.size div bs))
    assert y.rawType == x.rawType.base
    genericAssign(x.value +!! i*bs, y.value, y.rawType)
  of tySequence:
    when defined(gcDestructors):
      var s = cast[ptr NimSeqV2Reimpl](x.value)
      if i >=% s.len:
        raise newException(IndexDefect, formatErrorIndexBound(i, s.len-1))
      let bs = x.rawType.base.size
      let ba = x.rawType.base.align
      let headerSize = align(sizeof(int), ba)
      assert y.rawType == x.rawType.base
      genericAssign(s.p +!! (headerSize+i*bs), y.value, y.rawType)
    else:
      var s = cast[ppointer](x.value)[]
      if s == nil: raise newException(ValueError, "sequence is nil")
      var bs = x.rawType.base.size
      if i >=% cast[PGenSeq](s).len:
        raise newException(IndexDefect, formatErrorIndexBound(i, cast[PGenSeq](s).len-1))
      assert y.rawType == x.rawType.base
      genericAssign(s +!! (align(GenericSeqSize, x.rawType.base.align)+i*bs), y.value, y.rawType)
  else: raiseAssert "unreachable"

proc len*(x: Any): int =
  ## `len` for an any `x` that represents an array or a sequence.
  case x.rawType.kind
  of tyArray:
    result = x.rawType.size div x.rawType.base.size
  of tySequence:
    when defined(gcDestructors):
      result = cast[ptr NimSeqV2Reimpl](x.value).len
    else:
      let pgenSeq = cast[PGenSeq](cast[ppointer](x.value)[])
      if isNil(pgenSeq):
        result = 0
      else:
        result = pgenSeq.len
  else: raiseAssert "unreachable"


proc base*(x: Any): Any =
  ## Returns the base type of `x` (useful for inherited object types).
  result = Any(value: x.value)
  result.rawType = x.rawType.base

proc isNil*(x: Any): bool =
  ## `isNil` for an `x` that represents a cstring, proc or
  ## some pointer type.
  assert x.rawType.kind in {tyCstring, tyRef, tyPtr, tyPointer, tyProc}
  result = isNil(cast[ppointer](x.value)[])

const pointerLike =
  when defined(gcDestructors): {tyCstring, tyRef, tyPtr, tyPointer, tyProc}
  else: {tyString, tyCstring, tyRef, tyPtr, tyPointer, tySequence, tyProc}

proc getPointer*(x: Any): pointer =
  ## Retrieves the pointer value out of `x`. `x` needs to be of kind
  ## `akString`, `akCString`, `akProc`, `akRef`, `akPtr`,
  ## `akPointer` or `akSequence`.
  assert x.rawType.kind in pointerLike
  result = cast[ppointer](x.value)[]

proc setPointer*(x: Any, y: pointer) =
  ## Sets the pointer value of `x`. `x` needs to be of kind
  ## `akString`, `akCString`, `akProc`, `akRef`, `akPtr`,
  ## `akPointer` or `akSequence`.
  assert x.rawType.kind in pointerLike
  if y != nil and x.rawType.kind != tyPointer:
    genericAssign(x.value, y, x.rawType)
  else:
    cast[ppointer](x.value)[] = y

proc fieldsAux(p: pointer, n: ptr TNimNode,
               ret: var seq[tuple[name: cstring, any: Any]]) =
  case n.kind
  of nkNone: assert(false)
  of nkSlot:
    ret.add((n.name, newAny(p +!! n.offset, n.typ)))
    assert ret[ret.len()-1][0] != nil
  of nkList:
    for i in 0..n.len-1: fieldsAux(p, n.sons[i], ret)
  of nkCase:
    var m = selectBranch(p, n)
    ret.add((n.name, newAny(p +!! n.offset, n.typ)))
    if m != nil: fieldsAux(p, m, ret)

iterator fields*(x: Any): tuple[name: string, any: Any] =
  ## Iterates over every active field of `x`. `x` needs to represent an object
  ## or a tuple.
  assert x.rawType.kind in {tyTuple, tyObject}
  let p = x.value
  var t = x.rawType
  # XXX BUG: does not work yet, however is questionable anyway
  when false:
    if x.rawType.kind == tyObject: t = cast[ptr PNimType](x.value)[]
  var ret: seq[tuple[name: cstring, any: Any]] = @[]
  if t.kind == tyObject:
    while true:
      fieldsAux(p, t.node, ret)
      t = t.base
      if t.isNil: break
  else:
    fieldsAux(p, t.node, ret)
  for name, any in items(ret):
    yield ($name, any)

proc getFieldNode(p: pointer, n: ptr TNimNode, name: cstring): ptr TNimNode =
  result = nil
  case n.kind
  of nkNone: raiseAssert "unreachable"
  of nkSlot:
    if cmpNimIdentifier(n.name, name) == 0:
      result = n
  of nkList:
    for i in 0..n.len-1:
      result = getFieldNode(p, n.sons[i], name)
      if result != nil: break
  of nkCase:
    if cmpNimIdentifier(n.name, name) == 0:
      result = n
    else:
      let m = selectBranch(p, n)
      if m != nil: result = getFieldNode(p, m, name)

proc `[]=`*(x: Any, fieldName: string, value: Any) =
  ## Sets a field of `x`. `x` needs to represent an object or a tuple.
  var t = x.rawType
  # XXX BUG: does not work yet, however is questionable anyway
  when false:
    if x.rawType.kind == tyObject: t = cast[ptr PNimType](x.value)[]
  assert x.rawType.kind in {tyTuple, tyObject}
  let n = getFieldNode(x.value, t.node, fieldName)
  if n != nil:
    assert n.typ == value.rawType
    genericAssign(x.value +!! n.offset, value.value, value.rawType)
  else:
    raise newException(ValueError, "invalid field name: " & fieldName)

proc `[]`*(x: Any, fieldName: string): Any =
  ## Gets a field of `x`. `x` needs to represent an object or a tuple.
  var t = x.rawType
  # XXX BUG: does not work yet, however is questionable anyway
  when false:
    if x.rawType.kind == tyObject: t = cast[ptr PNimType](x.value)[]
  assert x.rawType.kind in {tyTuple, tyObject}
  let n = getFieldNode(x.value, t.node, fieldName)
  if n != nil:
    result = Any(value: x.value +!! n.offset)
    result.rawType = n.typ
  elif x.rawType.kind == tyObject and x.rawType.base != nil:
    return `[]`(newAny(x.value, x.rawType.base), fieldName)
  else:
    raise newException(ValueError, "invalid field name: " & fieldName)

proc `[]`*(x: Any): Any =
  ## Dereference operator for `Any`. `x` needs to represent a ptr or a ref.
  assert x.rawType.kind in {tyRef, tyPtr}
  result = Any(value: cast[ppointer](x.value)[])
  result.rawType = x.rawType.base

proc `[]=`*(x, y: Any) =
  ## Dereference operator for `Any`. `x` needs to represent a ptr or a ref.
  assert x.rawType.kind in {tyRef, tyPtr}
  assert y.rawType == x.rawType.base
  genericAssign(cast[ppointer](x.value)[], y.value, y.rawType)

proc getInt*(x: Any): int =
  ## Retrieves the `int` value out of `x`. `x` needs to represent an `int`.
  assert skipRange(x.rawType).kind == tyInt
  result = cast[ptr int](x.value)[]

proc getInt8*(x: Any): int8 =
  ## Retrieves the `int8` value out of `x`. `x` needs to represent an `int8`.
  assert skipRange(x.rawType).kind == tyInt8
  result = cast[ptr int8](x.value)[]

proc getInt16*(x: Any): int16 =
  ## Retrieves the `int16` value out of `x`. `x` needs to represent an `int16`.
  assert skipRange(x.rawType).kind == tyInt16
  result = cast[ptr int16](x.value)[]

proc getInt32*(x: Any): int32 =
  ## Retrieves the `int32` value out of `x`. `x` needs to represent an `int32`.
  assert skipRange(x.rawType).kind == tyInt32
  result = cast[ptr int32](x.value)[]

proc getInt64*(x: Any): int64 =
  ## Retrieves the `int64` value out of `x`. `x` needs to represent an `int64`.
  assert skipRange(x.rawType).kind == tyInt64
  result = cast[ptr int64](x.value)[]

proc getBiggestInt*(x: Any): BiggestInt =
  ## Retrieves the integer value out of `x`. `x` needs to represent
  ## some integer, a bool, a char, an enum or a small enough bit set.
  ## The value might be sign-extended to `BiggestInt`.
  let t = skipRange(x.rawType)
  case t.kind
  of tyInt: result = BiggestInt(cast[ptr int](x.value)[])
  of tyInt8: result = BiggestInt(cast[ptr int8](x.value)[])
  of tyInt16: result = BiggestInt(cast[ptr int16](x.value)[])
  of tyInt32: result = BiggestInt(cast[ptr int32](x.value)[])
  of tyInt64, tyUInt64: result = BiggestInt(cast[ptr int64](x.value)[])
  of tyBool: result = BiggestInt(cast[ptr bool](x.value)[])
  of tyChar: result = BiggestInt(cast[ptr char](x.value)[])
  of tyEnum, tySet:
    case t.size
    of 1: result = int64(cast[ptr uint8](x.value)[])
    of 2: result = int64(cast[ptr uint16](x.value)[])
    of 4: result = BiggestInt(cast[ptr int32](x.value)[])
    of 8: result = BiggestInt(cast[ptr int64](x.value)[])
    else: raiseAssert "unreachable"
  of tyUInt: result = BiggestInt(cast[ptr uint](x.value)[])
  of tyUInt8: result = BiggestInt(cast[ptr uint8](x.value)[])
  of tyUInt16: result = BiggestInt(cast[ptr uint16](x.value)[])
  of tyUInt32: result = BiggestInt(cast[ptr uint32](x.value)[])
  else: raiseAssert "unreachable"

proc setBiggestInt*(x: Any, y: BiggestInt) =
  ## Sets the integer value of `x`. `x` needs to represent
  ## some integer, a bool, a char, an enum or a small enough bit set.
  let t = skipRange(x.rawType)
  case t.kind
  of tyInt: cast[ptr int](x.value)[] = int(y)
  of tyInt8: cast[ptr int8](x.value)[] = int8(y)
  of tyInt16: cast[ptr int16](x.value)[] = int16(y)
  of tyInt32: cast[ptr int32](x.value)[] = int32(y)
  of tyInt64, tyUInt64: cast[ptr int64](x.value)[] = int64(y)
  of tyBool: cast[ptr bool](x.value)[] = y != 0
  of tyChar: cast[ptr char](x.value)[] = chr(y.int)
  of tyEnum, tySet:
    case t.size
    of 1: cast[ptr uint8](x.value)[] = uint8(y.int)
    of 2: cast[ptr uint16](x.value)[] = uint16(y.int)
    of 4: cast[ptr int32](x.value)[] = int32(y)
    of 8: cast[ptr int64](x.value)[] = y
    else: assert false
  of tyUInt: cast[ptr uint](x.value)[] = uint(y)
  of tyUInt8: cast[ptr uint8](x.value)[] = uint8(y)
  of tyUInt16: cast[ptr uint16](x.value)[] = uint16(y)
  of tyUInt32: cast[ptr uint32](x.value)[] = uint32(y)
  else: assert false

proc getUInt*(x: Any): uint =
  ## Retrieves the `uint` value out of `x`. `x` needs to represent a `uint`.
  assert skipRange(x.rawType).kind == tyUInt
  result = cast[ptr uint](x.value)[]

proc getUInt8*(x: Any): uint8 =
  ## Retrieves the `uint8` value out of `x`. `x` needs to represent a `uint8`.
  assert skipRange(x.rawType).kind == tyUInt8
  result = cast[ptr uint8](x.value)[]

proc getUInt16*(x: Any): uint16 =
  ## Retrieves the `uint16` value out of `x`. `x` needs to represent a `uint16`.
  assert skipRange(x.rawType).kind == tyUInt16
  result = cast[ptr uint16](x.value)[]

proc getUInt32*(x: Any): uint32 =
  ## Retrieves the `uint32` value out of `x`. `x` needs to represent a `uint32`.
  assert skipRange(x.rawType).kind == tyUInt32
  result = cast[ptr uint32](x.value)[]

proc getUInt64*(x: Any): uint64 =
  ## Retrieves the `uint64` value out of `x`. `x` needs to represent a `uint64`.
  assert skipRange(x.rawType).kind == tyUInt64
  result = cast[ptr uint64](x.value)[]

proc getBiggestUint*(x: Any): uint64 =
  ## Retrieves the unsigned integer value out of `x`. `x` needs to
  ## represent an unsigned integer.
  let t = skipRange(x.rawType)
  case t.kind
  of tyUInt: result = uint64(cast[ptr uint](x.value)[])
  of tyUInt8: result = uint64(cast[ptr uint8](x.value)[])
  of tyUInt16: result = uint64(cast[ptr uint16](x.value)[])
  of tyUInt32: result = uint64(cast[ptr uint32](x.value)[])
  of tyUInt64: result = uint64(cast[ptr uint64](x.value)[])
  else: raiseAssert "unreachable"

proc setBiggestUint*(x: Any; y: uint64) =
  ## Sets the unsigned integer value of `x`. `x` needs to represent an
  ## unsigned integer.
  let t = skipRange(x.rawType)
  case t.kind:
  of tyUInt: cast[ptr uint](x.value)[] = uint(y)
  of tyUInt8: cast[ptr uint8](x.value)[] = uint8(y)
  of tyUInt16: cast[ptr uint16](x.value)[] = uint16(y)
  of tyUInt32: cast[ptr uint32](x.value)[] = uint32(y)
  of tyUInt64: cast[ptr uint64](x.value)[] = uint64(y)
  else: raiseAssert "unreachable"

proc getChar*(x: Any): char =
  ## Retrieves the `char` value out of `x`. `x` needs to represent a `char`.
  let t = skipRange(x.rawType)
  assert t.kind == tyChar
  result = cast[ptr char](x.value)[]

proc getBool*(x: Any): bool =
  ## Retrieves the `bool` value out of `x`. `x` needs to represent a `bool`.
  let t = skipRange(x.rawType)
  assert t.kind == tyBool
  result = cast[ptr bool](x.value)[]

proc skipRange*(x: Any): Any =
  ## Skips the range information of `x`.
  assert x.rawType.kind == tyRange
  result = Any(value: x.value)
  result.rawType = x.rawType.base

proc getEnumOrdinal*(x: Any, name: string): int =
  ## Gets the enum field ordinal from `name`. `x` needs to represent an enum
  ## but is only used to access the type information. In case of an error
  ## `low(int)` is returned.
  let typ = skipRange(x.rawType)
  assert typ.kind == tyEnum
  let n = typ.node
  let s = n.sons
  for i in 0 .. n.len-1:
    if cmpNimIdentifier($s[i].name, name) == 0:
      if ntfEnumHole notin typ.flags:
        return i
      else:
        return s[i].offset
  result = low(int)

proc getEnumField*(x: Any, ordinalValue: int): string =
  ## Gets the enum field name as a string. `x` needs to represent an enum
  ## but is only used to access the type information. The field name of
  ## `ordinalValue` is returned.
  let typ = skipRange(x.rawType)
  assert typ.kind == tyEnum
  let e = ordinalValue
  if ntfEnumHole notin typ.flags:
    if e <% typ.node.len:
      return $typ.node.sons[e].name
  else:
    # ugh we need a slow linear search:
    let n = typ.node
    let s = n.sons
    for i in 0 .. n.len-1:
      if s[i].offset == e: return $s[i].name
  result = $e

proc getEnumField*(x: Any): string =
  ## Gets the enum field name as a string. `x` needs to represent an enum.
  result = getEnumField(x, getBiggestInt(x).int)

proc getFloat*(x: Any): float =
  ## Retrieves the `float` value out of `x`. `x` needs to represent a `float`.
  assert skipRange(x.rawType).kind == tyFloat
  result = cast[ptr float](x.value)[]

proc getFloat32*(x: Any): float32 =
  ## Retrieves the `float32` value out of `x`. `x` needs to represent a `float32`.
  assert skipRange(x.rawType).kind == tyFloat32
  result = cast[ptr float32](x.value)[]

proc getFloat64*(x: Any): float64 =
  ## Retrieves the `float64` value out of `x`. `x` needs to represent a `float64`.
  assert skipRange(x.rawType).kind == tyFloat64
  result = cast[ptr float64](x.value)[]

proc getBiggestFloat*(x: Any): BiggestFloat =
  ## Retrieves the float value out of `x`. `x` needs to represent
  ## some float. The value is extended to `BiggestFloat`.
  case skipRange(x.rawType).kind
  of tyFloat: result = BiggestFloat(cast[ptr float](x.value)[])
  of tyFloat32: result = BiggestFloat(cast[ptr float32](x.value)[])
  of tyFloat64: result = BiggestFloat(cast[ptr float64](x.value)[])
  else: raiseAssert "unreachable"

proc setBiggestFloat*(x: Any, y: BiggestFloat) =
  ## Sets the float value of `x`. `x` needs to represent
  ## some float.
  case skipRange(x.rawType).kind
  of tyFloat: cast[ptr float](x.value)[] = y
  of tyFloat32: cast[ptr float32](x.value)[] = y.float32
  of tyFloat64: cast[ptr float64](x.value)[] = y
  else: raiseAssert "unreachable"

proc getString*(x: Any): string =
  ## Retrieves the `string` value out of `x`. `x` needs to represent a `string`.
  assert x.rawType.kind == tyString
  when defined(gcDestructors):
    result = cast[ptr string](x.value)[]
  else:
    if not isNil(cast[ptr pointer](x.value)[]):
      result = cast[ptr string](x.value)[]

proc setString*(x: Any, y: string) =
  ## Sets the `string` value of `x`. `x` needs to represent a `string`.
  assert x.rawType.kind == tyString
  cast[ptr string](x.value)[] = y # also correct for gcDestructors

proc getCString*(x: Any): cstring =
  ## Retrieves the `cstring` value out of `x`. `x` needs to represent a `cstring`.
  assert x.rawType.kind == tyCstring
  result = cast[ptr cstring](x.value)[]

proc assign*(x, y: Any) =
  ## Copies the value of `y` to `x`. The assignment operator for `Any`
  ## does NOT do this; it performs a shallow copy instead!
  assert y.rawType == x.rawType
  genericAssign(x.value, y.value, y.rawType)

iterator elements*(x: Any): int =
  ## Iterates over every element of `x`. `x` needs to represent a `set`.
  assert x.rawType.kind == tySet
  let typ = x.rawType
  let p = x.value
  # "typ.slots.len" field is for sets the "first" field
  var u: int64 = 0'i64
  case typ.size
  of 1: u = int64(cast[ptr uint8](p)[])
  of 2: u = int64(cast[ptr uint16](p)[])
  of 4: u = int64(cast[ptr uint32](p)[])
  of 8: u = cast[ptr int64](p)[]
  else:
    let a = cast[pbyteArray](p)
    for i in 0 .. typ.size*8-1:
      if (int(a[i div 8]) and (1 shl (i mod 8))) != 0:
        yield i + typ.node.len
  if typ.size <= 8:
    for i in 0..sizeof(int64)*8-1:
      if (u and (1'i64 shl int64(i))) != 0'i64:
        yield i + typ.node.len

proc inclSetElement*(x: Any, elem: int) =
  ## Includes an element `elem` in `x`. `x` needs to represent a Nim bitset.
  assert x.rawType.kind == tySet
  let typ = x.rawType
  let p = x.value
  # "typ.slots.len" field is for sets the "first" field
  let e = elem - typ.node.len
  case typ.size
  of 1:
    var a = cast[ptr int8](p)
    a[] = a[] or (1'i8 shl int8(e))
  of 2:
    var a = cast[ptr int16](p)
    a[] = a[] or (1'i16 shl int16(e))
  of 4:
    var a = cast[ptr int32](p)
    a[] = a[] or (1'i32 shl int32(e))
  of 8:
    var a = cast[ptr int64](p)
    a[] = a[] or (1'i64 shl e)
  else:
    var a = cast[pbyteArray](p)
    a[e shr 3] = a[e shr 3] or uint8(1 shl (e and 7))

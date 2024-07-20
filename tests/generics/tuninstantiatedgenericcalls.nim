# Cases that used to only work due to weird workarounds in the compiler
# involving not instantiating calls in generic bodies which are removed
# due to breaking statics.
# The issue was that these calls are compiled as regular expressions at
# the generic declaration with unresolved generic parameter types,
# which are special cased in some places in the compiler, but sometimes
# treated like real types.

block:
  type Base10 = object

  func maxLen(T: typedesc[Base10], I: type): int8 =
    when I is uint8:
      3
    elif I is uint16:
      5
    elif I is uint32:
      10
    elif I is uint64:
      20
    else:
      when sizeof(uint) == 4:
        10
      else:
        20
  
  type
    Base10Buf[T: SomeUnsignedInt] = object
      data: array[maxLen(Base10, T), byte]
      len: int8

  var x: Base10Buf[uint32]
  doAssert x.data.len == 10
  var y: Base10Buf[uint16]
  doAssert y.data.len == 5

import typetraits

block thardcases:
  proc typeNameLen(x: typedesc): int {.compileTime.} =
    result = x.name.len
  macro selectType(a, b: typedesc): typedesc =
    result = a

  type
    Foo[T] = object
      data1: array[T.high, int]
      data2: array[typeNameLen(T), float]
      data3: array[0..T.typeNameLen, selectType(float, int)]
  
  type MyEnum = enum A, B, C, D

  var f1: Foo[MyEnum]
  var f2: Foo[int8]

  doAssert high(f1.data1) == 2 # (D = 3) - 1 == 2
  doAssert high(f1.data2) == 5 # (MyEnum.len = 6) - 1 == 5

  doAssert high(f2.data1) == 126 # 127 - 1 == 126
  doAssert high(f2.data2) == 3 # int8.len - 1 == 3

  static:
    doAssert high(f1.data1) == ord(C)
    doAssert high(f1.data2) == 5 # length of MyEnum minus one, because we used T.high

    doAssert high(f2.data1) == 126
    doAssert high(f2.data2) == 3

    doAssert high(f1.data3) == 6 # length of MyEnum
    doAssert high(f2.data3) == 4 # length of int8

    doAssert f2.data3[0] is float

import muninstantiatedgenericcalls

block:
  var x: Leb128Buf[uint32]
  doAssert x.data.len == 5
  var y: Leb128Buf[uint16]
  doAssert y.data.len == 3

import macros

block: # issue #12415
  macro isSomePointerImpl(t: typedesc): bool =
    var impl = t.getTypeInst[1].getTypeImpl
    if impl.kind == nnkDistinctTy:
      impl = impl[0].getTypeImpl
    if impl.kind in {nnkPtrTy,nnkRefTy}:
      result = newLit(true)
    elif impl.kind == nnkSym and impl.eqIdent("pointer"):
      result = newLit(true)
    else:
      result = newLit(false)

  proc isSomePointer[T](t: typedesc[T]): bool {.compileTime.} =
    isSomePointerImpl(t)

  type
    Option[T] = object
      ## An optional type that stores its value and state separately in a boolean.
      when isSomePointer(typedesc(T)):
        val: T
      else:
        val: T
        has: bool
  var x: Option[ref int]
  doAssert not compiles(x.has)
  var y: Option[int]
  doAssert compiles(y.has)

block: # issue #2002
  proc isNillable(T: typedesc): bool =
    when compiles((let v: T = nil)):
      return true
    else:
      return false

  type
    Foo[T] = object
      when isNillable(T):
        nillable: float
      else:
        notnillable: int

  var val1: Foo[ref int]
  doAssert compiles(val1.nillable)
  doAssert not compiles(val1.notnillable)
  var val2: Foo[int]
  doAssert not compiles(val2.nillable)
  doAssert compiles(val2.notnillable)

block: # issue #1771
  type
    Foo[X, T] = object
      bar: array[X.low..X.high, T]

  proc test[X, T](f: Foo[X, T]): T =
    f.bar[X.low]

  var a: Foo[range[0..2], float]
  doAssert test(a) == 0.0

block: # issue #23730
  proc test(M: static[int]): array[1 shl M, int] = discard
  doAssert len(test(3)) == 8
  doAssert len(test(5)) == 32

block: # issue #19819
  type
    Example[N: static int] = distinct int
    What[E: Example] = Example[E.N + E.N]

block: # issue #23339
  type
    A = object
    B = object
  template aToB(t: typedesc[A]): typedesc = B
  type
    Inner[I] = object
      innerField: I
    Outer[O] = object
      outerField: Inner[O.aToB]
  var x: Outer[A]
  doAssert typeof(x.outerField.innerField) is B

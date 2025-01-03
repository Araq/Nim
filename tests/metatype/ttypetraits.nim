discard """
  joinable: false
"""

import typetraits
import macros

block: # toUnsigned, toSigned
  var a1: toSigned(int16)
  doAssert a1 is int16
  var a2: toSigned(uint16)
  doAssert $a2.typeof == "int16"
  doAssert toSigned(uint32) is int32
  doAssert uint64.toSigned is int64
  doAssert int64.toSigned is int64
  doAssert int64.toUnsigned is uint64
  doAssert int.toUnsigned is uint
  doAssert $uint.toUnsigned == "uint"
  # disallowed for now
  doAssert not compiles(toUnsigned(range[0..7]))
  doAssert not compiles(toSigned(range[0..7]))

block: # isNamedTuple
  type Foo1 = (a:1,).type
  type Foo2 = (Field0:1,).type
  type Foo3 = ().type
  type Foo4 = object
  type Foo5[T] = tuple[x:int, y: T]
  type Foo6[T] = (T,)

  doAssert (a:1,).type.isNamedTuple
  doAssert Foo1.isNamedTuple
  doAssert Foo2.isNamedTuple
  doAssert isNamedTuple(tuple[key: int])
  doAssert not Foo3.isNamedTuple
  doAssert not Foo4.isNamedTuple
  doAssert not (1,).type.isNamedTuple
  doAssert isNamedTuple(Foo5[int8])
  doAssert not isNamedTuple(Foo5)
  doAssert not isNamedTuple(Foo6[int8])

proc typeToString*(t: typedesc, prefer = "preferTypeName"): string {.magic: "TypeTrait".}
  ## Returns the name of the given type, with more flexibility than `name`,
  ## and avoiding the potential clash with a variable named `name`.
  ## prefer = "preferResolved" will resolve type aliases recursively.
  # Move to typetraits.nim once api stabilized.

block: # name, `$`
  static:
    doAssert $type(42) == "int"
    doAssert int.name == "int"

  const a1 = name(int)
  const a2 = $(int)
  const a3 = $int
  doAssert a1 == "int"
  doAssert a2 == "int"
  doAssert a3 == "int"

  proc fun[T: typedesc](t: T) =
    const a1 = name(t)
    const a2 = $(t)
    const a3 = $t
    doAssert a1 == "int"
    doAssert a2 == "int"
    doAssert a3 == "int"
  fun(int)

  doAssert $(int,) == "(int,)"
  doAssert $(1,) == "(1,)" # just for comparison to make sure it has same structure
  doAssert $tuple[] == "tuple[]"
  doAssert $(int,) == "(int,)"
  doAssert $(int, float) == "(int, float)"
  doAssert $((int), tuple[], tuple[a: uint], tuple[a: uint, b: float], (int,), (int, float)) ==
    "(int, tuple[], tuple[a: uint], tuple[a: uint, b: float], (int,), (int, float))"

block: # typeToString
  type MyInt = int
  type
    C[T0, T1] = object
  type C2=C # alias => will resolve as C
  type C2b=C # alias => will resolve as C (recursively)
  type C3[U,V] = C[V,U]
  type C4[X] = C[X,X]
  template name2(T): string = typeToString(T, "preferResolved")
  doAssert MyInt.name2 == "int"
  doAssert C3[MyInt, C2b].name2 == "C3[int, C]"
    # C3 doesn't get resolved to C, not an alias (nor does C4)
  doAssert C2b[MyInt, C4[cstring]].name2 == "C[int, C4[cstring]]"
  doAssert C4[MyInt].name2 == "C4[int]"
  when BiggestFloat is float and cint is int:
    doAssert C2b[cint, BiggestFloat].name2 == "C3[int, C3[float, int32]]"

  template name3(T): string = typeToString(T, "preferMixed")
  doAssert MyInt.name3 == "MyInt{int}"
  doAssert (tuple[a: MyInt, b: float]).name3 == "tuple[a: MyInt{int}, b: float]"
  doAssert (tuple[a: C2b[MyInt, C4[cstring]], b: cint, c: float]).name3 ==
    "tuple[a: C[MyInt{int}, C4[cstring]], b: cint{int32}, c: float]"

  macro fn(): string =
    # not 100% sure whether this should even compile; if some PR breaks this test,
    # this could be revisited, maybe.
    newLit $($getType(untyped), $getType(typed))
  doAssert fn() == """("untyped", "typed")"""

block distinctBase:
  block:
    type
      Foo[T] = distinct seq[T]
    var a: Foo[int]
    doAssert a.type.distinctBase is seq[int]
    doAssert seq[int].distinctBase is seq[int]
    doAssert "abc".distinctBase == "abc"

  block:
    # simplified from https://github.com/nim-lang/Nim/pull/8531#issuecomment-410436458
    macro uintImpl(bits: static[int]): untyped =
      if bits >= 128:
        let inner = getAST(uintImpl(bits div 2))
        result = newTree(nnkBracketExpr, ident("UintImpl"), inner)
      else:
        result = ident("uint64")

    type
      BaseUint = UintImpl or SomeUnsignedInt
      UintImpl[Baseuint] = object
      Uint[bits: static[int]] = distinct uintImpl(bits)

    doAssert Uint[128].distinctBase is UintImpl[uint64]

    block:
      type
        AA = distinct seq[int]
        BB = distinct string
        CC = distinct int
        AAA = AA

      static:
        var a2: AAA
        var b2: BB
        var c2: CC

        doAssert(a2 is distinct)
        doAssert(b2 is distinct)
        doAssert(c2 is distinct)

        doAssert($distinctBase(typeof(a2)) == "seq[int]")
        doAssert($distinctBase(typeof(b2)) == "string")
        doAssert($distinctBase(typeof(c2)) == "int")

block: # rangeBase
  {.push warningAsError[EnumConv]: on.}
  proc foo[T: not range](x: T): string =
    $T & "(" & $x & ")"
  proc foo[T: range](x: T): string =
    "ranged(" & $low(T) & ".." & $high(T) & " of " & $rangeBase(T) & ") " & foo(rangeBase(x))
  doAssert foo(123) == "int(123)"
  type IntRange = range[0..3]
  let x: IntRange = 2
  doAssert foo(x) == "ranged(0..3 of int) int(2)"
  type E = enum a, b, c, d, e, f
  type EnumRange = range[c..e]
  let y: EnumRange = d
  doAssert foo(y) == "ranged(c..e of E) E(d)"
  let z: range['a'..'z'] = 'g'
  doAssert foo(z) == "ranged(a..z of char) char(g)"
  {.pop.}

  # works only with #24037:
  var toChange: range[0..3] = 1
  proc bar[T: int and not range](y: var T) =
    inc y
  doAssert not compiles(bar(toChange))
  bar(rangeBase(toChange))
  doAssert toChange == 2

block: # tupleLen
  doAssert not compiles(tupleLen(int))

  type
    MyTupleType = (int,float,string)

  static: doAssert MyTupleType.tupleLen == 3

  type
    MyGenericTuple[T] = (T,int,float)
    MyGenericAlias = MyGenericTuple[string]
  static: doAssert MyGenericAlias.tupleLen == 3

  type
    MyGenericTuple2[T,U] = (T,U,string)
    MyGenericTuple2Alias[T] =  MyGenericTuple2[T,int]

    MyGenericTuple2Alias2 =   MyGenericTuple2Alias[float]
  static: doAssert MyGenericTuple2Alias2.tupleLen == 3

  static: doAssert (int, float).tupleLen == 2
  static: doAssert (1, ).tupleLen == 1
  static: doAssert ().tupleLen == 0

  let x = (1,2,)
  doAssert x.tupleLen == 2
  doAssert ().tupleLen == 0
  doAssert (1,).tupleLen == 1
  doAssert (int,).tupleLen == 1
  doAssert type(x).tupleLen == 2
  doAssert type(x).default.tupleLen == 2
  type T1 = (int,float)
  type T2 = T1
  doAssert T2.tupleLen == 2

block genericParams:
  type Foo[T1, T2]=object
  doAssert genericParams(Foo[float, string]) is (float, string)
  type Foo1 = Foo[float, int]
  doAssert genericParams(Foo1) is (float, int)
  type Foo2 = Foo[float, Foo1]
  doAssert genericParams(Foo2) is (float, Foo[float, int])
  doAssert genericParams(Foo2) is (float, Foo1)
  doAssert genericParams(Foo2).get(1) is Foo1
  doAssert (int,).get(0) is int
  doAssert (int, float).get(1) is float

  type Bar[N: static int, T] = object
  type Bar3 = Bar[3, float]
  doAssert genericParams(Bar3) is (StaticParam[3], float)
  doAssert genericParams(Bar3).get(0) is StaticParam
  doAssert genericParams(Bar3).get(0).value == 3
  doAssert genericParams(Bar[3, float]).get(0).value == 3
  static: doAssert genericParams(Bar[3, float]).get(0).value == 3

  type
    VectorElementType = SomeNumber | bool
    Vec[N: static[int], T: VectorElementType] = object
      arr: array[N, T]
    Vec4[T: VectorElementType] = Vec[4,T]
    Vec4f = Vec4[float32]

    MyTupleType = (int,float,string)
    MyGenericTuple[T] = (T,int,float)
    MyGenericAlias = MyGenericTuple[string]
    MyGenericTuple2[T,U] = (T,U,string)
    MyGenericTuple2Alias[T] =  MyGenericTuple2[T,int]
    MyGenericTuple2Alias2 =   MyGenericTuple2Alias[float]

  doAssert genericParams(MyGenericAlias) is (string,)
  doAssert genericHead(MyGenericAlias) is MyGenericTuple
  doAssert genericParams(MyGenericTuple2Alias2) is (float,)
  doAssert genericParams(MyGenericTuple2[float, int]) is (float, int)
  doAssert genericParams(MyGenericAlias) is (string,)
  doAssert genericParams(Vec4f) is (float32,)
  doAssert genericParams(Vec[4, bool]) is (StaticParam[4], bool)

  block:
    type Foo[T1, T2]=object
    doAssert genericParams(Foo[float, string]) is (float, string)
    type Bar[N: static float, T] = object
    doAssert genericParams(Bar[1.0, string]) is (StaticParam[1.0], string)
    type Bar2 = Bar[2.0, string]
    doAssert genericParams(Bar2) is (StaticParam[2.0], string)
    type Bar3 = Bar[1.0 + 2.0, string]
    doAssert genericParams(Bar3) is (StaticParam[3.0], string)

    const F = 5.0
    type Bar4 = Bar[F, string]
    doAssert genericParams(Bar4) is (StaticParam[5.0], string)
    doAssert genericParams(Bar[F, string]) is (StaticParam[5.0], string)

  block typeof:
    var
      a: seq[int]
      b: array[42, float]
      c: array[char, int]
      d: array[1..2, char]

    doAssert genericParams(typeof(a)).get(0) is int
    doAssert genericParams(typeof(b)) is (range[0..41], float)
    doAssert genericParams(typeof(c)) is (char, int)
    doAssert genericParams(typeof(d)) is (range[1..2], char)

  block nestedContainers:
    doAssert genericParams(seq[Foo[string, float]]).get(0) is Foo[string, float]
    doAssert genericParams(array[10, Foo[Bar[1, int], Bar[2, float]]]) is (StaticParam[10], Foo[Bar[1, int], Bar[2, float]])
    doAssert genericParams(array[1..9, int]) is (range[1..9], int)

##############################################
# bug 13095

type
  CpuStorage[T] {.shallow.} = ref object
    when supportsCopyMem(T):
      raw_buffer*: ptr UncheckedArray[T] # 8 bytes
      memalloc*: pointer                 # 8 bytes
      isMemOwner*: bool                  # 1 byte
    else: # Tensors of strings, other ref types or non-trivial destructors
      raw_buffer*: seq[T]                # 8 bytes (16 for seq v2 backed by destructors?)

var x = CpuStorage[string]()

static:
  doAssert(not string.supportsCopyMem)
  doAssert x.T is string          # true
  doAssert x.raw_buffer is seq

block genericHead:
  type Foo[T1,T2] = object
    x1: T1
    x2: T2
  type FooInst = Foo[int, float]
  type Foo2 = genericHead(FooInst)
  doAssert Foo2 is Foo # issue #13066

  block:
    type Goo[T] = object
    type Moo[U] = object
    type Hoo = Goo[Moo[float]]
    type Koo = genericHead(Hoo)
    doAssert Koo is Goo
    doAssert genericParams(Hoo) is (Moo[float],)
    doAssert genericParams(Hoo).get(0) is Moo[float]
    doAssert genericHead(genericParams(Hoo).get(0)) is Moo

  type Foo2Inst = Foo2[int, float]
  doAssert FooInst.default == Foo2Inst.default
  doAssert FooInst.default.x2 == 0.0
  doAssert Foo2Inst is FooInst
  doAssert FooInst is Foo2Inst
  doAssert compiles(genericHead(FooInst))
  doAssert not compiles(genericHead(Foo))
  type Bar = object
  doAssert not compiles(genericHead(Bar))

  when false: # xxx not supported yet
    doAssert seq[int].genericHead is seq
  when false: # xxx not supported yet, gives: Error: identifier expected
    type Hoo[T] = object
    doAssert genericHead(Hoo[int])[float] is Hoo[float]

block: # elementType
  iterator myiter(n: int): auto =
    for i in 0..<n: yield i
  iterator myiter3(): int = yield 10
  iterator myiter2(n: int): auto {.closure.} =
    for i in 0..<n: yield i
  doAssert elementType(@[1,2]) is int
  doAssert elementType("asdf") is char
  doAssert elementType(myiter(3)) is int
  doAssert elementType(myiter2(3)) is int
  doAssert elementType([1.1]) is float
  doAssert compiles elementType([1])
  doAssert not compiles elementType(1)
  doAssert compiles elementType(myiter3())
  doAssert not compiles elementType(myiter3)
  # check that it also works for 0-sized seq:
  var a: seq[int]
  doAssert elementType(a) is int
  doAssert elementType(seq[char].default) is char

block: # enum.len
  type
    Direction = enum
      north, east, south, west
    
    Direction2 = Direction
    Direction3 = Direction2

    TokenType = enum
      a = 2, b = 4, c = 89
    
    MyEnum = enum
      ##[This is test of enum with a doc comment.

         Which is also a multi line one.]##
      valueA = (0, "my value A"),
        ## The items are also commented. This has both integer and string
        ## values.
      valueB = "value B",
        ## This item has only a string value,
      valueC = 2,
        ## and this one only an integer.
      valueD = (3, "abc")
        ## Both, integer and string values again.

    OtherEnum {.pure.} = enum
      valueX, valueY, valueZ

    MyFlag {.size: sizeof(cint).} = enum
      A, B, C, D

  static:
    doAssert Direction.enumLen == 4
    doAssert Direction2.enumLen == 4
    doAssert Direction3.enumLen == 4
    doAssert TokenType.enumLen == 3
    doAssert MyEnum.enumLen == 4
    doAssert OtherEnum.enumLen == 3
    doAssert MyFlag.enumLen == 4

when true: # Odd bug where alias can seep inside of `distinctBase`
  import std/unittest

  type
    AdtChild* = concept t
      distinctBase(t)

  proc `$`*[T: AdtChild](adtChild: T): string = ""

  check 10 is int


block: # bug #24378
  macro forked(body: typed): untyped = # typed or untyped does not matter
    result = quote do:
      type Win = typeof(`body`)
      doAssert not supportsCopyMem((int, Win))
      doAssert not supportsCopyMem(tuple[a: int, b: Win])

      type Win2[T] = typeof(`body`)
      doAssert not supportsCopyMem((int, Win2[int]))
      doAssert not supportsCopyMem(tuple[a: int, b: Win2[int]])
  forked:
    "foobar"


  type Win111 = typeof("foobar")
  doAssert not supportsCopyMem((int, Win111))
  doAssert not supportsCopyMem(tuple[a: int, b: Win111])

  type Win222[T] = typeof("foobar")
  doAssert not supportsCopyMem((int, Win222[int]))
  doAssert not supportsCopyMem(tuple[a: int, b: Win222[int]])

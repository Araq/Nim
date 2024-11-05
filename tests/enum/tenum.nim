discard """
  output: '''
B
B
ABCDC
foo
first0second32third64
my value A1my value Bconc2valueCabc4abc
my value A0my value Bconc1valueCabc3abc
'''
"""


import macros

block tenum1:
  type E = enum a, b, c, x, y, z
  var en: E
  en = a

  # Bug #4066
  macro genEnum(): untyped = newNimNode(nnkEnumTy).add(newEmptyNode(), newIdentNode("geItem1"))
  type GeneratedEnum = genEnum()
  doAssert(type(geItem1) is GeneratedEnum)



block tenum2:
  type
    TEnumHole = enum
      eA = 0,
      eB = 4,
      eC = 5

  var
    e: TEnumHole = eB

  case e
  of eA: echo "A"
  of eB: echo "B"
  of eC: echo "C"



block tenum3:
  type
    TEnumHole {.size: sizeof(int).} = enum
      eA = 0,
      eB = 4,
      eC = 5

  var
    e: TEnumHole = eB

  case e
  of eA: echo "A"
  of eB: echo "B"
  of eC: echo "C"



block tbasic:
  type
    MyEnum = enum
      A,B,C,D
  # trick the optimizer with an seq:
  var x = @[A,B,C,D]
  echo x[0],x[1],x[2],x[3],MyEnum(2)



block talias:
  # bug #5148
  type
    A = enum foo, bar
    B = A

  echo B.foo



block thole:
  type Holed = enum
    hFirst = (0,"first")
    hSecond = (32,"second")
    hThird = (64,"third")
    
  var x = @[0,32,64] # This is just to avoid the compiler inlining the value of the enum

  echo Holed(x[0]),ord Holed(x[0]),Holed(x[1]),ord Holed(x[1]),Holed(x[2]),ord Holed(x[2])



block toffset:
  const
    strValB = "my value B"

  type
    TMyEnum = enum
      valueA = (1, "my value A"),
      valueB = strValB & "conc",
      valueC,
      valueD = (4, "abc")

  proc getValue(i:int): TMyEnum = TMyEnum(i)

  # trick the optimizer with a variable:
  var x = getValue(4)
  echo getValue(1), ord(valueA), getValue(2), ord(valueB), getValue(3), getValue(4), ord(valueD), x



block tnamedfields:
  const strValB = "my value B"

  type
    TMyEnum = enum
      valueA = (0, "my value A"),
      valueB = strValB & "conc",
      valueC,
      valueD = (3, "abc"),
      valueE = 4

  # trick the optimizer with a variable:
  var x = valueD
  echo valueA, ord(valueA), valueB, ord(valueB), valueC, valueD, ord(valueD), x
  doAssert $x == $valueD, $x
  doAssert $x == "abc", $x


block tfakeOptions:
  type
    TFakeOption = enum
      fakeNone, fakeForceFullMake, fakeBoehmGC, fakeRefcGC, fakeRangeCheck,
      fakeBoundsCheck, fakeOverflowCheck, fakeNilCheck, fakeAssert, fakeLineDir,
      fakeWarns, fakeHints, fakeListCmd, fakeCompileOnly,
      fakeSafeCode,             # only allow safe code
      fakeStyleCheck, fakeOptimizeSpeed, fakeOptimizeSize, fakeGenDynLib,
      fakeGenGuiApp, fakeStackTrace

    TFakeOptionset = set[TFakeOption]

  var
    gFakeOptions: TFakeOptionset = {fakeRefcGC, fakeRangeCheck, fakeBoundsCheck,
      fakeOverflowCheck, fakeAssert, fakeWarns, fakeHints, fakeLineDir, fakeStackTrace}
    compilerArgs: int
    gExitcode: int8



block nonzero: # bug #6959
  type SomeEnum = enum
    A = 10
    B
    C
  let slice = SomeEnum.low..SomeEnum.high

block size_one_byte: # bug #15752
  type
    Flag = enum
      Disabled = 0x00
      Enabled = 0xFF

  static:
    assert 1 == sizeof(Flag)

block: # bug #12589
  when not defined(i386):
    type
      OGRwkbGeometryType {.size: sizeof(cuint).} = enum
        wkbPoint25D = 0x80000001.cuint, wkbLineString25D = 0x80000002,
        wkbPolygon25D = 0x80000003

    proc typ(): OGRwkbGeometryType =
      return wkbPoint25D

    when not defined(gcRefc):
      doAssert $typ() == "wkbPoint25D"

    block: # bug #21280
      type
        Test = enum
          B = 19
          A = int64.high()

      doAssert ord(A) == int64.high()

import std/enumutils
from std/sequtils import toSeq
import std/macros

block: # unordered enum
  block:
    type
      unordered_enum = enum
        a = 1
        b = 0

    doAssert (ord(a), ord(b)) == (1, 0)
    doAssert unordered_enum.toSeq == @[b, a]

  block:
    type
      unordered_enum = enum
        a = 1
        b = 0
        c

    doAssert (ord(a), ord(b), ord(c)) == (1, 0, 2)

  block:
    type
      unordered_enum = enum
        a = 100
        b
        c = 50
        d

    doAssert (ord(a), ord(b), ord(c), ord(d)) == (100, 101, 50, 51)

  block:
    type
      unordered_enum = enum
        a = 7
        b = 6
        c = 5
        d

    doAssert (ord(a), ord(b), ord(c), ord(d)) == (7, 6, 5, 8)
    doAssert unordered_enum.toSeq == @[c, b, a, d]

  block:
    type
      unordered_enum = enum
        a = 100
        b
        c = 500
        d
        e
        f = 50
        g
        h

    doAssert (ord(a), ord(b), ord(c), ord(d), ord(e), ord(f), ord(g), ord(h)) == 
             (100, 101, 500, 501, 502, 50, 51, 52)

  block:
    type
      unordered_enum = enum
        A
        B
        C = -1
        D
        E
        G = -999

    doAssert (ord(A), ord(B), ord(C), ord(D), ord(E), ord(G)) ==
             (0, 1, -1, 2, 3, -999)

  block:
    type
      SomeEnum = enum
        seA = 3
        seB = 2
        seC = "foo"

    doAssert (ord(seA), ord(seB), ord(seC)) == (3, 2, 4)

block: # bug #23952
  block:
    proc foo =
      type Foo = enum A B = -1
      doAssert cast[Foo](-1) == B
      doAssert ord(A) == 0
    static: foo()
    foo()

  block:
    proc foo =
      type Foo = enum A B=8, C=1
      let s1 = {A}
      let s2 = {B}
      doAssert s1 != s2
    static: foo()
    foo()

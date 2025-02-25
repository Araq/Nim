discard """
  output: '''true true false yes
false
true
false
true
true
yes'''
"""

proc IsVoid[T](): string =
  when T is void:
    result = "yes"
  else:
    result = "no"

const x = int is int
echo x, " ", float is float, " ", float is string, " ", IsVoid[void]()

template yes(e): void =
  static: assert e

template no(e): void =
  static: assert(not e)

when false:
  var s = @[1, 2, 3]

  yes s.items is iterator
  no  s.items is proc

  yes s.items is iterator: int
  no  s.items is iterator: float

  yes s.items is iterator: TNumber
  no  s.items is iterator: object

  type
    Iter[T] = iterator: T

  yes s.items is Iter[TNumber]
  no  s.items is Iter[float]

type
  Foo[N: static[int], T] = object
    field: array[1..N, T]

  Bar[T] = Foo[4, T]
  Baz[N: static[int]] = Foo[N, float]

no Foo[2, float] is Foo[3, float]
no Foo[2, float] is Foo[2, int]

yes Foo[4, string] is Foo[4, string]
yes Bar[int] is Foo[4, int]
yes Foo[4, int] is Bar[int]

no Foo[4, int] is Baz[4]
yes Foo[4, float] is Baz[4]


# bug #2505

echo(8'i8 is int32)

# bug #1853
type SeqOrSet[E] = seq[E] or set[E]
type SeqOfInt = seq[int]
type SeqOrSetOfInt = SeqOrSet[int]

# This prints "true", as expected. Previously "false" was returned and that
# seemed less correct that (1) printing "true" or (2) raising a compiler error.
echo seq is SeqOrSet

# This prints "false", as expected.
echo seq is SeqOrSetOfInt

# This prints "true", as expected.
echo SeqOfInt is SeqOrSet

# This causes an internal error (filename: compiler/semtypes.nim, line: 685).
echo SeqOfInt is SeqOrSetOfInt

# bug #2522
proc test[T](x: T) =
  when T is typedesc:
    echo "yes"
  else:
    echo "no"

test(7)

block:
  # bug #13066
  type Bar[T1,T2] = object
  type Foo[T1,T2] = object
  type Foo2 = Foo
  doAssert Foo2 is Foo
  doAssert Foo is Foo2
  doAssert Foo is Foo
  doAssert Foo2 is Foo2
  doAssert Foo2 isnot Bar
  doAssert Foo[int,float] is Foo2[int,float]

  # other
  doAssert Foo[int,float] isnot Foo2[float,float]
  doAssert Foo[int,float] is Foo2
  doAssert Foo[int,float|int] is Foo2
  doAssert Foo2[int,float|int] is Foo
  doAssert Foo2[int,float|int] isnot Bar
  doAssert int is (int|float)


block:
  # Slice[T] as static type issue
  type
    MyEnum = enum
      x1, x2, x3, x4, x5, x6

  proc enumGen[T: enum](s: static[Slice[T]]) = 
    doAssert($s.a & "  " & $s.b == "x1  x3")

  enumGen(x1..x3)

block:
  # issue #11142
  type
    MyObjParam[N: static int] = object
      x: int

    MyObj[P: static MyObjParam] = object
      y: int

  const P = MyObjParam[256](x: 2)
  let Q = MyObj[P](y: 2)
  doAssert($Q  == "(y: 2)")

block: # previously tisop.nim
  type
    TRecord = (tuple) or (object)
    TFoo[T, U] = object
      x: int
      when T is string:
        y: float
      else:
        y: string
      when U is TRecord:
        z: float
    E = enum A, B, C
  template m(t: typedesc): typedesc =
    when t is enum:
      string
    else:
      int
  var f: TFoo[int, int]
  static: doAssert(typeof(f.y) is string)
  when compiles(f.z):
    {.error: "Foo should not have a `z` field".}
  proc p(a, b: auto) =
    when typeof(a) is int:
      static: doAssert false
    var f: TFoo[m(a.typeof), b.typeof]
    static:
      doAssert f.x.typeof is int
      doAssert f.y.typeof is float
      doAssert f.z.typeof is float
  p(A, f)

block: # issue #22850
  doAssert not (type is int)
  doAssert not (typedesc is int)

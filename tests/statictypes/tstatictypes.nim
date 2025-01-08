discard """
nimoutFull: true
nimout: '''
staticAlialProc instantiated with 358
staticAlialProc instantiated with 368
0: Foo
1: Bar
0: Foo
1: Bar
0: Foo
1: Bar
0: Foo
1: Bar
'''
output: '''
16
16
b is 2 times a
17
['\x00', '\x00', '\x00', '\x00']
heyho
Val1
Val1
'''
matrix: "--hints:off --warnings:off --mm:orc; --hints:off --warnings:off --mm:refc"
"""

import macros

template ok(x) = doAssert(x)
template no(x) = doAssert(not x)

template accept(x) =
  static: doAssert(compiles(x))

template reject(x) =
  static: doAssert(not compiles(x))

proc plus(a, b: int): int = a + b

template isStatic(x: static): bool = true
template isStatic(x: auto): bool = false

var v = 1

when true:
  # test that `isStatic` works as expected
  const C = 2

  static:
    ok C.isStatic
    ok isStatic(plus(1, 2))
    ok plus(C, 2).isStatic

    no isStatic(v)
    no plus(1, v).isStatic

when true:
  # test that proc instantiation works as expected
  type
    StaticTypeAlias = static[int]

  proc staticAliasProc(a: StaticTypeAlias,
                       b: static[int],
                       c: static int) =
    static:
      doAssert a.isStatic and b.isStatic and c.isStatic
      doAssert isStatic(a + plus(b, c))
      echo "staticAlialProc instantiated with ", a, b, c

    when b mod a == 0:
      echo "b is ", b div a, " times a"

    echo a + b + c

  staticAliasProc 1+2, 5, 8
  staticAliasProc 3, 2+3, 9-1
  staticAliasProc 3, 3+3, 4+4

when true:
  # test static coercions. normal cases that should work:
  accept:
    var s1 = static[int] plus(1, 2)
    var s2 = static(plus(1,2))
    var s3 = static plus(1,2)
    var s4 = static[SomeInteger](1 + 2)

  # the sub-script operator can be used only with types:
  reject:
    var just_static3 = static[plus(1,2)]

  # static coercion takes into account the type:
  reject:
    var x = static[string](plus(1, 2))
  reject:
    var x = static[string] plus(1, 2)
  reject:
    var x = static[SomeFloat] plus(3, 4)

  # you cannot coerce a run-time variable
  reject:
    var x = static(v)

block: # issue #13730
  type Foo[T: static[float]] = object
  doAssert Foo[0.0] is Foo[-0.0]

when true:
  type
    ArrayWrapper1[S: static int] = object
      data: array[S + 1, int]

    ArrayWrapper2[S: static[int]] = object
      data: array[S.plus(2), int]

    ArrayWrapper3[S: static[(int, string)]] = object
      data: array[S[0], int]

  var aw1: ArrayWrapper1[5]
  var aw2: ArrayWrapper2[5]
  var aw3: ArrayWrapper3[(10, "str")]

  static:
    doAssert aw1.data.high == 5
    doAssert aw2.data.high == 6
    doAssert aw3.data.high == 9

# #6077
block:
  type
    Backend = enum
      Cpu

    Tensor[B: static[Backend]; T] = object

    BackProp[B: static[Backend],T] = proc (gradient: Tensor[B,T]): Tensor[B,T]

# https://github.com/nim-lang/Nim/issues/10073
block:
  proc foo[N: static int](x: var int,
                          y: int,
                          z: static int,
                          arr: array[N, int]): auto =
    var t1 = (a: x, b: y, c: z, d: N)
    var t2 = (x, y, z, N)
    doAssert t1 == t2
    result = t1

  var y = 20
  var x = foo(y, 10, 15, [1, 2, 3])
  doAssert x == (20, 10, 15, 3)

# #7609
block:
  type
    Coord[N: static[int]] = tuple[col, row: range[0'i8 .. (N.int8-1)]]
    Point[N: static[int]] = range[0'i16 .. N.int16 * N.int16 - 1]

# https://github.com/nim-lang/Nim/issues/10339
block:
  type
    MicroKernel = object
      a: float
      b: int

  macro extractA(ukernel: static MicroKernel): untyped =
    result = newLit ukernel.a

  proc tFunc[ukernel: static MicroKernel]() =
    const x = ukernel.extractA
    doAssert x == 5.5

  const uk = MicroKernel(a: 5.5, b: 1)
  tFunc[uk]()


# bug #7258
type
  StringValue*[LEN: static[Natural]] = array[LEN+Natural(2),char]
  StringValue16* = StringValue[2]

var
  s: StringValue16

echo s

block: #13529
  block:
    type Foo[T: static type] = object
    var foo: Foo["test"]
    doAssert $foo == "()"
    doAssert foo.T is string
    static: doAssert foo.T == "test"
    doAssert not compiles(
      block:
        type Foo2[T: static type] = object
          x: T)

  block:
    type Foo[T: static[float]] = object
    var foo: Foo[1.2]
    doAssert $foo == "()"
    doAssert foo.T == 1.2

  block: # routines also work
    proc fun(a: static) = (const a2 = a)
    fun(1)
    fun(1.2)
  block: # routines also work
    proc fun(a: static type) = (const a2 = a)
    fun(1)
    fun(1.2)

  block: # this also works
    proc fun[T](a: static[T]) = (const a2 = a)
    fun(1)
    fun(1.2)

block: # #12713
  block:
    type Cell = object
      c: int
    proc test(c: static string) = discard #Remove this and it compiles
    proc test(c: Cell) = discard
    test Cell(c: 0)
  block:
    type Cell = object
      c: int
    proc test(c: static string) = discard #Remove this and it compiles
    proc test(c: Cell) = discard
    test Cell()

block: # issue #14802
  template fn(s: typed): untyped =
    proc bar() = discard
    12
  const myConst = static(fn(1))
  doAssert myConst == 12


# bug #12571
type
  T[K: static bool] = object of RootObj
    when K == true:
      foo: string
    else:
      bar: string
  U[K: static bool] = object of T[K]

let t = T[true](foo: "hey")
let u = U[false](bar: "ho")
echo t.foo, u.bar


#------------------------------------------------------------------------------
# issue #9679

type
  Foo*[T] = object
    bar*: int
    dummy: T

proc initFoo(T: type, bar: int): Foo[T] =
  result.bar = 1

proc fails[T](x: static Foo[T]) = # Change to non-static and it compiles
  doAssert($x == "(bar: 1, dummy: 0)")

block:
  const foo = initFoo(int, 2)
  fails(foo)


import tables

var foo{.compileTime.} = [
  "Foo",
  "Bar"
]

var bar{.compileTime.} = {
  0: "Foo",
  1: "Bar"
}.toTable()

macro fooM(): untyped =
  for i, val in foo:
    echo i, ": ", val

macro barM(): untyped =
  for i, val in bar:
    echo i, ": ", val

macro fooParam(x: static array[2, string]): untyped =
  for i, val in x:
    echo i, ": ", val

macro barParam(x: static Table[int, string]): untyped =
  let barParamInsides = proc(i: int, val: string): NimNode =
    echo i, ": ", val
  for i, val in x:
    discard barParamInsides(i, val)

fooM()
barM()
fooParam(foo)
barParam(bar)


#-----------------------------------------------------------------------------------------
# issue #7546
type
  rangeB[N: static[int16]] = range[0'i16 .. N]
  setB[N: static[int16]] = set[rangeB[N]]

block:
  var s : setB[14'i16]


#-----------------------------------------------------------------------------------------
# issue #9520

type
  MyEnum = enum
    Val1, Val2

proc myproc(a: static[MyEnum], b: int) =
  if b < 0:
    myproc(a, -b)

  echo $a

myproc(Val1, -10)


#------------------------------------------------------------------------------------------
# issue #6177

type                                                                                                 
  G[N,M:static[int], T] = object                                                                      
    o: T                                                                                             
                                                                                                     
proc newG[N,M:static[int],T](x:var G[N,M,T], y:T) =                                                  
  x.o = y+10*N+100*M                                                                                 
                                                                                                     
proc newG[N,M:static[int],T](x:T):G[N,M,T] = result.newG(x)                                          
                                                                                                     
var x:G[2,3,int]                                                                                     
x.newG(4)                                                                                            
var y = newG[2,3,int](4)


#------------------------------------------------------------------------------------------
# issue #12897

type
  TileCT[n: static int] = object
    a: array[n, int]
  Tile = TileCT #Commenting this out to make it work


#------------------------------------------------------------------------------------------
# issue #15858

proc fn(N1: static int, N2: static int, T: typedesc): array[N1 * N2, T] = 
  doAssert(len(result) == N1 * N2)

let yy = fn(5, 10, float)


block:
  block:
    type Foo[N: static int] = array[cint(0) .. cint(N), float]
    type T = Foo[3]
  block:
    type Foo[N: static int] = array[int32(0) .. int32(N), float]
    type T = Foo[3]


#------------------------------------------------------------------------------------------
# static proc/lambda param
func isSorted2[T](a: openArray[T], cmp: static proc(x, y: T): bool {.inline.}): bool =
  result = true
  for i in 0..<len(a)-1:
    if not cmp(a[i], a[i+1]):
      return false

proc compare(a, b: int): bool {.inline.} = a < b

var sorted = newSeq[int](1000)
for i in 0..<sorted.len: sorted[i] = i*2
doAssert isSorted2(sorted, compare)
doAssert isSorted2(sorted, proc (a, b: int): bool {.inline.} = a < b)


block: # Ensure static descriminated objects compile
  type
    ObjKind = enum
      KindA, KindB, KindC

    MyObject[kind: static[ObjKind]] = object of RootObj
      myNumber: int
      when kind != KindA:
        driverType: int
        otherField: int
      elif kind == KindC:
        driverType: uint
        otherField: int

  var instance: MyObject[KindA]
  discard instance
  discard MyObject[KindC]()

block: # more cases of above, issue #8446
  type
    Color = enum
      red, green, blue
    Blah[color: static[Color]] = object
      when color == red:
        a: string
      else:
        b: int

  proc foo(blah: Blah) = discard
  foo(Blah[red](a: "abc"))

  type
    Mytype[K: static[int]] = object
      when K < 16:
        data: uint8
      else:
        data: uint64
  proc usingMyt(k: Mytype) = discard  # triggers Error: cannot generate code for: K

block: # bug #22600
  proc f(n: static int): int = n * 2 # same for template

  type
    a[N: static int] = object
      field : array[N, uint8]

    b[N: static int] = object
      field : a[N]

    c[N: static int] = object
      f0    : a[N     ]         # works
      f1    : a[N + 1 ]         # asserts
      f2    : a[f(N)  ]         # asserts

      f3    : b[N     ]         # works
      f4    : b[N + 1 ]         # asserts
      f5    : b[f(N)  ]         # asserts

  proc init[N: static int](x : var a[N]) = discard
  proc init[N: static int](x : var b[N]) = discard
  proc init[N: static int](x : var c[N]) = x.f1.init() # this is needed

  var x: c[2]
  x.init()

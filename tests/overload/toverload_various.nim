discard """
  output: '''
true012innertrue
m1
tup1
another number: 123
yay
helloa 1 b 2 x @[3, 4, 5] y 6 z 7
yay
12
ref ref T ptr S
dynamic: let
dynamic: var
static: const
static: literal
static: constant folding
static: static string
foo1
1
'''
"""


import strutils, sequtils


block overl2:
  # Test new overloading resolution rules
  proc toverl2(x: int): string = return $x
  proc toverl2(x: bool): string = return $x

  iterator toverl2(x: int): int =
    var res = 0
    while res < x:
      yield res
      inc(res)

  var
    pp: proc (x: bool): string {.nimcall.} = toverl2

  stdout.write(pp(true))

  for x in toverl2(3):
    stdout.write(toverl2(x))

  block:
    proc toverl2(x: int): string = return "inner"
    stdout.write(toverl2(5))
    stdout.write(true)

  stdout.write("\n")
  #OUT true012innertrue



block overl3:
  # Tests more specific generic match:
  proc m[T](x: T) = echo "m2"
  proc m[T](x: var ref T) = echo "m1"
  proc tup[S, T](x: tuple[a: S, b: ref T]) = echo "tup1"
  proc tup[S, T](x: tuple[a: S, b: T]) = echo "tup2"

  var
    obj: ref int
    tu: tuple[a: int, b: ref bool]

  m(obj)
  tup(tu)



block toverprc:
  # Test overloading of procs when used as function pointers
  proc parseInt(x: float): int {.noSideEffect.} = discard
  proc parseInt(x: bool): int {.noSideEffect.} = discard
  proc parseInt(x: float32): int {.noSideEffect.} = discard
  proc parseInt(x: int8): int {.noSideEffect.} = discard
  proc parseInt(x: File): int {.noSideEffect.} = discard
  proc parseInt(x: char): int {.noSideEffect.} = discard
  proc parseInt(x: int16): int {.noSideEffect.} = discard

  proc parseInt[T](x: T): int = echo x; 34

  type
    TParseInt = proc (x: string): int {.noSideEffect.}

  var
    q = TParseInt(parseInt)
    p: TParseInt = parseInt

  proc takeParseInt(x: proc (y: string): int {.noSideEffect.}): int =
    result = x("123")

  if false:
    echo "Give a list of numbers (separated by spaces): "
    var x = stdin.readline.split.map(parseInt).max
    echo x, " is the maximum!"
  echo "another number: ", takeParseInt(parseInt)


  type
    TFoo[a,b] = object
      lorem: a
      ipsum: b

  proc bar[a,b](f: TFoo[a,b], x: a) = echo(x, " ", f.lorem, f.ipsum)
  proc bar[a,b](f: TFoo[a,b], x: b) = echo(x, " ", f.lorem, f.ipsum)

  discard parseInt[string]("yay")



block toverwr:
  # Test the overloading resolution in connection with a qualifier
  proc write(t: File, s: string) =
    discard # a nop
  system.write(stdout, "hello")
  #OUT hello



block tparams_after_varargs:
  proc test(a, b: int, x: varargs[int]; y, z: int) =
    echo "a ", a, " b ", b, " x ", @x, " y ", y, " z ", z

  test 1, 2, 3, 4, 5, 6, 7

  # XXX maybe this should also work with ``varargs[untyped]``
  template takesBlockA(a, b: untyped; x: varargs[typed]; blck: untyped): untyped =
    blck
    echo a, b

  takesBlockA 1, 2, "some", 0.90, "random stuff":
    echo "yay"



block tprefer_specialized_generic:
  proc foo[T](x: T) =
    echo "only T"

  proc foo[T](x: ref T) =
    echo "ref T"

  proc foo[T, S](x: ref ref T; y: ptr S) =
    echo "ref ref T ptr S"

  proc foo[T, S](x: ref T; y: ptr S) =
    echo "ref T ptr S"

  proc foo[T](x: ref T; default = 0) =
    echo "ref T; default"

  var x: ref ref int
  var y: ptr ptr int
  foo(x, y)



block tstaticoverload:
  proc foo(s: string) =
    echo "dynamic: ", s

  proc foo(s: static[string]) =
    echo "static: ", s

  let l = "let"
  var v = "var"
  const c = "const"

  type staticString = static[string]

  foo(l)
  foo(v)
  foo(c)
  foo("literal")
  foo("constant" & " " & "folding")
  foo(staticString("static string"))

# bug #8568 (2)

proc goo(a: int): string = "int"
proc goo(a: static[int]): string = "static int"
proc goo(a: var int): string = "var int"
proc goo[T: int](a: T): string = "T: int"
#proc goo[T](a: T): string = "nur T"

const tmp1 = 1
let tmp2 = 1
var tmp3 = 1

doAssert goo(1) == "static int"
doAssert goo(tmp1) == "static int"
doAssert goo(tmp2) == "int"
doAssert goo(tmp3) == "var int"

doAssert goo[int](1) == "T: int"

doAssert goo[int](tmp1) == "T: int"
doAssert goo[int](tmp2) == "T: int"
doAssert goo[int](tmp3) == "T: int"

# bug #6076

type A[T] = object

proc regr(a: A[void]) = echo "foo1"
proc regr[T](a: A[T]) = doAssert(false)

regr(A[void]())


type Foo[T] = object

proc regr[T](p: Foo[T]): seq[T] =
  discard

proc regr(p: Foo[void]): seq[int] =
  discard


discard regr(Foo[int]())
discard regr(Foo[void]())


type
  Sha2Context*[bits: static[int],
               bsize: static[int],
               T: uint32|uint64] = object
    count: array[2, T]
    state: array[8, T]
    buffer: array[bsize, byte]

  sha224* = Sha2Context[224, 64, uint32]
  sha256* = Sha2Context[256, 64, uint32]
  sha384* = Sha2Context[384, 128, uint64]
  sha512* = Sha2Context[512, 128, uint64]
  sha512_224* = Sha2Context[224, 128, uint64]
  sha512_256* = Sha2Context[256, 128, uint64]

type
  RipemdContext*[bits: static[int]] = object
    count: array[2, uint32]
    state: array[bits div 32, uint32]
    buffer: array[64, byte]

  ripemd128* = RipemdContext[128]
  ripemd160* = RipemdContext[160]
  ripemd256* = RipemdContext[256]
  ripemd320* = RipemdContext[320]

const
  MaxHmacBlockSize = 256

type
  HMAC*[HashType] = object
    mdctx: HashType
    opadctx: HashType

template sizeBlock*(h: HMAC[Sha2Context]): uint = 1u
template sizeBlock*(h: HMAC[RipemdContext]): uint = 0u

proc init*[T](hmctx: HMAC[T], key: ptr byte, ulen: uint) =
  const sizeBlock = hmctx.sizeBlock
  echo sizeBlock

proc hmac*[A, B](HashType: typedesc, key: openArray[A],
                 data: openArray[B]) =
  var ctx: HMAC[HashType]
  ctx.init(nil, 0)

sha256.hmac("", "")



# nested generic types
block:
  type
    Foo[T] = object
      f: T
    Bar[T] = object
      b: T
    Baz[T] = object
      z: T
    FooBar[T] = Foo[Bar[T]]
    FooBarBaz[T] = FooBar[Baz[T]]
    #Int = int
    Int = SomeInteger
    FooBarBazInt = FooBarBaz[Int]
    FooBarBazX = FooBarBaz[int]

  proc p00(x: Foo): auto = x.f
  proc p01[T](x: Foo[T]): auto = x.f
  proc p02[T:Foo](x: T): auto = x.f

  proc p10(x: FooBar): auto = x.f
  proc p11[T](x: FooBar[T]): auto = x.f
  proc p12[T:FooBar](x: T): auto = x.f
  proc p13(x: Foo[Bar]): auto = x.f
  proc p14[T](x: Foo[Bar[T]]): auto = x.f
  proc p15[T:Bar](x: Foo[T]): auto = x.f
  proc p16[T:Foo[Bar]](x: T): auto = x.f

  proc p20(x: FooBarBaz): auto = x.f
  proc p21[T](x: FooBarBaz[T]): auto = x.f
  proc p22[T:FooBarBaz](x: T): auto = x.f
  proc p23(x: FooBar[Baz]): auto = x.f
  proc p24[T](x: FooBar[Baz[T]]): auto = x.f
  proc p25[T:Baz](x: FooBar[T]): auto = x.f
  proc p26[T:FooBar[Baz]](x: T): auto = x.f
  proc p27(x: Foo[Bar[Baz]]): auto = x.f
  proc p28[T](x: Foo[Bar[Baz[T]]]): auto = x.f
  proc p29[T:Baz](x: Foo[Bar[T]]): auto = x.f
  proc p2A[T:Bar[Baz]](x: Foo[T]): auto = x.f
  proc p2B[T:Foo[Bar[Baz]]](x: T): auto = x.f

  proc p30(x: FooBarBazInt): auto = x.f
  proc p31[T:FooBarBazInt](x: T): auto = x.f
  proc p32(x: FooBarBaz[Int]): auto = x.f
  proc p33[T:Int](x: FooBarBaz[T]): auto = x.f
  proc p34[T:FooBarBaz[Int]](x: T): auto = x.f
  proc p35(x: FooBar[Baz[Int]]): auto = x.f
  proc p36[T:Int](x: FooBar[Baz[T]]): auto = x.f
  proc p37[T:Baz[Int]](x: FooBar[T]): auto = x.f
  proc p38[T:FooBar[Baz[Int]]](x: T): auto = x.f
  proc p39(x: Foo[Bar[Baz[Int]]]): auto = x.f
  proc p3A[T:Int](x: Foo[Bar[Baz[T]]]): auto = x.f
  proc p3B[T:Baz[Int]](x: Foo[Bar[T]]): auto = x.f
  proc p3C[T:Bar[Baz[Int]]](x: Foo[T]): auto = x.f
  proc p3D[T:Foo[Bar[Baz[Int]]]](x: T): auto = x.f

  template test(x: typed) =
    let t00 = p00(x)
    let t01 = p01(x)
    let t02 = p02(x)
    let t10 = p10(x)
    let t11 = p11(x)
    let t12 = p12(x)
    #let t13 = p13(x)
    let t14 = p14(x)
    #let t15 = p15(x)
    #let t16 = p16(x)
    let t20 = p20(x)
    let t21 = p21(x)
    let t22 = p22(x)
    #let t23 = p23(x)
    let t24 = p24(x)
    #let t25 = p25(x)
    #let t26 = p26(x)
    #let t27 = p27(x)
    let t28 = p28(x)
    #let t29 = p29(x)
    #let t2A = p2A(x)
    #let t2B = p2B(x)
    let t30 = p30(x)
    let t31 = p31(x)
    let t32 = p32(x)
    let t33 = p33(x)
    let t34 = p34(x)
    let t35 = p35(x)
    let t36 = p36(x)
    let t37 = p37(x)
    let t38 = p38(x)
    let t39 = p39(x)
    let t3A = p3A(x)
    let t3B = p3B(x)
    let t3C = p3C(x)
    let t3D = p3D(x)

  var a: Foo[Bar[Baz[int]]]
  test(a)
  var b: FooBar[Baz[int]]
  test(b)
  var c: FooBarBaz[int]
  test(c)
  var d: FooBarBazX
  test(d)


# overloading on tuples with generic alias
block:
  type
    Foo[F,T] = object
      exArgs: T
    FooUn[F,T] = Foo[F,tuple[a:T]]
    FooBi[F,T1,T2] = Foo[F,tuple[a:T1,b:T2]]

  proc foo1[F,T](x: Foo[F,tuple[a:T]]): int = 1
  proc foo1[F,T1,T2](x: Foo[F,tuple[a:T1,b:T2]]): int = 2
  proc foo2[F,T](x: FooUn[F,T]): int = 1
  proc foo2[F,T1,T2](x: FooBi[F,T1,T2]):int = 2

  template bar1[F,T](x: Foo[F,tuple[a:T]]): int = 1
  template bar1[F,T1,T2](x: Foo[F,tuple[a:T1,b:T2]]): int = 2
  template bar2[F,T](x: FooUn[F,T]): int = 1
  template bar2[F,T1,T2](x: FooBi[F,T1,T2]): int = 2

  proc test(x: auto, n: int) =
    doAssert(foo1(x) == n)
    doAssert(foo2(x) == n)
    doAssert(bar1(x) == n)
    doAssert(bar2(x) == n)

  var a: Foo[int, tuple[a:int]]
  test(a, 1)
  var b: FooUn[int, int]
  test(b, 1)
  var c: Foo[int, tuple[a:int,b:int]]
  test(c, 2)
  var d: FooBi[int, int, int]
  test(d, 2)


# inheritance and generics
block:
  type
    Foo[T] = object of RootObj
      x: T
    Bar[T] = object of Foo[T]
      y: T
    Baz[T] = object of Bar[T]
      z: T

  template t0(x: Foo[int]): int = 0
  template t0(x: Bar[int]): int = 1
  template t0(x: Foo[bool or int]): int = 10
  template t0(x: Bar[bool or int]): int = 11
  #template t0[T:bool or int](x: Bar[T]): int = 11
  template t0[T](x: Foo[T]): int = 20
  template t0[T](x: Bar[T]): int = 21
  proc p0(x: Foo[int]): int = 0
  proc p0(x: Bar[int]): int = 1
  #proc p0(x: Foo[bool or int]): int = 10
  #proc p0(x: Bar[bool or int]): int = 11
  proc p0[T](x: Foo[T]): int = 20
  proc p0[T](x: Bar[T]): int = 21

  var a: Foo[int]
  var b: Bar[int]
  var c: Baz[int]
  var d: Foo[bool]
  var e: Bar[bool]
  var f: Baz[bool]
  var g: Foo[float]
  var h: Bar[float]
  var i: Baz[float]
  doAssert(t0(a) == 0)
  doAssert(t0(b) == 1)
  doAssert(t0(c) == 1)
  doAssert(t0(d) == 10)
  doAssert(t0(e) == 11)
  doAssert(t0(f) == 11)
  doAssert(t0(g) == 20)
  doAssert(t0(h) == 21)
  #doAssert(t0(i) == 21)
  doAssert(p0(a) == 0)
  doAssert(p0(b) == 1)
  doAssert(p0(c) == 1)
  #doAssert(p0(d) == 10)
  #doAssert(p0(e) == 11)
  #doAssert(p0(f) == 11)
  doAssert(p0(g) == 20)
  doAssert(p0(h) == 21)
  doAssert(p0(i) == 21)

  #type
  #  f0 = proc(x:Foo)


block:
  type
    TilesetCT[n: static[int]] = distinct int
    TilesetRT = int
    Tileset = TilesetCT | TilesetRT

  func prepareTileset(tileset: var Tileset) = discard

  func prepareTileset(tileset: Tileset): Tileset =
    result = tileset
    result.prepareTileset

  var parsedTileset: TilesetRT
  prepareTileset(parsedTileset)


block:
  proc p1[T,U: SomeInteger|SomeFloat](x: T, y: U): int|float =
    when T is SomeInteger and U is SomeInteger:
      result = int(x) + int(y)
    else:
      result = float(x) + float(y)
  doAssert(p1(1,2) == 3)
  doAssert(p1(1.0,2) == 3.0)
  doAssert(p1(1,2.0) == 3.0)
  doAssert(p1(1.0,2.0) == 3.0)

  type Foo[T,U] = U
  template F[T,U](t: typedesc[T], x: U): untyped = Foo[T,U](x)
  proc p2[T; U,V:Foo[T,SomeNumber]](x: U, y: V): T =
    T(x) + T(y)
  #proc p2[T; U:Foo[T,SomeNumber], V:Foo[not T,SomeNumber]](x: U, y: V): T =
  #  T(x) + T(y)
  doAssert(p2(F(int,1),F(int,2)) == 3)
  doAssert(p2(F(float,1),F(float,2)) == 3.0)
  doAssert(p2(F(float,1),F(float,2.0)) == 3.0)
  doAssert(p2(F(float,1.0),F(float,2)) == 3.0)
  doAssert(p2(F(float,1.0),F(float,2.0)) == 3.0)
  #doAssert(p2(F(float,1),F(int,2.0)) == 3.0)

block: # PR #23870
  type
    A {.inheritable.} = object
    B = object of A
    C = object of B

  proc p[T: A](x: T): int = 0
  proc p[T: B](x: T): int = 1

  proc d(x: A): int = 0
  proc d(x: B): int = 1
  
  proc g[T:A](x: typedesc[T]): int = 0
  proc g[T: B](x: typedesc[T]): int = 1
  
  proc f[T](x: typedesc[T]): int = 0
  proc f[T:B](x: typedesc[T]): int = 1

  assert p(C()) == 1
  assert d(C()) == 1
  assert g(C) == 1
  assert f(C) == 1

block: # PR #23870
  type
    A = object of RootObj
    PT = proc(ev: A) {.closure.}
    sdt = seq[(PT, PT)]

  proc encap() =
    proc p(a: A) {.closure.} =
      discard

    var s: sdt
    s.add (p, nil)

  encap()

block: # PR #23870
  type
    A = object of RootObj
    B = object of A
    C = object of B

  proc p(a: B | RootObj): int =
    0

  proc p(a: A | A): int =
    1

  assert p(C()) == 0

  proc d(a: RootObj | B): int =
    0

  proc d(a: A | A): int =
    1

  assert d(C()) == 0

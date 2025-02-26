discard """
  output: '''
4
3
(weight: 17.0, color: 100)
perm: 22 det: 22
TMatrix[3, 3, system.int]
3
@[0.9, 0.1]
U[3]
U[(f: 3)]
U[[3]]
b()
@[1, 2]
@[3, 4]
1
concrete 88
123
1
2
3
!!Hi!!
G:0,1:0.1
G:0,1:0.1
H:1:0.1
0
(foo: none(seq[Foo]), s: "")
(foo: some(@[(a: "world", bar: none(Bar))]), s: "hello,")
@[(a: "hey", bar: none(Bar))]
'''
joinable: false
"""

import macros, sequtils, sets, sugar, tables, typetraits

block t88:
  type
    BaseClass[V] = object of RootObj
      b: V

  proc new[V](t: typedesc[BaseClass], v: V): BaseClass[V] =
    BaseClass[V](b: v)

  proc baseMethod[V](v: BaseClass[V]): V = v.b
  proc overriddenMethod[V](v: BaseClass[V]): V = v.baseMethod

  type
    ChildClass[V] = object of BaseClass[V]
      c: V

  proc new[V](t: typedesc[ChildClass], v1, v2: V): ChildClass[V] =
    ChildClass[V](b: v1, c: v2)

  proc overriddenMethod[V](v: ChildClass[V]): V = v.c

  let c = ChildClass[string].new("Base", "Child")

  doAssert c.baseMethod == "Base"
  doAssert c.overriddenMethod == "Child"



block t4528:
  type GenericBase[T] = ref object of RootObj
  type GenericSubclass[T] = ref object of GenericBase[T]
  proc foo[T](g: GenericBase[T]) = discard
  var bar: GenericSubclass[int]
  foo(bar)



block t1050_5597:
  type ArrayType[T] = distinct T

  proc arrayItem(a: ArrayType): auto =
    static: echo(name(type(a).T))
    result = (type(a).T)(4)

  var arr: ArrayType[int]
  echo arrayItem(arr)

  # bug #5597

  template fail() = "what"

  proc g[T](x: var T) =
    x.fail = 3

  type
    Obj = object
      fail: int

  var y: Obj
  g y



block t1789:
  type
    Foo[N: static[int]] = object

  proc bindStaticN[N](foo: Foo[N]) =
    var ar0: array[3, int]
    var ar1: array[N, int]
    var ar2: array[1..N, int]
    var ar3: array[0..(N+10), float]
    echo N

  var f: Foo[3]
  f.bindStaticN

  # case 2

  type
    ObjectWithStatic[X, Y: static[int], T] = object
      bar: array[X * Y, T]   # this one works

    AliasWithStatic[X, Y: static[int], T] = array[X * Y, T]

  var
    x: ObjectWithStatic[1, 2, int]
    y: AliasWithStatic[2, 3, int]

  # case 3

  type
    Bar[N: static[int], T] = object
      bar: array[N, T]

  proc `[]`[N, T](f: Bar[N, T], n: range[0..(N - 1)]): T =
    doAssert high(n) == N-1
    result = f.bar[n]

  var b: Bar[3, int]
  doAssert b[2] == 0



block t3977:
  type Foo[N: static[int]] = object

  proc foo[N](x: Foo[N]) =
    let n = N
    doAssert N == n

  var f1: Foo[42]
  f1.foo



block t5570:
  type
    BaseFruit[T] = object of RootObj
      color: T

    Banana[T] = object of BaseFruit[uint32]
      weight: T

  macro printTypeName(typ: typed): untyped =
    echo "type ", getType(typ).repr

  proc setColor[K](self: var BaseFruit[K], c: int) =
    printTypeName(self.color)
    self.color = uint32(c)

  var x: Banana[float64]
  x.weight = 17
  printTypeName(x.color)
  x.setColor(100)
  echo x



block t5643:
  type
    Matrix[M, N: static[int], T: SomeFloat] = object
      data: ref array[N * M, T]
    Matrix64[M, N: static[int]] = Matrix[M, N, float64]

  proc zeros64(M,N: static[int]): Matrix64[M,N] =
    new result.data
    for i in 0 ..< (M * N):
      result.data[i] = 0'f64

  proc bar[M,N: static[int], T](a: Matrix[M,N,T], b: Matrix[M,N,T]) =
    discard

  let a = zeros64(2,2)
  bar(a,a)
    # https://github.com/nim-lang/Nim/issues/5643
    #
    # The test case was failing here, because the compiler failed to
    # detect the two matrix instantiations as the same type.
    #
    # The root cause was that the `T` type variable is a different
    # type after the first Matrix type has been matched.
    #
    # Sigmatch was failing to match the second version of `T`, but
    # due to some complex interplay between tyOr, tyTypeDesc and
    # tyGenericParam this was allowed to went through. The generic
    # instantiation of the second matrix was incomplete and the
    # generic cache lookup failed, producing two separate types.



block t5683:
  type Matrix[M,N: static[int]] = array[M, array[N, float]]

  proc det[M,N](a: Matrix[M,N]): int = N*10 + M
  proc perm[M,N](a: Matrix[M,N]): int = M*10 + N

  const
    a = [ [1.0, 2.0]
        , [3.0, 4.0]
        ]

  echo "perm: ", a.perm, " det: ", a.det

  # This tests multiple instantiations of a generic
  # proc involving static params:
  type
    Vector64[N: static[int]] = ref array[N, float64]
    Array64[N: static[int]] = array[N, float64]

  proc vector[N: static[int]](xs: Array64[N]): Vector64[N] =
    new result
    for i in 0 ..< N:
      result[i] = xs[i]

  let v1 = vector([1.0, 2.0, 3.0, 4.0, 5.0])
  let v2 = vector([1.0, 2.0, 3.0, 4.0, 5.0])
  let v3 = vector([1.0, 2.0, 3.0, 4.0])



block t7794:
  type
    Data[T:SomeNumber, U:SomeFloat] = ref object
      x: T
      value*: U

  var d = Data[int, float64](x:10.int, value:2'f64)
  doAssert d.x == 10
  doAssert d.value == 2.0



block t8403:
  proc sum[T](s: seq[T], R: typedesc): R =
    var sum: R = 0
    for x in s:
      sum += R(x)
    return sum

  doAssert @[1, 2, 3].sum(float) == 6.0



block t8439:
  type
    Cardinal = enum
      north, east, south, west

  proc foo[cardinal: static[Cardinal]](): int = 1
  doAssert foo[north]() == 1



block t8694:
  when true:
    # Error: undeclared identifier: '|'
    proc bar[T](t:T): bool =
      runnableExamples:
        type Foo = int | float
      true
    doAssert bar(0)

  when true:
    # ok
    proc bar(t:int): bool =
      runnableExamples:
        type Foo = int | float
      true
    doAssert bar(0)

  when true:
    # Error: undeclared identifier: '|'
    proc bar(t:typedesc): bool =
      runnableExamples:
        type Foo = int | float
      true
    doAssert bar(int)



block t9130:
  when true:
    # stack overflow
    template baz1(iter: untyped): untyped =
      runnableExamples:
        import sugar
        proc fun(a: proc(x:int): int) = discard
        baz1(fun(x:int => x))
      discard

    proc foo1[A](ts: A) =
      baz1(ts)

  when true:
    # ok
    template baz2(iter: untyped): untyped =
      runnableExamples:
        import sugar
        proc fun(a: proc(x:int): int) = discard
        baz2(fun(x:int => x))
      discard

    proc foo2(ts: int) =
      baz2(ts)

  when true:
    # stack overflow
    template baz3(iter: untyped): untyped =
      runnableExamples:
        baz3(fun(x:int => x))
      discard

    proc foo3[A](ts: A) =
      baz3(ts)



block t1056:
  type
    TMatrix[N,M: static[int], T] = object
      data: array[0..N*M-1, T]

    TMat2[T] = TMatrix[2,2,T]

  proc echoMatrix(a: TMatrix) =
    echo a.type.name
    echo TMatrix.N

  proc echoMat2(a: TMat2) =
    echo TMat2.M

  var m = TMatrix[3,3,int](data: [1,2,3,4,5,6,7,8,9])

  echoMatrix m



block t4884:
  type
    Vec[N: static[int], T] = object
      arr*: array[N, T]

    Mat[N,M: static[int], T] = object
      arr: array[N, Vec[M,T]]

  var m : Mat[3,3,float]
  var strMat : Mat[m.N, m.M, string]
  var lenMat : Mat[m.N, m.M, int]



block t2221:
  var tblo: TableRef[string, int]
  doAssert tblo == nil



block t2304:
  type TV2[T:SomeNumber] = array[0..1, T]
  proc newV2T[T](x, y: T=0): TV2[T] = [x, y]

  let x = newV2T[float](0.9, 0.1)
  echo(@x)



block t2752:
  proc myFilter[T](it: (iterator(): T), f: (proc(anything: T):bool)): (iterator(): T) =
    iterator aNameWhichWillConflict(): T {.closure.}=
      for x in it():
        if f(x):
          yield x
    result = aNameWhichWillConflict

  iterator testIt():int {.closure.}=
    yield -1
    yield 2

  #let unusedVariable = myFilter(testIt, (x: int) => x > 0)

  proc onlyPos(it: (iterator(): int)): (iterator(): int)=
    iterator aNameWhichWillConflict(): int {.closure.}=
      var filtered = onlyPos(myFilter(it, (x:int) => x > 0))
      for x in filtered():
        yield x
    result = aNameWhichWillConflict

  let x = onlyPos(testIt)



block t5106:
  block:
    type T = distinct int

    proc `+`(a, b: T): T =
      T(int(a) + int(b))

    type U[F: static[T]] = distinct int

    proc `+`[P1, P2: static[T]](a: U[P1], b: U[P2]): U[P1 + P2] =
      U[P1 + P2](int(a) + int(b))

    var a = U[T(1)](1)
    var b = U[T(2)](2)
    var c = a + b
    echo c.type.name

  block:
    type T = object
      f: int

    proc `+`(a, b: T): T =
      T(f: a.f + b.f)

    type U[F: static[T]] = distinct int

    proc `+`[P1, P2: static[T]](a: U[P1], b: U[P2]): U[P1 + P2] =
      U[P1 + P2](int(a) + int(b))

    var a = U[T(f: 1)](1)
    var b = U[T(f: 2)](2)
    var c = a + b
    echo c.type.name

  block:
    type T = distinct array[0..0, int]

    proc `+`(a, b: T): T =
      T([array[0..0, int](a)[0] + array[0..0, int](b)[0]])

    type U[F: static[T]] = distinct int

    proc `+`[P1, P2: static[T]](a: U[P1], b: U[P2]): U[P1 + P2] =
      U[P1 + P2](int(a) + int(b))

    var a = U[T([1])](1)
    var b = U[T([2])](2)
    var c = a + b
    echo c.type.name



block t3055:
  proc b(t: int | string)
  proc a(t: int) = b(t)
  proc b(t: int | string) = echo "b()"
  a(1)

  # test recursive generics still work:
  proc fac[T](x: T): T =
    if x == 0: return 1
    else: return fac(x-1)*x

  doAssert fac(6) == 720
  doAssert fac(5.0) == 120.0


  # test recursive generic with forwarding:
  proc fac2[T](x: T): T

  doAssert fac2(6) == 720
  doAssert fac2(5.0) == 120.0

  proc fac2[T](x: T): T =
    if x == 0: return 1
    else: return fac2(x-1)*x



block t1187:
  type
    TEventArgs = object
      skip: bool
    TEventHandler[T] = proc (e: var TEventArgs, data: T) {.closure.}
    TEvent[T] = object
      #handlers: seq[TEventHandler[T]] # Does not work
      handlers: seq[proc (e: var TEventArgs, d: T) {.closure.}] # works

    TData = object
      x: int

    TSomething = object
      s: TEvent[TData]

  proc init[T](e: var TEvent[T]) =
    e.handlers.newSeq(0)

  #proc add*[T](e: var TEvent[T], h: proc (e: var TEventArgs, data: T) {.closure.}) =
  # this line works
  proc add[T](e: var TEvent[T], h: TEventHandler[T]) =
    # this line does not work
    e.handlers.add(h)

  proc main () =
    var something: TSomething
    something.s.init()
    var fromOutside = 4711

    something.s.add() do (e: var TEventArgs, data: TData):
      var x = data.x
      x = fromOutside

  main()



block t1919:
  type
    Base[M] = object of RootObj
      a : M
    Sub1[M] = object of Base[M]
      b : int
    Sub2[M] = object of Sub1[M]
      c : int

  var x: Sub2[float]
  doAssert x.a == 0.0



block t5756:
  type
    Vec[N : static[int]] = object
      x: int
      arr: array[N, int32]

    Mat[M,N: static[int]] = object
      x: int
      arr: array[M, Vec[N]]

  proc vec2(x,y:int32) : Vec[2] =
    result.arr = [x,y]
    result.x = 10

  proc mat2(a,b: Vec[2]): Mat[2,2] =
    result.arr = [a,b]
    result.x = 20

  const M = mat2(vec2(1, 2), vec2(3, 4))

  let m1 = M
  echo @(m1.arr[0].arr)
  echo @(m1.arr[1].arr)

  proc foo =
    let m2 = M
    echo m1.arr[0].arr[0]

  foo()



block t7854:
  type
    Stream = ref StreamObj
    StreamObj = object of RootObj

    InhStream = ref InhStreamObj
    InhStreamObj = object of Stream
      f: string

  proc newInhStream(f: string): InhStream =
    new(result)
    result.f = f

  var val: int
  let str = newInhStream("input_file.json")

  block:
    # works:
    proc load[T](data: var T, s: Stream) =
      discard
    load(val, str)

  block:
    # works
    proc load[T](s: Stream, data: T) =
      discard
    load(str, val)

  block:
    # broken
    proc load[T](s: Stream, data: var T) =
      discard
    load(str, val)



block t5864:
  proc defaultStatic(s: openArray, N: static[int] = 1): int = N
  proc defaultGeneric[T](a: T = 2): int = a

  let a = [1, 2, 3, 4].defaultStatic()
  let b = defaultGeneric()

  doAssert a == 1
  doAssert b == 2



block t3498:
  template defaultOf[T](t: T): untyped = (var d: T; d)

  doAssert defaultOf(1) == 0

  # assignment using template

  template tassign[T](x: var seq[T]) =
    x = @[1, 2, 3]

  var y: seq[int]
  tassign(y) #<- x is expected = @[1, 2, 3]
  tassign(y)

  doAssert y[0] == 1
  doAssert y[1] == 2
  doAssert y[2] == 3



block t3499:
  proc foo[T](x: proc(): T) =
    echo "generic ", x()

  proc foo(x: proc(): int) =
    echo "concrete ", x()

  # note the following 'proc' is not .closure!
  foo(proc (): auto {.nimcall.} = 88)

  # bug #3499 last snippet fixed
  # bug 705  last snippet fixed




block t797:
  proc foo[T](s:T):string = $s

  type IntStringProc = proc(x: int): string

  var f1 = IntStringProc(foo)
  var f2: proc(x: int): string = foo
  var f3: IntStringProc = foo

  echo f1(1), f2(2), f3(3)

  for x in map([1,2,3], foo): echo x



block t4658:
  var x = 123
  proc twice[T](f: T -> T): T -> T = (x: T) => f(f(x))
  proc quote(s: string): string = "!" & s & "!"
  echo twice(quote)("Hi")



block t4589:
  type SimpleTable[TKey, TVal] = TableRef[TKey, TVal]
  template newSimpleTable(TKey, TVal: typedesc): SimpleTable[TKey, TVal] = newTable[TKey, TVal]()
  var fontCache : SimpleTable[string, SimpleTable[int32, int]]
  fontCache = newSimpleTable(string, SimpleTable[int32, int])



block t4600:
  template foo(x: untyped): untyped = echo 1
  template foo(x,y: untyped): untyped = echo 2

  proc bar1[T](x: T) = foo(x)
  proc bar2(x: float) = foo(x,x)
  proc bar3[T](x: T) = foo(x,x)



block t4672:
  type
    EnumContainer[T: enum] = object
      v: T
    SomeEnum {.pure.} = enum
      A,B,C

  proc value[T: enum](this: EnumContainer[T]): T =
    this.v

  var enumContainer: EnumContainer[SomeEnum]
  discard enumContainer.value()



block t4863:
  type
    G[i,j: static[int]] = object
      v:float
    H[j: static[int]] = G[0,j]
  proc p[i,j: static[int]](x:G[i,j]) = echo "G:", i, ",", j, ":", x.v
  proc q[j: static[int]](x:H[j]) = echo "H:", j, ":", x.v

  var
    g0 = G[0,1](v: 0.1)
    h0:H[1] = g0
  p(g0)
  p(h0)
  q(h0)



block t1684:
  type
    BaseType {.inheritable pure.} = object
      idx: int

    DerivedType {.final pure.} = object of BaseType

  proc index[Toohoo: BaseType](h: Toohoo): int {.inline.} = h.idx
  proc newDerived(idx: int): DerivedType {.inline.} = DerivedType(idx: idx)

  let d = newDerived(2)
  doAssert(d.index == 2)



block t5632:
  type Option[T] = object

  # original issue test uses Option[A] instead
  proc point[A](v: A, t: typedesc[Option]): Option[A] =
    discard

  discard point(1, Option)



block t7247:
  type n8 = range[0'i8..127'i8]
  var tab = initHashSet[n8]()
  doAssert tab.contains(8) == false



block t3717:
  type
    Foo[T] = object
      a: T
    Foo1[T] = Foo[T] | int

  proc foo[T](s: Foo1[Foo[T]]): T =
    5

  var f: Foo[Foo[int]]
  discard foo(f)



block: # issue #9458
  type
    Option[T] = object
      val: T
      has: bool

    Bar = object

  proc none(T: typedesc): Option[T] =
    discard

  proc foo[T](self: T; x: Option[Bar] = Bar.none) =
    discard

  foo(1)


# bug #8426
type
  MyBool[T: uint] = range[T(0)..T(1)] # Works

var x: MyBool[uint]
echo x

# x = 2 # correctly prevented

type
  MyBool2 = range[uint(0)..uint(1)] # Error ordinal or float type expected


# bug #10396
import options, strutils

type
  Foo {.acyclic.} = object
    a: string
    bar: Option[Bar]

  Bar {.acyclic.} = object
    foo: Option[seq[Foo]]   # if this was just Option[Foo], everything works fine
    s: string

proc getBar(x: string): Bar

proc intoFoos(ss: seq[string]): seq[Foo] =
  result = @[]
  for s in ss:
    let spl = s.split(',')
    if spl.len > 1:
      result.add Foo(a: spl[0],
                     bar: some(getBar(spl[1])))
    else:
      result.add Foo(a: s,
                     bar: none[Bar]())

proc getBar(x: string): Bar =
  let spl = x.split(' ')
  result =
    if spl.len > 1:
      Bar(foo: some(spl[1..high(spl)].intoFoos),
          s: spl[0])
    else:
      Bar(foo: none[seq[Foo]](),
          s: "")

proc fakeReadLine(): string = "hey"

echo getBar(fakeReadLine()) # causes error

echo getBar("hello, world") # causes error

discard $getBar(fakeReadLine()) # causes error

discard $getBar("hello, world") # causes error

discard getBar(fakeReadLine()) # no error

discard getBar("hello, world") # no error

echo intoFoos(fakeReadLine().split(' ')) # no error, works as expected


# bug #14990
type
  Tile3 = Tile2
  Tile2 = Tile
  Tile[n] = object
    a: n

var a: Tile3[int]

block: # Ensure no segfault from constraint
  type
    Regex[A: SomeOrdinal] = ref object
      val: Regex[A]
    MyConstraint = (seq or enum or set)
    MyOtherType[A: MyConstraint] = ref object
      val: MyOtherType[A]

  var
    a = Regex[int]()
    b = Regex[bool]()
    c = MyOtherType[seq[int]]()

block: # https://github.com/nim-lang/Nim/issues/20416
  type
    Item[T] = object
      link:ptr Item[T]
      data:T

    KVSeq[A,B] = seq[(A,B)]

    MyTable[A,B] = object
      data: KVSeq[A,B]

    Container[T] = object
      a: MyTable[int,ref Item[T]]

  proc p1(sg:Container) = discard # Make sure that a non parameterized 'Container' argument still compiles

  proc p2[T](sg:Container[T]) = discard
  var v : Container[int]
  p2(v)

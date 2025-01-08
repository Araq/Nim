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

block: # deref syntax
  type
    Enqueueable = concept x
      x is ptr
    Foo[T: Enqueueable] = object
      x: typeof(default(T)[])

  proc p[T](f: Foo[T]) =
    var bar: Foo[T]
    discard
  var foo: Foo[ptr int]
  p(foo)
  doAssert foo.x is int
  foo.x = 123
  doAssert foo.x == 123
  inc foo.x
  doAssert foo.x == 124

block:
  type Generic[T] = object
    field: T
  macro foo(x: typed): untyped = x
  macro bar[T](x: typedesc[Generic[T]]): untyped = x
  type
    Foo[T] = object
      field: Generic[int].foo()
    Foo2[T] = object
      field: Generic[T].foo()
    Bar[T] = object
      field: Generic[int].bar()
    Bar2[T] = object
      field: Generic[T].bar()
  var x: Foo[int]
  var x2: Foo2[int]
  var y: Bar[int]
  var y2: Bar2[int]

block:
  macro pick(x: static int): untyped =
    if x < 100:
      result = bindSym"int"
    else:
      result = bindSym"float"
  
  type Foo[T: static int] = object
    fixed1: pick(25)
    fixed2: pick(125)
    unknown: pick(T)
  
  var a: Foo[123]
  doAssert a.fixed1 is int
  doAssert a.fixed2 is float
  doAssert a.unknown is float
  var b: Foo[23]
  doAssert b.fixed1 is int
  doAssert b.fixed2 is float
  doAssert b.unknown is int

import std/sequtils

block: # version of #23432 with `typed`, don't delay instantiation
  type
    Future[T] = object
    InternalRaisesFuture[T, E] = object
  macro Raising[T](F: typedesc[Future[T]], E: varargs[typed]): untyped =
    let raises = nnkTupleConstr.newTree(E.mapIt(it))
    nnkBracketExpr.newTree(
      ident "InternalRaisesFuture",
      nnkDotExpr.newTree(F, ident"T"),
      raises
    )
  type X[E] = Future[void].Raising(E)
  proc f(x: X) = discard
  var v: Future[void].Raising([ValueError])
  f(v)

block: # issue #22647
  proc c0(n: static int): int = 8
  proc c1(n: static int): int = n div 2
  proc c2(n: static int): int = n * 2
  proc c3(n: static int, n2: int): int = n * n2
  proc `**`(n: static int, n2: int): int = n * n2
  proc c4(n: int, n2: int): int = n * n2

  type
    a[N: static int] = object
      f0 : array[N, int]

    b[N: static int] = object
      f0 : a[c0(N)]  # does not work
      f1 : a[c1(N)]  # does not work
      f2 : a[c2(N)]  # does not work
      f3 : a[N * 2]  # does not work
      f4 : a[N]      # works
      f5: a[c3(N, 2)]
      f6: a[N ** 2]
      f7: a[2 * N]
      f8: a[c4(N, 2)]

  proc p[N: static int](x : a[N]) = discard x.f0[0]
  template check(x, s: untyped) =
    p(x)
    doAssert x is a[s]
    doAssert x.N == s
    doAssert typeof(x).N == s
    doAssert x.f0 == default(array[s, int])
    doAssert x.f0.len == s
    proc p2[N: static int](y : a[N]) {.gensym.} =
      doAssert y is a[s]
      doAssert y.N == s
      doAssert typeof(y).N == s
      doAssert y.f0 == default(array[s, int])
      doAssert y.f0.len == s
    p2(x)
    proc p3(z: typeof(x)) {.gensym.} = discard
    p3(default(a[s]))
  proc p[N: static int](x : b[N]) =
    x.f0.check(8)
    x.f1.check(2)
    x.f2.check(8)
    x.f3.check(8)
    x.f4.check(4)
    x.f5.check(8)
    x.f6.check(8)
    x.f7.check(8)
    x.f8.check(8)

  var x: b[4]
  x.p()

block: # issue #1969
  type ZeroGenerator = object
  proc next(g: ZeroGenerator): int = 0
  # This compiles.
  type TripleOfInts = tuple
    a, b, c: typeof(new(ZeroGenerator)[].next)
  # This raises a compiler error before it's even instantiated.
  # The `new` proc can't be resolved because `Generator` is not defined.
  type TripleLike[Generator] = tuple
    a, b, c: typeof(new(Generator)[].next)

import std/atomics

block: # issue #12720
  const CacheLineSize = 128
  type
    Enqueueable = concept x, type T
      x is ptr
      x.next is Atomic[pointer]
    MyChannel[T: Enqueueable] = object
      pad: array[CacheLineSize - sizeof(default(T)[]), byte]
      dummy: typeof(default(T)[])

block: # issue #12714
  type
    Enqueueable = concept x, type T
      x is ptr
      x.next is Atomic[pointer]
    MyChannel[T: Enqueueable] = object
      dummy: type(default(T)[])

block: # issue #24044
  type ArrayBuf[N: static int, T = byte] = object
    buf: array[N, T]
  template maxLen(T: type): int =
    sizeof(T) * 2
  type MyBuf[I] = ArrayBuf[maxLen(I)]
  var v: MyBuf[int]

block: # issue #15959
  proc my[T](a: T): typeof(a[0]) = discard
  proc my2[T](a: T): array[sizeof(a[0]), T] = discard
  proc byLent2[T](a: T): lent type(a[0]) = a[0] # Error: type mismatch: got <T, int literal(0)>
  proc byLent3[T](a: T): lent typeof(a[0]) = a[0] # ditto
  proc byLent4[T](a: T): lent[type(a[0])] = a[0] # Error: no generic parameters allowed for lent
  var x = @[1, 2, 3]
  doAssert my(x) is int
  doAssert my2(x) is array[sizeof(int), seq[int]]
  doAssert byLent2(x) == 1
  doAssert byLent2(x) is lent int
  doAssert byLent3(x) == 1
  doAssert byLent3(x) is lent int
  doAssert byLent4(x) == 1
  doAssert byLent4(x) is lent int
  proc fn[U](a: U): auto = a
  proc my3[T](a: T, b: typeof(fn(a))) = discard
  my3(x, x)
  doAssert not compiles(my3(x, x[0]))

block: # issue #14877
  proc fn[T](a: T, index: int): typeof(a.x) = a.x # ok
  proc fn2(a: seq[int], index: int): typeof(a[0]) = a[index] # ok
  proc fn3[T](a: T, index: int): typeof(a[0]) = a[index] # Error: type mismatch: got <T, int literal(0)>

block: # issue #22342, type section version of #22607
  type GenAlias[isInt: static bool] = (
    when isInt:
      int
    else:
      float
  )
  doAssert GenAlias[true] is int
  doAssert GenAlias[false] is float
  proc foo(T: static bool): GenAlias[T] = discard
  doAssert foo(true) is int
  doAssert foo(false) is float
  proc foo[T: static bool](v: var GenAlias[T]) =
    v += 1
  var x: int
  foo[true](x)
  doAssert not compiles(foo[false](x))
  foo[true](x)
  doAssert x == 2
  var y: float
  foo[false](y)
  doAssert not compiles(foo[true](y))
  foo[false](y)
  doAssert y == 2

block: # `when`, test no constant semchecks
  type Foo[T] = (
    when false:
      {.error: "bad".}
    elif defined(neverDefined):
      {.error: "bad 2".}
    else:
      T
  )
  var x: Foo[int]
  type Bar[T] = (
    when true:
      T
    elif defined(js):
      {.error: "bad".}
    else:
      {.error: "bad 2".}
  )
  var y: Bar[int]

block: # weird regression
  type
    Foo[T] = distinct int
    Bar[T, U] = distinct int
  proc foo[T, U](x: static Foo[T], y: static Bar[T, U]): Foo[T] =
    # signature gives:
    # Error: cannot instantiate Bar
    # got: <typedesc[T], U>
    # but expected: <T, U>
    x
  doAssert foo(Foo[int](1), Bar[int, int](2)).int == 1

block: # issue #24090
  type M[V] = object
  template y[V](N: type M, v: V): M[V] = default(M[V])
  proc d(x: int | int, f: M[int] = M.y(0)) = discard
  d(0, M.y(0))
  type Foo[T] = object
    x: typeof(M.y(default(T)))
  var a: Foo[int]
  doAssert a.x is M[int]
  var b: Foo[float]
  doAssert b.x is M[float]
  # related to #24091:
  doAssert not (compiles do:
    type Bar[T] = object
      # ideally fails here immediately since the inside of `typeof` does not
      # depend on an unresolved parameter
      # but if typechecking gets too lazy, then we need to instantiate to error
      x: typeof(M()))
  doAssert not (compiles do:
    type Bar[T] = object
      # again, ideally fails here immediately
      x: typeof(default(M)))
  proc foo[T: M](x: T = default(T)) = discard x
  foo[M[int]]()
  doAssert not compiles(foo())

block: # above but encountered by sigmatch using replaceTypeVarsN
  type Opt[T] = object
    x: T
  proc none[T](x: type Opt, y: typedesc[T]): Opt[T] = discard
  proc foo[T](x: T, a = Opt.none(int)) = discard
  foo(1, a = Opt.none(int))
  foo(1)

block: # real version of above
  type Opt[T] = object
    x: T
  template none(x: type Opt, T: type): Opt[T] = Opt[T]()
  proc foo[T](x: T, a = Opt.none(int)) = discard
  foo(1, a = Opt.none(int))
  foo(1)

block: # issue #20880
  type
    Child[n: static int] = object
      data: array[n, int]
    Parent[n: static int] = object
      child: Child[3*n]
  const n = 3
  doAssert $(typeof Parent[n*3]()) == "Parent[9]"
  doAssert $(typeof Parent[1]().child) == "Child[3]"
  doAssert Parent[1]().child.data.len == 3

{.experimental: "dynamicBindSym".}
block: # issue #16774
  type SecretWord = distinct uint64
  const WordBitWidth = 8 * sizeof(uint64)
  func wordsRequired(bits: int): int {.compileTime.} =
    ## Compute the number of limbs required
    # from the **announced** bit length
    (bits + WordBitWidth - 1) div WordBitWidth
  type
    Curve = enum BLS12_381
    BigInt[bits: static int] = object
      limbs: array[bits.wordsRequired, SecretWord]
  const BLS12_381_Modulus = default(BigInt[381])
  macro Mod(C: static Curve): untyped =
    ## Get the Modulus associated to a curve
    result = bindSym($C & "_Modulus")
  macro getCurveBitwidth(C: static Curve): untyped =
    result = nnkDotExpr.newTree(
      getAST(Mod(C)),
      ident"bits"
    )
  type Fp[C: static Curve] = object
    ## Finite Fields / Modular arithmetic
    ## modulo the curve modulus
    mres: BigInt[getCurveBitwidth(C)]
  var x: Fp[BLS12_381]
  doAssert x.mres.limbs.len == wordsRequired(getCurveBitWidth(BLS12_381))
  # minimized, as if we haven't tested it already:
  macro makeIntLit(c: static int): untyped =
    result = newLit(c)
  type Test[T: static int] = object
    myArray: array[makeIntLit(T), int]
  var y: Test[2]
  doAssert y.myArray.len == 2
  var z: Test[4]
  doAssert z.myArray.len == 4

block: # issue #16175
  type
    Thing[D: static uint] = object
      when D == 0:
        kid: char
      else:
        kid: Thing[D-1]
  var t2 = Thing[3]()
  doAssert t2.kid is Thing[2.uint]
  doAssert t2.kid.kid is Thing[1.uint]
  doAssert t2.kid.kid.kid is Thing[0.uint]
  doAssert t2.kid.kid.kid.kid is char
  var s = Thing[1]()
  doAssert s.kid is Thing[0.uint]
  doAssert s.kid.kid is char

block: # issue #23287
  template emitTupleType(trait: typedesc): untyped =
    trait

  type
    Traitor[Traits] = ref object of RootObj ##
      vtable: emitTupleType(Traits)

  type Generic[X] = object

  proc test2[Traits](val: Traitor[Generic[Traits]]) =
    static: assert val.vtable is Generic[int]

  proc test[X](val: Traitor[Generic[X]]) = discard

  test2 Traitor[Generic[int]]() # This should error,  but passes
  test Traitor[Generic[int]]()

block: # issue #20367, example 1
  template someTemp(T:type):typedesc = T
  type
    Foo[T2] = someTemp(T2)
    Bar[T1] = Foo[T1]
  var u:Foo[float] # works
  var v:Bar[float] # Error: invalid type: 'None' in this context: 'Bar[system.float]' for var

block: # issue #20367, example 2
  template someOtherTemp(p:static[int]):untyped = array[p,int]
  type
    Foo2[n:static[int]] = someOtherTemp(n)
    Bar2[m:static[int]] = Foo2[m]
  var x:Foo2[1] # works
  var y:Bar2[1] # Error: undeclared identifier: 'n'

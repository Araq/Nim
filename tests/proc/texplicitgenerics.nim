block: # issue #16376
  type
    Matrix[T] = object
      data: T
  proc randMatrix[T](m, n: int, max: T): Matrix[T] = discard
  proc randMatrix[T](m, n: int, x: Slice[T]): Matrix[T] = discard
  template randMatrix[T](m, n: int): Matrix[T] = randMatrix[T](m, n, T(1.0))
  let B = randMatrix[float32](20, 10)

block: # different generic param counts 
  type
    Matrix[T] = object
      data: T
  proc randMatrix[T](m: T, n: T): Matrix[T] = Matrix[T](data: T(1.0))
  proc randMatrix[T; U: not T](m: T, n: U): (Matrix[T], U) = (Matrix[T](data: T(1.0)), default(U))
  let b = randMatrix[float32](20, 10)
  doAssert b == Matrix[float32](data: 1.0)

block: # above for templates 
  type
    Matrix[T] = object
      data: T
  template randMatrix[T](m: T, n: T): Matrix[T] = Matrix[T](data: T(1.0))
  template randMatrix[T; U: not T](m: T, n: U): (Matrix[T], U) = (Matrix[T](data: T(1.0)), default(U))
  let b = randMatrix[float32](20, 10)
  doAssert b == Matrix[float32](data: 1.0)

block: # sigmatch can't handle this without pre-instantiating the type:
  # minimized from numericalnim
  type Foo[T] = proc (x: T)
  proc foo[T](x: T) = discard
  proc bar[T](f: Foo[T]) = discard
  bar[int](foo)

block: # ditto but may be wrong minimization
  # minimized from measuremancer
  type Foo[T] = object
  proc foo[T](): Foo[T] = Foo[T]()
  # this is the actual issue but there are other instantiation problems
  proc bar[T](x = foo[T]()) = discard
  bar[int](Foo[int]())
  bar[int]()
  # alternative version, also causes instantiation issue
  proc baz[T](x: typeof(foo[T]())) = discard
  baz[int](Foo[int]())

block: # issue #21346
  type K[T] = object
  template s[T](x: int) = doAssert T is K[K[int]]
  proc b1(n: bool | bool) = s[K[K[int]]](3)
  proc b2(n: bool)        = s[K[K[int]]](3)
  template b3(n: bool)    = s[K[K[int]]](3)
  b1(false)     # Error: cannot instantiate K; got: <T> but expected: <T>
  b2(false)     # Builds, on its own
  b3(false)

block: # explicit generic with unresolved generic param, https://forum.nim-lang.org/t/12579
  var s: seq[string] = @[]
  proc MyMedian[T](A: var openArray[T],myCmp : proc(x,y:T):int {.nimcall.} = cmp[T]) : T =
    if myCmp(A[0], A[1]) == 0: s.add("1")
  var x = [1, 1]
  discard MyMedian(x) # emits "1\n"
  doAssert s == @["1"]

block: # issue #16153
  type
    X[T] = openArray[T] | varargs[T] | seq[T]
    Y[T] = ref object
      dll: T

  proc initY[T](): Y[T] =
    new(result)

  proc initY[T](v: X[T]): Y[T] =
    new(result)
    for e in v:
      echo e

  var deque: Y[int] = initY[int]()

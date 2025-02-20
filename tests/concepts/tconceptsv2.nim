discard """
action: "run"
output: '''
B[system.int]
A[system.string]
A[array[0..0, int]]
A[seq[int]]
100
a
b
c
a
b
c
'''
"""
import conceptsv2_helper

block: # issue  #24451
  type
    A = object
      x: int
    B[T] = object
      b: T
    AConcept = concept
      proc implementation(s: var Self, p1: B[int])

  proc implementation(r: var A, p1: B[int])=
    echo typeof(p1)

  proc accept(r: var AConcept)=
    r.implementation(B[int]())

  var a = A()
  a.accept()

block: # typeclass
  type
    A[T] = object
      x: int
    AConcept = concept
      proc implementation(s: Self)

  proc implementation(r: A) =
    echo typeof(r)

  proc accept(r: AConcept) =
    r.implementation()

  var a = A[string]()
  a.accept()

block:
  type
    SomethingLike[T] = concept
      proc len(s: Self): int
      proc `[]`(s: Self; index: int): T

    A[T] = object
      x: T

  proc initA(x: SomethingLike): auto =
    A[type x](x: x)

  var a: array[1, int]
  var s: seq[int]
  echo typeof(initA(a))
  echo typeof(initA(s))

block:
  proc iGetShadowed(s: int)=
    discard
  proc spring(x: ShadowConcept)=
    discard
  let a = DummyFitsObj()
  spring(a)

block:
  type
    Buffer = concept
      proc put(s: Self)
    ArrayBuffer[T: static int] = object
  proc put(x: ArrayBuffer)=discard
  proc p(a: Buffer)=discard
  var buffer = ArrayBuffer[5]()
  p(buffer)

block: # composite typeclass matching
  type
    A[T] = object
    Buffer = concept
      proc put(s: Self, i: A)
    BufferImpl = object
    WritableImpl = object

  proc launch(a: var Buffer)=discard
  proc put(x: BufferImpl, i: A)=discard

  var a = BufferImpl()
  launch(a)

block: # simple recursion
  type
    Buffer = concept
      proc put(s: var Self, i: auto)
      proc second(s: Self)
    Writable = concept
      proc put(w: var Buffer, s: Self)
    BufferImpl[T: static int] = object
    WritableImpl = object

  proc launch(a: var Buffer, b: Writable)= discard
  proc put[T](x: var BufferImpl, i: T)= discard
  proc second(x: BufferImpl)= discard
  proc put(x: var Buffer, y: WritableImpl)= discard

  var a = BufferImpl[5]()
  launch(a, WritableImpl())

block: # more complex recursion
  type
    Buffer = concept
      proc put(s: var Self, i: auto)
      proc second(s: Self)
    Writable = concept
      proc put(w: var Buffer, s: Self)
    BufferImpl[T: static int] = object
    WritableImpl = object

  proc launch(a: var Buffer, b: Writable)= discard
  proc put[T](x: var Buffer, i: T)= discard
  proc put(x: var BufferImpl, i: object)= discard
  proc second(x: BufferImpl)= discard
  proc put(x: var Buffer, y: WritableImpl)= discard

  var a = BufferImpl[5]()
  launch(a, WritableImpl())

block: # co-dependent concepts
  type
    Writable = concept
      proc w(b: var Buffer; s: Self): int
    Buffer = concept
      proc w(s: var Self; data: Writable): int
    SizedWritable = concept
      proc size(x: Self): int
      proc w(b: var Buffer, x: Self): int
    BufferImpl = object
    
  proc w(x: var BufferImpl, d: int): int = return 100
  proc size(d: int): int = sizeof(int)

  proc p(b: var Buffer, data: SizedWritable): int =
    b.w(data)

  var b = BufferImpl()
  echo p(b, 5)

block: # indirect concept matching
  type
    Sizeable = concept
      proc size(s: Self): int
    Buffer = concept
      proc w(s: Self, data: Sizeable)
    Serializable = concept
      proc something(s: Self)
      proc w(b: Buffer, s: Self)
    BufferImpl = object
    ArrayImpl = object

  proc something(s: ArrayImpl)= discard
  proc size(s: ArrayImpl): int= discard

  proc w(x: BufferImpl, d: Sizeable)= discard

  proc spring(s: Buffer, data: Serializable)=discard

  spring(BufferImpl(), ArrayImpl())

block: # instantiate even when generic params are the same
  type
    ArrayLike[T] = concept
      proc len(x: Self): int
      proc `[]`(b: Self, i: int): T
  proc p[T](x: ArrayLike[T])=
    for k in x:
      echo k
  # For this test to work the second call's instantiation has to be incompatible with the first on the back end
  p(['a','b','c'])
  p("abc")

block: # reject improper generic variables in candidates
  type
    ArrayLike[T] = concept
      proc len(x: Self): int
      proc g(b: Self, i: int): T
    FreakString = concept
      proc len(x: Self): int
      proc characterSize(s: Self): int 
    A = object

  proc g[T, H](s: T, i: H): H = default(T)
  proc len(s: A): int = discard
  proc characterSize(s: A): int = discard
  
  proc p(symbol: ArrayLike[char]): int = assert false
  proc p(symbol: FreakString): int=discard
  
  discard p(A())

block: # typerel disambiguation by concept subset
  type
    ArrayLike[T] = concept
      proc len(x: Self): int
      proc characterSize(s: Self): int
    FreakString = concept
      proc len(x: Self): int
      proc characterSize(s: Self): int
      proc tieBreaker(s: Self, j: int): float
    A = object

  proc len(s: A): int = discard
  proc characterSize(s: A): int = discard
  proc tieBreaker(s: A, h: int):float = 0.0
  
  proc p(symbol: ArrayLike[char]): int = assert false
  proc p(symbol: FreakString): int=discard
  
  discard p(A())

block:  # tie break via sumGeneric
  type
    C1 = concept
      proc p1(x: Self, b: int)
      proc p2(x: Self, b: float)
      proc p3(x: Self, b: string)
    C2 = concept
      proc b1(x: Self, b: int)
      proc b2(x: Self, b: float)
    A = object
  
  proc p1(x: A, b: int)=discard
  proc p2(x: A, b: float)=discard
  proc p3(x: A, b: string)=discard
  
  proc b1(x: A, b: int)=discard
  proc b2(x: A, b: float)=discard
  
  proc p(symbol: C1): int = discard
  proc p(symbol: C2): int = assert false
  
  discard p(A())

block: # not type
  type
    C1 = concept
      proc p(s: Self, a: int)
    C1Impl = object
    
  proc p(x: C1Impl, a: not float)= discard
  proc spring(x: C1)= discard

  spring(C1Impl())

block: # not type parameterized
  type
    C1[T: not int] = concept
      proc p(s: Self, a: T)
    C1Impl = object
    
  proc p(x: C1Impl, a: float)= discard
  proc spring(x: C1)= discard

  spring(C1Impl())

block: # typedesc
  type
    C1 = concept
      proc p(s: Self, a: typedesc[SomeInteger])
    C1Impl = object
    
  proc p(x: C1Impl, a: typedesc)= discard
  proc spring(x: C1)= discard

  spring(C1Impl())


block: # or
  type
    C1 = concept
      proc p(s: Self, a: int | float)
    C1Impl = object
    
  proc p(x: C1Impl, a: int | float | string)= discard
  proc spring(x: C1)= discard

  spring(C1Impl())

block: # or mixed generic param
  type
    C1 = concept
      proc p(s: Self, a: int | float)
    C1Impl = object
    
  proc p[T: string | float](x: C1Impl, a: int | T) = discard
  proc spring(x: C1)= discard

  spring(C1Impl())

block: # or parameterized
  type
    C1[T: int | float | string] = concept
      proc p(s: Self, a: T)
    C1Impl = object
    
  proc p(x: C1Impl, a: int | float)= discard
  proc spring(x: C1)= discard

  spring(C1Impl())

block: # unconstrained param
  type
    A = object
    C1[T] = concept
      proc p(s: Self, a: T)
    C1Impl = object
    
  proc p(x: C1Impl, a: A)= discard
  proc spring(x: C1)= discard

  spring(C1Impl())

block: # unconstrained param sanity check
  type
    A = object
    C1[T: auto] = concept
      proc p(s: Self, a: T)
    C1Impl = object
    
  proc p(x: C1Impl, a: A)= discard
  proc spring(x: C1)= discard

  spring(C1Impl())

block: # exact nested concept binding
  #[
    prove ArrayImpl is serializable (spring)
      prove Buffer is Buffer (w)
      prove ArrayImpl is ArrayLike (w)
        prove ArrayImpl is ArrayImpl (len)
  ]#
  type
    Sizeable = concept
      proc size(s: Self): int
    Buffer = concept
      proc w(s: Self, data: Sizeable)
    Serializable = concept
      proc w(b: Buffer, s: Self)
    ArrayLike = concept
      proc len(s: Self): int
    ArrayImpl = object

  proc len(s: ArrayImpl): int = discard
  proc w(x: Buffer, d: ArrayLike)=discard

  proc spring(data: Serializable)=discard
  spring(ArrayImpl())

block:
  type
    StaticallySized = concept
      proc staticSize(x: typedesc[Self]): int
      proc dynamicSize(x: Self): int
    DynamicallySized = concept
      proc dynamicSize(x: Self): int

  proc dynamicSize(a: SomeInteger): int = 5
  proc read[T: DynamicallySized](a: var T): int = 1
  proc read[T: SomeInteger](a: var T): int = 2

  var a: uint16
  assert read(a) == 2

block:
  type
    A[X, Y] = object
      x: X
      y: Y
    C1 = concept
      proc p(z: var Self)
    C2 = concept
      proc g(x: var Self, y: int)
    C3 = C1 and C2
    C4 = concept
      proc h(x: Self): C3

  proc p[X, Y](z: var A[int, float]) = discard
  proc g[X, Y](z: var A[X, Y], y: int) = discard
  proc h[X, Y](z: var A[X, Y]): A[X, Y] = discard

  proc spring(x: C4) = discard
  var d = A[int, float]()
  d.spring()

block:
  type
    A[X, Y] = object
      x: X
      y: Y
    B = object
    C1 = concept
      proc p(z: var Self, d: A[int, float])

  proc p[X: int; Y: float](x: var B, y: A[X, Y]) = discard
  proc spring(x: var C1) = discard
  var d = B()
  d.spring()

block:
  type
    A = object
    C1 = concept
      proc p(s: Self; x: auto)
    C2[T: int] = concept
      proc p(s: Self; x: T)
    Impl = object

  proc p(n: Impl; i: int) = discard

  proc spring(x: C1): int = 1
  proc spring(x: C2): int = 2

  assert spring(Impl()) == 2


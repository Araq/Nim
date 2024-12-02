discard """
action: "run"
output: '''
B[system.int]
A[system.string]
A[array[0..0, int]]
A[seq[int]]
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

block: # not type each
  type
    C1 = concept
      proc p(s: Self, a: each typedesc[not int])
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
    
  proc p[T: string | float](x: C1Impl, a: int | T)= discard
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

block: # or each
  type
    C1 = concept
      proc p(s: Self, a: each typedesc[int | float | string])
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

block: # parameterization via `each`
  type
    A = object
    C1 = concept
      proc p(s: Self, a: each auto)
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

block: # co-dependent implicit
  #[
    prove ArrayImpl is Serializable (spring)
      fail to find a binding for Serializable.w
      Serializable and Buffer are co-dependent, assume Buffer.w exists
        prove ArrayImpl is Sizeable (Buffer.w)
          prove ArrayImpl is ArrayImpl (len)
  ]#
  type
    Sizeable = concept
      proc size(s: Self): int
    Buffer = concept
      proc w(s: Self, data: Sizeable)
    Serializable = concept
      proc w(b: Buffer, s: Self)
    ArrayImpl = object

  proc size(x: ArrayImpl): int= discard

  proc spring(data: Serializable)= discard
  spring(ArrayImpl())

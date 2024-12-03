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
  proc put(x: var BufferImpl, i: object)= discard
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
  proc put(x: var Buffer, i: object)= discard
  proc put(x: var BufferImpl, i: object)= discard
  proc second(x: BufferImpl)= discard
  proc put(x: var Buffer, y: WritableImpl)= discard

  var a = BufferImpl[5]()
  launch(a, WritableImpl())

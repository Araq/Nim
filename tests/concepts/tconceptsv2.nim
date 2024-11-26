discard """
action: "run"
output: '''
B[system.int]
A[system.string]
A[array[0..0, int]]
A[seq[int]]
'''
"""
import conceptsv2Helper

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

discard """
  output: '''string
A[seq[int]]
A[array[0..0, string]]
'''
"""

type
  SomethingLike[T] = concept x
    x.len is int
    x[int] is T
  
  A[T] = object
    x: T

proc p*[T](x: SomethingLike[T]) =
  echo typeof(x)

proc initA*[T; S: SomethingLike[T]](x: S): A[S] =
  A[S](x: x)

proc initA2[T](x: SomethingLike[T]): auto =
  A[typeof x](x:x)

p("testing")
echo typeof(initA(newSeq[int]()))
var ar: array[1, string]
echo typeof(initA2(ar))

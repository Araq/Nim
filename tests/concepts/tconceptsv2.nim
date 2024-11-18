discard """
action: "run"
output: '''
A[array[0..0, int]]
A[seq[int]]
'''
"""
type
  SomethingLike[T] = concept
    proc len(s: Self): int
    proc `[]`(s: Self; index: int): T

  A[T] = object
    x: T

proc initA*(x: SomethingLike): auto =
  A[type x](x: x)

var a: array[1, int]
var s: seq[int]
echo typeof(initA(a))
echo typeof(initA(s))

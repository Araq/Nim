discard """
  errormsg: "ambiguous call"
"""

type
  A[T] = object
  C = object
    x:int
proc p[T: A[ptr]](x:ptr[T]):bool = false
proc p(x: ptr[A[ptr]]):bool = true
var a: A[ptr[C]]
doAssert p(a.addr) == true

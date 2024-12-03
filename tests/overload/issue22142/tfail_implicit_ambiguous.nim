discard """
  errormsg: "ambiguous call"
"""
type
  A[T] = object
  C = object

proc test[T: A](param: T): bool = false
proc test(param: A): bool = true
doAssert test(A[C]()) == true  # previously would pass

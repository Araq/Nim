discard """
action: "reject"
"""
type
  A[T] = object
  C1 = concept
    proc p(s: Self, a: A)
  C1Impl = object
  
proc p(x: C1Impl, a: A[int])= discard
proc spring(x: C1)= discard

spring(C1Impl())

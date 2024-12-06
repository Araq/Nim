discard """
  action: "reject"
"""
type
  A = object
  C1 = concept
    proc p(s: Self, a: auto)
  C1Impl = object
  
proc p(x: C1Impl, a: A)= discard
proc spring(x: C1)= discard

spring(C1Impl())

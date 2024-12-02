discard """
  outputsub: "type mismatch"
  exitcode: "1"
"""
type
  C1 = concept
    proc p(s: Self, a: int | float | string)
  C1Impl = object
  
proc p(x: C1Impl, a: int | float)= discard
proc spring(x: C1)= discard

spring(C1Impl())
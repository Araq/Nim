discard """
  outputsub: "type mismatch"
  exitcode: "1"
"""
type
  C1 = concept
    proc p(s: Self, a: typedesc)
  C1Impl = object
  
proc p(x: C1Impl, a: typedesc[SomeInteger])= discard
proc spring(x: C1)= discard

spring(C1Impl())
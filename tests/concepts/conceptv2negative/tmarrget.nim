discard """
action: "reject"
"""

# stop mArrGet magic from giving everything `[]`
type
  C[T] = concept
    proc `[]`(b: Self, i: int): T
  A = object
  
proc p(a: C): int = assert false
discard p(A())

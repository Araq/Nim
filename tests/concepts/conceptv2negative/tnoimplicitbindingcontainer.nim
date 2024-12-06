discard """
action: "reject"
"""
type
  Sizeable = concept
    proc size(s: Self): int
  Buffer = concept
    proc w(s: Self, data: Sizeable)
  Serializable[T: Buffer] = concept
    proc w(b: T, s: Self)
  ArrayLike = concept
    proc size(s: Self): int
  ArrayImpl = object

proc size(x: ArrayImpl): int= discard

proc spring(data: Serializable)= discard
spring(ArrayImpl())

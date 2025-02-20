discard """
action: "reject"
"""

#[
  ArrayImpl is not Sizeable
]#

type
  Sizeable = concept
    proc size(s: Self): int
  Buffer = concept
    proc w(s: Self, data: Sizeable)
  Serializable = concept
    proc something(s: Self)
    proc w(b: Buffer, s: Self)
  BufferImpl = object
  ArrayImpl = object

proc something(s: ArrayImpl)= discard
#proc size(s: ArrayImpl): int= discard
proc w(x: BufferImpl, d: Sizeable)= discard

proc spring(s: Buffer, data: Serializable)= discard

spring(BufferImpl(), ArrayImpl())

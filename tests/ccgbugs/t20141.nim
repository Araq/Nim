discard """
  joinable: false
"""

# bug #20141
type
  A = object
  B = object
  U = proc()

proc m(h: var B) = discard

template n[T, U](x: U): T =
  static: doAssert true
  cast[ptr T](addr x)[]

proc k() =
  var res: A
  m(n[B, A](res))

proc w(mounter: U) = discard

proc mount(proto: U) = discard
proc v() = mount k

# This is required for failure
w(v)

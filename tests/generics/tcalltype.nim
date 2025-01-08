discard """
  joinable: false # breaks everything because of #23977
"""

# issue #23406

template helper(_: untyped): untyped =
  int

type # Each of them should always be `int`.
  GenA[T] = helper int
  GenB[T] = helper(int)
  GenC[T] = helper helper(int)

block:
  template helper(_: untyped): untyped =
    float

  type
    A = GenA[int]
    B = GenB[int]
    C = GenC[int]

  assert A is int # OK.
  assert B is int # Fails; it is `float`!
  assert C is int # OK.

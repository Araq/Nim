discard """
  errormsg: "undeclared identifier: 'thing'"
"""

template inner(i: int) {.dirty.} =
  let thing = 1

template outer() =
  proc p[T](x: T) =
    echo thing

template outerouter() =
  outer()
  inner(5)

outerouter()
p(0)

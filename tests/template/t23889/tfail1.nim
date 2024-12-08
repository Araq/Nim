discard """
  errormsg: "redefinition of 'thing'"
"""

template inner(i: int) {.dirty.} =
  let thing = 1

template outer() =
  proc p[T](x: T) =
    inner(5)
    var thing = 5
    echo thing

outer()
p(0)

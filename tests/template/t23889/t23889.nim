template inner(i: int) {.dirty.} =
  let thing = 1

template outer() =
  proc p[T](x: T): int =
    inner(5)
    return thing

outer()
assert p(0) == 1
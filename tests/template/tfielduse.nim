# issue #24657

proc g() {.error.} = discard

type T = object
  g: int

template B(): untyped = typeof(T.g)
type _ = B()

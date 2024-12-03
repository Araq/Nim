# issue #24241

{.warningAsError[Deprecated]: on.}

type X = distinct int

converter toInt(x: X): int{.deprecated.} = int(x)

template `==`(a, b: X): bool = false # this gets called so we didn't convert

doAssert not (X(1) == X(2))
doAssert not compiles(X(1) + X(2))
doAssert not (compiles do:
  let x: int = X(1))

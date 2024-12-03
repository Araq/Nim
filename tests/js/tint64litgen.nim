discard """
  matrix: "--jsbigint64:on; --jsbigint64:off"
"""

block: # issue #24233
  proc foo[T: SomeInteger](a, b: T) =
    let x = a div b

  const bar = 123

  let x: int64 = 456
  foo(x, bar)

block: # issue #24233, modified
  proc f(a, b: int64) =
    let x = a div b

  proc foo[T: SomeInteger](a, b: T) =
    f(a, b)

  const bar = 123

  let x: int64 = 456
  foo(x, bar)

block:
  proc foo[I: Ordinal](x: I) = discard
  foo(123)
  let x = [0, 1, 2]
  discard x[0]

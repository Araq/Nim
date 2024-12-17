discard """
  matrix: "--skipParentCfg --filenames:legacyRelProj"
"""

const value = "captured"
template fooOld(x: int, body: untyped): untyped =
  let value {.inject.} = "injected"
  body
template foo(x: int, body: untyped): untyped =
  let value {.inject.} = "injected"
  {.push experimental: "genericsOpenSym".}
  body
  {.pop.}

proc old[T](): string =
  fooOld(123):
    return value
doAssert old[int]() == "captured"

template oldTempl(): string =
  block:
    var res: string
    fooOld(123):
      res = value
    res
doAssert oldTempl() == "captured"

proc bar[T](): string =
  foo(123):
    return value
doAssert bar[int]() == "injected"

template barTempl(): string =
  block:
    var res: string
    foo(123):
      res = value
    res
doAssert barTempl() == "injected"

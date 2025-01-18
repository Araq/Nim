discard """
  joinable: false
"""

#[
tests: hintAsError, warningAsError
]#

template fn1 =
  {.hintAsError[ConvFromXtoItselfNotNeeded]:on.}
  proc fn(a: string) = discard a.string
  {.hintAsError[ConvFromXtoItselfNotNeeded]:off.}

template fn2 =
  {.hintAsError[ConvFromXtoItselfNotNeeded]:on.}
  proc fn(a: string) = discard a
  {.hintAsError[ConvFromXtoItselfNotNeeded]:off.}

template gn1 =
  {.warningAsError[ProveInit]:on.}
  proc fn(): var int = discard
  discard fn()
  {.warningAsError[ProveInit]:off.}

template gn2 =
  {.warningAsError[ProveInit]:on.}
  proc fn(): int = discard
  discard fn()
  {.warningAsError[ProveInit]:off.}

doAssert not compiles(fn1())
doAssert compiles(fn2())

doAssert not compiles(gn1())
doAssert compiles(gn2())

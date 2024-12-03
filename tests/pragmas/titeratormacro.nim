# issue #16413

import std/macros

macro identity(x: untyped) =
  result = x.copy()
  result[6] = quote do:
    yield 1
  discard result.toStrLit

iterator demo(): int {.identity.}
iterator demo2(): int {.identity.} = discard # but this works as expected

var s: seq[int] = @[]
for e in demo():
  s.add(e)
doAssert s == @[1]

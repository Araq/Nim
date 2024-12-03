discard """
  targets: "c js"
  output: "@[\"42\"]"
"""

proc chk_fail(): seq[string] =
  iterator x(): int {.closure.} = yield 42
  proc f(cl: iterator(): int {.closure.}): seq[string] =
    result = @[]
    for i in cl(): result.add($i)
  result = f(x)

echo(chk_fail())

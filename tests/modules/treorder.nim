discard """
  matrix: "-d:testdef"
  output: '''works 34
34
defined
3'''
"""

{.experimental: "codeReordering".}

{.push callconv: stdcall.}

proc bar(x: T)

proc foo() =
  bar(34)
  whendep()

proc foo(dummy: int) = echo dummy

proc bar(x: T) =
  echo "works ", x
  foo(x)

when defined(testdef):
  proc whendep() = echo "defined"
else:
  proc whendep() = echo "undefined"

foo()

type
  T = int


when not declared(goo):
  proc goo(my, omy) = echo my

when not declared(goo):
  proc goo(my, omy) = echo omy

using
  my, omy: int

goo(3, 4)

{.pop.}

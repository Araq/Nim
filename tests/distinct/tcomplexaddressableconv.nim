# issue #22523

from std/typetraits import distinctBase

type
  V[p: static int] = distinct int
  D[p: static int] = distinct int
  T = V[1]

proc f(y: var T) = discard

var a: D[0]

static:
  doAssert distinctBase(T) is distinctBase(D[0])
  doAssert distinctBase(T) is int
  doAssert distinctBase(D[0]) is int
  doAssert T(a) is T

f(cast[ptr T](addr a)[])
f(T(a))

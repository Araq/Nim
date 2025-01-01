type P = object

template d(Name: untyped) {.dirty.} =
  type Name* = object

import menumdirty2

d(Json)

type K[Flavor = P] = object
  lex: V

template F*(T: type Json, F: distinct type = P): type = K[F]

proc init*(T: type K): T = discard

proc s*[T](r: var K, value: var T) =
  x(r.lex)

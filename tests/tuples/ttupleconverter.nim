# issue #24609

import std/options

type
  Config* = object
    bits*: tuple[r, g, b, a: Option[int32]]

# works on 2.0.8
#
# results in error on 2.2.0
#   type mismatch: got 'int literal(8)' for '8' but expected 'Option[system.int32]'
#
converter toInt32Tuple*(t: tuple[r,g,b,a: int]): tuple[r,g,b,a: Option[int32]] =
  (some(t.r.int32), some(t.g.int32), some(t.b.int32), some(t.a.int32))

var cfg: Config
cfg.bits = (r: 8, g: 8, b: 8, a: 16)

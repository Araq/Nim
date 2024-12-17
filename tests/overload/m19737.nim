type
  UInt128* = object
    lo, hi: uint64

func `<`*(x, y: UInt128): bool =
  (x.hi < y.hi) or ((x.hi == y.hi) and (x.lo < y.lo))

when not defined(works):
  func `>`*(x, y: UInt128): bool =
    (x.hi > y.hi) or ((x.hi == y.hi) and (x.lo > y.lo))

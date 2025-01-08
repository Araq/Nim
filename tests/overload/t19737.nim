# issue #19737

import ./m19737

var m: seq[uint64]

proc foo(x: bool) = discard

proc test[T: uint64|uint32](s: var seq[T]) =
  var tmp = newSeq[T](1)
  s = newSeq[T](1)

  foo s[0] > tmp[0]

test(m)

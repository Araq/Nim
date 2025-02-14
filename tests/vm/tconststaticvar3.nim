# issue #24633

import std/sequtils

proc f(a: static openArray[int]) =
  const s1 = a.mapIt(it)
  const s2 = a.toSeq()

f([1,2,3])

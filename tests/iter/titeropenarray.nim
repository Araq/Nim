block: # issue #13417
  var s: seq[int] = @[]
  proc p1(): seq[int] =
    s.add(3)
    @[1,2]

  iterator ip1(v: openArray[int]): auto =
    for x in v:
      yield x

  for x in ip1(p1()):
    s.add(x)

  doAssert s == @[3, 1, 2]

import std / sequtils

block: # issue #19703
  iterator combinations[T](s: seq[T], r: Positive): seq[T] =
    yield @[s[0], s[1]]

  iterator pairwise[T](s: openArray[T]): seq[T] =
    yield @[s[0], s[0]]

  proc checkSpecialSubset5(s: seq[int]): bool =
    toSeq(
      toSeq(
        s.combinations(2)
      ).map(proc(a: auto): int = a[0]).pairwise()
    ).any(proc(a: auto): bool = a == @[s[0], s[0]])

  doAssert checkSpecialSubset5 @[1, 2]

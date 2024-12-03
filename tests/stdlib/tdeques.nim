discard """
  matrix: "--mm:refc; --mm:orc"
  targets: "c cpp js"
"""

import std/deques
from std/sequtils import toSeq
import std/assertions

block:
  proc index(self: Deque[int], idx: Natural): int =
    self[idx]

  proc main =
    var testDeque = initDeque[int]()
    testDeque.addFirst(1)
    doAssert testDeque.index(0) == 1

  main()

block:
  var d = initDeque[int]()
  d.addLast(1)
  doAssert $d == "[1]"
block:
  var d = initDeque[string]()
  d.addLast("1")
  doAssert $d == """["1"]"""
block:
  var d = initDeque[char]()
  d.addLast('1')
  doAssert $d == "['1']"

block:
  var deq = initDeque[int](1)
  deq.addLast(4)
  deq.addFirst(9)
  deq.addFirst(123)
  var first = deq.popFirst()
  deq.addLast(56)
  doAssert(deq.peekLast() == 56)
  deq.addLast(6)
  doAssert(deq.peekLast() == 6)
  var second = deq.popFirst()
  deq.addLast(789)
  doAssert(deq.peekLast() == 789)

  doAssert first == 123
  doAssert second == 9
  doAssert($deq == "[4, 56, 6, 789]")
  doAssert deq == [4, 56, 6, 789].toDeque

  doAssert deq[0] == deq.peekFirst and deq.peekFirst == 4
  #doAssert deq[^1] == deq.peekLast and deq.peekLast == 789
  deq[0] = 42
  deq[deq.len - 1] = 7

  doAssert 6 in deq and 789 notin deq
  doAssert deq.find(6) >= 0
  doAssert deq.find(789) < 0

  block:
    var d = initDeque[int](1)
    d.addLast 7
    d.addLast 8
    d.addLast 10
    d.addFirst 5
    d.addFirst 2
    d.addFirst 1
    d.addLast 20
    d.shrink(fromLast = 2)
    doAssert($d == "[1, 2, 5, 7, 8]")
    d.shrink(2, 1)
    doAssert($d == "[5, 7]")
    d.shrink(2, 2)
    doAssert d.len == 0

  for i in -2 .. 10:
    if i in deq:
      doAssert deq.contains(i) and deq.find(i) >= 0
    else:
      doAssert(not deq.contains(i) and deq.find(i) < 0)

  when compileOption("boundChecks"):
    try:
      echo deq[99]
      doAssert false
    except IndexDefect:
      discard

    try:
      doAssert deq.len == 4
      for i in 0 ..< 5: deq.popFirst()
      doAssert false
    except IndexDefect:
      discard

  # grabs some types of resize error.
  deq = initDeque[int]()
  for i in 1 .. 4: deq.addLast i
  deq.popFirst()
  deq.popLast()
  for i in 5 .. 8: deq.addFirst i
  doAssert $deq == "[8, 7, 6, 5, 2, 3]"

  # Similar to proc from the documentation example
  proc foo(a, b: Positive) = # assume random positive values for `a` and `b`.
    var deq = initDeque[int]()
    doAssert deq.len == 0
    for i in 1 .. a: deq.addLast i

    if b < deq.len: # checking before indexed access.
      doAssert deq[b] == b + 1

    # The following two lines don't need any checking on access due to the logic
    # of the program, but that would not be the case if `a` could be 0.
    doAssert deq.peekFirst == 1
    doAssert deq.peekLast == a

    while deq.len > 0: # checking if the deque is empty
      doAssert deq.popFirst() > 0

  #foo(0,0)
  foo(8, 5)
  foo(10, 9)
  foo(1, 1)
  foo(2, 1)
  foo(1, 5)
  foo(3, 2)

import std/sets

block t13310:
  proc main() =
    var q = initDeque[HashSet[int16]](2)
    q.addFirst([1'i16].toHashSet)
    q.addFirst([2'i16].toHashSet)
    q.addFirst([3'i16].toHashSet)
    doAssert $q == "[{3}, {2}, {1}]"

  static:
    main()


proc main() =
  block:
    let a = [10, 20, 30].toDeque
    doAssert toSeq(a.pairs) == @[(0, 10), (1, 20), (2, 30)]

  block:
    let q = [7, 9].toDeque
    doAssert 7 in q
    doAssert q.contains(7)
    doAssert 8 notin q

  block:
    let a = [10, 20, 30, 40, 50].toDeque
    doAssert $a == "[10, 20, 30, 40, 50]"
    doAssert a.peekFirst == 10
    doAssert len(a) == 5

  block:
    let a = [10, 20, 30, 40, 50].toDeque
    doAssert $a == "[10, 20, 30, 40, 50]"
    doAssert a.peekLast == 50
    doAssert len(a) == 5

  block:
    var a = [10, 20, 30, 40, 50].toDeque
    doAssert $a == "[10, 20, 30, 40, 50]"
    doAssert a.popFirst == 10
    doAssert $a == "[20, 30, 40, 50]"

  block:
    var a = [10, 20, 30, 40, 50].toDeque
    doAssert $a == "[10, 20, 30, 40, 50]"
    doAssert a.popLast == 50
    doAssert $a == "[10, 20, 30, 40]"

  block:
    var a = [10, 20, 30, 40, 50].toDeque
    doAssert $a == "[10, 20, 30, 40, 50]"
    clear(a)
    doAssert len(a) == 0

  block: # bug #21278
    var a = [10, 20, 30, 40].toDeque

    a.shrink(fromFirst = 0, fromLast = 1)
    doAssert $a == "[10, 20, 30]"

  block:
    var a, b: Deque[int] = initDeque[int]()
    for i in 1 .. 256:
      a.addLast(i)
    for i in 1 .. 255:
      a.popLast
    b.addLast(1)
    doAssert a == b

  block:
    # Issue 23275
    # Test `==`.
    block:
      var a, b = initDeque[int]()
      doAssert a == b
      doAssert a.hash == b.hash
      a.addFirst(1)
      doAssert a != b
      doAssert a.hash != b.hash
      b.addLast(1)
      doAssert a == b
      doAssert a.hash == b.hash
      a.popFirst
      b.popLast
      doAssert a == b
      doAssert a.hash == b.hash
      a.addLast 2
      doAssert a != b
      doAssert a.hash != b.hash
      b.addFirst 2
      doAssert a == b
      doAssert a.hash == b.hash

    block:
      var a, b = initDeque[int]()
      for i in countdown(100, 1):
        a.addFirst(i)
      for i in 1..100:
        b.addLast(i)
      doAssert a == b
      for i in 1..99:
        a.popLast
      let a1 = [1].toDeque
      doAssert a == a1
      doAssert a.hash == a1.hash
      var c = initDeque[int]()
      c.addLast(1)
      doAssert a == c
      doAssert a.hash == c.hash

static: main()
main()

#
#
#              Nim's Runtime Library
#        (c) Copyright 2020 Nim Contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module adds functionality for the built-in `set` type.
##
## See also
## ========
## * `std/packedsets <packedsets.html>`_
## * `std/sets <sets.html>`_

import std/[typetraits, macros]

#[
  type SetElement* = char|byte|bool|int16|uint16|enum|uint8|int8
    ## The allowed types of a built-in set.
]#

template toSet*(iter: untyped): untyped =
  ## Returns a built-in set from the elements of the iterable `iter`.
  runnableExamples:
    assert "helloWorld".toSet == {'W', 'd', 'e', 'h', 'l', 'o', 'r'}
    assert toSet([10u16, 20, 30]) == {10u16, 20, 30}
    assert [30u8, 100, 10].toSet == {10u8, 30, 100}
    assert toSet(@[1321i16, 321, 90]) == {90i16, 321, 1321}
    assert toSet([false]) == {false}
    assert toSet(0u8..10) == {0u8..10}

  var result: set[elementType(iter)]
  for x in iter:
    incl(result, x)
  result

macro enumElementsAsSet(enm: typed): untyped = result = newNimNode(nnkCurly).add(enm.getType[1][1..^1])

# func fullSet*(T: typedesc): set[T] {.inline.} = # xxx would give: Error: ordinal type expected
func fullSet*[T](U: typedesc[T]): set[T] {.inline.} =
  ## Returns a set containing all elements in `U`.
  runnableExamples:
    assert bool.fullSet == {true, false}
    type A = range[1..3]
    assert A.fullSet == {1.A, 2, 3}
    assert int8.fullSet.len == 256
  when T is Ordinal:
    {T.low..T.high}
  else: # Hole filled enum
    enumElementsAsSet(T)

func complement*[T](s: set[T]): set[T] {.inline.} =
  ## Returns the set complement of `a`.
  runnableExamples:
    type Colors = enum
      red, green = 3, blue
    assert complement({red, blue}) == {green}
    assert complement({red, green, blue}).card == 0
    assert complement({range[0..10](0), 1, 2, 3}) == {range[0..10](4), 5, 6, 7, 8, 9, 10}
    assert complement({'0'..'9'}) == {0.char..255.char} - {'0'..'9'}
  fullSet(T) - s

func `[]=`*[T](t: var set[T], key: T, val: bool) {.inline.} =
  ## Syntax sugar for `if val: t.incl key else: t.excl key`
  runnableExamples:
    type A = enum
      a0, a1, a2, a3
    var s = {a0, a3}
    s[a0] = false
    s[a1] = false
    assert s == {a3}
    s[a2] = true
    s[a3] = true
    assert s == {a2, a3}
  if val: t.incl key else: t.excl key

when defined(nimHasXorSet):
  func symmetricDifference*[T](x, y: set[T]): set[T] {.magic: "XorSet".} =
    ## This operator computes the symmetric difference of two sets,
    ## equivalent to but more efficient than `x + y - x * y` or
    ## `(x - y) + (y - x)`.
    runnableExamples:
      assert symmetricDifference({1, 2, 3}, {2, 3, 4}) == {1, 4}
else:
  func symmetricDifference*[T](x, y: set[T]): set[T] {.inline.} =
    result = x + y - (x * y)

proc `-+-`*[T](x, y: set[T]): set[T] {.inline.} =
  ## Operator alias for `symmetricDifference`.
  runnableExamples:
    assert {1, 2, 3} -+- {2, 3, 4} == {1, 4}
  result = symmetricDifference(x, y)

proc toggle*[T](x: var set[T], y: set[T]) {.inline.} =
  ## Toggles the existence of each value of `y` in `x`.
  ## If any element in `y` is also in `x`, it is excluded from `x`;
  ## otherwise it is included.
  ## Equivalent to `x = symmetricDifference(x, y)`.
  runnableExamples:
    var x = {1, 2, 3}
    x.toggle({2, 3, 4})
    assert x == {1, 4}
  x = symmetricDifference(x, y)

discard """
  matrix: "--mm:refc; --mm:orc"
"""

import std/varints
import std/assertions

# xxx doesn't work with js: tvarints.nim(18, 14) `wrLen == rdLen`  [AssertionDefect]

block:
  var dest: array[50, byte]
  var got: uint64

  for test in [0xFFFF_FFFF_FFFFF_FFFFu64, 77u64, 0u64, 10_000_000u64, uint64(high(int64)),
              uint64(high(int32)), uint64(high(int32)), uint64(high(int64))]:
    let wrLen = writeVu64(dest, test)
    let rdLen = readVu64(dest, got)
    doAssert wrLen == rdLen
    doAssert got == test

  for test in 0u64..300u64:
    let wrLen = writeVu64(dest, test)
    let rdLen = readVu64(dest, got)
    doAssert wrLen == rdLen
    doAssert got == test

  # check this also works for floats:
  for test in [0.0, 0.1, 2.0, +Inf, NegInf]:
    let t = cast[uint64](test)
    let wrLenB = writeVu64(dest, t)
    let rdLenB = readVu64(dest, got)
    doAssert wrLenB == rdLenB
    doAssert cast[float64](got) == test

block:
  var hugeIntArray: array[9, byte]
  var readedInt: uint64

  template chk(a) =
    let b = cast[uint64](a)
    doAssert writeVu64(hugeIntArray, b) == readVu64(hugeIntArray, readedInt)
    doAssert readedInt == b

  chk 0
  chk uint64.high
  chk int64.high
  chk int32.high
  chk int16.high
  chk int16.high
  chk int8.high
  chk 0.0
  chk -0.0
  chk 0.1
  chk Inf
  chk NegInf
  chk NaN
  chk 3.1415926535897932384626433

block:
  template chk(a) =
    let b = cast[uint64](a)
    doAssert encodeZigzag(decodeZigzag(b)) == b
  chk 0
  chk uint32.high
  chk int32.high
  chk int16.high
  chk int8.high
  chk 0.0
  chk 0.1
  chk 0.9555555555555555555555501
  chk Inf
  chk 3.1415926535897932384626433
  chk 2.71828182845904523536028747

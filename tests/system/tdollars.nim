discard """
  matrix: "--mm:refc; --mm:orc; --backend:cpp; --backend:js --jsbigint64:off -d:nimStringHash2; --backend:js --jsbigint64:on"
"""

#[
if https://github.com/nim-lang/Nim/pull/14043 is merged (or at least its
tests/system/tostring.nim diff subset), merge
tests/system/tostring.nim into this file, named after dollars.nim

The goal is to increase test coverage across backends while minimizing test code
duplication (which always results in weaker test coverage in practice).
]#

import std/unittest
import std/private/jsutils
template test[T](a: T, expected: string) =
  check $a == expected
  var b = a
  check $b == expected
  static:
    doAssert $a == expected

template testType(T: typedesc) =
  when T is bool:
    test true, "true"
    test false, "false"
  elif T is char:
    test char, "\0"
    test char.high, static($T.high)
  else:
    test T.default, "0"
    test 1.T, "1"
    test T.low, static($T.low)
    test T.high, static($T.high)

block: # `$`(SomeInteger)
  # direct tests
  check $0'u8 == "0"
  check $255'u8 == "255"
  check $(-127'i8) == "-127"

  # known limitation: Error: number out of range: '128'i8',
  # see https://github.com/timotheecour/Nim/issues/125
  # check $(-128'i8) == "-128"

  check $int8.low == "-128"
  check $int8(-128) == "-128"
  check $cast[int8](-128) == "-128"

  var a = 12345'u16
  check $a == "12345"
  check $12345678'u64 == "12345678"
  check $12345678'i64 == "12345678"
  check $(-12345678'i64) == "-12345678"

  # systematic tests
  testType uint8
  testType uint16
  testType uint32
  testType uint

  testType int8
  testType int16
  testType int32

  testType int
  testType bool

  when hasWorkingInt64:
    testType uint64
    testType int64
    testType BiggestInt

block: # #14350, #16674, #16686 for JS
  var cstr: cstring
  doAssert cstr == cstring(nil)
  doAssert cstr == nil
  doAssert cstr.isNil
  doAssert cstr != cstring("")
  doAssert cstr.len == 0

  when defined(js):
    cstr.add(cstring("abc"))
    doAssert cstr == cstring("abc")

    var nil1, nil2: cstring = nil

    nil1.add(nil2)
    doAssert nil1 == cstring(nil)
    doAssert nil2 == cstring(nil)

    nil1.add(cstring(""))
    doAssert nil1 == cstring("")
    doAssert nil2 == cstring(nil)

    nil1.add(nil2)
    doAssert nil1 == cstring("")
    doAssert nil2 == cstring(nil)

    nil2.add(nil1)
    doAssert nil1 == cstring("")
    doAssert nil2 == cstring("")

block:
  when defined(js): # bug #18591
    let a1 = -1'i8
    let a2 = uint8(a1)
    # if `uint8(a1)` changes meaning to `cast[uint8](a1)` in future, update this test;
    # until then, this is the correct semantics.
    let a3 = $a2
    doAssert a2 == 255'u8
    doAssert a3 == "255"
    proc intToStr(a: uint8): cstring {.importjs: "(# + \"\")".}
    doAssert $intToStr(a2) == "255"
  else:
    block:
      let x = -1'i8
      let y = uint32(x)
      doAssert $y == "4294967295"
    block:
      let x = -1'i16
      let y = uint32(x)
      doAssert $y == "4294967295"
    block:
      let x = -1'i32
      let y = uint32(x)
      doAssert $y == "4294967295"
    block:
      proc foo1(arg: int): string =
        let x = uint32(arg)
        $x
      doAssert $foo1(-1) == "4294967295"

  block:
    let x = 4294967295'u32
    doAssert $x == "4294967295"
  block:
    doAssert $(4294967295'u32) == "4294967295"

proc main()=
  block:
    let a = -0.0
    doAssert $a == "-0.0"
    doAssert $(-0.0) == "-0.0"

  block:
    let a = 0.0
    doAssert $a == "0.0"
    doAssert $(0.0) == "0.0"

  block:
    let b = -0
    doAssert $b == "0"
    doAssert $(-0) == "0"

  block:
    let b = 0
    doAssert $b == "0"
    doAssert $(0) == "0"

  doAssert $uint32.high == "4294967295"

  block: # addInt
    var res = newStringOfCap(24)
    template test2(a, b) =
      res.setLen(0)
      res.addInt a
      doAssert res == b

    for i in 0 .. 9:
      res.addInt int64(i)
    doAssert res == "0123456789"

    res.setLen(0)
    for i in -9 .. 0:
      res.addInt int64(i)
    doAssert res == "-9-8-7-6-5-4-3-2-10"

    when hasWorkingInt64:
      test2 high(int64), "9223372036854775807"
      test2 low(int64), "-9223372036854775808"
    test2 high(int32), "2147483647"
    test2 low(int32), "-2147483648"
    test2 high(int16), "32767"
    test2 low(int16), "-32768"
    test2 high(int8), "127"
    test2 low(int8), "-128"

  block:
    const
      a: array[3, char] = ['N', 'i', 'm']
      aStr = $(a)

    doAssert aStr == """['N', 'i', 'm']"""

static: main()
main()

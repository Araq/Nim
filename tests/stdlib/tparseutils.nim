discard """
  matrix: "--mm:refc; --mm:orc"
  targets: "c cpp"
"""

import std/[parseutils, sequtils, sugar, formatfloat]
import std/assertions

proc test() =
  let input = "$test{}  $this is ${an{  example}}  "
  let expected = @[(ikVar, "test"), (ikStr, "{}  "), (ikVar, "this"),
                    (ikStr, " is "), (ikExpr, "an{  example}"), (ikStr, "  ")]
  doAssert toSeq(interpolatedFragments(input)) == expected

  var value = 0
  discard parseHex("0x38", value)
  doAssert value == 56

  value = -1
  doAssert(parseSaturatedNatural("848", value) == 3)
  doAssert value == 848

  value = -1
  discard parseSaturatedNatural("84899999999999999999324234243143142342135435342532453", value)
  doAssert value == high(int)

  value = -1
  discard parseSaturatedNatural("9223372036854775808", value)
  doAssert value == high(int)

  value = -1
  discard parseSaturatedNatural("9223372036854775807", value)
  doAssert value == high(int)

  value = -1
  discard parseSaturatedNatural("18446744073709551616", value)
  doAssert value == high(int)

  value = -1
  discard parseSaturatedNatural("18446744073709551615", value)
  doAssert value == high(int)

  value = -1
  doAssert(parseSaturatedNatural("1_000_000", value) == 9)
  doAssert value == 1_000_000

  var i64Value: int64 = 0'i64
  discard parseBiggestInt("9223372036854775807", i64Value)
  doAssert i64Value == 9223372036854775807

  block:
    var f: float = 0.0
    let res = collect:
      for x in ["9.123456789012345+","11.123456789012345+","9.123456789012345-","8.123456789012345+","9.12345678901234-","9.123456789012345"]:
        (parseFloat(x, f, 0), $f)
    doAssert res == @[(17, "9.123456789012344"), (18, "11.123456789012344"),
                      (17, "9.123456789012344"), (17, "8.123456789012344"),
                      (16, "9.12345678901234"), (17, "9.123456789012344")]

test()
static: test()

block:  # With this included, static: test() crashes the compiler (from a
        # VM problem with parseSize calling parseFloat).
  var sz: int64
  template checkParseSize(s, expectLen, expectVal) =
    if (let got = parseSize(s, sz); got != expectLen):
      raise newException(IOError, "got len " & $got & " != " & $expectLen)
    if sz != expectVal:
      raise newException(IOError, "got sz " & $sz & " != " & $expectVal)
  #              STRING    LEN SZ
  # Good, complete parses
  checkParseSize "1  b"   , 4, 1
  checkParseSize "1  B"   , 4, 1
  checkParseSize "1k"     , 2, 1000
  checkParseSize "1 kib"  , 5, 1024
  checkParseSize "1 ki"   , 4, 1024
  checkParseSize "1mi"    , 3, 1048576
  checkParseSize "1 mi"   , 4, 1048576
  checkParseSize "1 mib"  , 5, 1048576
  checkParseSize "1 Mib"  , 5, 1048576
  checkParseSize "1 MiB"  , 5, 1048576
  checkParseSize "1.23GiB", 7, 1320702444 # 1320702443.52 rounded
  checkParseSize "0.001k" , 6, 1
  checkParseSize "0.0004k", 7, 0
  checkParseSize "0.0006k", 7, 1
  # Incomplete parses
  checkParseSize "1  "    , 1, 1          # Trailing white IGNORED
  checkParseSize "1  B "  , 4, 1          # Trailing white IGNORED
  checkParseSize "1  B/s" , 4, 1          # Trailing junk IGNORED
  checkParseSize "1 kX"   , 3, 1000
  checkParseSize "1 kiX"  , 4, 1024
  checkParseSize "1j"     , 1, 1          # Unknown prefix IGNORED
  checkParseSize "1 jib"  , 2, 1          # Unknown prefix post space
  checkParseSize "1  ji"  , 3, 1
  # Bad parses; `sz` should stay last good|incomplete value
  checkParseSize "-1b"    , 0, 1          # Negative numbers
  checkParseSize "abc"    , 0, 1          # Non-numeric
  checkParseSize " 12"    , 0, 1          # Leading white
  # Value Edge cases
  checkParseSize "9223372036854775807", 19, int64.high

block: # bug #23936
  func parsePyFloat(
      a: openArray[char],  # here must be openArray instead of string to reproduce this bug
      res: var BiggestFloat): int =
    result = parseFloat(a, res)

  static:
    var f = 0.0
    doAssert "1.0".parsePyFloat(f) == 3
    doAssert f == 1.0

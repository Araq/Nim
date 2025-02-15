discard """
  matrix: "; --backend:js --jsbigint64:off -d:nimStringHash2; --backend:js --jsbigint64:on"
  output: '''
0 0
0 0
Success'''
"""
# Test the different integer operations


import std/private/jsutils

var testNumber = 0

template test(opr, a, b, c: untyped): untyped =
  # test the expression at compile and runtime
  block:
    const constExpr = opr(a, b)
    when constExpr != c:
      {.error: "Test failed " & $constExpr & " " & $c.}
    inc(testNumber)
    #Echo("Test: " & $testNumber)
    var aa = a
    var bb = b
    var varExpr = opr(aa, bb)
    assert(varExpr == c)

test(`+`, 12'i8, -13'i16, -1'i16)
test(`shl`, 0b11, 0b100, 0b110000)
when hasWorkingInt64:
  test(`shl`, 0b11'i64, 0b100'i64, 0b110000'i64)
when not defined(js):
  # mixed type shr needlessly complicates codegen with bigint
  # and thus is not yet supported in JS for 64 bit ints
  test(`shl`, 0b11'i32, 0b100'i64, 0b110000'i64)
test(`shl`, 0b11'i32, 0b100'i32, 0b110000'i32)

test(`or`, 0xf0f0'i16, 0x0d0d'i16, 0xfdfd'i16)
test(`and`, 0xf0f0'i16, 0xfdfd'i16, 0xf0f0'i16)

when hasWorkingInt64:
  test(`shr`, 0xffffffffffffffff'i64, 0x4'i64, 0xffffffffffffffff'i64)
test(`shr`, 0xffff'i16, 0x4'i16, 0xffff'i16)
test(`shr`, 0xff'i8, 0x4'i8, 0xff'i8)

when hasWorkingInt64:
  test(`shr`, 0xffffffff'i64, 0x4'i64, 0x0fffffff'i64)
test(`shr`, 0xffffffff'i32, 0x4'i32, 0xffffffff'i32)

when hasWorkingInt64:
  test(`shl`, 0xffffffffffffffff'i64, 0x4'i64, 0xfffffffffffffff0'i64)
test(`shl`, 0xffff'i16, 0x4'i16, 0xfff0'i16)
test(`shl`, 0xff'i8, 0x4'i8, 0xf0'i8)

when hasWorkingInt64:
  test(`shl`, 0xffffffff'i64, 0x4'i64, 0xffffffff0'i64)
test(`shl`, 0xffffffff'i32, 0x4'i32, 0xfffffff0'i32)

# bug #916
proc unc(a: float): float =
  return a

echo int(unc(0.5)), " ", int(unc(-0.5))
echo int(0.5), " ", int(-0.5)

block: # Casts to uint
  template testCast(fromValue: typed, toType: typed, expectedResult: typed) =
    let src = fromValue
    let dst = cast[toType](src)
    if dst != expectedResult:
      echo "Casting ", astToStr(fromValue), " to ", astToStr(toType), " = ", dst.int, " instead of ", astToStr(expectedResult)
    doAssert(dst == expectedResult)

  testCast(-1'i16, uint16, 0xffff'u16)
  testCast(0xffff'u16, int16, -1'i16)

  testCast(0xff'u16, uint8, 0xff'u8)
  testCast(0xffff'u16, uint8, 0xff'u8)

  testCast(-1'i16, uint32, 0xffffffff'u32)
  testCast(0xffffffff'u32, int32, -1)

  testCast(0xfffffffe'u32, int32, -2'i32)
  testCast(0xffffff'u32, int16, -1'i32)

  testCast(-5'i32, uint8, 251'u8)

# issue #7174
let c = 1'u
let val = c > 0
doAssert val

block: # bug #6752
  when not defined(js) or (defined(js) and compileOption("jsbigint64")):
    let x = 711127'i64
    doAssert x * 86400'i64 == 61441372800'i64

block: # bug #17604
  let a = 2147483648'u
  doAssert (a and a) == a
  doAssert (a or 0) == a

block: # bitwise not
  let
    z8 = 0'u8
    z16 = 0'u16
    z32 = 0'u32
    z64 = 0'u64
  doAssert (not z8) == uint8.high
  doAssert (not z16) == uint16.high
  doAssert (not z32) == uint32.high
  when not defined(js) or (defined(js) and compileOption("jsbigint64")):
    doAssert (not z64) == uint64.high

block: # shl
  let i8 = int8.high
  let i16 = int16.high
  let i32 = int32.high
  let i64 = int64.high
  doAssert i8 shl 1 == -2
  doAssert i8 shl 2 == -4
  doAssert i16 shl 1 == -2
  doAssert i16 shl 2 == -4
  doAssert i32 shl 1 == -2
  doAssert i32 shl 2 == -4
  when not defined(js) or (defined(js) and compileOption("jsbigint64")):
    doAssert i64 shl 1 == -2
    doAssert i64 shl 2 == -4

  let u8 = uint8.high
  let u16 = uint16.high
  let u32 = uint32.high
  let u64 = uint64.high
  doAssert u8 shl 1 == u8 - 1
  doAssert u16 shl 1 == u16 - 1
  doAssert u32 shl 1 == u32 - 1
  when not defined(js) or (defined(js) and compileOption("jsbigint64")):
    doAssert u64 shl 1 == u64 - 1

block: # bug #23378
  var neg = -1  # prevent compile-time evaluation
  let n = abs BiggestInt neg
  doAssert n == 1

echo("Success") #OUT Success

discard """
  nimout: "OK"
  matrix: "--mm:refc; --mm:orc"
  output: '''
OK
'''
"""
import bitops
import std/assertions

proc main() =
  const U8 = 0b0011_0010'u8
  const I8 = 0b0011_0010'i8
  const U16 = 0b00100111_00101000'u16
  const I16 = 0b00100111_00101000'i16
  const U32 = 0b11010101_10011100_11011010_01010000'u32
  const I32 = 0b11010101_10011100_11011010_01010000'i32
  const U64A = 0b01000100_00111111_01111100_10001010_10011001_01001000_01111010_00010001'u64
  const I64A = 0b01000100_00111111_01111100_10001010_10011001_01001000_01111010_00010001'i64
  const U64B = 0b00110010_11011101_10001111_00101000_00000000_00000000_00000000_00000000'u64
  const I64B = 0b00110010_11011101_10001111_00101000_00000000_00000000_00000000_00000000'i64
  const U64C = 0b00101010_11110101_10001111_00101000_00000100_00000000_00000100_00000000'u64
  const I64C = 0b00101010_11110101_10001111_00101000_00000100_00000000_00000100_00000000'i64

  doAssert (U8 and U8) == bitand(U8,U8)
  doAssert (I8 and I8) == bitand(I8,I8)
  doAssert (U16 and U16) == bitand(U16,U16)
  doAssert (I16 and I16) == bitand(I16,I16)
  doAssert (U32 and U32) == bitand(U32,U32)
  doAssert (I32 and I32) == bitand(I32,I32)
  doAssert (U64A and U64B) == bitand(U64A,U64B)
  doAssert (I64A and I64B) == bitand(I64A,I64B)
  doAssert (U64A and U64B and U64C) == bitand(U64A,U64B,U64C)
  doAssert (I64A and I64B and I64C) == bitand(I64A,I64B,I64C)

  doAssert (U8 or U8) == bitor(U8,U8)
  doAssert (I8 or I8) == bitor(I8,I8)
  doAssert (U16 or U16) == bitor(U16,U16)
  doAssert (I16 or I16) == bitor(I16,I16)
  doAssert (U32 or U32) == bitor(U32,U32)
  doAssert (I32 or I32) == bitor(I32,I32)
  doAssert (U64A or U64B) == bitor(U64A,U64B)
  doAssert (I64A or I64B) == bitor(I64A,I64B)
  doAssert (U64A or U64B or U64C) == bitor(U64A,U64B,U64C)
  doAssert (I64A or I64B or I64C) == bitor(I64A,I64B,I64C)

  doAssert (U8 xor U8) == bitxor(U8,U8)
  doAssert (I8 xor I8) == bitxor(I8,I8)
  doAssert (U16 xor U16) == bitxor(U16,U16)
  doAssert (I16 xor I16) == bitxor(I16,I16)
  doAssert (U32 xor U32) == bitxor(U32,U32)
  doAssert (I32 xor I32) == bitxor(I32,I32)
  doAssert (U64A xor U64B) == bitxor(U64A,U64B)
  doAssert (I64A xor I64B) == bitxor(I64A,I64B)
  doAssert (U64A xor U64B xor U64C) == bitxor(U64A,U64B,U64C)
  doAssert (I64A xor I64B xor I64C) == bitxor(I64A,I64B,I64C)

  doAssert not(U8) == bitnot(U8)
  doAssert not(I8) == bitnot(I8)
  doAssert not(U16) == bitnot(U16)
  doAssert not(I16) == bitnot(I16)
  doAssert not(U32) == bitnot(U32)
  doAssert not(I32) == bitnot(I32)
  doAssert not(U64A) == bitnot(U64A)
  doAssert not(I64A) == bitnot(I64A)

  doAssert U64A.fastLog2 == 62
  doAssert I64A.fastLog2 == 62
  doAssert U64A.countLeadingZeroBits == 1
  doAssert I64A.countLeadingZeroBits == 1
  doAssert U64A.countTrailingZeroBits == 0
  doAssert I64A.countTrailingZeroBits == 0
  doAssert U64A.firstSetBit == 1
  doAssert I64A.firstSetBit == 1
  doAssert U64A.parityBits == 1
  doAssert I64A.parityBits == 1
  doAssert U64A.countSetBits == 29
  doAssert I64A.countSetBits == 29
  doAssert U64A.rotateLeftBits(37) == 0b00101001_00001111_01000010_00101000_10000111_11101111_10010001_01010011'u64
  doAssert U64A.rotateRightBits(37) == 0b01010100_11001010_01000011_11010000_10001010_00100001_11111011_11100100'u64

  doAssert U64B.firstSetBit == 36
  doAssert I64B.firstSetBit == 36

  doAssert U32.fastLog2 == 31
  doAssert I32.fastLog2 == 31
  doAssert U32.countLeadingZeroBits == 0
  doAssert I32.countLeadingZeroBits == 0
  doAssert U32.countTrailingZeroBits == 4
  doAssert I32.countTrailingZeroBits == 4
  doAssert U32.firstSetBit == 5
  doAssert I32.firstSetBit == 5
  doAssert U32.parityBits == 0
  doAssert I32.parityBits == 0
  doAssert U32.countSetBits == 16
  doAssert I32.countSetBits == 16
  doAssert U32.rotateLeftBits(21) == 0b01001010_00011010_10110011_10011011'u32
  doAssert U32.rotateRightBits(21) == 0b11100110_11010010_10000110_10101100'u32

  doAssert U16.fastLog2 == 13
  doAssert I16.fastLog2 == 13
  doAssert U16.countLeadingZeroBits == 2
  doAssert I16.countLeadingZeroBits == 2
  doAssert U16.countTrailingZeroBits == 3
  doAssert I16.countTrailingZeroBits == 3
  doAssert U16.firstSetBit == 4
  doAssert I16.firstSetBit == 4
  doAssert U16.parityBits == 0
  doAssert I16.parityBits == 0
  doAssert U16.countSetBits == 6
  doAssert I16.countSetBits == 6
  doAssert U16.rotateLeftBits(12) == 0b10000010_01110010'u16
  doAssert U16.rotateRightBits(12) == 0b01110010_10000010'u16

  doAssert U8.fastLog2 == 5
  doAssert I8.fastLog2 == 5
  doAssert U8.countLeadingZeroBits == 2
  doAssert I8.countLeadingZeroBits == 2
  doAssert U8.countTrailingZeroBits == 1
  doAssert I8.countTrailingZeroBits == 1
  doAssert U8.firstSetBit == 2
  doAssert I8.firstSetBit == 2
  doAssert U8.parityBits == 1
  doAssert I8.parityBits == 1
  doAssert U8.countSetBits == 3
  doAssert I8.countSetBits == 3
  doAssert U8.rotateLeftBits(3) == 0b10010001'u8
  doAssert U8.rotateRightBits(3) == 0b0100_0110'u8

  template test_undefined_impl(ffunc: untyped; expected: int; is_static: bool) =
    doAssert ffunc(0'u8) == expected
    doAssert ffunc(0'i8) == expected
    doAssert ffunc(0'u16) == expected
    doAssert ffunc(0'i16) == expected
    doAssert ffunc(0'u32) == expected
    doAssert ffunc(0'i32) == expected
    doAssert ffunc(0'u64) == expected
    doAssert ffunc(0'i64) == expected

  template test_undefined(ffunc: untyped; expected: int) =
    test_undefined_impl(ffunc, expected, false)
    static:
      test_undefined_impl(ffunc, expected, true)

  when defined(noUndefinedBitOpts):
    # check for undefined behavior with zero.
    test_undefined(countSetBits, 0)
    test_undefined(parityBits, 0)
    test_undefined(firstSetBit, 0)
    test_undefined(countLeadingZeroBits, 0)
    test_undefined(countTrailingZeroBits, 0)
    test_undefined(fastLog2, -1)

    # check for undefined behavior with rotate by zero.
    doAssert U8.rotateLeftBits(0) == U8
    doAssert U8.rotateRightBits(0) == U8
    doAssert U16.rotateLeftBits(0) == U16
    doAssert U16.rotateRightBits(0) == U16
    doAssert U32.rotateLeftBits(0) == U32
    doAssert U32.rotateRightBits(0) == U32
    doAssert U64A.rotateLeftBits(0) == U64A
    doAssert U64A.rotateRightBits(0) == U64A

    # check for undefined behavior with rotate by integer width.
    doAssert U8.rotateLeftBits(8) == U8
    doAssert U8.rotateRightBits(8) == U8
    doAssert U16.rotateLeftBits(16) == U16
    doAssert U16.rotateRightBits(16) == U16
    doAssert U32.rotateLeftBits(32) == U32
    doAssert U32.rotateRightBits(32) == U32
    doAssert U64A.rotateLeftBits(64) == U64A
    doAssert U64A.rotateRightBits(64) == U64A

  block:
    # basic mask operations (mutating)
    var v: uint8 = 0'u8
    v.setMask(0b1100_0000)
    v.setMask(0b0000_1100)
    doAssert v == 0b1100_1100
    v.flipMask(0b0101_0101)
    doAssert v == 0b1001_1001
    v.clearMask(0b1000_1000)
    doAssert v == 0b0001_0001
    v.clearMask(0b0001_0001)
    doAssert v == 0b0000_0000
    v.setMask(0b0001_1110)
    doAssert v == 0b0001_1110
    v.mask(0b0101_0100)
    doAssert v == 0b0001_0100
  block:
    # basic mask operations (non-mutating)
    let v = 0b1100_0000'u8
    doAssert v.masked(0b0000_1100) == 0b0000_0000
    doAssert v.masked(0b1000_1100) == 0b1000_0000
    doAssert v.setMasked(0b0000_1100) == 0b1100_1100
    doAssert v.setMasked(0b1000_1110) == 0b1100_1110
    doAssert v.flipMasked(0b1100_1000) == 0b0000_1000
    doAssert v.flipMasked(0b0000_1100) == 0b1100_1100
    let t = 0b1100_0110'u8
    doAssert t.clearMasked(0b0100_1100) == 0b1000_0010
    doAssert t.clearMasked(0b1100_0000) == 0b0000_0110
  block:
    # basic bitslice opeartions
    let a = 0b1111_1011'u8
    doAssert a.bitsliced(0 .. 3) == 0b1011
    doAssert a.bitsliced(2 .. 3) == 0b10
    doAssert a.bitsliced(4 .. 7) == 0b1111

    # same thing, but with exclusive ranges.
    doAssert a.bitsliced(0 ..< 4) == 0b1011
    doAssert a.bitsliced(2 ..< 4) == 0b10
    doAssert a.bitsliced(4 ..< 8) == 0b1111

    # mutating
    var b = 0b1111_1011'u8
    b.bitslice(1 .. 3)
    doAssert b == 0b101

    # loop test:
    let c = 0b1111_1111'u8
    for i in 0 .. 7:
      doAssert c.bitsliced(i .. 7) == c shr i
  block:
    # bitslice versions of mask operations (mutating)
    var a = 0b1100_1100'u8
    let b = toMask[uint8](2 .. 3)
    a.mask(b)
    doAssert a == 0b0000_1100
    a.setMask(4 .. 7)
    doAssert a == 0b1111_1100
    a.flipMask(1 .. 3)
    doAssert a == 0b1111_0010
    a.flipMask(2 .. 4)
    doAssert a == 0b1110_1110
    a.clearMask(2 .. 4)
    doAssert a == 0b1110_0010
    a.mask(0 .. 3)
    doAssert a == 0b0000_0010

    # composition of mask from slices:
    let c = bitor(toMask[uint8](2 .. 3), toMask[uint8](5 .. 7))
    doAssert c == 0b1110_1100'u8
  block:
    # bitslice versions of mask operations (non-mutating)
    let a = 0b1100_1100'u8
    doAssert a.masked(toMask[uint8](2 .. 3)) == 0b0000_1100
    doAssert a.masked(2 .. 3) == 0b0000_1100
    doAssert a.setMasked(0 .. 3) == 0b1100_1111
    doAssert a.setMasked(3 .. 4) == 0b1101_1100
    doAssert a.flipMasked(0 .. 3) == 0b1100_0011
    doAssert a.flipMasked(0 .. 7) == 0b0011_0011
    doAssert a.flipMasked(2 .. 3) == 0b1100_0000
    doAssert a.clearMasked(2 .. 3) == 0b1100_0000
    doAssert a.clearMasked(3 .. 6) == 0b1000_0100
  block:
    # single bit operations
    var v: uint8 = 0'u8
    v.setBit(0)
    doAssert v == 0x0000_0001
    v.setBit(1)
    doAssert v == 0b0000_0011
    v.flipBit(7)
    doAssert v == 0b1000_0011
    v.clearBit(0)
    doAssert v == 0b1000_0010
    v.flipBit(1)
    doAssert v == 0b1000_0000
    doAssert v.testBit(7)
    doAssert not v.testBit(6)
  block:
    # multi bit operations
    var v: uint8 = 0'u8
    v.setBits(0, 1, 7)
    doAssert v == 0b1000_0011
    v.flipBits(2, 3)
    doAssert v == 0b1000_1111
    v.clearBits(7, 0, 1)
    doAssert v == 0b0000_1100
  block:
    # signed
    var v: int8 = 0'i8
    v.setBit(7)
    doAssert v == -128
  block:
    var v: uint64 = 0'u64
    v.setBit(63)
    doAssert v == 0b1000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000'u64

  block:
    proc testReverseBitsInvo(x: SomeUnsignedInt) =
      doAssert reverseBits(reverseBits(x)) == x

    proc testReverseBitsPerType(x, reversed: uint64) =
      doAssert reverseBits(x) == reversed
      doAssert reverseBits(cast[uint32](x)) == cast[uint32](reversed shr 32)
      doAssert reverseBits(cast[uint32](x shr 16)) == cast[uint32](reversed shr 16)
      doAssert reverseBits(cast[uint16](x)) == cast[uint16](reversed shr 48)
      doAssert reverseBits(cast[uint8](x)) == cast[uint8](reversed shr 56)

      testReverseBitsInvo(x)
      testReverseBitsInvo(cast[uint32](x))
      testReverseBitsInvo(cast[uint16](x))
      testReverseBitsInvo(cast[uint8](x))

    proc testReverseBitsRefl(x, reversed: uint64) =
      testReverseBitsPerType(x, reversed)
      testReverseBitsPerType(reversed, x)

    proc testReverseBitsShift(d, b: uint64) =
      var
        x = d
        y = b

      for i in 1..64:
        testReverseBitsRefl(x, y)
        x = x shl 1
        y = y shr 1

    proc testReverseBits(d, b: uint64) =
      testReverseBitsShift(d, b)

    testReverseBits(0x0u64, 0x0u64)
    testReverseBits(0xffffffffffffffffu64, 0xffffffffffffffffu64)
    testReverseBits(0x0123456789abcdefu64, 0xf7b3d591e6a2c480u64)
    testReverseBits(0x5555555555555555u64, 0xaaaaaaaaaaaaaaaau64)
    testReverseBits(0x5555555500000001u64, 0x80000000aaaaaaaau64)
    testReverseBits(0x55555555aaaaaaaau64, 0x55555555aaaaaaaau64)
    testReverseBits(0xf0f0f0f00f0f0f0fu64, 0xf0f0f0f00f0f0f0fu64)
    testReverseBits(0x181881810ff00916u64, 0x68900ff081811818u64)

  echo "OK"

  # bug #7587
  doAssert popcount(0b11111111'i8) == 8

block: # not ready for vm because exception is compile error
  try:
    var v: uint32 = 0'u32
    var i = 32
    v.setBit(i)
    doAssert false
  except RangeDefect:
    discard
  except:
    doAssert false


main()
static:
  # test everything on vm as well
  main()

##  Copyright 2020 Alexander Bolz
##
##  Distributed under the Boost Software License, Version 1.0.
##   (See accompanying file LICENSE_1_0.txt or copy at https://www.boost.org/LICENSE_1_0.txt)

# --------------------------------------------------------------------------------------------------
##  This file contains an implementation of the Schubfach algorithm as described in
##
##  \[1] Raffaello Giulietti, "The Schubfach way to render doubles",
##      https://drive.google.com/open?id=1luHhyQF9zKlM8yJ1nebU0OgVYhfC6CBN
# --------------------------------------------------------------------------------------------------

import std/private/digitsutils

when defined(nimPreviewSlimSystem):
  import std/assertions


template sf_Assert(x: untyped): untyped =
  assert(x)

# ==================================================================================================
#
# ==================================================================================================

type
  ValueType = float32
  BitsType = uint32
  Single {.bycopy.} = object
    bits: BitsType

const
  significandSize: int32 = 24
  MaxExponent = 128
  exponentBias: int32 = MaxExponent - 1 + (significandSize - 1)
  maxIeeeExponent: BitsType = BitsType(2 * MaxExponent - 1)
  hiddenBit: BitsType = BitsType(1) shl (significandSize - 1)
  significandMask: BitsType = hiddenBit - 1
  exponentMask: BitsType = maxIeeeExponent shl (significandSize - 1)
  signMask: BitsType = not (not BitsType(0) shr 1)

proc constructSingle(bits: BitsType): Single =
  result = Single(bits: bits)

proc constructSingle(value: ValueType): Single =
  result = Single(bits: cast[typeof(result.bits)](value))

proc physicalSignificand(this: Single): BitsType {.noSideEffect.} =
  return this.bits and significandMask

proc physicalExponent(this: Single): BitsType {.noSideEffect.} =
  return (this.bits and exponentMask) shr (significandSize - 1)

proc isFinite(this: Single): bool {.noSideEffect.} =
  return (this.bits and exponentMask) != exponentMask

proc isInf(this: Single): bool {.noSideEffect.} =
  return (this.bits and exponentMask) == exponentMask and
      (this.bits and significandMask) == 0

proc isNaN(this: Single): bool {.noSideEffect.} =
  return (this.bits and exponentMask) == exponentMask and
      (this.bits and significandMask) != 0

proc isZero(this: Single): bool {.noSideEffect.} =
  return (this.bits and not signMask) == 0

proc signBit(this: Single): int {.noSideEffect.} =
  return int((this.bits and signMask) != 0)

# ==================================================================================================
##  Returns floor(x / 2^n).
##
##  Technically, right-shift of negative integers is implementation defined...
##  Should easily be optimized into SAR (or equivalent) instruction.

proc floorDivPow2(x: int32; n: int32): int32 {.inline.} =
  return x shr n

##  Returns floor(log_10(2^e))
##  ```c
##  static inline int32_t FloorLog10Pow2(int32_t e)
##  {
##      SF_ASSERT(e >= -1500);
##      SF_ASSERT(e <=  1500);
##      return FloorDivPow2(e * 1262611, 22);
##  }
##  ```
##  Returns floor(log_10(3/4 2^e))
##  ```c
##  static inline int32_t FloorLog10ThreeQuartersPow2(int32_t e)
##  {
##      SF_ASSERT(e >= -1500);
##      SF_ASSERT(e <=  1500);
##      return FloorDivPow2(e * 1262611 - 524031, 22);
##  }
##  ```
##  Returns floor(log_2(10^e))

proc floorLog2Pow10(e: int32): int32 {.inline.} =
  sf_Assert(e >= -1233)
  sf_Assert(e <= 1233)
  return floorDivPow2(e * 1741647, 19)

const
  kMin: int32 = -31
  kMax: int32 = 45
  g: array[kMax - kMin + 1, uint64] = [0x81CEB32C4B43FCF5'u64, 0xA2425FF75E14FC32'u64,
    0xCAD2F7F5359A3B3F'u64, 0xFD87B5F28300CA0E'u64, 0x9E74D1B791E07E49'u64,
    0xC612062576589DDB'u64, 0xF79687AED3EEC552'u64, 0x9ABE14CD44753B53'u64,
    0xC16D9A0095928A28'u64, 0xF1C90080BAF72CB2'u64, 0x971DA05074DA7BEF'u64,
    0xBCE5086492111AEB'u64, 0xEC1E4A7DB69561A6'u64, 0x9392EE8E921D5D08'u64,
    0xB877AA3236A4B44A'u64, 0xE69594BEC44DE15C'u64, 0x901D7CF73AB0ACDA'u64,
    0xB424DC35095CD810'u64, 0xE12E13424BB40E14'u64, 0x8CBCCC096F5088CC'u64,
    0xAFEBFF0BCB24AAFF'u64, 0xDBE6FECEBDEDD5BF'u64, 0x89705F4136B4A598'u64,
    0xABCC77118461CEFD'u64, 0xD6BF94D5E57A42BD'u64, 0x8637BD05AF6C69B6'u64,
    0xA7C5AC471B478424'u64, 0xD1B71758E219652C'u64, 0x83126E978D4FDF3C'u64,
    0xA3D70A3D70A3D70B'u64, 0xCCCCCCCCCCCCCCCD'u64, 0x8000000000000000'u64,
    0xA000000000000000'u64, 0xC800000000000000'u64, 0xFA00000000000000'u64,
    0x9C40000000000000'u64, 0xC350000000000000'u64, 0xF424000000000000'u64,
    0x9896800000000000'u64, 0xBEBC200000000000'u64, 0xEE6B280000000000'u64,
    0x9502F90000000000'u64, 0xBA43B74000000000'u64, 0xE8D4A51000000000'u64,
    0x9184E72A00000000'u64, 0xB5E620F480000000'u64, 0xE35FA931A0000000'u64,
    0x8E1BC9BF04000000'u64, 0xB1A2BC2EC5000000'u64, 0xDE0B6B3A76400000'u64,
    0x8AC7230489E80000'u64, 0xAD78EBC5AC620000'u64, 0xD8D726B7177A8000'u64,
    0x878678326EAC9000'u64, 0xA968163F0A57B400'u64, 0xD3C21BCECCEDA100'u64,
    0x84595161401484A0'u64, 0xA56FA5B99019A5C8'u64, 0xCECB8F27F4200F3A'u64,
    0x813F3978F8940985'u64, 0xA18F07D736B90BE6'u64, 0xC9F2C9CD04674EDF'u64,
    0xFC6F7C4045812297'u64, 0x9DC5ADA82B70B59E'u64, 0xC5371912364CE306'u64,
    0xF684DF56C3E01BC7'u64, 0x9A130B963A6C115D'u64, 0xC097CE7BC90715B4'u64,
    0xF0BDC21ABB48DB21'u64, 0x96769950B50D88F5'u64, 0xBC143FA4E250EB32'u64,
    0xEB194F8E1AE525FE'u64, 0x92EFD1B8D0CF37BF'u64, 0xB7ABC627050305AE'u64,
    0xE596B7B0C643C71A'u64, 0x8F7E32CE7BEA5C70'u64, 0xB35DBF821AE4F38C'u64]

proc computePow10Single(k: int32): uint64 {.inline.} =
  ##  There are unique beta and r such that 10^k = beta 2^r and
  ##  2^63 <= beta < 2^64, namely r = floor(log_2 10^k) - 63 and
  ##  beta = 2^-r 10^k.
  ##  Let g = ceil(beta), so (g-1) 2^r < 10^k <= g 2^r, with the latter
  ##  value being a pretty good overestimate for 10^k.
  ##  NB: Since for all the required exponents k, we have g < 2^64,
  ##      all constants can be stored in 128-bit integers.
  sf_Assert(k >= kMin)
  sf_Assert(k <= kMax)
  return g[k - kMin]

proc lo32(x: uint64): uint32 {.inline.} =
  return cast[uint32](x)

proc hi32(x: uint64): uint32 {.inline.} =
  return cast[uint32](x shr 32)

when defined(sizeof_Int128):
  proc roundToOdd(g: uint64; cp: uint32): uint32 {.inline.} =
    let p: uint128 = uint128(g) * cp
    let y1: uint32 = lo32(cast[uint64](p shr 64))
    let y0: uint32 = hi32(cast[uint64](p))
    return y1 or uint32(y0 > 1)

elif defined(vcc) and defined(cpu64):
  proc umul128(x, y: uint64, z: ptr uint64): uint64 {.importc: "_umul128", header: "<intrin.h>".}
  proc roundToOdd(g: uint64; cpHi: uint32): uint32 {.inline.} =
    var p1: uint64 = 0
    var p0: uint64 = umul128(g, cpHi, addr(p1))
    let y1: uint32 = lo32(p1)
    let y0: uint32 = hi32(p0)
    return y1 or uint32(y0 > 1)

else:
  proc roundToOdd(g: uint64; cp: uint32): uint32 {.inline.} =
    let b01: uint64 = uint64(lo32(g)) * cp
    let b11: uint64 = uint64(hi32(g)) * cp
    let hi: uint64 = b11 + hi32(b01)
    let y1: uint32 = hi32(hi)
    let y0: uint32 = lo32(hi)
    return y1 or uint32(y0 > 1)

##  Returns whether value is divisible by 2^e2

proc multipleOfPow2(value: uint32; e2: int32): bool {.inline.} =
  sf_Assert(e2 >= 0)
  sf_Assert(e2 <= 31)
  return (value and ((uint32(1) shl e2) - 1)) == 0

type
  FloatingDecimal32 {.bycopy.} = object
    digits: uint32            ##  num_digits <= 9
    exponent: int32

proc toDecimal32(ieeeSignificand: uint32; ieeeExponent: uint32): FloatingDecimal32 {.
    inline.} =
  var c: uint32
  var q: int32
  if ieeeExponent != 0:
    c = hiddenBit or ieeeSignificand
    q = cast[int32](ieeeExponent) - exponentBias
    if 0 <= -q and -q < significandSize and multipleOfPow2(c, -q):
      return FloatingDecimal32(digits: c shr -q, exponent: 0'i32)
  else:
    c = ieeeSignificand
    q = 1 - exponentBias
  let isEven: bool = (c mod 2 == 0)
  let lowerBoundaryIsCloser: bool = (ieeeSignificand == 0 and ieeeExponent > 1)
  ##   const int32_t qb = q - 2;
  let cbl: uint32 = 4 * c - 2 + uint32(lowerBoundaryIsCloser)
  let cb: uint32 = 4 * c
  let cbr: uint32 = 4 * c + 2
  ##  (q * 1262611         ) >> 22 == floor(log_10(    2^q))
  ##  (q * 1262611 - 524031) >> 22 == floor(log_10(3/4 2^q))
  sf_Assert(q >= -1500)
  sf_Assert(q <= 1500)
  let k: int32 = floorDivPow2(q * 1262611 - (if lowerBoundaryIsCloser: 524031 else: 0), 22)
  let h: int32 = q + floorLog2Pow10(-k) + 1
  sf_Assert(h >= 1)
  sf_Assert(h <= 4)
  let pow10: uint64 = computePow10Single(-k)
  let vbl: uint32 = roundToOdd(pow10, cbl shl h)
  let vb: uint32 = roundToOdd(pow10, cb shl h)
  let vbr: uint32 = roundToOdd(pow10, cbr shl h)
  let lower: uint32 = vbl + uint32(not isEven)
  let upper: uint32 = vbr - uint32(not isEven)
  ##  See Figure 4 in [1].
  ##  And the modifications in Figure 6.
  let s: uint32 = vb div 4
  ##  NB: 4 * s == vb & ~3 == vb & -4
  if s >= 10:
    let sp: uint32 = s div 10
    ##  = vb / 40
    let upInside: bool = lower <= 40 * sp
    let wpInside: bool = 40 * sp + 40 <= upper
    ##       if (up_inside || wp_inside) // NB: At most one of u' and w' is in R_v.
    if upInside != wpInside:
      return FloatingDecimal32(digits: sp + uint32(wpInside), exponent: k + 1)
  let uInside: bool = lower <= 4 * s
  let wInside: bool = 4 * s + 4 <= upper
  if uInside != wInside:
    return FloatingDecimal32(digits: s + uint32(wInside), exponent: k)
  let mid: uint32 = 4 * s + 2
  ##  = 2(s + t)
  let roundUp: bool = vb > mid or (vb == mid and (s and 1) != 0)
  return FloatingDecimal32(digits: s + uint32(roundUp), exponent: k)

## ==================================================================================================
##  ToChars
## ==================================================================================================

proc printDecimalDigitsBackwards[T: Ordinal](buf: var openArray[char]; pos: T; output: uint32): int {.inline.} =
  var output = output
  var pos = pos
  var tz = 0
  ##  number of trailing zeros removed.
  var nd = 0
  ##  number of decimal digits processed.
  ##  At most 9 digits remaining
  if output >= 10000:
    let q: uint32 = output div 10000
    let r: uint32 = output mod 10000
    output = q
    dec(pos, 4)
    if r != 0:
      let rH: uint32 = r div 100
      let rL: uint32 = r mod 100
      utoa2Digits(buf, pos, rH)
      utoa2Digits(buf, pos + 2, rL)
      tz = trailingZeros2Digits(if rL == 0: rH else: rL) + (if rL == 0: 2 else: 0)
    else:
      tz = 4
    nd = 4
  if output >= 100:
    let q: uint32 = output div 100
    let r: uint32 = output mod 100
    output = q
    dec(pos, 2)
    utoa2Digits(buf, pos, r)
    if tz == nd:
      inc(tz, trailingZeros2Digits(r))
    inc(nd, 2)
    if output >= 100:
      let q2: uint32 = output div 100
      let r2: uint32 = output mod 100
      output = q2
      dec(pos, 2)
      utoa2Digits(buf, pos, r2)
      if tz == nd:
        inc(tz, trailingZeros2Digits(r2))
      inc(nd, 2)
  sf_Assert(output >= 1)
  sf_Assert(output <= 99)
  if output >= 10:
    let q: uint32 = output
    dec(pos, 2)
    utoa2Digits(buf, pos, q)
    if tz == nd:
      inc(tz, trailingZeros2Digits(q))
  else:
    let q: uint32 = output
    sf_Assert(q >= 1)
    sf_Assert(q <= 9)
    dec(pos)
    buf[pos] = chr(uint32('0') + q)
  return tz

proc decimalLength(v: uint32): int {.inline.} =
  sf_Assert(v >= 1)
  sf_Assert(v <= 999999999'u)
  if v >= 100000000'u:
    return 9
  if v >= 10000000'u:
    return 8
  if v >= 1000000'u:
    return 7
  if v >= 100000'u:
    return 6
  if v >= 10000'u:
    return 5
  if v >= 1000'u:
    return 4
  if v >= 100'u:
    return 3
  if v >= 10'u:
    return 2
  return 1

proc formatDigits[T: Ordinal](buffer: var openArray[char]; pos: T; digits: uint32; decimalExponent: int;
                  forceTrailingDotZero: bool = false): int {.inline.} =
  const
    minFixedDecimalPoint: int32 = -4
    maxFixedDecimalPoint: int32 = 9
  var pos = pos
  assert(minFixedDecimalPoint <= -1, "internal error")
  assert(maxFixedDecimalPoint >= 1, "internal error")
  sf_Assert(digits >= 1)
  sf_Assert(digits <= 999999999'u)
  sf_Assert(decimalExponent >= -99)
  sf_Assert(decimalExponent <= 99)
  var numDigits = decimalLength(digits)
  let decimalPoint = numDigits + decimalExponent
  let useFixed: bool = minFixedDecimalPoint <= decimalPoint and
      decimalPoint <= maxFixedDecimalPoint
  ##  Prepare the buffer.
  ##  Avoid calling memset/memcpy with variable arguments below...
  for i in 0..<32: buffer[pos+i] = '0'
  assert(minFixedDecimalPoint >= -30, "internal error")
  assert(maxFixedDecimalPoint <= 32, "internal error")
  var decimalDigitsPosition: int
  if useFixed:
    if decimalPoint <= 0:
      ##  0.[000]digits
      decimalDigitsPosition = 2 - decimalPoint
    else:
      ##  dig.its
      ##  digits[000]
      decimalDigitsPosition = 0
  else:
    ##  dE+123 or d.igitsE+123
    decimalDigitsPosition = 1
  var digitsEnd = pos + decimalDigitsPosition + numDigits
  let tz = printDecimalDigitsBackwards(buffer, digitsEnd, digits)
  dec(digitsEnd, tz)
  dec(numDigits, tz)
  ##   decimal_exponent += tz; // => decimal_point unchanged.
  if useFixed:
    if decimalPoint <= 0:
      ##  0.[000]digits
      buffer[pos+1] = '.'
      pos = digitsEnd
    elif decimalPoint < numDigits:
      ##  dig.its
      for i in countdown(7, 0):
        buffer[i + decimalPoint + 1] = buffer[i + decimalPoint]
      buffer[pos+decimalPoint] = '.'
      pos = digitsEnd + 1
    else:
      ##  digits[000]
      inc(pos, decimalPoint)
      if forceTrailingDotZero:
        buffer[pos] = '.'
        buffer[pos+1] = '0'
        inc(pos, 2)
  else:
    buffer[pos] = buffer[pos+1]
    if numDigits == 1:
      ##  dE+123
      inc(pos)
    else:
      ##  d.igitsE+123
      buffer[pos+1] = '.'
      pos = digitsEnd
    let scientificExponent = decimalPoint - 1
    ##       SF_ASSERT(scientific_exponent != 0);
    buffer[pos] = 'e'
    buffer[pos+1] = if scientificExponent < 0: '-' else: '+'
    inc(pos, 2)
    let k: uint32 = cast[uint32](if scientificExponent < 0: -scientificExponent else: scientificExponent)
    if k < 10:
      buffer[pos] = chr(uint32('0') + k)
      inc pos
    else:
      utoa2Digits(buffer, pos, k)
      inc(pos, 2)
  return pos

proc float32ToChars*(buffer: var openArray[char]; v: float32; forceTrailingDotZero = false): int {.
    inline.} =
  let significand: uint32 = physicalSignificand(constructSingle(v))
  let exponent: uint32 = physicalExponent(constructSingle(v))
  var pos = 0
  if exponent != maxIeeeExponent:
    ##  Finite
    buffer[pos] = '-'
    inc(pos, signBit(constructSingle(v)))
    if exponent != 0 or significand != 0:
      ##  != 0
      let dec: auto = toDecimal32(significand, exponent)
      return formatDigits(buffer, pos, dec.digits, dec.exponent.int, forceTrailingDotZero)
    else:
      buffer[pos] = '0'
      buffer[pos+1] = '.'
      buffer[pos+2] = '0'
      buffer[pos+3] = ' '
      inc(pos, if forceTrailingDotZero: 3 else: 1)
      return pos
  if significand == 0:
    buffer[pos] = '-'
    inc(pos, signBit(constructSingle(v)))
    buffer[pos] = 'i'
    buffer[pos+1] = 'n'
    buffer[pos+2] = 'f'
    buffer[pos+3] = ' '
    return pos + 3
  else:
    buffer[pos] = 'n'
    buffer[pos+1] = 'a'
    buffer[pos+2] = 'n'
    buffer[pos+3] = ' '
    return pos + 3

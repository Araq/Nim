discard """
  targets: "c cpp js"
  matrix:"; -d:danger; --mm:refc"
"""

# xxx: there should be a test with `-d:nimTmathCase2 -d:danger --passc:-ffast-math`,
# but it requires disabling certain lines with `when not defined(nimTmathCase2)`

import std/math
import std/assertions


# Function for approximate comparison of floats
proc `==~`(x, y: float): bool = abs(x - y) < 1e-9


template main() =
  block:
    when not defined(js):
      # check for no side effect annotation
      proc mySqrt(num: float): float {.noSideEffect.} =
        # xxx unused
        sqrt(num)

      # check gamma function
      doAssert gamma(5.0) == 24.0 # 4!
      doAssert almostEqual(gamma(0.5), sqrt(PI))
      doAssert almostEqual(gamma(-0.5), -2 * sqrt(PI))
      doAssert lgamma(1.0) == 0.0 # ln(1.0) == 0.0
      doAssert almostEqual(lgamma(0.5), 0.5 * ln(PI))
      doAssert erf(6.0) > erf(5.0)
      doAssert erfc(6.0) < erfc(5.0)

  block: # sgn() tests
    doAssert sgn(1'i8) == 1
    doAssert sgn(1'i16) == 1
    doAssert sgn(1'i32) == 1
    doAssert sgn(1'i64) == 1
    doAssert sgn(1'u8) == 1
    doAssert sgn(1'u16) == 1
    doAssert sgn(1'u32) == 1
    doAssert sgn(1'u64) == 1
    doAssert sgn(-12342.8844'f32) == -1
    doAssert sgn(123.9834'f64) == 1
    doAssert sgn(0'i32) == 0
    doAssert sgn(0'f32) == 0
    doAssert sgn(-0.0'f64) == 0
    doAssert sgn(NegInf) == -1
    doAssert sgn(Inf) == 1
    doAssert sgn(NaN) == 0

  block: # fac() tests
    when nimvm: discard
    else:
      try:
        discard fac(-1)
      except AssertionDefect:
        discard

    doAssert fac(0) == 1
    doAssert fac(1) == 1
    doAssert fac(2) == 2
    doAssert fac(3) == 6
    doAssert fac(4) == 24
    doAssert fac(5) == 120

  block: # floorMod/floorDiv
    doAssert floorDiv(8, 3) == 2
    doAssert floorMod(8, 3) == 2

    doAssert floorDiv(8, -3) == -3
    doAssert floorMod(8, -3) == -1

    doAssert floorDiv(-8, 3) == -3
    doAssert floorMod(-8, 3) == 1

    doAssert floorDiv(-8, -3) == 2
    doAssert floorMod(-8, -3) == -2

    doAssert floorMod(8.0, -3.0) == -1.0
    doAssert floorMod(-8.5, 3.0) == 0.5

  block: # euclDiv/euclMod
    doAssert euclDiv(8, 3) == 2
    doAssert euclMod(8, 3) == 2

    doAssert euclDiv(8, -3) == -2
    doAssert euclMod(8, -3) == 2

    doAssert euclDiv(-8, 3) == -3
    doAssert euclMod(-8, 3) == 1

    doAssert euclDiv(-8, -3) == 3
    doAssert euclMod(-8, -3) == 1

    doAssert euclMod(8.0, -3.0) == 2.0
    doAssert euclMod(-8.5, 3.0) == 0.5

    doAssert euclDiv(9, 3) == 3
    doAssert euclMod(9, 3) == 0

    doAssert euclDiv(9, -3) == -3
    doAssert euclMod(9, -3) == 0

    doAssert euclDiv(-9, 3) == -3
    doAssert euclMod(-9, 3) == 0

    doAssert euclDiv(-9, -3) == 3
    doAssert euclMod(-9, -3) == 0

  block: # ceilDiv
    doAssert ceilDiv(8,  3) ==  3
    doAssert ceilDiv(8,  4) ==  2
    doAssert ceilDiv(8,  5) ==  2
    doAssert ceilDiv(11, 3) ==  4
    doAssert ceilDiv(12, 3) ==  4
    doAssert ceilDiv(13, 3) ==  5
    doAssert ceilDiv(41, 7) ==  6
    doAssert ceilDiv(0,  1) ==  0
    doAssert ceilDiv(1,  1) ==  1
    doAssert ceilDiv(1,  2) ==  1
    doAssert ceilDiv(2,  1) ==  2
    doAssert ceilDiv(2,  2) ==  1
    doAssert ceilDiv(0, high(int)) == 0
    doAssert ceilDiv(1, high(int)) == 1
    doAssert ceilDiv(0, high(int) - 1) == 0
    doAssert ceilDiv(1, high(int) - 1) == 1
    doAssert ceilDiv(high(int) div 2, high(int) div 2 + 1) == 1
    doAssert ceilDiv(high(int) div 2, high(int) div 2 + 2) == 1
    doAssert ceilDiv(high(int) div 2 + 1, high(int) div 2) == 2
    doAssert ceilDiv(high(int) div 2 + 2, high(int) div 2) == 2
    doAssert ceilDiv(high(int) div 2 + 1, high(int) div 2 + 1) == 1
    doAssert ceilDiv(high(int), 1) == high(int)
    doAssert ceilDiv(high(int) - 1, 1) == high(int) - 1
    doAssert ceilDiv(high(int) - 1, 2) == high(int) div 2
    doAssert ceilDiv(high(int) - 1, high(int)) == 1
    doAssert ceilDiv(high(int) - 1, high(int) - 1) == 1
    doAssert ceilDiv(high(int) - 1, high(int) - 2) == 2
    doAssert ceilDiv(high(int), high(int)) == 1
    doAssert ceilDiv(high(int), high(int) - 1) == 2
    doAssert ceilDiv(255'u8,  1'u8) == 255'u8
    doAssert ceilDiv(254'u8,  2'u8) == 127'u8
    when not defined(danger):
      doAssertRaises(AssertionDefect): discard ceilDiv(41,  0)
      doAssertRaises(AssertionDefect): discard ceilDiv(41, -1)
      doAssertRaises(AssertionDefect): discard ceilDiv(-1,  1)
      doAssertRaises(AssertionDefect): discard ceilDiv(-1, -1)
      doAssertRaises(AssertionDefect): discard ceilDiv(254'u8, 3'u8)
      doAssertRaises(AssertionDefect): discard ceilDiv(255'u8, 2'u8)

  block: # splitDecimal() tests
    doAssert splitDecimal(54.674).intpart == 54.0
    doAssert splitDecimal(54.674).floatpart ==~ 0.674
    doAssert splitDecimal(-693.4356).intpart == -693.0
    doAssert splitDecimal(-693.4356).floatpart ==~ -0.4356
    doAssert splitDecimal(0.0).intpart == 0.0
    doAssert splitDecimal(0.0).floatpart == 0.0

  block: # trunc tests for vcc
    doAssert trunc(-1.1) == -1
    doAssert trunc(1.1) == 1
    doAssert trunc(-0.1) == -0
    doAssert trunc(0.1) == 0

    # special case
    doAssert classify(trunc(1e1000000)) == fcInf
    doAssert classify(trunc(-1e1000000)) == fcNegInf
    when not defined(nimTmathCase2):
      doAssert classify(trunc(0.0/0.0)) == fcNan
    doAssert classify(trunc(0.0)) == fcZero

    # trick the compiler to produce signed zero
    let
      f_neg_one = -1.0
      f_zero = 0.0
      f_nan = f_zero / f_zero

    doAssert classify(trunc(f_neg_one*f_zero)) == fcNegZero

    doAssert trunc(-1.1'f32) == -1
    doAssert trunc(1.1'f32) == 1
    doAssert trunc(-0.1'f32) == -0
    doAssert trunc(0.1'f32) == 0
    doAssert classify(trunc(1e1000000'f32)) == fcInf
    doAssert classify(trunc(-1e1000000'f32)) == fcNegInf
    when not defined(nimTmathCase2):
      doAssert classify(trunc(f_nan.float32)) == fcNan
    doAssert classify(trunc(0.0'f32)) == fcZero

  block: # divmod
    doAssert divmod(int.high, 1) == (int.high, 0)
    doAssert divmod(-1073741823, 17) == (-63161283, -12)
    doAssert divmod(int32.high, 1.int32) == (int32.high, 0.int32)
    doAssert divmod(1073741823.int32, 5.int32) == (214748364.int32, 3.int32)
    doAssert divmod(4611686018427387903.int64, 5.int64) == (922337203685477580.int64, 3.int64)
    when not defined(js) and (not compileOption("panics")) and compileOption("overflowChecks"):
      when nimvm:
        discard # cannot catch OverflowDefect here
      else:
        doAssertRaises(OverflowDefect, (discard divmod(cint.low, -1.cint)))
        doAssertRaises(OverflowDefect, (discard divmod(clong.low, -1.clong)))
        doAssertRaises(OverflowDefect, (discard divmod(clonglong.low, -1.clonglong)))
        doAssertRaises(DivByZeroDefect, (discard divmod(1, 0)))

  block: # log
    doAssert log(4.0, 3.0) ==~ ln(4.0) / ln(3.0)
    doAssert log2(8.0'f64) == 3.0'f64
    doAssert log2(4.0'f64) == 2.0'f64
    doAssert log2(2.0'f64) == 1.0'f64
    doAssert log2(1.0'f64) == 0.0'f64
    doAssert classify(log2(0.0'f64)) == fcNegInf

    doAssert log2(8.0'f32) == 3.0'f32
    doAssert log2(4.0'f32) == 2.0'f32
    doAssert log2(2.0'f32) == 1.0'f32
    doAssert log2(1.0'f32) == 0.0'f32
    doAssert classify(log2(0.0'f32)) == fcNegInf

  block: # cumsum
    block: # cumsum int seq return
      let counts = [1, 2, 3, 4]
      doAssert counts.cumsummed == @[1, 3, 6, 10]
      let empty: seq[int] = @[]
      doAssert empty.cumsummed == @[]

    block: # cumsum float seq return
      let counts = [1.0, 2.0, 3.0, 4.0]
      doAssert counts.cumsummed == @[1.0, 3.0, 6.0, 10.0]
      let empty: seq[float] = @[]
      doAssert empty.cumsummed == @[]

    block: # cumsum int in-place
      var counts = [1, 2, 3, 4]
      counts.cumsum
      doAssert counts == [1, 3, 6, 10]
      var empty: seq[int] = @[]
      empty.cumsum
      doAssert empty == @[]

    block: # cumsum float in-place
      var counts = [1.0, 2.0, 3.0, 4.0]
      counts.cumsum
      doAssert counts == [1.0, 3.0, 6.0, 10.0]
      var empty: seq[float] = @[]
      empty.cumsum
      doAssert empty == @[]

  block: # cumprod
    block: #cumprod int seq return
      let counts = [ 1, 2, 3, 4 ]
      doAssert counts.cumproded == [ 1, 2, 6, 24 ]

    block: # cumprod float seq return
      let counts = [ 1.0, 2.0, 3.0, 4.0 ]
      doAssert counts.cumproded == [ 1.0, 2.0, 6.0, 24.0 ]

    block: # cumprod int in-place
      var counts = [ 1, 2, 3, 4 ]
      counts.cumprod
      doAssert counts == [ 1, 2, 6, 24 ]

    block: # cumprod float in-place
      var counts = [ 1.0, 2.0, 3.0, 4.0 ]
      counts.cumprod
      doAssert counts == [ 1.0, 2.0, 6.0, 24.0 ]

  block: # ^ compiles for valid types
    doAssert: compiles(5 ^ 2)
    doAssert: compiles(5.5 ^ 2)
    doAssert: compiles(5.5 ^ 2.int8)
    doAssert: compiles(5.5 ^ 2.uint)
    doAssert: compiles(5.5 ^ 2.uint8)

  block:
    doAssert: compiles(5.5 ^ 2.2)
    when not defined(danger):
      doAssertRaises(AssertionDefect): discard (0.0 ^ -5.0)
      doAssertRaises(AssertionDefect): discard (-0.0 ^ -5.0)
      doAssertRaises(AssertionDefect): discard (-0.0 ^ -5.3)
      doAssertRaises(AssertionDefect): discard (-0.0 ^ -4.0)
      doAssertRaises(AssertionDefect): discard (-0.0 ^ -5.3)
      doAssertRaises(AssertionDefect): discard (-0.0 ^ -4.0)
      doAssertRaises(AssertionDefect): discard (-0.0 ^ -4.0)
      # Base finite, negative and exponent finite, non-integer returns NaN and raises Error
      doAssertRaises(AssertionDefect): discard (-5.5 ^ 2.2)
    doAssert: -1.0 ^ Inf == 1.0
    doAssert: -1.0 ^ -Inf == 1.0
    doAssert: 1.0 ^ Inf == 1.0
    doAssert: 1.0 ^ -Inf == 1.0
    doAssert: 1.0 ^ -5.4 == 1.0
    doAssert: 1.0 ^ 1.0 == 1.0

    # ^-Inf or ^Inf returns 0 or Inf depending on base absolute value relative to 1
    doAssert: 0.5 ^ -Inf == Inf
    doAssert: -0.5 ^ -Inf == Inf
    doAssert: 1.01 ^ -Inf == 0.0
    doAssert: -1.01 ^ -Inf == 0.0
    doAssert: 0.5 ^ Inf == 0.0
    doAssert: -0.5 ^ Inf == 0.0
    doAssert: 1.01 ^ Inf == Inf
    doAssert: -1.01 ^ Inf == Inf

    # -Inf base (the sign depends on the exponent parity)
    doAssert: -Inf ^ -5.0 == -0.0
    doAssert: -Inf ^ -4.0 == 0.0
    doAssert: -Inf ^ -5.1 == 0.0

    doAssert: -Inf ^ 3.0 == -Inf
    doAssert: -Inf ^ 3.1 == Inf
    doAssert: -Inf ^ 2.0 == Inf

    doAssert: Inf ^ -5.0 == 0.0
    doAssert: Inf ^ -5.1 == 0.0

    doAssert: Inf ^ 4.3 == Inf
    doAssert: Inf ^ 5.0 == Inf

    doAssert: -Inf ^ -Inf == 0.0
    doAssert: -Inf ^ Inf == Inf
    doAssert: Inf ^ -Inf == 0.0
    doAssert: Inf ^ Inf == Inf

  block:
    # doAssert: 1.0 ^ NaN == 1.0
    # doAssert: NaN ^ 0.0 == 1.0
    doAssert: (0.0 ^ NaN).isNaN
    doAssert: (NaN ^ 1.0).isNaN

  block: # isNaN
    doAssert NaN.isNaN
    doAssert not Inf.isNaN
    doAssert isNaN(Inf - Inf)
    doAssert not isNaN(0.0)
    doAssert not isNaN(3.1415926)
    doAssert not isNaN(0'f32)

  block: # signbit
    doAssert not signbit(0.0)
    doAssert signbit(-0.0)
    doAssert signbit(-0.1)
    doAssert not signbit(0.1)

    doAssert not signbit(Inf)
    doAssert signbit(-Inf)
    doAssert not signbit(NaN)

    let x1 = NaN
    let x2 = -NaN
    let x3 = -x1

    doAssert isNaN(x1)
    doAssert isNaN(x2)
    doAssert isNaN(x3)
    doAssert not signbit(x1)
    doAssert signbit(x2)
    doAssert signbit(x3)

  block: # copySign
    doAssert copySign(10.0, 1.0) == 10.0
    doAssert copySign(10.0, -1.0) == -10.0
    doAssert copySign(-10.0, -1.0) == -10.0
    doAssert copySign(-10.0, 1.0) == 10.0
    doAssert copySign(float(10), -1.0) == -10.0

    doAssert copySign(10.0'f64, 1.0) == 10.0
    doAssert copySign(10.0'f64, -1.0) == -10.0
    doAssert copySign(-10.0'f64, -1.0) == -10.0
    doAssert copySign(-10.0'f64, 1.0) == 10.0
    doAssert copySign(10'f64, -1.0) == -10.0

    doAssert copySign(10.0'f32, 1.0) == 10.0
    doAssert copySign(10.0'f32, -1.0) == -10.0
    doAssert copySign(-10.0'f32, -1.0) == -10.0
    doAssert copySign(-10.0'f32, 1.0) == 10.0
    doAssert copySign(10'f32, -1.0) == -10.0

    doAssert copySign(Inf, -1.0) == -Inf
    doAssert copySign(-Inf, 1.0) == Inf
    doAssert copySign(Inf, 1.0) == Inf
    doAssert copySign(-Inf, -1.0) == -Inf
    doAssert copySign(Inf, 0.0) == Inf
    doAssert copySign(Inf, -0.0) == -Inf
    doAssert copySign(-Inf, 0.0) == Inf
    doAssert copySign(-Inf, -0.0) == -Inf
    doAssert copySign(1.0, -0.0) == -1.0
    doAssert copySign(0.0, -0.0) == -0.0
    doAssert copySign(-1.0, 0.0) == 1.0
    doAssert copySign(10.0, 0.0) == 10.0
    doAssert copySign(-1.0, NaN) == 1.0
    doAssert copySign(10.0, NaN) == 10.0

    doAssert copySign(NaN, NaN).isNaN
    doAssert copySign(-NaN, NaN).isNaN
    doAssert copySign(NaN, -NaN).isNaN
    doAssert copySign(-NaN, -NaN).isNaN
    doAssert copySign(NaN, 0.0).isNaN
    doAssert copySign(NaN, -0.0).isNaN
    doAssert copySign(-NaN, 0.0).isNaN
    doAssert copySign(-NaN, -0.0).isNaN

    doAssert copySign(-1.0, NaN) == 1.0
    doAssert copySign(-1.0, -NaN) == -1.0
    doAssert copySign(1.0, copySign(NaN, -1.0)) == -1.0

  block: # almostEqual
    doAssert almostEqual(3.141592653589793, 3.1415926535897936)
    doAssert almostEqual(1.6777215e7'f32, 1.6777216e7'f32)
    doAssert almostEqual(Inf, Inf)
    doAssert almostEqual(-Inf, -Inf)
    doAssert not almostEqual(Inf, -Inf)
    doAssert not almostEqual(-Inf, Inf)
    doAssert not almostEqual(Inf, NaN)
    doAssert not almostEqual(NaN, NaN)

  block: # round
    block: # Round to 0 decimal places
      doAssert round(54.652) == 55.0
      doAssert round(54.352) == 54.0
      doAssert round(-54.652) == -55.0
      doAssert round(-54.352) == -54.0
      doAssert round(0.0) == 0.0
      doAssert 1 / round(0.0) == Inf
      doAssert 1 / round(-0.0) == -Inf
      doAssert round(Inf) == Inf
      doAssert round(-Inf) == -Inf
      doAssert round(NaN).isNaN
      doAssert round(-NaN).isNaN
      doAssert round(-0.5) == -1.0
      doAssert round(0.5) == 1.0
      doAssert round(-1.5) == -2.0
      doAssert round(1.5) == 2.0
      doAssert round(-2.5) == -3.0
      doAssert round(2.5) == 3.0
      doAssert round(2.5'f32) == 3.0'f32
      doAssert round(2.5'f64) == 3.0'f64

    block: # func round*[T: float32|float64](x: T, places: int): T
      doAssert round(54.345, 0) == 54.0
      template fn(x) =
        doAssert round(x, 2).almostEqual 54.35
        doAssert round(x, 2).almostEqual 54.35
        doAssert round(x, -1).almostEqual 50.0
        doAssert round(x, -2).almostEqual 100.0
        doAssert round(x, -3).almostEqual 0.0
      fn(54.346)
      fn(54.346'f32)

  block: # abs
    doAssert 1.0 / abs(-0.0) == Inf
    doAssert 1.0 / abs(0.0) == Inf
    doAssert -1.0 / abs(-0.0) == -Inf
    doAssert -1.0 / abs(0.0) == -Inf
    doAssert abs(0.0) == 0.0
    doAssert abs(0.0'f32) == 0.0'f32

    doAssert abs(Inf) == Inf
    doAssert abs(-Inf) == Inf
    doAssert abs(NaN).isNaN
    doAssert abs(-NaN).isNaN

  block: # classify
    doAssert classify(0.3) == fcNormal
    doAssert classify(-0.3) == fcNormal
    doAssert classify(5.0e-324) == fcSubnormal
    doAssert classify(-5.0e-324) == fcSubnormal
    doAssert classify(0.0) == fcZero
    doAssert classify(-0.0) == fcNegZero
    doAssert classify(NaN) == fcNan
    doAssert classify(0.3 / 0.0) == fcInf
    doAssert classify(Inf) == fcInf
    doAssert classify(-0.3 / 0.0) == fcNegInf
    doAssert classify(-Inf) == fcNegInf

  block: # sum
    let empty: seq[int] = @[]
    doAssert sum(empty) == 0
    doAssert sum([1, 2, 3, 4]) == 10
    doAssert sum([-4, 3, 5]) == 4

  block: # prod
    let empty: seq[int] = @[]
    doAssert prod(empty) == 1
    doAssert prod([1, 2, 3, 4]) == 24
    doAssert prod([-4, 3, 5]) == -60
    doAssert almostEqual(prod([1.5, 3.4]), 5.1)
    let x: seq[float] = @[]
    doAssert prod(x) == 1.0

  block: # clamp range
    doAssert clamp(10, 1..5) == 5
    doAssert clamp(3, 1..5) == 3
    doAssert clamp(5, 1..5) == 5
    doAssert clamp(42.0, 1.0 .. 3.1415926535) == 3.1415926535
    doAssert clamp(NaN, 1.0 .. 2.0).isNaN
    doAssert clamp(-Inf, -Inf .. -1.0) == -Inf
    type A = enum a0, a1, a2, a3, a4, a5
    doAssert a1.clamp(a2..a4) == a2
    doAssert clamp((3, 0), (1, 0) .. (2, 9)) == (2, 9)

  block: # edge cases
    doAssert sqrt(-4.0).isNaN

    doAssert ln(0.0) == -Inf
    doAssert ln(-0.0) == -Inf
    doAssert ln(-12.0).isNaN

    doAssert log10(0.0) == -Inf
    doAssert log10(-0.0) == -Inf
    doAssert log10(-12.0).isNaN

    doAssert log2(0.0) == -Inf
    doAssert log2(-0.0) == -Inf
    doAssert log2(-12.0).isNaN

    when nimvm: discard
    else:
      doAssert frexp(0.0) == (0.0, 0)
      doAssert frexp(-0.0) == (-0.0, 0)
      doAssert classify(frexp(-0.0)[0]) == fcNegZero

    when not defined(js):
      doAssert gamma(0.0) == Inf
      doAssert gamma(-0.0) == -Inf
      doAssert gamma(-1.0).isNaN

      doAssert lgamma(0.0) == Inf
      doAssert lgamma(-0.0) == Inf
      doAssert lgamma(-1.0) == Inf

static: main()
main()

when not defined(js) and not defined(danger):
  block: # bug #21792
    block:
      type Digit = 0..9
      var x = [Digit 4, 7]

      doAssertRaises(RangeDefect):
        discard sum(x)

    block:
      var x = [int8 124, 127]

      doAssertRaises(OverflowDefect):
        discard sum(x)

block: # bug #24673
  let x: Natural = 5
  let y: Natural = 3

  doAssert divmod(x, y) == (Natural 1, Natural 2)

#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## *Constructive mathematics is naturally typed.* -- Simon Thompson
##
## Basic math routines for Nim.
##
## Note that the trigonometric functions naturally operate on radians.
## The helper functions `degToRad <#degToRad,T>`_ and `radToDeg <#radToDeg,T>`_
## provide conversion between radians and degrees.

runnableExamples:
  from std/fenv import epsilon
  from std/random import rand

  proc generateGaussianNoise(mu: float = 0.0, sigma: float = 1.0): (float, float) =
    # Generates values from a normal distribution.
    # Translated from https://en.wikipedia.org/wiki/Box%E2%80%93Muller_transform#Implementation.
    var u1: float
    var u2: float
    while true:
      u1 = rand(1.0)
      u2 = rand(1.0)
      if u1 > epsilon(float): break
    let mag = sigma * sqrt(-2 * ln(u1))
    let z0 = mag * cos(2 * PI * u2) + mu
    let z1 = mag * sin(2 * PI * u2) + mu
    (z0, z1)

  echo generateGaussianNoise()

## This module is available for the `JavaScript target
## <backends.html#backends-the-javascript-target>`_.
##
## See also
## ========
## * `complex module <complex.html>`_ for complex numbers and their
##   mathematical operations
## * `rationals module <rationals.html>`_ for rational numbers and their
##   mathematical operations
## * `fenv module <fenv.html>`_ for handling of floating-point rounding
##   and exceptions (overflow, zero-divide, etc.)
## * `random module <random.html>`_ for a fast and tiny random number generator
## * `stats module <stats.html>`_ for statistical analysis
## * `strformat module <strformat.html>`_ for formatting floats for printing
## * `system module <system.html>`_ for some very basic and trivial math operators
##   (`shr`, `shl`, `xor`, `clamp`, etc.)


import std/private/since
{.push debugger: off.} # the user does not want to trace a part
                       # of the standard library!

import std/[bitops, fenv]
import system/countbits_impl

when defined(nimPreviewSlimSystem):
  import std/assertions


when not defined(js) and not defined(nimscript): # C
  proc c_isnan(x: float): bool {.importc: "isnan", header: "<math.h>".}
    # a generic like `x: SomeFloat` might work too if this is implemented via a C macro.

  proc c_copysign(x, y: cfloat): cfloat {.importc: "copysignf", header: "<math.h>".}
  proc c_copysign(x, y: cdouble): cdouble {.importc: "copysign", header: "<math.h>".}

  proc c_signbit(x: SomeFloat): cint {.importc: "signbit", header: "<math.h>".}

  # don't export `c_frexp` in the future and remove `c_frexp2`.
  func c_frexp2(x: cfloat, exponent: var cint): cfloat {.
      importc: "frexpf", header: "<math.h>".}
  func c_frexp2(x: cdouble, exponent: var cint): cdouble {.
      importc: "frexp", header: "<math.h>".}

  type
    div_t {.importc, header: "<stdlib.h>".} = object
      quot: cint
      rem: cint
    ldiv_t {.importc, header: "<stdlib.h>".} = object
      quot: clong
      rem: clong
    lldiv_t {.importc, header: "<stdlib.h>".} = object
      quot: clonglong
      rem: clonglong

  when cint isnot clong:
    func divmod_c(x, y: cint): div_t {.importc: "div", header: "<stdlib.h>".}
  when clong isnot clonglong:
    func divmod_c(x, y: clonglong): lldiv_t {.importc: "lldiv", header: "<stdlib.h>".}
  func divmod_c(x, y: clong): ldiv_t {.importc: "ldiv", header: "<stdlib.h>".}
  func divmod*[T: SomeInteger](x, y: T): (T, T) {.inline.} =
    ## Specialized instructions for computing both division and modulus.
    ## Return structure is: (quotient, remainder)
    runnableExamples:
      doAssert divmod(5, 2) == (2, 1)
      doAssert divmod(5, -3) == (-1, 2)
    when T is cint | clong | clonglong:
      when compileOption("overflowChecks"):
        if y == 0:
          raise new(DivByZeroDefect)
        elif (x == T.low and y == -1.T):
          raise new(OverflowDefect)
      let res = divmod_c(x, y)
      result[0] = res.quot
      result[1] = res.rem
    else:
      result[0] = x div y
      result[1] = x mod y

func binom*(n, k: int): int =
  ## Computes the [binomial coefficient](https://en.wikipedia.org/wiki/Binomial_coefficient).
  runnableExamples:
    doAssert binom(6, 2) == 15
    doAssert binom(-6, 2) == 1
    doAssert binom(6, 0) == 1

  if k <= 0: return 1
  if 2 * k > n: return binom(n, n - k)
  result = n
  for i in countup(2, k):
    result = (result * (n + 1 - i)) div i

func createFactTable[N: static[int]]: array[N, int] =
  result[0] = 1
  for i in 1 ..< N:
    result[i] = result[i - 1] * i

func fac*(n: int): int =
  ## Computes the [factorial](https://en.wikipedia.org/wiki/Factorial) of
  ## a non-negative integer `n`.
  ##
  ## **See also:**
  ## * `prod func <#prod,openArray[T]>`_
  runnableExamples:
    doAssert fac(0) == 1
    doAssert fac(4) == 24
    doAssert fac(10) == 3628800

  const factTable =
    when sizeof(int) == 2:
      createFactTable[5]()
    elif sizeof(int) == 4:
      createFactTable[13]()
    else:
      createFactTable[21]()
  assert(n >= 0, $n & " must not be negative.")
  assert(n < factTable.len, $n & " is too large to look up in the table")
  factTable[n]

{.push checks: off, line_dir: off, stack_trace: off.}

when defined(posix) and not defined(genode) and not defined(macosx):
  {.passl: "-lm".}

const
  PI* = 3.1415926535897932384626433          ## The circle constant PI (Ludolph's number).
  TAU* = 2.0 * PI                            ## The circle constant TAU (= 2 * PI).
  E* = 2.71828182845904523536028747          ## Euler's number.

  MaxFloat64Precision* = 16                  ## Maximum number of meaningful digits
                                             ## after the decimal point for Nim's
                                             ## `float64` type.
  MaxFloat32Precision* = 8                   ## Maximum number of meaningful digits
                                             ## after the decimal point for Nim's
                                             ## `float32` type.
  MaxFloatPrecision* = MaxFloat64Precision   ## Maximum number of
                                             ## meaningful digits
                                             ## after the decimal point
                                             ## for Nim's `float` type.
  MinFloatNormal* = 2.225073858507201e-308   ## Smallest normal number for Nim's
                                             ## `float` type (= 2^-1022).
  RadPerDeg = PI / 180.0                     ## Number of radians per degree.

type
  FloatClass* = enum ## Describes the class a floating point value belongs to.
                     ## This is the type that is returned by the
                     ## `classify func <#classify,float>`_.
    fcNormal,        ## value is an ordinary nonzero floating point value
    fcSubnormal,     ## value is a subnormal (a very small) floating point value
    fcZero,          ## value is zero
    fcNegZero,       ## value is the negative zero
    fcNan,           ## value is Not a Number (NaN)
    fcInf,           ## value is positive infinity
    fcNegInf         ## value is negative infinity

func isNaN*(x: SomeFloat): bool {.inline, since: (1,5,1).} =
  ## Returns whether `x` is a `NaN`, more efficiently than via `classify(x) == fcNan`.
  ## Works even with `--passc:-ffast-math`.
  runnableExamples:
    doAssert NaN.isNaN
    doAssert not Inf.isNaN
    doAssert not isNaN(3.1415926)

  template fn: untyped = result = x != x
  when nimvm: fn()
  else:
    when defined(js) or defined(nimscript): fn()
    else: result = c_isnan(x)

when defined(js):
  import std/private/jsutils

  proc toBitsImpl(x: float): array[2, uint32] =
    let buffer = newArrayBuffer(8)
    let a = newFloat64Array(buffer)
    let b = newUint32Array(buffer)
    a[0] = x
    {.emit: "`result` = `b`;".}
    # result = cast[array[2, uint32]](b)

  proc jsSetSign(x: float, sgn: bool): float =
    let buffer = newArrayBuffer(8)
    let a = newFloat64Array(buffer)
    let b = newUint32Array(buffer)
    a[0] = x
    {.emit: """
    function updateBit(num, bitPos, bitVal) {
      return (num & ~(1 << bitPos)) | (bitVal << bitPos);
    }
    `b`[1] = updateBit(`b`[1], 31, `sgn`);
    `result` = `a`[0];
    """.}

proc signbit*(x: SomeFloat): bool {.inline, since: (1, 5, 1).} =
  ## Returns true if `x` is negative, false otherwise.
  runnableExamples:
    doAssert not signbit(0.0)
    doAssert signbit(-0.0)
    doAssert signbit(-0.1)
    doAssert not signbit(0.1)

  when defined(js):
    let uintBuffer = toBitsImpl(x)
    result = (uintBuffer[1] shr 31) != 0
  else:
    result = c_signbit(x) != 0

func copySign*[T: SomeFloat](x, y: T): T {.inline, since: (1, 5, 1).} =
  ## Returns a value with the magnitude of `x` and the sign of `y`;
  ## this works even if x or y are NaN, infinity or zero, all of which can carry a sign.
  runnableExamples:
    doAssert copySign(10.0, 1.0) == 10.0
    doAssert copySign(10.0, -1.0) == -10.0
    doAssert copySign(-Inf, -0.0) == -Inf
    doAssert copySign(NaN, 1.0).isNaN
    doAssert copySign(1.0, copySign(NaN, -1.0)) == -1.0

  # TODO: use signbit for examples
  when defined(js):
    let uintBuffer = toBitsImpl(y)
    let sgn = (uintBuffer[1] shr 31) != 0
    result = jsSetSign(x, sgn)
  else:
    when nimvm: # not exact but we have a vmops for recent enough nim
      if y > 0.0 or (y == 0.0 and 1.0 / y > 0.0):
        result = abs(x)
      elif y <= 0.0:
        result = -abs(x)
      else: # must be NaN
        result = abs(x)
    else: result = c_copysign(x, y)

func classify*(x: float): FloatClass =
  ## Classifies a floating point value.
  ##
  ## Returns `x`'s class as specified by the `FloatClass enum<#FloatClass>`_.
  runnableExamples:
    doAssert classify(0.3) == fcNormal
    doAssert classify(0.0) == fcZero
    doAssert classify(0.3 / 0.0) == fcInf
    doAssert classify(-0.3 / 0.0) == fcNegInf
    doAssert classify(5.0e-324) == fcSubnormal

  # JavaScript and most C compilers have no classify:
  if isNan(x): return fcNan
  if x == 0.0:
    if 1.0 / x == Inf:
      return fcZero
    else:
      return fcNegZero
  if x * 0.5 == x:
    if x > 0.0: return fcInf
    else: return fcNegInf
  if abs(x) < MinFloatNormal:
    return fcSubnormal
  return fcNormal

func almostEqual*[T: SomeFloat](x, y: T; unitsInLastPlace: Natural = 4): bool {.
    since: (1, 5), inline.} =
  ## Checks if two float values are almost equal, using the
  ## [machine epsilon](https://en.wikipedia.org/wiki/Machine_epsilon).
  ##
  ## `unitsInLastPlace` is the max number of
  ## [units in the last place](https://en.wikipedia.org/wiki/Unit_in_the_last_place)
  ## difference tolerated when comparing two numbers. The larger the value, the
  ## more error is allowed. A `0` value means that two numbers must be exactly the
  ## same to be considered equal.
  ##
  ## The machine epsilon has to be scaled to the magnitude of the values used
  ## and multiplied by the desired precision in ULPs unless the difference is
  ## subnormal.
  ##
  # taken from: https://en.cppreference.com/w/cpp/types/numeric_limits/epsilon
  runnableExamples:
    doAssert almostEqual(PI, 3.14159265358979)
    doAssert almostEqual(Inf, Inf)
    doAssert not almostEqual(NaN, NaN)

  if x == y:
    # short circuit exact equality -- needed to catch two infinities of
    # the same sign. And perhaps speeds things up a bit sometimes.
    return true
  let diff = abs(x - y)
  result = diff <= epsilon(T) * abs(x + y) * T(unitsInLastPlace) or
      diff < minimumPositiveValue(T)

func isPowerOfTwo*(x: int): bool =
  ## Returns `true`, if `x` is a power of two, `false` otherwise.
  ##
  ## Zero and negative numbers are not a power of two.
  ##
  ## **See also:**
  ## * `nextPowerOfTwo func <#nextPowerOfTwo,int>`_
  runnableExamples:
    doAssert isPowerOfTwo(16)
    doAssert not isPowerOfTwo(5)
    doAssert not isPowerOfTwo(0)
    doAssert not isPowerOfTwo(-16)

  return (x > 0) and ((x and (x - 1)) == 0)

func nextPowerOfTwo*(x: int): int =
  ## Returns `x` rounded up to the nearest power of two.
  ##
  ## Zero and negative numbers get rounded up to 1.
  ##
  ## **See also:**
  ## * `isPowerOfTwo func <#isPowerOfTwo,int>`_
  runnableExamples:
    doAssert nextPowerOfTwo(16) == 16
    doAssert nextPowerOfTwo(5) == 8
    doAssert nextPowerOfTwo(0) == 1
    doAssert nextPowerOfTwo(-16) == 1

  result = x - 1
  when defined(cpu64):
    result = result or (result shr 32)
  when sizeof(int) > 2:
    result = result or (result shr 16)
  when sizeof(int) > 1:
    result = result or (result shr 8)
  result = result or (result shr 4)
  result = result or (result shr 2)
  result = result or (result shr 1)
  result += 1 + ord(x <= 0)




when not defined(js): # C
  func sqrt*(x: float32): float32 {.importc: "sqrtf", header: "<math.h>".}
  func sqrt*(x: float64): float64 {.importc: "sqrt", header: "<math.h>".} =
    ## Computes the square root of `x`.
    ##
    ## **See also:**
    ## * `cbrt func <#cbrt,float64>`_ for the cube root
    runnableExamples:
      doAssert almostEqual(sqrt(4.0), 2.0)
      doAssert almostEqual(sqrt(1.44), 1.2)
  func cbrt*(x: float32): float32 {.importc: "cbrtf", header: "<math.h>".}
  func cbrt*(x: float64): float64 {.importc: "cbrt", header: "<math.h>".} =
    ## Computes the cube root of `x`.
    ##
    ## **See also:**
    ## * `sqrt func <#sqrt,float64>`_ for the square root
    runnableExamples:
      doAssert almostEqual(cbrt(8.0), 2.0)
      doAssert almostEqual(cbrt(2.197), 1.3)
      doAssert almostEqual(cbrt(-27.0), -3.0)
  func ln*(x: float32): float32 {.importc: "logf", header: "<math.h>".}
  func ln*(x: float64): float64 {.importc: "log", header: "<math.h>".} =
    ## Computes the [natural logarithm](https://en.wikipedia.org/wiki/Natural_logarithm)
    ## of `x`.
    ##
    ## **See also:**
    ## * `log func <#log,T,T>`_
    ## * `log10 func <#log10,float64>`_
    ## * `log2 func <#log2,float64>`_
    ## * `exp func <#exp,float64>`_
    runnableExamples:
      doAssert almostEqual(ln(exp(4.0)), 4.0)
      doAssert almostEqual(ln(1.0), 0.0)
      doAssert almostEqual(ln(0.0), -Inf)
      doAssert ln(-7.0).isNaN
else: # JS
  func sqrt*(x: float32): float32 {.importc: "Math.sqrt", nodecl.}
  func sqrt*(x: float64): float64 {.importc: "Math.sqrt", nodecl.}

  func cbrt*(x: float32): float32 {.importc: "Math.cbrt", nodecl.}
  func cbrt*(x: float64): float64 {.importc: "Math.cbrt", nodecl.}

  func ln*(x: float32): float32 {.importc: "Math.log", nodecl.}
  func ln*(x: float64): float64 {.importc: "Math.log", nodecl.}

func log*[T: SomeFloat](x, base: T): T =
  ## Computes the logarithm of `x` to base `base`.
  ##
  ## **See also:**
  ## * `ln func <#ln,float64>`_
  ## * `log10 func <#log10,float64>`_
  ## * `log2 func <#log2,float64>`_
  runnableExamples:
    doAssert almostEqual(log(9.0, 3.0), 2.0)
    doAssert almostEqual(log(0.0, 2.0), -Inf)
    doAssert log(-7.0, 4.0).isNaN
    doAssert log(8.0, -2.0).isNaN

  ln(x) / ln(base)

when not defined(js): # C
  func log10*(x: float32): float32 {.importc: "log10f", header: "<math.h>".}
  func log10*(x: float64): float64 {.importc: "log10", header: "<math.h>".} =
    ## Computes the common logarithm (base 10) of `x`.
    ##
    ## **See also:**
    ## * `ln func <#ln,float64>`_
    ## * `log func <#log,T,T>`_
    ## * `log2 func <#log2,float64>`_
    runnableExamples:
      doAssert almostEqual(log10(100.0) , 2.0)
      doAssert almostEqual(log10(0.0), -Inf)
      doAssert log10(-100.0).isNaN
  func exp*(x: float32): float32 {.importc: "expf", header: "<math.h>".}
  func exp*(x: float64): float64 {.importc: "exp", header: "<math.h>".} =
    ## Computes the exponential function of `x` (`e^x`).
    ##
    ## **See also:**
    ## * `ln func <#ln,float64>`_
    runnableExamples:
      doAssert almostEqual(exp(1.0), E)
      doAssert almostEqual(ln(exp(4.0)), 4.0)
      doAssert almostEqual(exp(0.0), 1.0)
  func sin*(x: float32): float32 {.importc: "sinf", header: "<math.h>".}
  func sin*(x: float64): float64 {.importc: "sin", header: "<math.h>".} =
    ## Computes the sine of `x`.
    ##
    ## **See also:**
    ## * `arcsin func <#arcsin,float64>`_
    runnableExamples:
      doAssert almostEqual(sin(PI / 6), 0.5)
      doAssert almostEqual(sin(degToRad(90.0)), 1.0)
  func cos*(x: float32): float32 {.importc: "cosf", header: "<math.h>".}
  func cos*(x: float64): float64 {.importc: "cos", header: "<math.h>".} =
    ## Computes the cosine of `x`.
    ##
    ## **See also:**
    ## * `arccos func <#arccos,float64>`_
    runnableExamples:
      doAssert almostEqual(cos(2 * PI), 1.0)
      doAssert almostEqual(cos(degToRad(60.0)), 0.5)
  func tan*(x: float32): float32 {.importc: "tanf", header: "<math.h>".}
  func tan*(x: float64): float64 {.importc: "tan", header: "<math.h>".} =
    ## Computes the tangent of `x`.
    ##
    ## **See also:**
    ## * `arctan func <#arctan,float64>`_
    runnableExamples:
      doAssert almostEqual(tan(degToRad(45.0)), 1.0)
      doAssert almostEqual(tan(PI / 4), 1.0)
  func sinh*(x: float32): float32 {.importc: "sinhf", header: "<math.h>".}
  func sinh*(x: float64): float64 {.importc: "sinh", header: "<math.h>".} =
    ## Computes the [hyperbolic sine](https://en.wikipedia.org/wiki/Hyperbolic_function#Definitions) of `x`.
    ##
    ## **See also:**
    ## * `arcsinh func <#arcsinh,float64>`_
    runnableExamples:
      doAssert almostEqual(sinh(0.0), 0.0)
      doAssert almostEqual(sinh(1.0), 1.175201193643801)
  func cosh*(x: float32): float32 {.importc: "coshf", header: "<math.h>".}
  func cosh*(x: float64): float64 {.importc: "cosh", header: "<math.h>".} =
    ## Computes the [hyperbolic cosine](https://en.wikipedia.org/wiki/Hyperbolic_function#Definitions) of `x`.
    ##
    ## **See also:**
    ## * `arccosh func <#arccosh,float64>`_
    runnableExamples:
      doAssert almostEqual(cosh(0.0), 1.0)
      doAssert almostEqual(cosh(1.0), 1.543080634815244)
  func tanh*(x: float32): float32 {.importc: "tanhf", header: "<math.h>".}
  func tanh*(x: float64): float64 {.importc: "tanh", header: "<math.h>".} =
    ## Computes the [hyperbolic tangent](https://en.wikipedia.org/wiki/Hyperbolic_function#Definitions) of `x`.
    ##
    ## **See also:**
    ## * `arctanh func <#arctanh,float64>`_
    runnableExamples:
      doAssert almostEqual(tanh(0.0), 0.0)
      doAssert almostEqual(tanh(1.0), 0.7615941559557649)
  func arcsin*(x: float32): float32 {.importc: "asinf", header: "<math.h>".}
  func arcsin*(x: float64): float64 {.importc: "asin", header: "<math.h>".} =
    ## Computes the arc sine of `x`.
    ##
    ## **See also:**
    ## * `sin func <#sin,float64>`_
    runnableExamples:
      doAssert almostEqual(radToDeg(arcsin(0.0)), 0.0)
      doAssert almostEqual(radToDeg(arcsin(1.0)), 90.0)
  func arccos*(x: float32): float32 {.importc: "acosf", header: "<math.h>".}
  func arccos*(x: float64): float64 {.importc: "acos", header: "<math.h>".} =
    ## Computes the arc cosine of `x`.
    ##
    ## **See also:**
    ## * `cos func <#cos,float64>`_
    runnableExamples:
      doAssert almostEqual(radToDeg(arccos(0.0)), 90.0)
      doAssert almostEqual(radToDeg(arccos(1.0)), 0.0)
  func arctan*(x: float32): float32 {.importc: "atanf", header: "<math.h>".}
  func arctan*(x: float64): float64 {.importc: "atan", header: "<math.h>".} =
    ## Calculate the arc tangent of `x`.
    ##
    ## **See also:**
    ## * `arctan2 func <#arctan2,float64,float64>`_
    ## * `tan func <#tan,float64>`_
    runnableExamples:
      doAssert almostEqual(arctan(1.0), 0.7853981633974483)
      doAssert almostEqual(radToDeg(arctan(1.0)), 45.0)
  func arctan2*(y, x: float32): float32 {.importc: "atan2f", header: "<math.h>".}
  func arctan2*(y, x: float64): float64 {.importc: "atan2", header: "<math.h>".} =
    ## Calculate the arc tangent of `y/x`.
    ##
    ## It produces correct results even when the resulting angle is near
    ## `PI/2` or `-PI/2` (`x` near 0).
    ##
    ## **See also:**
    ## * `arctan func <#arctan,float64>`_
    runnableExamples:
      doAssert almostEqual(arctan2(1.0, 0.0), PI / 2.0)
      doAssert almostEqual(radToDeg(arctan2(1.0, 0.0)), 90.0)
  func arcsinh*(x: float32): float32 {.importc: "asinhf", header: "<math.h>".}
  func arcsinh*(x: float64): float64 {.importc: "asinh", header: "<math.h>".}
    ## Computes the inverse hyperbolic sine of `x`.
    ##
    ## **See also:**
    ## * `sinh func <#sinh,float64>`_
  func arccosh*(x: float32): float32 {.importc: "acoshf", header: "<math.h>".}
  func arccosh*(x: float64): float64 {.importc: "acosh", header: "<math.h>".}
    ## Computes the inverse hyperbolic cosine of `x`.
    ##
    ## **See also:**
    ## * `cosh func <#cosh,float64>`_
  func arctanh*(x: float32): float32 {.importc: "atanhf", header: "<math.h>".}
  func arctanh*(x: float64): float64 {.importc: "atanh", header: "<math.h>".}
    ## Computes the inverse hyperbolic tangent of `x`.
    ##
    ## **See also:**
    ## * `tanh func <#tanh,float64>`_

else: # JS
  func log10*(x: float32): float32 {.importc: "Math.log10", nodecl.}
  func log10*(x: float64): float64 {.importc: "Math.log10", nodecl.}
  func log2*(x: float32): float32 {.importc: "Math.log2", nodecl.}
  func log2*(x: float64): float64 {.importc: "Math.log2", nodecl.}
  func exp*(x: float32): float32 {.importc: "Math.exp", nodecl.}
  func exp*(x: float64): float64 {.importc: "Math.exp", nodecl.}

  func sin*[T: float32|float64](x: T): T {.importc: "Math.sin", nodecl.}
  func cos*[T: float32|float64](x: T): T {.importc: "Math.cos", nodecl.}
  func tan*[T: float32|float64](x: T): T {.importc: "Math.tan", nodecl.}

  func sinh*[T: float32|float64](x: T): T {.importc: "Math.sinh", nodecl.}
  func cosh*[T: float32|float64](x: T): T {.importc: "Math.cosh", nodecl.}
  func tanh*[T: float32|float64](x: T): T {.importc: "Math.tanh", nodecl.}

  func arcsin*[T: float32|float64](x: T): T {.importc: "Math.asin", nodecl.}
    # keep this as generic or update test in `tvmops.nim` to make sure we
    # keep testing that generic importc procs work
  func arccos*[T: float32|float64](x: T): T {.importc: "Math.acos", nodecl.}
  func arctan*[T: float32|float64](x: T): T {.importc: "Math.atan", nodecl.}
  func arctan2*[T: float32|float64](y, x: T): T {.importc: "Math.atan2", nodecl.}

  func arcsinh*[T: float32|float64](x: T): T {.importc: "Math.asinh", nodecl.}
  func arccosh*[T: float32|float64](x: T): T {.importc: "Math.acosh", nodecl.}
  func arctanh*[T: float32|float64](x: T): T {.importc: "Math.atanh", nodecl.}

func cot*[T: float32|float64](x: T): T = 1.0 / tan(x)
  ## Computes the cotangent of `x` (`1/tan(x)`).
func sec*[T: float32|float64](x: T): T = 1.0 / cos(x)
  ## Computes the secant of `x` (`1/cos(x)`).
func csc*[T: float32|float64](x: T): T = 1.0 / sin(x)
  ## Computes the cosecant of `x` (`1/sin(x)`).

func coth*[T: float32|float64](x: T): T = 1.0 / tanh(x)
  ## Computes the hyperbolic cotangent of `x` (`1/tanh(x)`).
func sech*[T: float32|float64](x: T): T = 1.0 / cosh(x)
  ## Computes the hyperbolic secant of `x` (`1/cosh(x)`).
func csch*[T: float32|float64](x: T): T = 1.0 / sinh(x)
  ## Computes the hyperbolic cosecant of `x` (`1/sinh(x)`).

func arccot*[T: float32|float64](x: T): T = arctan(1.0 / x)
  ## Computes the inverse cotangent of `x` (`arctan(1/x)`).
func arcsec*[T: float32|float64](x: T): T = arccos(1.0 / x)
  ## Computes the inverse secant of `x` (`arccos(1/x)`).
func arccsc*[T: float32|float64](x: T): T = arcsin(1.0 / x)
  ## Computes the inverse cosecant of `x` (`arcsin(1/x)`).

func arccoth*[T: float32|float64](x: T): T = arctanh(1.0 / x)
  ## Computes the inverse hyperbolic cotangent of `x` (`arctanh(1/x)`).
func arcsech*[T: float32|float64](x: T): T = arccosh(1.0 / x)
  ## Computes the inverse hyperbolic secant of `x` (`arccosh(1/x)`).
func arccsch*[T: float32|float64](x: T): T = arcsinh(1.0 / x)
  ## Computes the inverse hyperbolic cosecant of `x` (`arcsinh(1/x)`).

const windowsCC89 = defined(windows) and defined(bcc)

when not defined(js): # C
  func hypot*(x, y: float32): float32 {.importc: "hypotf", header: "<math.h>".}
  func hypot*(x, y: float64): float64 {.importc: "hypot", header: "<math.h>".} =
    ## Computes the length of the hypotenuse of a right-angle triangle with
    ## `x` as its base and `y` as its height. Equivalent to `sqrt(x*x + y*y)`.
    runnableExamples:
      doAssert almostEqual(hypot(3.0, 4.0), 5.0)
  func pow*(x, y: float32): float32 {.importc: "powf", header: "<math.h>".}
  func pow*(x, y: float64): float64 {.importc: "pow", header: "<math.h>".} =
    ## Computes `x` raised to the power of `y`.
    ##
    ## You may use the `^ func <#^, T, U>`_ instead.
    ##
    ## **See also:**
    ## * `^ (SomeNumber, Natural) func <#^,T,Natural>`_
    ## * `^ (SomeNumber, SomeFloat) func <#^,T,U>`_
    ## * `sqrt func <#sqrt,float64>`_
    ## * `cbrt func <#cbrt,float64>`_
    runnableExamples:
      doAssert almostEqual(pow(100, 1.5), 1000.0)
      doAssert almostEqual(pow(16.0, 0.5), 4.0)

  # TODO: add C89 version on windows
  when not windowsCC89:
    func erf*(x: float32): float32 {.importc: "erff", header: "<math.h>".}
    func erf*(x: float64): float64 {.importc: "erf", header: "<math.h>".}
      ## Computes the [error function](https://en.wikipedia.org/wiki/Error_function) for `x`.
      ##
      ## **Note:** Not available for the JS backend.
    func erfc*(x: float32): float32 {.importc: "erfcf", header: "<math.h>".}
    func erfc*(x: float64): float64 {.importc: "erfc", header: "<math.h>".}
      ## Computes the [complementary error function](https://en.wikipedia.org/wiki/Error_function#Complementary_error_function) for `x`.
      ##
      ## **Note:** Not available for the JS backend.
    func gamma*(x: float32): float32 {.importc: "tgammaf", header: "<math.h>".}
    func gamma*(x: float64): float64 {.importc: "tgamma", header: "<math.h>".} =
      ## Computes the [gamma function](https://en.wikipedia.org/wiki/Gamma_function) for `x`.
      ##
      ## **Note:** Not available for the JS backend.
      ##
      ## **See also:**
      ## * `lgamma func <#lgamma,float64>`_ for the natural logarithm of the gamma function
      runnableExamples:
        doAssert almostEqual(gamma(1.0), 1.0)
        doAssert almostEqual(gamma(4.0), 6.0)
        doAssert almostEqual(gamma(11.0), 3628800.0)
    func lgamma*(x: float32): float32 {.importc: "lgammaf", header: "<math.h>".}
    func lgamma*(x: float64): float64 {.importc: "lgamma", header: "<math.h>".} =
      ## Computes the natural logarithm of the gamma function for `x`.
      ##
      ## **Note:** Not available for the JS backend.
      ##
      ## **See also:**
      ## * `gamma func <#gamma,float64>`_ for gamma function

  func floor*(x: float32): float32 {.importc: "floorf", header: "<math.h>".}
  func floor*(x: float64): float64 {.importc: "floor", header: "<math.h>".} =
    ## Computes the floor function (i.e. the largest integer not greater than `x`).
    ##
    ## **See also:**
    ## * `ceil func <#ceil,float64>`_
    ## * `round func <#round,float64>`_
    ## * `trunc func <#trunc,float64>`_
    runnableExamples:
      doAssert floor(2.1)  == 2.0
      doAssert floor(2.9)  == 2.0
      doAssert floor(-3.5) == -4.0

  func ceil*(x: float32): float32 {.importc: "ceilf", header: "<math.h>".}
  func ceil*(x: float64): float64 {.importc: "ceil", header: "<math.h>".} =
    ## Computes the ceiling function (i.e. the smallest integer not smaller
    ## than `x`).
    ##
    ## **See also:**
    ## * `floor func <#floor,float64>`_
    ## * `round func <#round,float64>`_
    ## * `trunc func <#trunc,float64>`_
    runnableExamples:
      doAssert ceil(2.1)  == 3.0
      doAssert ceil(2.9)  == 3.0
      doAssert ceil(-2.1) == -2.0

  when windowsCC89:
    # MSVC 2010 don't have trunc/truncf
    # this implementation was inspired by Go-lang Math.Trunc
    func truncImpl(f: float64): float64 =
      const
        mask: uint64 = 0x7FF
        shift: uint64 = 64 - 12
        bias: uint64 = 0x3FF

      if f < 1:
        if f < 0: return -truncImpl(-f)
        elif f == 0: return f # Return -0 when f == -0
        else: return 0

      var x = cast[uint64](f)
      let e = (x shr shift) and mask - bias

      # Keep the top 12+e bits, the integer part; clear the rest.
      if e < 64 - 12:
        x = x and (not (1'u64 shl (64'u64 - 12'u64 - e) - 1'u64))

      result = cast[float64](x)

    func truncImpl(f: float32): float32 =
      const
        mask: uint32 = 0xFF
        shift: uint32 = 32 - 9
        bias: uint32 = 0x7F

      if f < 1:
        if f < 0: return -truncImpl(-f)
        elif f == 0: return f # Return -0 when f == -0
        else: return 0

      var x = cast[uint32](f)
      let e = (x shr shift) and mask - bias

      # Keep the top 9+e bits, the integer part; clear the rest.
      if e < 32 - 9:
        x = x and (not (1'u32 shl (32'u32 - 9'u32 - e) - 1'u32))

      result = cast[float32](x)

    func trunc*(x: float64): float64 =
      if classify(x) in {fcZero, fcNegZero, fcNan, fcInf, fcNegInf}: return x
      result = truncImpl(x)

    func trunc*(x: float32): float32 =
      if classify(x) in {fcZero, fcNegZero, fcNan, fcInf, fcNegInf}: return x
      result = truncImpl(x)

    func round*[T: float32|float64](x: T): T =
      ## Windows compilers prior to MSVC 2012 do not implement 'round',
      ## 'roundl' or 'roundf'.
      result = if x < 0.0: ceil(x - T(0.5)) else: floor(x + T(0.5))
  else:
    func round*(x: float32): float32 {.importc: "roundf", header: "<math.h>".}
    func round*(x: float64): float64 {.importc: "round", header: "<math.h>".} =
      ## Rounds a float to zero decimal places.
      ##
      ## Used internally by the `round func <#round,T,int>`_
      ## when the specified number of places is 0.
      ##
      ## **See also:**
      ## * `round func <#round,T,int>`_ for rounding to the specific
      ##   number of decimal places
      ## * `floor func <#floor,float64>`_
      ## * `ceil func <#ceil,float64>`_
      ## * `trunc func <#trunc,float64>`_
      runnableExamples:
        doAssert round(3.4) == 3.0
        doAssert round(3.5) == 4.0
        doAssert round(4.5) == 5.0

    func trunc*(x: float32): float32 {.importc: "truncf", header: "<math.h>".}
    func trunc*(x: float64): float64 {.importc: "trunc", header: "<math.h>".} =
      ## Truncates `x` to the decimal point.
      ##
      ## **See also:**
      ## * `floor func <#floor,float64>`_
      ## * `ceil func <#ceil,float64>`_
      ## * `round func <#round,float64>`_
      runnableExamples:
        doAssert trunc(PI) == 3.0
        doAssert trunc(-1.85) == -1.0

  func `mod`*(x, y: float32): float32 {.importc: "fmodf", header: "<math.h>".}
  func `mod`*(x, y: float64): float64 {.importc: "fmod", header: "<math.h>".} =
    ## Computes the modulo operation for float values (the remainder of `x` divided by `y`).
    ##
    ## **See also:**
    ## * `floorMod func <#floorMod,T,T>`_ for Python-like (`%` operator) behavior
    runnableExamples:
      doAssert  6.5 mod  2.5 ==  1.5
      doAssert -6.5 mod  2.5 == -1.5
      doAssert  6.5 mod -2.5 ==  1.5
      doAssert -6.5 mod -2.5 == -1.5

else: # JS
  func hypot*(x, y: float32): float32 {.importc: "Math.hypot", varargs, nodecl.}
  func hypot*(x, y: float64): float64 {.importc: "Math.hypot", varargs, nodecl.}
  func pow*(x, y: float32): float32 {.importc: "Math.pow", nodecl.}
  func pow*(x, y: float64): float64 {.importc: "Math.pow", nodecl.}
  func floor*(x: float32): float32 {.importc: "Math.floor", nodecl.}
  func floor*(x: float64): float64 {.importc: "Math.floor", nodecl.}
  func ceil*(x: float32): float32 {.importc: "Math.ceil", nodecl.}
  func ceil*(x: float64): float64 {.importc: "Math.ceil", nodecl.}

  when (NimMajor, NimMinor) < (1, 5) or defined(nimLegacyJsRound):
    func round*(x: float): float {.importc: "Math.round", nodecl.}
  else:
    func jsRound(x: float): float {.importc: "Math.round", nodecl.}
    func round*[T: float64 | float32](x: T): T =
      if x >= 0: result = jsRound(x)
      else:
        result = ceil(x)
        if result - x >= T(0.5):
          result -= T(1.0)
  func trunc*(x: float32): float32 {.importc: "Math.trunc", nodecl.}
  func trunc*(x: float64): float64 {.importc: "Math.trunc", nodecl.}

  func `mod`*(x, y: float32): float32 {.importjs: "(# % #)".}
  func `mod`*(x, y: float64): float64 {.importjs: "(# % #)".} =
    ## Computes the modulo operation for float values (the remainder of `x` divided by `y`).
    runnableExamples:
      doAssert  6.5 mod  2.5 ==  1.5
      doAssert -6.5 mod  2.5 == -1.5
      doAssert  6.5 mod -2.5 ==  1.5
      doAssert -6.5 mod -2.5 == -1.5

  func divmod*[T:SomeInteger](num, denom: T): (T, T) =
    runnableExamples:
      doAssert  divmod(5, 2) ==  (2, 1)
      doAssert divmod(5, -3) == (-1, 2)
    result[0] = num div denom
    result[1] = num mod denom


func round*[T: float32|float64](x: T, places: int): T =
  ## Decimal rounding on a binary floating point number.
  ##
  ## This function is NOT reliable. Floating point numbers cannot hold
  ## non integer decimals precisely. If `places` is 0 (or omitted),
  ## round to the nearest integral value following normal mathematical
  ## rounding rules (e.g.  `round(54.5) -> 55.0`). If `places` is
  ## greater than 0, round to the given number of decimal places,
  ## e.g. `round(54.346, 2) -> 54.350000000000001421…`. If `places` is negative, round
  ## to the left of the decimal place, e.g. `round(537.345, -1) -> 540.0`.
  runnableExamples:
    doAssert round(PI, 2) == 3.14
    doAssert round(PI, 4) == 3.1416

  if places == 0:
    result = round(x)
  else:
    var mult = pow(10.0, T(places))
    result = round(x * mult) / mult

func floorDiv*[T: SomeInteger](x, y: T): T =
  ## Floor division is conceptually defined as `floor(x / y)`.
  ##
  ## This is different from the `system.div <system.html#div,int,int>`_
  ## operator, which is defined as `trunc(x / y)`.
  ## That is, `div` rounds towards `0` and `floorDiv` rounds down.
  ##
  ## **See also:**
  ## * `system.div proc <system.html#div,int,int>`_ for integer division
  ## * `floorMod func <#floorMod,T,T>`_ for Python-like (`%` operator) behavior
  runnableExamples:
    doAssert floorDiv( 13,  3) ==  4
    doAssert floorDiv(-13,  3) == -5
    doAssert floorDiv( 13, -3) == -5
    doAssert floorDiv(-13, -3) ==  4

  result = x div y
  let r = x mod y
  if (r > 0 and y < 0) or (r < 0 and y > 0): result.dec 1

func floorMod*[T: SomeNumber](x, y: T): T =
  ## Floor modulo is conceptually defined as `x - (floorDiv(x, y) * y)`.
  ##
  ## This func behaves the same as the `%` operator in Python.
  ##
  ## **See also:**
  ## * `mod func <#mod,float64,float64>`_
  ## * `floorDiv func <#floorDiv,T,T>`_
  runnableExamples:
    doAssert floorMod( 13,  3) ==  1
    doAssert floorMod(-13,  3) ==  2
    doAssert floorMod( 13, -3) == -2
    doAssert floorMod(-13, -3) == -1

  result = x mod y
  if (result > 0 and y < 0) or (result < 0 and y > 0): result += y

func euclDiv*[T: SomeInteger](x, y: T): T {.since: (1, 5, 1).} =
  ## Returns euclidean division of `x` by `y`.
  runnableExamples:
    doAssert euclDiv(13, 3) == 4
    doAssert euclDiv(-13, 3) == -5
    doAssert euclDiv(13, -3) == -4
    doAssert euclDiv(-13, -3) == 5

  result = x div y
  if x mod y < 0:
    if y > 0:
      dec result
    else:
      inc result

func euclMod*[T: SomeNumber](x, y: T): T {.since: (1, 5, 1).} =
  ## Returns euclidean modulo of `x` by `y`.
  ## `euclMod(x, y)` is non-negative.
  runnableExamples:
    doAssert euclMod(13, 3) == 1
    doAssert euclMod(-13, 3) == 2
    doAssert euclMod(13, -3) == 1
    doAssert euclMod(-13, -3) == 2

  result = x mod y
  if result < 0:
    result += abs(y)

func ceilDiv*[T: SomeInteger](x, y: T): T {.inline, since: (1, 5, 1).} =
  ## Ceil division is conceptually defined as `ceil(x / y)`.
  ##
  ## Assumes `x >= 0` and `y > 0` (and `x + y - 1 <= high(T)` if T is SomeUnsignedInt).
  ##
  ## This is different from the `system.div <system.html#div,int,int>`_
  ## operator, which works like `trunc(x / y)`.
  ## That is, `div` rounds towards `0` and `ceilDiv` rounds up.
  ##
  ## This function has the above input limitation, because that allows the
  ## compiler to generate faster code and it is rarely used with
  ## negative values or unsigned integers close to `high(T)/2`.
  ## If you need a `ceilDiv` that works with any input, see:
  ## https://github.com/demotomohiro/divmath.
  ##
  ## **See also:**
  ## * `system.div proc <system.html#div,int,int>`_ for integer division
  ## * `floorDiv func <#floorDiv,T,T>`_ for integer division which rounds down.
  runnableExamples:
    assert ceilDiv(12, 3) ==  4
    assert ceilDiv(13, 3) ==  5

  when sizeof(T) == 8:
    type UT = uint64
  elif sizeof(T) == 4:
    type UT = uint32
  elif sizeof(T) == 2:
    type UT = uint16
  elif sizeof(T) == 1:
    type UT = uint8
  else:
    {.fatal: "Unsupported int type".}

  assert x >= 0 and y > 0
  when T is SomeUnsignedInt:
    assert x + y - 1 >= x

  # If the divisor is const, the backend C/C++ compiler generates code without a `div`
  # instruction, as it is slow on most CPUs.
  # If the divisor is a power of 2 and a const unsigned integer type, the
  # compiler generates faster code.
  # If the divisor is const and a signed integer, generated code becomes slower
  # than the code with unsigned integers, because division with signed integers
  # need to works for both positive and negative value without `idiv`/`sdiv`.
  # That is why this code convert parameters to unsigned.
  # This post contains a comparison of the performance of signed/unsigned integers:
  # https://github.com/nim-lang/Nim/pull/18596#issuecomment-894420984.
  # If signed integer arguments were not converted to unsigned integers,
  # `ceilDiv` wouldn't work for any positive signed integer value, because
  # `x + (y - 1)` can overflow.
  ((x.UT + (y.UT - 1.UT)) div y.UT).T

func frexp*[T: float32|float64](x: T): tuple[frac: T, exp: int] {.inline.} =
  ## Splits `x` into a normalized fraction `frac` and an integral power of 2 `exp`,
  ## such that `abs(frac) in 0.5..<1` and `x == frac * 2 ^ exp`, except for special
  ## cases shown below.
  runnableExamples:
    doAssert frexp(8.0) == (0.5, 4)
    doAssert frexp(-8.0) == (-0.5, 4)
    doAssert frexp(0.0) == (0.0, 0)

    # special cases:
    when sizeof(int) == 8:
      doAssert frexp(-0.0).frac.signbit # signbit preserved for +-0
      doAssert frexp(Inf).frac == Inf # +- Inf preserved
      doAssert frexp(NaN).frac.isNaN

  result = default(tuple[frac: T, exp: int])
  when not defined(js):
    var exp: cint = cint(0)
    result.frac = c_frexp2(x, exp)
    result.exp = exp
  else:
    if x == 0.0:
      # reuse signbit implementation
      let uintBuffer = toBitsImpl(x)
      if (uintBuffer[1] shr 31) != 0:
        # x is -0.0
        result = (-0.0, 0)
      else:
        result = (0.0, 0)
    elif x < 0.0:
      result = frexp(-x)
      result.frac = -result.frac
    else:
      var ex = trunc(log2(x))
      result.exp = int(ex)
      result.frac = x / pow(2.0, ex)
      if abs(result.frac) >= 1:
        inc(result.exp)
        result.frac = result.frac / 2
      if result.exp == 1024 and result.frac == 0.0:
        result.frac = 0.99999999999999988898

func frexp*[T: float32|float64](x: T, exponent: var int): T {.inline.} =
  ## Overload of `frexp` that calls `(result, exponent) = frexp(x)`.
  runnableExamples:
    var x: int
    doAssert frexp(5.0, x) == 0.625
    doAssert x == 3

  (result, exponent) = frexp(x)


when not defined(js):
  when windowsCC89:
    # taken from Go-lang Math.Log2
    const ln2 = 0.693147180559945309417232121458176568075500134360255254120680009
    template log2Impl[T](x: T): T =
      var exp: int
      var frac = frexp(x, exp)
      # Make sure exact powers of two give an exact answer.
      # Don't depend on Log(0.5)*(1/Ln2)+exp being exactly exp-1.
      if frac == 0.5: return T(exp - 1)
      log10(frac) * (1 / ln2) + T(exp)

    func log2*(x: float32): float32 = log2Impl(x)
    func log2*(x: float64): float64 = log2Impl(x)
      ## Log2 returns the binary logarithm of x.
      ## The special cases are the same as for Log.

  else:
    func log2*(x: float32): float32 {.importc: "log2f", header: "<math.h>".}
    func log2*(x: float64): float64 {.importc: "log2", header: "<math.h>".} =
      ## Computes the binary logarithm (base 2) of `x`.
      ##
      ## **See also:**
      ## * `log func <#log,T,T>`_
      ## * `log10 func <#log10,float64>`_
      ## * `ln func <#ln,float64>`_
      runnableExamples:
        doAssert almostEqual(log2(8.0), 3.0)
        doAssert almostEqual(log2(1.0), 0.0)
        doAssert almostEqual(log2(0.0), -Inf)
        doAssert log2(-2.0).isNaN

func splitDecimal*[T: float32|float64](x: T): tuple[intpart: T, floatpart: T] =
  ## Breaks `x` into an integer and a fractional part.
  ##
  ## Returns a tuple containing `intpart` and `floatpart`, representing
  ## the integer part and the fractional part, respectively.
  ##
  ## Both parts have the same sign as `x`.  Analogous to the `modf`
  ## function in C.
  runnableExamples:
    doAssert splitDecimal(5.25) == (intpart: 5.0, floatpart: 0.25)
    doAssert splitDecimal(-2.73) == (intpart: -2.0, floatpart: -0.73)
  result = default(tuple[intpart: T, floatpart: T])
  var absolute: T = abs(x)
  result.intpart = floor(absolute)
  result.floatpart = absolute - result.intpart
  if x < 0:
    result.intpart = -result.intpart
    result.floatpart = -result.floatpart


func degToRad*[T: float32|float64](d: T): T {.inline.} =
  ## Converts from degrees to radians.
  ##
  ## **See also:**
  ## * `radToDeg func <#radToDeg,T>`_
  runnableExamples:
    doAssert almostEqual(degToRad(180.0), PI)

  result = d * T(RadPerDeg)

func radToDeg*[T: float32|float64](d: T): T {.inline.} =
  ## Converts from radians to degrees.
  ##
  ## **See also:**
  ## * `degToRad func <#degToRad,T>`_
  runnableExamples:
    doAssert almostEqual(radToDeg(2 * PI), 360.0)

  result = d / T(RadPerDeg)

func sgn*[T: SomeNumber](x: T): int {.inline.} =
  ## Sign function.
  ##
  ## Returns:
  ## * `-1` for negative numbers and `NegInf`,
  ## * `1` for positive numbers and `Inf`,
  ## * `0` for positive zero, negative zero and `NaN`
  runnableExamples:
    doAssert sgn(5) == 1
    doAssert sgn(0) == 0
    doAssert sgn(-4.1) == -1

  ord(T(0) < x) - ord(x < T(0))

{.pop.}
{.pop.}

func sum*[T](x: openArray[T]): T =
  ## Computes the sum of the elements in `x`.
  ##
  ## If `x` is empty, 0 is returned.
  ##
  ## **See also:**
  ## * `prod func <#prod,openArray[T]>`_
  ## * `cumsum func <#cumsum,openArray[T]>`_
  ## * `cumsummed func <#cumsummed,openArray[T]>`_
  runnableExamples:
    doAssert sum([1, 2, 3, 4]) == 10
    doAssert sum([-4, 3, 5]) == 4
  result = default(T)
  for i in items(x): result = result + i

func prod*[T](x: openArray[T]): T =
  ## Computes the product of the elements in `x`.
  ##
  ## If `x` is empty, 1 is returned.
  ##
  ## **See also:**
  ## * `sum func <#sum,openArray[T]>`_
  ## * `fac func <#fac,int>`_
  runnableExamples:
    doAssert prod([1, 2, 3, 4]) == 24
    doAssert prod([-4, 3, 5]) == -60

  result = T(1)
  for i in items(x): result = result * i

func cumprod*[T](x: var openArray[T]) =
  ## Transforms ``x`` in-place (must be declared as `var`) into its
  ## product.
  ##
  ## See also:
  ## * `prod proc <#sum,openArray[T]>`_
  ## * `cumproded proc <#cumproded,openArray[T]>`_ for a version which
  ##   returns cumproded sequence
  runnableExamples:
    var a = [1, 2, 3, 4]
    cumprod(a)
    doAssert a == @[1, 2, 6, 24]
  for i in 1 ..< x.len: x[i] = x[i-1] * x[i]

func cumproded*[T](x: openArray[T]): seq[T] =
  ## Return cumulative (aka prefix) product of ``x``.
  ##
  ## See also:
  ## * `prod proc <#prod,openArray[T]>`_
  ## * `cumprod proc <#cumprod,openArray[T]>`_ for the in-place version
  runnableExamples:
    let a = [1, 2, 3, 4]
    doAssert cumproded(a) == @[1, 2, 6, 24]
  result = @[]
  let xLen = x.len
  if xLen == 0:
    return @[]
  result.setLen(xLen)
  result[0] = x[0]
  for i in 1 ..< xLen: result[i] = result[i-1] * x[i]

func cumsummed*[T](x: openArray[T]): seq[T] =
  ## Returns the cumulative (aka prefix) summation of `x`.
  ##
  ## If `x` is empty, `@[]` is returned.
  ##
  ## **See also:**
  ## * `sum func <#sum,openArray[T]>`_
  ## * `cumsum func <#cumsum,openArray[T]>`_ for the in-place version
  runnableExamples:
    doAssert cumsummed([1, 2, 3, 4]) == @[1, 3, 6, 10]
  result = @[]
  let xLen = x.len
  if xLen == 0:
    return @[]
  result.setLen(xLen)
  result[0] = x[0]
  for i in 1 ..< xLen: result[i] = result[i - 1] + x[i]

func cumsum*[T](x: var openArray[T]) =
  ## Transforms `x` in-place (must be declared as `var`) into its
  ## cumulative (aka prefix) summation.
  ##
  ## **See also:**
  ## * `sum func <#sum,openArray[T]>`_
  ## * `cumsummed func <#cumsummed,openArray[T]>`_ for a version which
  ##   returns a cumsummed sequence
  runnableExamples:
    var a = [1, 2, 3, 4]
    cumsum(a)
    doAssert a == @[1, 3, 6, 10]

  for i in 1 ..< x.len: x[i] = x[i - 1] + x[i]

func `^`*[T: SomeNumber](x: T, y: Natural): T =
  ## Computes `x` to the power of `y`.
  ##
  ## The exponent `y` must be non-negative, use
  ## `pow <#pow,float64,float64>`_ for negative exponents.
  ##
  ## **See also:**
  ## * `^ func <#^,T,U>`_ for negative exponent or floats
  ## * `pow func <#pow,float64,float64>`_ for `float32` or `float64` output
  ## * `sqrt func <#sqrt,float64>`_
  ## * `cbrt func <#cbrt,float64>`_
  runnableExamples:
    doAssert -3 ^ 0 == 1
    doAssert -3 ^ 1 == -3
    doAssert -3 ^ 2 == 9

  case y
  of 0: result = 1
  of 1: result = x
  of 2: result = x * x
  of 3: result = x * x * x
  else:
    var (x, y) = (x, y)
    result = 1
    while true:
      if (y and 1) != 0:
        result *= x
      y = y shr 1
      if y == 0:
        break
      x *= x

func isInteger(y: SomeFloat): bool =
  ## Determines if a float represents an integer
  return round(y) == y

func `^`*[T: SomeNumber, U: SomeFloat](x: T, y: U): float =
  ## Computes `x` to the power of `y`.
  ##
  ## Error handling follows the C++ specification even for the JS backend
  ## https://en.cppreference.com/w/cpp/numeric/math/pow
  ##
  ## **See also:**
  ## * `^ func <#^,T,Natural>`_
  ## * `pow func <#pow,float64,float64>`_ for `float32` or `float64` output
  ## * `sqrt func <#sqrt,float64>`_
  ## * `cbrt func <#cbrt,float64>`_
  runnableExamples:
    doAssert almostEqual(5.5 ^ 2.2, 42.540042248725975)
    doAssert 1.0 ^ Inf == 1.0
  let
    isZero_x: bool = (x == 0.0 or x == -0.0)
    isNegZero: bool = classify(x) == fcNegZero
    isPosZero: bool = classify(x) == fcZero
    yIsFinite: bool = (y != Inf and y != -Inf)
    yIsOddInteger: bool = (isInteger(y) and yIsFinite and (abs(int(y) mod 2) == 1))

  assert not(isPosZero and y < 0 and yIsOddInteger)
  assert not(isNegZero and y < 0 and yIsOddInteger)
  assert not(isZero_x and y < 0 and y != -Inf)
  assert not(isZero_x and y == -Inf)
  assert not(x < 0 and not isInteger(x) and yIsFinite and not yIsOddInteger)
  when defined(js):
    # JS behavior follows an old version of IEEE 754 for compatibility reasons
    # See https://262.ecma-international.org/#sec-numeric-types-number-exponentiate
    if (x == 1.0 or x == -1.0) and not yIsFinite:
      float(1.0)
    elif x == 1.0 and y.isNan():
      float(1.0)
    else:
      float(pow(x, y))
  else:
    float(pow(x, y))

func gcd*[T](x, y: T): T =
  ## Computes the greatest common (positive) divisor of `x` and `y`.
  ##
  ## Note that for floats, the result cannot always be interpreted as
  ## "greatest decimal `z` such that `z*N == x and z*M == y`
  ## where N and M are positive integers".
  ##
  ## **See also:**
  ## * `gcd func <#gcd,SomeInteger,SomeInteger>`_ for an integer version
  ## * `lcm func <#lcm,T,T>`_
  runnableExamples:
    doAssert gcd(13.5, 9.0) == 4.5

  var (x, y) = (x, y)
  while y != 0:
    x = x mod y
    swap x, y
  abs x

when useBuiltins:
  ## this func uses bitwise comparisons from C compilers, which are not always available.
  func gcd*(x, y: SomeInteger): SomeInteger =
    ## Computes the greatest common (positive) divisor of `x` and `y`,
    ## using the binary GCD (aka Stein's) algorithm.
    ##
    ## **See also:**
    ## * `gcd func <#gcd,T,T>`_ for a float version
    ## * `lcm func <#lcm,T,T>`_
    runnableExamples:
      doAssert gcd(12, 8) == 4
      doAssert gcd(17, 63) == 1
  
    when x is SomeSignedInt:
      var x = abs(x)
    else:
      var x = x
    when y is SomeSignedInt:
      var y = abs(y)
    else:
      var y = y
  
    if x == 0:
      return y
    if y == 0:
      return x
  
    let shift = countTrailingZeroBits(x or y)
    y = y shr countTrailingZeroBits(y)
    while x != 0:
      x = x shr countTrailingZeroBits(x)
      if y > x:
        swap y, x
      x -= y
    y shl shift
  
func gcd*[T](x: openArray[T]): T {.since: (1, 1).} =
  ## Computes the greatest common (positive) divisor of the elements of `x`.
  ##
  ## **See also:**
  ## * `gcd func <#gcd,T,T>`_ for a version with two arguments
  runnableExamples:
    doAssert gcd(@[13.5, 9.0]) == 4.5

  result = x[0]
  for i in 1 ..< x.len:
    result = gcd(result, x[i])

func lcm*[T](x, y: T): T =
  ## Computes the least common multiple of `x` and `y`.
  ##
  ## **See also:**
  ## * `gcd func <#gcd,T,T>`_
  runnableExamples:
    doAssert lcm(24, 30) == 120
    doAssert lcm(13, 39) == 39

  x div gcd(x, y) * y

func clamp*[T](val: T, bounds: Slice[T]): T {.since: (1, 5), inline.} =
  ## Like `system.clamp`, but takes a slice, so you can easily clamp within a range.
  runnableExamples:
    assert clamp(10, 1 .. 5) == 5
    assert clamp(1, 1 .. 3) == 1
    type A = enum a0, a1, a2, a3, a4, a5
    assert a1.clamp(a2..a4) == a2
    assert clamp((3, 0), (1, 0) .. (2, 9)) == (2, 9)
    doAssertRaises(AssertionDefect): discard clamp(1, 3..2) # invalid bounds
  assert bounds.a <= bounds.b, $(bounds.a, bounds.b)
  clamp(val, bounds.a, bounds.b)

func lcm*[T](x: openArray[T]): T {.since: (1, 1).} =
  ## Computes the least common multiple of the elements of `x`.
  ##
  ## **See also:**
  ## * `lcm func <#lcm,T,T>`_ for a version with two arguments
  runnableExamples:
    doAssert lcm(@[24, 30]) == 120

  result = x[0]
  for i in 1 ..< x.len:
    result = lcm(result, x[i])


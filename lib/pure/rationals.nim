#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Dennis Felsing
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#


## This module implements rational numbers, consisting of a numerator and
## a denominator. The denominator can not be 0.

runnableExamples:
  let
    r1 = 1 // 2
    r2 = -3 // 4

  doAssert r1 + r2 == -1 // 4
  doAssert r1 - r2 ==  5 // 4
  doAssert r1 * r2 == -3 // 8
  doAssert r1 / r2 == -2 // 3

import std/[math, hashes]
when defined(nimPreviewSlimSystem):
  import std/assertions

type Rational*[T] = object
  ## A rational number, consisting of a numerator `num` and a denominator `den`.
  num*, den*: T

func reduce*[T: SomeInteger](x: var Rational[T]) =
  ## Reduces the rational number `x`, so that the numerator and denominator
  ## have no common divisors other than 1 (and -1).
  ## If `x` is 0, raises `DivByZeroDefect`.
  ##
  ## **Note:** This is called automatically by the various operations on rationals.
  runnableExamples:
    var r = Rational[int](num: 2, den: 4) # 1/2
    reduce(r)
    doAssert r.num == 1
    doAssert r.den == 2
  if x.den == 0:
    raise newException(DivByZeroDefect, "division by zero")
  let common = gcd(x.num, x.den)
  if x.den > 0:
    x.num = x.num div common
    x.den = x.den div common
  when T isnot SomeUnsignedInt:
    if x.den < 0:
      x.num = -x.num div common
      x.den = -x.den div common

func initRational*[T: SomeInteger](num, den: T): Rational[T] =
  ## Creates a new rational number with numerator `num` and denominator `den`.
  ## `den` must not be 0.
  ##
  ## **Note:** `den != 0` is not checked when assertions are turned off.
  assert(den != 0, "a denominator of zero is invalid")
  result = Rational[T](num: num, den: den)
  reduce(result)

func `//`*[T](num, den: T): Rational[T] =
  ## A friendlier version of `initRational <#initRational,T,T>`_.
  runnableExamples:
    let x = 1 // 3 + 1 // 5
    doAssert x == 8 // 15

  initRational[T](num, den)

func `$`*[T](x: Rational[T]): string =
  ## Turns a rational number into a string.
  runnableExamples:
    doAssert $(1 // 2) == "1/2"

  result = $x.num & "/" & $x.den

func toRational*[T: SomeInteger](x: T): Rational[T] =
  ## Converts some integer `x` to a rational number.
  runnableExamples:
    doAssert toRational(42) == 42 // 1
  result = Rational[T](num: x, den: 1)

func toRational*(x: float,
                 n: int = high(int) shr (sizeof(int) div 2 * 8)): Rational[int] =
  ## Calculates the best rational approximation of `x`,
  ## where the denominator is smaller than `n`
  ## (default is the largest possible `int` for maximal resolution).
  ##
  ## The algorithm is based on the theory of continued fractions.
  # David Eppstein / UC Irvine / 8 Aug 1993
  # With corrections from Arno Formella, May 2008
  runnableExamples:
    let x = 1.2
    doAssert x.toRational.toFloat == x

  var
    m11, m22 = 1
    m12, m21 = 0
    ai = int(x)
    x = x
  while m21 * ai + m22 <= n:
    swap m12, m11
    swap m22, m21
    m11 = m12 * ai + m11
    m21 = m22 * ai + m21
    if x == float(ai): break # division by zero
    x = 1 / (x - float(ai))
    if x > float(high(int32)): break # representation failure
    ai = int(x)
  result = m11 // m21

func toFloat*[T](x: Rational[T]): float =
  ## Converts a rational number `x` to a `float`.
  x.num / x.den

func toInt*[T](x: Rational[T]): int =
  ## Converts a rational number `x` to an `int`. Conversion rounds towards 0 if
  ## `x` does not contain an integer value.
  x.num div x.den

func `+`*[T](x, y: Rational[T]): Rational[T] =
  ## Adds two rational numbers.
  let common = lcm(x.den, y.den)
  result = Rational[T](num: common div x.den * x.num + common div y.den * y.num,
                       den: common
  )
  reduce(result)

func `+`*[T](x: Rational[T], y: T): Rational[T] =
  ## Adds the rational `x` to the int `y`.
  result = Rational[T](num: x.num + y * x.den, den: x.den)

func `+`*[T](x: T, y: Rational[T]): Rational[T] =
  ## Adds the int `x` to the rational `y`.
  result = Rational[T](num: x * y.den + y.num, den: y.den)

func `+=`*[T](x: var Rational[T], y: Rational[T]) =
  ## Adds the rational `y` to the rational `x` in-place.
  let common = lcm(x.den, y.den)
  x.num = common div x.den * x.num + common div y.den * y.num
  x.den = common
  reduce(x)

func `+=`*[T](x: var Rational[T], y: T) =
  ## Adds the int `y` to the rational `x` in-place.
  x.num += y * x.den

func `-`*[T](x: Rational[T]): Rational[T] =
  ## Unary minus for rational numbers.
  result = Rational[T](num: -x.num, den: x.den)

func `-`*[T](x, y: Rational[T]): Rational[T] =
  ## Subtracts two rational numbers.
  let common = lcm(x.den, y.den)
  result = Rational[T](num: common div x.den * x.num - common div y.den * y.num,
                den: common
  )
  reduce(result)

func `-`*[T](x: Rational[T], y: T): Rational[T] =
  ## Subtracts the int `y` from the rational `x`.
  result = Rational[T](num: x.num - y * x.den, den: x.den)

func `-`*[T](x: T, y: Rational[T]): Rational[T] =
  ## Subtracts the rational `y` from the int `x`.
  result = Rational[T](num: x * y.den - y.num, den: y.den)

func `-=`*[T](x: var Rational[T], y: Rational[T]) =
  ## Subtracts the rational `y` from the rational `x` in-place.
  let common = lcm(x.den, y.den)
  x.num = common div x.den * x.num - common div y.den * y.num
  x.den = common
  reduce(x)

func `-=`*[T](x: var Rational[T], y: T) =
  ## Subtracts the int `y` from the rational `x` in-place.
  x.num -= y * x.den

func `*`*[T](x, y: Rational[T]): Rational[T] =
  ## Multiplies two rational numbers.
  result = Rational[T](num: x.num * y.num, den: x.den * y.den)
  reduce(result)

func `*`*[T](x: Rational[T], y: T): Rational[T] =
  ## Multiplies the rational `x` with the int `y`.
  result = Rational[T](num: x.num * y, den: x.den)
  reduce(result)

func `*`*[T](x: T, y: Rational[T]): Rational[T] =
  ## Multiplies the int `x` with the rational `y`.
  result = Rational[T](num: x * y.num, den: y.den)
  reduce(result)

func `*=`*[T](x: var Rational[T], y: Rational[T]) =
  ## Multiplies the rational `x` by `y` in-place.
  x.num *= y.num
  x.den *= y.den
  reduce(x)

func `*=`*[T](x: var Rational[T], y: T) =
  ## Multiplies the rational `x` by the int `y` in-place.
  x.num *= y
  reduce(x)

func reciprocal*[T](x: Rational[T]): Rational[T] =
  ## Calculates the reciprocal of `x` (`1/x`).
  ## If `x` is 0, raises `DivByZeroDefect`.
  if x.num > 0:
    result = Rational[T](num: x.den, den: x.num)
  elif x.num < 0:
    result = Rational[T](num: -x.den, den: -x.num)
  else:
    raise newException(DivByZeroDefect, "division by zero")

func `/`*[T](x, y: Rational[T]): Rational[T] =
  ## Divides the rational `x` by the rational `y`.
  result = Rational[T](num: x.num * y.den, den: x.den * y.num)
  reduce(result)

func `/`*[T](x: Rational[T], y: T): Rational[T] =
  ## Divides the rational `x` by the int `y`.
  result = Rational[T](num: x.num, den: x.den * y)
  reduce(result)

func `/`*[T](x: T, y: Rational[T]): Rational[T] =
  ## Divides the int `x` by the rational `y`.
  result = Rational[T](num: x * y.den, den: y.num)
  reduce(result)

func `/=`*[T](x: var Rational[T], y: Rational[T]) =
  ## Divides the rational `x` by the rational `y` in-place.
  x.num *= y.den
  x.den *= y.num
  reduce(x)

func `/=`*[T](x: var Rational[T], y: T) =
  ## Divides the rational `x` by the int `y` in-place.
  x.den *= y
  reduce(x)

func cmp*(x, y: Rational): int =
  ## Compares two rationals. Returns
  ## * a value less than zero, if `x < y`
  ## * a value greater than zero, if `x > y`
  ## * zero, if `x == y`
  (x - y).num

func `<`*(x, y: Rational): bool =
  ## Returns true if `x` is less than `y`.
  (x - y).num < 0

func `<=`*(x, y: Rational): bool =
  ## Returns tue if `x` is less than or equal to `y`.
  (x - y).num <= 0

func `==`*(x, y: Rational): bool =
  ## Compares two rationals for equality.
  (x - y).num == 0

func abs*[T](x: Rational[T]): Rational[T] =
  ## Returns the absolute value of `x`.
  runnableExamples:
    doAssert abs(1 // 2) == 1 // 2
    doAssert abs(-1 // 2) == 1 // 2
  result = Rational[T](num: abs x.num, den: abs x.den)

func `div`*[T: SomeInteger](x, y: Rational[T]): T =
  ## Computes the rational truncated division.
  (x.num * y.den) div (y.num * x.den)

func `mod`*[T: SomeInteger](x, y: Rational[T]): Rational[T] =
  ## Computes the rational modulo by truncated division (remainder).
  ## This is same as `x - (x div y) * y`.
  result = ((x.num * y.den) mod (y.num * x.den)) // (x.den * y.den)
  reduce(result)

func floorDiv*[T: SomeInteger](x, y: Rational[T]): T =
  ## Computes the rational floor division.
  ##
  ## Floor division is conceptually defined as `floor(x / y)`.
  ## This is different from the `div` operator, which is defined
  ## as `trunc(x / y)`. That is, `div` rounds towards 0 and `floorDiv`
  ## rounds down.
  floorDiv(x.num * y.den, y.num * x.den)

func floorMod*[T: SomeInteger](x, y: Rational[T]): Rational[T] =
  ## Computes the rational modulo by floor division (modulo).
  ##
  ## This is same as `x - floorDiv(x, y) * y`.
  ## This func behaves the same as the `%` operator in Python.
  result = floorMod(x.num * y.den, y.num * x.den) // (x.den * y.den)
  reduce(result)

func hash*[T](x: Rational[T]): Hash =
  ## Computes the hash for the rational `x`.
  # reduce first so that hash(x) == hash(y) for x == y
  result = Hash(0)
  var copy = x
  reduce(copy)

  var h: Hash = 0
  h = h !& hash(copy.num)
  h = h !& hash(copy.den)
  result = !$h

func `^`*[T: SomeInteger](x: Rational[T], y: T): Rational[T] =
  ## Computes `x` to the power of `y`.
  ##
  ## The exponent `y` must be an integer. Negative exponents are supported
  ## but floating point exponents are not.
  runnableExamples:
    doAssert (-3 // 5) ^ 0 == (1 // 1)
    doAssert (-3 // 5) ^ 1 == (-3 // 5)
    doAssert (-3 // 5) ^ 2 == (9 // 25)
    doAssert (-3 // 5) ^ -2 == (25 // 9)

  if y >= 0:
    result = Rational[T](num: x.num ^ y, den: x.den ^ y)
  else:
    result = Rational[T](num: x.den ^ -y, den: x.num ^ -y)
  # Note that all powers of reduced rationals are already reduced,
  # so we don't need to call reduce() here

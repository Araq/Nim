#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#


## This module implements rational numbers, consisting of a numerator `num` and
## a denominator `den`, both of type int. The denominator can not be 0.

import math

type Rational* = tuple[num, den: int]
  ## a rational number, consisting of a numerator and denominator

proc toRational*(x: SomeInteger): Rational =
  ## Convert some integer `x` to a rational number.
  result.num = x
  result.den = 1

proc toFloat*(x: Rational): float =
  ## Convert a rational number `x` to a float.
  float(x.num) / float(x.den)

proc toInt*(x: Rational): int =
  ## Convert a rational number `x` to an int. Conversion rounds if `x` does not
  ## contain an integer value.
  round(toFloat(x))

proc reduce*(x: var Rational) =
  ## Reduce rational `x`.
  let common = gcd(x.num, x.den)
  if x.den > 0:
    x.num = x.num div common
    x.den = x.den div common
  elif x.den < 0:
    x.num = -x.num div common
    x.den = -x.den div common
  else:
    raise newException(DivByZeroError, "division by zero")

proc `+` *(x, y: Rational): Rational =
  ## Add two rational numbers.
  let common = lcm(x.den, y.den)
  result.num = common div x.den * x.num + common div y.den * y.num
  result.den = common
  reduce(result)

proc `+` *(x: Rational, y: int): Rational =
  ## Add rational `x` to int `y`.
  result.num = x.num + y * x.den
  result.den = x.den

proc `+` *(x: int, y: Rational): Rational =
  ## Add int `x` to tational `y`.
  result.num = x * y.den + y.num
  result.den = y.den

proc `+=` *(x: var Rational, y: Rational) =
  ## Add rational `y` to rational `x`.
  let common = lcm(x.den, y.den)
  x.num = common div x.den * x.num + common div y.den * y.num
  x.den = common
  reduce(x)

proc `+=` *(x: var Rational, y: int) =
  ## Add int `y` to rational `x`.
  x.num += y

proc `-` *(x: Rational): Rational =
  ## Unary minus for rational numbers.
  result.num = -x.num
  result.den = x.den

proc `-` *(x, y: Rational): Rational =
  ## Subtract two rational numbers.
  let common = lcm(x.den, y.den)
  result.num = common div x.den * x.num - common div y.den * y.num
  result.den = common
  reduce(result)

proc `-` *(x: Rational, y: int): Rational =
  ## Subtract int `y` from rational `x`.
  result.num = x.num - y * x.den
  result.den = x.den

proc `-` *(x: int, y: Rational): Rational =
  ## Subtract rational `y` from int `x`.
  result.num = - x * y.den + y.num
  result.den = y.den

proc `-=` *(x: var Rational, y: Rational) =
  ## Subtract rational `y` from rational `x`.
  let common = lcm(x.den, y.den)
  x.num = common div x.den * x.num - common div y.den * y.num
  x.den = common
  reduce(x)

proc `-=` *(x: var Rational, y: int) =
  ## Subtract int `y` from rational `x`.
  x.num -= y

proc `*` *(x, y: Rational): Rational =
  ## Multiply two rational numbers.
  result.num = x.num * y.num
  result.den = x.den * y.den
  reduce(result)

proc `*` *(x: Rational, y: int): Rational =
  ## Multiply rational `x` with int `y`.
  result.num = x.num * y
  result.den = x.den
  reduce(result)

proc `*` *(x: int, y: Rational): Rational =
  ## Multiply int `x` with rational `y`.
  result.num = x * y.num
  result.den = y.den
  reduce(result)

proc `*=` *(x: var Rational, y: Rational) =
  ## Multiply rationals `y` to `x`.
  x.num *= y.num
  x.den *= y.den
  reduce(x)

proc `*=` *(x: var Rational, y: int) =
  ## Multiply int `y` to rational `x`.
  x.num *= y
  reduce(x)

proc reciprocal*(x: Rational): Rational =
  ## Calculate the reciprocal of `x`. (1/x)
  if x.num > 0:
    result.num = x.den
    result.den = x.num
  elif x.num < 0:
    result.num = -x.den
    result.den = -x.num
  else:
    raise newException(DivByZeroError, "division by zero")

proc `/`*(x, y: Rational): Rational =
  ## Divide rationals `x` by `y`.
  result.num = x.num * y.den
  result.den = x.den * y.num
  reduce(result)

proc `/`*(x: Rational, y: int): Rational =
  ## Divide rational `x` by int `y`.
  result.num = x.num
  result.den = x.den * y
  reduce(result)

proc `/`*(x: int, y: Rational): Rational =
  ## Divide int `x` by Rational `y`.
  result.num = y.num
  result.den = x * y.den
  reduce(result)

proc `/=`*(x: var Rational, y: Rational): Rational =
  ## Divide rationals `x` by `y` in place.
  x.num *= y.den
  x.den *= y.num
  reduce(x)

proc `/=`*(x: var Rational, y: int): Rational =
  ## Divide rational `x` by int `y` in place.
  x.den *= y
  reduce(x)

proc cmp*(x, y: Rational): int =
  ## Compares two rationals.
  (x - y).num

proc `<` *(x, y: Rational): bool =
  (x - y).num < 0

proc `<=` *(x, y: Rational): bool =
  (x - y).num <= 0

proc `==` *(x, y: Rational): bool =
  (x - y).num == 0

proc abs*(x: Rational): Rational =
  result.num = abs x.num
  result.den = abs x.den

when isMainModule:
  var z = (0, 1)
  var o = (1, 1)
  var a = (1, 2)
  var b = (-1, -2)
  var m1 = (-1, 1)
  var tt = (10, 2)

  assert( a     == a )
  assert( (a-a) == z )
  assert( (a+b) == o )
  assert( (a/b) == o )
  assert( (a*b) == (1, 4) )
  assert( 10*a  == tt )
  assert( a*10  == tt )
  assert( tt/10 == a  )
  assert( a-m1  == (3, 2) )
  assert( a+m1  == (-1, 2) )
  assert( m1+tt == (16, 4) )
  assert( m1-tt == (6, -1) )

  assert( z < o )
  assert( z <= o )
  assert( z == z )
  assert( cmp(z, o) < 0)
  assert( cmp(o, z) > 0)

  assert( o == o )
  assert( o >= o )
  assert( not(o > o) )
  assert( cmp(o, o) == 0)
  assert( cmp(z, z) == 0)

  assert( a == b )
  assert( a >= b )
  assert( not(b > a) )
  assert( cmp(a, b) == 0)

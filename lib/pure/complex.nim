#
#
#            Nim's Runtime Library
#        (c) Copyright 2010 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements complex numbers
## and basic mathematical operations on them.
##
## Complex numbers are currently generic over 64-bit or 32-bit floats.

runnableExamples:
  from std/math import almostEqual, sqrt

  let
    z1 = complex(1.0, 2.0)
    z2 = complex(3.0, -4.0)

  assert almostEqual(z1 + z2, complex(4.0, -2.0))
  assert almostEqual(z1 - z2, complex(-2.0, 6.0))
  assert almostEqual(z1 * z2, complex(11.0, 2.0))
  assert almostEqual(z1 / z2, complex(-0.2, 0.4))

  assert almostEqual(abs(z1), sqrt(5.0))
  assert almostEqual(conjugate(z1), complex(1.0, -2.0))

  let (r, phi) = z1.polar
  assert almostEqual(rect(r, phi), z1)

{.push checks: off, line_dir: off, stack_trace: off, debugger: off.}
# the user does not want to trace a part of the standard library!

import std/[math, strformat, strutils]

type
  Complex*[T: SomeFloat] = object
    ## A complex number, consisting of a real and an imaginary part.
    re*, im*: T
  Complex64* = Complex[float64]
    ## Alias for a complex number using 64-bit floats.
  Complex32* = Complex[float32]
    ## Alias for a complex number using 32-bit floats.

func complex*[T: SomeFloat](re: T; im: T = 0.0): Complex[T] =
  ## Returns a `Complex[T]` with real part `re` and imaginary part `im`.
  result = Complex[T](re: re, im: im)

func complex32*(re: float32; im: float32 = 0.0): Complex32 =
  ## Returns a `Complex32` with real part `re` and imaginary part `im`.
  result = Complex32(re: re, im: im)

func complex64*(re: float64; im: float64 = 0.0): Complex64 =
  ## Returns a `Complex64` with real part `re` and imaginary part `im`.
  result = Complex64(re: re, im: im)

template im*(arg: typedesc[float32]): Complex32 = complex32(0, 1)
  ## Returns the imaginary unit (`complex32(0, 1)`).
template im*(arg: typedesc[float64]): Complex64 = complex64(0, 1)
  ## Returns the imaginary unit (`complex64(0, 1)`).
template im*(arg: float32): Complex32 = complex32(0, arg)
  ## Returns `arg` as an imaginary number (`complex32(0, arg)`).
template im*(arg: float64): Complex64 = complex64(0, arg)
  ## Returns `arg` as an imaginary number (`complex64(0, arg)`).

func abs*[T](z: Complex[T]): T =
  ## Returns the absolute value of `z`,
  ## that is the distance from (0, 0) to `z`.
  result = hypot(z.re, z.im)

func abs2*[T](z: Complex[T]): T =
  ## Returns the squared absolute value of `z`,
  ## that is the squared distance from (0, 0) to `z`.
  ## This is more efficient than `abs(z) ^ 2`.
  result = z.re * z.re + z.im * z.im

func sgn*[T](z: Complex[T]): Complex[T] =
  ## Returns the phase of `z` as a unit complex number,
  ## or 0 if `z` is 0.
  let a = abs(z)
  if a != 0:
    result = z / a
  else:
    result = Complex[T]()

func conjugate*[T](z: Complex[T]): Complex[T] =
  ## Returns the complex conjugate of `z` (`complex(z.re, -z.im)`).
  result = Complex[T](re: z.re, im: -z.im)

func inv*[T](z: Complex[T]): Complex[T] =
  ## Returns the multiplicative inverse of `z` (`1/z`).
  result = conjugate(z) / abs2(z)

func `==`*[T](x, y: Complex[T]): bool =
  ## Compares two complex numbers for equality.
  result = x.re == y.re and x.im == y.im

func `+`*[T](x: T; y: Complex[T]): Complex[T] =
  ## Adds a real number to a complex number.
  result = Complex[T](re: x + y.re, im: y.im)

func `+`*[T](x: Complex[T]; y: T): Complex[T] =
  ## Adds a complex number to a real number.
  result = Complex[T](re: x.re + y, im: x.im)

func `+`*[T](x, y: Complex[T]): Complex[T] =
  ## Adds two complex numbers.
  result = Complex[T](re: x.re + y.re, im: x.im + y.im)

func `-`*[T](z: Complex[T]): Complex[T] =
  ## Unary minus for complex numbers.
  result = Complex[T](re: -z.re, im: -z.im)

func `-`*[T](x: T; y: Complex[T]): Complex[T] =
  ## Subtracts a complex number from a real number.
  result = Complex[T](re: x - y.re, im: -y.im)

func `-`*[T](x: Complex[T]; y: T): Complex[T] =
  ## Subtracts a real number from a complex number.
  result = Complex[T](re: x.re - y, im: x.im)

func `-`*[T](x, y: Complex[T]): Complex[T] =
  ## Subtracts two complex numbers.
  result = Complex[T](re: x.re - y.re, im: x.im - y.im)

func `*`*[T](x: T; y: Complex[T]): Complex[T] =
  ## Multiplies a real number with a complex number.
  result = Complex[T](re: x * y.re, im: x * y.im)

func `*`*[T](x: Complex[T]; y: T): Complex[T] =
  ## Multiplies a complex number with a real number.
  result = Complex[T](re: x.re * y, im: x.im * y)

func `*`*[T](x, y: Complex[T]): Complex[T] =
  ## Multiplies two complex numbers.
  result = Complex[T](re: x.re * y.re - x.im * y.im,
                      im: x.im * y.re + x.re * y.im)

func `/`*[T](x: Complex[T]; y: T): Complex[T] =
  ## Divides a complex number by a real number.
  result = Complex[T](re: x.re / y, im: x.im / y)

func `/`*[T](x: T; y: Complex[T]): Complex[T] =
  ## Divides a real number by a complex number.
  result = x * inv(y)

func `/`*[T](x, y: Complex[T]): Complex[T] =
  ## Divides two complex numbers.
  x * conjugate(y) / abs2(y)

func `+=`*[T](x: var Complex[T]; y: Complex[T]) =
  ## Adds `y` to `x`.
  x.re += y.re
  x.im += y.im

func `-=`*[T](x: var Complex[T]; y: Complex[T]) =
  ## Subtracts `y` from `x`.
  x.re -= y.re
  x.im -= y.im

func `*=`*[T](x: var Complex[T]; y: Complex[T]) =
  ## Multiplies `x` by `y`.
  let im = x.im * y.re + x.re * y.im
  x.re = x.re * y.re - x.im * y.im
  x.im = im

func `/=`*[T](x: var Complex[T]; y: Complex[T]) =
  ## Divides `x` by `y` in place.
  x = x / y


func sqrt*[T](z: Complex[T]): Complex[T] =
  ## Computes the
  ## ([principal](https://en.wikipedia.org/wiki/Square_root#Principal_square_root_of_a_complex_number))
  ## square root of a complex number `z`.
  var x, y, w, r: T

  if z.re == 0.0 and z.im == 0.0:
    result = z
  else:
    x = abs(z.re)
    y = abs(z.im)
    if x >= y:
      r = y / x
      w = sqrt(x) * sqrt(0.5 * (1.0 + sqrt(1.0 + r * r)))
    else:
      r = x / y
      w = sqrt(y) * sqrt(0.5 * (r + sqrt(1.0 + r * r)))

    if z.re >= 0.0:
      result = Complex[T](re: w, im: z.im / (w * 2.0))
    else:
      result = Complex[T](im: if z.im >= 0.0: w else: -w)
      result.re = z.im / (result.im + result.im)

func exp*[T](z: Complex[T]): Complex[T] =
  ## Computes the exponential function (`e^z`).
  let
    rho = exp(z.re)
    theta = z.im
  result = Complex[T](re: rho * cos(theta), im: rho * sin(theta))

func ln*[T](z: Complex[T]): Complex[T] =
  ## Returns the
  ## ([principal value](https://en.wikipedia.org/wiki/Complex_logarithm#Principal_value)
  ## of the) natural logarithm of `z`.
  result = Complex[T](re: ln(abs(z)), im: arctan2(z.im, z.re))

func log10*[T](z: Complex[T]): Complex[T] =
  ## Returns the logarithm base 10 of `z`.
  ##
  ## **See also:**
  ## * `ln func<#ln,Complex[T]>`_
  result = ln(z) / ln(10.0)

func log2*[T](z: Complex[T]): Complex[T] =
  ## Returns the logarithm base 2 of `z`.
  ##
  ## **See also:**
  ## * `ln func<#ln,Complex[T]>`_
  result = ln(z) / ln(2.0)

func pow*[T](x, y: Complex[T]): Complex[T] =
  ## `x` raised to the power of `y`.
  if x.re == 0.0 and x.im == 0.0:
    if y.re == 0.0 and y.im == 0.0:
      result = Complex[T](re: 1.0, im: 0.0)
    else:
      result = Complex[T](re: 0.0, im: 0.0)
  elif y.im == 0.0:
    if y.re == 1.0:
      result = x
    elif y.re == -1.0:
      result = T(1.0) / x
    elif y.re == 2.0:
      result = x * x
    elif y.re == 0.5:
      result = sqrt(x)
    elif x.im == 0.0:
      # Revert to real pow when both base and exponent are real
      result = Complex[T](re: pow(x.re, y.re), im: 0.0)
    else:
      # Special case when the exponent is real
      let
        rho = abs(x)
        theta = arctan2(x.im, x.re)
        s = pow(rho, y.re)
        r = y.re * theta
      result = Complex[T](re: s * cos(r), im: s * sin(r))
  elif x.im == 0.0 and x.re == E:
   # Special case Euler's formula
   result = exp(y)
  else:
    let
      rho = abs(x)
      theta = arctan2(x.im, x.re)
      s = pow(rho, y.re) * exp(-y.im * theta)
      r = y.re * theta + y.im * ln(rho)
    result = Complex[T](re: s * cos(r), im: s * sin(r))

func pow*[T](x: Complex[T]; y: T): Complex[T] =
  ## The complex number `x` raised to the power of the real number `y`.
  pow(x, complex[T](y))

func sin*[T](z: Complex[T]): Complex[T] =
  ## Returns the sine of `z`.
  result = Complex[T](re: sin(z.re) * cosh(z.im), im: cos(z.re) * sinh(z.im))

func arcsin*[T](z: Complex[T]): Complex[T] =
  ## Returns the inverse sine of `z`.
  result = -im(T) * ln(im(T) * z + sqrt(T(1.0) - z*z))

func cos*[T](z: Complex[T]): Complex[T] =
  ## Returns the cosine of `z`.
  result = Complex[T](re: cos(z.re) * cosh(z.im),
                      im: -sin(z.re) * sinh(z.im)
  )

func arccos*[T](z: Complex[T]): Complex[T] =
  ## Returns the inverse cosine of `z`.
  result = -im(T) * ln(z + sqrt(z*z - T(1.0)))

func tan*[T](z: Complex[T]): Complex[T] =
  ## Returns the tangent of `z`.
  result = sin(z) / cos(z)

func arctan*[T](z: Complex[T]): Complex[T] =
  ## Returns the inverse tangent of `z`.
  result = T(0.5)*im(T) * (ln(T(1.0) - im(T)*z) - ln(T(1.0) + im(T)*z))

func cot*[T](z: Complex[T]): Complex[T] =
  ## Returns the cotangent of `z`.
  result = cos(z)/sin(z)

func arccot*[T](z: Complex[T]): Complex[T] =
  ## Returns the inverse cotangent of `z`.
  result = T(0.5)*im(T) * (ln(T(1.0) - im(T)/z) - ln(T(1.0) + im(T)/z))

func sec*[T](z: Complex[T]): Complex[T] =
  ## Returns the secant of `z`.
  result = T(1.0) / cos(z)

func arcsec*[T](z: Complex[T]): Complex[T] =
  ## Returns the inverse secant of `z`.
  result = -im(T) * ln(im(T) * sqrt(1.0 - 1.0/(z*z)) + T(1.0)/z)

func csc*[T](z: Complex[T]): Complex[T] =
  ## Returns the cosecant of `z`.
  result = T(1.0) / sin(z)

func arccsc*[T](z: Complex[T]): Complex[T] =
  ## Returns the inverse cosecant of `z`.
  result = -im(T) * ln(sqrt(T(1.0) - T(1.0)/(z*z)) + im(T)/z)

func sinh*[T](z: Complex[T]): Complex[T] =
  ## Returns the hyperbolic sine of `z`.
  result = T(0.5) * (exp(z) - exp(-z))

func arcsinh*[T](z: Complex[T]): Complex[T] =
  ## Returns the inverse hyperbolic sine of `z`.
  result = ln(z + sqrt(z*z + 1.0))

func cosh*[T](z: Complex[T]): Complex[T] =
  ## Returns the hyperbolic cosine of `z`.
  result = T(0.5) * (exp(z) + exp(-z))

func arccosh*[T](z: Complex[T]): Complex[T] =
  ## Returns the inverse hyperbolic cosine of `z`.
  result = ln(z + sqrt(z*z - T(1.0)))

func tanh*[T](z: Complex[T]): Complex[T] =
  ## Returns the hyperbolic tangent of `z`.
  result = sinh(z) / cosh(z)

func arctanh*[T](z: Complex[T]): Complex[T] =
  ## Returns the inverse hyperbolic tangent of `z`.
  result = T(0.5) * (ln((T(1.0)+z) / (T(1.0)-z)))

func coth*[T](z: Complex[T]): Complex[T] =
  ## Returns the hyperbolic cotangent of `z`.
  result = cosh(z) / sinh(z)

func arccoth*[T](z: Complex[T]): Complex[T] =
  ## Returns the inverse hyperbolic cotangent of `z`.
  result = T(0.5) * (ln(T(1.0) + T(1.0)/z) - ln(T(1.0) - T(1.0)/z))

func sech*[T](z: Complex[T]): Complex[T] =
  ## Returns the hyperbolic secant of `z`.
  result = T(2.0) / (exp(z) + exp(-z))

func arcsech*[T](z: Complex[T]): Complex[T] =
  ## Returns the inverse hyperbolic secant of `z`.
  result = ln(1.0/z + sqrt(T(1.0)/z+T(1.0)) * sqrt(T(1.0)/z-T(1.0)))

func csch*[T](z: Complex[T]): Complex[T] =
  ## Returns the hyperbolic cosecant of `z`.
  result = T(2.0) / (exp(z) - exp(-z))

func arccsch*[T](z: Complex[T]): Complex[T] =
  ## Returns the inverse hyperbolic cosecant of `z`.
  result = ln(T(1.0)/z + sqrt(T(1.0)/(z*z) + T(1.0)))

func phase*[T](z: Complex[T]): T =
  ## Returns the phase (or argument) of `z`, that is the angle in polar representation.
  ##
  ## | `result = arctan2(z.im, z.re)`
  arctan2(z.im, z.re)

func polar*[T](z: Complex[T]): tuple[r, phi: T] =
  ## Returns `z` in polar coordinates.
  ##
  ## | `result.r = abs(z)`
  ## | `result.phi = phase(z)`
  ##
  ## **See also:**
  ## * `rect func<#rect,T,T>`_ for the inverse operation
  (r: abs(z), phi: phase(z))

func rect*[T](r, phi: T): Complex[T] =
  ## Returns the complex number with polar coordinates `r` and `phi`.
  ##
  ## | `result.re = r * cos(phi)`
  ## | `result.im = r * sin(phi)`
  ##
  ## **See also:**
  ## * `polar func<#polar,Complex[T]>`_ for the inverse operation
  complex(r * cos(phi), r * sin(phi))

func almostEqual*[T: SomeFloat](x, y: Complex[T]; unitsInLastPlace: Natural = 4): bool =
  ## Checks if two complex values are almost equal, using the
  ## [machine epsilon](https://en.wikipedia.org/wiki/Machine_epsilon).
  ##
  ## Two complex values are considered almost equal if their real and imaginary
  ## components are almost equal.
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
  almostEqual(x.re, y.re, unitsInLastPlace = unitsInLastPlace) and
  almostEqual(x.im, y.im, unitsInLastPlace = unitsInLastPlace)

func `$`*(z: Complex): string =
  ## Returns `z`'s string representation as `"(re, im)"`.
  runnableExamples:
    doAssert $complex(1.0, 2.0) == "(1.0, 2.0)"

  result = "(" & $z.re & ", " & $z.im & ")"

proc formatValueAsTuple(result: var string; value: Complex; specifier: string) =
  ## Format implementation for `Complex` representing the value as a (real, imaginary) tuple.
  result.add "("
  formatValue(result, value.re, specifier)
  result.add ", "
  formatValue(result, value.im, specifier)
  result.add ")"

proc formatValueAsComplexNumber(result: var string; value: Complex; specifier: string) =
  ## Format implementation for `Complex` representing the value as a (RE+IMj) number
  ## By default, the real and imaginary parts are formatted using the general ('g') format
  let specifier = if specifier.contains({'e', 'E', 'f', 'F', 'g', 'G'}):
      specifier.replace("j")
    else:
      specifier.replace('j', 'g')
  result.add "("
  formatValue(result, value.re, specifier)
  if value.im >= 0 and not specifier.contains({'+', '-'}):
    result.add "+"
  formatValue(result, value.im, specifier)
  result.add "j)"

proc formatValue*(result: var string; value: Complex; specifier: string) =
  ## Standard format implementation for `Complex`. It makes little
  ## sense to call this directly, but it is required to exist
  ## by the `&` macro.
  ## For complex numbers, we add a specific 'j' specifier, which formats
  ## the value as (A+Bj) like in mathematics.
  if specifier.len == 0:
    result.add $value
  elif 'j' in specifier:
    formatValueAsComplexNumber(result, value, specifier)
  else:
    formatValueAsTuple(result, value, specifier)

{.pop.}

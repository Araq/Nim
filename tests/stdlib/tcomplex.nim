discard """
  matrix: "--mm:refc; --mm:orc"
"""

import std/[complex, math, strformat, formatfloat]
import std/assertions

proc `=~`[T](x, y: Complex[T]): bool =
  result = abs(x.re-y.re) < 1e-6 and abs(x.im-y.im) < 1e-6

proc `=~`[T](x: Complex[T]; y: T): bool =
  result = abs(x.re-y) < 1e-6 and abs(x.im) < 1e-6

let
  z: Complex64 = complex(0.0, 0.0)
  oo: Complex64 = complex(1.0, 1.0)
  a: Complex64 = complex(1.0, 2.0)
  b: Complex64 = complex(-1.0, -2.0)
  m1: Complex64 = complex(-1.0, 0.0)
  i: Complex64 = complex(0.0, 1.0)
  one: Complex64 = complex(1.0, 0.0)
  tt: Complex64 = complex(10.0, 20.0)
  ipi: Complex64 = complex(0.0, -PI)

doAssert(a/2.0 =~ complex(0.5, 1.0))
doAssert(a == a)
doAssert((a-a) == z)
doAssert((a+b) == z)
doAssert((a+b) =~ 0.0)
doAssert((a/b) == m1)
doAssert((1.0/a) =~ complex(0.2, -0.4))
doAssert((a*b) == complex(3.0, -4.0))
doAssert(10.0*a == tt)
doAssert(a*10.0 == tt)
doAssert(tt/10.0 == a)
doAssert(oo+(-1.0) == i)
doAssert( (-1.0)+oo == i)
doAssert(abs(oo) == sqrt(2.0))
doAssert(conjugate(a) == complex(1.0, -2.0))
doAssert(sqrt(m1) == i)
doAssert(exp(ipi) =~ m1)

doAssert(pow(a, b) =~ complex(-3.72999124927876, -1.68815826725068))
doAssert(pow(z, a) =~ complex(0.0, 0.0))
doAssert(pow(z, z) =~ complex(1.0, 0.0))
doAssert(pow(a, one) =~ a)
doAssert(pow(a, m1) =~ complex(0.2, -0.4))
doAssert(pow(a, 2.0) =~ complex(-3.0, 4.0))
doAssert(pow(a, 2) =~ complex(-3.0, 4.0))
doAssert(not(pow(a, 2.0) =~ a))

doAssert(ln(a) =~ complex(0.804718956217050, 1.107148717794090))
doAssert(log10(a) =~ complex(0.349485002168009, 0.480828578784234))
doAssert(log2(a) =~ complex(1.16096404744368, 1.59727796468811))

doAssert(sin(a) =~ complex(3.16577851321617, 1.95960104142161))
doAssert(cos(a) =~ complex(2.03272300701967, -3.05189779915180))
doAssert(tan(a) =~ complex(0.0338128260798967, 1.0147936161466335))
doAssert(cot(a) =~ 1.0 / tan(a))
doAssert(sec(a) =~ 1.0 / cos(a))
doAssert(csc(a) =~ 1.0 / sin(a))
doAssert(arcsin(a) =~ complex(0.427078586392476, 1.528570919480998))
doAssert(arccos(a) =~ complex(1.14371774040242, -1.52857091948100))
doAssert(arctan(a) =~ complex(1.338972522294494, 0.402359478108525))
doAssert(arccot(a) =~ complex(0.2318238045004031, -0.402359478108525))
doAssert(arcsec(a) =~ complex(1.384478272687081, 0.3965682301123288))
doAssert(arccsc(a) =~ complex(0.1863180541078155, -0.3965682301123291))

doAssert(cosh(a) =~ complex(-0.642148124715520, 1.068607421382778))
doAssert(sinh(a) =~ complex(-0.489056259041294, 1.403119250622040))
doAssert(tanh(a) =~ complex(1.1667362572409199, -0.243458201185725))
doAssert(sech(a) =~ 1.0 / cosh(a))
doAssert(csch(a) =~ 1.0 / sinh(a))
doAssert(coth(a) =~ 1.0 / tanh(a))
doAssert(arccosh(a) =~ complex(1.528570919480998, 1.14371774040242))
doAssert(arcsinh(a) =~ complex(1.469351744368185, 1.06344002357775))
doAssert(arctanh(a) =~ complex(0.173286795139986, 1.17809724509617))
doAssert(arcsech(a) =~ arccosh(1.0/a))
doAssert(arccsch(a) =~ arcsinh(1.0/a))
doAssert(arccoth(a) =~ arctanh(1.0/a))

doAssert(phase(a) == 1.1071487177940904)
let t = polar(a)
doAssert(rect(t.r, t.phi) =~ a)
doAssert(rect(1.0, 2.0) =~ complex(-0.4161468365471424, 0.9092974268256817))

doAssert(almostEqual(a, a + complex(1e-16, 1e-16)))
doAssert(almostEqual(a, a + complex(2e-15, 2e-15), unitsInLastPlace = 5))


let
  i64: Complex32 = complex(0.0f, 1.0f)
  a64: Complex32 = 2.0f*i64 + 1.0.float32
  b64: Complex32 = complex(-1.0'f32, -2.0'f32)

doAssert(a64 == a64)
doAssert(a64 == -b64)
doAssert(a64 + b64 =~ 0.0'f32)
doAssert(not(pow(a64, b64) =~ a64))
doAssert(pow(a64, 0.5f) =~ sqrt(a64))
doAssert(pow(a64, 2) =~ complex(-3.0'f32, 4.0'f32))
doAssert(sin(arcsin(b64)) =~ b64)
doAssert(cosh(arccosh(a64)) =~ a64)

doAssert(phase(a64) - 1.107149f < 1e-6)
let t64 = polar(a64)
doAssert(rect(t64.r, t64.phi) =~ a64)
doAssert(rect(1.0f, 2.0f) =~ complex(-0.4161468f, 0.90929742f))
doAssert(sizeof(a64) == 8)
doAssert(sizeof(a) == 16)

doAssert 123.0.im + 456.0 == complex64(456, 123)

let localA = complex(0.1'f32)
doAssert localA.im is float32

block: # bug #24666
  let z = complex64(1, 2)
  doAssert fmt"{z}" == "(1.0, 2.0)"

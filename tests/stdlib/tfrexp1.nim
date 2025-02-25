discard """
  matrix: "--mm:refc; --mm:orc"
  targets: "js c cpp"
"""

import std/math
import std/assertions

const manualTest = false

when manualTest:
  import strformat

proc frexp_test(lo, hi, step: float64) =
  var exp: int = 0
  var frac: float64

  var eps = 1e-15.float64

  var x: float64 = lo
  while x <= hi:
    frac = frexp(x.float, exp)
    let rslt = pow(2.0, float(exp)) * frac

    doAssert(abs(rslt - x) < eps)

    when manualTest:
      echo fmt("x: {x:10.3f} exp: {exp:4d} frac: {frac:24.20f} check: {$(abs(rslt - x) < eps):-5s} {rslt: 9.3f}")
    x += step

when manualTest:
  var exp: int
  var frac: float64

  for flval in [1.7976931348623157e+308, -1.7976931348623157e+308, # max, min float64
                3.4028234663852886e+38, -3.4028234663852886e+38,   # max, min float32
                4.9406564584124654e-324, -4.9406564584124654e-324, # smallest/largest positive/negative float64
                1.4012984643248171e-45, -1.4012984643248171e-45,   # smallest/largest positive/negative float32
                2.2250738585072014e-308, 1.1754943508222875e-38]:  # smallest normal float64/float32
    frac = frexp(flval, exp)
    echo fmt("{flval:25.16e}, {exp: 6d}, {frac: .20f} {frac * pow(2.0, float(exp)): .20e}")

  frexp_test(-1000.0, 1000.0, 0.0125)
else:
  frexp_test(-200000.0, 200000.0, 0.125)


doAssert frexp(8.0) == (0.5, 4)
doAssert frexp(-8.0) == (-0.5, 4)
doAssert frexp(0.0) == (0.0, 0)

block:
  var x: int
  doAssert frexp(5.0, x) == 0.625
  doAssert x == 3

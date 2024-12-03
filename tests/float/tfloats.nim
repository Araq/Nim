discard """
  targets: "c cpp js"
"""

#[
xxx merge all or most float tests into this file
]#

import std/[fenv, math, strutils]
import stdtest/testutils

proc equalsOrNaNs(a, b: float): bool =
  if isNaN(a): isNaN(b)
  elif a == 0:
    b == 0 and signbit(a) == signbit(b)
  else:
    a == b

template reject(a) =
  doAssertRaises(ValueError): discard parseFloat(a)

template main =
  block:
    proc test(a: string, b: float) =
      let a2 = a.parseFloat
      doAssert equalsOrNaNs(a2, b), $(a, a2, b)
    test "0.00_0001", 1E-6
    test "0.00__00_01", 1E-6
    test "0.0_01", 0.001
    test "0.00_000_1", 1E-6
    test "0.00000_1", 1E-6
    test "1_0.00_0001", 10.000001
    test "1__00.00_0001", 1_00.000001
    test "inf", Inf
    test "-inf", -Inf
    test "-Inf", -Inf
    test "-INF", -Inf
    test "NaN", NaN
    test "-nan", NaN
    test ".1", 0.1
    test "-.1", -0.1
    test "-0", -0.0
    test "-0", -0'f # see #18246, -0 won't work
    test ".1e-1", 0.1e-1
    test "0_1_2_3.0_1_2_3E+0_1_2", 123.0123e12
    test "0_1_2.e-0", 12e0
    test "0_1_2e-0", 12e0
    test "-0e0", -0.0
    test "-0e-0", -0.0

  reject "a"
  reject ""
  reject "e1"
  reject "infa"
  reject "infe1"
  reject "_"
  reject "1e"

  when false: # gray area; these numbers should probably be invalid
    reject "1_"
    reject "1_.0"
    reject "1.0_"

  block: # bugs mentioned in https://github.com/nim-lang/Nim/pull/18504#issuecomment-881635317
    block: # example 1
      let a = 0.1+0.2
      doAssert a != 0.3
      doAssert $a == "0.30000000000000004"
    block: # example 2
      const a = 0.1+0.2
      doAssert $($a, a) == """("0.30000000000000004", 0.30000000000000004)"""
    block: # example 3
      const a1 = 0.1+0.2
      let a2 = a1
      doAssert a1 != 0.3
      doAssert $[$a1, $a2] == """["0.30000000000000004", "0.30000000000000004"]"""


  when true:
    block: # bug #18148
      var a = 1.1'f32
      doAssert $a == "1.1", $a # was failing

    block: # bug #18400
      block:
        let a1 = 0.1'f32
        let a2 = 0.2'f32
        let a3 = a1 + a2
        var s = ""
        s.addFloat(a3)
        whenVMorJs: discard # xxx refs #12884
        do:
          doAssert a3 == 0.3'f32
          doAssert $a3 == "0.3"

      block:
        let a1 = 0.1
        let a2 = 0.2
        let a3 = a1 + a2
        var s = ""
        s.addFloat(a3)
        doAssert a3 != 0.3
        doAssert $a3 == "0.30000000000000004"

      block:
        var s = [-13.888888'f32]
        whenRuntimeJs: discard
        do:
          doAssert $s == "[-13.888888]"
          doAssert $s[0] == "-13.888888"

    block: # bug #7717
      proc test(f: float) =
        let f2 = $f
        let f3 = parseFloat(f2)
        doAssert equalsOrNaNs(f, f3), $(f, f2, f3)
      test 1.0 + epsilon(float64)
      test 1000000.0000000123
      test log2(100000.0)
      test maximumPositiveValue(float32)
      test maximumPositiveValue(float64)
      test minimumPositiveValue(float32)
      test minimumPositiveValue(float64)

    block: # bug #12884
      block: # example 1
        const x0: float32 = 1.32
        let x1 = 1.32
        let x2 = 1.32'f32
        var x3: float32 = 1.32
        doAssert $(x0, x1, x2, x3) == "(1.32, 1.32, 1.32, 1.32)"
      block: # example https://github.com/nim-lang/Nim/issues/12884#issuecomment-564967962
        let x = float(1.32'f32)
        when nimvm: discard # xxx prints 1.3
        else:
          when not defined(js):
            doAssert $x == "1.3200000524520874"
        doAssert $1.32 == "1.32"
        doAssert $1.32'f32 == "1.32"
        let x2 = 1.32'f32
        doAssert $x2 == "1.32"
      block:
        var x = 1.23456789012345'f32
        when nimvm:
          discard # xxx, refs #12884
        else:
          doAssert x == 1.2345679'f32
          doAssert $x == "1.2345679"

static: main()
main()

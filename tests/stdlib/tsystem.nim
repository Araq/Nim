discard """
  matrix: "--mm:refc; --mm:orc"
  targets: "c cpp js"
"""

import stdtest/testutils
import std/[assertions, formatfloat]

# TODO: in future work move existing `system` tests here, where they belong


template main =
  block: # closure
    proc outer() =
      var a = 0
      proc inner1 = a.inc
      proc inner2 = discard
      doAssert inner1 is "closure"
      doAssert inner2 isnot "closure"
      doAssert inner1 is (proc)
      doAssert inner2 is (proc)
      let inner1b = inner1
      doAssert inner1b is "closure"
      doAssert inner1b == inner1
    outer()

  block: # rawProc, rawProc, bug #17911
    proc outer() =
      var a = 0
      var b = 0
      proc inner1() = a.inc
      proc inner2() = a += 2
      proc inner3() = b.inc
      let inner1b = inner1
      doAssert inner2 != inner1
      doAssert inner3 != inner1
      whenVMorJs: discard
      do:
        doAssert rawProc(inner1b) == rawProc(inner1)
        doAssert rawProc(inner2) != rawProc(inner1)
        doAssert rawProc(inner3) != rawProc(inner1)

        doAssert rawEnv(inner1b) == rawEnv(inner1)
        doAssert rawEnv(inner2) == rawEnv(inner1) # because both use `a`
        # doAssert rawEnv(inner3) != rawEnv(inner1) # because `a` vs `b` # this doesn't hold
    outer()

  block: # system.delete
    block:
      var s = @[1]
      s.delete(0)
      doAssert s == @[]

    block:
      var s = @["foo", "bar"]
      s.delete(1)
      doAssert s == @["foo"]

    when false:
      var s: seq[string]
      doAssertRaises(IndexDefect):
        s.delete(0)

    block:
      doAssert not compiles(@["foo"].delete(-1))

    block: # bug #6710
      var s = @["foo"]
      s.delete(0)
      doAssert s == @[]

    when false: # bug #16544: deleting out of bounds index should raise
      var s = @["foo"]
      doAssertRaises(IndexDefect):
        s.delete(1)

static: main()
main()

# bug #19967
block:
  type
    X = object
      a: string
      b: set[char]
      c: int
      d: float
      e: int64


  var x = X(b: {'a'}, e: 10)

  var y = move x

  doAssert x.a == ""
  doAssert x.b == {}
  doAssert x.c == 0
  doAssert x.d == 0.0
  doAssert x.e == 0

  reset(y)

  doAssert y.a == ""
  doAssert y.b == {}
  doAssert y.c == 0
  doAssert y.d == 0.0
  doAssert y.e == 0

block:
  var x = 2
  var y = move x
  doAssert y == 2
  doAssert x == 0
  reset y
  doAssert y == 0

block:
  type
    X = object
      a: string
      b: float

  var y = X(b: 1314.521)

  reset(y)

  doAssert y.b == 0.0

block:
  type
    X = object
      a: string
      b: string

  var y = X(b: "1314")

  reset(y)

  doAssert y.b == ""

block:
  type
    X = object
      a: string
      b: seq[int]

  var y = X(b: @[1, 3])

  reset(y)

  doAssert y.b == @[]

block:
  type
    X = object
      a: string
      b: tuple[a: int, b: string]

  var y = X(b: (1, "cc"))

  reset(y)

  doAssert y.b == (0, "")

block:
  type
    Color = enum
      Red, Blue, Yellow
    X = object
      a: string
      b: set[Color]

  var y = X(b: {Red, Blue})

  reset(y)
  doAssert y.b == {}

block: # bug #20516
  type Foo = object
    x {.bitsize:4.}: uint
    y {.bitsize:4.}: uint

  when not defined(js):
    let a = create(Foo)

block: # bug #6549
  when not defined(js):
    block:
      const v = 18446744073709551615'u64

      doAssert $v == "18446744073709551615"
      doAssert $float32(v) == "1.8446744e+19", $float32(v)
      doAssert $float64(v) == "1.8446744073709552e+19", $float64(v)

    block:
      let v = 18446744073709551615'u64

      doAssert $v == "18446744073709551615"
      doAssert $float32(v) == "1.8446744e+19"
      doAssert $float64(v) == "1.8446744073709552e+19"

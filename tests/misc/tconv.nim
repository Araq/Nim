discard """
  matrix: "--warningAsError:EnumConv --warningAsError:CStringConv"
"""

from std/enumutils import items  # missing from the example code
from std/sequtils import toSeq

template reject(x) =
  static: doAssert(not compiles(x))
template accept(x) =
  static: doAssert(compiles(x))

reject:
    const x = int8(300)

reject:
    const x = int64(NaN)

type
    R = range[0..10]

reject:
    const x = R(11)

reject:
    const x = R(11.0)

reject:
    const x = R(NaN)

reject:
    const x = R(Inf)

type
    FloatRange = range[0'f..10'f]

reject:
    const x = FloatRange(-1'f)

reject:
    const x = FloatRange(-1)

reject:
    const x = FloatRange(NaN)

block:
    const x = float32(NaN)

type E = enum a, b, c

reject:
    const e = E(4)

block: # issue 3766

  type R = range[0..2]

  reject:
    type
      T[n: static[R]] = object
      V = T[3.R]

  reject:
    proc r(x: static[R]) =
      echo x
    r 3.R


block: # https://github.com/nim-lang/RFCs/issues/294
  type Koo = enum k1, k2
  type Goo = enum g1, g2

  accept: Koo(k2)
  accept: k2.Koo
  accept: k2.int.Goo

  reject: Goo(k2)
  reject: k2.Goo
  reject: k2.string

  {.push warningAsError[EnumConv]:off.}
  discard Goo(k2)
  accept: Goo(k2)
  accept: k2.Goo
  reject: k2.string
  {.pop.}

  reject: Goo(k2)
  reject: k2.Goo

  type KooRange = range[k2..k2]
  accept: KooRange(k2)
  accept: k2.KooRange
  let k2ranged: KooRange = k2
  accept: Koo(k2ranged)
  accept: k2ranged.Koo

reject:
  # bug #18550
  proc f(c: char): cstring =
    var x = newString(109*1024*1024)
    x[0] = c
    x

{.push warning[AnyEnumConv]:on, warningAsError[AnyEnumConv]:on.}

reject:
  type
    Foo = enum
      one
      three

  var va = 2
  var vb = va.Foo

{.pop.}

{.push warningAsError[HoleEnumConv]:on.}

reject:
  # bug #12815
  type
    Hole = enum
      one = 1
      three = 3

  var va = 2
  var vb = va.Hole

block: # bug #22844
  type
    A = enum
      a0 = 2
      a1 = 4
      a2
    B[T] = enum
      b0 = 2
      b1 = 4

  doAssert A.toSeq == [a0, a1, a2]
  doAssert B[float].toSeq == [B[float].b0, B[float].b1]

{.pop.}

discard """
  matrix: "--mm:refc; --mm:orc"
  targets: "c js"
"""

import std/enumutils
from std/sequtils import toSeq
import std/assertions

template main =
  block: # items
    type A = enum a0 = 2, a1 = 4, a2
    type B[T] = enum b0 = 2, b1 = 4
    doAssert A.toSeq == [a0, a1, a2]
    doAssert B[float].toSeq == [B[float].b0, B[float].b1]

  block: # symbolName
    block:
      type A2 = enum a20, a21, a22
      doAssert $a21 == "a21"
      doAssert a21.symbolName == "a21"
      proc `$`(a: A2): string = "foo"
      doAssert $a21 == "foo"
      doAssert a21.symbolName == "a21"
      var a = a22
      doAssert $a == "foo"
      doAssert a.symbolName == "a22"

    type B = enum
      b0 = (10, "kb0")
      b1 = "kb1"
      b2
    let b = B.low
    doAssert b.symbolName == "b0"
    doAssert $b == "kb0"
    static: doAssert B.high.symbolName == "b2"

  block:
    type
      Color = enum
        Red = "red", Yellow = "yellow", Blue = "blue"

    var s = Red
    doAssert symbolName(s) == "Red"
    var x: range[Red..Blue] = Yellow
    doAssert symbolName(x) == "Yellow"

static: main()
main()

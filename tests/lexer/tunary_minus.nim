discard """
  targets: "c cpp js"
"""

# Test numeric literals and handling of minus symbol

import std/[macros, strutils]
import std/private/jsutils

import mlexerutils

const one = 1
const minusOne = `-`(one)

# border cases that *should* generate compiler errors:
assertAST dedent """
  StmtList
    Asgn
      Ident "x"
      Command
        IntLit 4
        IntLit -1""":
  x = 4 -1
assertAST dedent """
  StmtList
    VarSection
      IdentDefs
        Ident "x"
        Ident "uint"
        IntLit -1""":
  var x: uint = -1
template bad() =
  x = 4 -1
doAssert not compiles(bad())

template main =
  block: # check when a minus (-) is a negative sign for a literal
    doAssert -1 == minusOne:
      "unable to parse a spaced-prefixed negative int"
    doAssert lispReprStr(-1) == """(IntLit -1)"""
    doAssert -1.0'f64 == minusOne.float64
    doAssert lispReprStr(-1.000'f64) == """(Float64Lit -1.0)"""
    doAssert lispReprStr( -1.000'f64) == """(Float64Lit -1.0)"""
    doAssert [-1].contains(minusOne):
      "unable to handle negatives after square bracket"
    doAssert lispReprStr([-1]) == """(Bracket (IntLit -1))"""
    doAssert (-1, 2)[0] == minusOne:
      "unable to handle negatives after parenthesis"
    doAssert lispReprStr((-1, 2)) == """(TupleConstr (IntLit -1) (IntLit 2))"""
    proc x(): int =
      var a = 1;-1  # the -1 should act as the return value
    doAssert x() == minusOne:
      "unable to handle negatives after semi-colon"

  block:
    doAssert -0b111 == -7
    doAssert -0xff == -255
    doAssert -128'i8 == (-128).int8
    doAssert $(-128'i8) == "-128"
    doAssert -32768'i16 == int16.low
    doAssert -2147483648'i32 == int32.low
    when int.sizeof > 4:
      doAssert -9223372036854775808 == int.low
    when hasWorkingInt64:
      doAssert -9223372036854775808 == int64.low

  block: # check when a minus (-) is an unary op
    doAssert -one == minusOne:
      "unable to a negative prior to identifier"

  block: # check when a minus (-) is a a subtraction op
    doAssert 4-1 == 3:
      "unable to handle subtraction sans surrounding spaces with a numeric literal"
    doAssert 4-one == 3:
      "unable to handle subtraction sans surrounding spaces with an identifier"
    doAssert 4 - 1 == 3:
      "unable to handle subtraction with surrounding spaces with a numeric literal"
    doAssert 4 - one == 3:
      "unable to handle subtraction with surrounding spaces with an identifier"

static: main()
main()

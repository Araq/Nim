discard """
  targets: "c cpp js"
"""

# Test tkStrNumLit

import std/[macros, strutils]
import mlexerutils

# AST checks

assertAST dedent """
  StmtList
    ProcDef
      AccQuoted
        Ident "\'"
        Ident "wrap"
      Empty
      Empty
      FormalParams
        Ident "string"
        IdentDefs
          Ident "number"
          Ident "string"
          Empty
      Empty
      Empty
      StmtList
        Asgn
          Ident "result"
          Infix
            Ident "&"
            Infix
              Ident "&"
              StrLit "[["
              Ident "number"
            StrLit "]]"""":
  proc `'wrap`(number: string): string =
    result = "[[" & number & "]]"

assertAST dedent """
  StmtList
    DotExpr
      RStrLit "-38383839292839283928392839283928392839283.928493849385935898243e-50000"
      Ident "\'wrap"""":
  -38383839292839283928392839283928392839283.928493849385935898243e-50000'wrap

proc `'wrap`(number: string): string = "[[" & number & "]]"
proc wrap2(number: string): string = "[[" & number & "]]"
doAssert lispReprStr(-1'wrap) == """(DotExpr (RStrLit "-1") (Ident "\'wrap"))"""

template main =
  block: # basic suffix usage
    template `'twrap`(number: string): untyped =
      number.`'wrap`
    proc extraContext(): string =
      22.40'wrap
    proc `*`(left, right: string): string =
      result = left & "times" & right
    proc `+`(left, right: string): string =
      result = left & "plus" & right

    doAssert 1'wrap == "[[1]]"
    doAssert -1'wrap == "[[-1]]":
      "unable to resolve a negative integer-suffix pattern"
    doAssert 12345.67890'wrap == "[[12345.67890]]"
    doAssert 1'wrap*1'wrap == "[[1]]times[[1]]":
      "unable to resolve an operator between two suffixed numeric literals"
    doAssert 1'wrap+ -1'wrap == "[[1]]plus[[-1]]":  # will generate a compiler warning about inconsistent spacing
      "unable to resolve a negative suffixed numeric literal following an operator"
    doAssert 1'wrap + -1'wrap == "[[1]]plus[[-1]]"
    doAssert 1'twrap == "[[1]]"
    doAssert extraContext() == "[[22.40]]":
      "unable to return a suffixed numeric literal by an implicit return"
    doAssert 0x5a3a'wrap == "[[0x5a3a]]"
    doAssert 0o5732'wrap == "[[0o5732]]"
    doAssert 0b0101111010101'wrap == "[[0b0101111010101]]"
    doAssert -38383839292839283928392839283928392839283.928493849385935898243e-50000'wrap == "[[-38383839292839283928392839283928392839283.928493849385935898243e-50000]]"
    doAssert 1234.56'wrap == "[[1234.56]]":
      "unable to properly account for context with suffixed numeric literals"

  block: # verify that the i64, f32, etc builtin suffixes still parse correctly
    const expectedF32: float32 = 123.125
    proc `'f9`(number: string): string =   # proc starts with 'f' just like 'f32'
      "[[" & number & "]]"
    proc `'f32a`(number: string): string =   # looks even more like 'f32'
      "[[" & number & "]]"
    proc `'d9`(number: string): string =   # proc starts with 'd' just like the d suffix
      "[[" & number & "]]"
    proc `'i9`(number: string): string =   # proc starts with 'i' just like 'i64'
      "[[" & number & "]]"
    proc `'u9`(number: string): string =   # proc starts with 'u' just like 'u8'
      "[[" & number & "]]"

    doAssert 123.125f32 == expectedF32:
      "failing to support non-quoted legacy f32 floating point suffix"
    doAssert 123.125'f32 == expectedF32
    doAssert 123.125e0'f32 == expectedF32
    doAssert 1234.56'wrap == 1234.56'f9
    doAssert 1234.56'wrap == 1234.56'f32a
    doAssert 1234.56'wrap == 1234.56'd9
    doAssert 1234.56'wrap == 1234.56'i9
    doAssert 1234.56'wrap == 1234.56'u9
    doAssert lispReprStr(1234.56'u9) == """(DotExpr (RStrLit "1234.56") (Ident "\'u9"))""":
      "failed to properly build AST for suffix that starts with u"
    doAssert -128'i8 == (-128).int8

  block: # case checks
    doAssert 1E2 == 100:
      "lexer not handling upper-case exponent"
    doAssert 1.0E2 == 100.0
    doAssert 1e2 == 100
    doAssert 0xdeadBEEF'wrap == "[[0xdeadBEEF]]":
      "lexer not maintaining original case"
    doAssert 0.1E12'wrap == "[[0.1E12]]"
    doAssert 0.0e12'wrap == "[[0.0e12]]"
    doAssert 0.0e+12'wrap == "[[0.0e+12]]"
    doAssert 0.0e-12'wrap == "[[0.0e-12]]"
    doAssert 0e-12'wrap == "[[0e-12]]"

  block: # macro and template usage
    template `'foo`(a: string): untyped = (a, 2)
    doAssert -12'foo == ("-12", 2)
    template `'fooplus`(a: string, b: int): untyped = (a, b)
    doAssert -12'fooplus(2) == ("-12", 2)
    template `'fooplusopt`(a: string, b: int = 99): untyped = (a, b)
    doAssert -12'fooplusopt(2) == ("-12", 2)
    doAssert -12'fooplusopt() == ("-12", 99)
    doAssert -12'fooplusopt == ("-12", 99)
    macro `'bar`(a: static string): untyped = newLit(a.repr)
    doAssert -12'bar == "\"-12\""
    macro deb(a): untyped = newLit(a.repr)
    doAssert deb(-12'bar) == "-12'bar"

  block: # bug 1 from https://github.com/nim-lang/Nim/pull/17020#issuecomment-803193947
    macro deb1(a): untyped = newLit a.repr
    macro deb2(a): untyped =
      a[1] = ident($a[1])
      newLit a.lispRepr
    doAssert deb1(-12'wrap) == "-12'wrap"
    doAssert deb1(-12'nonexistent) == "-12'nonexistent"
    doAssert deb2(-12'nonexistent) == """(DotExpr (RStrLit "-12") (Ident "\'nonexistent"))"""
    doAssert deb2(-12.wrap2) == """(DotExpr (IntLit -12) (Ident "wrap2"))"""
    doAssert deb2(-12'wrap) == """(DotExpr (RStrLit "-12") (Ident "\'wrap"))"""

  block: # bug 2 from https://github.com/nim-lang/Nim/pull/17020#issuecomment-803193947
    template toSuf(`'suf`): untyped =
      let x = -12'suf
      x
    doAssert toSuf(`'wrap`) == "[[-12]]"

  block: # bug 10 from https://github.com/nim-lang/Nim/pull/17020#issuecomment-803193947
    proc `myecho`(a: auto): auto = a
    template fn1(): untyped =
      let a = "abc"
      -12'wrap
    template fn2(): untyped =
      `myecho` -12'wrap
    template fn3(): untyped =
      -12'wrap
    doAssert fn1() == "[[-12]]"
    doAssert fn2() == "[[-12]]"
    doAssert fn3() == "[[-12]]"

    block: # bug 9 from https://github.com/nim-lang/Nim/pull/17020#issuecomment-803193947
      func wrap1(a: string): string = "{" & a & "}"
      func `'wrap3`(a: string): string = "{" & a & "}"
      macro metawrap(): untyped =
        result = quote do:
          let a1 {.inject.} = wrap1"-128"
          let a2 {.inject.} = -128'wrap3
      metawrap()
      doAssert a1 == "{-128}"
      doAssert a2 == "{-128}"

static: main()
main()

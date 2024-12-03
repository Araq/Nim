discard """
  matrix: "--mm:refc; --mm:orc"
  targets: "c cpp js"
  output: '''
PEG AST traversal output
------------------------
pkNonTerminal: Sum @(2, 3)
  pkSequence: (Product (('+' / '-') Product)*)
    pkNonTerminal: Product @(3, 7)
      pkSequence: (Value (('*' / '/') Value)*)
        pkNonTerminal: Value @(4, 5)
          pkOrderedChoice: (([0-9] [0-9]*) / ('(' Expr ')'))
            pkSequence: ([0-9] [0-9]*)
              pkCharChoice: [0-9]
              pkGreedyRepSet: [0-9]*
            pkSequence: ('(' Expr ')')
              pkChar: '('
              pkNonTerminal: Expr @(1, 4)
                pkNonTerminal: Sum @(2, 3)
              pkChar: ')'
        pkGreedyRep: (('*' / '/') Value)*
          pkSequence: (('*' / '/') Value)
            pkOrderedChoice: ('*' / '/')
              pkChar: '*'
              pkChar: '/'
            pkNonTerminal: Value @(4, 5)
    pkGreedyRep: (('+' / '-') Product)*
      pkSequence: (('+' / '-') Product)
        pkOrderedChoice: ('+' / '-')
          pkChar: '+'
          pkChar: '-'
        pkNonTerminal: Product @(3, 7)

Event parser output
-------------------
@[5.0]
+
@[5.0, 3.0]
@[8.0]

/
@[8.0, 2.0]
@[4.0]

-
@[4.0, 7.0]
-*
@[4.0, 7.0, 22.0]
@[4.0, 154.0]
-
@[-150.0]
'''
"""

when defined(nimHasEffectsOf):
  {.experimental: "strictEffects".}

import std/[strutils, streams, pegs, assertions]

const
  indent = "  "

let
  pegAst = """
Expr    <- Sum
Sum     <- Product (('+' / '-')Product)*
Product <- Value (('*' / '/')Value)*
Value   <- [0-9]+ / '(' Expr ')'
  """.peg
  txt = "(5+3)/2-7*22"

block:
  var
    outp = newStringStream()
    processed: seq[string] = @[]

  proc prt(outp: Stream, kind: PegKind, s: string; level: int = 0) =
    outp.writeLine indent.repeat(level) & "$1: $2" % [$kind, s]

  proc recLoop(p: Peg, level: int = 0) =
    case p.kind
    of pkEmpty..pkWhitespace:
      discard
    of pkTerminal, pkTerminalIgnoreCase, pkTerminalIgnoreStyle:
      outp.prt(p.kind, $p, level)
    of pkChar, pkGreedyRepChar:
      outp.prt(p.kind, $p, level)
    of pkCharChoice, pkGreedyRepSet:
      outp.prt(p.kind, $p, level)
    of pkNonTerminal:
      outp.prt(p.kind,
        "$1 @($3, $4)" % [p.nt.name, $p.nt.rule.kind, $p.nt.line, $p.nt.col], level)
      if not(p.nt.name in processed):
        processed.add p.nt.name
        p.nt.rule.recLoop level+1
    of pkBackRef..pkBackRefIgnoreStyle:
      outp.prt(p.kind, $p, level)
    else:
      outp.prt(p.kind, $p, level)
      for s in items(p):
        s.recLoop level+1

  pegAst.recLoop
  echo "PEG AST traversal output"
  echo "------------------------"
  echo outp.data

block:
  var
    pStack {.threadvar.}: seq[string]
    valStack {.threadvar.}: seq[float]
    opStack {.threadvar.}: string
  let
    parseArithExpr = pegAst.eventParser:
      pkNonTerminal:
        enter:
          pStack.add p.nt.name
        leave:
          pStack.setLen pStack.high
          if length > 0:
            let matchStr = s.substr(start, start+length-1)
            case p.nt.name
            of "Value":
              try:
                valStack.add matchStr.parseFloat
                echo valStack
              except ValueError:
                discard
            of "Sum", "Product":
              try:
                let val {.used.} = matchStr.parseFloat
              except ValueError:
                if valStack.len > 1 and opStack.len > 0:
                  valStack[^2] = case opStack[^1]
                  of '+': valStack[^2] + valStack[^1]
                  of '-': valStack[^2] - valStack[^1]
                  of '*': valStack[^2] * valStack[^1]
                  else: valStack[^2] / valStack[^1]
                  valStack.setLen valStack.high
                  echo valStack
                  opStack.setLen opStack.high
                  echo opStack
      pkChar:
        leave:
          if length == 1 and "Value" != pStack[^1]:
            let matchChar = s[start]
            opStack.add matchChar
            echo opStack
  echo "Event parser output"
  echo "-------------------"
  let pLen = parseArithExpr(txt)
  doAssert txt.len == pLen


import std/importutils

block:
  proc pegsTest() =
    privateAccess(NonTerminal)
    privateAccess(Captures)

    if "test" =~ peg"s <- {{\ident}}": # bug #19104
      doAssert matches[0] == "test"
      doAssert matches[1] == "test", $matches[1]

    doAssert escapePeg("abc''def'") == r"'abc'\x27\x27'def'\x27"
    doAssert match("(a b c)", peg"'(' @ ')'")
    doAssert match("W_HI_Le", peg"\y 'while'")
    doAssert(not match("W_HI_L", peg"\y 'while'"))
    doAssert(not match("W_HI_Le", peg"\y v'while'"))
    doAssert match("W_HI_Le", peg"y'while'")

    doAssert($ +digits == $peg"\d+")
    doAssert "0158787".match(peg"\d+")
    doAssert "ABC 0232".match(peg"\w+\s+\d+")
    doAssert "ABC".match(peg"\d+ / \w+")

    var accum: seq[string] = @[]
    for word in split("00232this02939is39an22example111", peg"\d+"):
      accum.add(word)
    doAssert(accum == @["this", "is", "an", "example"])

    doAssert matchLen("key", ident) == 3

    var pattern = sequence(ident, *whitespace, term('='), *whitespace, ident)
    doAssert matchLen("key1=  cal9", pattern) == 11

    var ws = newNonTerminal("ws", 1, 1)
    ws.rule = *whitespace

    var expr = newNonTerminal("expr", 1, 1)
    expr.rule = sequence(capture(ident), *sequence(
                  nonterminal(ws), term('+'), nonterminal(ws), nonterminal(expr)))

    var c: Captures = default(Captures)
    var s = "a+b +  c +d+e+f"
    doAssert rawMatch(s, expr.rule, 0, c) == len(s)
    var a = ""
    for i in 0..c.ml-1:
      a.add(substr(s, c.matches[i][0], c.matches[i][1]))
    doAssert a == "abcdef"
    #echo expr.rule

    #const filename = "lib/devel/peg/grammar.txt"
    #var grammar = parsePeg(newFileStream(filename, fmRead), filename)
    #echo "a <- [abc]*?".match(grammar)
    doAssert find("_____abc_______", term("abc"), 2) == 5
    doAssert match("_______ana", peg"A <- 'ana' / . A")
    doAssert match("abcs%%%", peg"A <- ..A / .A / '%'")

    var matches: array[0..MaxSubpatterns-1, string] = default(array[0..MaxSubpatterns-1, string])
    if "abc" =~ peg"{'a'}'bc' 'xyz' / {\ident}":
      doAssert matches[0] == "abc"
    else:
      doAssert false

    var g2 = peg"""S <- A B / C D
                   A <- 'a'+
                   B <- 'b'+
                   C <- 'c'+
                   D <- 'd'+
                """
    doAssert($g2 == "((A B) / (C D))")
    doAssert match("cccccdddddd", g2)
    doAssert("var1=key; var2=key2".replacef(peg"{\ident}'='{\ident}", "$1<-$2$2") ==
           "var1<-keykey; var2<-key2key2")
    doAssert("var1=key; var2=key2".replace(peg"{\ident}'='{\ident}", "$1<-$2$2") ==
           "$1<-$2$2; $1<-$2$2")
    doAssert "var1=key; var2=key2".endsWith(peg"{\ident}'='{\ident}")

    if "aaaaaa" =~ peg"'aa' !. / ({'a'})+":
      doAssert matches[0] == "a"
    else:
      doAssert false

    if match("abcdefg", peg"c {d} ef {g}", matches, 2):
      doAssert matches[0] == "d"
      doAssert matches[1] == "g"
    else:
      doAssert false

    accum = @[]
    for x in findAll("abcdef", peg".", 3):
      accum.add(x)
    doAssert(accum == @["d", "e", "f"])

    for x in findAll("abcdef", peg"^{.}", 3):
      doAssert x == "d"

    if "f(a, b)" =~ peg"{[0-9]+} / ({\ident} '(' {@} ')')":
      doAssert matches[0] == "f"
      doAssert matches[1] == "a, b"
    else:
      doAssert false

    doAssert match("eine übersicht und außerdem", peg"(\letter \white*)+")
    # ß is not a lower cased letter?!
    doAssert match("eine übersicht und auerdem", peg"(\lower \white*)+")
    doAssert match("EINE ÜBERSICHT UND AUSSERDEM", peg"(\upper \white*)+")
    doAssert(not match("456678", peg"(\letter)+"))

    doAssert("var1 = key; var2 = key2".replacef(
      peg"\skip(\s*) {\ident}'='{\ident}", "$1<-$2$2") ==
           "var1<-keykey;var2<-key2key2")

    doAssert match("prefix/start", peg"^start$", 7)

    if "foo" =~ peg"{'a'}?.*":
      doAssert matches[0].len == 0
    else: doAssert false

    if "foo" =~ peg"{''}.*":
      doAssert matches[0] == ""
    else: doAssert false

    if "foo" =~ peg"{'foo'}":
      doAssert matches[0] == "foo"
    else: doAssert false

    let empty_test = peg"^\d*"
    let str = "XYZ"

    doAssert(str.find(empty_test) == 0)
    doAssert(str.match(empty_test))

    proc handleMatches(m: int, n: int, c: openArray[string]): string =
      result = ""

      if m > 0:
        result.add ", "

      result.add case n:
        of 2: toLowerAscii(c[0]) & ": '" & c[1] & "'"
        of 1: toLowerAscii(c[0]) & ": ''"
        else: ""

    doAssert("Var1=key1;var2=Key2;   VAR3".
      replace(peg"{\ident}('='{\ident})* ';'* \s*",
      handleMatches) == "var1: 'key1', var2: 'Key2', var3: ''")


    doAssert "test1".match(peg"""{@}$""")
    doAssert "test2".match(peg"""{(!$ .)*} $""")

    doAssert "abbb".match(peg"{a} {b} $2 $^1")
    doAssert "abBA".match(peg"{a} {b} i$2 i$^2")

    doAssert "abba".match(peg"{a} {b} $^1 {} $^1")

    block:
      let grammar = peg"""
program <- {''} stmt* $
stmt <- call / block
call <- 'call()' EOL
EOL <- \n / $
block <- 'block:' \n indBody
indBody <- {$^1 ' '+} stmt ($^1 stmt)* {}
"""
      let program = """
call()
block:
  block:
    call()
    call()
  call()
call()
"""
      var c: Captures = default(Captures)
      doAssert program.len == program.rawMatch(grammar, 0, c)
      doAssert c.ml == 1

    block:
      # bug #21632

      let p = peg"""
        atext <- \w / \d
      """

      doAssert "a".match(p)
      doAssert "1".match(p)

  pegsTest()
  static:
    pegsTest()

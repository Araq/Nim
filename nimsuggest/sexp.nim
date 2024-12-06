#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Andreas Rumpf, Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## **Note:** Import ``nimsuggest/sexp`` to use this module

import
  hashes, strutils, lexbase, streams, unicode, macros

import std/private/decode_helpers

when defined(nimPreviewSlimSystem):
  import std/[assertions, formatfloat]

type
  SexpEventKind* = enum  ## enumeration of all events that may occur when parsing
    sexpError,           ## an error occurred during parsing
    sexpEof,             ## end of file reached
    sexpString,          ## a string literal
    sexpSymbol,          ## a symbol
    sexpInt,             ## an integer literal
    sexpFloat,           ## a float literal
    sexpNil,             ## the value ``nil``
    sexpDot,             ## the dot to separate car/cdr
    sexpListStart,       ## start of a list: the ``(`` token
    sexpListEnd,         ## end of a list: the ``)`` token

  TTokKind = enum        # must be synchronized with SexpEventKind!
    tkError,
    tkEof,
    tkString,
    tkSymbol,
    tkInt,
    tkFloat,
    tkNil,
    tkDot,
    tkParensLe,
    tkParensRi
    tkSpace

  SexpError* = enum        ## enumeration that lists all errors that can occur
    errNone,               ## no error
    errInvalidToken,       ## invalid token
    errParensRiExpected,    ## ``)`` expected
    errQuoteExpected,      ## ``"`` expected
    errEofExpected,        ## EOF expected

  SexpParser* = object of BaseLexer ## the parser object.
    a: string
    tok: TTokKind
    kind: SexpEventKind
    err: SexpError

const
  errorMessages: array[SexpError, string] = [
    "no error",
    "invalid token",
    "')' expected",
    "'\"' or \"'\" expected",
    "EOF expected",
  ]
  tokToStr: array[TTokKind, string] = [
    "invalid token",
    "EOF",
    "string literal",
    "symbol",
    "int literal",
    "float literal",
    "nil",
    ".",
    "(", ")", "space"
  ]

proc close*(my: var SexpParser) {.inline.} =
  ## closes the parser `my` and its associated input stream.
  lexbase.close(my)

proc str*(my: SexpParser): string {.inline.} =
  ## returns the character data for the events: ``sexpInt``, ``sexpFloat``,
  ## ``sexpString``
  assert(my.kind in {sexpInt, sexpFloat, sexpString})
  result = my.a

proc getInt*(my: SexpParser): BiggestInt {.inline.} =
  ## returns the number for the event: ``sexpInt``
  assert(my.kind == sexpInt)
  result = parseBiggestInt(my.a)

proc getFloat*(my: SexpParser): float {.inline.} =
  ## returns the number for the event: ``sexpFloat``
  assert(my.kind == sexpFloat)
  result = parseFloat(my.a)

proc kind*(my: SexpParser): SexpEventKind {.inline.} =
  ## returns the current event type for the SEXP parser
  result = my.kind

proc getColumn*(my: SexpParser): int {.inline.} =
  ## get the current column the parser has arrived at.
  result = getColNumber(my, my.bufpos)

proc getLine*(my: SexpParser): int {.inline.} =
  ## get the current line the parser has arrived at.
  result = my.lineNumber

proc errorMsg*(my: SexpParser): string =
  ## returns a helpful error message for the event ``sexpError``
  assert(my.kind == sexpError)
  result = "($1, $2) Error: $3" % [$getLine(my), $getColumn(my), errorMessages[my.err]]

proc errorMsgExpected*(my: SexpParser, e: string): string =
  ## returns an error message "`e` expected" in the same format as the
  ## other error messages
  result = "($1, $2) Error: $3" % [$getLine(my), $getColumn(my), e & " expected"]

proc parseString(my: var SexpParser): TTokKind =
  result = tkString
  var pos = my.bufpos + 1
  while true:
    case my.buf[pos]
    of '\0':
      my.err = errQuoteExpected
      result = tkError
      break
    of '"':
      inc(pos)
      break
    of '\\':
      case my.buf[pos+1]
      of '\\', '"', '\'', '/':
        add(my.a, my.buf[pos+1])
        inc(pos, 2)
      of 'b':
        add(my.a, '\b')
        inc(pos, 2)
      of 'f':
        add(my.a, '\f')
        inc(pos, 2)
      of 'n':
        add(my.a, '\L')
        inc(pos, 2)
      of 'r':
        add(my.a, '\C')
        inc(pos, 2)
      of 't':
        add(my.a, '\t')
        inc(pos, 2)
      of 'u':
        inc(pos, 2)
        var r: int = 0
        if handleHexChar(my.buf[pos], r): inc(pos)
        if handleHexChar(my.buf[pos], r): inc(pos)
        if handleHexChar(my.buf[pos], r): inc(pos)
        if handleHexChar(my.buf[pos], r): inc(pos)
        add(my.a, toUTF8(Rune(r)))
      else:
        # don't bother with the error
        add(my.a, my.buf[pos])
        inc(pos)
    of '\c':
      pos = lexbase.handleCR(my, pos)
      add(my.a, '\c')
    of '\L':
      pos = lexbase.handleLF(my, pos)
      add(my.a, '\L')
    else:
      add(my.a, my.buf[pos])
      inc(pos)
  my.bufpos = pos # store back

proc parseNumber(my: var SexpParser) =
  var pos = my.bufpos
  if my.buf[pos] == '-':
    add(my.a, '-')
    inc(pos)
  if my.buf[pos] == '.':
    add(my.a, "0.")
    inc(pos)
  else:
    while my.buf[pos] in Digits:
      add(my.a, my.buf[pos])
      inc(pos)
    if my.buf[pos] == '.':
      add(my.a, '.')
      inc(pos)
  # digits after the dot:
  while my.buf[pos] in Digits:
    add(my.a, my.buf[pos])
    inc(pos)
  if my.buf[pos] in {'E', 'e'}:
    add(my.a, my.buf[pos])
    inc(pos)
    if my.buf[pos] in {'+', '-'}:
      add(my.a, my.buf[pos])
      inc(pos)
    while my.buf[pos] in Digits:
      add(my.a, my.buf[pos])
      inc(pos)
  my.bufpos = pos

proc parseSymbol(my: var SexpParser) =
  var pos = my.bufpos
  if my.buf[pos] in IdentStartChars:
    while my.buf[pos] in IdentChars:
      add(my.a, my.buf[pos])
      inc(pos)
  my.bufpos = pos

proc getTok(my: var SexpParser): TTokKind =
  setLen(my.a, 0)
  case my.buf[my.bufpos]
  of '-', '0'..'9': # numbers that start with a . are not parsed
                    # correctly.
    parseNumber(my)
    if {'.', 'e', 'E'} in my.a:
      result = tkFloat
    else:
      result = tkInt
  of '"': #" # gotta fix nim-mode
    result = parseString(my)
  of '(':
    inc(my.bufpos)
    result = tkParensLe
  of ')':
    inc(my.bufpos)
    result = tkParensRi
  of '\0':
    result = tkEof
  of 'a'..'z', 'A'..'Z', '_':
    parseSymbol(my)
    if my.a == "nil":
      result = tkNil
    else:
      result = tkSymbol
  of ' ':
    result = tkSpace
    inc(my.bufpos)
  of '.':
    result = tkDot
    inc(my.bufpos)
  else:
    inc(my.bufpos)
    result = tkError
  my.tok = result

# ------------- higher level interface ---------------------------------------

type
  SexpNodeKind* = enum ## possible SEXP node types
    SNil,
    SInt,
    SFloat,
    SString,
    SSymbol,
    SList,
    SCons

  SexpNode* = ref SexpNodeObj ## SEXP node
  SexpNodeObj* {.acyclic.} = object
    case kind*: SexpNodeKind
    of SString:
      str*: string
    of SSymbol:
      symbol*: string
    of SInt:
      num*: BiggestInt
    of SFloat:
      fnum*: float
    of SList:
      elems*: seq[SexpNode]
    of SCons:
      car: SexpNode
      cdr: SexpNode
    of SNil:
      discard

  Cons = tuple[car: SexpNode, cdr: SexpNode]

  SexpParsingError* = object of ValueError ## is raised for a SEXP error

proc raiseParseErr*(p: SexpParser, msg: string) {.noinline, noreturn.} =
  ## raises an `ESexpParsingError` exception.
  raise newException(SexpParsingError, errorMsgExpected(p, msg))

proc newSString*(s: string): SexpNode =
  ## Creates a new `SString SexpNode`.
  result = SexpNode(kind: SString, str: s)

proc newSInt*(n: BiggestInt): SexpNode =
  ## Creates a new `SInt SexpNode`.
  result = SexpNode(kind: SInt, num: n)

proc newSFloat*(n: float): SexpNode =
  ## Creates a new `SFloat SexpNode`.
  result = SexpNode(kind: SFloat, fnum: n)

proc newSNil*(): SexpNode =
  ## Creates a new `SNil SexpNode`.
  result = SexpNode(kind: SNil)

proc newSCons*(car, cdr: SexpNode): SexpNode =
  ## Creates a new `SCons SexpNode`
  result = SexpNode(kind: SCons, car: car, cdr: cdr)

proc newSList*(): SexpNode =
  ## Creates a new `SList SexpNode`
  result = SexpNode(kind: SList, elems: @[])

proc newSSymbol*(s: string): SexpNode =
  result = SexpNode(kind: SSymbol, symbol: s)

proc getStr*(n: SexpNode, default: string = ""): string =
  ## Retrieves the string value of a `SString SexpNode`.
  ##
  ## Returns ``default`` if ``n`` is not a ``SString``.
  if n.kind != SString: return default
  else: return n.str

proc getNum*(n: SexpNode, default: BiggestInt = 0): BiggestInt =
  ## Retrieves the int value of a `SInt SexpNode`.
  ##
  ## Returns ``default`` if ``n`` is not a ``SInt``.
  if n.kind != SInt: return default
  else: return n.num

proc getFNum*(n: SexpNode, default: float = 0.0): float =
  ## Retrieves the float value of a `SFloat SexpNode`.
  ##
  ## Returns ``default`` if ``n`` is not a ``SFloat``.
  if n.kind != SFloat: return default
  else: return n.fnum

proc getSymbol*(n: SexpNode, default: string = ""): string =
  ## Retrieves the int value of a `SList SexpNode`.
  ##
  ## Returns ``default`` if ``n`` is not a ``SList``.
  if n.kind != SSymbol: return default
  else: return n.symbol

proc getElems*(n: SexpNode, default: seq[SexpNode] = @[]): seq[SexpNode] =
  ## Retrieves the int value of a `SList SexpNode`.
  ##
  ## Returns ``default`` if ``n`` is not a ``SList``.
  if n.kind == SNil: return @[]
  elif n.kind != SList: return default
  else: return n.elems

proc getCons*(n: SexpNode, defaults: Cons = (newSNil(), newSNil())): Cons =
  ## Retrieves the cons value of a `SList SexpNode`.
  ##
  ## Returns ``default`` if ``n`` is not a ``SList``.
  if n.kind == SCons: return (n.car, n.cdr)
  elif n.kind == SList: return (n.elems[0], n.elems[1])
  else: return defaults

proc sexp*(s: string): SexpNode =
  ## Generic constructor for SEXP data. Creates a new `SString SexpNode`.
  result = SexpNode(kind: SString, str: s)

proc sexp*(n: BiggestInt): SexpNode =
  ## Generic constructor for SEXP data. Creates a new `SInt SexpNode`.
  result = SexpNode(kind: SInt, num: n)

proc sexp*(n: float): SexpNode =
  ## Generic constructor for SEXP data. Creates a new `SFloat SexpNode`.
  result = SexpNode(kind: SFloat, fnum: n)

proc sexp*(b: bool): SexpNode =
  ## Generic constructor for SEXP data. Creates a new `SSymbol
  ## SexpNode` with value t or `SNil SexpNode`.
  if b:
    result = SexpNode(kind: SSymbol, symbol: "t")
  else:
    result = SexpNode(kind: SNil)

proc sexp*(elements: openArray[SexpNode]): SexpNode =
  ## Generic constructor for SEXP data. Creates a new `SList SexpNode`
  result = SexpNode(kind: SList)
  newSeq(result.elems, elements.len)
  for i, p in pairs(elements): result.elems[i] = p

proc sexp*(s: SexpNode): SexpNode =
  result = s

proc toSexp(x: NimNode): NimNode {.compileTime.} =
  case x.kind
  of nnkBracket:
    result = newNimNode(nnkBracket)
    for i in 0 ..< x.len:
      result.add(toSexp(x[i]))

  else:
    result = x

  result = prefix(result, "sexp")

macro convertSexp*(x: untyped): untyped =
  ## Convert an expression to a SexpNode directly, without having to specify
  ## `%` for every element.
  result = toSexp(x)

func `==`* (a, b: SexpNode): bool =
  ## Check two nodes for equality
  if a.isNil:
    if b.isNil: return true
    return false
  elif b.isNil or a.kind != b.kind:
    return false
  else:
    return case a.kind
    of SString:
      a.str == b.str
    of SInt:
      a.num == b.num
    of SFloat:
      a.fnum == b.fnum
    of SNil:
      true
    of SList:
      a.elems == b.elems
    of SSymbol:
      a.symbol == b.symbol
    of SCons:
      a.car == b.car and a.cdr == b.cdr

proc hash* (n:SexpNode): Hash =
  ## Compute the hash for a SEXP node
  case n.kind
  of SList:
    result = hash(n.elems)
  of SInt:
    result = hash(n.num)
  of SFloat:
    result = hash(n.fnum)
  of SString:
    result = hash(n.str)
  of SNil:
    result = hash(0)
  of SSymbol:
    result = hash(n.symbol)
  of SCons:
    result = hash(n.car) !& hash(n.cdr)

proc len*(n: SexpNode): int =
  ## If `n` is a `SList`, it returns the number of elements.
  ## If `n` is a `JObject`, it returns the number of pairs.
  ## Else it returns 0.
  case n.kind
  of SList: result = n.elems.len
  else: result = 0

proc `[]`*(node: SexpNode, index: int): SexpNode =
  ## Gets the node at `index` in a List. Result is undefined if `index`
  ## is out of bounds
  assert(not isNil(node))
  assert(node.kind == SList)
  return node.elems[index]

proc add*(father, child: SexpNode) =
  ## Adds `child` to a SList node `father`.
  assert father.kind == SList
  father.elems.add(child)

# ------------- pretty printing ----------------------------------------------

proc indent(s: var string, i: int) =
  s.add(spaces(i))

proc newIndent(curr, indent: int, ml: bool): int =
  if ml: return curr + indent
  else: return indent

proc nl(s: var string, ml: bool) =
  if ml: s.add("\n")

proc escapeJson*(s: string): string =
  ## Converts a string `s` to its JSON representation.
  result = newStringOfCap(s.len + s.len shr 3)
  result.add("\"")
  for x in runes(s):
    var r = int(x)
    if r >= 32 and r <= 127:
      var c = chr(r)
      case c
      of '"': result.add("\\\"") #" # gotta fix nim-mode
      of '\\': result.add("\\\\")
      else: result.add(c)
    else:
      result.add("\\u")
      result.add(toHex(r, 4))
  result.add("\"")

proc copy*(p: SexpNode): SexpNode =
  ## Performs a deep copy of `a`.
  case p.kind
  of SString:
    result = newSString(p.str)
  of SInt:
    result = newSInt(p.num)
  of SFloat:
    result = newSFloat(p.fnum)
  of SNil:
    result = newSNil()
  of SSymbol:
    result = newSSymbol(p.symbol)
  of SList:
    result = newSList()
    for i in items(p.elems):
      result.elems.add(copy(i))
  of SCons:
    result = newSCons(copy(p.car), copy(p.cdr))

proc toPretty(result: var string, node: SexpNode, indent = 2, ml = true,
              lstArr = false, currIndent = 0) =
  case node.kind
  of SString:
    if lstArr: result.indent(currIndent)
    result.add(escapeJson(node.str))
  of SInt:
    if lstArr: result.indent(currIndent)
    result.addInt(node.num)
  of SFloat:
    if lstArr: result.indent(currIndent)
    result.addFloat(node.fnum)
  of SNil:
    if lstArr: result.indent(currIndent)
    result.add("nil")
  of SSymbol:
    if lstArr: result.indent(currIndent)
    result.add(node.symbol)
  of SList:
    if lstArr: result.indent(currIndent)
    if len(node.elems) != 0:
      result.add("(")
      result.nl(ml)
      for i in 0..len(node.elems)-1:
        if i > 0:
          result.add(" ")
          result.nl(ml) # New Line
        toPretty(result, node.elems[i], indent, ml,
            true, newIndent(currIndent, indent, ml))
      result.nl(ml)
      result.indent(currIndent)
      result.add(")")
    else: result.add("nil")
  of SCons:
    if lstArr: result.indent(currIndent)
    result.add("(")
    toPretty(result, node.car, indent, ml,
        true, newIndent(currIndent, indent, ml))
    result.add(" . ")
    toPretty(result, node.cdr, indent, ml,
        true, newIndent(currIndent, indent, ml))
    result.add(")")

proc pretty*(node: SexpNode, indent = 2): string =
  ## Converts `node` to its Sexp Representation, with indentation and
  ## on multiple lines.
  result = ""
  toPretty(result, node, indent)

proc `$`*(node: SexpNode): string =
  ## Converts `node` to its SEXP Representation on one line.
  result = ""
  toPretty(result, node, 0, false)

iterator items*(node: SexpNode): SexpNode =
  ## Iterator for the items of `node`. `node` has to be a SList.
  assert node.kind == SList
  for i in items(node.elems):
    yield i

iterator mitems*(node: var SexpNode): var SexpNode =
  ## Iterator for the items of `node`. `node` has to be a SList. Items can be
  ## modified.
  assert node.kind == SList
  for i in mitems(node.elems):
    yield i

proc eat(p: var SexpParser, tok: TTokKind) =
  if p.tok == tok: discard getTok(p)
  else: raiseParseErr(p, tokToStr[tok])

proc parseSexp(p: var SexpParser): SexpNode =
  ## Parses SEXP from a SEXP Parser `p`.
  case p.tok
  of tkString:
    # we capture 'p.a' here, so we need to give it a fresh buffer afterwards:
    result = SexpNode(kind: SString, str: move p.a)
    discard getTok(p)
  of tkInt:
    result = newSInt(parseBiggestInt(p.a))
    discard getTok(p)
  of tkFloat:
    result = newSFloat(parseFloat(p.a))
    discard getTok(p)
  of tkNil:
    result = newSNil()
    discard getTok(p)
  of tkSymbol:
    result = SexpNode(kind: SSymbol, symbol: move p.a)
    discard getTok(p)
  of tkParensLe:
    result = newSList()
    discard getTok(p)
    while p.tok notin {tkParensRi, tkDot}:
      result.add(parseSexp(p))
      if p.tok != tkSpace: break
      discard getTok(p)
    if p.tok == tkDot:
      eat(p, tkDot)
      eat(p, tkSpace)
      result.add(parseSexp(p))
      result = newSCons(result[0], result[1])
    eat(p, tkParensRi)
  of tkSpace, tkDot, tkError, tkParensRi, tkEof:
    raiseParseErr(p, "(")

proc open*(my: var SexpParser, input: Stream) =
  ## initializes the parser with an input stream.
  lexbase.open(my, input)
  my.kind = sexpError
  my.a = ""

proc parseSexp*(s: Stream): SexpNode =
  ## Parses from a buffer `s` into a `SexpNode`.
  var p: SexpParser = SexpParser()
  p.open(s)
  discard getTok(p) # read first token
  result = p.parseSexp()
  p.close()

proc parseSexp*(buffer: string): SexpNode =
  ## Parses Sexp from `buffer`.
  result = parseSexp(newStringStream(buffer))

when isMainModule:
  let testSexp = parseSexp("""(1 (98 2) nil (2) foobar "foo" 9.234)""")
  assert(testSexp[0].getNum == 1)
  assert(testSexp[1][0].getNum == 98)
  assert(testSexp[2].getElems == @[])
  assert(testSexp[4].getSymbol == "foobar")
  assert(testSexp[5].getStr == "foo")

  let alist = parseSexp("""((1 . 2) (2 . "foo"))""")
  assert(alist[0].getCons.car.getNum == 1)
  assert(alist[0].getCons.cdr.getNum == 2)
  assert(alist[1].getCons.cdr.getStr == "foo")

  # Generator:
  var j = convertSexp([true, false, "foobar", [1, 2, "baz"]])
  assert($j == """(t nil "foobar" (1 2 "baz"))""")

#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Simple PEG (Parsing expression grammar) matching. Uses no memorization, but
## uses superoperators and symbol inlining to improve performance. Note:
## Matching performance is hopefully competitive with optimized regular
## expression engines.
##
## .. include:: ../../doc/pegdocs.txt
##

include "system/inclrtl"
when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions]

const
  useUnicode = true ## change this to deactivate proper UTF-8 support

import std/[strutils, macros]
import std/private/decode_helpers

when useUnicode:
  import std/unicode
  export unicode.`==`

const
  InlineThreshold = 5  ## number of leaves; -1 to disable inlining
  MaxSubpatterns* = 20 ## defines the maximum number of subpatterns that
                       ## can be captured. More subpatterns cannot be captured!

type
  PegKind* = enum
    pkEmpty,
    pkAny,            ## any character (.)
    pkAnyRune,        ## any Unicode character (_)
    pkNewLine,        ## CR-LF, LF, CR
    pkLetter,         ## Unicode letter
    pkLower,          ## Unicode lower case letter
    pkUpper,          ## Unicode upper case letter
    pkTitle,          ## Unicode title character
    pkWhitespace,     ## Unicode whitespace character
    pkTerminal,
    pkTerminalIgnoreCase,
    pkTerminalIgnoreStyle,
    pkChar,           ## single character to match
    pkCharChoice,
    pkNonTerminal,
    pkSequence,       ## a b c ... --> Internal DSL: peg(a, b, c)
    pkOrderedChoice,  ## a / b / ... --> Internal DSL: a / b or /[a, b, c]
    pkGreedyRep,      ## a*     --> Internal DSL: *a
                      ## a+     --> (a a*)
    pkGreedyRepChar,  ## x* where x is a single character (superop)
    pkGreedyRepSet,   ## [set]* (superop)
    pkGreedyAny,      ## .* or _* (superop)
    pkOption,         ## a?     --> Internal DSL: ?a
    pkAndPredicate,   ## &a     --> Internal DSL: &a
    pkNotPredicate,   ## !a     --> Internal DSL: !a
    pkCapture,        ## {a}    --> Internal DSL: capture(a)
    pkBackRef,        ## $i     --> Internal DSL: backref(i)
    pkBackRefIgnoreCase,
    pkBackRefIgnoreStyle,
    pkSearch,         ## @a     --> Internal DSL: !*a
    pkCapturedSearch, ## {@} a  --> Internal DSL: !*\a
    pkRule,           ## a <- b
    pkList,           ## a, b
    pkStartAnchor     ## ^      --> Internal DSL: startAnchor()
  NonTerminalFlag* = enum
    ntDeclared, ntUsed
  NonTerminalObj = object       ## represents a non terminal symbol
    name: string                ## the name of the symbol
    line: int                   ## line the symbol has been declared/used in
    col: int                    ## column the symbol has been declared/used in
    flags: set[NonTerminalFlag] ## the nonterminal's flags
    rule: Peg                   ## the rule that the symbol refers to
  Peg* {.shallow.} = object ## type that represents a PEG
    case kind: PegKind
    of pkEmpty..pkWhitespace: nil
    of pkTerminal, pkTerminalIgnoreCase, pkTerminalIgnoreStyle: term: string
    of pkChar, pkGreedyRepChar: ch: char
    of pkCharChoice, pkGreedyRepSet: charChoice: ref set[char]
    of pkNonTerminal: nt: NonTerminal
    of pkBackRef..pkBackRefIgnoreStyle: index: range[-MaxSubpatterns..MaxSubpatterns-1]
    else: sons: seq[Peg]
  NonTerminal* = ref NonTerminalObj

func kind*(p: Peg): PegKind = p.kind
  ## Returns the *PegKind* of a given *Peg* object.

func term*(p: Peg): string = p.term
  ## Returns the *string* representation of a given *Peg* variant object
  ## where present.

func ch*(p: Peg): char = p.ch
  ## Returns the *char* representation of a given *Peg* variant object
  ## where present.

func charChoice*(p: Peg): ref set[char] = p.charChoice
  ## Returns the *charChoice* field of a given *Peg* variant object
  ## where present.

func nt*(p: Peg): NonTerminal = p.nt
  ## Returns the *NonTerminal* object of a given *Peg* variant object
  ## where present.

func index*(p: Peg): range[-MaxSubpatterns..MaxSubpatterns-1] = p.index
  ## Returns the back-reference index of a captured sub-pattern in the
  ## *Captures* object for a given *Peg* variant object where present.

iterator items*(p: Peg): Peg {.inline.} =
  ## Yields the child nodes of a *Peg* variant object where present.
  for s in p.sons:
    yield s

iterator pairs*(p: Peg): (int, Peg) {.inline.} =
  ## Yields the indices and child nodes of a *Peg* variant object where present.
  for i in 0 ..< p.sons.len:
    yield (i, p.sons[i])

func name*(nt: NonTerminal): string = nt.name
  ## Gets the name of the symbol represented by the parent *Peg* object variant
  ## of a given *NonTerminal*.

func line*(nt: NonTerminal): int = nt.line
  ## Gets the line number of the definition of the parent *Peg* object variant
  ## of a given *NonTerminal*.

func col*(nt: NonTerminal): int = nt.col
  ## Gets the column number of the definition of the parent *Peg* object variant
  ## of a given *NonTerminal*.

func flags*(nt: NonTerminal): set[NonTerminalFlag] = nt.flags
  ## Gets the *NonTerminalFlag*-typed flags field of the parent *Peg* variant
  ## object of a given *NonTerminal*.

func rule*(nt: NonTerminal): Peg = nt.rule
  ## Gets the *Peg* object representing the rule definition of the parent *Peg*
  ## object variant of a given *NonTerminal*.

func term*(t: string): Peg {.rtl, extern: "npegs$1Str".} =
  ## constructs a PEG from a terminal string
  if t.len != 1:
    result = Peg(kind: pkTerminal, term: t)
  else:
    result = Peg(kind: pkChar, ch: t[0])

func termIgnoreCase*(t: string): Peg {.
  rtl, extern: "npegs$1".} =
  ## constructs a PEG from a terminal string; ignore case for matching
  result = Peg(kind: pkTerminalIgnoreCase, term: t)

func termIgnoreStyle*(t: string): Peg {.
  rtl, extern: "npegs$1".} =
  ## constructs a PEG from a terminal string; ignore style for matching
  result = Peg(kind: pkTerminalIgnoreStyle, term: t)

func term*(t: char): Peg {.rtl, extern: "npegs$1Char".} =
  ## constructs a PEG from a terminal char
  assert t != '\0'
  result = Peg(kind: pkChar, ch: t)

func charSet*(s: set[char]): Peg {.rtl, extern: "npegs$1".} =
  ## constructs a PEG from a character set `s`
  assert '\0' notin s
  result = Peg(kind: pkCharChoice)
  {.cast(noSideEffect).}:
    new(result.charChoice)
    result.charChoice[] = s

func len(a: Peg): int {.inline.} = return a.sons.len
func add(d: var Peg, s: Peg) {.inline.} = add(d.sons, s)

func addChoice(dest: var Peg, elem: Peg) =
  var L = dest.len-1
  if L >= 0 and dest.sons[L].kind == pkCharChoice:
    # caution! Do not introduce false aliasing here!
    case elem.kind
    of pkCharChoice:
      dest.sons[L] = charSet(dest.sons[L].charChoice[] + elem.charChoice[])
    of pkChar:
      dest.sons[L] = charSet(dest.sons[L].charChoice[] + {elem.ch})
    else: add(dest, elem)
  else: add(dest, elem)

template multipleOp(k: PegKind, localOpt: untyped) =
  result = Peg(kind: k, sons: @[])
  for x in items(a):
    if x.kind == k:
      for y in items(x.sons):
        localOpt(result, y)
    else:
      localOpt(result, x)
  if result.len == 1:
    result = result.sons[0]

func `/`*(a: varargs[Peg]): Peg {.
  rtl, extern: "npegsOrderedChoice".} =
  ## constructs an ordered choice with the PEGs in `a`
  multipleOp(pkOrderedChoice, addChoice)

func addSequence(dest: var Peg, elem: Peg) =
  var L = dest.len-1
  if L >= 0 and dest.sons[L].kind == pkTerminal:
    # caution! Do not introduce false aliasing here!
    case elem.kind
    of pkTerminal:
      dest.sons[L] = term(dest.sons[L].term & elem.term)
    of pkChar:
      dest.sons[L] = term(dest.sons[L].term & elem.ch)
    else: add(dest, elem)
  else: add(dest, elem)

func sequence*(a: varargs[Peg]): Peg {.
  rtl, extern: "npegs$1".} =
  ## constructs a sequence with all the PEGs from `a`
  multipleOp(pkSequence, addSequence)

func `?`*(a: Peg): Peg {.rtl, extern: "npegsOptional".} =
  ## constructs an optional for the PEG `a`
  if a.kind in {pkOption, pkGreedyRep, pkGreedyAny, pkGreedyRepChar,
                pkGreedyRepSet}:
    # a* ?  --> a*
    # a? ?  --> a?
    result = a
  else:
    result = Peg(kind: pkOption, sons: @[a])

func `*`*(a: Peg): Peg {.rtl, extern: "npegsGreedyRep".} =
  ## constructs a "greedy repetition" for the PEG `a`
  case a.kind
  of pkGreedyRep, pkGreedyRepChar, pkGreedyRepSet, pkGreedyAny, pkOption:
    raiseAssert "unreachable"  # produces endless loop!
  of pkChar:
    result = Peg(kind: pkGreedyRepChar, ch: a.ch)
  of pkCharChoice:
    result = Peg(kind: pkGreedyRepSet, charChoice: a.charChoice)
  of pkAny, pkAnyRune:
    result = Peg(kind: pkGreedyAny)
  else:
    result = Peg(kind: pkGreedyRep, sons: @[a])

func `!*`*(a: Peg): Peg {.rtl, extern: "npegsSearch".} =
  ## constructs a "search" for the PEG `a`
  result = Peg(kind: pkSearch, sons: @[a])

func `!*\`*(a: Peg): Peg {.rtl,
                             extern: "npgegsCapturedSearch".} =
  ## constructs a "captured search" for the PEG `a`
  result = Peg(kind: pkCapturedSearch, sons: @[a])

func `+`*(a: Peg): Peg {.rtl, extern: "npegsGreedyPosRep".} =
  ## constructs a "greedy positive repetition" with the PEG `a`
  return sequence(a, *a)

func `&`*(a: Peg): Peg {.rtl, extern: "npegsAndPredicate".} =
  ## constructs an "and predicate" with the PEG `a`
  result = Peg(kind: pkAndPredicate, sons: @[a])

func `!`*(a: Peg): Peg {.rtl, extern: "npegsNotPredicate".} =
  ## constructs a "not predicate" with the PEG `a`
  result = Peg(kind: pkNotPredicate, sons: @[a])

func any*: Peg {.inline.} =
  ## constructs the PEG `any character`:idx: (``.``)
  result = Peg(kind: pkAny)

func anyRune*: Peg {.inline.} =
  ## constructs the PEG `any rune`:idx: (``_``)
  result = Peg(kind: pkAnyRune)

func newLine*: Peg {.inline.} =
  ## constructs the PEG `newline`:idx: (``\n``)
  result = Peg(kind: pkNewLine)

func unicodeLetter*: Peg {.inline.} =
  ## constructs the PEG ``\letter`` which matches any Unicode letter.
  result = Peg(kind: pkLetter)

func unicodeLower*: Peg {.inline.} =
  ## constructs the PEG ``\lower`` which matches any Unicode lowercase letter.
  result = Peg(kind: pkLower)

func unicodeUpper*: Peg {.inline.} =
  ## constructs the PEG ``\upper`` which matches any Unicode uppercase letter.
  result = Peg(kind: pkUpper)

func unicodeTitle*: Peg {.inline.} =
  ## constructs the PEG ``\title`` which matches any Unicode title letter.
  result = Peg(kind: pkTitle)

func unicodeWhitespace*: Peg {.inline.} =
  ## constructs the PEG ``\white`` which matches any Unicode
  ## whitespace character.
  result = Peg(kind: pkWhitespace)

func startAnchor*: Peg {.inline.} =
  ## constructs the PEG ``^`` which matches the start of the input.
  result = Peg(kind: pkStartAnchor)

func endAnchor*: Peg {.inline.} =
  ## constructs the PEG ``$`` which matches the end of the input.
  result = !any()

func capture*(a: Peg = Peg(kind: pkEmpty)): Peg {.rtl, extern: "npegsCapture".} =
  ## constructs a capture with the PEG `a`
  result = Peg(kind: pkCapture, sons: @[a])

func backref*(index: range[1..MaxSubpatterns], reverse: bool = false): Peg {.
  rtl, extern: "npegs$1".} =
  ## constructs a back reference of the given `index`. `index` starts counting
  ## from 1. `reverse` specifies whether indexing starts from the end of the
  ## capture list.
  result = Peg(kind: pkBackRef, index: (if reverse: -index else: index - 1))

func backrefIgnoreCase*(index: range[1..MaxSubpatterns], reverse: bool = false): Peg {.
  rtl, extern: "npegs$1".} =
  ## constructs a back reference of the given `index`. `index` starts counting
  ## from 1. `reverse` specifies whether indexing starts from the end of the
  ## capture list. Ignores case for matching.
  result = Peg(kind: pkBackRefIgnoreCase, index: (if reverse: -index else: index - 1))

func backrefIgnoreStyle*(index: range[1..MaxSubpatterns], reverse: bool = false): Peg {.
  rtl, extern: "npegs$1".} =
  ## constructs a back reference of the given `index`. `index` starts counting
  ## from 1. `reverse` specifies whether indexing starts from the end of the
  ## capture list. Ignores style for matching.
  result = Peg(kind: pkBackRefIgnoreStyle, index: (if reverse: -index else: index - 1))

func spaceCost(n: Peg): int =
  case n.kind
  of pkEmpty: result = 0
  of pkTerminal, pkTerminalIgnoreCase, pkTerminalIgnoreStyle, pkChar,
     pkGreedyRepChar, pkCharChoice, pkGreedyRepSet,
     pkAny..pkWhitespace, pkGreedyAny, pkBackRef..pkBackRefIgnoreStyle:
    result = 1
  of pkNonTerminal:
    # we cannot inline a rule with a non-terminal
    result = InlineThreshold+1
  else:
    result = 0
    for i in 0..n.len-1:
      inc(result, spaceCost(n.sons[i]))
      if result >= InlineThreshold: break

func nonterminal*(n: NonTerminal): Peg {.
  rtl, extern: "npegs$1".} =
  ## constructs a PEG that consists of the nonterminal symbol
  assert n != nil
  if ntDeclared in n.flags and spaceCost(n.rule) < InlineThreshold:
    when false: echo "inlining symbol: ", n.name
    result = n.rule # inlining of rule enables better optimizations
  else:
    result = Peg(kind: pkNonTerminal, nt: n)

func newNonTerminal*(name: string, line, column: int): NonTerminal {.
  rtl, extern: "npegs$1".} =
  ## constructs a nonterminal symbol
  result = NonTerminal(name: name, line: line, col: column)

template letters*: Peg =
  ## expands to ``charset({'A'..'Z', 'a'..'z'})``
  charSet({'A'..'Z', 'a'..'z'})

template digits*: Peg =
  ## expands to ``charset({'0'..'9'})``
  charSet({'0'..'9'})

template whitespace*: Peg =
  ## expands to ``charset({' ', '\9'..'\13'})``
  charSet({' ', '\9'..'\13'})

template identChars*: Peg =
  ## expands to ``charset({'a'..'z', 'A'..'Z', '0'..'9', '_'})``
  charSet({'a'..'z', 'A'..'Z', '0'..'9', '_'})

template identStartChars*: Peg =
  ## expands to ``charset({'A'..'Z', 'a'..'z', '_'})``
  charSet({'a'..'z', 'A'..'Z', '_'})

template ident*: Peg =
  ## same as ``[a-zA-Z_][a-zA-z_0-9]*``; standard identifier
  sequence(charSet({'a'..'z', 'A'..'Z', '_'}),
           *charSet({'a'..'z', 'A'..'Z', '0'..'9', '_'}))

template natural*: Peg =
  ## same as ``\d+``
  +digits

# ------------------------- debugging -----------------------------------------

func esc(c: char, reserved = {'\0'..'\255'}): string =
  case c
  of '\b': result = "\\b"
  of '\t': result = "\\t"
  of '\c': result = "\\c"
  of '\L': result = "\\l"
  of '\v': result = "\\v"
  of '\f': result = "\\f"
  of '\e': result = "\\e"
  of '\a': result = "\\a"
  of '\\': result = "\\\\"
  of 'a'..'z', 'A'..'Z', '0'..'9', '_': result = $c
  elif c < ' ' or c >= '\127': result = '\\' & $ord(c)
  elif c in reserved: result = '\\' & c
  else: result = $c

func singleQuoteEsc(c: char): string = return "'" & esc(c, {'\''}) & "'"

func singleQuoteEsc(str: string): string =
  result = "'"
  for c in items(str): add result, esc(c, {'\''})
  add result, '\''

func charSetEscAux(cc: set[char]): string =
  const reserved = {'^', '-', ']'}
  result = ""
  var c1 = 0
  while c1 <= 0xff:
    if chr(c1) in cc:
      var c2 = c1
      while c2 < 0xff and chr(succ(c2)) in cc: inc(c2)
      if c1 == c2:
        add result, esc(chr(c1), reserved)
      elif c2 == succ(c1):
        add result, esc(chr(c1), reserved) & esc(chr(c2), reserved)
      else:
        add result, esc(chr(c1), reserved) & '-' & esc(chr(c2), reserved)
      c1 = c2
    inc(c1)

func charSetEsc(cc: set[char]): string =
  if card(cc) >= 128+64:
    result = "[^" & charSetEscAux({'\1'..'\xFF'} - cc) & ']'
  else:
    result = '[' & charSetEscAux(cc) & ']'

func toStrAux(r: Peg, res: var string) =
  case r.kind
  of pkEmpty: add(res, "()")
  of pkAny: add(res, '.')
  of pkAnyRune: add(res, '_')
  of pkLetter: add(res, "\\letter")
  of pkLower: add(res, "\\lower")
  of pkUpper: add(res, "\\upper")
  of pkTitle: add(res, "\\title")
  of pkWhitespace: add(res, "\\white")

  of pkNewLine: add(res, "\\n")
  of pkTerminal: add(res, singleQuoteEsc(r.term))
  of pkTerminalIgnoreCase:
    add(res, 'i')
    add(res, singleQuoteEsc(r.term))
  of pkTerminalIgnoreStyle:
    add(res, 'y')
    add(res, singleQuoteEsc(r.term))
  of pkChar: add(res, singleQuoteEsc(r.ch))
  of pkCharChoice: add(res, charSetEsc(r.charChoice[]))
  of pkNonTerminal: add(res, r.nt.name)
  of pkSequence:
    add(res, '(')
    toStrAux(r.sons[0], res)
    for i in 1 .. high(r.sons):
      add(res, ' ')
      toStrAux(r.sons[i], res)
    add(res, ')')
  of pkOrderedChoice:
    add(res, '(')
    toStrAux(r.sons[0], res)
    for i in 1 .. high(r.sons):
      add(res, " / ")
      toStrAux(r.sons[i], res)
    add(res, ')')
  of pkGreedyRep:
    toStrAux(r.sons[0], res)
    add(res, '*')
  of pkGreedyRepChar:
    add(res, singleQuoteEsc(r.ch))
    add(res, '*')
  of pkGreedyRepSet:
    add(res, charSetEsc(r.charChoice[]))
    add(res, '*')
  of pkGreedyAny:
    add(res, ".*")
  of pkOption:
    toStrAux(r.sons[0], res)
    add(res, '?')
  of pkAndPredicate:
    add(res, '&')
    toStrAux(r.sons[0], res)
  of pkNotPredicate:
    add(res, '!')
    toStrAux(r.sons[0], res)
  of pkSearch:
    add(res, '@')
    toStrAux(r.sons[0], res)
  of pkCapturedSearch:
    add(res, "{@}")
    toStrAux(r.sons[0], res)
  of pkCapture:
    add(res, '{')
    toStrAux(r.sons[0], res)
    add(res, '}')
  of pkBackRef:
    add(res, '$')
    add(res, $r.index)
  of pkBackRefIgnoreCase:
    add(res, "i$")
    add(res, $r.index)
  of pkBackRefIgnoreStyle:
    add(res, "y$")
    add(res, $r.index)
  of pkRule:
    toStrAux(r.sons[0], res)
    add(res, " <- ")
    toStrAux(r.sons[1], res)
  of pkList:
    for i in 0 .. high(r.sons):
      toStrAux(r.sons[i], res)
      add(res, "\n")
  of pkStartAnchor:
    add(res, '^')

func `$` *(r: Peg): string {.rtl, extern: "npegsToString".} =
  ## converts a PEG to its string representation
  result = ""
  toStrAux(r, result)

# --------------------- core engine -------------------------------------------

type
  Captures* = object ## contains the captured substrings.
    matches: array[0..MaxSubpatterns-1, tuple[first, last: int]]
    ml: int
    origStart: int

func bounds*(c: Captures,
             i: range[0..MaxSubpatterns-1]): tuple[first, last: int] =
  ## returns the bounds ``[first..last]`` of the `i`'th capture.
  result = c.matches[i]

when not useUnicode:
  type
    Rune = char
  template fastRuneAt(s, i, ch) =
    ch = s[i]
    inc(i)
  template runeLenAt(s, i): untyped = 1

  func isAlpha(a: char): bool {.inline.} = return a in {'a'..'z', 'A'..'Z'}
  func isUpper(a: char): bool {.inline.} = return a in {'A'..'Z'}
  func isLower(a: char): bool {.inline.} = return a in {'a'..'z'}
  func isTitle(a: char): bool {.inline.} = return false
  func isWhiteSpace(a: char): bool {.inline.} = return a in {' ', '\9'..'\13'}

template matchOrParse(mopProc: untyped) =
  # Used to make the main matcher proc *rawMatch* as well as event parser
  # procs. For the former, *enter* and *leave* event handler code generators
  # are provided which just return *discard*.

  proc mopProc(s: string, p: Peg, start: int, c: var Captures): int {.gcsafe, raises: [].} =
    result = 0

    proc matchBackRef(s: string, p: Peg, start: int, c: var Captures): int =
      # Parse handler code must run in an *of* clause of its own for each
      # *PegKind*, so we encapsulate the identical clause body for
      # *pkBackRef..pkBackRefIgnoreStyle* here.
      var index = p.index
      if index < 0: index.inc(c.ml)
      if index < 0 or index >= c.ml: return -1
      var (a, b) = c.matches[index]
      var n: Peg
      case p.kind
      of pkBackRef:
        n = Peg(kind: pkTerminal, term: s.substr(a, b))
      of pkBackRefIgnoreStyle:
        n = Peg(kind: pkTerminalIgnoreStyle, term: s.substr(a, b))
      of pkBackRefIgnoreCase:
        n = Peg(kind: pkTerminalIgnoreCase, term: s.substr(a, b))
      else: raiseAssert "impossible case"
      mopProc(s, n, start, c)

    case p.kind
    of pkEmpty:
      enter(pkEmpty, s, p, start)
      result = 0 # match of length 0
      leave(pkEmpty, s, p, start, result)
    of pkAny:
      enter(pkAny, s, p, start)
      if start < s.len: result = 1
      else: result = -1
      leave(pkAny, s, p, start, result)
    of pkAnyRune:
      enter(pkAnyRune, s, p, start)
      if start < s.len:
        result = runeLenAt(s, start)
      else:
        result = -1
      leave(pkAnyRune, s, p, start, result)
    of pkLetter:
      enter(pkLetter, s, p, start)
      if start < s.len:
        var a: Rune
        result = start
        fastRuneAt(s, result, a)
        if isAlpha(a): dec(result, start)
        else: result = -1
      else:
        result = -1
      leave(pkLetter, s, p, start, result)
    of pkLower:
      enter(pkLower, s, p, start)
      if start < s.len:
        var a: Rune
        result = start
        fastRuneAt(s, result, a)
        if isLower(a): dec(result, start)
        else: result = -1
      else:
        result = -1
      leave(pkLower, s, p, start, result)
    of pkUpper:
      enter(pkUpper, s, p, start)
      if start < s.len:
        var a: Rune
        result = start
        fastRuneAt(s, result, a)
        if isUpper(a): dec(result, start)
        else: result = -1
      else:
        result = -1
      leave(pkUpper, s, p, start, result)
    of pkTitle:
      enter(pkTitle, s, p, start)
      if start < s.len:
        var a: Rune
        result = start
        fastRuneAt(s, result, a)
        if isTitle(a): dec(result, start)
        else: result = -1
      else:
        result = -1
      leave(pkTitle, s, p, start, result)
    of pkWhitespace:
      enter(pkWhitespace, s, p, start)
      if start < s.len:
        var a: Rune
        result = start
        fastRuneAt(s, result, a)
        if isWhiteSpace(a): dec(result, start)
        else: result = -1
      else:
        result = -1
      leave(pkWhitespace, s, p, start, result)
    of pkGreedyAny:
      enter(pkGreedyAny, s, p, start)
      result = len(s) - start
      leave(pkGreedyAny, s, p, start, result)
    of pkNewLine:
      enter(pkNewLine, s, p, start)
      if start < s.len and s[start] == '\L': result = 1
      elif start < s.len and s[start] == '\C':
        if start+1 < s.len and s[start+1] == '\L': result = 2
        else: result = 1
      else: result = -1
      leave(pkNewLine, s, p, start, result)
    of pkTerminal:
      enter(pkTerminal, s, p, start)
      result = len(p.term)
      for i in 0..result-1:
        if start+i >= s.len or p.term[i] != s[start+i]:
          result = -1
          break
      leave(pkTerminal, s, p, start, result)
    of pkTerminalIgnoreCase:
      enter(pkTerminalIgnoreCase, s, p, start)
      var
        i = 0
        a, b: Rune
      result = start
      while i < len(p.term):
        if result >= s.len:
          result = -1
          break
        fastRuneAt(p.term, i, a)
        fastRuneAt(s, result, b)
        if toLower(a) != toLower(b):
          result = -1
          break
      dec(result, start)
      leave(pkTerminalIgnoreCase, s, p, start, result)
    of pkTerminalIgnoreStyle:
      enter(pkTerminalIgnoreStyle, s, p, start)
      var
        i = 0
        a, b: Rune = default(Rune)
      result = start
      while i < len(p.term):
        while i < len(p.term):
          fastRuneAt(p.term, i, a)
          if a != Rune('_'): break
        while result < s.len:
          fastRuneAt(s, result, b)
          if b != Rune('_'): break
        if result >= s.len:
          if i >= p.term.len: break
          else:
            result = -1
            break
        elif toLower(a) != toLower(b):
          result = -1
          break
      dec(result, start)
      leave(pkTerminalIgnoreStyle, s, p, start, result)
    of pkChar:
      enter(pkChar, s, p, start)
      if start < s.len and p.ch == s[start]: result = 1
      else: result = -1
      leave(pkChar, s, p, start, result)
    of pkCharChoice:
      enter(pkCharChoice, s, p, start)
      if start < s.len and contains(p.charChoice[], s[start]): result = 1
      else: result = -1
      leave(pkCharChoice, s, p, start, result)
    of pkNonTerminal:
      enter(pkNonTerminal, s, p, start)
      var oldMl = c.ml
      when false: echo "enter: ", p.nt.name
      result = mopProc(s, p.nt.rule, start, c)
      when false: echo "leave: ", p.nt.name
      if result < 0: c.ml = oldMl
      leave(pkNonTerminal, s, p, start, result)
    of pkSequence:
      enter(pkSequence, s, p, start)
      var oldMl = c.ml
      result = 0
      for i in 0..high(p.sons):
        var x = mopProc(s, p.sons[i], start+result, c)
        if x < 0:
          c.ml = oldMl
          result = -1
          break
        else: inc(result, x)
      leave(pkSequence, s, p, start, result)
    of pkOrderedChoice:
      enter(pkOrderedChoice, s, p, start)
      var oldMl = c.ml
      for i in 0..high(p.sons):
        result = mopProc(s, p.sons[i], start, c)
        if result >= 0: break
        c.ml = oldMl
      leave(pkOrderedChoice, s, p, start, result)
    of pkSearch:
      enter(pkSearch, s, p, start)
      var oldMl = c.ml
      result = 0
      while start+result <= s.len:
        var x = mopProc(s, p.sons[0], start+result, c)
        if x >= 0:
          inc(result, x)
          leave(pkSearch, s, p, start, result)
          return
        inc(result)
      result = -1
      c.ml = oldMl
      leave(pkSearch, s, p, start, result)
    of pkCapturedSearch:
      enter(pkCapturedSearch, s, p, start)
      var idx = c.ml # reserve a slot for the subpattern
      inc(c.ml)
      result = 0
      while start+result <= s.len:
        var x = mopProc(s, p.sons[0], start+result, c)
        if x >= 0:
          if idx < MaxSubpatterns:
            c.matches[idx] = (start, start+result-1)
          #else: silently ignore the capture
          inc(result, x)
          leave(pkCapturedSearch, s, p, start, result)
          return
        inc(result)
      result = -1
      c.ml = idx
      leave(pkCapturedSearch, s, p, start, result)
    of pkGreedyRep:
      enter(pkGreedyRep, s, p, start)
      result = 0
      while true:
        var x = mopProc(s, p.sons[0], start+result, c)
        # if x == 0, we have an endless loop; so the correct behaviour would be
        # not to break. But endless loops can be easily introduced:
        # ``(comment / \w*)*`` is such an example. Breaking for x == 0 does the
        # expected thing in this case.
        if x <= 0: break
        inc(result, x)
      leave(pkGreedyRep, s, p, start, result)
    of pkGreedyRepChar:
      enter(pkGreedyRepChar, s, p, start)
      result = 0
      var ch = p.ch
      while start+result < s.len and ch == s[start+result]: inc(result)
      leave(pkGreedyRepChar, s, p, start, result)
    of pkGreedyRepSet:
      enter(pkGreedyRepSet, s, p, start)
      result = 0
      while start+result < s.len and contains(p.charChoice[], s[start+result]):
        inc(result)
      leave(pkGreedyRepSet, s, p, start, result)
    of pkOption:
      enter(pkOption, s, p, start)
      result = max(0, mopProc(s, p.sons[0], start, c))
      leave(pkOption, s, p, start, result)
    of pkAndPredicate:
      enter(pkAndPredicate, s, p, start)
      var oldMl = c.ml
      result = mopProc(s, p.sons[0], start, c)
      if result >= 0: result = 0 # do not consume anything
      else: c.ml = oldMl
      leave(pkAndPredicate, s, p, start, result)
    of pkNotPredicate:
      enter(pkNotPredicate, s, p, start)
      var oldMl = c.ml
      result = mopProc(s, p.sons[0], start, c)
      if result < 0: result = 0
      else:
        c.ml = oldMl
        result = -1
      leave(pkNotPredicate, s, p, start, result)
    of pkCapture:
      enter(pkCapture, s, p, start)
      if p.sons.len == 0 or p.sons[0].kind == pkEmpty:
        # empty capture removes last match
        dec(c.ml)
        c.matches[c.ml] = (0, 0)
        result = 0 # match of length 0
      else:
        var idx = c.ml # reserve a slot for the subpattern
        result = mopProc(s, p.sons[0], start, c)
        if result >= 0:
          if idx < MaxSubpatterns:
            if idx != c.ml:
              for i in countdown(c.ml, idx):
                c.matches[i+1] = c.matches[i]
            c.matches[idx] = (start, start+result-1)
          #else: silently ignore the capture
          inc(c.ml)
      leave(pkCapture, s, p, start, result)
    of pkBackRef:
      enter(pkBackRef, s, p, start)
      result = matchBackRef(s, p, start, c)
      leave(pkBackRef, s, p, start, result)
    of pkBackRefIgnoreCase:
      enter(pkBackRefIgnoreCase, s, p, start)
      result = matchBackRef(s, p, start, c)
      leave(pkBackRefIgnoreCase, s, p, start, result)
    of pkBackRefIgnoreStyle:
      enter(pkBackRefIgnoreStyle, s, p, start)
      result = matchBackRef(s, p, start, c)
      leave(pkBackRefIgnoreStyle, s, p, start, result)
    of pkStartAnchor:
      enter(pkStartAnchor, s, p, start)
      if c.origStart == start: result = 0
      else: result = -1
      leave(pkStartAnchor, s, p, start, result)
    of pkRule, pkList: assert false

func rawMatch*(s: string, p: Peg, start: int, c: var Captures): int
      {.rtl, extern: "npegs$1".} =
  ## low-level matching proc that implements the PEG interpreter. Use this
  ## for maximum efficiency (every other PEG operation ends up calling this
  ## proc).
  ## Returns -1 if it does not match, else the length of the match

  # Set the handler generators to produce do-nothing handlers.
  template enter(pk, s, p, start) =
    discard
  template leave(pk, s, p, start, length) =
    discard
  matchOrParse(matchIt)
  {.cast(noSideEffect).}:
    # This cast is allowed because the `matchOrParse` template is used for
    # both matching and parsing, but side effects are only possible when it's
    # used by `eventParser`.
    result = matchIt(s, p, start, c)

macro mkHandlerTplts(handlers: untyped): untyped =
  # Transforms the handler spec in *handlers* into handler templates.
  # The AST structure of *handlers[0]*:
  #
  #   ```
  #   StmtList
  #     Call
  #       Ident "pkNonTerminal"
  #       StmtList
  #         Call
  #           Ident "enter"
  #           StmtList
  #             <handler code block>
  #         Call
  #           Ident "leave"
  #           StmtList
  #             <handler code block>
  #     Call
  #       Ident "pkChar"
  #       StmtList
  #         Call
  #           Ident "leave"
  #           StmtList
  #             <handler code block>
  #     ...
  #   ```
  func mkEnter(hdName, body: NimNode): NimNode =
    template helper(hdName, body) {.dirty.} =
      template hdName(s, p, start) =
        let s {.inject.} = s
        let p {.inject.} = p
        let start {.inject.} = start
        body
    result = getAst(helper(hdName, body))

  template mkLeave(hdPostf, body) {.dirty.} =
    # this has to be dirty to be able to capture *result* as *length* in
    # *leaveXX* calls.
    template `leave hdPostf`(s, p, start, length) =
      body

  result = newStmtList()
  for topCall in handlers[0]:
    if topCall.kind notin nnkCallKinds:
      error("Call syntax expected.", topCall)
    let pegKind = topCall[0]
    if pegKind.kind notin {nnkIdent, nnkSym}:
      error("PegKind expected.", pegKind)
    if 2 == topCall.len:
      for hdDef in topCall[1]:
        if hdDef.kind notin nnkCallKinds:
          error("Call syntax expected.", hdDef)
        if hdDef[0].kind notin {nnkIdent, nnkSym}:
          error("Handler identifier expected.", hdDef[0])
        if 2 == hdDef.len:
          let hdPostf = substr(pegKind.strVal, 2)
          case hdDef[0].strVal
          of "enter":
            result.add mkEnter(newIdentNode("enter" & hdPostf), hdDef[1])
          of "leave":
            result.add getAst(mkLeave(ident(hdPostf), hdDef[1]))
          else:
            error(
              "Unsupported handler identifier, expected 'enter' or 'leave'.",
              hdDef[0]
            )

template eventParser*(pegAst, handlers: untyped): (proc(s: string): int) =
  ## Generates an interpreting event parser *proc* according to the specified
  ## PEG AST and handler code blocks. The *proc* can be called with a string
  ## to be parsed and will execute the handler code blocks whenever their
  ## associated grammar element is matched. It returns -1 if the string does not
  ## match, else the length of the total match. The following example code
  ## evaluates an arithmetic expression defined by a simple PEG:
  ##
  ##   ```nim
  ##   import std/[strutils, pegs]
  ##
  ##   let
  ##     pegAst = """
  ##   Expr    <- Sum
  ##   Sum     <- Product (('+' / '-')Product)*
  ##   Product <- Value (('*' / '/')Value)*
  ##   Value   <- [0-9]+ / '(' Expr ')'
  ##     """.peg
  ##     txt = "(5+3)/2-7*22"
  ##
  ##   var
  ##     pStack: seq[string] = @[]
  ##     valStack: seq[float] = @[]
  ##     opStack = ""
  ##   let
  ##     parseArithExpr = pegAst.eventParser:
  ##       pkNonTerminal:
  ##         enter:
  ##           pStack.add p.nt.name
  ##         leave:
  ##           pStack.setLen pStack.high
  ##           if length > 0:
  ##             let matchStr = s.substr(start, start+length-1)
  ##             case p.nt.name
  ##             of "Value":
  ##               try:
  ##                 valStack.add matchStr.parseFloat
  ##                 echo valStack
  ##               except ValueError:
  ##                 discard
  ##             of "Sum", "Product":
  ##               try:
  ##                 let val = matchStr.parseFloat
  ##               except ValueError:
  ##                 if valStack.len > 1 and opStack.len > 0:
  ##                   valStack[^2] = case opStack[^1]
  ##                   of '+': valStack[^2] + valStack[^1]
  ##                   of '-': valStack[^2] - valStack[^1]
  ##                   of '*': valStack[^2] * valStack[^1]
  ##                   else: valStack[^2] / valStack[^1]
  ##                   valStack.setLen valStack.high
  ##                   echo valStack
  ##                   opStack.setLen opStack.high
  ##                   echo opStack
  ##       pkChar:
  ##         leave:
  ##           if length == 1 and "Value" != pStack[^1]:
  ##             let matchChar = s[start]
  ##             opStack.add matchChar
  ##             echo opStack
  ##
  ##   let pLen = parseArithExpr(txt)
  ##   ```
  ##
  ## The *handlers* parameter consists of code blocks for *PegKinds*,
  ## which define the grammar elements of interest. Each block can contain
  ## handler code to be executed when the parser enters and leaves text
  ## matching the grammar element. An *enter* handler can access the specific
  ## PEG AST node being matched as *p*, the entire parsed string as *s*
  ## and the position of the matched text segment in *s* as *start*. A *leave*
  ## handler can access *p*, *s*, *start* and also the length of the matched
  ## text segment as *length*. For an unsuccessful match, the *enter* and
  ## *leave* handlers will be executed, with *length* set to -1.
  ##
  ## Symbols  declared in an *enter* handler can be made visible in the
  ## corresponding *leave* handler by annotating them with an *inject* pragma.
  proc rawParse(s: string, p: Peg, start: int, c: var Captures): int
      {.gensym.} =

    # binding from *macros*
    bind strVal

    mkHandlerTplts:
      handlers

    macro enter(pegKind, s, pegNode, start: untyped): untyped =
      # This is called by the matcher code in *matchOrParse* at the
      # start of the code for a grammar element of kind *pegKind*.
      # Expands to a call to the handler template if one was generated
      # by *mkHandlerTplts*.
      template mkDoEnter(hdPostf, s, pegNode, start) =
        when declared(`enter hdPostf`):
          `enter hdPostf`(s, pegNode, start)
        else:
          discard
      let hdPostf = ident(substr($pegKind, 2))
      getAst(mkDoEnter(hdPostf, s, pegNode, start))

    macro leave(pegKind, s, pegNode, start, length: untyped): untyped =
      # Like *enter*, but called at the end of the matcher code for
      # a grammar element of kind *pegKind*.
      template mkDoLeave(hdPostf, s, pegNode, start, length) =
        when declared(`leave hdPostf`):
          `leave hdPostf`(s, pegNode, start, length)
        else:
          discard
      let hdPostf = ident(substr($pegKind, 2))
      getAst(mkDoLeave(hdPostf, s, pegNode, start, length))

    matchOrParse(parseIt)
    parseIt(s, p, start, c)

  proc parser(s: string): int {.gensym.} =
    # the proc to be returned
    var
      ms: array[MaxSubpatterns, (int, int)] = default(array[MaxSubpatterns, (int, int)])
      cs = Captures(matches: ms, ml: 0, origStart: 0)
    rawParse(s, pegAst, 0, cs)
  parser

template fillMatches(s, caps, c) =
  for k in 0..c.ml-1:
    let startIdx = c.matches[k][0]
    let endIdx = c.matches[k][1]
    if startIdx != -1:
      caps[k] = substr(s, startIdx, endIdx)
    else:
      caps[k] = ""

func matchLen*(s: string, pattern: Peg, matches: var openArray[string],
               start = 0): int {.rtl, extern: "npegs$1Capture".} =
  ## the same as ``match``, but it returns the length of the match,
  ## if there is no match, -1 is returned. Note that a match length
  ## of zero can happen. It's possible that a suffix of `s` remains
  ## that does not belong to the match.
  var c: Captures = Captures(origStart: start)
  result = rawMatch(s, pattern, start, c)
  if result >= 0: fillMatches(s, matches, c)

func matchLen*(s: string, pattern: Peg,
               start = 0): int {.rtl, extern: "npegs$1".} =
  ## the same as ``match``, but it returns the length of the match,
  ## if there is no match, -1 is returned. Note that a match length
  ## of zero can happen. It's possible that a suffix of `s` remains
  ## that does not belong to the match.
  var c: Captures = Captures(origStart: start)
  result = rawMatch(s, pattern, start, c)

func match*(s: string, pattern: Peg, matches: var openArray[string],
            start = 0): bool {.rtl, extern: "npegs$1Capture".} =
  ## returns ``true`` if ``s[start..]`` matches the ``pattern`` and
  ## the captured substrings in the array ``matches``. If it does not
  ## match, nothing is written into ``matches`` and ``false`` is
  ## returned.
  result = matchLen(s, pattern, matches, start) != -1

func match*(s: string, pattern: Peg,
            start = 0): bool {.rtl, extern: "npegs$1".} =
  ## returns ``true`` if ``s`` matches the ``pattern`` beginning from ``start``.
  result = matchLen(s, pattern, start) != -1


func find*(s: string, pattern: Peg, matches: var openArray[string],
           start = 0): int {.rtl, extern: "npegs$1Capture".} =
  ## returns the starting position of ``pattern`` in ``s`` and the captured
  ## substrings in the array ``matches``. If it does not match, nothing
  ## is written into ``matches`` and -1 is returned.
  var c: Captures = Captures(origStart: start)
  for i in start .. s.len-1:
    c.ml = 0
    if rawMatch(s, pattern, i, c) >= 0:
      fillMatches(s, matches, c)
      return i
  return -1
  # could also use the pattern here: (!P .)* P

func findBounds*(s: string, pattern: Peg, matches: var openArray[string],
                 start = 0): tuple[first, last: int] {.
                 rtl, extern: "npegs$1Capture".} =
  ## returns the starting position and end position of ``pattern`` in ``s``
  ## and the captured
  ## substrings in the array ``matches``. If it does not match, nothing
  ## is written into ``matches`` and (-1,0) is returned.
  var c: Captures = Captures(origStart: start)
  for i in start .. s.len-1:
    c.ml = 0
    var L = rawMatch(s, pattern, i, c)
    if L >= 0:
      fillMatches(s, matches, c)
      return (i, i+L-1)
  return (-1, 0)

func find*(s: string, pattern: Peg,
           start = 0): int {.rtl, extern: "npegs$1".} =
  ## returns the starting position of ``pattern`` in ``s``. If it does not
  ## match, -1 is returned.
  var c: Captures = Captures(origStart: start)
  for i in start .. s.len-1:
    if rawMatch(s, pattern, i, c) >= 0: return i
  return -1

iterator findAll*(s: string, pattern: Peg, start = 0): string =
  ## yields all matching *substrings* of `s` that match `pattern`.
  var c: Captures = Captures(origStart: start)
  var i = start
  while i < s.len:
    c.ml = 0
    var L = rawMatch(s, pattern, i, c)
    if L < 0:
      inc(i, 1)
    else:
      yield substr(s, i, i+L-1)
      inc(i, L)

func findAll*(s: string, pattern: Peg, start = 0): seq[string] {.
  rtl, extern: "npegs$1".} =
  ## returns all matching *substrings* of `s` that match `pattern`.
  ## If it does not match, `@[]` is returned.
  result = @[]
  for it in findAll(s, pattern, start): result.add it

template `=~`*(s: string, pattern: Peg): bool =
  ## This calls ``match`` with an implicit declared ``matches`` array that
  ## can be used in the scope of the ``=~`` call:
  ##
  ##   ```nim
  ##   if line =~ peg"\s* {\w+} \s* '=' \s* {\w+}":
  ##     # matches a key=value pair:
  ##     echo("Key: ", matches[0])
  ##     echo("Value: ", matches[1])
  ##   elif line =~ peg"\s*{'#'.*}":
  ##     # matches a comment
  ##     # note that the implicit ``matches`` array is different from the
  ##     # ``matches`` array of the first branch
  ##     echo("comment: ", matches[0])
  ##   else:
  ##     echo("syntax error")
  ##   ```
  bind MaxSubpatterns
  when not declaredInScope(matches):
    var matches {.inject.} = default(array[0..MaxSubpatterns-1, string])
  match(s, pattern, matches)

# ------------------------- more string handling ------------------------------

func contains*(s: string, pattern: Peg, start = 0): bool {.
  rtl, extern: "npegs$1".} =
  ## same as ``find(s, pattern, start) >= 0``
  return find(s, pattern, start) >= 0

func contains*(s: string, pattern: Peg, matches: var openArray[string],
              start = 0): bool {.rtl, extern: "npegs$1Capture".} =
  ## same as ``find(s, pattern, matches, start) >= 0``
  return find(s, pattern, matches, start) >= 0

func startsWith*(s: string, prefix: Peg, start = 0): bool {.
  rtl, extern: "npegs$1".} =
  ## returns true if `s` starts with the pattern `prefix`
  result = matchLen(s, prefix, start) >= 0

func endsWith*(s: string, suffix: Peg, start = 0): bool {.
  rtl, extern: "npegs$1".} =
  ## returns true if `s` ends with the pattern `suffix`
  result = false
  var c: Captures = Captures(origStart: start)
  for i in start .. s.len-1:
    if rawMatch(s, suffix, i, c) == s.len - i: return true

func replacef*(s: string, sub: Peg, by: string): string {.
  rtl, extern: "npegs$1".} =
  ## Replaces `sub` in `s` by the string `by`. Captures can be accessed in `by`
  ## with the notation ``$i`` and ``$#`` (see strutils.`%`). Examples:
  ##
  ##   ```nim
  ##   "var1=key; var2=key2".replacef(peg"{\ident}'='{\ident}", "$1<-$2$2")
  ##   ```
  ##
  ## Results in:
  ##
  ##   ```nim
  ##   "var1<-keykey; val2<-key2key2"
  ##   ```
  result = ""
  var i = 0
  var caps: array[0..MaxSubpatterns-1, string] = default(array[0..MaxSubpatterns-1, string])
  var c: Captures = default(Captures)
  while i < s.len:
    c.ml = 0
    var x = rawMatch(s, sub, i, c)
    if x <= 0:
      add(result, s[i])
      inc(i)
    else:
      fillMatches(s, caps, c)
      addf(result, by, caps)
      inc(i, x)
  add(result, substr(s, i))

func replace*(s: string, sub: Peg, by = ""): string {.
  rtl, extern: "npegs$1".} =
  ## Replaces `sub` in `s` by the string `by`. Captures cannot be accessed
  ## in `by`.
  result = ""
  var i = 0
  var c: Captures = default(Captures)
  while i < s.len:
    var x = rawMatch(s, sub, i, c)
    if x <= 0:
      add(result, s[i])
      inc(i)
    else:
      add(result, by)
      inc(i, x)
  add(result, substr(s, i))

func parallelReplace*(s: string, subs: varargs[
                      tuple[pattern: Peg, repl: string]]): string {.
                      rtl, extern: "npegs$1".} =
  ## Returns a modified copy of `s` with the substitutions in `subs`
  ## applied in parallel.
  result = ""
  var i = 0
  var c: Captures = default(Captures)
  var caps: array[0..MaxSubpatterns-1, string] = default(array[0..MaxSubpatterns-1, string])
  while i < s.len:
    block searchSubs:
      for j in 0..high(subs):
        c.ml = 0
        var x = rawMatch(s, subs[j][0], i, c)
        if x > 0:
          fillMatches(s, caps, c)
          addf(result, subs[j][1], caps)
          inc(i, x)
          break searchSubs
      add(result, s[i])
      inc(i)
  # copy the rest:
  add(result, substr(s, i))

when not defined(nimHasEffectsOf):
  {.pragma: effectsOf.}

func replace*(s: string, sub: Peg, cb: proc(
              match: int, cnt: int, caps: openArray[string]): string): string {.
              rtl, extern: "npegs$1cb", effectsOf: cb.} =
  ## Replaces `sub` in `s` by the resulting strings from the callback.
  ## The callback proc receives the index of the current match (starting with 0),
  ## the count of captures and an open array with the captures of each match. Examples:
  ##
  ##   ```nim
  ##   func handleMatches*(m: int, n: int, c: openArray[string]): string =
  ##     result = ""
  ##     if m > 0:
  ##       result.add ", "
  ##     result.add case n:
  ##       of 2: c[0].toLower & ": '" & c[1] & "'"
  ##       of 1: c[0].toLower & ": ''"
  ##       else: ""
  ##
  ##   let s = "Var1=key1;var2=Key2;   VAR3"
  ##   echo s.replace(peg"{\ident}('='{\ident})* ';'* \s*", handleMatches)
  ##   ```
  ##
  ## Results in:
  ##
  ##   ```nim
  ##   "var1: 'key1', var2: 'Key2', var3: ''"
  ##   ```
  result = ""
  var i = 0
  var caps: array[0..MaxSubpatterns-1, string] = default(array[0..MaxSubpatterns-1, string])
  var c: Captures = default(Captures)
  var m = 0
  while i < s.len:
    c.ml = 0
    var x = rawMatch(s, sub, i, c)
    if x <= 0:
      add(result, s[i])
      inc(i)
    else:
      fillMatches(s, caps, c)
      add(result, cb(m, c.ml, caps))
      inc(i, x)
      inc(m)
  add(result, substr(s, i))

when not defined(js):
  proc transformFile*(infile, outfile: string,
                      subs: varargs[tuple[pattern: Peg, repl: string]]) {.
                      rtl, extern: "npegs$1".} =
    ## reads in the file `infile`, performs a parallel replacement (calls
    ## `parallelReplace`) and writes back to `outfile`. Raises ``IOError`` if an
    ## error occurs. This is supposed to be used for quick scripting.
    ##
    ## **Note**: this proc does not exist while using the JS backend.
    var x = readFile(infile)
    writeFile(outfile, x.parallelReplace(subs))


iterator split*(s: string, sep: Peg): string =
  ## Splits the string `s` into substrings.
  ##
  ## Substrings are separated by the PEG `sep`.
  ## Examples:
  ##
  ##   ```nim
  ##   for word in split("00232this02939is39an22example111", peg"\d+"):
  ##     writeLine(stdout, word)
  ##   ```
  ##
  ## Results in:
  ##
  ##   ```nim
  ##   "this"
  ##   "is"
  ##   "an"
  ##   "example"
  ##   ```
  var c: Captures = default(Captures)
  var
    first = 0
    last = 0
  while last < len(s):
    c.ml = 0
    var x = rawMatch(s, sep, last, c)
    if x > 0: inc(last, x)
    first = last
    while last < len(s):
      inc(last)
      c.ml = 0
      x = rawMatch(s, sep, last, c)
      if x > 0: break
    if first < last:
      yield substr(s, first, last-1)

func split*(s: string, sep: Peg): seq[string] {.
  rtl, extern: "npegs$1".} =
  ## Splits the string `s` into substrings.
  result = @[]
  for it in split(s, sep): result.add it

# ------------------- scanner -------------------------------------------------

type
  Modifier = enum
    modNone,
    modVerbatim,
    modIgnoreCase,
    modIgnoreStyle
  TokKind = enum  ## enumeration of all tokens
    tkInvalid,    ## invalid token
    tkEof,        ## end of file reached
    tkAny,        ## .
    tkAnyRune,    ## _
    tkIdentifier, ## abc
    tkStringLit,  ## "abc" or 'abc'
    tkCharSet,    ## [^A-Z]
    tkParLe,      ## '('
    tkParRi,      ## ')'
    tkCurlyLe,    ## '{'
    tkCurlyRi,    ## '}'
    tkCurlyAt,    ## '{@}'
    tkEmptyCurl,  ## '{}'
    tkArrow,      ## '<-'
    tkBar,        ## '/'
    tkStar,       ## '*'
    tkPlus,       ## '+'
    tkAmp,        ## '&'
    tkNot,        ## '!'
    tkOption,     ## '?'
    tkAt,         ## '@'
    tkBuiltin,    ## \identifier
    tkEscaped,    ## \\
    tkBackref,    ## '$'
    tkDollar,     ## '$'
    tkHat         ## '^'

  Token {.final.} = object ## a token
    kind: TokKind          ## the type of the token
    modifier: Modifier
    literal: string        ## the parsed (string) literal
    charset: set[char]     ## if kind == tkCharSet
    index: int             ## if kind == tkBackref

  PegLexer {.inheritable.} = object ## the lexer object.
    bufpos: int                     ## the current position within the buffer
    buf: string                     ## the buffer itself
    lineNumber: int                 ## the current line number
    lineStart: int                  ## index of last line start in buffer
    colOffset: int                  ## column to add
    filename: string

const
  tokKindToStr: array[TokKind, string] = [
    "invalid", "[EOF]", ".", "_", "identifier", "string literal",
    "character set", "(", ")", "{", "}", "{@}", "{}",
    "<-", "/", "*", "+", "&", "!", "?",
    "@", "built-in", "escaped", "$", "$", "^"
  ]

func handleCR(L: var PegLexer, pos: int): int =
  assert(L.buf[pos] == '\c')
  inc(L.lineNumber)
  result = pos+1
  if result < L.buf.len and L.buf[result] == '\L': inc(result)
  L.lineStart = result

func handleLF(L: var PegLexer, pos: int): int =
  assert(L.buf[pos] == '\L')
  inc(L.lineNumber)
  result = pos+1
  L.lineStart = result

func init(L: var PegLexer, input, filename: string, line = 1, col = 0) =
  L.buf = input
  L.bufpos = 0
  L.lineNumber = line
  L.colOffset = col
  L.lineStart = 0
  L.filename = filename

func getColumn(L: PegLexer): int {.inline.} =
  result = abs(L.bufpos - L.lineStart) + L.colOffset

func getLine(L: PegLexer): int {.inline.} =
  result = L.lineNumber

func errorStr(L: PegLexer, msg: string, line = -1, col = -1): string =
  var line = if line < 0: getLine(L) else: line
  var col = if col < 0: getColumn(L) else: col
  result = "$1($2, $3) Error: $4" % [L.filename, $line, $col, msg]

func getEscapedChar(c: var PegLexer, tok: var Token) =
  inc(c.bufpos)
  if c.bufpos >= len(c.buf):
    tok.kind = tkInvalid
    return
  case c.buf[c.bufpos]
  of 'r', 'R', 'c', 'C':
    add(tok.literal, '\c')
    inc(c.bufpos)
  of 'l', 'L':
    add(tok.literal, '\L')
    inc(c.bufpos)
  of 'f', 'F':
    add(tok.literal, '\f')
    inc(c.bufpos)
  of 'e', 'E':
    add(tok.literal, '\e')
    inc(c.bufpos)
  of 'a', 'A':
    add(tok.literal, '\a')
    inc(c.bufpos)
  of 'b', 'B':
    add(tok.literal, '\b')
    inc(c.bufpos)
  of 'v', 'V':
    add(tok.literal, '\v')
    inc(c.bufpos)
  of 't', 'T':
    add(tok.literal, '\t')
    inc(c.bufpos)
  of 'x', 'X':
    inc(c.bufpos)
    if c.bufpos >= len(c.buf):
      tok.kind = tkInvalid
      return
    var xi = 0
    if handleHexChar(c.buf[c.bufpos], xi):
      inc(c.bufpos)
      if handleHexChar(c.buf[c.bufpos], xi):
        inc(c.bufpos)
    if xi == 0: tok.kind = tkInvalid
    else: add(tok.literal, chr(xi))
  of '0'..'9':
    var val = ord(c.buf[c.bufpos]) - ord('0')
    inc(c.bufpos)
    var i = 1
    while (c.bufpos < len(c.buf)) and (i <= 3) and (c.buf[c.bufpos] in {'0'..'9'}):
      val = val * 10 + ord(c.buf[c.bufpos]) - ord('0')
      inc(c.bufpos)
      inc(i)
    if val > 0 and val <= 255: add(tok.literal, chr(val))
    else: tok.kind = tkInvalid
  of '\0'..'\31':
    tok.kind = tkInvalid
  elif c.buf[c.bufpos] in strutils.Letters:
    tok.kind = tkInvalid
  else:
    add(tok.literal, c.buf[c.bufpos])
    inc(c.bufpos)

func skip(c: var PegLexer) =
  var pos = c.bufpos
  while pos < c.buf.len:
    case c.buf[pos]
    of ' ', '\t':
      inc(pos)
    of '#':
      while (pos < c.buf.len) and
             not (c.buf[pos] in {'\c', '\L', '\0'}): inc(pos)
    of '\c':
      pos = handleCR(c, pos)
    of '\L':
      pos = handleLF(c, pos)
    else:
      break # EndOfFile also leaves the loop
  c.bufpos = pos

func getString(c: var PegLexer, tok: var Token) =
  tok.kind = tkStringLit
  var pos = c.bufpos + 1
  var quote = c.buf[pos-1]
  while pos < c.buf.len:
    case c.buf[pos]
    of '\\':
      c.bufpos = pos
      getEscapedChar(c, tok)
      pos = c.bufpos
    of '\c', '\L', '\0':
      tok.kind = tkInvalid
      break
    elif c.buf[pos] == quote:
      inc(pos)
      break
    else:
      add(tok.literal, c.buf[pos])
      inc(pos)
  c.bufpos = pos

func getDollar(c: var PegLexer, tok: var Token) =
  var pos = c.bufpos + 1
  var neg = false
  if pos < c.buf.len and c.buf[pos] == '^':
    neg = true
    inc(pos)
  if pos < c.buf.len and c.buf[pos] in {'0'..'9'}:
    tok.kind = tkBackref
    tok.index = 0
    while pos < c.buf.len and c.buf[pos] in {'0'..'9'}:
      tok.index = tok.index * 10 + ord(c.buf[pos]) - ord('0')
      inc(pos)
    if neg:
      tok.index = -tok.index
  else:
    if neg:
      dec(pos)
    tok.kind = tkDollar
  c.bufpos = pos

func getCharSet(c: var PegLexer, tok: var Token) =
  tok.kind = tkCharSet
  tok.charset = {}
  var pos = c.bufpos + 1
  var caret = false
  if pos < c.buf.len:
    if c.buf[pos] == '^':
      inc(pos)
      caret = true
    while pos < c.buf.len:
      var ch: char
      case c.buf[pos]
      of ']':
        if pos < c.buf.len: inc(pos)
        break
      of '\\':
        c.bufpos = pos
        getEscapedChar(c, tok)
        pos = c.bufpos
        ch = tok.literal[tok.literal.len-1]
      of '\C', '\L', '\0':
        tok.kind = tkInvalid
        break
      else:
        ch = c.buf[pos]
        inc(pos)
      incl(tok.charset, ch)
      if c.buf[pos] == '-':
        if pos+1 < c.buf.len and c.buf[pos+1] == ']':
          incl(tok.charset, '-')
          inc(pos)
        else:
          if pos+1 < c.buf.len:
            inc(pos)
          else:
            break
          var ch2: char
          case c.buf[pos]
          of '\\':
            c.bufpos = pos
            getEscapedChar(c, tok)
            pos = c.bufpos
            ch2 = tok.literal[tok.literal.len-1]
          of '\C', '\L', '\0':
            tok.kind = tkInvalid
            break
          else:
            if pos+1 < c.buf.len:
              ch2 = c.buf[pos]
              inc(pos)
            else:
              break
          for i in ord(ch)+1 .. ord(ch2):
            incl(tok.charset, chr(i))
  c.bufpos = pos
  if caret: tok.charset = {'\1'..'\xFF'} - tok.charset

func getSymbol(c: var PegLexer, tok: var Token) =
  var pos = c.bufpos
  while pos < c.buf.len:
    add(tok.literal, c.buf[pos])
    inc(pos)
    if pos < c.buf.len and c.buf[pos] notin strutils.IdentChars: break
  c.bufpos = pos
  tok.kind = tkIdentifier

func getBuiltin(c: var PegLexer, tok: var Token) =
  if c.bufpos+1 < c.buf.len and c.buf[c.bufpos+1] in strutils.Letters:
    inc(c.bufpos)
    getSymbol(c, tok)
    tok.kind = tkBuiltin
  else:
    tok.kind = tkEscaped
    getEscapedChar(c, tok) # may set tok.kind to tkInvalid

func getTok(c: var PegLexer, tok: var Token) =
  tok.kind = tkInvalid
  tok.modifier = modNone
  setLen(tok.literal, 0)
  skip(c)

  if c.bufpos >= c.buf.len:
    tok.kind = tkEof
    tok.literal = "[EOF]"
    add(tok.literal, '\0')
    inc(c.bufpos)
    return

  case c.buf[c.bufpos]
  of '{':
    inc(c.bufpos)
    if c.buf[c.bufpos] == '@' and c.bufpos+2 < c.buf.len and
      c.buf[c.bufpos+1] == '}':
      tok.kind = tkCurlyAt
      inc(c.bufpos, 2)
      add(tok.literal, "{@}")
    elif c.buf[c.bufpos] == '}' and c.bufpos < c.buf.len:
      tok.kind = tkEmptyCurl
      inc(c.bufpos)
      add(tok.literal, "{}")
    else:
      tok.kind = tkCurlyLe
      add(tok.literal, '{')
  of '}':
    tok.kind = tkCurlyRi
    inc(c.bufpos)
    add(tok.literal, '}')
  of '[':
    getCharSet(c, tok)
  of '(':
    tok.kind = tkParLe
    inc(c.bufpos)
    add(tok.literal, '(')
  of ')':
    tok.kind = tkParRi
    inc(c.bufpos)
    add(tok.literal, ')')
  of '.':
    tok.kind = tkAny
    inc(c.bufpos)
    add(tok.literal, '.')
  of '_':
    tok.kind = tkAnyRune
    inc(c.bufpos)
    add(tok.literal, '_')
  of '\\':
    getBuiltin(c, tok)
  of '\'', '"': getString(c, tok)
  of '$': getDollar(c, tok)
  of 'a'..'z', 'A'..'Z', '\128'..'\255':
    getSymbol(c, tok)
    if c.bufpos >= c.buf.len:
      return
    if c.buf[c.bufpos] in {'\'', '"'} or
        c.buf[c.bufpos] == '$' and c.bufpos+1 < c.buf.len and
        c.buf[c.bufpos+1] in {'^', '0'..'9'}:
      case tok.literal
      of "i": tok.modifier = modIgnoreCase
      of "y": tok.modifier = modIgnoreStyle
      of "v": tok.modifier = modVerbatim
      else: discard
      setLen(tok.literal, 0)
      if c.buf[c.bufpos] == '$':
        getDollar(c, tok)
      else:
        getString(c, tok)
      if tok.modifier == modNone: tok.kind = tkInvalid
  of '+':
    tok.kind = tkPlus
    inc(c.bufpos)
    add(tok.literal, '+')
  of '*':
    tok.kind = tkStar
    inc(c.bufpos)
    add(tok.literal, '+')
  of '<':
    if c.bufpos+2 < c.buf.len and c.buf[c.bufpos+1] == '-':
      inc(c.bufpos, 2)
      tok.kind = tkArrow
      add(tok.literal, "<-")
    else:
      add(tok.literal, '<')
  of '/':
    tok.kind = tkBar
    inc(c.bufpos)
    add(tok.literal, '/')
  of '?':
    tok.kind = tkOption
    inc(c.bufpos)
    add(tok.literal, '?')
  of '!':
    tok.kind = tkNot
    inc(c.bufpos)
    add(tok.literal, '!')
  of '&':
    tok.kind = tkAmp
    inc(c.bufpos)
    add(tok.literal, '!')
  of '@':
    tok.kind = tkAt
    inc(c.bufpos)
    add(tok.literal, '@')
    if c.buf[c.bufpos] == '@':
      tok.kind = tkCurlyAt
      inc(c.bufpos)
      add(tok.literal, '@')
  of '^':
    tok.kind = tkHat
    inc(c.bufpos)
    add(tok.literal, '^')
  else:
    if c.bufpos >= c.buf.len:
      tok.kind = tkEof
      tok.literal = "[EOF]"
    add(tok.literal, c.buf[c.bufpos])
    inc(c.bufpos)

func arrowIsNextTok(c: PegLexer): bool =
  # the only look ahead we need
  var pos = c.bufpos
  while pos < c.buf.len and c.buf[pos] in {'\t', ' '}: inc(pos)
  if pos+1 >= c.buf.len:
    return
  result = c.buf[pos] == '<' and c.buf[pos+1] == '-'

# ----------------------------- parser ----------------------------------------

type
  EInvalidPeg* = object of ValueError ## raised if an invalid
                                      ## PEG has been detected
  PegParser = object of PegLexer ## the PEG parser object
    tok: Token
    nonterms: seq[NonTerminal]
    modifier: Modifier
    captures: int
    identIsVerbatim: bool
    skip: Peg

func pegError(p: PegParser, msg: string, line = -1, col = -1) {.noreturn.} =
  var e = (ref EInvalidPeg)(msg: errorStr(p, msg, line, col))
  raise e

func getTok(p: var PegParser) =
  getTok(p, p.tok)
  if p.tok.kind == tkInvalid: pegError(p, "'" & p.tok.literal & "' is invalid token")

func eat(p: var PegParser, kind: TokKind) =
  if p.tok.kind == kind: getTok(p)
  else: pegError(p, tokKindToStr[kind] & " expected")

func parseExpr(p: var PegParser): Peg {.gcsafe.}

func getNonTerminal(p: var PegParser, name: string): NonTerminal =
  for i in 0..high(p.nonterms):
    result = p.nonterms[i]
    if cmpIgnoreStyle(result.name, name) == 0: return
  # forward reference:
  result = newNonTerminal(name, getLine(p), getColumn(p))
  add(p.nonterms, result)

func modifiedTerm(s: string, m: Modifier): Peg =
  case m
  of modNone, modVerbatim: result = term(s)
  of modIgnoreCase: result = termIgnoreCase(s)
  of modIgnoreStyle: result = termIgnoreStyle(s)

func modifiedBackref(s: int, m: Modifier): Peg =
  var
    reverse = s < 0
    index = if reverse: -s else: s
  case m
  of modNone, modVerbatim: result = backref(index, reverse)
  of modIgnoreCase: result = backrefIgnoreCase(index, reverse)
  of modIgnoreStyle: result = backrefIgnoreStyle(index, reverse)

func builtin(p: var PegParser): Peg =
  # do not use "y", "skip" or "i" as these would be ambiguous
  case p.tok.literal
  of "n": result = newLine()
  of "d": result = charSet({'0'..'9'})
  of "D": result = charSet({'\1'..'\xff'} - {'0'..'9'})
  of "s": result = charSet({' ', '\9'..'\13'})
  of "S": result = charSet({'\1'..'\xff'} - {' ', '\9'..'\13'})
  of "w": result = charSet({'a'..'z', 'A'..'Z', '_', '0'..'9'})
  of "W": result = charSet({'\1'..'\xff'} - {'a'..'z', 'A'..'Z', '_', '0'..'9'})
  of "a": result = charSet({'a'..'z', 'A'..'Z'})
  of "A": result = charSet({'\1'..'\xff'} - {'a'..'z', 'A'..'Z'})
  of "ident": result = pegs.ident
  of "letter": result = unicodeLetter()
  of "upper": result = unicodeUpper()
  of "lower": result = unicodeLower()
  of "title": result = unicodeTitle()
  of "white": result = unicodeWhitespace()
  else: pegError(p, "unknown built-in: " & p.tok.literal)

func token(terminal: Peg, p: PegParser): Peg =
  if p.skip.kind == pkEmpty: result = terminal
  else: result = sequence(p.skip, terminal)

func primary(p: var PegParser): Peg =
  case p.tok.kind
  of tkAmp:
    getTok(p)
    return &primary(p)
  of tkNot:
    getTok(p)
    return !primary(p)
  of tkAt:
    getTok(p)
    return !*primary(p)
  of tkCurlyAt:
    getTok(p)
    return !*\primary(p).token(p)
  else: discard
  case p.tok.kind
  of tkIdentifier:
    if p.identIsVerbatim:
      var m = p.tok.modifier
      if m == modNone: m = p.modifier
      result = modifiedTerm(p.tok.literal, m).token(p)
      getTok(p)
    elif not arrowIsNextTok(p):
      var nt = getNonTerminal(p, p.tok.literal)
      {.cast(noSideEffect).}:
        incl(nt.flags, ntUsed)
      result = nonterminal(nt).token(p)
      getTok(p)
    else:
      pegError(p, "expression expected, but found: " & p.tok.literal)
  of tkStringLit:
    var m = p.tok.modifier
    if m == modNone: m = p.modifier
    result = modifiedTerm(p.tok.literal, m).token(p)
    getTok(p)
  of tkCharSet:
    if '\0' in p.tok.charset:
      pegError(p, "binary zero ('\\0') not allowed in character class")
    result = charSet(p.tok.charset).token(p)
    getTok(p)
  of tkParLe:
    getTok(p)
    result = parseExpr(p)
    eat(p, tkParRi)
  of tkCurlyLe:
    getTok(p)
    result = capture(parseExpr(p)).token(p)
    eat(p, tkCurlyRi)
    inc(p.captures)
  of tkEmptyCurl:
    result = capture()
    getTok(p)
  of tkAny:
    result = any().token(p)
    getTok(p)
  of tkAnyRune:
    result = anyRune().token(p)
    getTok(p)
  of tkBuiltin:
    result = builtin(p).token(p)
    getTok(p)
  of tkEscaped:
    result = term(p.tok.literal[0]).token(p)
    getTok(p)
  of tkDollar:
    result = endAnchor()
    getTok(p)
  of tkHat:
    result = startAnchor()
    getTok(p)
  of tkBackref:
    if abs(p.tok.index) > p.captures or p.tok.index == 0:
      pegError(p, "invalid back reference index: " & $p.tok.index)
    var m = p.tok.modifier
    if m == modNone: m = p.modifier
    result = modifiedBackref(p.tok.index, m).token(p)
    getTok(p)
  else:
    pegError(p, "expression expected, but found: " & p.tok.literal)
    # getTok(p) # we must consume a token here to prevent endless loops!
  while true:
    case p.tok.kind
    of tkOption:
      result = ?result
      getTok(p)
    of tkStar:
      result = *result
      getTok(p)
    of tkPlus:
      result = +result
      getTok(p)
    else: break

func seqExpr(p: var PegParser): Peg =
  result = primary(p)
  while true:
    case p.tok.kind
    of tkAmp, tkNot, tkAt, tkStringLit, tkCharSet, tkParLe, tkCurlyLe,
       tkAny, tkAnyRune, tkBuiltin, tkEscaped, tkDollar, tkBackref,
       tkHat, tkCurlyAt, tkEmptyCurl:
      result = sequence(result, primary(p))
    of tkIdentifier:
      if not arrowIsNextTok(p):
        result = sequence(result, primary(p))
      else: break
    else: break

func parseExpr(p: var PegParser): Peg =
  result = seqExpr(p)
  while p.tok.kind == tkBar:
    getTok(p)
    result = result / seqExpr(p)

func parseRule(p: var PegParser): NonTerminal =
  if p.tok.kind == tkIdentifier and arrowIsNextTok(p):
    result = getNonTerminal(p, p.tok.literal)
    if ntDeclared in result.flags:
      pegError(p, "attempt to redefine: " & result.name)
    {.cast(noSideEffect).}:
      result.line = getLine(p)
      result.col = getColumn(p)
    getTok(p)
    eat(p, tkArrow)
    {.cast(noSideEffect).}:
      result.rule = parseExpr(p)
      incl(result.flags, ntDeclared) # NOW inlining may be attempted
  else:
    pegError(p, "rule expected, but found: " & p.tok.literal)

func rawParse(p: var PegParser): Peg =
  ## parses a rule or a PEG expression
  while p.tok.kind == tkBuiltin:
    case p.tok.literal
    of "i":
      p.modifier = modIgnoreCase
      getTok(p)
    of "y":
      p.modifier = modIgnoreStyle
      getTok(p)
    of "skip":
      getTok(p)
      p.skip = ?primary(p)
    else: break
  if p.tok.kind == tkIdentifier and arrowIsNextTok(p):
    result = parseRule(p).rule
    while p.tok.kind != tkEof:
      discard parseRule(p)
  else:
    p.identIsVerbatim = true
    result = parseExpr(p)
  if p.tok.kind != tkEof:
    pegError(p, "EOF expected, but found: " & p.tok.literal)
  for i in 0..high(p.nonterms):
    var nt = p.nonterms[i]
    if ntDeclared notin nt.flags:
      pegError(p, "undeclared identifier: " & nt.name, nt.line, nt.col)
    elif ntUsed notin nt.flags and i > 0:
      pegError(p, "unused rule: " & nt.name, nt.line, nt.col)

func parsePeg*(pattern: string, filename = "pattern", line = 1, col = 0): Peg =
  ## constructs a Peg object from `pattern`. `filename`, `line`, `col` are
  ## used for error messages, but they only provide start offsets. `parsePeg`
  ## keeps track of line and column numbers within `pattern`.
  var p: PegParser = default(PegParser)
  init(PegLexer(p), pattern, filename, line, col)
  p.tok.kind = tkInvalid
  p.tok.modifier = modNone
  p.tok.literal = ""
  p.tok.charset = {}
  p.nonterms = @[]
  p.identIsVerbatim = false
  getTok(p)
  result = rawParse(p)

func peg*(pattern: string): Peg =
  ## constructs a Peg object from the `pattern`. The short name has been
  ## chosen to encourage its use as a raw string modifier:
  ##
  ##     peg"{\ident} \s* '=' \s* {.*}"
  result = parsePeg(pattern, "pattern")

func escapePeg*(s: string): string =
  ## escapes `s` so that it is matched verbatim when used as a peg.
  result = ""
  var inQuote = false
  for c in items(s):
    case c
    of '\0'..'\31', '\'', '"', '\\':
      if inQuote:
        result.add('\'')
        inQuote = false
      result.add("\\x")
      result.add(toHex(ord(c), 2))
    else:
      if not inQuote:
        result.add('\'')
        inQuote = true
      result.add(c)
  if inQuote: result.add('\'')

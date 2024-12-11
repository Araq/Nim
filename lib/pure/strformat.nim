#
#
#            Nim's Runtime Library
#        (c) Copyright 2017 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

##[
String `interpolation`:idx: / `format`:idx: inspired by
Python's f-strings.

# `fmt` vs. `&`

You can use either `fmt` or the unary `&` operator for formatting. The
difference between them is subtle but important.

The `fmt"{expr}"` syntax is more aesthetically pleasing, but it hides a small
gotcha. The string is a
`generalized raw string literal <manual.html#lexical-analysis-generalized-raw-string-literals>`_.
This has some surprising effects:
]##

runnableExamples:
  let msg = "hello"
  assert fmt"{msg}\n" == "hello\\n"

##[
Because the literal is a raw string literal, the `\n` is not interpreted as
an escape sequence.

There are multiple ways to get around this, including the use of the `&` operator:
]##

runnableExamples:
  let msg = "hello"

  assert &"{msg}\n" == "hello\n"

  assert fmt"{msg}{'\n'}" == "hello\n"
  assert fmt("{msg}\n") == "hello\n"
  assert "{msg}\n".fmt == "hello\n"

##[
The choice of style is up to you.

# Formatting strings
]##

runnableExamples:
  assert &"""{"abc":>4}""" == " abc"
  assert &"""{"abc":<4}""" == "abc "

##[
# Formatting floats
]##

runnableExamples:
  assert fmt"{-12345:08}" == "-0012345"
  assert fmt"{-1:3}" == " -1"
  assert fmt"{-1:03}" == "-01"
  assert fmt"{16:#X}" == "0x10"

  assert fmt"{123.456}" == "123.456"
  assert fmt"{123.456:>9.3f}" == "  123.456"
  assert fmt"{123.456:9.3f}" == "  123.456"
  assert fmt"{123.456:9.4f}" == " 123.4560"
  assert fmt"{123.456:>9.0f}" == "     123."
  assert fmt"{123.456:<9.4f}" == "123.4560 "

  assert fmt"{123.456:e}" == "1.234560e+02"
  assert fmt"{123.456:>13e}" == " 1.234560e+02"
  assert fmt"{123.456:13e}" == " 1.234560e+02"

##[
# Expressions
]##
runnableExamples:
  let x = 3.14
  assert fmt"{(if x!=0: 1.0/x else: 0):.5}" == "0.31847"
  assert fmt"""{(block:
    var res: string
    for i in 1..15:
      res.add (if i mod 15 == 0: "FizzBuzz"
        elif i mod 5 == 0: "Buzz"
        elif i mod 3 == 0: "Fizz"
        else: $i) & " "
    res)}""" == "1 2 Fizz 4 Buzz Fizz 7 8 Fizz Buzz 11 Fizz 13 14 FizzBuzz "
##[
# Debugging strings

`fmt"{expr=}"` expands to `fmt"expr={expr}"` namely the text of the expression,
an equal sign and the results of evaluated expression.
]##

runnableExamples:
  assert fmt"{123.456=}" == "123.456=123.456"
  assert fmt"{123.456=:>9.3f}" == "123.456=  123.456"

  let x = "hello"
  assert fmt"{x=}" == "x=hello"
  assert fmt"{x =}" == "x =hello"

  let y = 3.1415926
  assert fmt"{y=:.2f}" == fmt"y={y:.2f}"
  assert fmt"{y=}" == fmt"y={y}"
  assert fmt"{y = : <8}" == fmt"y = 3.14159 "

  proc hello(a: string, b: float): int = 12
  assert fmt"{hello(x, y) = }" == "hello(x, y) = 12"
  assert fmt"{x.hello(y) = }" == "x.hello(y) = 12"
  assert fmt"{hello x, y = }" == "hello x, y = 12"

##[
Note that it is space sensitive:
]##

runnableExamples:
  let x = "12"
  assert fmt"{x=}" == "x=12"
  assert fmt"{x =:}" == "x =12"
  assert fmt"{x =}" == "x =12"
  assert fmt"{x= :}" == "x= 12"
  assert fmt"{x= }" == "x= 12"
  assert fmt"{x = :}" == "x = 12"
  assert fmt"{x = }" == "x = 12"
  assert fmt"{x   =  :}" == "x   =  12"
  assert fmt"{x   =  }" == "x   =  12"

##[
# Implementation details

An expression like `&"{key} is {value:arg} {{z}}"` is transformed into:

  ```nim
  var temp = newStringOfCap(educatedCapGuess)
  temp.formatValue(key, "")
  temp.add(" is ")
  temp.formatValue(value, arg)
  temp.add(" {z}")
  temp
  ```

Parts of the string that are enclosed in the curly braces are interpreted
as Nim code. To escape a `{` or `}`, double it.

Within a curly expression, however, `{`, `}`, must be escaped with a backslash.

To enable evaluating Nim expressions within curlies, colons inside parentheses
do not need to be escaped.
]##

runnableExamples:
  let x = "hello"
  assert fmt"""{ "\{(" & x & ")\}" }""" == "{(hello)}"
  assert fmt"""{{({ x })}}""" == "{(hello)}"
  assert fmt"""{ $(\{x:1,"world":2\}) }""" == """[("hello", 1), ("world", 2)]"""

##[
`&` delegates most of the work to an open overloaded set
of `formatValue` procs. The required signature for a type `T` that supports
formatting is usually `proc formatValue(result: var string; x: T; specifier: string)`.

The subexpression after the colon
(`arg` in `&"{key} is {value:arg} {{z}}"`) is optional. It will be passed as
the last argument to `formatValue`. When the colon with the subexpression it is
left out, an empty string will be taken instead.

For strings and numeric types the optional argument is a so-called
"standard format specifier".

# Standard format specifiers for strings, integers and floats

The general form of a standard format specifier is:

    [[fill]align][sign][#][0][minimumwidth][.precision][type]

The square brackets `[]` indicate an optional element.

The optional `align` flag can be one of the following:

`<`
:   Forces the field to be left-aligned within the available
    space. (This is the default for strings.)

`>`
:   Forces the field to be right-aligned within the available space.
    (This is the default for numbers.)

`^`
:   Forces the field to be centered within the available space.

Note that unless a minimum field width is defined, the field width
will always be the same size as the data to fill it, so that the alignment
option has no meaning in this case.

The optional `fill` character defines the character to be used to pad
the field to the minimum width. The fill character, if present, must be
followed by an alignment flag.

The `sign` option is only valid for numeric types, and can be one of the following:

=================        ====================================================
  Sign                   Meaning
=================        ====================================================
`+`                      Indicates that a sign should be used for both
                         positive as well as negative numbers.
`-`                      Indicates that a sign should be used only for
                         negative numbers (this is the default behavior).
(space)                  Indicates that a leading space should be used on
                         positive numbers.
=================        ====================================================

If the `#` character is present, integers use the 'alternate form' for formatting.
This means that binary, octal and hexadecimal output will be prefixed
with `0b`, `0o` and `0x`, respectively.

`width` is a decimal integer defining the minimum field width. If not specified,
then the field width will be determined by the content.

If the width field is preceded by a zero (`0`) character, this enables
zero-padding.

The `precision` is a decimal number indicating how many digits should be displayed
after the decimal point in a floating point conversion. For non-numeric types the
field indicates the maximum field size - in other words, how many characters will
be used from the field content. The precision is ignored for integer conversions.

Finally, the `type` determines how the data should be presented.

The available integer presentation types are:

=================        ====================================================
  Type                   Result
=================        ====================================================
`b`                      Binary. Outputs the number in base 2.
`d`                      Decimal Integer. Outputs the number in base 10.
`o`                      Octal format. Outputs the number in base 8.
`x`                      Hex format. Outputs the number in base 16, using
                         lower-case letters for the digits above 9.
`X`                      Hex format. Outputs the number in base 16, using
                         uppercase letters for the digits above 9.
(None)                   The same as `d`.
=================        ====================================================

The available floating point presentation types are:

=================        ====================================================
  Type                   Result
=================        ====================================================
`e`                      Exponent notation. Prints the number in scientific
                         notation using the letter `e` to indicate the
                         exponent.
`E`                      Exponent notation. Same as `e` except it converts
                         the number to uppercase.
`f`                      Fixed point. Displays the number as a fixed-point
                         number.
`F`                      Fixed point. Same as `f` except it converts the
                         number to uppercase.
`g`                      General format. This prints the number as a
                         fixed-point number, unless the number is too
                         large, in which case it switches to `e`
                         exponent notation.
`G`                      General format. Same as `g` except it switches to `E`
                         if the number gets to large.
`i`                      Complex General format. This is only supported for
                         complex numbers, which it prints using the mathematical
                         (RE+IMj) format. The real and imaginary parts are printed
                         using the general format `g` by default, but it is
                         possible to combine this format with one of the other
                         formats (e.g `jf`).
(None)                   Similar to `g`, except that it prints at least one
                         digit after the decimal point.
=================        ====================================================

# Limitations

Because of the well defined order how templates and macros are
expanded, strformat cannot expand template arguments:

  ```nim
  template myTemplate(arg: untyped): untyped =
    echo "arg is: ", arg
    echo &"--- {arg} ---"

  let x = "abc"
  myTemplate(x)
  ```

First the template `myTemplate` is expanded, where every identifier
`arg` is substituted with its argument. The `arg` inside the
format string is not seen by this process, because it is part of a
quoted string literal. It is not an identifier yet. Then the strformat
macro creates the `arg` identifier from the string literal, an
identifier that cannot be resolved anymore.

The workaround for this is to bind the template argument to a new local variable.

  ```nim
  template myTemplate(arg: untyped): untyped =
    block:
      let arg1 {.inject.} = arg
      echo "arg is: ", arg1
      echo &"--- {arg1} ---"
  ```

The use of `{.inject.}` here is necessary again because of template
expansion order and hygienic templates. But since we generally want to
keep the hygiene of `myTemplate`, and we do not want `arg1`
to be injected into the context where `myTemplate` is expanded,
everything is wrapped in a `block`.


# Future directions

A curly expression with commas in it like `{x, argA, argB}` could be
transformed to `formatValue(result, x, argA, argB)` in order to support
formatters that do not need to parse a custom language within a custom
language but instead prefer to use Nim's existing syntax. This would also
help with readability, since there is only so much you can cram into
single letter DSLs.
]##

import std/[macros, parseutils, unicode]
import std/strutils except format

when defined(nimPreviewSlimSystem):
  import std/assertions


proc mkDigit(v: int, typ: char): string {.inline.} =
  assert(v < 26)
  if v < 10:
    result = $chr(ord('0') + v)
  else:
    result = $chr(ord(if typ == 'x': 'a' else: 'A') + v - 10)

proc alignString*(s: string, minimumWidth: int; align = '\0'; fill = ' '): string =
  ## Aligns `s` using the `fill` char.
  ## This is only of interest if you want to write a custom `format` proc that
  ## should support the standard format specifiers.
  if minimumWidth == 0:
    result = s
  else:
    let sRuneLen = if s.validateUtf8 == -1: s.runeLen else: s.len
    let toFill = minimumWidth - sRuneLen
    if toFill <= 0:
      result = s
    elif align == '<' or align == '\0':
      result = s & repeat(fill, toFill)
    elif align == '^':
      let half = toFill div 2
      result = repeat(fill, half) & s & repeat(fill, toFill - half)
    else:
      result = repeat(fill, toFill) & s

type
  StandardFormatSpecifier* = object ## Type that describes "standard format specifiers".
    fill*, align*: char            ## Desired fill and alignment.
    sign*: char                    ## Desired sign.
    alternateForm*: bool           ## Whether to prefix binary, octal and hex numbers
                                   ## with `0b`, `0o`, `0x`.
    padWithZero*: bool             ## Whether to pad with zeros rather than spaces.
    minimumWidth*, precision*: int ## Desired minimum width and precision.
    typ*: char                     ## Type like 'f', 'g' or 'd'.
    endPosition*: int              ## End position in the format specifier after
                                   ## `parseStandardFormatSpecifier` returned.

proc formatInt(n: SomeNumber; radix: int; spec: StandardFormatSpecifier): string =
  ## Converts `n` to a string. If `n` is `SomeFloat`, it casts to `int64`.
  ## Conversion is done using `radix`. If result's length is less than
  ## `minimumWidth`, it aligns result to the right or left (depending on `a`)
  ## with the `fill` char.
  when n is SomeUnsignedInt:
    var v = n.uint64
    let negative = false
  else:
    let n = n.int64
    let negative = n < 0
    var v =
      if negative:
        # `uint64(-n)`, but accounts for `n == low(int64)`
        uint64(not n) + 1
      else:
        uint64(n)

  var xx = ""
  if spec.alternateForm:
    case spec.typ
    of 'X': xx = "0x"
    of 'x': xx = "0x"
    of 'b': xx = "0b"
    of 'o': xx = "0o"
    else: discard

  if v == 0:
    result = "0"
  else:
    result = ""
    while v > typeof(v)(0):
      let d = v mod typeof(v)(radix)
      v = v div typeof(v)(radix)
      result.add(mkDigit(d.int, spec.typ))
    for idx in 0..<(result.len div 2):
      swap result[idx], result[result.len - idx - 1]
  if spec.padWithZero:
    let sign = negative or spec.sign != '-'
    let toFill = spec.minimumWidth - result.len - xx.len - ord(sign)
    if toFill > 0:
      result = repeat('0', toFill) & result

  if negative:
    result = "-" & xx & result
  elif spec.sign != '-':
    result = spec.sign & xx & result
  else:
    result = xx & result

  if spec.align == '<':
    for i in result.len..<spec.minimumWidth:
      result.add(spec.fill)
  else:
    let toFill = spec.minimumWidth - result.len
    if spec.align == '^':
      let half = toFill div 2
      result = repeat(spec.fill, half) & result & repeat(spec.fill, toFill - half)
    else:
      if toFill > 0:
        result = repeat(spec.fill, toFill) & result

proc parseStandardFormatSpecifier*(s: string; start = 0;
                                   ignoreUnknownSuffix = false): StandardFormatSpecifier =
  ## An exported helper proc that parses the "standard format specifiers",
  ## as specified by the grammar:
  ##
  ##     [[fill]align][sign][#][0][minimumwidth][.precision][type]
  ##
  ## This is only of interest if you want to write a custom `format` proc that
  ## should support the standard format specifiers. If `ignoreUnknownSuffix` is true,
  ## an unknown suffix after the `type` field is not an error.
  const alignChars = {'<', '>', '^'}
  result.fill = ' '
  result.align = '\0'
  result.sign = '-'
  var i = start
  if i + 1 < s.len and s[i+1] in alignChars:
    result.fill = s[i]
    result.align = s[i+1]
    inc i, 2
  elif i < s.len and s[i] in alignChars:
    result.align = s[i]
    inc i

  if i < s.len and s[i] in {'-', '+', ' '}:
    result.sign = s[i]
    inc i

  if i < s.len and s[i] == '#':
    result.alternateForm = true
    inc i

  if i + 1 < s.len and s[i] == '0' and s[i+1] in {'0'..'9'}:
    result.padWithZero = true
    inc i

  let parsedLength = parseSaturatedNatural(s, result.minimumWidth, i)
  inc i, parsedLength
  if i < s.len and s[i] == '.':
    inc i
    let parsedLengthB = parseSaturatedNatural(s, result.precision, i)
    inc i, parsedLengthB
  else:
    result.precision = -1

  if i < s.len and s[i] in {'A'..'Z', 'a'..'z'}:
    result.typ = s[i]
    inc i
  result.endPosition = i
  if i != s.len and not ignoreUnknownSuffix:
    raise newException(ValueError,
      "invalid format string, cannot parse: " & s[i..^1])

proc toRadix(typ: char): int =
  case typ
  of 'x', 'X': 16
  of 'd', '\0': 10
  of 'o': 8
  of 'b': 2
  else:
    raise newException(ValueError,
      "invalid type in format string for number, expected one " &
      " of 'x', 'X', 'b', 'd', 'o' but got: " & typ)

proc formatValue*[T: SomeInteger](result: var string; value: T;
                                  specifier: static string) =
  ## Standard format implementation for `SomeInteger`. It makes little
  ## sense to call this directly, but it is required to exist
  ## by the `&` macro.
  when specifier.len == 0:
    result.add $value
  else:
    const
      spec = parseStandardFormatSpecifier(specifier)
      radix = toRadix(spec.typ)

    result.add formatInt(value, radix, spec)

proc formatValue*[T: SomeInteger](result: var string; value: T;
                                  specifier: string) =
  ## Standard format implementation for `SomeInteger`. It makes little
  ## sense to call this directly, but it is required to exist
  ## by the `&` macro.
  if specifier.len == 0:
    result.add $value
  else:
    let
      spec = parseStandardFormatSpecifier(specifier)
      radix = toRadix(spec.typ)

    result.add formatInt(value, radix, spec)

proc formatFloat(
    result: var string, value: SomeFloat, fmode: FloatFormatMode,
    spec: StandardFormatSpecifier) =
  var f = formatBiggestFloat(value, fmode, spec.precision)
  var sign = false
  if value >= 0.0:
    if spec.sign != '-':
      sign = true
      if value == 0.0:
        if 1.0 / value == Inf:
          # only insert the sign if value != negZero
          f.insert($spec.sign, 0)
      else:
        f.insert($spec.sign, 0)
  else:
    sign = true

  if spec.padWithZero:
    var signStr = ""
    if sign:
      signStr = $f[0]
      f = f[1..^1]

    let toFill = spec.minimumWidth - f.len - ord(sign)
    if toFill > 0:
      f = repeat('0', toFill) & f
    if sign:
      f = signStr & f

  # the default for numbers is right-alignment:
  let align = if spec.align == '\0': '>' else: spec.align
  let res = alignString(f, spec.minimumWidth, align, spec.fill)
  if spec.typ in {'A'..'Z'}:
    result.add toUpperAscii(res)
  else:
    result.add res

proc toFloatFormatMode(typ: char): FloatFormatMode =
  case typ
  of 'e', 'E': ffScientific
  of 'f', 'F': ffDecimal
  of 'g', 'G': ffDefault
  of '\0': ffDefault
  else:
    raise newException(ValueError,
      "invalid type in format string for number, expected one " &
      " of 'e', 'E', 'f', 'F', 'g', 'G' but got: " & typ)

proc formatValue*(result: var string; value: SomeFloat; specifier: static string) =
  ## Standard format implementation for `SomeFloat`. It makes little
  ## sense to call this directly, but it is required to exist
  ## by the `&` macro.
  when specifier.len == 0:
    result.add $value
  else:
    const
      spec = parseStandardFormatSpecifier(specifier)
      fmode = toFloatFormatMode(spec.typ)

    formatFloat(result, value, fmode, spec)

proc formatValue*(result: var string; value: SomeFloat; specifier: string) =
  ## Standard format implementation for `SomeFloat`. It makes little
  ## sense to call this directly, but it is required to exist
  ## by the `&` macro.
  if specifier.len == 0:
    result.add $value
  else:
    let
      spec = parseStandardFormatSpecifier(specifier)
      fmode = toFloatFormatMode(spec.typ)

    formatFloat(result, value, fmode, spec)

proc formatValue*(result: var string; value: string; specifier: static string) =
  ## Standard format implementation for `string`. It makes little
  ## sense to call this directly, but it is required to exist
  ## by the `&` macro.
  const spec = parseStandardFormatSpecifier(specifier)
  var value =
    when spec.typ in {'s', '\0'}: value
    else: static:
      raise newException(ValueError,
        "invalid type in format string for string, expected 's', but got " &
        spec.typ)
  when spec.precision != -1:
    if spec.precision < runeLen(value):
      const precision = cast[Natural](spec.precision)
      setLen(value, Natural(runeOffset(value, precision)))

  result.add alignString(value, spec.minimumWidth, spec.align, spec.fill)

proc formatValue*(result: var string; value: string; specifier: string) =
  ## Standard format implementation for `string`. It makes little
  ## sense to call this directly, but it is required to exist
  ## by the `&` macro.
  let spec = parseStandardFormatSpecifier(specifier)
  var value =
    if spec.typ in {'s', '\0'}: value
    else:
      raise newException(ValueError,
        "invalid type in format string for string, expected 's', but got " &
        spec.typ)
  if spec.precision != -1:
    if spec.precision < runeLen(value):
      let precision = cast[Natural](spec.precision)
      setLen(value, Natural(runeOffset(value, precision)))

  result.add alignString(value, spec.minimumWidth, spec.align, spec.fill)

proc formatValue[T: not SomeInteger](result: var string; value: T; specifier: static string) =
  mixin `$`
  formatValue(result, $value, specifier)

proc formatValue[T: not SomeInteger](result: var string; value: T; specifier: string) =
  mixin `$`
  formatValue(result, $value, specifier)

template formatValue(result: var string; value: char; specifier: string) =
  result.add value

template formatValue(result: var string; value: cstring; specifier: string) =
  result.add value

proc strformatImpl(f: string; openChar, closeChar: char,
                   lineInfoNode: NimNode = nil): NimNode =
  template missingCloseChar =
    error("invalid format string: missing closing character '" & closeChar & "'")

  if openChar == ':' or closeChar == ':':
    error "openChar and closeChar must not be ':'"
  var i = 0
  let res = genSym(nskVar, "fmtRes")
  result = newNimNode(nnkStmtListExpr, lineInfoNode)
  # XXX: https://github.com/nim-lang/Nim/issues/8405
  # When compiling with -d:useNimRtl, certain procs such as `count` from the strutils
  # module are not accessible at compile-time:
  let expectedGrowth = when defined(useNimRtl): 0 else: count(f, openChar) * 10
  result.add newVarStmt(res, newCall(bindSym"newStringOfCap",
                                     newLit(f.len + expectedGrowth)))
  var strlit = ""
  while i < f.len:
    if f[i] == openChar:
      inc i
      if f[i] == openChar:
        inc i
        strlit.add openChar
      else:
        if strlit.len > 0:
          result.add newCall(bindSym"add", res, newLit(strlit))
          strlit = ""

        var subexpr = ""
        var inParens = 0
        var inSingleQuotes = false
        var inDoubleQuotes = false
        template notEscaped:bool = f[i-1]!='\\'
        while i < f.len and f[i] != closeChar and (f[i] != ':' or inParens != 0):
          case f[i]
          of '\\':
            if i < f.len-1 and f[i+1] in {openChar,closeChar,':'}: inc i
          of '\'':
            if not inDoubleQuotes and notEscaped: inSingleQuotes = not inSingleQuotes
          of '\"':
            if notEscaped: inDoubleQuotes = not inDoubleQuotes
          of '(':
            if not (inSingleQuotes or inDoubleQuotes): inc inParens
          of ')':
            if not (inSingleQuotes or inDoubleQuotes): dec inParens
          of '=':
            let start = i
            inc i
            i += f.skipWhitespace(i)
            if i == f.len:
              missingCloseChar
            if f[i] == closeChar or f[i] == ':':
              result.add newCall(bindSym"add", res, newLit(subexpr & f[start ..< i]))
            else:
              subexpr.add f[start ..< i]
            continue
          else: discard
          subexpr.add f[i]
          inc i

        if i == f.len:
          missingCloseChar

        var x: NimNode
        try:
          x = parseExpr(subexpr)
        except ValueError as e:
          error("could not parse `$#` in `$#`.\n$#" % [subexpr, f, e.msg], lineInfoNode)
        x.copyLineInfo(lineInfoNode)
        let formatSym = bindSym("formatValue", brOpen)
        var options = ""
        if f[i] == ':':
          inc i
          while i < f.len and f[i] != closeChar:
            options.add f[i]
            inc i
        if i == f.len:
          missingCloseChar
        if f[i] == closeChar:
          inc i
        result.add newCall(formatSym, res, x, newLit(options))
    elif f[i] == closeChar:
      if i<f.len-1 and f[i+1] == closeChar:
        strlit.add closeChar
        inc i, 2
      else:
        raiseAssert "invalid format string: '$1' instead of '$1$1'" % $closeChar
    else:
      strlit.add f[i]
      inc i
  if strlit.len > 0:
    result.add newCall(bindSym"add", res, newLit(strlit))
  result.add res
  # workaround for #20381
  var blockExpr = newNimNode(nnkBlockExpr, lineInfoNode)
  blockExpr.add(newEmptyNode())
  blockExpr.add(result)
  result = blockExpr
  when defined(debugFmtDsl):
    echo repr result

macro fmt(pattern: static string; openChar: static char, closeChar: static char, lineInfoNode: untyped): string =
  ## version of `fmt` with dummy untyped param for line info
  strformatImpl(pattern, openChar, closeChar, lineInfoNode)

when not defined(nimHasCallsitePragma):
  {.pragma: callsite.}

template fmt*(pattern: static string; openChar: static char, closeChar: static char): string {.callsite.} =
  ## Interpolates `pattern` using symbols in scope.
  runnableExamples:
    let x = 7
    assert "var is {x * 2}".fmt == "var is 14"
    assert "var is {{x}}".fmt == "var is {x}" # escape via doubling
    const s = "foo: {x}"
    assert s.fmt == "foo: 7" # also works with const strings

    assert fmt"\n" == r"\n" # raw string literal
    assert "\n".fmt == "\n" # regular literal (likewise with `fmt("\n")` or `fmt "\n"`)
  runnableExamples:
    # custom `openChar`, `closeChar`
    let x = 7
    assert "<x>".fmt('<', '>') == "7"
    assert "<<<x>>>".fmt('<', '>') == "<7>"
    assert "`x`".fmt('`', '`') == "7"
  fmt(pattern, openChar, closeChar, dummyForLineInfo)

template fmt*(pattern: static string): untyped {.callsite.} =
  ## Alias for `fmt(pattern, '{', '}')`.
  fmt(pattern, '{', '}', dummyForLineInfo)

template `&`*(pattern: string{lit}): string {.callsite.} =
  ## `&pattern` is the same as `pattern.fmt`.
  ## For a specification of the `&` macro, see the module level documentation.
  # pending bug #18275, bug #18278, use `pattern: static string`
  # consider deprecating this, it's redundant with `fmt` and `fmt` is strictly
  # more flexible, readable (no confusion with the binary `&`), self-documenting,
  # not to mention #18275, bug #18278.
  runnableExamples:
    let x = 7
    assert &"{x}\n" == "7\n" # regular string literal
    assert &"{x}\n" == "{x}\n".fmt # `fmt` can be used instead
    assert &"{x}\n" != fmt"{x}\n" # see `fmt` docs, this would use a raw string literal
  fmt(pattern, '{', '}', dummyForLineInfo)

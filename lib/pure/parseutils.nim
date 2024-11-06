#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module contains helpers for parsing tokens, numbers, integers, floats,
## identifiers, etc.
##
## To unpack raw bytes look at the `streams <streams.html>`_ module.
##
##   ```nim test
##   let logs = @["2019-01-10: OK_", "2019-01-11: FAIL_", "2019-01: aaaa"]
##   var outp: seq[string]
##
##   for log in logs:
##     var res: string
##     if parseUntil(log, res, ':') == 10: # YYYY-MM-DD == 10
##       outp.add(res & " - " & captureBetween(log, ' ', '_'))
##   doAssert outp == @["2019-01-10 - OK", "2019-01-11 - FAIL"]
##   ```
##
##   ```nim test
##   from std/strutils import Digits, parseInt
##
##   let
##     input1 = "2019 school start"
##     input2 = "3 years back"
##     startYear = input1[0 .. skipWhile(input1, Digits)-1] # 2019
##     yearsBack = input2[0 .. skipWhile(input2, Digits)-1] # 3
##     examYear = parseInt(startYear) + parseInt(yearsBack)
##   doAssert "Examination is in " & $examYear == "Examination is in 2022"
##   ```
##
## **See also:**
## * `strutils module<strutils.html>`_ for combined and identical parsing proc's
## * `json module<json.html>`_ for a JSON parser
## * `parsecfg module<parsecfg.html>`_ for a configuration file parser
## * `parsecsv module<parsecsv.html>`_ for a simple CSV (comma separated value) parser
## * `parseopt module<parseopt.html>`_ for a command line parser
## * `parsexml module<parsexml.html>`_ for a XML / HTML parser
## * `other parsers<lib.html#pure-libraries-parsers>`_ for other parsers

{.push debugger: off.} # the user does not want to trace a part
                       # of the standard library!

include "system/inclrtl"

template toOa(s: string): openArray[char] = openArray[char](s)

const
  Whitespace = {' ', '\t', '\v', '\r', '\l', '\f'}
  IdentChars = {'a'..'z', 'A'..'Z', '0'..'9', '_'}
  IdentStartChars = {'a'..'z', 'A'..'Z', '_'}
    ## copied from strutils

proc toLower(c: char): char {.inline.} =
  result = if c in {'A'..'Z'}: chr(ord(c)-ord('A')+ord('a')) else: c

proc parseBin*[T: SomeInteger](s: openArray[char], number: var T, maxLen = 0): int {.noSideEffect.} =
  ## Parses a binary number and stores its value in ``number``.
  ##
  ## Returns the number of the parsed characters or 0 in case of an error.
  ## If error, the value of ``number`` is not changed.
  ##
  ## If ``maxLen == 0``, the parsing continues until the first non-bin character
  ## or to the end of the string. Otherwise, no more than ``maxLen`` characters
  ## are parsed starting from the ``start`` position.
  ##
  ## It does not check for overflow. If the value represented by the string is
  ## too big to fit into ``number``, only the value of last fitting characters
  ## will be stored in ``number`` without producing an error.
  runnableExamples:
    var num: int
    doAssert parseBin("0100_1110_0110_1001_1110_1101", num) == 29
    doAssert num == 5138925
    doAssert parseBin("3", num) == 0
    var num8: int8
    doAssert parseBin("0b_0100_1110_0110_1001_1110_1101", num8) == 32
    doAssert num8 == 0b1110_1101'i8
    doAssert parseBin("0b_0100_1110_0110_1001_1110_1101", num8, 3, 9) == 9
    doAssert num8 == 0b0100_1110'i8
    var num8u: uint8
    doAssert parseBin("0b_0100_1110_0110_1001_1110_1101", num8u) == 32
    doAssert num8u == 237
    var num64: int64
    doAssert parseBin("0100111001101001111011010100111001101001", num64) == 40
    doAssert num64 == 336784608873
  var i = 0
  var output = T(0)
  var foundDigit = false
  let last = min(s.len, if maxLen == 0: s.len else: i + maxLen)
  if i + 1 < last and s[i] == '0' and (s[i+1] in {'b', 'B'}): inc(i, 2)
  while i < last:
    case s[i]
    of '_': discard
    of '0'..'1':
      output = output shl 1 or T(ord(s[i]) - ord('0'))
      foundDigit = true
    else: break
    inc(i)
  if foundDigit:
    number = output
    result = i

proc parseOct*[T: SomeInteger](s: openArray[char], number: var T, maxLen = 0): int {.noSideEffect.} =
  ## Parses an octal number and stores its value in ``number``.
  ##
  ## Returns the number of the parsed characters or 0 in case of an error.
  ## If error, the value of ``number`` is not changed.
  ##
  ## If ``maxLen == 0``, the parsing continues until the first non-oct character
  ## or to the end of the string. Otherwise, no more than ``maxLen`` characters
  ## are parsed starting from the ``start`` position.
  ##
  ## It does not check for overflow. If the value represented by the string is
  ## too big to fit into ``number``, only the value of last fitting characters
  ## will be stored in ``number`` without producing an error.
  runnableExamples:
    var num: int
    doAssert parseOct("0o23464755", num) == 10
    doAssert num == 5138925
    doAssert parseOct("8", num) == 0
    var num8: int8
    doAssert parseOct("0o_1464_755", num8) == 11
    doAssert num8 == -19
    doAssert parseOct("0o_1464_755", num8, 3, 3) == 3
    doAssert num8 == 102
    var num8u: uint8
    doAssert parseOct("1464755", num8u) == 7
    doAssert num8u == 237
    var num64: int64
    doAssert parseOct("2346475523464755", num64) == 16
    doAssert num64 == 86216859871725
  var i = 0
  var output = T(0)
  var foundDigit = false
  let last = min(s.len, if maxLen == 0: s.len else: i + maxLen)
  if i + 1 < last and s[i] == '0' and (s[i+1] in {'o', 'O'}): inc(i, 2)
  while i < last:
    case s[i]
    of '_': discard
    of '0'..'7':
      output = output shl 3 or T(ord(s[i]) - ord('0'))
      foundDigit = true
    else: break
    inc(i)
  if foundDigit:
    number = output
    result = i

proc parseHex*[T: SomeInteger](s: openArray[char], number: var T, maxLen = 0): int {.noSideEffect.} =
  ## Parses a hexadecimal number and stores its value in ``number``.
  ##
  ## Returns the number of the parsed characters or 0 in case of an error.
  ## If error, the value of ``number`` is not changed.
  ##
  ## If ``maxLen == 0``, the parsing continues until the first non-hex character
  ## or to the end of the string. Otherwise, no more than ``maxLen`` characters
  ## are parsed starting from the ``start`` position.
  ##
  ## It does not check for overflow. If the value represented by the string is
  ## too big to fit into ``number``, only the value of last fitting characters
  ## will be stored in ``number`` without producing an error.
  runnableExamples:
    var num: int
    doAssert parseHex("4E_69_ED", num) == 8
    doAssert num == 5138925
    doAssert parseHex("X", num) == 0
    doAssert parseHex("#ABC", num) == 4
    var num8: int8
    doAssert parseHex("0x_4E_69_ED", num8) == 11
    doAssert num8 == 0xED'i8
    doAssert parseHex("0x_4E_69_ED", num8, 3, 2) == 2
    doAssert num8 == 0x4E'i8
    var num8u: uint8
    doAssert parseHex("0x_4E_69_ED", num8u) == 11
    doAssert num8u == 237
    var num64: int64
    doAssert parseHex("4E69ED4E69ED", num64) == 12
    doAssert num64 == 86216859871725
  result = 0
  var i = 0
  var output = T(0)
  var foundDigit = false
  let last = min(s.len, if maxLen == 0: s.len else: i + maxLen)
  if i + 1 < last and s[i] == '0' and (s[i+1] in {'x', 'X'}): inc(i, 2)
  elif i < last and s[i] == '#': inc(i)
  while i < last:
    case s[i]
    of '_': discard
    of '0'..'9':
      output = output shl 4 or T(ord(s[i]) - ord('0'))
      foundDigit = true
    of 'a'..'f':
      output = output shl 4 or T(ord(s[i]) - ord('a') + 10)
      foundDigit = true
    of 'A'..'F':
      output = output shl 4 or T(ord(s[i]) - ord('A') + 10)
      foundDigit = true
    else: break
    inc(i)
  if foundDigit:
    number = output
    result = i

proc parseIdent*(s: openArray[char], ident: var string): int =
  ## Parses an identifier and stores it in ``ident``. Returns
  ## the number of the parsed characters or 0 in case of an error.
  ## If error, the value of `ident` is not changed.
  runnableExamples:
    var res: string
    doAssert parseIdent("Hello World", res, 0) == 5
    doAssert res == "Hello"
    doAssert parseIdent("Hello World", res, 1) == 4
    doAssert res == "ello"
    doAssert parseIdent("Hello World", res, 6) == 5
    doAssert res == "World"
  var i = 0
  if i < s.len and s[i] in IdentStartChars:
    inc(i)
    while i < s.len and s[i] in IdentChars: inc(i)
    ident = substr(s.toOpenArray(0, i-1))
    result = i

proc parseIdent*(s: openArray[char]): string =
  ## Parses an identifier and returns it or an empty string in
  ## case of an error.
  runnableExamples:
    doAssert parseIdent("Hello World", 0) == "Hello"
    doAssert parseIdent("Hello World", 1) == "ello"
    doAssert parseIdent("Hello World", 5) == ""
    doAssert parseIdent("Hello World", 6) == "World"
  result = ""
  var i = 0
  if i < s.len and s[i] in IdentStartChars:
    inc(i)
    while i < s.len and s[i] in IdentChars: inc(i)
    result = substr(s.toOpenArray(0, i - 1))

proc parseChar*(s: openArray[char], c: var char): int =
  ## Parses a single character, stores it in `c` and returns 1.
  ## In case of error (if start >= s.len) it returns 0
  ## and the value of `c` is unchanged.
  runnableExamples:
    var c: char
    doAssert "nim".parseChar(c, 3) == 0
    doAssert c == '\0'
    doAssert "nim".parseChar(c, 0) == 1
    doAssert c == 'n'
  if s.len > 0:
    c = s[0]
    result = 1

proc skipWhitespace*(s: openArray[char]): int {.inline.} =
  ## Skips the whitespace starting at ``s[start]``. Returns the number of
  ## skipped characters.
  runnableExamples:
    doAssert skipWhitespace("Hello World", 0) == 0
    doAssert skipWhitespace(" Hello World", 0) == 1
    doAssert skipWhitespace("Hello World", 5) == 1
    doAssert skipWhitespace("Hello  World", 5) == 2
  result = 0
  while result < s.len and s[result] in Whitespace: inc(result)

proc skip*(s, token: openArray[char]): int {.inline.} =
  ## Skips the `token` starting at ``s[start]``. Returns the length of `token`
  ## or 0 if there was no `token` at ``s[start]``.
  runnableExamples:
    doAssert skip("2019-01-22", "2019", 0) == 4
    doAssert skip("2019-01-22", "19", 0) == 0
    doAssert skip("2019-01-22", "19", 2) == 2
    doAssert skip("CAPlow", "CAP", 0) == 3
    doAssert skip("CAPlow", "cap", 0) == 0
  result = 0
  while result < s.len and result < token.len and
      s[result] == token[result]:
    inc(result)
  if result != token.len: result = 0

proc skipIgnoreCase*(s, token: openArray[char]): int =
  ## Same as `skip` but case is ignored for token matching.
  runnableExamples:
    doAssert skipIgnoreCase("CAPlow", "CAP", 0) == 3
    doAssert skipIgnoreCase("CAPlow", "cap", 0) == 3
  result = 0
  while result < s.len and result < token.len and
      toLower(s[result]) == toLower(token[result]): inc(result)
  if result != token.len: result = 0

proc skipUntil*(s: openArray[char], until: set[char]): int {.inline.} =
  ## Skips all characters until one char from the set `until` is found
  ## or the end is reached.
  ## Returns number of characters skipped.
  runnableExamples:
    doAssert skipUntil("Hello World", {'W', 'e'}, 0) == 1
    doAssert skipUntil("Hello World", {'W'}, 0) == 6
    doAssert skipUntil("Hello World", {'W', 'd'}, 0) == 6
  result = 0
  while result < s.len and s[result] notin until: inc(result)

proc skipUntil*(s: openArray[char], until: char): int {.inline.} =
  ## Skips all characters until the char `until` is found
  ## or the end is reached.
  ## Returns number of characters skipped.
  runnableExamples:
    doAssert skipUntil("Hello World", 'o', 0) == 4
    doAssert skipUntil("Hello World", 'o', 4) == 0
    doAssert skipUntil("Hello World", 'W', 0) == 6
    doAssert skipUntil("Hello World", 'w', 0) == 11
  result = 0
  while result < s.len and s[result] != until: inc(result)

proc skipWhile*(s: openArray[char], toSkip: set[char]): int {.inline.} =
  ## Skips all characters while one char from the set `toSkip` is found.
  ## Returns number of characters skipped.
  runnableExamples:
    doAssert skipWhile("Hello World", {'H', 'e'}) == 2
    doAssert skipWhile("Hello World", {'e'}) == 0
    doAssert skipWhile("Hello World", {'W', 'o', 'r'}, 6) == 3
  result = 0
  while result < s.len and s[result] in toSkip: inc(result)

proc fastSubstr(s: openArray[char]; token: var string; length: int) =
  token.setLen length
  for i in 0 ..< length: token[i] = s[i]

proc parseUntil*(s: openArray[char], token: var string, until: set[char]): int {.inline.} =
  ## Parses a token and stores it in ``token``. Returns
  ## the number of the parsed characters or 0 in case of an error. A token
  ## consists of the characters notin `until`.
  runnableExamples:
    var myToken: string
    doAssert parseUntil("Hello World", myToken, {'W', 'o', 'r'}) == 4
    doAssert myToken == "Hell"
    doAssert parseUntil("Hello World", myToken, {'W', 'r'}) == 6
    doAssert myToken == "Hello "
    doAssert parseUntil("Hello World", myToken, {'W', 'r'}, 3) == 3
    doAssert myToken == "lo "
  var i = 0
  while i < s.len and s[i] notin until: inc(i)
  result = i
  fastSubstr(s, token, result)
  #token = substr(s, start, i-1)

proc parseUntil*(s: openArray[char], token: var string, until: char): int {.inline.} =
  ## Parses a token and stores it in ``token``. Returns
  ## the number of the parsed characters or 0 in case of an error. A token
  ## consists of any character that is not the `until` character.
  runnableExamples:
    var myToken: string
    doAssert parseUntil("Hello World", myToken, 'W') == 6
    doAssert myToken == "Hello "
    doAssert parseUntil("Hello World", myToken, 'o') == 4
    doAssert myToken == "Hell"
    doAssert parseUntil("Hello World", myToken, 'o', 2) == 2
    doAssert myToken == "ll"
  var i = 0
  while i < s.len and s[i] != until: inc(i)
  result = i
  fastSubstr(s, token, result)
  #token = substr(s, start, i-1)

proc parseUntil*(s: openArray[char], token: var string, until: string): int {.inline.} =
  ## Parses a token and stores it in ``token``. Returns
  ## the number of the parsed characters or 0 in case of an error. A token
  ## consists of any character that comes before the `until`  token.
  runnableExamples:
    var myToken: string
    doAssert parseUntil("Hello World", myToken, "Wor") == 6
    doAssert myToken == "Hello "
    doAssert parseUntil("Hello World", myToken, "Wor", 2) == 4
    doAssert myToken == "llo "
  when (NimMajor, NimMinor) <= (1, 0):
    if until.len == 0:
      token.setLen(0)
      return 0
  var i = 0
  while i < s.len:
    if until.len > 0 and s[i] == until[0]:
      var u = 1
      while i+u < s.len and u < until.len and s[i+u] == until[u]:
        inc u
      if u >= until.len: break
    inc(i)
  result = i
  fastSubstr(s, token, result)
  #token = substr(s, start, i-1)

proc parseWhile*(s: openArray[char], token: var string, validChars: set[char]): int {.inline.} =
  ## Parses a token and stores it in ``token``. Returns
  ## the number of the parsed characters or 0 in case of an error. A token
  ## consists of the characters in `validChars`.
  runnableExamples:
    var myToken: string
    doAssert parseWhile("Hello World", myToken, {'W', 'o', 'r'}, 0) == 0
    doAssert myToken.len() == 0
    doAssert parseWhile("Hello World", myToken, {'W', 'o', 'r'}, 6) == 3
    doAssert myToken == "Wor"
  var i = 0
  while i < s.len and s[i] in validChars: inc(i)
  result = i
  fastSubstr(s, token, result)
  #token = substr(s, start, i-1)

proc captureBetween*(s: openArray[char], first: char, second = '\0'): string =
  ## Finds the first occurrence of ``first``, then returns everything from there
  ## up to ``second`` (if ``second`` is '\0', then ``first`` is used).
  runnableExamples:
    doAssert captureBetween("Hello World", 'e') == "llo World"
    doAssert captureBetween("Hello World", 'e', 'r') == "llo Wo"
    doAssert captureBetween("Hello World".toOpenArray(6, "Hello World".high), 'l') == "d"
  var i = skipUntil(s, first) + 1
  result = ""
  discard parseUntil(s.toOpenArray(i, s.high), result, if second == '\0': first else: second)

proc integerOutOfRangeError() {.noinline.} =
  raise newException(ValueError, "Parsed integer outside of valid range")

# See #6752
when defined(js):
  {.push overflowChecks: off.}

proc rawParseInt(s: openArray[char], b: var BiggestInt): int =
  var
    sign: BiggestInt = -1
    i = 0
  if i < s.len:
    if s[i] == '+': inc(i)
    elif s[i] == '-':
      inc(i)
      sign = 1
  if i < s.len and s[i] in {'0'..'9'}:
    b = 0
    while i < s.len and s[i] in {'0'..'9'}:
      let c = ord(s[i]) - ord('0')
      if b >= (low(BiggestInt) + c) div 10:
        b = b * 10 - c
      else:
        integerOutOfRangeError()
      inc(i)
      while i < s.len and s[i] == '_': inc(i) # underscores are allowed and ignored
    if sign == -1 and b == low(BiggestInt):
      integerOutOfRangeError()
    else:
      b = b * sign
      result = i

when defined(js):
  {.pop.} # overflowChecks: off

proc parseBiggestInt*(s: openArray[char], number: var BiggestInt): int {.
  rtl, extern: "npuParseBiggestInt", noSideEffect, raises: [ValueError].} =
  ## Parses an integer and stores the value into `number`.
  ## Result is the number of processed chars or 0 if there is no integer.
  ## `ValueError` is raised if the parsed integer is out of the valid range.
  runnableExamples:
    var res: BiggestInt
    doAssert parseBiggestInt("9223372036854775807", res) == 19
    doAssert res == 9223372036854775807
    doAssert parseBiggestInt("-2024_05_09", res) == 11
    doAssert res == -20240509
  var res = BiggestInt(0)
  # use 'res' for exception safety (don't write to 'number' in case of an
  # overflow exception):
  result = rawParseInt(s, res)
  if result != 0:
    number = res

proc parseInt*(s: openArray[char], number: var int): int {.
  rtl, extern: "npuParseInt", noSideEffect, raises: [ValueError].} =
  ## Parses an integer and stores the value into `number`.
  ## Result is the number of processed chars or 0 if there is no integer.
  ## `ValueError` is raised if the parsed integer is out of the valid range.
  runnableExamples:
    var res: int
    doAssert parseInt("-2024_05_02", res) == 11
    doAssert res == -20240502
  var res = BiggestInt(0)
  result = parseBiggestInt(s, res)
  when sizeof(int) <= 4:
    if res < low(int) or res > high(int):
      integerOutOfRangeError()
  if result != 0:
    number = int(res)

proc parseSaturatedNatural*(s: openArray[char], b: var int): int {.
    raises: [].} =
  ## Parses a natural number into ``b``. This cannot raise an overflow
  ## error. ``high(int)`` is returned for an overflow.
  ## The number of processed character is returned.
  ## This is usually what you really want to use instead of `parseInt`:idx:.
  runnableExamples:
    var res = 0
    discard parseSaturatedNatural("848", res)
    doAssert res == 848
  var i = 0
  if i < s.len and s[i] == '+': inc(i)
  if i < s.len and s[i] in {'0'..'9'}:
    b = 0
    while i < s.len and s[i] in {'0'..'9'}:
      let c = ord(s[i]) - ord('0')
      if b <= (high(int) - c) div 10:
        b = b * 10 + c
      else:
        b = high(int)
      inc(i)
      while i < s.len and s[i] == '_': inc(i) # underscores are allowed and ignored
    result = i

proc rawParseUInt(s: openArray[char], b: var BiggestUInt): int =
  var
    res = 0.BiggestUInt
    prev = 0.BiggestUInt
    i = 0
  if i < s.len - 1 and s[i] == '-' and s[i + 1] in {'0'..'9'}:
    integerOutOfRangeError()
  if i < s.len and s[i] == '+': inc(i) # Allow
  if i < s.len and s[i] in {'0'..'9'}:
    b = 0
    while i < s.len and s[i] in {'0'..'9'}:
      prev = res
      res = res * 10 + (ord(s[i]) - ord('0')).BiggestUInt
      if prev > res:
        integerOutOfRangeError()
      inc(i)
      while i < s.len and s[i] == '_': inc(i) # underscores are allowed and ignored
    b = res
    result = i

proc parseBiggestUInt*(s: openArray[char], number: var BiggestUInt): int {.
  rtl, extern: "npuParseBiggestUInt", noSideEffect, raises: [ValueError].} =
  ## Parses an unsigned integer and stores the value
  ## into `number`.
  ## `ValueError` is raised if the parsed integer is out of the valid range.
  runnableExamples:
    var res: BiggestUInt
    doAssert parseBiggestUInt("12", res, 0) == 2
    doAssert res == 12
    doAssert parseBiggestUInt("1111111111111111111", res, 0) == 19
    doAssert res == 1111111111111111111'u64
  var res = BiggestUInt(0)
  # use 'res' for exception safety (don't write to 'number' in case of an
  # overflow exception):
  result = rawParseUInt(s, res)
  if result != 0:
    number = res

proc parseUInt*(s: openArray[char], number: var uint): int {.
  rtl, extern: "npuParseUInt", noSideEffect, raises: [ValueError].} =
  ## Parses an unsigned integer and stores the value
  ## into `number`.
  ## `ValueError` is raised if the parsed integer is out of the valid range.
  runnableExamples:
    var res: uint
    doAssert parseUInt("3450", res) == 4
    doAssert res == 3450
    doAssert parseUInt("3450", res, 2) == 2
    doAssert res == 50
  var res = BiggestUInt(0)
  result = parseBiggestUInt(s, res)
  when sizeof(BiggestUInt) > sizeof(uint) and sizeof(uint) <= 4:
    if res > 0xFFFF_FFFF'u64:
      integerOutOfRangeError()
  if result != 0:
    number = uint(res)

proc parseBiggestFloat*(s: openArray[char], number: var BiggestFloat): int {.
  magic: "ParseBiggestFloat", importc: "nimParseBiggestFloat", noSideEffect.}
  ## Parses a float and stores the value into `number`.
  ## Result is the number of processed chars or 0 if a parsing error
  ## occurred.

proc parseFloat*(s: openArray[char], number: var float): int {.
  rtl, extern: "npuParseFloat", noSideEffect.} =
  ## Parses a float and stores the value into `number`.
  ## Result is the number of processed chars or 0 if there occurred a parsing
  ## error.
  runnableExamples:
    var res: float
    doAssert parseFloat("32", res, 0) == 2
    doAssert res == 32.0
    doAssert parseFloat("32.57", res, 0) == 5
    doAssert res == 32.57
    doAssert parseFloat("32.57", res, 3) == 2
    doAssert res == 57.00
  var bf = BiggestFloat(0.0)
  result = parseBiggestFloat(s, bf)
  if result != 0:
    number = bf

func toLowerAscii(c: char): char =
  if c in {'A'..'Z'}: char(uint8(c) xor 0b0010_0000'u8) else: c

func parseSize*(s: openArray[char], size: var int64, alwaysBin=false): int =
  ## Parse a size qualified by binary or metric units into `size`.  This format
  ## is often called "human readable".  Result is the number of processed chars
  ## or 0 on parse errors and size is rounded to the nearest integer.  Trailing
  ## garbage like "/s" in "1k/s" is allowed and detected by `result < s.len`.
  ##
  ## To simplify use, following non-rare wild conventions, and since fractional
  ## data like milli-bytes is so rare, unit matching is case-insensitive but for
  ## the 'i' distinguishing binary-metric from metric (which cannot be 'I').
  ##
  ## An optional trailing 'B|b' is ignored but processed.  I.e., you must still
  ## know if units are bytes | bits or infer this fact via the case of s[^1] (if
  ## users can even be relied upon to use 'B' for byte and 'b' for bit or have
  ## that be s[^1]).
  ##
  ## If `alwaysBin==true` then scales are always binary-metric, but e.g. "KiB"
  ## is still accepted for clarity.  If the value would exceed the range of
  ## `int64`, `size` saturates to `int64.high`.  Supported metric prefix chars
  ## include k, m, g, t, p, e, z, y (but z & y saturate unless the number is a
  ## small fraction).
  ##
  ## **See also:**
  ## * https://en.wikipedia.org/wiki/Binary_prefix
  ## * `formatSize module<strutils.html>`_ for formatting
  runnableExamples:
    var res: int64  # caller must still know if 'b' refers to bytes|bits
    doAssert parseSize("10.5 MB", res) == 7
    doAssert res == 10_500_000  # decimal metric Mega prefix
    doAssert parseSize("64 mib", res) == 6
    doAssert res == 67108864    # 64 shl 20
    doAssert parseSize("1G/h", res, true) == 2 # '/' stops parse
    doAssert res == 1073741824  # 1 shl 30, forced binary metric
  const prefix = "b" & "kmgtpezy"       # byte|bit & lowCase metric-ish prefixes
  const scaleM = [1.0, 1e3, 1e6, 1e9, 1e12, 1e15, 1e18, 1e21, 1e24] # 10^(3*idx)
  const scaleB = [1.0, 1024, 1048576, 1073741824, 1099511627776.0,  # 2^(10*idx)
                  1125899906842624.0, 1152921504606846976.0,        # ldexp?
                  1.180591620717411303424e21, 1.208925819614629174706176e24]
  var number: float
  var scale = 1.0
  result = parseFloat(s, number)
  if number < 0:                        # While parseFloat accepts negatives ..
    result = 0                          #.. we do not since sizes cannot be < 0
  if result > 0:
    let start = result                  # Save spot to maybe unwind white to EOS
    while result < s.len and s[result] in Whitespace:
      inc result
    if result < s.len:                  # Illegal starting char => unity
      if (let si = prefix.find(s[result].toLowerAscii); si >= 0):
        inc result                      # Now parse the scale
        scale = if alwaysBin: scaleB[si] else: scaleM[si]
        if result < s.len and s[result] == 'i':
          scale = scaleB[si]            # Switch from default to binary-metric
          inc result
        if result < s.len and s[result].toLowerAscii == 'b':
          inc result                    # Skip optional '[bB]'
    else:                               # Unwind result advancement when there..
      result = start                    #..is no unit to the end of `s`.
    var sizeF = number * scale + 0.5    # Saturate to int64.high when too big
    size = if sizeF > 9223372036854774784.0: int64.high else: sizeF.int64
# Above constant=2^63-1024 avoids C UB; github.com/nim-lang/Nim/issues/20102 or
# stackoverflow.com/questions/20923556/math-pow2-63-1-math-pow2-63-512-is-true

type
  InterpolatedKind* = enum ## Describes for `interpolatedFragments`
                           ## which part of the interpolated string is
                           ## yielded; for example in "str$$$var${expr}"
    ikStr,                 ## ``str`` part of the interpolated string
    ikDollar,              ## escaped ``$`` part of the interpolated string
    ikVar,                 ## ``var`` part of the interpolated string
    ikExpr                 ## ``expr`` part of the interpolated string

iterator interpolatedFragments*(s: openArray[char]): tuple[kind: InterpolatedKind,
  value: string] =
  ## Tokenizes the string `s` into substrings for interpolation purposes.
  ##
  runnableExamples:
    var outp: seq[tuple[kind: InterpolatedKind, value: string]]
    for k, v in interpolatedFragments("  $this is ${an  example}  $$"):
      outp.add (k, v)
    doAssert outp == @[(ikStr, "  "),
                       (ikVar, "this"),
                       (ikStr, " is "),
                       (ikExpr, "an  example"),
                       (ikStr, "  "),
                       (ikDollar, "$")]

  var i = 0
  var kind: InterpolatedKind
  while true:
    var j = i
    if j < s.len and s[j] == '$':
      if j+1 < s.len and s[j+1] == '{':
        inc j, 2
        var nesting = 0
        block curlies:
          while j < s.len:
            case s[j]
            of '{': inc nesting
            of '}':
              if nesting == 0:
                inc j
                break curlies
              dec nesting
            else: discard
            inc j
          raise newException(ValueError,
            "Expected closing '}': " & substr(s.toOpenArray(i, s.high)))
        inc i, 2 # skip ${
        kind = ikExpr
      elif j+1 < s.len and s[j+1] in IdentStartChars:
        inc j, 2
        while j < s.len and s[j] in IdentChars: inc(j)
        inc i # skip $
        kind = ikVar
      elif j+1 < s.len and s[j+1] == '$':
        inc j, 2
        inc i # skip $
        kind = ikDollar
      else:
        raise newException(ValueError,
          "Unable to parse a variable name at " & substr(s.toOpenArray(i, s.high)))
    else:
      while j < s.len and s[j] != '$': inc j
      kind = ikStr
    if j > i:
      # do not copy the trailing } for ikExpr:
      yield (kind, substr(s.toOpenArray(i, j-1-ord(kind == ikExpr))))
    else:
      break
    i = j

{.pop.}


proc parseBin*[T: SomeInteger](s: string, number: var T, start = 0,
    maxLen = 0): int {.noSideEffect.} =
  ## Parses a binary number and stores its value in ``number``.
  ##
  ## Returns the number of the parsed characters or 0 in case of an error.
  ## If error, the value of ``number`` is not changed.
  ##
  ## If ``maxLen == 0``, the parsing continues until the first non-bin character
  ## or to the end of the string. Otherwise, no more than ``maxLen`` characters
  ## are parsed starting from the ``start`` position.
  ##
  ## It does not check for overflow. If the value represented by the string is
  ## too big to fit into ``number``, only the value of last fitting characters
  ## will be stored in ``number`` without producing an error.
  runnableExamples:
    var num: int
    doAssert parseBin("0100_1110_0110_1001_1110_1101", num) == 29
    doAssert num == 5138925
    doAssert parseBin("3", num) == 0
    var num8: int8
    doAssert parseBin("0b_0100_1110_0110_1001_1110_1101", num8) == 32
    doAssert num8 == 0b1110_1101'i8
    doAssert parseBin("0b_0100_1110_0110_1001_1110_1101", num8, 3, 9) == 9
    doAssert num8 == 0b0100_1110'i8
    var num8u: uint8
    doAssert parseBin("0b_0100_1110_0110_1001_1110_1101", num8u) == 32
    doAssert num8u == 237
    var num64: int64
    doAssert parseBin("0100111001101001111011010100111001101001", num64) == 40
    doAssert num64 == 336784608873
  parseBin(s.toOpenArray(start, s.high), number, maxLen)

proc parseOct*[T: SomeInteger](s: string, number: var T, start = 0,
    maxLen = 0): int {.noSideEffect.} =
  ## Parses an octal number and stores its value in ``number``.
  ##
  ## Returns the number of the parsed characters or 0 in case of an error.
  ## If error, the value of ``number`` is not changed.
  ##
  ## If ``maxLen == 0``, the parsing continues until the first non-oct character
  ## or to the end of the string. Otherwise, no more than ``maxLen`` characters
  ## are parsed starting from the ``start`` position.
  ##
  ## It does not check for overflow. If the value represented by the string is
  ## too big to fit into ``number``, only the value of last fitting characters
  ## will be stored in ``number`` without producing an error.
  runnableExamples:
    var num: int
    doAssert parseOct("0o23464755", num) == 10
    doAssert num == 5138925
    doAssert parseOct("8", num) == 0
    var num8: int8
    doAssert parseOct("0o_1464_755", num8) == 11
    doAssert num8 == -19
    doAssert parseOct("0o_1464_755", num8, 3, 3) == 3
    doAssert num8 == 102
    var num8u: uint8
    doAssert parseOct("1464755", num8u) == 7
    doAssert num8u == 237
    var num64: int64
    doAssert parseOct("2346475523464755", num64) == 16
    doAssert num64 == 86216859871725
  parseOct(s.toOpenArray(start, s.high), number, maxLen)

proc parseHex*[T: SomeInteger](s: string, number: var T, start = 0,
    maxLen = 0): int {.noSideEffect.} =
  ## Parses a hexadecimal number and stores its value in ``number``.
  ##
  ## Returns the number of the parsed characters or 0 in case of an error.
  ## If error, the value of ``number`` is not changed.
  ##
  ## If ``maxLen == 0``, the parsing continues until the first non-hex character
  ## or to the end of the string. Otherwise, no more than ``maxLen`` characters
  ## are parsed starting from the ``start`` position.
  ##
  ## It does not check for overflow. If the value represented by the string is
  ## too big to fit into ``number``, only the value of last fitting characters
  ## will be stored in ``number`` without producing an error.
  runnableExamples:
    var num: int
    doAssert parseHex("4E_69_ED", num) == 8
    doAssert num == 5138925
    doAssert parseHex("X", num) == 0
    doAssert parseHex("#ABC", num) == 4
    var num8: int8
    doAssert parseHex("0x_4E_69_ED", num8) == 11
    doAssert num8 == 0xED'i8
    doAssert parseHex("0x_4E_69_ED", num8, 3, 2) == 2
    doAssert num8 == 0x4E'i8
    var num8u: uint8
    doAssert parseHex("0x_4E_69_ED", num8u) == 11
    doAssert num8u == 237
    var num64: int64
    doAssert parseHex("4E69ED4E69ED", num64) == 12
    doAssert num64 == 86216859871725
  parseHex(s.toOpenArray(start, s.high), number, maxLen)

proc parseIdent*(s: string, ident: var string, start = 0): int =
  ## Parses an identifier and stores it in ``ident``. Returns
  ## the number of the parsed characters or 0 in case of an error.
  ## If error, the value of `ident` is not changed.
  runnableExamples:
    var res: string
    doAssert parseIdent("Hello World", res, 0) == 5
    doAssert res == "Hello"
    doAssert parseIdent("Hello World", res, 1) == 4
    doAssert res == "ello"
    doAssert parseIdent("Hello World", res, 6) == 5
    doAssert res == "World"
  parseIdent(s.toOpenArray(start, s.high), ident)

proc parseIdent*(s: string, start = 0): string =
  ## Parses an identifier and returns it or an empty string in
  ## case of an error.
  runnableExamples:
    doAssert parseIdent("Hello World", 0) == "Hello"
    doAssert parseIdent("Hello World", 1) == "ello"
    doAssert parseIdent("Hello World", 5) == ""
    doAssert parseIdent("Hello World", 6) == "World"
  parseIdent(s.toOpenArray(start, s.high))

proc parseChar*(s: string, c: var char, start = 0): int =
  ## Parses a single character, stores it in `c` and returns 1.
  ## In case of error (if start >= s.len) it returns 0
  ## and the value of `c` is unchanged.
  runnableExamples:
    var c: char
    doAssert "nim".parseChar(c, 3) == 0
    doAssert c == '\0'
    doAssert "nim".parseChar(c, 0) == 1
    doAssert c == 'n'
  parseChar(s.toOpenArray(start, s.high), c)

proc skipWhitespace*(s: string, start = 0): int {.inline.} =
  ## Skips the whitespace starting at ``s[start]``. Returns the number of
  ## skipped characters.
  runnableExamples:
    doAssert skipWhitespace("Hello World", 0) == 0
    doAssert skipWhitespace(" Hello World", 0) == 1
    doAssert skipWhitespace("Hello World", 5) == 1
    doAssert skipWhitespace("Hello  World", 5) == 2
  skipWhitespace(s.toOpenArray(start, s.high))

proc skip*(s, token: string, start = 0): int {.inline.} =
  ## Skips the `token` starting at ``s[start]``. Returns the length of `token`
  ## or 0 if there was no `token` at ``s[start]``.
  runnableExamples:
    doAssert skip("2019-01-22", "2019", 0) == 4
    doAssert skip("2019-01-22", "19", 0) == 0
    doAssert skip("2019-01-22", "19", 2) == 2
    doAssert skip("CAPlow", "CAP", 0) == 3
    doAssert skip("CAPlow", "cap", 0) == 0
  skip(s.toOpenArray(start, s.high), token)

proc skipIgnoreCase*(s, token: string, start = 0): int =
  ## Same as `skip` but case is ignored for token matching.
  runnableExamples:
    doAssert skipIgnoreCase("CAPlow", "CAP", 0) == 3
    doAssert skipIgnoreCase("CAPlow", "cap", 0) == 3
  skipIgnoreCase(s.toOpenArray(start, s.high), token)

proc skipUntil*(s: string, until: set[char], start = 0): int {.inline.} =
  ## Skips all characters until one char from the set `until` is found
  ## or the end is reached.
  ## Returns number of characters skipped.
  runnableExamples:
    doAssert skipUntil("Hello World", {'W', 'e'}, 0) == 1
    doAssert skipUntil("Hello World", {'W'}, 0) == 6
    doAssert skipUntil("Hello World", {'W', 'd'}, 0) == 6
  skipUntil(s.toOpenArray(start, s.high), until)

proc skipUntil*(s: string, until: char, start = 0): int {.inline.} =
  ## Skips all characters until the char `until` is found
  ## or the end is reached.
  ## Returns number of characters skipped.
  runnableExamples:
    doAssert skipUntil("Hello World", 'o', 0) == 4
    doAssert skipUntil("Hello World", 'o', 4) == 0
    doAssert skipUntil("Hello World", 'W', 0) == 6
    doAssert skipUntil("Hello World", 'w', 0) == 11
  skipUntil(s.toOpenArray(start, s.high), until)

proc skipWhile*(s: string, toSkip: set[char], start = 0): int {.inline.} =
  ## Skips all characters while one char from the set `toSkip` is found.
  ## Returns number of characters skipped.
  runnableExamples:
    doAssert skipWhile("Hello World", {'H', 'e'}) == 2
    doAssert skipWhile("Hello World", {'e'}) == 0
    doAssert skipWhile("Hello World", {'W', 'o', 'r'}, 6) == 3
  skipWhile(s.toOpenArray(start, s.high), toSkip)

proc parseUntil*(s: string, token: var string, until: set[char],
                 start = 0): int {.inline.} =
  ## Parses a token and stores it in ``token``. Returns
  ## the number of the parsed characters or 0 in case of an error. A token
  ## consists of the characters notin `until`.
  runnableExamples:
    var myToken: string
    doAssert parseUntil("Hello World", myToken, {'W', 'o', 'r'}) == 4
    doAssert myToken == "Hell"
    doAssert parseUntil("Hello World", myToken, {'W', 'r'}) == 6
    doAssert myToken == "Hello "
    doAssert parseUntil("Hello World", myToken, {'W', 'r'}, 3) == 3
    doAssert myToken == "lo "
  parseUntil(s.toOpenArray(start, s.high), token, until)

proc parseUntil*(s: string, token: var string, until: char,
                 start = 0): int {.inline.} =
  ## Parses a token and stores it in ``token``. Returns
  ## the number of the parsed characters or 0 in case of an error. A token
  ## consists of any character that is not the `until` character.
  runnableExamples:
    var myToken: string
    doAssert parseUntil("Hello World", myToken, 'W') == 6
    doAssert myToken == "Hello "
    doAssert parseUntil("Hello World", myToken, 'o') == 4
    doAssert myToken == "Hell"
    doAssert parseUntil("Hello World", myToken, 'o', 2) == 2
    doAssert myToken == "ll"
  parseUntil(s.toOpenArray(start, s.high), token, until)

proc parseUntil*(s: string, token: var string, until: string,
                 start = 0): int {.inline.} =
  ## Parses a token and stores it in ``token``. Returns
  ## the number of the parsed characters or 0 in case of an error. A token
  ## consists of any character that comes before the `until`  token.
  runnableExamples:
    var myToken: string
    doAssert parseUntil("Hello World", myToken, "Wor") == 6
    doAssert myToken == "Hello "
    doAssert parseUntil("Hello World", myToken, "Wor", 2) == 4
    doAssert myToken == "llo "
  parseUntil(s.toOpenArray(start, s.high), token, until)

proc parseWhile*(s: string, token: var string, validChars: set[char],
                 start = 0): int {.inline.} =
  ## Parses a token and stores it in ``token``. Returns
  ## the number of the parsed characters or 0 in case of an error. A token
  ## consists of the characters in `validChars`.
  runnableExamples:
    var myToken: string
    doAssert parseWhile("Hello World", myToken, {'W', 'o', 'r'}, 0) == 0
    doAssert myToken.len() == 0
    doAssert parseWhile("Hello World", myToken, {'W', 'o', 'r'}, 6) == 3
    doAssert myToken == "Wor"
  parseWhile(s.toOpenArray(start, s.high), token, validChars)

proc captureBetween*(s: string, first: char, second = '\0', start = 0): string =
  ## Finds the first occurrence of ``first``, then returns everything from there
  ## up to ``second`` (if ``second`` is '\0', then ``first`` is used).
  runnableExamples:
    doAssert captureBetween("Hello World", 'e') == "llo World"
    doAssert captureBetween("Hello World", 'e', 'r') == "llo Wo"
    doAssert captureBetween("Hello World", 'l', start = 6) == "d"
  captureBetween(s.toOpenArray(start, s.high), first, second)

proc parseBiggestInt*(s: string, number: var BiggestInt, start = 0): int {.noSideEffect, raises: [ValueError].} =
  ## Parses an integer starting at `start` and stores the value into `number`.
  ## Result is the number of processed chars or 0 if there is no integer.
  ## `ValueError` is raised if the parsed integer is out of the valid range.
  runnableExamples:
    var res: BiggestInt
    doAssert parseBiggestInt("9223372036854775807", res, 0) == 19
    doAssert res == 9223372036854775807
    doAssert parseBiggestInt("-2024_05_09", res) == 11
    doAssert res == -20240509
    doAssert parseBiggestInt("-2024_05_02", res, 7) == 4
    doAssert res == 502
  parseBiggestInt(s.toOpenArray(start, s.high), number)

proc parseInt*(s: string, number: var int, start = 0): int {.noSideEffect, raises: [ValueError].} =
  ## Parses an integer starting at `start` and stores the value into `number`.
  ## Result is the number of processed chars or 0 if there is no integer.
  ## `ValueError` is raised if the parsed integer is out of the valid range.
  runnableExamples:
    var res: int
    doAssert parseInt("-2024_05_02", res) == 11
    doAssert res == -20240502
    doAssert parseInt("-2024_05_02", res, 7) == 4
    doAssert res == 502
  parseInt(s.toOpenArray(start, s.high), number)


proc parseSaturatedNatural*(s: string, b: var int, start = 0): int {.
    raises: [].} =
  ## Parses a natural number into ``b``. This cannot raise an overflow
  ## error. ``high(int)`` is returned for an overflow.
  ## The number of processed character is returned.
  ## This is usually what you really want to use instead of `parseInt`:idx:.
  runnableExamples:
    var res = 0
    discard parseSaturatedNatural("848", res)
    doAssert res == 848
  parseSaturatedNatural(s.toOpenArray(start, s.high), b)


proc parseBiggestUInt*(s: string, number: var BiggestUInt, start = 0): int {.noSideEffect, raises: [ValueError].} =
  ## Parses an unsigned integer starting at `start` and stores the value
  ## into `number`.
  ## `ValueError` is raised if the parsed integer is out of the valid range.
  runnableExamples:
    var res: BiggestUInt
    doAssert parseBiggestUInt("12", res, 0) == 2
    doAssert res == 12
    doAssert parseBiggestUInt("1111111111111111111", res, 0) == 19
    doAssert res == 1111111111111111111'u64
  parseBiggestUInt(s.toOpenArray(start, s.high), number)

proc parseUInt*(s: string, number: var uint, start = 0): int {.noSideEffect, raises: [ValueError].} =
  ## Parses an unsigned integer starting at `start` and stores the value
  ## into `number`.
  ## `ValueError` is raised if the parsed integer is out of the valid range.
  runnableExamples:
    var res: uint
    doAssert parseUInt("3450", res) == 4
    doAssert res == 3450
    doAssert parseUInt("3450", res, 2) == 2
    doAssert res == 50
  parseUInt(s.toOpenArray(start, s.high), number)

proc parseBiggestFloat*(s: string, number: var BiggestFloat, start = 0): int {.noSideEffect.} =
  ## Parses a float starting at `start` and stores the value into `number`.
  ## Result is the number of processed chars or 0 if a parsing error
  ## occurred.
  parseFloat(s.toOpenArray(start, s.high), number)

proc parseFloat*(s: string, number: var float, start = 0): int {.noSideEffect.} =
  ## Parses a float starting at `start` and stores the value into `number`.
  ## Result is the number of processed chars or 0 if there occurred a parsing
  ## error.
  runnableExamples:
    var res: float
    doAssert parseFloat("32", res, 0) == 2
    doAssert res == 32.0
    doAssert parseFloat("32.57", res, 0) == 5
    doAssert res == 32.57
    doAssert parseFloat("32.57", res, 3) == 2
    doAssert res == 57.00
  parseFloat(s.toOpenArray(start, s.high), number)

iterator interpolatedFragments*(s: string): tuple[kind: InterpolatedKind,
  value: string] =
  ## Tokenizes the string `s` into substrings for interpolation purposes.
  ##
  runnableExamples:
    var outp: seq[tuple[kind: InterpolatedKind, value: string]]
    for k, v in interpolatedFragments("  $this is ${an  example}  $$"):
      outp.add (k, v)
    doAssert outp == @[(ikStr, "  "),
                       (ikVar, "this"),
                       (ikStr, " is "),
                       (ikExpr, "an  example"),
                       (ikStr, "  "),
                       (ikDollar, "$")]
  for x in s.toOa.interpolatedFragments:
    yield x


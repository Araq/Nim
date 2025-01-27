#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

when defined(js):
  {.error: "This library needs to be compiled with a c-like backend, and depends on PCRE; See jsre for JS backend.".}

## Regular expression support for Nim.
##
## This module is implemented by providing a wrapper around the
## `PCRE (Perl-Compatible Regular Expressions) <https://www.pcre.org>`_
## C library. This means that your application will depend on the PCRE
## library's licence when using this module, which should not be a problem
## though.
##
## .. note:: There are also alternative nimble packages such as [tinyre](https://github.com/khchen/tinyre)
##   and [regex](https://github.com/nitely/nim-regex).
##
## PCRE's licence follows:
##
## .. include:: ../../doc/regexprs.txt
##

runnableExamples:
  ## Unless specified otherwise, `start` parameter in each proc indicates
  ## where the scan starts, but outputs are relative to the start of the input
  ## string, not to `start`:
  doAssert find("uxabc", re"(?<=x|y)ab", start = 1) == 2 # lookbehind assertion
  doAssert find("uxabc", re"ab", start = 3) == -1 # we're past `start` => not found
  doAssert not match("xabc", re"^abc$", start = 1)
    # can't match start of string since we're starting at 1

import
  std/[pcre, strutils, rtarrays]

when defined(nimPreviewSlimSystem):
  import std/syncio

const
  MaxSubpatterns* = 20
    ## defines the maximum number of subpatterns that can be captured.
    ## This limit still exists for `replacef` and `parallelReplace`.

type
  RegexFlag* = enum     ## options for regular expressions
    reIgnoreCase = 0,   ## do caseless matching
    reMultiLine = 1,    ## `^` and `$` match newlines within data
    reDotAll = 2,       ## `.` matches anything including NL
    reExtended = 3,     ## ignore whitespace and `#` comments
    reStudy = 4         ## study the expression (may be omitted if the
                        ## expression will be used only once)

  RegexDesc = object
    h: ptr Pcre
    e: ptr ExtraData

  Regex* = ref RegexDesc ## a compiled regular expression

  RegexError* = object of ValueError
    ## is raised if the pattern is no valid regular expression.

when defined(gcDestructors):
  when defined(nimAllowNonVarDestructor):
    proc `=destroy`(x: RegexDesc) =
      pcre.free_substring(cast[cstring](x.h))
      if not isNil(x.e):
        pcre.free_study(x.e)
  else:
    proc `=destroy`(x: var RegexDesc) =
      pcre.free_substring(cast[cstring](x.h))
      if not isNil(x.e):
        pcre.free_study(x.e)

proc raiseInvalidRegex(msg: string) {.noinline, noreturn.} =
  var e: ref RegexError
  new(e)
  e.msg = msg
  raise e

proc rawCompile(pattern: string, flags: cint): ptr Pcre =
  var
    msg: cstring = ""
    offset: cint = 0
  result = pcre.compile(pattern, flags, addr(msg), addr(offset), nil)
  if result == nil:
    raiseInvalidRegex($msg & "\n" & pattern & "\n" & spaces(offset) & "^\n")

proc finalizeRegEx(x: Regex) =
  # XXX This is a hack, but PCRE does not export its "free" function properly.
  # Sigh. The hack relies on PCRE's implementation (see `pcre_get.c`).
  # Fortunately the implementation is unlikely to change.
  pcre.free_substring(cast[cstring](x.h))
  if not isNil(x.e):
    pcre.free_study(x.e)

proc re*(s: string, flags = {reStudy}): Regex =
  ## Constructor of regular expressions.
  ##
  ## Note that Nim's
  ## extended raw string literals support the syntax `re"[abc]"` as
  ## a short form for `re(r"[abc]")`. Also note that since this
  ## compiles the regular expression, which is expensive, you should
  ## avoid putting it directly in the arguments of the functions like
  ## the examples show below if you plan to use it a lot of times, as
  ## this will hurt performance immensely. (e.g. outside a loop, ...)
  when defined(gcDestructors):
    result = Regex()
  else:
    new(result, finalizeRegEx)
  result.h = rawCompile(s, cast[cint](flags - {reStudy}))
  if reStudy in flags:
    var msg: cstring = ""
    var options: cint = 0
    var hasJit: cint = 0
    if pcre.config(pcre.CONFIG_JIT, addr hasJit) == 0:
      if hasJit == 1'i32:
        options = pcre.STUDY_JIT_COMPILE
    result.e = pcre.study(result.h, options, addr msg)
    if not isNil(msg): raiseInvalidRegex($msg)

proc rex*(s: string, flags = {reStudy, reExtended}): Regex =
  ## Constructor for extended regular expressions.
  ##
  ## The extended means that comments starting with `#` and
  ## whitespace are ignored.
  result = re(s, flags)

proc bufSubstr(b: cstring, sPos, ePos: int): string {.inline.} =
  ## Return a Nim string built from a slice of a cstring buffer.
  ## Don't assume cstring is '\0' terminated
  let sz = ePos - sPos
  result = newString(sz+1)
  copyMem(addr(result[0]), unsafeAddr(b[sPos]), sz)
  result.setLen(sz)

proc matchOrFind(buf: cstring, pattern: Regex, matches: var openArray[string],
                 start, bufSize, flags: cint): cint =
  var
    rtarray = initRtArray[cint]((matches.len+1)*3)
    rawMatches = rtarray.getRawData
    res = pcre.exec(pattern.h, pattern.e, buf, bufSize, start, flags,
      cast[ptr cint](rawMatches), (matches.len+1).cint*3)
  if res < 0'i32: return res
  for i in 1..int(res)-1:
    var a = rawMatches[i * 2]
    var b = rawMatches[i * 2 + 1]
    if a >= 0'i32:
      matches[i-1] = bufSubstr(buf, int(a), int(b))
    else: matches[i-1] = ""
  return rawMatches[1] - rawMatches[0]

const MaxReBufSize* = high(cint)
  ## Maximum PCRE (API 1) buffer start/size equal to `high(cint)`, which even
  ## for 64-bit systems can be either 2`31`:sup:-1 or 2`63`:sup:-1.

proc findBounds*(buf: cstring, pattern: Regex, matches: var openArray[string],
                 start = 0, bufSize: int): tuple[first, last: int] =
  ## returns the starting position and end position of `pattern` in `buf`
  ## (where `buf` has length `bufSize` and is not necessarily `'\0'` terminated),
  ## and the captured
  ## substrings in the array `matches`. If it does not match, nothing
  ## is written into `matches` and `(-1,0)` is returned.
  ##
  ## Note: The memory for `matches` needs to be allocated before this function is
  ## called, otherwise it will just remain empty.
  var
    rtarray = initRtArray[cint]((matches.len+1)*3)
    rawMatches = rtarray.getRawData
    res = pcre.exec(pattern.h, pattern.e, buf, bufSize.cint, start.cint, 0'i32,
      cast[ptr cint](rawMatches), (matches.len+1).cint*3)
  if res < 0'i32: return (-1, 0)
  for i in 1..int(res)-1:
    var a = rawMatches[i * 2]
    var b = rawMatches[i * 2 + 1]
    if a >= 0'i32: matches[i-1] = bufSubstr(buf, int(a), int(b))
    else: matches[i-1] = ""
  return (rawMatches[0].int, rawMatches[1].int - 1)

proc findBounds*(s: string, pattern: Regex, matches: var openArray[string],
                 start = 0): tuple[first, last: int] {.inline.} =
  ## returns the starting position and end position of `pattern` in `s`
  ## and the captured substrings in the array `matches`.
  ## If it does not match, nothing
  ## is written into `matches` and `(-1,0)` is returned.
  ##
  ## .. note:: The memory for `matches` needs to be allocated before this function is called, otherwise it will just remain empty.
  runnableExamples:
    var matches = newSeq[string](1)
    let (first, last) = findBounds("Hello World", re"(W\w+)", matches)
    doAssert first == 6
    doAssert last == 10
    doAssert matches[0] == "World"
  result = findBounds(cstring(s), pattern, matches,
      min(start, MaxReBufSize), min(s.len, MaxReBufSize))

proc findBounds*(buf: cstring, pattern: Regex,
                 matches: var openArray[tuple[first, last: int]],
                 start = 0, bufSize: int): tuple[first, last: int] =
  ## returns the starting position and end position of `pattern` in `buf`
  ## (where `buf` has length `bufSize` and is not necessarily `'\0'` terminated),
  ## and the captured substrings in the array `matches`.
  ## If it does not match, nothing is written into `matches` and
  ## `(-1,0)` is returned.
  ##
  ## .. note:: The memory for `matches` needs to be allocated before this function is called, otherwise it will just remain empty.
  var
    rtarray = initRtArray[cint]((matches.len+1)*3)
    rawMatches = rtarray.getRawData
    res = pcre.exec(pattern.h, pattern.e, buf, bufSize.cint, start.cint, 0'i32,
      cast[ptr cint](rawMatches), (matches.len+1).cint*3)
  if res < 0'i32: return (-1, 0)
  for i in 1..int(res)-1:
    var a = rawMatches[i * 2]
    var b = rawMatches[i * 2 + 1]
    if a >= 0'i32: matches[i-1] = (int(a), int(b)-1)
    else: matches[i-1] = (-1,0)
  return (rawMatches[0].int, rawMatches[1].int - 1)

proc findBounds*(s: string, pattern: Regex,
                 matches: var openArray[tuple[first, last: int]],
                 start = 0): tuple[first, last: int] {.inline.} =
  ## returns the starting position and end position of `pattern` in `s`
  ## and the captured substrings in the array `matches`.
  ## If it does not match, nothing is written into `matches` and
  ## `(-1,0)` is returned.
  ##
  ## .. note:: The memory for `matches` needs to be allocated before this function is called, otherwise it will just remain empty.
  runnableExamples:
    var matches = newSeq[tuple[first, last: int]](1)
    let (first, last) = findBounds("Hello World", re"(\w+)", matches)
    doAssert first == 0
    doAssert last == 4
    doAssert matches[0] == (0, 4)
  result = findBounds(cstring(s), pattern, matches,
      min(start, MaxReBufSize), min(s.len, MaxReBufSize))

proc findBoundsImpl(buf: cstring, pattern: Regex,
                    start = 0, bufSize = 0, flags = 0): tuple[first, last: int] =
  var rtarray = initRtArray[cint](3)
  let rawMatches = rtarray.getRawData
  let res = pcre.exec(pattern.h, pattern.e, buf, bufSize.cint, start.cint, flags.int32,
                cast[ptr cint](rawMatches), 3)

  if res < 0'i32:
    result = (-1, 0)
  else:
    result = (int(rawMatches[0]), int(rawMatches[1]-1))

proc findBounds*(buf: cstring, pattern: Regex,
                 start = 0, bufSize: int): tuple[first, last: int] =
  ## returns the `first` and `last` position of `pattern` in `buf`,
  ## where `buf` has length `bufSize` (not necessarily `'\0'` terminated).
  ## If it does not match, `(-1,0)` is returned.
  var
    rtarray = initRtArray[cint](3)
    rawMatches = rtarray.getRawData
    res = pcre.exec(pattern.h, pattern.e, buf, bufSize.cint, start.cint, 0'i32,
      cast[ptr cint](rawMatches), 3)
  if res < 0'i32: return (int(res), 0)
  return (int(rawMatches[0]), int(rawMatches[1]-1))

proc findBounds*(s: string, pattern: Regex,
                 start = 0): tuple[first, last: int] {.inline.} =
  ## returns the `first` and `last` position of `pattern` in `s`.
  ## If it does not match, `(-1,0)` is returned.
  ##
  ## Note: there is a speed improvement if the matches do not need to be captured.
  runnableExamples:
    assert findBounds("01234abc89", re"abc") == (5,7)
  result = findBounds(cstring(s), pattern,
      min(start, MaxReBufSize), min(s.len, MaxReBufSize))

proc matchOrFind(buf: cstring, pattern: Regex, start, bufSize: int, flags: cint): cint =
  var
    rtarray = initRtArray[cint](3)
    rawMatches = rtarray.getRawData
  result = pcre.exec(pattern.h, pattern.e, buf, bufSize.cint, start.cint, flags,
                    cast[ptr cint](rawMatches), 3)
  if result >= 0'i32:
    result = rawMatches[1] - rawMatches[0]

proc matchLen*(s: string, pattern: Regex, matches: var openArray[string],
              start = 0): int {.inline.} =
  ## the same as `match`, but it returns the length of the match,
  ## if there is no match, `-1` is returned. Note that a match length
  ## of zero can happen.
  ##
  ## .. note:: The memory for `matches` needs to be allocated before this function is called, otherwise it will just remain empty.
  result = matchOrFind(cstring(s), pattern, matches, start.cint, s.len.cint, pcre.ANCHORED)

proc matchLen*(buf: cstring, pattern: Regex, matches: var openArray[string],
              start = 0, bufSize: int): int {.inline.} =
  ## the same as `match`, but it returns the length of the match,
  ## if there is no match, `-1` is returned. Note that a match length
  ## of zero can happen.
  ##
  ## .. note:: The memory for `matches` needs to be allocated before this function is called, otherwise it will just remain empty.
  return matchOrFind(buf, pattern, matches, start.cint, bufSize.cint, pcre.ANCHORED)

proc matchLen*(s: string, pattern: Regex, start = 0): int {.inline.} =
  ## the same as `match`, but it returns the length of the match,
  ## if there is no match, `-1` is returned. Note that a match length
  ## of zero can happen.
  ##
  runnableExamples:
    doAssert matchLen("abcdefg", re"cde", 2) == 3
    doAssert matchLen("abcdefg", re"abcde") == 5
    doAssert matchLen("abcdefg", re"cde") == -1
  result = matchOrFind(cstring(s), pattern, start.cint, s.len.cint, pcre.ANCHORED)

proc matchLen*(buf: cstring, pattern: Regex, start = 0, bufSize: int): int {.inline.} =
  ## the same as `match`, but it returns the length of the match,
  ## if there is no match, `-1` is returned. Note that a match length
  ## of zero can happen.
  result = matchOrFind(buf, pattern, start.cint, bufSize, pcre.ANCHORED)

proc match*(s: string, pattern: Regex, start = 0): bool {.inline.} =
  ## returns `true` if `s[start..]` matches the `pattern`.
  result = matchLen(cstring(s), pattern, start, s.len) != -1

proc match*(s: string, pattern: Regex, matches: var openArray[string],
           start = 0): bool {.inline.} =
  ## returns `true` if `s[start..]` matches the `pattern` and
  ## the captured substrings in the array `matches`. If it does not
  ## match, nothing is written into `matches` and `false` is
  ## returned.
  ##
  ## .. note:: The memory for `matches` needs to be allocated before this function is called, otherwise it will just remain empty.
  runnableExamples:
    import std/sequtils
    var matches: array[2, string]
    if match("abcdefg", re"c(d)ef(g)", matches, 2):
      doAssert toSeq(matches) == @["d", "g"]
  result = matchLen(cstring(s), pattern, matches, start, s.len) != -1

proc match*(buf: cstring, pattern: Regex, matches: var openArray[string],
           start = 0, bufSize: int): bool {.inline.} =
  ## returns `true` if `buf[start..<bufSize]` matches the `pattern` and
  ## the captured substrings in the array `matches`. If it does not
  ## match, nothing is written into `matches` and `false` is
  ## returned.
  ## `buf` has length `bufSize` (not necessarily `'\0'` terminated).
  ##
  ## .. note:: The memory for `matches` needs to be allocated before this function is called, otherwise it will just remain empty.
  result = matchLen(buf, pattern, matches, start, bufSize) != -1

proc find*(buf: cstring, pattern: Regex, matches: var openArray[string],
           start = 0, bufSize: int): int =
  ## returns the starting position of `pattern` in `buf` and the captured
  ## substrings in the array `matches`. If it does not match, nothing
  ## is written into `matches` and `-1` is returned.
  ## `buf` has length `bufSize` (not necessarily `'\0'` terminated).
  ##
  ## .. note:: The memory for `matches` needs to be allocated before this function is called, otherwise it will just remain empty.
  var
    rtarray = initRtArray[cint]((matches.len+1)*3)
    rawMatches = rtarray.getRawData
    res = pcre.exec(pattern.h, pattern.e, buf, bufSize.cint, start.cint, 0'i32,
      cast[ptr cint](rawMatches), (matches.len+1).cint*3)
  if res < 0'i32: return res
  for i in 1..int(res)-1:
    var a = rawMatches[i * 2]
    var b = rawMatches[i * 2 + 1]
    if a >= 0'i32: matches[i-1] = bufSubstr(buf, int(a), int(b))
    else: matches[i-1] = ""
  return rawMatches[0]

proc find*(s: string, pattern: Regex, matches: var openArray[string],
           start = 0): int {.inline.} =
  ## returns the starting position of `pattern` in `s` and the captured
  ## substrings in the array `matches`. If it does not match, nothing
  ## is written into `matches` and `-1` is returned.
  ##
  ## .. note:: The memory for `matches` needs to be allocated before this function is called, otherwise it will just remain empty.
  result = find(cstring(s), pattern, matches, start, s.len)

proc find*(buf: cstring, pattern: Regex, start = 0, bufSize: int): int =
  ## returns the starting position of `pattern` in `buf`,
  ## where `buf` has length `bufSize` (not necessarily `'\0'` terminated).
  ## If it does not match, `-1` is returned.
  var
    rtarray = initRtArray[cint](3)
    rawMatches = rtarray.getRawData
    res = pcre.exec(pattern.h, pattern.e, buf, bufSize.cint, start.cint, 0'i32,
      cast[ptr cint](rawMatches), 3)
  if res < 0'i32: return res
  return rawMatches[0]

proc find*(s: string, pattern: Regex, start = 0): int {.inline.} =
  ## returns the starting position of `pattern` in `s`. If it does not
  ## match, `-1` is returned. We start the scan at `start`.
  runnableExamples:
    doAssert find("abcdefg", re"cde") == 2
    doAssert find("abcdefg", re"abc") == 0
    doAssert find("abcdefg", re"zz") == -1 # not found
    doAssert find("abcdefg", re"cde", start = 2) == 2 # still 2
    doAssert find("abcdefg", re"cde", start = 3) == -1 # we're past the start position
    doAssert find("xabc", re"(?<=x|y)abc", start = 1) == 1
      # lookbehind assertion `(?<=x|y)` can look behind `start`
  result = find(cstring(s), pattern, start, s.len)

iterator findAll*(s: string, pattern: Regex, start = 0): string =
  ## Yields all matching *substrings* of `s` that match `pattern`.
  ##
  ## Note that since this is an iterator you should not modify the string you
  ## are iterating over: bad things could happen.
  var
    i = int32(start)
    rtarray = initRtArray[cint](3)
    rawMatches = rtarray.getRawData
  while true:
    let res = pcre.exec(pattern.h, pattern.e, s, len(s).cint, i, 0'i32,
      cast[ptr cint](rawMatches), 3)
    if res < 0'i32: break
    let a = rawMatches[0]
    let b = rawMatches[1]
    if a == b and a == i: break
    yield substr(s, int(a), int(b)-1)
    i = b

iterator findAll*(buf: cstring, pattern: Regex, start = 0, bufSize: int): string =
  ## Yields all matching `substrings` of `s` that match `pattern`.
  ##
  ## Note that since this is an iterator you should not modify the string you
  ## are iterating over: bad things could happen.
  var
    i = int32(start)
    rtarray = initRtArray[cint](3)
    rawMatches = rtarray.getRawData
  while true:
    let res = pcre.exec(pattern.h, pattern.e, buf, bufSize.cint, i, 0'i32,
      cast[ptr cint](rawMatches), 3)
    if res < 0'i32: break
    let a = rawMatches[0]
    let b = rawMatches[1]
    if a == b and a == i: break
    var str = newString(b-a)
    copyMem(str[0].addr, unsafeAddr(buf[a]), b-a)
    yield str
    i = b

proc findAll*(s: string, pattern: Regex, start = 0): seq[string] {.inline.} =
  ## returns all matching `substrings` of `s` that match `pattern`.
  ## If it does not match, `@[]` is returned.
  result = @[]
  for x in findAll(s, pattern, start): result.add x

template `=~` *(s: string, pattern: Regex): untyped =
  ## This calls `match` with an implicit declared `matches` array that
  ## can be used in the scope of the `=~` call:
  runnableExamples:
    proc parse(line: string): string =
      if line =~ re"\s*(\w+)\s*\=\s*(\w+)": # matches a key=value pair:
        result = $(matches[0], matches[1])
      elif line =~ re"\s*(\#.*)": # matches a comment
        # note that the implicit `matches` array is different from 1st branch
        result = $(matches[0],)
      else: raiseAssert "unreachable"
      doAssert not declared(matches)
    doAssert parse("NAME = LENA") == """("NAME", "LENA")"""
    doAssert parse("   # comment ... ") == """("# comment ... ",)"""
  bind MaxSubpatterns
  when not declaredInScope(matches):
    var matches {.inject.}: array[MaxSubpatterns, string] = default(array[MaxSubpatterns, string])
  match(s, pattern, matches)

# ------------------------- more string handling ------------------------------

proc contains*(s: string, pattern: Regex, start = 0): bool {.inline.} =
  ## same as `find(s, pattern, start) >= 0`
  return find(s, pattern, start) >= 0

proc contains*(s: string, pattern: Regex, matches: var openArray[string],
              start = 0): bool {.inline.} =
  ## same as `find(s, pattern, matches, start) >= 0`
  ##
  ## .. note:: The memory for `matches` needs to be allocated before this function is called, otherwise it will just remain empty.
  return find(s, pattern, matches, start) >= 0

proc startsWith*(s: string, prefix: Regex): bool {.inline.} =
  ## returns true if `s` starts with the pattern `prefix`
  result = matchLen(s, prefix) >= 0

proc endsWith*(s: string, suffix: Regex): bool {.inline.} =
  ## returns true if `s` ends with the pattern `suffix`
  for i in 0 .. s.len-1:
    if matchLen(s, suffix, i) == s.len - i: return true

proc replace*(s: string, sub: Regex, by = ""): string =
  ## Replaces `sub` in `s` by the string `by`. Captures cannot be
  ## accessed in `by`.
  runnableExamples:
    doAssert "var1=key; var2=key2".replace(re"(\w+)=(\w+)") == "; "
    doAssert "var1=key; var2=key2".replace(re"(\w+)=(\w+)", "?") == "?; ?"
  result = ""
  var prev = 0
  var flags = int32(0)
  while prev < s.len:
    var match = findBoundsImpl(s.cstring, sub, prev, s.len, flags)
    flags = 0
    if match.first < 0: break
    add(result, substr(s, prev, match.first-1))
    add(result, by)
    if match.first > match.last:
      # 0-len match
      flags = pcre.NOTEMPTY_ATSTART
    prev = match.last + 1
  add(result, substr(s, prev))

proc replacef*(s: string, sub: Regex, by: string): string =
  ## Replaces `sub` in `s` by the string `by`. Captures can be accessed in `by`
  ## with the notation `$i` and `$#` (see strutils.\`%\`).
  runnableExamples:
    doAssert "var1=key; var2=key2".replacef(re"(\w+)=(\w+)", "$1<-$2$2") ==
      "var1<-keykey; var2<-key2key2"
  result = ""
  var caps: array[MaxSubpatterns, string]
  var prev = 0
  while prev < s.len:
    var match = findBounds(s, sub, caps, prev)
    if match.first < 0: break
    add(result, substr(s, prev, match.first-1))
    addf(result, by, caps)
    if match.last + 1 == prev: break
    prev = match.last + 1
  add(result, substr(s, prev))

proc multiReplace*(s: string, subs: openArray[
                   tuple[pattern: Regex, repl: string]]): string =
  ## Returns a modified copy of `s` with the substitutions in `subs`
  ## applied in parallel.
  result = ""
  var i = 0
  var caps: array[MaxSubpatterns, string]
  while i < s.len:
    block searchSubs:
      for j in 0..high(subs):
        var x = matchLen(s, subs[j][0], caps, i)
        if x > 0:
          addf(result, subs[j][1], caps)
          inc(i, x)
          break searchSubs
      add(result, s[i])
      inc(i)
  # copy the rest:
  add(result, substr(s, i))

proc transformFile*(infile, outfile: string,
                    subs: openArray[tuple[pattern: Regex, repl: string]]) =
  ## reads in the file `infile`, performs a parallel replacement (calls
  ## `parallelReplace`) and writes back to `outfile`. Raises `IOError` if an
  ## error occurs. This is supposed to be used for quick scripting.
  var x = readFile(infile)
  writeFile(outfile, x.multiReplace(subs))

iterator split*(s: string, sep: Regex; maxsplit = -1): string =
  ## Splits the string `s` into substrings.
  ##
  ## Substrings are separated by the regular expression `sep`
  ## (and the portion matched by `sep` is not returned).
  runnableExamples:
    import std/sequtils
    doAssert toSeq(split("00232this02939is39an22example111", re"\d+")) ==
      @["", "this", "is", "an", "example", ""]
  var last = 0
  var splits = maxsplit
  var x = -1
  if len(s) == 0:
    last = 1
  if matchLen(s, sep, 0) == 0:
    x = 0
  while last <= len(s):
    var first = last
    var sepLen = 1
    if x == 0:
      inc(last)
    while last < len(s):
      x = matchLen(s, sep, last)
      if x >= 0:
        sepLen = x
        break
      inc(last)
    if splits == 0: last = len(s)
    yield substr(s, first, last-1)
    if splits == 0: break
    dec(splits)
    inc(last, sepLen)

proc split*(s: string, sep: Regex, maxsplit = -1): seq[string] {.inline.} =
  ## Splits the string `s` into a seq of substrings.
  ##
  ## The portion matched by `sep` is not returned.
  result = @[]
  for x in split(s, sep, maxsplit): result.add x

proc escapeRe*(s: string): string =
  ## escapes `s` so that it is matched verbatim when used as a regular
  ## expression.
  result = ""
  for c in items(s):
    case c
    of 'a'..'z', 'A'..'Z', '0'..'9', '_':
      result.add(c)
    else:
      result.add("\\x")
      result.add(toHex(ord(c), 2))

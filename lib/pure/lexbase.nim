#
#
#            Nim's Runtime Library
#        (c) Copyright 2009 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements a base object of a lexer with efficient buffer
## handling. Only at line endings checks are necessary if the buffer
## needs refilling.

import
  std/[strutils, streams]

when defined(nimPreviewSlimSystem):
  import std/assertions

const
  EndOfFile* = '\0' ## end of file marker
  NewLines* = {'\c', '\L'}

# Buffer handling:
#  buf:
#  "Example Text\n ha!"   bufLen = 17
#   ^pos = 0     ^ sentinel = 12
#

type
  BaseLexer* = object of RootObj ## the base lexer. Inherit your lexer from
                                 ## this object.
    bufpos*: int                 ## the current position within the buffer
    buf*: string                 ## the buffer itself
    input: Stream                ## the input stream
    lineNumber*: int             ## the current line number
    sentinel: int
    lineStart: int               # index of last line start in buffer
    offsetBase*: int             # use `offsetBase + bufpos` to get the offset
    refillChars: set[char]

proc close*(L: var BaseLexer) =
  ## closes the base lexer. This closes `L`'s associated stream too.
  close(L.input)

proc fillBuffer(L: var BaseLexer) =
  var
    charsRead, toCopy, s: int # all are in characters,
                              # not bytes (in case this
                              # is not the same)
    oldBufLen: int
  # we know here that pos == L.sentinel, but not if this proc
  # is called the first time by initBaseLexer()
  assert(L.sentinel + 1 <= L.buf.len)
  toCopy = L.buf.len - (L.sentinel + 1)
  assert(toCopy >= 0)
  if toCopy > 0:
    when defined(js) or defined(nimscript):
      # nimscript has to be here to avoid compiling other branch (moveMem)
      for i in 0 ..< toCopy:
        L.buf[i] = L.buf[L.sentinel + 1 + i]
    else:
      when nimvm:
        for i in 0 ..< toCopy:
          L.buf[i] = L.buf[L.sentinel + 1 + i]
      else:
        # "moveMem" handles overlapping regions
        moveMem(addr L.buf[0], addr L.buf[L.sentinel + 1], toCopy)
  charsRead = L.input.readDataStr(L.buf, toCopy ..< toCopy + L.sentinel + 1)
  s = toCopy + charsRead
  if charsRead < L.sentinel + 1:
    L.buf[s] = EndOfFile # set end marker
    L.sentinel = s
  else:
    # compute sentinel:
    dec(s) # BUGFIX (valgrind)
    while true:
      assert(s < L.buf.len)
      while s >= 0 and L.buf[s] notin L.refillChars: dec(s)
      if s >= 0:
        # we found an appropriate character for a sentinel:
        L.sentinel = s
        break
      else:
        # rather than to give up here because the line is too long,
        # double the buffer's size and try again:
        oldBufLen = L.buf.len
        L.buf.setLen(L.buf.len * 2)
        charsRead = readDataStr(L.input, L.buf, oldBufLen ..< L.buf.len)
        if charsRead < oldBufLen:
          L.buf[oldBufLen + charsRead] = EndOfFile
          L.sentinel = oldBufLen + charsRead
          break
        s = L.buf.len - 1

proc fillBaseLexer(L: var BaseLexer, pos: int): int =
  assert(pos <= L.sentinel)
  if pos < L.sentinel:
    result = pos + 1 # nothing to do
  else:
    fillBuffer(L)
    L.offsetBase += pos
    L.bufpos = 0
    result = 0

proc handleCR*(L: var BaseLexer, pos: int): int =
  ## Call this if you scanned over `'\c'` in the buffer; it returns the
  ## position to continue the scanning from. `pos` must be the position
  ## of the `'\c'`.
  assert(L.buf[pos] == '\c')
  inc(L.lineNumber)
  result = fillBaseLexer(L, pos)
  if L.buf[result] == '\L':
    result = fillBaseLexer(L, result)
  L.lineStart = result

proc handleLF*(L: var BaseLexer, pos: int): int =
  ## Call this if you scanned over `'\L'` in the buffer; it returns the
  ## position to continue the scanning from. `pos` must be the position
  ## of the `'\L'`.
  assert(L.buf[pos] == '\L')
  inc(L.lineNumber)
  result = fillBaseLexer(L, pos) #L.lastNL := result-1; // BUGFIX: was: result;
  L.lineStart = result

proc handleRefillChar*(L: var BaseLexer, pos: int): int =
  ## Call this if a terminator character other than a new line is scanned
  ## at `pos`; it returns the position to continue the scanning from.
  assert(L.buf[pos] in L.refillChars)
  result = fillBaseLexer(L, pos) #L.lastNL := result-1; // BUGFIX: was: result;

proc skipUtf8Bom(L: var BaseLexer) =
  if (L.buf[0] == '\xEF') and (L.buf[1] == '\xBB') and (L.buf[2] == '\xBF'):
    inc(L.bufpos, 3)
    inc(L.lineStart, 3)

proc open*(L: var BaseLexer, input: Stream, bufLen: int = 8192;
           refillChars: set[char] = NewLines) =
  ## inits the BaseLexer with a stream to read from.
  assert(bufLen > 0)
  assert(input != nil)
  L.input = input
  L.bufpos = 0
  L.offsetBase = 0
  L.refillChars = refillChars
  L.buf = newString(bufLen)
  L.sentinel = bufLen - 1
  L.lineStart = 0
  L.lineNumber = 1 # lines start at 1
  fillBuffer(L)
  skipUtf8Bom(L)

proc getColNumber*(L: BaseLexer, pos: int): int =
  ## retrieves the current column.
  result = abs(pos - L.lineStart)

proc getCurrentLine*(L: BaseLexer, marker: bool = true): string =
  ## retrieves the current line.
  var i: int
  result = ""
  i = L.lineStart
  while not (L.buf[i] in {'\c', '\L', EndOfFile}):
    add(result, L.buf[i])
    inc(i)
  add(result, "\n")
  if marker:
    add(result, spaces(getColNumber(L, L.bufpos)) & "^\n")

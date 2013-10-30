#
#
#           The Nimrod Compiler
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# Base Object of a lexer with efficient buffer handling. In fact
# I believe that this is the most efficient method of buffer
# handling that exists! Only at line endings checks are necessary
# if the buffer needs refilling.

import
  llstream, strutils

const
  Lrz* = ' '
  Apo* = '\''
  Tabulator* = '\x09'
  ESC* = '\x1B'
  CR* = '\x0D'
  FF* = '\x0C'
  LF* = '\x0A'
  BEL* = '\x07'
  BACKSPACE* = '\x08'
  VT* = '\x0B'

const
  EndOfFile* = '\0'           # end of file marker
                              # A little picture makes everything clear :-)
                              #  buf:
                              #  "Example Text\n ha!"   bufLen = 17
                              #   ^pos = 0     ^ sentinel = 12
                              #
  NewLines* = {CR, LF}

type
  TBaseLexer* = object of TObject
    bufpos*: int
    buf*: cstring
    bufLen*: int              # length of buffer in characters
    stream*: PLLStream        # we read from this stream
    LineNumber*: int          # the current line number
                              # private data:
    sentinel*: int
    lineStart*: int           # index of last line start in buffer


proc openBaseLexer*(L: var TBaseLexer, inputstream: PLLStream,
                    bufLen: int = 8192)
  # 8K is a reasonable buffer size
proc closeBaseLexer*(L: var TBaseLexer)
proc getCurrentLine*(L: TBaseLexer, marker: bool = true): string
proc getColNumber*(L: TBaseLexer, pos: int): int
proc HandleCR*(L: var TBaseLexer, pos: int): int
  # Call this if you scanned over CR in the buffer; it returns the
  # position to continue the scanning from. `pos` must be the position
  # of the CR.
proc HandleLF*(L: var TBaseLexer, pos: int): int
  # Call this if you scanned over LF in the buffer; it returns the the
  # position to continue the scanning from. `pos` must be the position
  # of the LF.
# implementation

const
  chrSize = sizeof(char)

proc closeBaseLexer(L: var TBaseLexer) =
  dealloc(L.buf)
  LLStreamClose(L.stream)

proc FillBuffer(L: var TBaseLexer) =
  var
    charsRead, toCopy, s: int # all are in characters,
                              # not bytes (in case this
                              # is not the same)
    oldBufLen: int
  # we know here that pos == L.sentinel, but not if this proc
  # is called the first time by initBaseLexer()
  assert(L.sentinel < L.bufLen)
  toCopy = L.BufLen - L.sentinel - 1
  assert(toCopy >= 0)
  if toCopy > 0:
    MoveMem(L.buf, addr(L.buf[L.sentinel + 1]), toCopy * chrSize)
    # "moveMem" handles overlapping regions
  charsRead = LLStreamRead(L.stream, addr(L.buf[toCopy]),
                           (L.sentinel + 1) * chrSize) div chrSize
  s = toCopy + charsRead
  if charsRead < L.sentinel + 1:
    L.buf[s] = EndOfFile      # set end marker
    L.sentinel = s
  else:
    # compute sentinel:
    dec(s)                    # BUGFIX (valgrind)
    while true:
      assert(s < L.bufLen)
      while (s >= 0) and not (L.buf[s] in NewLines): Dec(s)
      if s >= 0:
        # we found an appropriate character for a sentinel:
        L.sentinel = s
        break
      else:
        # rather than to give up here because the line is too long,
        # double the buffer's size and try again:
        oldBufLen = L.BufLen
        L.bufLen = L.BufLen * 2
        L.buf = cast[cstring](realloc(L.buf, L.bufLen * chrSize))
        assert(L.bufLen - oldBuflen == oldBufLen)
        charsRead = LLStreamRead(L.stream, addr(L.buf[oldBufLen]),
                                 oldBufLen * chrSize) div chrSize
        if charsRead < oldBufLen:
          L.buf[oldBufLen + charsRead] = EndOfFile
          L.sentinel = oldBufLen + charsRead
          break
        s = L.bufLen - 1

proc fillBaseLexer(L: var TBaseLexer, pos: int): int =
  assert(pos <= L.sentinel)
  if pos < L.sentinel:
    result = pos + 1          # nothing to do
  else:
    fillBuffer(L)
    L.bufpos = 0              # XXX: is this really correct?
    result = 0
  L.lineStart = result

proc HandleCR(L: var TBaseLexer, pos: int): int =
  assert(L.buf[pos] == CR)
  inc(L.linenumber)
  result = fillBaseLexer(L, pos)
  if L.buf[result] == LF:
    result = fillBaseLexer(L, result)

proc HandleLF(L: var TBaseLexer, pos: int): int =
  assert(L.buf[pos] == LF)
  inc(L.linenumber)
  result = fillBaseLexer(L, pos) #L.lastNL := result-1; // BUGFIX: was: result;

proc skip_UTF_8_BOM(L: var TBaseLexer) =
  if (L.buf[0] == '\xEF') and (L.buf[1] == '\xBB') and (L.buf[2] == '\xBF'):
    inc(L.bufpos, 3)
    inc(L.lineStart, 3)

proc openBaseLexer(L: var TBaseLexer, inputstream: PLLStream, bufLen = 8192) =
  assert(bufLen > 0)
  L.bufpos = 0
  L.bufLen = bufLen
  L.buf = cast[cstring](alloc(bufLen * chrSize))
  L.sentinel = bufLen - 1
  L.lineStart = 0
  L.linenumber = 1            # lines start at 1
  L.stream = inputstream
  fillBuffer(L)
  skip_UTF_8_BOM(L)

proc getColNumber(L: TBaseLexer, pos: int): int =
  result = abs(pos - L.lineStart)

proc getCurrentLine(L: TBaseLexer, marker: bool = true): string =
  result = ""
  var i = L.lineStart
  while not (L.buf[i] in {CR, LF, EndOfFile}):
    add(result, L.buf[i])
    inc(i)
  result.add("\n")
  if marker:
    result.add(RepeatChar(getColNumber(L, L.bufpos)) & '^' & "\n")


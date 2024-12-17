#
#
#           The Nim Compiler
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Low-level streams for high performance.

import
  pathutils

when defined(nimPreviewSlimSystem):
  import std/syncio

# support `useGnuReadline`, `useLinenoise` for backwards compatibility
const hasRstdin = (defined(nimUseLinenoise) or defined(useLinenoise) or defined(useGnuReadline)) and
  not defined(windows)

when hasRstdin: import std/rdstdin

type
  TLLRepl* = proc (s: PLLStream, buf: pointer, bufLen: int): int
  OnPrompt* = proc() {.closure.}
  TLLStreamKind* = enum       # enum of different stream implementations
    llsNone,                  # null stream: reading and writing has no effect
    llsString,                # stream encapsulates a string
    llsFile,                  # stream encapsulates a file
    llsStdIn                  # stream encapsulates stdin
  TLLStream* = object of RootObj
    kind*: TLLStreamKind # accessible for low-level access (lexbase uses this)
    f*: File
    s*: string
    rd*, wr*: int             # for string streams
    lineOffset*: int          # for fake stdin line numbers
    repl*: TLLRepl            # gives stdin control to clients
    onPrompt*: OnPrompt

  PLLStream* = ref TLLStream

proc llStreamOpen*(data: sink string): PLLStream =
  PLLStream(kind: llsString, s: data)

proc llStreamOpen*(f: File): PLLStream =
  PLLStream(kind: llsFile, f: f)

proc llStreamOpen*(filename: AbsoluteFile, mode: FileMode): PLLStream =
  result = PLLStream(kind: llsFile)
  if not open(result.f, filename.string, mode): result = nil

proc llStreamOpen*(): PLLStream =
  PLLStream(kind: llsNone)

proc llReadFromStdin(s: PLLStream, buf: pointer, bufLen: int): int
proc llStreamOpenStdIn*(r: TLLRepl = llReadFromStdin, onPrompt: OnPrompt = nil): PLLStream =
  PLLStream(kind: llsStdIn, s: "", lineOffset: -1, repl: r, onPrompt: onPrompt)

proc llStreamClose*(s: PLLStream) =
  case s.kind
  of llsNone, llsString, llsStdIn:
    discard
  of llsFile:
    close(s.f)

when not declared(readLineFromStdin):
  # fallback implementation:
  proc readLineFromStdin(prompt: string, line: var string): bool =
    stdout.write(prompt)
    stdout.flushFile()
    result = readLine(stdin, line)
    if not result:
      stdout.write("\n")
      quit(0)

proc endsWith*(x: string, s: set[char]): bool =
  var i = x.len-1
  while i >= 0 and x[i] == ' ': dec(i)
  if i >= 0 and x[i] in s:
    result = true
  else:
    result = false

const
  LineContinuationOprs = {'+', '-', '*', '/', '\\', '<', '>', '!', '?', '^',
                          '|', '%', '&', '$', '@', '~', ','}
  AdditionalLineContinuationOprs = {'#', ':', '='}

proc endsWithOpr*(x: string): bool =
  result = x.endsWith(LineContinuationOprs)

proc continueLine(line: string, inTripleString: bool): bool {.inline.} =
  result = inTripleString or line.len > 0 and (
        line[0] == ' ' or
        line.endsWith(LineContinuationOprs+AdditionalLineContinuationOprs))

proc countTriples(s: string): int =
  result = 0
  var i = 0
  while i+2 < s.len:
    if s[i] == '"' and s[i+1] == '"' and s[i+2] == '"':
      inc result
      inc i, 2
    inc i

proc llReadFromStdin(s: PLLStream, buf: pointer, bufLen: int): int =
  s.s = ""
  s.rd = 0
  var line = newStringOfCap(120)
  var triples = 0
  while readLineFromStdin(if s.s.len == 0: ">>> " else: "... ", line):
    s.s.add(line)
    s.s.add("\n")
    inc triples, countTriples(line)
    if not continueLine(line, (triples and 1) == 1): break
  inc(s.lineOffset)
  result = min(bufLen, s.s.len - s.rd)
  if result > 0:
    copyMem(buf, addr(s.s[s.rd]), result)
    inc(s.rd, result)

proc llStreamRead*(s: PLLStream, buf: pointer, bufLen: int): int =
  case s.kind
  of llsNone:
    result = 0
  of llsString:
    result = min(bufLen, s.s.len - s.rd)
    if result > 0:
      copyMem(buf, addr(s.s[0 + s.rd]), result)
      inc(s.rd, result)
  of llsFile:
    result = readBuffer(s.f, buf, bufLen)
  of llsStdIn:
    if s.onPrompt!=nil: s.onPrompt()
    result = s.repl(s, buf, bufLen)

proc llStreamReadLine*(s: PLLStream, line: var string): bool =
  setLen(line, 0)
  case s.kind
  of llsNone:
    result = true
  of llsString:
    while s.rd < s.s.len:
      case s.s[s.rd]
      of '\r':
        inc(s.rd)
        if s.s[s.rd] == '\n': inc(s.rd)
        break
      of '\n':
        inc(s.rd)
        break
      else:
        line.add(s.s[s.rd])
        inc(s.rd)
    result = line.len > 0 or s.rd < s.s.len
  of llsFile:
    result = readLine(s.f, line)
  of llsStdIn:
    result = readLine(stdin, line)

proc llStreamWrite*(s: PLLStream, data: string) =
  case s.kind
  of llsNone, llsStdIn:
    discard
  of llsString:
    s.s.add(data)
    inc(s.wr, data.len)
  of llsFile:
    write(s.f, data)

proc llStreamWriteln*(s: PLLStream, data: string) =
  llStreamWrite(s, data)
  llStreamWrite(s, "\n")

proc llStreamWrite*(s: PLLStream, data: char) =
  var c: char
  case s.kind
  of llsNone, llsStdIn:
    discard
  of llsString:
    s.s.add(data)
    inc(s.wr)
  of llsFile:
    c = data
    discard writeBuffer(s.f, addr(c), sizeof(c))

proc llStreamWrite*(s: PLLStream, buf: pointer, buflen: int) =
  case s.kind
  of llsNone, llsStdIn:
    discard
  of llsString:
    if buflen > 0:
      setLen(s.s, s.s.len + buflen)
      copyMem(addr(s.s[0 + s.wr]), buf, buflen)
      inc(s.wr, buflen)
  of llsFile:
    discard writeBuffer(s.f, buf, buflen)

proc llStreamReadAll*(s: PLLStream): string =
  const
    bufSize = 2048
  case s.kind
  of llsNone, llsStdIn:
    result = ""
  of llsString:
    if s.rd == 0: result = s.s
    else: result = substr(s.s, s.rd)
    s.rd = s.s.len
  of llsFile:
    result = newString(bufSize)
    var bytes = readBuffer(s.f, addr(result[0]), bufSize)
    var i = bytes
    while bytes == bufSize:
      setLen(result, i + bufSize)
      bytes = readBuffer(s.f, addr(result[i + 0]), bufSize)
      inc(i, bytes)
    setLen(result, i)

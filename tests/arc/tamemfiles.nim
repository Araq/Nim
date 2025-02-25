discard """
  output: '''
loop 1a
loop 1b; cols: @[1, x]
loop 1c
loop 1d
loop 1a
loop 1b; cols: @[2, y]
loop 1c
loop 1d
'''
  cmd: "nim c --gc:arc $file"
"""

# bug #13596

import tables, memfiles, strutils, os

type Splitr* = tuple[ repeat: bool, chrDlm: char, setDlm: set[char], n: int ]

type csize = uint
proc cmemchr*(s: pointer, c: char, n: csize): pointer {.
  importc: "memchr", header: "<string.h>" .}
proc `-!`*(p, q: pointer): int {.inline.} =
  (cast[int](p) -% cast[int](q)).int
proc `+!`*(p: pointer, i: int): pointer {.inline.} =
  cast[pointer](cast[int](p) +% i)
proc `+!`*(p: pointer, i: uint64): pointer {.inline.} =
  cast[pointer](cast[uint64](p) + i)

proc charEq(x, c: char): bool {.inline.} = x == c

proc initSplitr*(delim: string): Splitr =
  result = default(Splitr)
  if delim == "white":          #User can use any other permutation if needed
    result.repeat = true
    result.chrDlm = ' '
    result.setDlm = { ' ', '\t', '\n' }
    result.n      = result.setDlm.card
    return
  for c in delim:
    if c in result.setDlm:
      result.repeat = true
      continue
    result.setDlm.incl(c)
    inc(result.n)
  if result.n == 1:             #support n==1 test to allow memchr optimization
    result.chrDlm = delim[0]

proc hash(x: MemSlice): int = 55542

template defSplit[T](slc: T, fs: var seq[MemSlice], n: int, repeat: bool,
                     sep: untyped, nextSep: untyped, isSep: untyped) {.dirty.} =
  fs.setLen(if n < 1: 16 else: n)
  var b   = slc.data
  var eob = b +! slc.size
  while repeat and eob -! b > 0 and isSep((cast[cstring](b))[0], sep):
    b = b +! 1
    if b == eob: fs.setLen(0); return
  var e = nextSep(b, sep, (eob -! b).csize)
  while e != nil:
    if n < 1:                               #Unbounded msplit
      if result == fs.len - 1:              #Expand capacity
        fs.setLen(if fs.len < 512: 2*fs.len else: fs.len + 512)
    elif result == n - 1:                   #Need 1 more slot for final field
      break
    fs[result].data = b
    fs[result].size = e -! b
    result += 1
    while repeat and eob -! e > 0 and isSep((cast[cstring](e))[1], sep):
      e = e +! 1
    b = e +! 1
    if eob -! b <= 0:
      b = eob
      break
    e = nextSep(b, sep, (eob -! b).csize)
  if not repeat or eob -! b > 0:
    fs[result].data = b
    fs[result].size = eob -! b
    result += 1
  fs.setLen(result)

proc msplit*(s: MemSlice, fs: var seq[MemSlice], sep=' ', n=0,
             repeat=false): int =
  result = 0
  defSplit(s, fs, n, repeat, sep, cmemchr, charEq)

proc split*(s: Splitr, line: MemSlice, cols: var seq[MemSlice],
            n=0) {.inline.} =
  discard msplit(line, cols, s.chrDlm, n, s.repeat)

########################################################################
# Using lines instead of memSlices & split instead of splitr.split seems
# to mask the arc problem, as does simplifying `Table` to `seq[char]`.

proc load(path: string, delim=" "): Table[MemSlice, seq[char]] =
  result = default(Table[MemSlice, seq[char]])
  let f = memfiles.open(path)
  let splitr = initSplitr(delim)
  var cols: seq[MemSlice] = @[ ]    # re-used seq buffer
  var nwSq = newSeqOfCap[char](1)   # re-used seq value
  nwSq.setLen 1
  for line in memSlices(f, eat='\0'):
    stderr.write "loop 1a\n"
    splitr.split(line, cols, 2)
    stderr.write "loop 1b; cols: ", cols, "\n"
    let cs = cast[cstring](cols[0].data)
    stderr.write "loop 1c\n"        #..reports exception here, but
    nwSq[0] = cs[0]                 #..actually doing out of bounds here
    stderr.write "loop 1d\n"
    result[cols[1]] = nwSq

discard load(getAppDir() / "testfile.txt")

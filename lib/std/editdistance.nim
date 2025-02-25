#
#
#            Nim's Runtime Library
#        (c) Copyright 2018 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements an algorithm to compute the
## `edit distance`:idx: between two Unicode strings.

import std/unicode

proc editDistance*(a, b: string): int {.noSideEffect.} =
  ## Returns the **unicode-rune** edit distance between `a` and `b`.
  ##
  ## This uses the `Levenshtein`:idx: distance algorithm with only a linear
  ## memory overhead.
  runnableExamples: static: doAssert editdistance("Kitten", "Bitten") == 1
  if runeLen(a) > runeLen(b):
    # make `b` the longer string
    return editDistance(b, a)
  # strip common prefix
  var
    iStart = 0 ## The character starting index of the first rune in both strings `a` and `b`
    iNextA = 0
    iNextB = 0
    runeA, runeB: Rune
    lenRunesA = 0 ## The number of relevant runes in string `a`.
    lenRunesB = 0 ## The number of relevant runes in string `b`.
  block commonPrefix:
    # `a` is the shorter string
    while iStart < len(a):
      iNextA = iStart
      a.fastRuneAt(iNextA, runeA, doInc = true)
      iNextB = iStart
      b.fastRuneAt(iNextB, runeB, doInc = true)
      if runeA != runeB:
        inc(lenRunesA)
        inc(lenRunesB)
        break
      iStart = iNextA
  var
    # we know that we are either at the start of the strings
    # or that the current value of runeA is not equal to runeB
    # => start search for common suffix after the current rune (`i_next_*`)
    iEndA = iNextA ## The exclusive upper index bound of string `a`.
    iEndB = iNextB ## The exclusive upper index bound of string `b`.
    iCurrentA = iNextA
    iCurrentB = iNextB
  block commonSuffix:
    var
      addRunesA = 0
      addRunesB = 0
    while iCurrentA < len(a) and iCurrentB < len(b):
      iNextA = iCurrentA
      a.fastRuneAt(iNextA, runeA)
      iNextB = iCurrentB
      b.fastRuneAt(iNextB, runeB)
      inc(addRunesA)
      inc(addRunesB)
      if runeA != runeB:
        iEndA = iNextA
        iEndB = iNextB
        inc(lenRunesA, addRunesA)
        inc(lenRunesB, addRunesB)
        addRunesA = 0
        addRunesB = 0
      iCurrentA = iNextA
      iCurrentB = iNextB
    if iCurrentA >= len(a): # `a` exhausted
      if iCurrentB < len(b): # `b` not exhausted
        iEndA = iCurrentA
        iEndB = iCurrentB
        inc(lenRunesA, addRunesA)
        inc(lenRunesB, addRunesB)
        while true:
          b.fastRuneAt(iEndB, runeB)
          inc(lenRunesB)
          if iEndB >= len(b): break
    elif iCurrentB >= len(b): # `b` exhausted and `a` not exhausted
      iEndA = iCurrentA
      iEndB = iCurrentB
      inc(lenRunesA, addRunesA)
      inc(lenRunesB, addRunesB)
      while true:
        a.fastRuneAt(iEndA, runeA)
        inc(lenRunesA)
        if iEndA >= len(a): break
  block specialCases:
    # trivial cases:
    if lenRunesA == 0: return lenRunesB
    if lenRunesB == 0: return lenRunesA
    # another special case:
    if lenRunesA == 1:
      a.fastRuneAt(iStart, runeA, doInc = false)
      var iCurrentB = iStart
      while iCurrentB < iEndB:
        b.fastRuneAt(iCurrentB, runeB, doInc = true)
        if runeA == runeB: return lenRunesB - 1
      return lenRunesB
  # common case:
  var
    len1 = lenRunesA + 1
    len2 = lenRunesB + 1
    row: seq[int]
  let half = lenRunesA div 2
  newSeq(row, len2)
  var e = iStart + len2 - 1 # end marker
  # initialize first row:
  for i in 1 .. (len2 - half - 1): row[i] = i
  row[0] = len1 - half - 1
  iCurrentA = iStart
  var
    char2pI = -1
    char2pPrev: int = 0
  for i in 1 .. (len1 - 1):
    iNextA = iCurrentA
    a.fastRuneAt(iNextA, runeA)
    var
      char2p: int
      diff, x: int
      p: int
    if i >= (len1 - half):
      # skip the upper triangle:
      let offset = i + half - len1
      if char2pI == i:
        b.fastRuneAt(char2pPrev, runeB)
        char2p = char2pPrev
        char2pI = i + 1
      else:
        char2p = iStart
        for j in 0 ..< offset:
          runeB = b.runeAt(char2p)
          inc(char2p, runeB.size)
        char2pI = i + 1
        char2pPrev = char2p
      p = offset
      runeB = b.runeAt(char2p)
      var c3 = row[p] + (if runeA != runeB: 1 else: 0)
      inc(char2p, runeB.size)
      inc(p)
      x = row[p] + 1
      diff = x
      if x > c3: x = c3
      row[p] = x
      inc(p)
    else:
      p = 1
      char2p = iStart
      diff = i
      x = i
    if i <= (half + 1):
      # skip the lower triangle:
      e = len2 + i - half - 2
    # main:
    while p <= e:
      dec(diff)
      runeB = b.runeAt(char2p)
      var c3 = diff + (if runeA != runeB: 1 else: 0)
      inc(char2p, runeB.size)
      inc(x)
      if x > c3: x = c3
      diff = row[p] + 1
      if x > diff: x = diff
      row[p] = x
      inc(p)
    # lower triangle sentinel:
    if i <= half:
      dec(diff)
      runeB = b.runeAt(char2p)
      var c3 = diff + (if runeA != runeB: 1 else: 0)
      inc(x)
      if x > c3: x = c3
      row[p] = x
    iCurrentA = iNextA
  result = row[e]

proc editDistanceAscii*(a, b: string): int {.noSideEffect.} =
  ## Returns the edit distance between `a` and `b`.
  ##
  ## This uses the `Levenshtein`:idx: distance algorithm with only a linear
  ## memory overhead.
  runnableExamples: static: doAssert editDistanceAscii("Kitten", "Bitten") == 1
  var len1 = a.len
  var len2 = b.len
  if len1 > len2:
    # make `b` the longer string
    return editDistanceAscii(b, a)

  # strip common prefix:
  var s = 0
  while s < len1 and a[s] == b[s]:
    inc(s)
    dec(len1)
    dec(len2)
  # strip common suffix:
  while len1 > 0 and len2 > 0 and a[s+len1-1] == b[s+len2-1]:
    dec(len1)
    dec(len2)
  # trivial cases:
  if len1 == 0: return len2
  if len2 == 0: return len1

  # another special case:
  if len1 == 1:
    for j in s..s+len2-1:
      if a[s] == b[j]: return len2 - 1
    return len2

  inc(len1)
  inc(len2)
  var half = len1 shr 1
  # initialize first row:
  #var row = cast[ptr array[0..high(int) div 8, int]](alloc(len2*sizeof(int)))
  var row: seq[int]
  newSeq(row, len2)
  var e = s + len2 - 1 # end marker
  for i in 1..len2 - half - 1: row[i] = i
  row[0] = len1 - half - 1
  for i in 1 .. len1 - 1:
    var char1 = a[i + s - 1]
    var char2p: int
    var diff, x: int
    var p: int
    if i >= len1 - half:
      # skip the upper triangle:
      var offset = i - len1 + half
      char2p = offset
      p = offset
      var c3 = row[p] + ord(char1 != b[s + char2p])
      inc(p)
      inc(char2p)
      x = row[p] + 1
      diff = x
      if x > c3: x = c3
      row[p] = x
      inc(p)
    else:
      p = 1
      char2p = 0
      diff = i
      x = i
    if i <= half + 1:
      # skip the lower triangle:
      e = len2 + i - half - 2
    # main:
    while p <= e:
      dec(diff)
      var c3 = diff + ord(char1 != b[char2p + s])
      inc(char2p)
      inc(x)
      if x > c3: x = c3
      diff = row[p] + 1
      if x > diff: x = diff
      row[p] = x
      inc(p)
    # lower triangle sentinel:
    if i <= half:
      dec(diff)
      var c3 = diff + ord(char1 != b[char2p + s])
      inc(x)
      if x > c3: x = c3
      row[p] = x
  result = row[e]

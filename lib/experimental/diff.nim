#
#
#            Nim's Runtime Library
#        (c) Copyright 2018 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements an algorithm to compute the
## `diff`:idx: between two sequences of lines.
##
## - To learn more see `Diff on Wikipedia. <https://wikipedia.org/wiki/Diff>`_

runnableExamples:
  assert diffInt(
    [0, 1, 2, 3, 4, 5, 6, 7, 8],
    [-1, 1, 2, 3, 4, 5, 666, 7, 42]) ==
    @[Item(startA: 0, startB: 0, deletedA: 1, insertedB: 1),
      Item(startA: 6, startB: 6, deletedA: 1, insertedB: 1),
      Item(startA: 8, startB: 8, deletedA: 1, insertedB: 1)]

runnableExamples:
  # 2 samples of text (from "The Call of Cthulhu" by Lovecraft)
  let txt0 = """
abc
def ghi
jkl2"""
  let txt1 = """
bacx
abc
def ghi
jkl"""
  assert diffText(txt0, txt1) ==
    @[Item(startA: 0, startB: 0, deletedA: 0, insertedB: 1),
      Item(startA: 2, startB: 3, deletedA: 1, insertedB: 1)]

# code owner: Arne Döring
#
# This is based on C# code written by Matthias Hertel, https://www.mathertel.de
#
# This Class implements the Difference Algorithm published in
# "An O(ND) Difference Algorithm and its Variations" by Eugene Myers
# Algorithmica Vol. 1 No. 2, 1986, p 251.

import std/[tables, strutils]

when defined(nimPreviewSlimSystem):
  import std/assertions

type
  Item* = object    ## An Item in the list of differences.
    startA*: int    ## Start Line number in Data A.
    startB*: int    ## Start Line number in Data B.
    deletedA*: int  ## Number of changes in Data A.
    insertedB*: int ## Number of changes in Data B.

  DiffData = object ## Data on one input file being compared.
    data: seq[int] ## Buffer of numbers that will be compared.
    modified: seq[bool] ## Array of booleans that flag for modified
                        ## data. This is the result of the diff.
                        ## This means deletedA in the first Data or
                        ## inserted in the second Data.

  Smsrd = object
    x, y: int

# template to avoid a seq copy. Required until `sink` parameters are ready.
template newDiffData(initData: seq[int]; L: int): DiffData =
  DiffData(
    data: initData,
    modified: newSeq[bool](L + 2)
  )

proc len(d: DiffData): int {.inline.} = d.data.len

proc diffCodes(aText: string; h: var Table[string, int]): DiffData =
  ## This function converts all textlines of the text into unique numbers for every unique textline
  ## so further work can work only with simple numbers.
  ## `aText` the input text
  ## `h` This extern initialized hashtable is used for storing all ever used textlines.
  ## `trimSpace` ignore leading and trailing space characters
  ## Returns a array of integers.
  var lastUsedCode = h.len
  result = DiffData(data: newSeq[int]())
  for s in aText.splitLines:
    if h.contains s:
      result.data.add h[s]
    else:
      inc lastUsedCode
      h[s] = lastUsedCode
      result.data.add lastUsedCode
  result.modified = newSeq[bool](result.data.len + 2)

proc optimize(data: var DiffData) =
  ## If a sequence of modified lines starts with a line that contains the same content
  ## as the line that appends the changes, the difference sequence is modified so that the
  ## appended line and not the starting line is marked as modified.
  ## This leads to more readable diff sequences when comparing text files.
  var startPos = 0
  while startPos < data.len:
    while startPos < data.len and not data.modified[startPos]:
      inc startPos
    var endPos = startPos
    while endPos < data.len and data.modified[endPos]:
      inc endPos

    if endPos < data.len and data.data[startPos] == data.data[endPos]:
      data.modified[startPos] = false
      data.modified[endPos] = true
    else:
      startPos = endPos

proc sms(dataA: var DiffData; lowerA, upperA: int; dataB: DiffData; lowerB, upperB: int;
         downVector, upVector: var openArray[int]): Smsrd =
  ## This is the algorithm to find the Shortest Middle Snake (sms).
  ## `dataA` sequence A
  ## `lowerA` lower bound of the actual range in dataA
  ## `upperA` upper bound of the actual range in dataA (exclusive)
  ## `dataB` sequence B
  ## `lowerB` lower bound of the actual range in dataB
  ## `upperB` upper bound of the actual range in dataB (exclusive)
  ## `downVector` a vector for the (0,0) to (x,y) search. Passed as a parameter for speed reasons.
  ## `upVector` a vector for the (u,v) to (N,M) search. Passed as a parameter for speed reasons.
  ## Returns a MiddleSnakeData record containing x,y and u,v.
  result = Smsrd()
  let max = dataA.len + dataB.len + 1

  let downK = lowerA - lowerB # the k-line to start the forward search
  let upK = upperA - upperB # the k-line to start the reverse search

  let delta = (upperA - lowerA) - (upperB - lowerB)
  let oddDelta = (delta and 1) != 0

  # The vectors in the publication accepts negative indexes. the vectors implemented here are 0-based
  # and are access using a specific offset: upOffset upVector and downOffset for downVector
  let downOffset = max - downK
  let upOffset = max - upK

  let maxD = ((upperA - lowerA + upperB - lowerB) div 2) + 1

  downVector[downOffset + downK + 1] = lowerA
  upVector[upOffset + upK - 1] = upperA

  for D in 0 .. maxD:
    # Extend the forward path.
    for k in countup(downK - D, downK + D, 2):
      # find the only or better starting point
      var x: int
      if k == downK - D:
        x = downVector[downOffset + k + 1] # down
      else:
        x = downVector[downOffset + k - 1] + 1 # a step to the right
        if k < downK + D and downVector[downOffset + k + 1] >= x:
          x = downVector[downOffset + k + 1] # down

      var y = x - k

      # find the end of the furthest reaching forward D-path in diagonal k.
      while x < upperA and y < upperB and dataA.data[x] == dataB.data[y]:
        inc x
        inc y

      downVector[downOffset + k] = x

      # overlap ?
      if oddDelta and upK - D < k and k < upK + D:
        if upVector[upOffset + k] <= downVector[downOffset + k]:
          return Smsrd(x: downVector[downOffset + k],
                       y: downVector[downOffset + k] - k)

    # Extend the reverse path.
    for k in countup(upK - D, upK + D, 2):
      # find the only or better starting point
      var x: int
      if k == upK + D:
        x = upVector[upOffset + k - 1] # up
      else:
        x = upVector[upOffset + k + 1] - 1 # left
        if k > upK - D and upVector[upOffset + k - 1] < x:
          x = upVector[upOffset + k - 1] # up

      var y = x - k
      while x > lowerA and y > lowerB and dataA.data[x - 1] == dataB.data[y - 1]:
        dec x
        dec y

      upVector[upOffset + k] = x

      # overlap ?
      if not oddDelta and downK-D <= k and k <= downK+D:
        if upVector[upOffset + k] <= downVector[downOffset + k]:
          return Smsrd(x: downVector[downOffset + k],
                       y: downVector[downOffset + k] - k)

  assert false, "the algorithm should never come here."

proc lcs(dataA: var DiffData; lowerA, upperA: int; dataB: var DiffData; lowerB, upperB: int;
         downVector, upVector: var openArray[int]) =
  ## This is the divide-and-conquer implementation of the longes common-subsequence (lcs)
  ## algorithm.
  ## The published algorithm passes recursively parts of the A and B sequences.
  ## To avoid copying these arrays the lower and upper bounds are passed while the sequences stay constant.
  ## `dataA` sequence A
  ## `lowerA` lower bound of the actual range in dataA
  ## `upperA` upper bound of the actual range in dataA (exclusive)
  ## `dataB` sequence B
  ## `lowerB` lower bound of the actual range in dataB
  ## `upperB` upper bound of the actual range in dataB (exclusive)
  ## `downVector` a vector for the (0,0) to (x,y) search. Passed as a parameter for speed reasons.
  ## `upVector` a vector for the (u,v) to (N,M) search. Passed as a parameter for speed reasons.

  # make mutable copy:
  var lowerA = lowerA
  var lowerB = lowerB
  var upperA = upperA
  var upperB = upperB

  # Fast walkthrough equal lines at the start
  while lowerA < upperA and lowerB < upperB and dataA.data[lowerA] == dataB.data[lowerB]:
    inc lowerA
    inc lowerB

  # Fast walkthrough equal lines at the end
  while lowerA < upperA and lowerB < upperB and dataA.data[upperA - 1] == dataB.data[upperB - 1]:
    dec upperA
    dec upperB

  if lowerA == upperA:
    # mark as inserted lines.
    while lowerB < upperB:
      dataB.modified[lowerB] = true
      inc lowerB

  elif lowerB == upperB:
    # mark as deleted lines.
    while lowerA < upperA:
      dataA.modified[lowerA] = true
      inc lowerA

  else:
    # Find the middle snake and length of an optimal path for A and B
    let smsrd = sms(dataA, lowerA, upperA, dataB, lowerB, upperB, downVector, upVector)
    # Debug.Write(2, "MiddleSnakeData", String.Format("{0},{1}", smsrd.x, smsrd.y))

    # The path is from LowerX to (x,y) and (x,y) to UpperX
    lcs(dataA, lowerA, smsrd.x, dataB, lowerB, smsrd.y, downVector, upVector)
    lcs(dataA, smsrd.x, upperA, dataB, smsrd.y, upperB, downVector, upVector)  # 2002.09.20: no need for 2 points

proc createDiffs(dataA, dataB: DiffData): seq[Item] =
  ## Scan the tables of which lines are inserted and deleted,
  ## producing an edit script in forward order.
  result = @[]
  var startA = 0
  var startB = 0
  var lineA = 0
  var lineB = 0
  while lineA < dataA.len or lineB < dataB.len:
    if lineA < dataA.len and not dataA.modified[lineA] and
       lineB < dataB.len and not dataB.modified[lineB]:
      # equal lines
      inc lineA
      inc lineB
    else:
      # maybe deleted and/or inserted lines
      startA = lineA
      startB = lineB

      while lineA < dataA.len and (lineB >= dataB.len or dataA.modified[lineA]):
        inc lineA

      while lineB < dataB.len and (lineA >= dataA.len or dataB.modified[lineB]):
        inc lineB

      if (startA < lineA) or (startB < lineB):
        result.add Item(startA: startA,
                        startB: startB,
                        deletedA: lineA - startA,
                        insertedB: lineB - startB)


proc diffInt*(arrayA, arrayB: openArray[int]): seq[Item] =
  ## Find the difference in 2 arrays of integers.
  ##
  ## `arrayA` A-version of the numbers (usually the old one)
  ##
  ## `arrayB` B-version of the numbers (usually the new one)
  ##
  ## Returns a sequence of Items that describe the differences.

  # The A-Version of the data (original data) to be compared.
  var dataA = newDiffData(@arrayA, arrayA.len)

  # The B-Version of the data (modified data) to be compared.
  var dataB = newDiffData(@arrayB, arrayB.len)

  let max = dataA.len + dataB.len + 1
  # vector for the (0,0) to (x,y) search
  var downVector = newSeq[int](2 * max + 2)
  # vector for the (u,v) to (N,M) search
  var upVector = newSeq[int](2 * max + 2)

  lcs(dataA, 0, dataA.len, dataB, 0, dataB.len, downVector, upVector)
  result = createDiffs(dataA, dataB)

proc diffText*(textA, textB: string): seq[Item] =
  ## Find the difference in 2 text documents, comparing by textlines.
  ##
  ## The algorithm itself is comparing 2 arrays of numbers so when comparing 2 text documents
  ## each line is converted into a (hash) number. This hash-value is computed by storing all
  ## textlines into a common hashtable so i can find duplicates in there, and generating a
  ## new number each time a new textline is inserted.
  ##
  ## `textA` A-version of the text (usually the old one)
  ##
  ## `textB` B-version of the text (usually the new one)
  ##
  ## Returns a seq of Items that describe the differences.
  # See also `gitutils.diffStrings`.
  # prepare the input-text and convert to comparable numbers.
  var h = initTable[string, int]()  # TextA.len + TextB.len  <- probably wrong initial size
  # The A-Version of the data (original data) to be compared.
  var dataA = diffCodes(textA, h)

  # The B-Version of the data (modified data) to be compared.
  var dataB = diffCodes(textB, h)

  h.clear # free up hashtable memory (maybe)

  let max = dataA.len + dataB.len + 1
  # vector for the (0,0) to (x,y) search
  var downVector = newSeq[int](2 * max + 2)
  # vector for the (u,v) to (N,M) search
  var upVector = newSeq[int](2 * max + 2)

  lcs(dataA, 0, dataA.len, dataB, 0, dataB.len, downVector, upVector)

  optimize(dataA)
  optimize(dataB)
  result = createDiffs(dataA, dataB)

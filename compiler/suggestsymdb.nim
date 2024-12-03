import std/[intsets, tables, algorithm, assertions]
import ast, lineinfos, msgs

type
  PackedBoolArray* = object
    s: IntSet
    len: int

  TinyLineInfo* = object
    line*: uint16
    col*: int16

  SymInfoPair* = object
    sym*: PSym
    info*: TLineInfo
    caughtExceptions*: seq[PType]
    caughtExceptionsSet*: bool
    isDecl*: bool

  SuggestFileSymbolDatabase* = object
    lineInfo*: seq[TinyLineInfo]
    sym*: seq[PSym]
    caughtExceptions*: seq[seq[PType]]
    caughtExceptionsSet*: PackedBoolArray
    isDecl*: PackedBoolArray
    fileIndex*: FileIndex
    trackCaughtExceptions*: bool
    isSorted*: bool

  SuggestSymbolDatabase* = Table[FileIndex, SuggestFileSymbolDatabase]


func newPackedBoolArray*(): PackedBoolArray =
  PackedBoolArray(
    s: initIntSet(),
    len: 0
  )

func low*(s: PackedBoolArray): int =
  0

func high*(s: PackedBoolArray): int =
  s.len - 1

func `[]`*(s: PackedBoolArray; idx: int): bool =
  s.s.contains(idx)

proc `[]=`*(s: var PackedBoolArray; idx: int; v: bool) =
  if v:
    s.s.incl(idx)
  else:
    s.s.excl(idx)

proc add*(s: var PackedBoolArray; v: bool) =
  inc(s.len)
  if v:
    s.s.incl(s.len - 1)

proc reverse*(s: var PackedBoolArray) =
  var
    reversedSet = initIntSet()
  for i in 0..s.high:
    if s.s.contains(i):
      reversedSet.incl(s.high - i)
  s.s = reversedSet

proc getSymInfoPair*(s: SuggestFileSymbolDatabase; idx: int): SymInfoPair =
  SymInfoPair(
    sym: s.sym[idx],
    info: TLineInfo(
      line: s.lineInfo[idx].line,
      col: s.lineInfo[idx].col,
      fileIndex: s.fileIndex
    ),
    caughtExceptions:
      if s.trackCaughtExceptions:
        s.caughtExceptions[idx]
      else:
        @[],
    caughtExceptionsSet:
      if s.trackCaughtExceptions:
        s.caughtExceptionsSet[idx]
      else:
        false,
    isDecl: s.isDecl[idx]
  )

proc reverse*(s: var SuggestFileSymbolDatabase) =
  s.lineInfo.reverse()
  s.sym.reverse()
  s.caughtExceptions.reverse()
  s.caughtExceptionsSet.reverse()
  s.isDecl.reverse()

proc newSuggestFileSymbolDatabase*(aFileIndex: FileIndex; aTrackCaughtExceptions: bool): SuggestFileSymbolDatabase =
  SuggestFileSymbolDatabase(
    lineInfo: @[],
    sym: @[],
    caughtExceptions: @[],
    caughtExceptionsSet: newPackedBoolArray(),
    isDecl: newPackedBoolArray(),
    fileIndex: aFileIndex,
    trackCaughtExceptions: aTrackCaughtExceptions,
    isSorted: true
  )

proc exactEquals*(a, b: TinyLineInfo): bool =
  result = a.line == b.line and a.col == b.col

proc `==`*(a, b: SymInfoPair): bool =
  result = a.sym == b.sym and a.info.exactEquals(b.info)

func cmp*(a: TinyLineInfo; b: TinyLineInfo): int =
  result = cmp(a.line, b.line)
  if result == 0:
    result = cmp(a.col, b.col)

func compare*(s: var SuggestFileSymbolDatabase; i, j: int): int =
  result = cmp(s.lineInfo[i], s.lineInfo[j])
  if result == 0:
    result = cmp(s.isDecl[i], s.isDecl[j])

proc exchange(s: var SuggestFileSymbolDatabase; i, j: int) =
  if i == j:
    return
  var tmp1 = s.lineInfo[i]
  s.lineInfo[i] = s.lineInfo[j]
  s.lineInfo[j] = tmp1
  if s.trackCaughtExceptions:
    var tmp2 = s.caughtExceptions[i]
    s.caughtExceptions[i] = s.caughtExceptions[j]
    s.caughtExceptions[j] = tmp2
    var tmp3 = s.caughtExceptionsSet[i]
    s.caughtExceptionsSet[i] = s.caughtExceptionsSet[j]
    s.caughtExceptionsSet[j] = tmp3
  var tmp4 = s.isDecl[i]
  s.isDecl[i] = s.isDecl[j]
  s.isDecl[j] = tmp4
  var tmp5 = s.sym[i]
  s.sym[i] = s.sym[j]
  s.sym[j] = tmp5

proc quickSort(s: var SuggestFileSymbolDatabase; ll, rr: int) =
  var
    i, j, pivotIdx: int
    l = ll
    r = rr
  while true:
    i = l
    j = r
    pivotIdx = l + ((r - l) shr 1)
    while true:
      while (i < pivotIdx) and (s.compare(pivotIdx, i) > 0):
        inc i
      while (j > pivotIdx) and (s.compare(pivotIdx, j) < 0):
        dec j
      if i < j:
        s.exchange(i, j)
        if pivotIdx == i:
          pivotIdx = j
          inc i
        elif pivotIdx == j:
          pivotIdx = i
          dec j
        else:
          inc i
          dec j
      else:
        break
    if (pivotIdx - l) < (r - pivotIdx):
      if (l + 1) < pivotIdx:
        s.quickSort(l, pivotIdx - 1)
      l = pivotIdx + 1
    else:
      if (pivotIdx + 1) < r:
        s.quickSort(pivotIdx + 1, r)
      if (l + 1) < pivotIdx:
        r = pivotIdx - 1
      else:
        break
    if l >= r:
      break

proc sort*(s: var SuggestFileSymbolDatabase) =
  s.quickSort(s.lineInfo.low, s.lineInfo.high)
  s.isSorted = true

proc add*(s: var SuggestFileSymbolDatabase; v: SymInfoPair) =
  doAssert(v.info.fileIndex == s.fileIndex)
  s.lineInfo.add(TinyLineInfo(
    line: v.info.line,
    col: v.info.col
  ))
  s.sym.add(v.sym)
  s.isDecl.add(v.isDecl)
  if s.trackCaughtExceptions:
    s.caughtExceptions.add(v.caughtExceptions)
    s.caughtExceptionsSet.add(v.caughtExceptionsSet)
  s.isSorted = false

proc add*(s: var SuggestSymbolDatabase; v: SymInfoPair; trackCaughtExceptions: bool) =
  s.mgetOrPut(v.info.fileIndex, newSuggestFileSymbolDatabase(v.info.fileIndex, trackCaughtExceptions)).add(v)

proc findSymInfoIndex*(s: var SuggestFileSymbolDatabase; li: TLineInfo): int =
  doAssert(li.fileIndex == s.fileIndex)
  if not s.isSorted:
    s.sort()
  var q = TinyLineInfo(
    line: li.line,
    col: li.col
  )
  result = binarySearch(s.lineInfo, q, cmp)

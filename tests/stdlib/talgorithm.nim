discard """
  targets: "c js"
  matrix: "--mm:refc; --mm:orc"
  output:'''@["3", "2", "1"]
'''
"""
#12928,10456

import std/[sequtils, algorithm, json, sugar]
import std/assertions

proc test() = 
  try: 
    let info = parseJson("""
    {"a": ["1", "2", "3"]}
    """)
    let prefixes = info["a"].getElems().mapIt(it.getStr()).sortedByIt(it).reversed()
    echo prefixes
  except:
    discard

test()

block:
  # Tests for lowerBound
  var arr = @[1, 2, 3, 5, 6, 7, 8, 9]
  doAssert arr.lowerBound(0) == 0
  doAssert arr.lowerBound(4) == 3
  doAssert arr.lowerBound(5) == 3
  doAssert arr.lowerBound(10) == 8
  arr = @[1, 5, 10]
  doAssert arr.lowerBound(4) == 1
  doAssert arr.lowerBound(5) == 1
  doAssert arr.lowerBound(6) == 2
  # Tests for isSorted
  var srt1 = [1, 2, 3, 4, 4, 4, 4, 5]
  var srt2 = ["iello", "hello"]
  var srt3 = [1.0, 1.0, 1.0]
  var srt4: seq[int]
  doAssert srt1.isSorted(cmp) == true
  doAssert srt2.isSorted(cmp) == false
  doAssert srt3.isSorted(cmp) == true
  doAssert srt4.isSorted(cmp) == true
  var srtseq = newSeq[int]()
  doAssert srtseq.isSorted(cmp) == true
  # Tests for reversed
  var arr1 = @[0, 1, 2, 3, 4]
  doAssert arr1.reversed() == @[4, 3, 2, 1, 0]
  for i in 0 .. high(arr1):
    doAssert arr1.reversed(0, i) == arr1.reversed()[high(arr1) - i .. high(arr1)]
    doAssert arr1.reversed(i, high(arr1)) == arr1.reversed()[0 .. high(arr1) - i]

block:
  var list = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  let list2 = list.rotatedLeft(1 ..< 9, 3)
  let expected = [0, 4, 5, 6, 7, 8, 1, 2, 3, 9, 10]

  doAssert list.rotateLeft(1 ..< 9, 3) == 6
  doAssert list == expected
  doAssert list2 == @expected

  var s0, s1, s2, s3, s4, s5 = "xxxabcdefgxxx"

  doAssert s0.rotateLeft(3 ..< 10, 3) == 7
  doAssert s0 == "xxxdefgabcxxx"
  doAssert s1.rotateLeft(3 ..< 10, 2) == 8
  doAssert s1 == "xxxcdefgabxxx"
  doAssert s2.rotateLeft(3 ..< 10, 4) == 6
  doAssert s2 == "xxxefgabcdxxx"
  doAssert s3.rotateLeft(3 ..< 10, -3) == 6
  doAssert s3 == "xxxefgabcdxxx"
  doAssert s4.rotateLeft(3 ..< 10, -10) == 6
  doAssert s4 == "xxxefgabcdxxx"
  doAssert s5.rotateLeft(3 ..< 10, 11) == 6
  doAssert s5 == "xxxefgabcdxxx"

  block product:
    doAssert product(newSeq[seq[int]]()) == newSeq[seq[int]](), "empty input"
    doAssert product(@[newSeq[int](), @[], @[]]) == newSeq[seq[int]](), "bit more empty input"
    doAssert product(@[@[1, 2]]) == @[@[1, 2]], "a simple case of one element"
    doAssert product(@[@[1, 2], @[3, 4]]) == @[@[2, 4], @[1, 4], @[2, 3], @[1,
        3]], "two elements"
    doAssert product(@[@[1, 2], @[3, 4], @[5, 6]]) == @[@[2, 4, 6], @[1, 4, 6],
        @[2, 3, 6], @[1, 3, 6], @[2, 4, 5], @[1, 4, 5], @[2, 3, 5], @[1, 3, 5]], "three elements"
    doAssert product(@[@[1, 2], @[]]) == newSeq[seq[int]](), "two elements, but one empty"

  block lowerBound:
    doAssert lowerBound([1, 2, 4], 3, system.cmp[int]) == 2
    doAssert lowerBound([1, 2, 2, 3], 4, system.cmp[int]) == 4
    doAssert lowerBound([1, 2, 3, 10], 11) == 4

  block upperBound:
    doAssert upperBound([1, 2, 4], 3, system.cmp[int]) == 2
    doAssert upperBound([1, 2, 2, 3], 3, system.cmp[int]) == 4
    doAssert upperBound([1, 2, 3, 5], 3) == 3

  block fillEmptySeq:
    var s = newSeq[int]()
    s.fill(0)

  block testBinarySearch:
    var noData: seq[int]
    doAssert binarySearch(noData, 7) == -1
    let oneData = @[1]
    doAssert binarySearch(oneData, 1) == 0
    doAssert binarySearch(oneData, 7) == -1
    let someData = @[1, 3, 4, 7]
    doAssert binarySearch(someData, 1) == 0
    doAssert binarySearch(someData, 7) == 3
    doAssert binarySearch(someData, -1) == -1
    doAssert binarySearch(someData, 5) == -1
    doAssert binarySearch(someData, 13) == -1
    let moreData = @[1, 3, 5, 7, 4711]
    doAssert binarySearch(moreData, -1) == -1
    doAssert binarySearch(moreData, 1) == 0
    doAssert binarySearch(moreData, 5) == 2
    doAssert binarySearch(moreData, 6) == -1
    doAssert binarySearch(moreData, 4711) == 4
    doAssert binarySearch(moreData, 4712) == -1

# merge
proc main() =
  block:
    var x = @[1, 7, 8, 11, 21, 33, 45, 99]
    var y = @[6, 7, 9, 12, 57, 66]

    var merged: seq[int] = @[]
    merged.merge(x, y)
    doAssert merged.isSorted
    doAssert merged == sorted(x & y)

  block:
    var x = @[111, 88, 76, 56, 45, 31, 22, 19, 11, 3]
    var y = @[99, 85, 83, 82, 69, 64, 48, 42, 33, 31, 26, 13]

    var merged: seq[int] = @[]
    merged.merge(x, y, (x, y) => -system.cmp(x, y))
    doAssert merged.isSorted((x, y) => -system.cmp(x, y))
    doAssert merged == sorted(x & y, SortOrder.Descending)

  block:
    var x: seq[int] = @[]
    var y = @[1]

    var merged: seq[int] = @[]
    merged.merge(x, y)
    doAssert merged.isSorted
    doAssert merged.isSorted(SortOrder.Descending)
    doAssert merged == @[1]

  block:
    var x = [1, 3, 5, 5, 7]
    var y: seq[int] = @[]

    var merged: seq[int] = @[]
    merged.merge(x, y)
    doAssert merged.isSorted
    doAssert merged == @x

  block:
    var x = [1, 3, 5, 5, 7]
    var y: seq[int] = @[]

    var merged: seq[int] = @[1, 2, 3, 5, 6, 56, 99, 2, 34]
    merged.merge(x, y)
    doAssert merged == @[1, 2, 3, 5, 6, 56, 99, 2, 34, 1, 3, 5, 5, 7]


  block:
    var x = default(array[0, int])
    var y = [1, 4, 6, 7, 9]

    var merged: seq[int] = @[]
    merged.merge(x, y)
    doAssert merged.isSorted
    doAssert merged == @y

  block:
    var x: array[0, int] = []
    var y: array[0, int] = []

    var merged: seq[int] = @[]
    merged.merge(x, y)
    doAssert merged.isSorted
    doAssert merged.len == 0

  block:
    var x: array[0, int] = []
    var y: array[0, int] = []

    var merged: seq[int] = @[99, 99, 99]
    merged.setLen(0)
    merged.merge(x, y)
    doAssert merged.isSorted
    doAssert merged.len == 0

  block:
    var x: seq[int] = @[]
    var y: seq[int] = @[]

    var merged: seq[int] = @[]
    merged.merge(x, y)
    doAssert merged.isSorted
    doAssert merged.len == 0

  block:
    type
      Record = object
        id: int
    
    proc r(id: int): Record =
      Record(id: id)

    proc cmp(x, y: Record): int =
      if x.id == y.id: return 0
      if x.id < y.id: return -1
      result = 1

    var x = @[r(-12), r(1), r(3), r(8), r(13), r(88)]
    var y = @[r(4), r(7), r(12), r(13), r(77), r(99)]

    var merged: seq[Record] = @[]
    merged.merge(x, y, cmp)
    doAssert merged.isSorted(cmp)
    doAssert merged.len == 12

  block:
    type
      Record = object
        id: int
    
    proc r(id: int): Record =
      Record(id: id)

    proc ascendingCmp(x, y: Record): int =
      if x.id == y.id: return 0
      if x.id < y.id: return -1
      result = 1

    proc descendingCmp(x, y: Record): int =
      if x.id == y.id: return 0
      if x.id < y.id: return 1
      result = -1

    var x = @[r(-12), r(1), r(3), r(8), r(13), r(88)]
    var y = @[r(4), r(7), r(12), r(13), r(77), r(99)]

    var merged: seq[Record] = @[]
    merged.setLen(0)
    merged.merge(x, y, ascendingCmp)
    doAssert merged.isSorted(ascendingCmp)
    doAssert merged == sorted(x & y, ascendingCmp)

    reverse(x)
    reverse(y)

    merged.setLen(0)
    merged.merge(x, y, descendingCmp)
    doAssert merged.isSorted(descendingCmp)
    doAssert merged == sorted(x & y, ascendingCmp, SortOrder.Descending)

    reverse(x)
    reverse(y)
    merged.setLen(0)
    merged.merge(x, y, proc (x, y: Record): int = -descendingCmp(x, y))
    doAssert merged.isSorted(proc (x, y: Record): int = -descendingCmp(x, y))
    doAssert merged == sorted(x & y, ascendingCmp)


  var x: seq[(int, int)] = @[]
  x.merge([(1,1)], [(1,2)], (a,b) => a[0] - b[0])
  doAssert x == @[(1, 1), (1, 2)]

static: main()
main()

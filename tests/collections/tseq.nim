discard """
  matrix: "--mm:refc; --mm:orc"
  output: '''
Hithere, what's your name?Hathere, what's your name?
fA13msg1falsefB14msg2truefC15msg3false
Zip: [{"Field0": 1, "Field1": 2}, {"Field0": 3, "Field1": 4}, {"Field0": 5, "Field1": 6}]
Filter Iterator: 3
Filter Iterator: 5
Filter Iterator: 7
Filter: [3, 5, 7]
FilterIt: [1, 3, 7]
Concat: [1, 3, 5, 7, 2, 4, 6]
Deduplicate: [1, 2, 3, 4, 5, 7]
@[()]
Minmax: (1, 7)
2345623456
'''
"""

block tseq2:
  proc `*`(a, b: seq[int]): seq[int] =
    # allocate a new sequence:
    newSeq(result, len(a))
    # multiply two int sequences:
    for i in 0..len(a)-1: result[i] = a[i] * b[i]

  doAssert(@[1, 2, 3] * @[1, 2, 3] == @[1, 4, 9])



block tseqcon:
  const nestedFixed = true

  type
    TRec {.final.} = object
      x, y: int
      s: string
      seq: seq[string]
    TRecSeq = seq[TRec]

  proc test() =
    var s, b: seq[string]
    s = @[]
    add(s, "Hi")
    add(s, "there, ")
    add(s, "what's your name?")

    b = s # deep copying here!
    b[0][1] = 'a'

    for i in 0 .. len(s)-1:
      write(stdout, s[i])
    for i in 0 .. len(b)-1:
      write(stdout, b[i])

  when nestedFixed:
    proc nested() =
      var
        s: seq[seq[string]]
      for i in 0..10_000: # test if the garbage collector
        # now works with sequences
        s = @[
          @["A", "B", "C", "D"],
          @["E", "F", "G", "H"],
          @["I", "J", "K", "L"],
          @["M", "N", "O", "P"]]

  test()
  when nestedFixed:
    nested()
  echo ""



import os
block tseqcon2:
  proc rec_dir(dir: string): seq[string] =
    result = @[]
    for kind, path in walk_dir(dir):
      if kind == pcDir:
        add(result, rec_dir(path))
      else:
        add(result, path)



block tseqtuple:
  type
    TMsg = tuple[
      file: string,
      line: int,
      msg: string,
      err: bool]

  var s: seq[TMsg] = @[]

  s.add(("fA", 13, "msg1", false))
  s.add(("fB", 14, "msg2", true))
  s.add(("fC", 15, "msg3", false))

  for file, line, msg, err in items(s):
    stdout.write(file)
    stdout.write($line)
    stdout.write(msg)
    stdout.write($err)
  echo ""


import sequtils, marshal
block tsequtils:
  proc testFindWhere(item : int) : bool =
    if item != 1: return true

  var seq1: seq[int] = @[]

  seq1.add(1)
  seq1.add(3)
  seq1.add(5)
  seq1.add(7)

  var seq2: seq[int] = @[2, 4, 6]
  var final = zip(seq1, seq2)

  echo "Zip: ", $$(final)

  #Test findWhere as a iterator

  for itms in filter(seq1, testFindWhere):
    echo "Filter Iterator: ", $$(itms)


  #Test findWhere as a proc

  var fullseq: seq[int] = filter(seq1, testFindWhere)

  echo "Filter: ", $$(fullseq)

  #Test findIt as a template

  var finditval: seq[int] = filterIt(seq1, it!=5)

  echo "FilterIt: ", $$(finditval)

  var concatseq = concat(seq1,seq2)
  echo "Concat: ", $$(concatseq)

  var seq3 = @[1,2,3,4,5,5,5,7]
  var dedupseq = deduplicate(seq3)
  echo "Deduplicate: ", $$(dedupseq)
  # bug #4973
  type
    SomeObj = object
    OtherObj = object
      field: SomeObj

  let aSeq = @[OtherObj(field: SomeObj())]
  let someObjSeq = aSeq.mapIt(it.field)
  echo someObjSeq

  block minmax:
    doAssert minmax(@[0]) == (0, 0)
    doAssert minmax(@[0, 1]) == (0, 1)
    doAssert minmax(@[1, 0]) == (0, 1)
    doAssert minmax(@[8,2,1,7,3,9,4,0,5]) == (0, 9)
    echo "Minmax: ", $(minmax(concat(seq1, seq2)))


when not defined(nimseqsv2):
  block tshallowseq:
    proc xxx() =
      var x: seq[int] = @[1, 2, 3]
      var y: seq[int]
      system.shallowCopy(y, x)
      y[1] = 42
      doAssert y == @[1, 42, 3]
      doAssert x == @[1, 42, 3]
    xxx()


  block tshallowemptyseq:
    proc test() =
      var nilSeq: seq[int] = @[]
      var emptySeq: seq[int] = newSeq[int]()
      block:
        var t = @[1,2,3]
        when defined(gcRefc):
          shallow(nilSeq)
        t = nilSeq
        doAssert t == @[]
      block:
        var t = @[1,2,3]
        when defined(gcRefc):
          shallow(emptySeq)
        t = emptySeq
        doAssert t == @[]
      block:
        var t = @[1,2,3]
        shallowCopy(t, nilSeq)
        doAssert t == @[]
      block:
        var t = @[1,2,3]
        shallowCopy(t, emptySeq)
        doAssert t == @[]
    test()


import strutils
block ttoseq:
  for x in toSeq(countup(2, 6)):
    stdout.write(x)
  for x in items(toSeq(countup(2, 6))):
    stdout.write(x)
  var y: typeof("a b c".split)
  y = "xzy"
  stdout.write("\n")

block tseqmapitchain:
  doAssert @[101, 102] == [1, 2].mapIt(func (x: int): int = it + x).mapIt(it(100))


for i in 0..100:
  # fix #14655
  var test = newSeqOfCap[uint32](1)
  test.setLen(1)
  doAssert test[0] == 0, $(test[0], i)


# bug #22560
doAssert len(newSeqOfCap[int](42)) == 0

block: # bug #17197
  type Matrix = seq[seq[int]]

  proc needlemanWunsch(sequence1: string, sequence2: string, gap_penal: int8, match: int8, indel_penal: int8): bool =
    let seq2_len = sequence2.len

    var grid: Matrix
    for i in sequence1:
      grid.add(newSeqOfCap[seq[int]](seq2_len))
    result = true

  doAssert needlemanWunsch("ABC", "DEFG", 1, 2, 3)

block: # bug #12340
  func consume(x: sink seq[int]) =
    x[0] += 5

  let x = @[1, 2, 3, 4]
  consume x
  doAssert x == @[1, 2, 3, 4]

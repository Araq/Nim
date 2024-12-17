
discard """
output:  '''test created
test destroyed 0
1
2
3
4
Pony is dying!'''
joinable: false
targets: "c"
"""

# bug #4214
type
  Data = object
    data: string
    rc: int

proc `=destroy`(d: var Data) =
  dec d.rc
  echo d.data, " destroyed ", d.rc

proc `=`(dst: var Data, src: Data) =
  echo src.data, " copied"
  dst.data = src.data & " (copy)"
  dec dst.rc
  inc dst.rc

proc initData(s: string): Data =
  result = Data(data: s, rc: 1)
  echo s, " created"

proc pointlessWrapper(s: string): Data =
  result = initData(s)

proc main =
  var x = pointlessWrapper"test"

when true:
  main()

# bug #985

type
  Pony = object
    name: string

proc `=destroy`(o: var Pony) =
  echo "Pony is dying!"

proc getPony: Pony =
  result = Pony(name: "Sparkles")

iterator items(p: Pony): int =
  for i in 1..4:
    yield i

for x in getPony():
  echo x





#------------------------------------------------------------
#-- Move into tuple constructor and move on tuple unpacking
#------------------------------------------------------------

type
  MySeqNonCopyable* = object
    len: int
    data: ptr UncheckedArray[float]

proc `=destroy`*(m: var MySeqNonCopyable) {.inline.} =
  if m.data != nil:
    deallocShared(m.data)
    m.data = nil

proc `=`*(m: var MySeqNonCopyable, m2: MySeqNonCopyable) {.error.}

proc `=sink`*(m: var MySeqNonCopyable, m2: MySeqNonCopyable) {.inline.} =
  if m.data != m2.data:
    if m.data != nil:
      `=destroy`(m)
    m.len = m2.len
    m.data = m2.data

proc len*(m: MySeqNonCopyable): int {.inline.} = m.len

proc `[]`*(m: MySeqNonCopyable; i: int): float {.inline.} =
  m.data[i.int]

proc `[]=`*(m: var MySeqNonCopyable; i, val: float) {.inline.} =
  m.data[i.int] = val

proc setTo(s: var MySeqNonCopyable, val: float) =
  for i in 0..<s.len.int:
    s.data[i] = val

proc newMySeq*(size: int, initial_value = 0.0): MySeqNonCopyable =#
  result.len = size
  if size > 0:
    result.data = cast[ptr UncheckedArray[float]](createShared(float, size))

  result.setTo(initial_value)

proc myfunc(x, y: int): (MySeqNonCopyable, MySeqNonCopyable) =
  result = (newMySeq(x, 1.0), newMySeq(y, 5.0))

proc myfunc2(x, y: int): tuple[a: MySeqNonCopyable, b:int, c:MySeqNonCopyable] =
  var cc = newMySeq(y, 5.0)
  (a: case x:
    of 1:
      let (z1, z2) = myfunc(x, y)
      z2
    elif x > 5: raise newException(ValueError, "new error")
    else: newMySeq(x, 1.0),
   b: 0,
   c: block:
        var tmp = if y > 0: move(cc) else: newMySeq(1, 3.0)
        tmp[0] = 5
        tmp
  )


let (seq1, seq2) = myfunc(2, 3)
doAssert seq1.len == 2
doAssert seq1[0] == 1.0
doAssert seq2.len == 3
doAssert seq2[0] == 5.0

var (seq3, i, _) = myfunc2(2, 3)
doAssert seq3.len == 2
doAssert seq3[0] == 1.0

var seq4, seq5: MySeqNonCopyable
(seq4, i, seq5) = myfunc2(2, 3)

proc foo =
  seq4 = block:
    var tmp = newMySeq(4, 1.0)
    tmp[0] = 3.0
    tmp

  doAssert seq4[0] == 3.0


  seq4 =
    if i > 0: newMySeq(2, 5.0)
    elif i < -100: raise newException(ValueError, "Parse Error")
    else: newMySeq(2, 3.0)

  seq4 =
    case (char) i:
      of 'A', {'W'..'Z'}: newMySeq(2, 5.0)
      of 'B': quit(-1)
      else:
        let (x1, x2, x3) = myfunc2(2, 3)
        x3

foo()

#------------------------------------------------------------
#-- Move into array constructor
#------------------------------------------------------------

var ii = 1
let arr2 = [newMySeq(2, 5.0), if i > 1: newMySeq(3, 1.0) else: newMySeq(0, 0.0)]
var seqOfSeq2 = @[newMySeq(2, 5.0), newMySeq(3, 1.0)]


## issue #10462
proc myfuncLoop(x: int): MySeqNonCopyable =
  for i in 0..<x:
    var cc = newMySeq(i, 5.0)
    result = cc

discard myfuncLoop(3)

#------------------------------------------------------------
# Move into table via openArray
#------------------------------------------------------------

type
  TableNonCopyable = object
    x: seq[(string, MySeqNonCopyable)]

proc toTable(pairs: sink openArray[(string, MySeqNonCopyable)]): TableNonCopyable =
  discard


let mytable = {"a": newMySeq(2, 5.0)}.toTable


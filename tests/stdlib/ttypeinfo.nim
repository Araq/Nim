discard """
  matrix: "--mm:refc; --mm:orc"
"""

import std/typeinfo
import std/assertions

type
  TE = enum
    blah, blah2

  TestObj = object
    test, asd: int
    case test2: TE
    of blah:
      help: string
    else:
      nil


var test = @[0,1,2,3,4]
var x = toAny(test)
var y = 78
x[4] = toAny(y)
doAssert x[2].getInt == 2

var test2: tuple[name: string, s: int] = ("test", 56)
var x2 = toAny(test2)
var i = 0
for n, a in fields(x2):
  case i
  of 0: doAssert n == "Field0" and $a.kind == "akString"
  of 1: doAssert n == "Field1" and $a.kind == "akInt"
  else: doAssert false
  inc i

var test3: TestObj
test3.test = 42
test3 = TestObj(test2: blah2)
var x3 = toAny(test3)
i = 0
for n, a in fields(x3):
  case i
  of 0: doAssert n == "test" and $a.kind == "akInt"
  of 1: doAssert n == "asd" and $a.kind == "akInt"
  of 2: doAssert n == "test2" and $a.kind == "akEnum"
  else: doAssert false
  inc i

var test4: ref string
new(test4)
test4[] = "test"
var x4 = toAny(test4)
doAssert($x4[].kind() == "akString")

block:
  # gimme a new scope dammit
  var myArr: array[0..4, array[0..4, string]] = [
    ["test", "1", "2", "3", "4"], ["test", "1", "2", "3", "4"],
    ["test", "1", "2", "3", "4"], ["test", "1", "2", "3", "4"],
    ["test", "1", "2", "3", "4"]]
  var m = toAny(myArr)
  for i in 0 .. m.len-1:
    for j in 0 .. m[i].len-1:
      doAssert getString(m[i][j]) == myArr[i][j]

block:
  type
    Test = enum
      Hello, he_llo

  var x = hello
  var y = x.toAny

  doAssert getEnumOrdinal(y, "Hello") == 0
  doAssert getEnumOrdinal(y, "hello") == 1

block: # bug #23556
  proc test =
    var
      t: seq[int] = @[]
      aseq = toAny(t)

    invokeNewSeq(aseq, 0)

    # Got random value only when loop 8 times.
    for i in 1 .. 8:
      extendSeq(aseq)

    doAssert t == @[0, 0, 0, 0, 0, 0, 0, 0]

  for i in 1 .. 7:
    test()

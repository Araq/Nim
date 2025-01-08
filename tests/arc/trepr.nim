discard """
  cmd: "nim c --gc:arc $file"
  nimout: '''(a: true, n: doAssert)
Table[system.string, trepr.MyType](data: @[], counter: 0)
nil
'''
  output: '''
nil
2
Obj(member: ref @["hello"])
ref (member: ref @["hello"])
ObjUa(v: 0, a: [...])
'''
"""

# xxx consider merging with `tests/stdlib/trepr.nim` to increase overall test coverage

import tables

type
  NimSym = distinct NimNode
  MyType = tuple
    a: bool
    n: NimSym

proc myproc(t: MyType) =
  echo repr(t)

proc myproc2(t: MyType) =
  var x = Table[string, t]()
  echo repr(x)

proc myproc3(t: MyType) =
  var x: TableRef[string, t] = nil
  echo repr(x)


macro dumpSym(a: typed) =
  myproc((a: true, n: NimSym(a)))
  myproc2((a: true, n: NimSym(a)))
  myproc3((a: true, n: NimSym(a)))

dumpSym(doAssert)

# bug 13731

import os
var a: File
echo repr a

# bug 13872

echo repr(2'u16)

# bug 14270

type
  Obj = ref object
    member: ref seq[string]

var c = Obj(member: new seq[string])
c.member[] = @["hello"]
echo c.repr

var c2 = new tuple[member: ref seq[string]]
c2.member = new seq[string]
c2.member[] = @["hello"]
echo c2.repr

proc p2 =
  echo "hey"

discard repr p2


#####################################################################
# bug #15043

import macros

macro extract(): untyped =
  result = newStmtList()
  var x: seq[tuple[node: NimNode]]

  proc test(n: NimNode) {.closure.} =
    x.add (node: n)
  
  test(parseExpr("discard"))
  
extract()

type
  ObjUa = ref object
    v: int
    a: UncheckedArray[char]

echo ObjUa().repr

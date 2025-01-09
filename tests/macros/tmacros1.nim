discard """
  output: '''Got: 'nnkCall' hi
{a}
{b}
{a, b}'''
"""

import macros

macro outterMacro*(n, blck: untyped): untyped =
  let n = callsite()
  var j : string = "hi"
  proc innerProc(i: int): string =
    echo "Using arg ! " & n.repr
    result = "Got: '" & $n.kind & "' " & $j
  var callNode = n[0]
  expectKind(n, NimNodeKind.nnkCall)
  if n.len != 3 or n[1].kind != NimNodeKind.nnkIdent:
    error("Macro " & callNode.repr &
      " requires the ident passed as parameter (eg: " & callNode.repr &
      "(the_name_you_want)): statements.")
  result = newNimNode(NimNodeKind.nnkStmtList)
  var ass : NimNode = newNimNode(nnkAsgn)
  ass.add(n[1])
  ass.add(newStrLitNode(innerProc(4)))
  result.add(ass)

var str: string
outterMacro(str):
  "hellow"
echo str

type E = enum a b
macro enumerators1(): set[E] = newLit({a})

macro enumerators2(): set[E] =
  return newLit({b})

macro enumerators3(): set[E] =
  result = newLit({E.low .. E.high})

var myEnums: set[E]


myEnums = enumerators1()
echo myEnums
myEnums = enumerators2()
echo myEnums
myEnums = enumerators3()
echo myEnums

#10751

type Tuple = tuple
  a: string
  b: int

macro foo(t: static Tuple): untyped =
  doAssert t.a == "foo"
  doAssert t.b == 12345

foo((a: "foo", b: 12345))


# bug #16307

macro bug(x: untyped): string =
  newLit repr(x)

let res = bug:
  block:
    ## one
    ## two
    ## three

doAssert res == """

block:
  ## one
  ## two
  ## three"""

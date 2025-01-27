discard """
output: '''
hi
hi
topLevel|topLevel|
topLevel2|topLevel2|
inProc|inProc|
inProc2|inProc2|
topLevel|9
topLevel2|10
inProc|7
inProc2|8
must have been the wind..
I'm there
must have been the wind..
I'm there
symbol'a'symbol'a'
symbol'b'symbol'b'
symbol'a'symbol'b'
symbol'a'9
symbol'b'9
symbol'a'0
'''
"""
import mdefaultprocparam

p()

proc testP =
  p()

testP()

proc p2(s: string, count = s): string = s & count

proc testP2 =
  echo p2 """inProc|"""
  echo p2 """inProc2|"""

echo p2 """topLevel|"""
echo p2 """topLevel2|"""

testP2()

import macros
macro dTT(a: typed) = echo a.treeRepr

proc p3(s: string, count = len(s)): string = s & $count

proc testP3 =
  echo p3 """inProc|"""
  echo p3 """inProc2|"""

echo p3 """topLevel|"""
echo p3 """topLevel2|"""

testP3()

proc cut(s: string, c = len(s)): string =
  s[0..<s.len-c]

echo "must have been the wind.." & cut "I'm gone"
echo cut("I'm gone", 4) & "there"

proc testCut =
  echo "must have been the wind.." & cut "I'm gone"
  echo cut("I'm gone", 4) & "there"

testCut()

var a = "symbol'a'"
var b = "symbol'b'"

block:
  echo p2(a)
block:
  echo p2(b)
block:
  echo p2(a, b)
block:
  echo p3(a)
  echo p3(b)
  echo p3(a, 0)

# bug #12252
proc foo(a = 0, b = a.high, c = high(typeof(a))) = 
  discard

foo()

import std/strformat

block: # issue #18074
  proc somefn[T](query: string, _: type[T], message = query) = discard
  somefn(fmt"", string)


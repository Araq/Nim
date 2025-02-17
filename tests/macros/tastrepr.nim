discard """
output: '''

var data = @[(1, "one"), (2, "two")]
for (i, d) in pairs(data):
  discard
for i, d in pairs(data):
  discard
for i, (x, y) in pairs(data):
  discard
var
  a = 1
  b = 2
type
  A* = object
var
  c* = 1
  d* {.used.} = 1
  e* = 2
let f* = 1
const
  g* = 1
proc h*() =
  discard

template i*() =
  discard


var data = @[(1, "one"), (2, "two")]
for (i, d) in pairs(data):
  discard
for i, d in pairs(data):
  discard
for i, (x, y) in pairs(data):
  discard
var (a, b) = (1, 2)
type
  A* = object
var
  c* = 1
  (d* {.used.}, e*) = (1, 2)
let f* = 1
const
  g* = 1
proc h*() =
  discard

template i*() =
  discard


var t04 = 1.0'f128
t04 = 2.0'f128
'''
"""

import macros

macro echoTypedRepr(arg: typed) =
  result = newCall(ident"echo", newLit(arg.repr))

macro echoUntypedRepr(arg: untyped) =
  result = newCall(ident"echo", newLit(arg.repr))

template echoTypedAndUntypedRepr(arg: untyped) =
  echoTypedRepr(arg)
  echoUntypedRepr(arg)

echoTypedAndUntypedRepr:
  var data = @[(1,"one"), (2,"two")]
  for (i, d) in pairs(data):
    discard
  for i, d in pairs(data):
    discard
  for i, (x,y) in pairs(data):
    discard
  var (a,b) = (1,2)
  type A* = object # issue #22933
  var
    c* = 1
    (d* {.used.}, e*) = (1, 2)
  let f* = 1
  const g* = 1
  proc h*() = discard
  template i*() = discard

echoUntypedRepr:
  var t04 = 1'f128
  t04 = 2'f128

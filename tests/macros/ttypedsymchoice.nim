# issue #12831

import std/[macros, strutils]

macro dumpRepr(x: typed): untyped =
  result = newLit(x.treeRepr & "\n")
doAssert dumpRepr(`$`).startsWith("ClosedSymChoice")

# issue #19446

macro typedVarargs(x: varargs[typed]): untyped =
  result = newLit($x[0].kind)

macro typedSingle(x: typed): untyped =
  result = newLit($x.kind)

doAssert typedSingle(len) == "nnkClosedSymChoice"
doAssert typedVarargs(len) == "nnkClosedSymChoice"

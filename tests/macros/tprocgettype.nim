discard """
  nimout: '''
var x: proc () {.cdecl.} = foo
var x: iterator (): int {.closure.} = bar
'''
"""

# issue #19010

import macros

macro createVar(x: typed): untyped =
  result = nnkVarSection.newTree:
    newIdentDefs(ident"x", getTypeInst(x), copy(x))
  
  echo repr result

block:
  proc foo() {.cdecl.} = discard

  createVar(foo)
  x()

block:
  iterator bar(): int {.closure.} = discard

  createVar(bar)
  for a in x(): discard

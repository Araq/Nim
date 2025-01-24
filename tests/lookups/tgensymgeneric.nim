discard """
  output: '''true'''
"""

# We need to open the gensym'ed symbol again so that the instantiation
# creates a fresh copy; but this is wrong the very first reason for gensym
# is that scope rules cannot be used! So simply removing 'sfGenSym' does
# not work. Copying the symbol does not work either because we're already
# the owner of the symbol! What we need to do is to copy the symbol
# in the generic instantiation process...

type
  TA = object
    x: int
  TB = object
    x: string

template genImpl() =
  var gensymed: T
  when T is TB:
    gensymed.x = "abc"
  else:
    gensymed.x = 123
  result = move gensymed

proc gen[T](x: T): T =
  genImpl()

var
  a: TA
  b: TB
let x = gen(a)
let y = gen(b)

doAssert x.x == 123
doAssert y.x == "abc"

# test symbol equality

import macros

static:
  let sym1 = genSym()
  let sym2 = genSym()
  let sym3 = sym1
  doAssert sym1 == sym1
  doAssert sym2 != sym3
  doAssert sym3 == sym1

echo "true"

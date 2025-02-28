discard """
  matrix: "--mm:orc"
  output: '''
found entry
'''
"""

import std/tables
type NoCopies = object

proc `=copy`(a: var NoCopies, b: NoCopies) {.error.}

# bug #24720
proc foo() =
  var t: Table[int, NoCopies]
  t[3] = NoCopies() # only moves
  for k, v in t.pairs(): # lent values, no need to copy!
    echo "found entry"

foo()

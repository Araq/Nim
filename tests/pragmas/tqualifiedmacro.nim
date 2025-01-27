discard """
  output: '''
template t
'''
"""

# issue #12696

import mqualifiedmacro
proc p() {. mqualifiedmacro.t .} = # errors with identifier expected but a.t found
  echo "proc p"

type Foo {. mqualifiedmacro.m("Bar") .} = object
doAssert Bar is object

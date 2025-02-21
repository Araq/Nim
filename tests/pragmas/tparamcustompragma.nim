discard """
  nimout: '''
proc foo(a {.attr.}: int) =
  discard

'''
"""

import macros
template attr*() {.pragma.}
proc foo(a {.attr.}: int) = discard
macro showImpl(a: typed) =
  echo repr getImpl(a)
showImpl(foo)

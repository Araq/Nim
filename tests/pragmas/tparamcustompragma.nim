discard """
  nimout: '''
proc foo(a {.attr.}: int) =
  discard

'''
"""

# fixes #24702

import macros
template attr*() {.pragma.}
proc foo(a {.attr.}: int) = discard
macro showImpl(a: typed) =
  echo repr getImpl(a)
showImpl(foo)

# issue #18095

import mqualifiedtypeclass

when true:
  # These work fine.
  discard default(mqualifiedtypeclass.A)
  proc f1(x: mqualifiedtypeclass.A) = discard
  discard default(mqualifiedtypeclass.B)
  proc f2(x: mqualifiedtypeclass.B) = discard
  discard default(A)
  proc f3(x: A) = discard
  discard default(B)
  proc f4(x: B) = discard
  proc f5(x: C) = discard
  proc f6(x: mqualifiedtypeclass.C | C) = discard

# Doesn't compile.
proc f(x: mqualifiedtypeclass.C) = discard

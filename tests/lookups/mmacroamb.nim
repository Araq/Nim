# issue #12732

import std/macros
const getPrivate3_tmp* = 0
const foobar1* = 0 # comment this or make private and it'll compile fine
macro foobar4*(): untyped =
  newLit "abc"
template currentPkgDir2*: string = foobar4()
macro currentPkgDir2*(dir: string): untyped =
  newLit "abc2"

# issue #23510

import ./mambtype1
import ./mambtype2

proc u(d: int | int) =
  var r: Y #[tt.Error
         ^ ambiguous identifier: 'Y' -- use one of the following:
  mambtype1.Y: Y
  mambtype2.Y: Y]#
  static: doAssert r is j.Y  # because j is imported first
  doAssert r is j.Y

u(0)

discard """
  matrix: "--gc:refc; --gc:arc"
"""

import std/widestrs

# bug #19862
type NewString = object

proc len(s: NewString): int = 10

converter toNewString(x: WideCStringObj): NewString = default(NewString)

let w = newWideCString("test")
doAssert len(w) == 4

discard """
  cmd: "nim c --mm:orc -d:useMalloc $file"
  valgrind: "true"
"""

import std/streams


proc foo() =
  var name = newStringStream("2r2")
  raise newException(ValueError, "sh")

try:
  foo()
except:
 discard
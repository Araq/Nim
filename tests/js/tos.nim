# xxx consider merging this in tests/stdlib/tos.nim for increased coverage (with selecting disabling)

static: doAssert defined(nodejs)

import os

block:
  doAssert "./foo//./bar/".normalizedPath == "foo/bar"
  doAssert relativePath(".//foo/bar", "foo") == "bar"
  doAssert "/".isAbsolute
  doAssert not "".isAbsolute
  doAssert not ".".isAbsolute
  doAssert not "foo".isAbsolute
  doAssert relativePath("", "bar") == ""
  doAssert normalizedPath(".///foo//./") == "foo"

  when nimvm: discard
  else:
    let cwd = getCurrentDir()
    doAssert cwd.isAbsolute
    doAssert relativePath(getCurrentDir() / "foo", "bar") == ".." / "foo"

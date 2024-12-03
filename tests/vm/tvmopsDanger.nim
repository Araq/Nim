discard """
  cmd: "nim c --experimental:vmopsDanger -r $file"
"""
when defined(nimPreviewSlimSystem):
  import std/assertions
import std/[times, os]

const foo = getTime()
let bar = foo
doAssert bar > low(Time)

static: # bug #23932
  doAssert getCurrentDir().len > 0

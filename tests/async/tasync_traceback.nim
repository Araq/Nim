discard """
  exitcode: 0
  output: "Matched"
"""
import asyncdispatch, strutils

# Tests to ensure our exception trace backs are friendly.

# --- Simple test. ---
#
# What does this look like when it's synchronous?
#
# tasync_traceback.nim(23) tasync_traceback
# tasync_traceback.nim(21) a
# tasync_traceback.nim(18) b
# Error: unhandled exception: b failure [OSError]
#
# Good (not quite ideal, but gotta work within constraints) traceback,
# when exception is unhandled:
#
# <traceback for the unhandled exception>
# <very much a bunch of noise>
# <would be ideal to customise this>
# <(the code responsible is in excpt:raiseExceptionAux)>
# Error: unhandled exception: b failure
# ===============
# Async traceback
# ===============
#
# tasync_traceback.nim(23) tasync_traceback
#
# tasync_traceback.nim(21) a
# tasync_traceback.nim(18) b

var result = ""

proc b(): Future[int] {.async.} =
  if true:
    raise newException(OSError, "b failure")

proc a(): Future[int] {.async.} =
  return await b()

let aFut = a()
try:
  discard waitFor aFut
except Exception as exc:
  result.add(exc.msg & "\n")
result.add("\n")

# From #6803
proc bar(): Future[string] {.async.} =
  await sleepAsync(100)
  if true:
    raise newException(OSError, "bar failure")

proc foo(): Future[string] {.async.} = return await bar()

try:
  result.add(waitFor(foo()) & "\n")
except Exception as exc:
  result.add(exc.msg & "\n")
result.add("\n")

# Use re to parse the result
import re
const expected = """
b failure
Async traceback:
  tasync_traceback\.nim\(\d+?\) tasync_traceback
  tasync_traceback\.nim\(\d+?\) a \(Async\)
  tasync_traceback\.nim\(\d+?\) b \(Async\)
Exception message: b failure


bar failure
Async traceback:
  tasync_traceback\.nim\(\d+?\) tasync_traceback
  tasync_traceback\.nim\(\d+?\) foo \(Async\)
  tasync_traceback\.nim\(\d+?\) bar \(Async\)
Exception message: bar failure

"""

# TODO: is asyncmacro good enough location for fooIter traceback/debugging? just put the callsite info for all?

let resLines = splitLines(result.strip)
let expLines = splitLines(expected.strip)

when not defined(cpp): # todo fixme
  if resLines.len != expLines.len:
    echo("Not matched! Wrong number of lines!")
    echo expLines.len
    echo resLines.len
    echo("Expected: -----------")
    echo expected
    echo("Gotten: -------------")
    echo result
    echo("---------------------")
    quit(QuitFailure)

  var ok = true
  for i in 0 ..< resLines.len:
    if not resLines[i].match(re(expLines[i])):
      echo "Not matched! Line ", i + 1
      echo "Expected:"
      echo expLines[i]
      echo "Actual:"
      echo resLines[i]
      ok = false

  if ok:
    echo("Matched")
  else:
    quit(QuitFailure)
else:
  echo("Matched")

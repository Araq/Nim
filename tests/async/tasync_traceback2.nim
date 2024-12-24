import std/asyncdispatch
import std/re
from std/strutils import dedent

proc err() =
  raise newException(ValueError, "the_error_msg")

block:
  proc recursion(i: int) {.async.} =
    if i == 5:
      err()
    await sleepAsync(1)
    await recursion(i+1)

  proc main {.async.} =
    await recursion(0)

  try:
    waitFor main()
    doAssert false
  except ValueError as err:
    let expected = """
      the_error_msg
      Async traceback:
        tasync_traceback2\.nim\(\d+\) tasync_traceback2
        tasync_traceback2\.nim\(\d+\) main \(Async\)
        tasync_traceback2\.nim\(\d+\) recursion \(Async\)
        tasync_traceback2\.nim\(\d+\) recursion \(Async\)
        tasync_traceback2\.nim\(\d+\) err
      Exception message: the_error_msg
      """.dedent
    doAssert match(err.msg, re(expected)), err.getStackTrace & err.msg

block:
  proc baz() =
    err()

  proc bar() =
    baz()

  proc foo() {.async.} =
    await sleepAsync(1)
    bar()

  proc main {.async.} =
    await foo()

  try:
    waitFor main()
    doAssert false
  except ValueError as err:
    let expected = """
      the_error_msg
      Async traceback:
        tasync_traceback2\.nim\(\d+\) tasync_traceback2
        tasync_traceback2\.nim\(\d+\) main \(Async\)
        tasync_traceback2\.nim\(\d+\) foo \(Async\)
        tasync_traceback2\.nim\(\d+\) bar
        tasync_traceback2\.nim\(\d+\) baz
        tasync_traceback2\.nim\(\d+\) err
      Exception message: the_error_msg
      """.dedent
    doAssert match(err.msg, re(expected)), err.getStackTrace & err.msg

block:  # async work
  proc baz() {.async.} =
    await sleepAsync(1)
    raise newException(ValueError, "the_error_msg")

  proc bar() {.async.} =
    await sleepAsync(1)
    await baz()

  proc foo() {.async.} =
    await sleepAsync(1)
    await bar()

  proc main {.async.} =
    await foo()

  try:
    waitFor main()
    doAssert false
  except ValueError as err:
    let expected = """
      the_error_msg
      Async traceback:
        tasync_traceback2\.nim\(\d+\) tasync_traceback2
        tasync_traceback2\.nim\(\d+\) main \(Async\)
        tasync_traceback2\.nim\(\d+\) foo \(Async\)
        tasync_traceback2\.nim\(\d+\) bar \(Async\)
        tasync_traceback2\.nim\(\d+\) baz \(Async\)
      Exception message: the_error_msg
      """.dedent
    doAssert match(err.msg, re(expected)), err.getStackTrace & err.msg

block:  # interleaved async work
  proc baz() {.async.} =
    await sleepAsync(1)
    raise newException(ValueError, "the_error_msg")

  proc bar() {.async.} =
    #await sleepAsync(1)
    await baz()

  proc foo() {.async.} =
    await sleepAsync(1)
    await bar()

  proc main {.async.} =
    await foo()

  try:
    waitFor main()
    doAssert false
  except ValueError as err:
    let expected = """
      the_error_msg
      Async traceback:
        tasync_traceback2\.nim\(\d+\) tasync_traceback2
        tasync_traceback2\.nim\(\d+\) main \(Async\)
        tasync_traceback2\.nim\(\d+\) foo \(Async\)
        tasync_traceback2\.nim\(\d+\) bar \(Async\)
        tasync_traceback2\.nim\(\d+\) baz \(Async\)
      Exception message: the_error_msg
      """.dedent
    doAssert match(err.msg, re(expected)), err.getStackTrace & err.msg

block:  # no async work
  proc baz() {.async.} =
    raise newException(ValueError, "the_error_msg")

  proc bar() {.async.} =
    await baz()

  proc foo() {.async.} =
    await bar()

  proc main {.async.} =
    await foo()

  try:
    waitFor main()
    doAssert false
  except ValueError as err:
    let expected = """
      the_error_msg
      Async traceback:
        tasync_traceback2\.nim\(\d+\) tasync_traceback2
        tasync_traceback2\.nim\(\d+\) main \(Async\)
        tasync_traceback2\.nim\(\d+\) foo \(Async\)
        tasync_traceback2\.nim\(\d+\) bar \(Async\)
        tasync_traceback2\.nim\(\d+\) baz \(Async\)
      Exception message: the_error_msg
      """.dedent
    doAssert match(err.msg, re(expected)), err.getStackTrace & err.msg

echo "ok"

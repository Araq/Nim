import std/asyncdispatch

type MyError = object of ValueError

proc err(throw: bool) =
  if throw:
    raise newException(MyError, "myerr")

block:
  proc bar() {.async.} =
    err(false)
  
  proc foo() {.async.} =
    await bar()

  proc main {.async, raises: [MyError].} =
    await foo()

  waitFor main()

block:
  proc foo() {.async, raises: [MyError].} =
    err(false)

  proc main {.async, raises: [MyError].} =
    await foo()

  waitFor main()

block:
  proc foo() {.async, raises: [MyError].} =
    err(false)

  proc bar(fut: FutureEx[void, (MyError,)]) {.async, raises: [MyError].} =
    await fut

  proc main {.async, raises: [MyError].} =
    await bar(foo())

  waitFor main()

block:
  template good =
    proc foo() {.async, raises: [MyError].} =
      err(false)
  template missingRaise =
    proc foo() {.async, raises: [].} =
      err(false)
  doAssert compiles(good())
  doAssert not compiles(missingRaise())

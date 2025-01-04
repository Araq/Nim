import std/asyncdispatch

type MyError = object of ValueError

proc err(throw: bool) =
  if throw:
    raise newException(MyError, "myerr")

block:
  proc bar {.async.} =
    err(false)
  
  proc foo {.async.} =
    await bar()

  proc main {.async, raises: [MyError].} =
    await foo()

  waitFor main()

block:
  proc foo {.async, raises: [MyError].} =
    err(false)

  proc main {.async, raises: [MyError].} =
    await foo()

  waitFor main()

block:
  proc foo {.async, raises: [MyError].} =
    err(false)

  proc bar(fut: FutureEx[void, (MyError,)]) {.async, raises: [MyError].} =
    await fut

  proc main {.async, raises: [MyError].} =
    let fooFut = toFutureEx foo()
    await bar(fooFut)

  waitFor main()

block:
  proc foo: Future[int] {.async, raises: [].} =
    discard

block:
  # we cannot tell if fcb is an async proc
  # or a closure that returns a user created newFuture()
  # that can raise anything
  type FooBar = object
    fcb: proc(): Future[void] {.closure, gcsafe.}

  proc bar {.async.} =
    discard

  proc foo {.async.} =
    var f = FooBar(fcb: bar)
    await f.fcb()

  template good =
    proc main {.async, raises: [Exception].} =
      await foo()
  template bad =
    proc main {.async, raises: [].} =
      await foo()
  doAssert compiles(good())
  doAssert not compiles(bad())

block:
  template good =
    proc foo {.async, raises: [MyError].} =
      err(false)
  template bad =
    proc foo {.async, raises: [].} =
      err(false)
  doAssert compiles(good())
  doAssert not compiles(bad())

block:
  proc bar {.async.} =
    err(false)

  proc foo {.async.} =
    await bar()

  template good =
    proc main {.async, raises: [MyError].} =
      await foo()
  template bad =
    proc main {.async, raises: [].} =
      await foo()
  doAssert compiles(good())
  doAssert not compiles(bad())

block:
  template good =
    proc foo(fut: FutureEx[void, (MyError,)]) {.async, raises: [MyError].} =
      await fut
  template bad =
    proc foo(fut: FutureEx[void, (MyError,)]) {.async, raises: [].} =
      await fut
  doAssert compiles(good())
  doAssert not compiles(bad())

block:
  template good =
    proc foo {.async, raises: [Exception].} =
      await newFuture[void]()
  template bad =
    proc foo {.async, raises: [].} =
      await newFuture[void]()
  doAssert compiles(good())
  doAssert not compiles(bad())

block:
  proc fut: Future[void] =
    newFuture[void]()

  template good =
    proc main {.async, raises: [Exception].} =
      await fut()
  template bad =
    proc main {.async, raises: [].} =
      await fut()
  doAssert compiles(good())
  doAssert not compiles(bad())

block:
  proc bar() {.async.} =
    err(false)

  # XXX We could check all returns are from async procs
  #     and if so use the inferred proc raises
  proc foo(): Future[void] =
    bar()

  template good =
    proc main {.async, raises: [Exception].} =
      await foo()
  template bad =
    proc main {.async, raises: [MyError].} =
      await foo()
  doAssert compiles(good())
  doAssert not compiles(bad())

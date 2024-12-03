discard """
  matrix: "--warningAsError:ProveInit --warningAsError:Uninit"
"""

{.experimental: "strictdefs".}

type Test = object
  id: int

proc foo {.noreturn.} = discard

block:
  proc test(x: bool): Test =
    if x:
      foo()
    else:
      foo()

block:
  proc test(x: bool): Test =
    if x:
      result = Test()
    else:
      foo()

  discard test(true)

block:
  proc test(x: bool): Test =
    if x:
      result = Test()
    else:
      return Test()

  discard test(true)

block:
  proc test(x: bool): Test =
    if x:
      return Test()
    else:
      return Test()

  discard test(true)

block:
  proc test(x: bool): Test =
    if x:
      result = Test()
    else:
      result = Test()
      return

  discard test(true)

block:
  proc test(x: bool): Test =
    if x:
      result = Test()
      return
    else:
      raise newException(ValueError, "unreachable")

  discard test(true)

# bug #21615
# bug #16735

block:
  type Test {.requiresInit.} = object
    id: int

  proc bar(): int =
    raise newException(CatchableError, "error")

  proc test(): Test =
    raise newException(CatchableError, "")

  template catchError(body) =
    var done = false
    try:
      body
    except CatchableError:
      done = true
    doAssert done

  catchError:
    echo test()

  catchError:
    echo bar()

block:
  proc foo(x: ptr int) =
    discard

  proc main =
    var s: int
    foo(addr s)

  main()

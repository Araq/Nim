discard """
  targets: cpp
"""

# manual example

type
  CStdException {.importcpp: "std::exception", header: "<exception>", inheritable.} = object
    ## does not inherit from `RootObj`, so we use `inheritable` instead
  CRuntimeError {.requiresInit, importcpp: "std::runtime_error", header: "<stdexcept>".} = object of CStdException
    ## `CRuntimeError` has no default constructor => `requiresInit`
proc what(s: CStdException): cstring {.importcpp: "((char *)#.what())".}
proc initRuntimeError(a: cstring): CRuntimeError {.importcpp: "std::runtime_error(@)", constructor.}
proc initStdException(): CStdException {.importcpp: "std::exception()", constructor.}

proc fn() =
  let a = initRuntimeError("foo")
  doAssert $a.what == "foo"
  var b = ""
  try: raise initRuntimeError("foo2")
  except CStdException as e:
    doAssert e is CStdException
    b = $e.what()
  doAssert b == "foo2"

  try: raise initStdException()
  except CStdException: discard

  try: raise initRuntimeError("foo3")
  except CRuntimeError as e:
    b = $e.what()
  except CStdException:
    doAssert false
  doAssert b == "foo3"

fn()

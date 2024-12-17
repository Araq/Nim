discard """
  targets: "c js"
"""

import std/assertions

block: # bug #4299
  proc scopeProc() =
    proc normalProc() =
      discard

    proc genericProc[T]() =
      normalProc()

    genericProc[string]()

  scopeProc()

block: # bug #12492
  proc foo() =
    var i = 0
    proc bar() =
      inc i

    bar()
    doAssert i == 1

  foo()
  static:
    foo()

block: # bug #10849
  type
    Generic[T] = ref object
      getState: proc(): T

  proc newGeneric[T](): Generic[T] =
    var state: T

    proc getState[T](): T =
      state

    Generic[T](getState: getState)

  let g = newGeneric[int]()
  let state = g.getState()
  doAssert state == 0

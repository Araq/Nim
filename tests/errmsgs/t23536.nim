discard """
  matrix: "--stackTrace:on --excessiveStackTrace:off"
"""

const expected = """
wrong trace:
t23536.nim(22)           t23536
t23536.nim(17)           foo
assertions.nim(41)       failedAssertImpl
assertions.nim(36)       raiseAssert
fatal.nim(53)            sysFatal
"""


try:
  proc foo = # bug #23536
    doAssert false

  for i in 0 .. 1:


    foo()
except AssertionDefect:
  let e = getCurrentException()
  let trace = e.getStackTrace
  doAssert "wrong trace:\n" & trace == expected

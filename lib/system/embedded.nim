#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#


# Bare-bones implementation of some things for embedded targets.

proc chckIndx(i, a, b: int): int {.inline, compilerproc.}
proc chckRange(i, a, b: int): int {.inline, compilerproc.}
proc chckRangeF(x, a, b: float): float {.inline, compilerproc.}
proc chckNil(p: pointer) {.inline, compilerproc.}

proc nimFrame(s: PFrame) {.compilerRtl, inl, exportc: "nimFrame".} = discard
proc popFrame {.compilerRtl, inl.} = discard

proc setFrame(s: PFrame) {.compilerRtl, inl.} = discard
when not gotoBasedExceptions:
  proc pushSafePoint(s: PSafePoint) {.compilerRtl, inl.} = discard
  proc popSafePoint {.compilerRtl, inl.} = discard
proc pushCurrentException(e: ref Exception) {.compilerRtl, inl.} = discard
proc popCurrentException {.compilerRtl, inl.} = discard

# some platforms have native support for stack traces:
const
  nativeStackTraceSupported = false
  hasSomeStackTrace = false

proc quitOrDebug() {.noreturn, importc: "abort", header: "<stdlib.h>", nodecl.}

proc raiseException(e: ref Exception, ename: cstring) {.compilerRtl.} =
  sysFatal(ReraiseDefect, "exception handling is not available")

proc raiseExceptionEx(e: sink(ref Exception), ename, procname, filename: cstring,
                      line: int) {.compilerRtl.} =
  sysFatal(ReraiseDefect, "exception handling is not available")

proc reraiseException() {.compilerRtl.} =
  sysFatal(ReraiseDefect, "no exception to reraise")

proc writeStackTrace() = discard

proc unsetControlCHook() = discard
proc setControlCHook(hook: proc () {.noconv.}) = discard

proc closureIterSetupExc(e: ref Exception) {.compilerproc, inline.} =
  sysFatal(ReraiseDefect, "exception handling is not available")

when gotoBasedExceptions:
  var nimInErrorMode {.threadvar.}: bool

  proc nimErrorFlag(): ptr bool {.compilerRtl, inl.} =
    result = addr(nimInErrorMode)

  proc nimTestErrorFlag() {.compilerRtl.} =
    if nimInErrorMode:
      sysFatal(ReraiseDefect, "exception handling is not available")

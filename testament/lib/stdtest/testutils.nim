import std/private/miscdollars
when defined(nimscript):
  import std/os # xxx investigate why needed
else:
  from std/os import getEnv
import std/[macros, genasts]

template flakyAssert*(cond: untyped, msg = "", notifySuccess = true) =
  ## API to deal with flaky or failing tests. This avoids disabling entire tests
  ## altogether so that at least the parts that are working are kept being
  ## tested. This also avoids making CI fail periodically for tests known to
  ## be flaky. Finally, for known failures, passing `notifySuccess = true` will
  ## log that the test succeeded, which may indicate that a bug was fixed
  ## "by accident" and should be looked into.
  const info = instantiationInfo(-1, true)
  const expr = astToStr(cond)
  if cond and not notifySuccess:
    discard # silent success
  else:
    var msg2 = ""
    toLocation(msg2, info.filename, info.line, info.column)
    if cond:
      # a flaky test is failing, we still report it but we don't fail CI
      msg2.add " FLAKY_SUCCESS "
    else:
      # a previously failing test is now passing, a pre-existing bug might've been
      # fixed by accidend
      msg2.add " FLAKY_FAILURE "
    msg2.add $expr & " " & msg
    echo msg2

when not defined(js) and not defined(nimscript):
  import std/strutils

  proc greedyOrderedSubsetLines*(lhs, rhs: string, allowPrefixMatch = false): bool =
    ## Returns true if each stripped line in `lhs` appears in rhs, using a greedy matching.
    # xxx improve error reporting by showing the last matched pair
    iterator splitLinesClosure(): string {.closure.} =
      for line in splitLines(rhs.strip):
        yield line
    template isMatch(lhsi, rhsi): bool =
      if allowPrefixMatch:
        startsWith(rhsi, lhsi)
      else:
        lhsi == rhsi

    var rhsIter = splitLinesClosure
    var currentLine = strip(rhsIter())

    for line in lhs.strip.splitLines:
      let line = line.strip
      if line.len != 0:
        while not isMatch(line, currentLine):
          currentLine = strip(rhsIter())
          if rhsIter.finished:
            return false

      if rhsIter.finished:
        return false
    return true

template enableRemoteNetworking*: bool =
  ## Allows contolling whether to run some test at a statement-level granularity.
  ## Using environment variables simplifies propagating this all the way across
  ## process calls, e.g. `testament all` calls itself, which in turns invokes
  ## a `nim` invocation (possibly via additional intermediate processes).
  getEnv("NIM_TESTAMENT_REMOTE_NETWORKING") == "1"

template disableSSLTesting*: bool =
  ## TODO: workaround for GitHub Action gcc 14 matrix; remove this
  ## matrix and the flag after Azure agent supports ubuntu 24.04
  getEnv("NIM_TESTAMENT_DISABLE_SSL") == "1"

template whenRuntimeJs*(bodyIf, bodyElse) =
  ##[
  Behaves as `when defined(js) and not nimvm` (which isn't legal yet).
  pending improvements to `nimvm`, this sugar helps; use as follows:

  whenRuntimeJs:
    doAssert defined(js)
    when nimvm: doAssert false
    else: discard
  do:
    discard
  ]##
  when nimvm: bodyElse
  else:
    when defined(js): bodyIf
    else: bodyElse

template whenVMorJs*(bodyIf, bodyElse) =
  ## Behaves as: `when defined(js) or nimvm`
  when nimvm: bodyIf
  else:
    when defined(js): bodyIf
    else: bodyElse

template accept*(a) =
  doAssert compiles(a)

template reject*(a) =
  doAssert not compiles(a)

template disableVm*(body) =
  when nimvm: discard
  else: body

macro assertAll*(body) =
  ## works in VM, unlike `check`, `require`
  runnableExamples:
    assertAll:
      1+1 == 2
      var a = @[1, 2] # statements work
      a.len == 2
  # remove this once these support VM, pending #10129 (closed but not yet fixed)
  result = newStmtList()
  for a in body:
    result.add genAst(a, a2 = a.repr, info = lineInfo(a)) do:
      # D20210421T014713:here
      # xxx pending https://github.com/nim-lang/Nim/issues/12030,
      # `typeof` should introduce its own scope, so that this
      # is sufficient: `typeof(a)` instead of `typeof(block: a)`
      when typeof(block: a) is void: a
      else:
        if not a:
          raise newException(AssertionDefect, info & " " & a2)

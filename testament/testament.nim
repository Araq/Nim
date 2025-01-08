#
#
#            Nim Testament
#        (c) Copyright 2017 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This program verifies Nim against the testcases.

import
  std/[strutils, pegs, os, osproc, streams, json,
    parseopt, browsers, terminal, exitprocs,
    algorithm, times, intsets, macros]

import backend, specs, azure, htmlgen

from std/sugar import dup
import compiler/nodejs
import lib/stdtest/testutils
from lib/stdtest/specialpaths import splitTestFile
from std/private/gitutils import diffStrings

import ../dist/checksums/src/checksums/md5

proc trimUnitSep(x: var string) =
  let L = x.len
  if L > 0 and x[^1] == '\31':
    setLen x, L-1

var useColors = true
var backendLogging = true
var simulate = false
var optVerbose = false
var useMegatest = true
var valgrindEnabled = true

proc verboseCmd(cmd: string) =
  if optVerbose:
    echo "executing: ", cmd

const
  failString* = "FAIL: " # ensures all failures can be searched with 1 keyword in CI logs
  testsDir = "tests" & DirSep
  resultsFile = "testresults.html"
  Usage = """Usage:
  testament [options] command [arguments]

Command:
  p|pat|pattern <glob>        run all the tests matching the given pattern
  all                         run all tests in category folders
  c|cat|category <category>   run all the tests of a certain category
  r|run <test>                run single test file
  html                        generate $1 from the database
Arguments:
  arguments are passed to the compiler
Options:
  --print                   print results to the console
  --verbose                 print commands (compiling and running tests)
  --simulate                see what tests would be run but don't run them (for debugging)
  --failing                 only show failing/ignored tests
  --targets:"c cpp js objc" run tests for specified targets (default: c)
  --nim:path                use a particular nim executable (default: $$PATH/nim)
  --directory:dir           Change to directory dir before reading the tests or doing anything else.
  --colors:on|off           Turn messages coloring on|off.
  --backendLogging:on|off   Disable or enable backend logging. By default turned on.
  --megatest:on|off         Enable or disable megatest. Default is on.
  --valgrind:on|off         Enable or disable valgrind support. Default is on.
  --skipFrom:file           Read tests to skip from `file` - one test per line, # comments ignored

On Azure Pipelines, testament will also publish test results via Azure Pipelines' Test Management API
provided that System.AccessToken is made available via the environment variable SYSTEM_ACCESSTOKEN.

Experimental: using environment variable `NIM_TESTAMENT_REMOTE_NETWORKING=1` enables
tests with remote networking (as in CI).
""" % resultsFile

proc isNimRepoTests(): bool =
  # this logic could either be specific to cwd, or to some file derived from
  # the input file, eg testament r /pathto/tests/foo/tmain.nim; we choose
  # the former since it's simpler and also works with `testament all`.
  let file = "testament"/"testament.nim.cfg"
  result = file.fileExists

type
  Category = distinct string
  TResults = object
    total, passed, failedButAllowed, skipped: int
      ## xxx rename passed to passedOrAllowedFailure
    data: string
  TTest = object
    name: string
    cat: Category
    options: string
    testArgs: seq[string]
    spec: TSpec
    startTime: float
    debugInfo: string

# ----------------------------------------------------------------------------

let
  pegLineError =
    peg"{[^(]*} '(' {\d+} ', ' {\d+} ') ' ('Error') ':' \s* {.*}"
  pegOtherError = peg"'Error:' \s* {.*}"
  pegOfInterest = pegLineError / pegOtherError

var gTargets = {low(TTarget)..high(TTarget)}
var targetsSet = false

proc isSuccess(input: string): bool =
  # not clear how to do the equivalent of pkg/regex's: re"FOO(.*?)BAR" in pegs
  # note: this doesn't handle colors, eg: `\e[1m\e[0m\e[32mHint:`; while we
  # could handle colors, there would be other issues such as handling other flags
  # that may appear in user config (eg: `--filenames`).
  # Passing `XDG_CONFIG_HOME= testament args...` can be used to ignore user config
  # stored in XDG_CONFIG_HOME, refs https://wiki.archlinux.org/index.php/XDG_Base_Directory
  input.startsWith("Hint: ") and input.endsWith("[SuccessX]")

proc getFileDir(filename: string): string =
  result = filename.splitFile().dir
  if not result.isAbsolute():
    result = getCurrentDir() / result

proc execCmdEx2(command: string, args: openArray[string]; workingDir: string = "", input: string = ""): tuple[
                cmdLine: string,
                output: string,
                exitCode: int] {.tags:
                [ExecIOEffect, ReadIOEffect, RootEffect], gcsafe.} =
  result = ("", "", 0)
  result.cmdLine.add quoteShell(command)
  for arg in args:
    result.cmdLine.add ' '
    result.cmdLine.add quoteShell(arg)
  verboseCmd(result.cmdLine)
  var p = startProcess(command, workingDir = workingDir, args = args,
                       options = {poStdErrToStdOut, poUsePath})
  var outp = outputStream(p)

  # There is no way to provide input for the child process
  # anymore. Closing it will create EOF on stdin instead of eternal
  # blocking.
  let instream = inputStream(p)
  instream.write(input)
  close instream

  result.exitCode = -1
  var line = newStringOfCap(120)
  while true:
    if outp.readLine(line):
      result.output.add line
      result.output.add '\n'
    else:
      result.exitCode = peekExitCode(p)
      if result.exitCode != -1: break
  close(p)

proc nimcacheDir(filename, options: string, target: TTarget): string =
  ## Give each test a private nimcache dir so they don't clobber each other's.
  let hashInput = options & $target
  result = "nimcache" / (filename & '_' & hashInput.getMD5)

proc prepareTestCmd(cmdTemplate, filename, options, nimcache: string,
                     target: TTarget, extraOptions = ""): string =
  var options = target.defaultOptions & ' ' & options
  if nimcache.len > 0: options.add(" --nimCache:$#" % nimcache.quoteShell)
  options.add ' ' & extraOptions
  # we avoid using `parseCmdLine` which is buggy, refs bug #14343
  result = cmdTemplate % ["target", targetToCmd[target],
                      "options", options, "file", filename.quoteShell,
                      "filedir", filename.getFileDir(), "nim", compilerPrefix]

proc callNimCompiler(cmdTemplate, filename, options, nimcache: string,
                     target: TTarget, extraOptions = ""): TSpec =
  result = TSpec(cmd: prepareTestCmd(cmdTemplate, filename, options, nimcache, target,
                          extraOptions))
  verboseCmd(result.cmd)
  var p = startProcess(command = result.cmd,
                       options = {poStdErrToStdOut, poUsePath, poEvalCommand})
  let outp = p.outputStream
  var foundSuccessMsg = false
  var foundErrorMsg = false
  var err = ""
  var x = newStringOfCap(120)
  result.nimout = ""
  while true:
    if outp.readLine(x):
      trimUnitSep x
      result.nimout.add(x & '\n')
      if x =~ pegOfInterest:
        # `err` should contain the last error message
        err = x
        foundErrorMsg = true
      elif x.isSuccess:
        foundSuccessMsg = true
    elif not running(p):
      break
  result.msg = ""
  result.file = ""
  result.output = ""
  result.line = 0
  result.column = 0

  result.err = reNimcCrash
  result.exitCode = p.peekExitCode
  close p
  case result.exitCode
  of 0:
    if foundErrorMsg:
      result.debugInfo.add " compiler exit code was 0 but some Error's were found."
    else:
      result.err = reSuccess
  of 1:
    if not foundErrorMsg:
      result.debugInfo.add " compiler exit code was 1 but no Error's were found."
    if foundSuccessMsg:
      result.debugInfo.add " compiler exit code was 1 but no `isSuccess` was true."
  else:
    result.debugInfo.add " expected compiler exit code 0 or 1, got $1." % $result.exitCode

  if err =~ pegLineError:
    result.file = extractFilename(matches[0])
    result.line = parseInt(matches[1])
    result.column = parseInt(matches[2])
    result.msg = matches[3]
  elif err =~ pegOtherError:
    result.msg = matches[0]
  trimUnitSep result.msg

proc initResults: TResults =
  result = TResults(
    total: 0,
    passed: 0,
    failedButAllowed: 0,
    skipped: 0,
    data: ""
  )

macro ignoreStyleEcho(args: varargs[typed]): untyped =
  let typForegroundColor = bindSym"ForegroundColor".getType
  let typBackgroundColor = bindSym"BackgroundColor".getType
  let typStyle = bindSym"Style".getType
  let typTerminalCmd = bindSym"TerminalCmd".getType
  result = newCall(bindSym"echo")
  for arg in children(args):
    if arg.kind == nnkNilLit: continue
    let typ = arg.getType
    if typ.kind != nnkEnumTy or
       typ != typForegroundColor and
       typ != typBackgroundColor and
       typ != typStyle and
       typ != typTerminalCmd:
      result.add(arg)

template maybeStyledEcho(args: varargs[untyped]): untyped =
  if useColors:
    styledEcho(args)
  else:
    ignoreStyleEcho(args)


proc `$`(x: TResults): string =
  result = """
Tests passed or allowed to fail: $2 / $1 <br />
Tests failed and allowed to fail: $3 / $1 <br />
Tests skipped: $4 / $1 <br />
""" % [$x.total, $x.passed, $x.failedButAllowed, $x.skipped]

proc testName(test: TTest, target: TTarget, extraOptions: string, allowFailure: bool): string =
  var name = test.name.replace(DirSep, '/')
  name.add ' ' & $target
  if allowFailure:
    name.add " (allowed to fail) "
  if test.options.len > 0: name.add ' ' & test.options
  if extraOptions.len > 0: name.add ' ' & extraOptions
  name.strip()

proc addResult(r: var TResults, test: TTest, target: TTarget,
               extraOptions, expected, given: string, success: TResultEnum, duration: float,
               allowFailure = false, givenSpec: ptr TSpec = nil) =
  # instead of `ptr TSpec` we could also use `Option[TSpec]`; passing `givenSpec` makes it easier to get what we need
  # instead of having to pass individual fields, or abusing existing ones like expected vs given.
  # test.name is easier to find than test.name.extractFilename
  # A bit hacky but simple and works with tests/testament/tshould_not_work.nim
  let name = testName(test, target, extraOptions, allowFailure)

  let durationStr = duration.formatFloat(ffDecimal, precision = 2).align(5)
  if backendLogging:
    backend.writeTestResult(name = name,
                            category = test.cat.string,
                            target = $target,
                            action = $test.spec.action,
                            result = $success,
                            expected = expected,
                            given = given)
  r.data.addf("$#\t$#\t$#\t$#", name, expected, given, $success)
  template dispNonSkipped(color, outcome) =
    maybeStyledEcho color, outcome, fgCyan, test.debugInfo, alignLeft(name, 60), fgBlue, " (", durationStr, " sec)"
  template disp(msg) =
    maybeStyledEcho styleDim, fgYellow, msg & ' ', styleBright, fgCyan, name
  if success == reSuccess:
    dispNonSkipped(fgGreen, "PASS: ")
  elif success == reDisabled:
    if test.spec.inCurrentBatch: disp("SKIP:")
    else: disp("NOTINBATCH:")
  elif success == reJoined: disp("JOINED:")
  else:
    dispNonSkipped(fgRed, failString)
    maybeStyledEcho styleBright, fgCyan, "Test \"", test.name, "\"", " in category \"", test.cat.string, "\""
    maybeStyledEcho styleBright, fgRed, "Failure: ", $success
    if givenSpec != nil and givenSpec.debugInfo.len > 0:
      echo "debugInfo: " & givenSpec.debugInfo
    if success in {reBuildFailed, reNimcCrash, reInstallFailed}:
      # expected is empty, no reason to print it.
      echo given
    else:
      maybeStyledEcho fgYellow, "Expected:"
      maybeStyledEcho styleBright, expected, "\n"
      maybeStyledEcho fgYellow, "Gotten:"
      maybeStyledEcho styleBright, given, "\n"
      echo diffStrings(expected, given).output

  if backendLogging and (isAppVeyor or isAzure):
    let (outcome, msg) =
      case success
      of reSuccess:
        ("Passed", "")
      of reDisabled, reJoined:
        ("Skipped", "")
      of reBuildFailed, reNimcCrash, reInstallFailed:
        ("Failed", "Failure: " & $success & '\n' & given)
      else:
        ("Failed", "Failure: " & $success & "\nExpected:\n" & expected & "\n\n" & "Gotten:\n" & given)
    if isAzure:
      azure.addTestResult(name, test.cat.string, int(duration * 1000), msg, success)
    else:
      var p = startProcess("appveyor", args = ["AddTest", test.name.replace("\\", "/") & test.options,
                           "-Framework", "nim-testament", "-FileName",
                           test.cat.string,
                           "-Outcome", outcome, "-ErrorMessage", msg,
                           "-Duration", $(duration * 1000).int],
                           options = {poStdErrToStdOut, poUsePath, poParentStreams})
      discard waitForExit(p)
      close(p)

proc finishTest(r: var TResults, test: TTest, target: TTarget,
                extraOptions, expected, given: string, successOrig: TResultEnum,
                allowFailure = false, givenSpec: ptr TSpec = nil) =
  ## calculates duration of test, reports result
  ## `retries` option in the test is ignored
  let duration = epochTime() - test.startTime
  let success = if test.spec.timeout > 0.0 and duration > test.spec.timeout: reTimeout
                else: successOrig
  addResult(r, test, target, extraOptions, expected, given, success, duration, allowFailure, givenSpec)

proc finishTestRetryable(r: var TResults, test: TTest, target: TTarget,
                         extraOptions, expected, given: string, successOrig: TResultEnum,
                         allowFailure = false, givenSpec: ptr TSpec = nil): bool =
  ## if test failed and has remaining retries, return `true`,
  ## otherwise calculate duration and report result
  ## 
  ## warning: if `true` is returned, then the result is not reported,
  ## it has to be retried or `finishTest` should be called instead 
  result = false
  let duration = epochTime() - test.startTime
  let success = if test.spec.timeout > 0.0 and duration > test.spec.timeout: reTimeout
                else: successOrig
  if test.spec.retries > 0 and success notin {reSuccess, reDisabled, reJoined, reInvalidSpec}:
    return true
  else:
    addResult(r, test, target, extraOptions, expected, given, success, duration, allowFailure, givenSpec)

proc toString(inlineError: InlineError, filename: string): string =
  result = "$file($line, $col) $kind: $msg" % [
    "file", filename,
    "line", $inlineError.line,
    "col", $inlineError.col,
    "kind", $inlineError.kind,
    "msg", $inlineError.msg
  ]

proc inlineErrorsMsgs(expected: TSpec): string =
  result = ""
  for inlineError in expected.inlineErrors.items:
    result.addLine inlineError.toString(expected.filename)

proc checkForInlineErrors(expected, given: TSpec): bool =
  for inlineError in expected.inlineErrors:
    if inlineError.toString(expected.filename) notin given.nimout:
      return false
  true

proc nimoutCheck(expected, given: TSpec): bool =
  result = true
  if expected.nimoutFull:
    if expected.nimout != given.nimout:
      result = false
  elif expected.nimout.len > 0 and not greedyOrderedSubsetLines(expected.nimout, given.nimout):
    result = false

proc cmpMsgs(r: var TResults, expected, given: TSpec, test: TTest,
             target: TTarget, extraOptions: string): bool =
  # result has to be checked for retry
  if not checkForInlineErrors(expected, given) or
    (not expected.nimoutFull and not nimoutCheck(expected, given)):
      result = r.finishTestRetryable(test, target, extraOptions, expected.nimout & inlineErrorsMsgs(expected), given.nimout, reMsgsDiffer)
  elif strip(expected.msg) notin strip(given.msg):
    result = r.finishTestRetryable(test, target, extraOptions, expected.msg, given.msg, reMsgsDiffer)
  elif not nimoutCheck(expected, given):
    result = r.finishTestRetryable(test, target, extraOptions, expected.nimout, given.nimout, reMsgsDiffer)
  elif extractFilename(expected.file) != extractFilename(given.file) and
      "internal error:" notin expected.msg:
    result = r.finishTestRetryable(test, target, extraOptions, expected.file, given.file, reFilesDiffer)
  elif expected.line != given.line and expected.line != 0 or
       expected.column != given.column and expected.column != 0:
    result = r.finishTestRetryable(test, target, extraOptions, $expected.line & ':' & $expected.column,
                      $given.line & ':' & $given.column, reLinesDiffer)
  else:
    result = r.finishTestRetryable(test, target, extraOptions, expected.msg, given.msg, reSuccess)
    inc(r.passed)

proc generatedFile(test: TTest, target: TTarget): string =
  if target == targetJS:
    result = test.name.changeFileExt("js")
  else:
    let (_, name, _) = test.name.splitFile
    let ext = targetToExt[target]
    result = nimcacheDir(test.name, test.options, target) / "@m" & name.changeFileExt(ext)

proc needsCodegenCheck(spec: TSpec): bool =
  result = spec.maxCodeSize > 0 or spec.ccodeCheck.len > 0

proc codegenCheck(test: TTest, target: TTarget, spec: TSpec, expectedMsg: var string,
                  given: var TSpec) =
  try:
    let genFile = generatedFile(test, target)
    let contents = readFile(genFile)
    for check in spec.ccodeCheck:
      if check.len > 0 and check[0] == '\\':
        # little hack to get 'match' support:
        if not contents.match(check.peg):
          given.err = reCodegenFailure
      elif contents.find(check.peg) < 0:
        given.err = reCodegenFailure
      expectedMsg = check
    if spec.maxCodeSize > 0 and contents.len > spec.maxCodeSize:
      given.err = reCodegenFailure
      given.msg = "generated code size: " & $contents.len
      expectedMsg = "max allowed size: " & $spec.maxCodeSize
  except ValueError:
    given.err = reInvalidPeg
    echo getCurrentExceptionMsg()
  except IOError:
    given.err = reCodeNotFound
    echo getCurrentExceptionMsg()

proc compilerOutputTests(test: TTest, target: TTarget, extraOptions: string,
                         given: var TSpec, expected: TSpec; r: var TResults): bool =
  # result has to be checked for retry
  var expectedmsg: string = ""
  var givenmsg: string = ""
  if given.err == reSuccess:
    if expected.needsCodegenCheck:
      codegenCheck(test, target, expected, expectedmsg, given)
      givenmsg = given.msg
    if not nimoutCheck(expected, given) or
       not checkForInlineErrors(expected, given):
      given.err = reMsgsDiffer
      expectedmsg = expected.nimout & inlineErrorsMsgs(expected)
      givenmsg = given.nimout.strip
  else:
    givenmsg = "$ " & given.cmd & '\n' & given.nimout
  if given.err == reSuccess: inc(r.passed)
  result = r.finishTestRetryable(test, target, extraOptions, expectedmsg, givenmsg, given.err)

proc getTestSpecTarget(): TTarget =
  if getEnv("NIM_COMPILE_TO_CPP", "false") == "true":
    result = targetCpp
  else:
    result = targetC

var count = 0

proc equalModuloLastNewline(a, b: string): bool =
  # allow lazy output spec that omits last newline, but really those should be fixed instead
  result = a == b or b.endsWith("\n") and a == b[0 ..< ^1]

proc testSpecHelper(r: var TResults, test: var TTest, expected: TSpec,
                    target: TTarget, extraOptions: string, nimcache: string) =
  template maybeRetry(x: bool) =
    # if `x` is true, retries the test
    if x:
      test.spec.err = reRetry
      dec test.spec.retries
      testSpecHelper(r, test, expected, target, extraOptions, nimcache)
      return
  if test.spec.err != reRetry:
    test.startTime = epochTime()
  if testName(test, target, extraOptions, false) in skips:
    test.spec.err = reDisabled

  if test.spec.err in {reDisabled, reJoined}:
    r.finishTest(test, target, extraOptions, "", "", test.spec.err)
    inc(r.skipped)
    return
  var given = callNimCompiler(expected.getCmd, test.name, test.options, nimcache, target, extraOptions)
  case expected.action
  of actionCompile:
    maybeRetry compilerOutputTests(test, target, extraOptions, given, expected, r)
  of actionRun:
    if given.err != reSuccess:
      maybeRetry r.finishTestRetryable(test, target, extraOptions, "", "$ " & given.cmd & '\n' & given.nimout, given.err, givenSpec = given.addr)
    else:
      let isJsTarget = target == targetJS
      var exeFile = changeFileExt(test.name, if isJsTarget: "js" else: ExeExt)
      if not fileExists(exeFile):
        maybeRetry r.finishTestRetryable(test, target, extraOptions, expected.output,
                    "executable not found: " & exeFile, reExeNotFound)
      else:
        let nodejs = if isJsTarget: findNodeJs() else: ""
        if isJsTarget and nodejs == "":
          maybeRetry r.finishTestRetryable(test, target, extraOptions, expected.output, "nodejs binary not in PATH",
                      reExeNotFound)
        else:
          var exeCmd: string
          var args = test.testArgs
          if isJsTarget:
            exeCmd = nodejs
            # see D20210217T215950
            args = @["--unhandled-rejections=strict", exeFile] & args
          else:
            exeCmd = exeFile.dup(normalizeExe)
            if valgrindEnabled and expected.useValgrind != disabled:
              var valgrindOptions = @["--error-exitcode=1"]
              if expected.useValgrind != leaking:
                valgrindOptions.add "--leak-check=yes"
              args = valgrindOptions & exeCmd & args
              exeCmd = "valgrind"
          var (_, buf, exitCode) = execCmdEx2(exeCmd, args, input = expected.input)
          # Treat all failure codes from nodejs as 1. Older versions of nodejs used
          # to return other codes, but for us it is sufficient to know that it's not 0.
          if exitCode != 0: exitCode = 1
          let bufB =
            if expected.sortoutput:
              var buf2 = buf
              buf2.stripLineEnd
              var x = splitLines(buf2)
              sort(x, system.cmp)
              join(x, "\n") & '\n'
            else:
              buf
          if exitCode != expected.exitCode:
            given.err = reExitcodesDiffer
            maybeRetry r.finishTestRetryable(test, target, extraOptions, "exitcode: " & $expected.exitCode,
                              "exitcode: " & $exitCode & "\n\nOutput:\n" &
                              bufB, reExitcodesDiffer)
          elif (expected.outputCheck == ocEqual and not expected.output.equalModuloLastNewline(bufB)) or
              (expected.outputCheck == ocSubstr and expected.output notin bufB):
            given.err = reOutputsDiffer
            maybeRetry r.finishTestRetryable(test, target, extraOptions, expected.output, bufB, reOutputsDiffer)
          maybeRetry compilerOutputTests(test, target, extraOptions, given, expected, r)
  of actionReject:
    # Make sure its the compiler rejecting and not the system (e.g. segfault)
    maybeRetry cmpMsgs(r, expected, given, test, target, extraOptions)
    if given.exitCode != QuitFailure:
      maybeRetry r.finishTestRetryable(test, target, extraOptions, "exitcode: " & $QuitFailure,
                        "exitcode: " & $given.exitCode & "\n\nOutput:\n" &
                        given.nimout, reExitcodesDiffer)



proc changeTarget(extraOptions: string; defaultTarget: TTarget): TTarget =
  result = defaultTarget
  var p = parseopt.initOptParser(extraOptions)

  while true:
    parseopt.next(p)
    case p.kind
    of cmdEnd: break
    of cmdLongOption, cmdShortOption:
      if p.key == "b" or p.key == "backend":
        result = parseEnum[TTarget](p.val.normalize)
        # chooses the last one
    else:
      discard

proc targetHelper(r: var TResults, test: TTest, expected: TSpec, extraOptions: string) =
  for target in expected.targets:
    inc(r.total)
    if target notin gTargets:
      r.finishTest(test, target, extraOptions, "", "", reDisabled)
      inc(r.skipped)
    elif simulate:
      inc count
      echo "testSpec count: ", count, " expected: ", expected
    else:
      let nimcache = nimcacheDir(test.name, test.options, target)
      var testClone = test
      let target = changeTarget(extraOptions, target)
      testSpecHelper(r, testClone, expected, target, extraOptions, nimcache)

proc testSpec(r: var TResults, test: TTest, targets: set[TTarget] = {}) =
  var expected = test.spec
  if expected.parseErrors.len > 0:
    # targetC is a lie, but a parameter is required
    r.finishTest(test, targetC, "", "", expected.parseErrors, reInvalidSpec)
    inc(r.total)
    return

  expected.targets.incl targets
  # still no target specified at all
  if expected.targets == {}:
    expected.targets = {getTestSpecTarget()}
  if test.spec.matrix.len > 0:
    for m in test.spec.matrix:
      targetHelper(r, test, expected, m)
  else:
    targetHelper(r, test, expected, "")

proc testSpecWithNimcache(r: var TResults, test: TTest; nimcache: string) {.used.} =
  for target in test.spec.targets:
    inc(r.total)
    var testClone = test
    testSpecHelper(r, testClone, test.spec, target, "", nimcache)

proc makeTest(test, options: string, cat: Category): TTest =
  result = TTest(
    cat: cat,
    name: test,
    options: options,
    spec: parseSpec(addFileExt(test, ".nim")),
    startTime: epochTime()
  )

proc makeRawTest(test, options: string, cat: Category): TTest {.used.} =
  result = TTest(cat: cat, name: test, options: options,
                spec: initSpec(addFileExt(test, ".nim"))
                )
  result.spec.action = actionCompile
  result.spec.targets = {getTestSpecTarget()}
  result.startTime = epochTime()

# TODO: fix these files
const disabledFilesDefault = @[
  "tableimpl.nim",
  "setimpl.nim",
  "hashcommon.nim",

  # Requires compiling with '--threads:on`
  "sharedlist.nim",
  "sharedtables.nim",

  # Error: undeclared identifier: 'hasThreadSupport'
  "ioselectors_epoll.nim",
  "ioselectors_kqueue.nim",
  "ioselectors_poll.nim",

  # Error: undeclared identifier: 'Timeval'
  "ioselectors_select.nim",
]

when defined(windows):
  const
    # array of modules disabled from compilation test of stdlib.
    disabledFiles = disabledFilesDefault & @["coro.nim"]
else:
  const
    # array of modules disabled from compilation test of stdlib.
    disabledFiles = disabledFilesDefault

include categories

proc loadSkipFrom(name: string): seq[string] =
  result = @[]
  if name.len == 0: return
  # One skip per line, comments start with #
  # used by `nlvm` (at least)
  for line in lines(name):
    let sline = line.strip()
    if sline.len > 0 and not sline.startsWith('#'):
      result.add sline

proc main() =
  azure.init()
  backend.open()
  var optPrintResults = false
  var optFailing = false
  var targetsStr = ""
  var isMainProcess = true
  var skipFrom = ""

  var p = initOptParser()
  p.next()
  while p.kind in {cmdLongOption, cmdShortOption}:
    case p.key.normalize
    of "print": optPrintResults = true
    of "verbose": optVerbose = true
    of "failing": optFailing = true
    of "pedantic": discard # deadcode refs https://github.com/nim-lang/Nim/issues/16731
    of "targets":
      targetsStr = p.val
      gTargets = parseTargets(targetsStr)
      targetsSet = true
    of "nim":
      compilerPrefix = addFileExt(p.val.absolutePath, ExeExt)
    of "directory":
      setCurrentDir(p.val)
    of "colors":
      case p.val:
      of "on":
        useColors = true
      of "off":
        useColors = false
      else:
        quit Usage
    of "batch":
      testamentData0.batchArg = p.val
      if p.val != "_" and p.val.len > 0 and p.val[0] in {'0'..'9'}:
        let s = p.val.split("_")
        doAssert s.len == 2, $(p.val, s)
        testamentData0.testamentBatch = s[0].parseInt
        testamentData0.testamentNumBatch = s[1].parseInt
        doAssert testamentData0.testamentNumBatch > 0
        doAssert testamentData0.testamentBatch >= 0 and testamentData0.testamentBatch < testamentData0.testamentNumBatch
    of "simulate":
      simulate = true
    of "megatest":
      case p.val:
      of "on":
        useMegatest = true
      of "off":
        useMegatest = false
      else:
        quit Usage
    of "valgrind":
      case p.val:
      of "on":
        valgrindEnabled = true
      of "off":
        valgrindEnabled = false
      else:
        quit Usage
    of "backendlogging":
      case p.val:
      of "on":
        backendLogging = true
      of "off":
        backendLogging = false
      else:
        quit Usage
    of "skipfrom":
      skipFrom = p.val
    else:
      quit Usage
    p.next()
  if p.kind != cmdArgument:
    quit Usage
  var action = p.key.normalize
  p.next()
  var r = initResults()
  case action
  of "all":
    #processCategory(r, Category"megatest", p.cmdLineRest, testsDir, runJoinableTests = false)

    var myself = quoteShell(getAppFilename())
    if targetsStr.len > 0:
      myself &= " " & quoteShell("--targets:" & targetsStr)

    myself &= " " & quoteShell("--nim:" & compilerPrefix)
    if testamentData0.batchArg.len > 0:
      myself &= " --batch:" & testamentData0.batchArg

    if skipFrom.len > 0:
      myself &= " " & quoteShell("--skipFrom:" & skipFrom)

    var cats: seq[string] = @[]
    let rest = if p.cmdLineRest.len > 0: " " & p.cmdLineRest else: ""
    for kind, dir in walkDir(testsDir):
      assert testsDir.startsWith(testsDir)
      let cat = dir[testsDir.len .. ^1]
      if kind == pcDir and cat notin ["testdata", "nimcache"]:
        cats.add cat
    if isNimRepoTests():
      cats.add AdditionalCategories
    if useMegatest: cats.add MegaTestCat

    var cmds: seq[string] = @[]
    for cat in cats:
      let runtype = if useMegatest: " pcat " else: " cat "
      cmds.add(myself & runtype & quoteShell(cat) & rest)

    proc progressStatus(idx: int) =
      echo "progress[all]: $1/$2 starting: cat: $3" % [$idx, $cats.len, cats[idx]]

    if simulate:
      skips = loadSkipFrom(skipFrom)
      for i, cati in cats:
        progressStatus(i)
        processCategory(r, Category(cati), p.cmdLineRest, testsDir, runJoinableTests = false)
    else:
      addExitProc azure.finalize
      quit osproc.execProcesses(cmds, {poEchoCmd, poStdErrToStdOut, poUsePath, poParentStreams}, beforeRunEvent = progressStatus)
  of "c", "cat", "category":
    skips = loadSkipFrom(skipFrom)
    var cat = Category(p.key)
    processCategory(r, cat, p.cmdLineRest, testsDir, runJoinableTests = true)
  of "pcat":
    skips = loadSkipFrom(skipFrom)
    # 'pcat' is used for running a category in parallel. Currently the only
    # difference is that we don't want to run joinable tests here as they
    # are covered by the 'megatest' category.
    isMainProcess = false
    var cat = Category(p.key)
    p.next
    processCategory(r, cat, p.cmdLineRest, testsDir, runJoinableTests = false)
  of "p", "pat", "pattern":
    skips = loadSkipFrom(skipFrom)
    let pattern = p.key
    p.next
    processPattern(r, pattern, p.cmdLineRest, simulate)
  of "r", "run":
    let (cat, path) = splitTestFile(p.key)
    processSingleTest(r, cat.Category, p.cmdLineRest, path, gTargets, targetsSet)
  of "html":
    generateHtml(resultsFile, optFailing)
  else:
    quit Usage

  if optPrintResults:
    if action == "html": openDefaultBrowser(resultsFile)
    else: echo r, r.data
  azure.finalize()
  backend.close()
  var failed = r.total - r.passed - r.skipped
  if failed != 0:
    echo "FAILURE! total: ", r.total, " passed: ", r.passed, " skipped: ",
      r.skipped, " failed: ", failed
    quit(QuitFailure)
  if isMainProcess:
    echo "Used ", compilerPrefix, " to run the tests. Use --nim to override."

if paramCount() == 0:
  quit Usage
main()

discard """
joinable: false
"""

#[
joinable: false
because it'd need cleanup up stdout
]#

when defined(case_testfile): # compiled test file for child process
  from posix import exitnow
  proc c_exit2(code: c_int): void {.importc: "_exit", header: "<unistd.h>".}
  import os
  var a = 0
  proc fun(b = 0) =
    a.inc
    if a mod 10000000 == 0: # prevents optimizing it away
      echo a
    fun(b+1)

  proc main() =
    let args = commandLineParams()
    echo (msg: "child binary", pid: getCurrentProcessId())
    let arg = args[0]
    echo (arg: arg)
    case arg
    of "exit_0":
      if true: quit(0)
    of "exitnow_139":
      if true: exitnow(139)
    of "c_exit2_139":
      if true: c_exit2(139)
    of "quit_139":
      # `exitStatusLikeShell` doesn't distinguish between a process that
      # exit(139) and a process that gets killed with `SIGSEGV` because
      # 139 = 11 + 128 = SIGSEGV + 128.
      # However, as #10249 shows, this leads to bad debugging experience
      # when a child process dies with SIGSEGV, leaving no trace of why it
      # failed. The shell (and lldb debugger) solves that by inserting a
      # helpful msg: `segmentation fault` when it detects a signal killed
      # the child.
      # todo: expose an API that will show more diagnostic, returning
      # (exitCode, signal) instead of just `shellExitCode`.
      if true: quit(139)
    of "exit_recursion": # stack overflow by infinite recursion
      fun()
      echo a
    of "exit_array": # bad array access
      echo args[1]
  main()

elif defined(case_testfile2):
  import strutils
  let x = stdin.readLine()
  echo x.parseInt + 5

elif defined(case_testfile3):
  echo "start ta_out"
  stdout.writeLine("to stdout")
  stdout.flushFile()
  stdout.writeLine("to stdout")
  stdout.flushFile()

  stderr.writeLine("to stderr")
  stderr.flushFile()
  stderr.writeLine("to stderr")
  stderr.flushFile()

  stdout.writeLine("to stdout")
  stdout.flushFile()
  stdout.writeLine("to stdout")
  stdout.flushFile()
  echo "end ta_out"

elif defined(case_testfile4):
  import system # we could remove that
  quit(QuitFailure)

else: # main driver
  import stdtest/[specialpaths, unittest_light]
  import os, osproc, strutils
  const nim = getCurrentCompilerExe()
  const sourcePath = currentSourcePath()
  let dir = getCurrentDir() / "tests" / "osproc"

  template deferScoped(cleanup, body) =
    # pending https://github.com/nim-lang/RFCs/issues/236#issuecomment-646855314
    # xxx move to std/sugar or (preferably) some low level module
    try: body
    finally: cleanup

  # we're testing `execShellCmd` so don't rely on it to compile test file
  # note: this should be exported in posix.nim
  proc c_system(cmd: cstring): cint {.importc: "system", header: "<stdlib.h>".}

  proc compileNimProg(opt: string, name: string): string =
    result = buildDir / name.addFileExt(ExeExt)
    let cmd = "$# c -o:$# --hints:off $# $#" % [nim.quoteShell, result.quoteShell, opt, sourcePath.quoteShell]
    doAssert c_system(cmd) == 0, $cmd
    doAssert result.fileExists

  block execShellCmdTest:
    let output = compileNimProg("-d:release -d:case_testfile", "D20190111T024543")

    ## use it
    template runTest(arg: string, expected: int) =
      echo (arg2: arg, expected2: expected)
      assertEquals execShellCmd(output & " " & arg), expected

    runTest("exit_0", 0)
    runTest("exitnow_139", 139)
    runTest("c_exit2_139", 139)
    runTest("quit_139", 139)

  block execProcessTest:
    let dir = sourcePath.parentDir
    let (_, err) = execCmdEx(nim & " c " & quoteShell(dir / "osproctest.nim"))
    doAssert err == 0
    let exePath = dir / addFileExt("osproctest", ExeExt)
    let outStr1 = execProcess(exePath, workingDir = dir, args = ["foo",
        "b A r"], options = {})
    doAssert outStr1 == dir & "\nfoo\nb A r\n"

    const testDir = "t e st"
    createDir(testDir)
    doAssert dirExists(testDir)
    let outStr2 = execProcess(exePath, workingDir = testDir, args = ["x yz"],
        options = {})
    doAssert outStr2 == absolutePath(testDir) & "\nx yz\n"

    removeDir(testDir)
    try:
      removeFile(exePath)
    except OSError:
      discard

  import std/streams

  block: # test for startProcess (more tests needed)
    # bugfix: windows stdin.close was a noop and led to blocking reads
    proc startProcessTest(command: string, options: set[ProcessOption] = {
                    poStdErrToStdOut, poUsePath}, input = ""): tuple[
                    output: TaintedString,
                    exitCode: int] {.tags:
                    [ExecIOEffect, ReadIOEffect, RootEffect], gcsafe.} =
      var p = startProcess(command, options = options + {poEvalCommand})
      var outp = outputStream(p)
      if input.len > 0: inputStream(p).write(input)
      close inputStream(p)
      result = (TaintedString"", -1)
      var line = newStringOfCap(120).TaintedString
      while true:
        if outp.readLine(line):
          result[0].string.add(line.string)
          result[0].string.add("\n")
        else:
          result[1] = peekExitCode(p)
          if result[1] != -1: break
      close(p)

    var result = startProcessTest("nim r --hints:off -", options = {}, input = "echo 3*4")
    doAssert result == ("12\n", 0)

  block: # startProcess stdin (replaces old test `tstdin` + `ta_in`)
    let output = compileNimProg("-d:case_testfile2", "D20200626T215919")
    var p = startProcess(output, dir) # dir not needed though
    p.inputStream.write("5\n")
    p.inputStream.flush()
    var line = ""
    var s: seq[string]
    while p.outputStream.readLine(line.TaintedString):
      s.add line
    doAssert s == @["10"]

  block: # startProcess stdout (replaces old test `tstderr` + `ta_out`)
    let output = compileNimProg("-d:case_testfile3", "D20200626T221233")
    var p = startProcess(output, dir, options={})
    deferScoped: p.close()
    do:
      var x = newStringOfCap(120)
      var serr, sout: seq[string]
      while p.errorStream.readLine(x.TaintedString): serr.add x
      while p.outputStream.readLine(x.TaintedString): sout.add x
      doAssert serr == @["to stderr", "to stderr"]
      doAssert sout == @["start ta_out", "to stdout", "to stdout", "to stdout", "to stdout", "end ta_out"]

  block: # startProcess exit code (replaces old test `texitcode` + `tafalse`)
    let output = compileNimProg("-d:case_testfile4", "D20200626T224758")
    var p = startProcess(output, dir)
    doAssert waitForExit(p) == QuitFailure
    p = startProcess(output, dir)
    var running = true
    while running:
      # xxx: avoid busyloop?
      running = running(p)
    doAssert waitForExit(p) == QuitFailure

    # make sure that first call to running() after process exit returns false
    p = startProcess(output, dir)
    for j in 0..<30: # refs #13449
      os.sleep(50)
      if not running(p): break
    doAssert not running(p)
    doAssert waitForExit(p) == QuitFailure # avoid zombies

  import std/strtabs
  block execProcessTest:
    var result = execCmdEx("nim r --hints:off -", options = {}, input = "echo 3*4")
    stripLineEnd(result[0])
    doAssert result == ("12", 0)
    doAssert execCmdEx("ls --nonexistant").exitCode != 0
    when false:
      # bug: on windows, this raises; on posix, passes
      doAssert execCmdEx("nonexistant").exitCode != 0
    when defined(posix):
      doAssert execCmdEx("echo $FO", env = newStringTable({"FO": "B"})) == ("B\n", 0)
      doAssert execCmdEx("echo $PWD", workingDir = "/") == ("/\n", 0)

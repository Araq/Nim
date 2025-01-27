#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements an advanced facility for executing OS processes
## and process communication.
##
## **See also:**
## * `os module <os.html>`_
## * `streams module <streams.html>`_
## * `memfiles module <memfiles.html>`_

include "system/inclrtl"

import
  std/[strutils, os, strtabs, streams, cpuinfo, streamwrapper,
  private/since]

export quoteShell, quoteShellWindows, quoteShellPosix

when defined(windows):
  import std/winlean
else:
  import std/posix

when defined(linux) and defined(useClone):
  import std/linux

when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions]
  when defined(windows):
    import std/widestrs


type
  ProcessOption* = enum ## Options that can be passed to `startProcess proc
                        ## <#startProcess,string,string,openArray[string],StringTableRef,set[ProcessOption]>`_.
    poEchoCmd,          ## Echo the command before execution.
    poUsePath,          ## Asks system to search for executable using PATH environment
                        ## variable.
                        ## On Windows, this is the default.
    poEvalCommand,      ## Pass `command` directly to the shell, without quoting.
                        ## Use it only if `command` comes from trusted source.
    poStdErrToStdOut,   ## Merge stdout and stderr to the stdout stream.
    poParentStreams,    ## Use the parent's streams.
    poInteractive,      ## Optimize the buffer handling for responsiveness for
                        ## UI applications. Currently this only affects
                        ## Windows: Named pipes are used so that you can peek
                        ## at the process' output streams.
    poDaemon            ## Windows: The program creates no Window.
                        ## Unix: Start the program as a daemon. This is still
                        ## work in progress!

  ProcessObj = object of RootObj
    when defined(windows):
      fProcessHandle: Handle
      fThreadHandle: Handle
      inHandle, outHandle, errHandle: FileHandle
      id: Handle
    else:
      inHandle, outHandle, errHandle: FileHandle
      id: Pid
    inStream, outStream, errStream: owned(Stream)
    exitStatus: cint
    exitFlag: bool
    options: set[ProcessOption]

  Process* = ref ProcessObj ## Represents an operating system process.


proc execProcess*(command: string, workingDir: string = "",
    args: openArray[string] = [], env: StringTableRef = nil,
    options: set[ProcessOption] = {poStdErrToStdOut, poUsePath, poEvalCommand}):
  string {.rtl, extern: "nosp$1", raises: [OSError, IOError],
                  tags: [ExecIOEffect, ReadIOEffect, RootEffect].}
  ## A convenience procedure that executes ``command`` with ``startProcess``
  ## and returns its output as a string.
  ##
  ## .. warning:: This function uses `poEvalCommand` by default for backwards
  ##   compatibility. Make sure to pass options explicitly.
  ##
  ## See also:
  ## * `startProcess proc
  ##   <#startProcess,string,string,openArray[string],StringTableRef,set[ProcessOption]>`_
  ## * `execProcesses proc <#execProcesses,openArray[string],proc(int),proc(int,Process)>`_
  ## * `execCmd proc <#execCmd,string>`_
  ##
  ## Example:
  ##   ```Nim
  ##   let outp = execProcess("nim", args=["c", "-r", "mytestfile.nim"], options={poUsePath})
  ##   let outp_shell = execProcess("nim c -r mytestfile.nim")
  ##   # Note: outp may have an interleave of text from the nim compile
  ##   # and any output from mytestfile when it runs
  ##   ```

proc execCmd*(command: string): int {.rtl, extern: "nosp$1",
    tags: [ExecIOEffect, ReadIOEffect, RootEffect].}
  ## Executes ``command`` and returns its error code.
  ##
  ## Standard input, output, error streams are inherited from the calling process.
  ## This operation is also often called `system`:idx:.
  ##
  ## See also:
  ## * `execCmdEx proc <#execCmdEx,string,set[ProcessOption],StringTableRef,string,string>`_
  ## * `startProcess proc
  ##   <#startProcess,string,string,openArray[string],StringTableRef,set[ProcessOption]>`_
  ## * `execProcess proc
  ##   <#execProcess,string,string,openArray[string],StringTableRef,set[ProcessOption]>`_
  ##
  ## Example:
  ##   ```Nim
  ##   let errC = execCmd("nim c -r mytestfile.nim")
  ##   ```

proc startProcess*(command: string, workingDir: string = "",
    args: openArray[string] = [], env: StringTableRef = nil,
    options: set[ProcessOption] = {poStdErrToStdOut}):
  owned(Process) {.rtl, extern: "nosp$1", raises: [OSError, IOError],
                   tags: [ExecIOEffect, ReadEnvEffect, RootEffect].}
  ## Starts a process. `Command` is the executable file, `workingDir` is the
  ## process's working directory. If ``workingDir == ""`` the current directory
  ## is used (default). `args` are the command line arguments that are passed to the
  ## process. On many operating systems, the first command line argument is the
  ## name of the executable. `args` should *not* contain this argument!
  ## `env` is the environment that will be passed to the process.
  ## If ``env == nil`` (default) the environment is inherited of
  ## the parent process. `options` are additional flags that may be passed
  ## to `startProcess`. See the documentation of `ProcessOption<#ProcessOption>`_
  ## for the meaning of these flags.
  ##
  ## You need to `close <#close,Process>`_ the process when done.
  ##
  ## Note that you can't pass any `args` if you use the option
  ## ``poEvalCommand``, which invokes the system shell to run the specified
  ## `command`. In this situation you have to concatenate manually the contents
  ## of `args` to `command` carefully escaping/quoting any special characters,
  ## since it will be passed *as is* to the system shell. Each system/shell may
  ## feature different escaping rules, so try to avoid this kind of shell
  ## invocation if possible as it leads to non portable software.
  ##
  ## Return value: The newly created process object. Nil is never returned,
  ## but ``OSError`` is raised in case of an error.
  ##
  ## See also:
  ## * `execProcesses proc <#execProcesses,openArray[string],proc(int),proc(int,Process)>`_
  ## * `execProcess proc
  ##   <#execProcess,string,string,openArray[string],StringTableRef,set[ProcessOption]>`_
  ## * `execCmd proc <#execCmd,string>`_

proc close*(p: Process) {.rtl, extern: "nosp$1", raises: [IOError, OSError], tags: [WriteIOEffect].}
  ## When the process has finished executing, cleanup related handles.
  ##
  ## .. warning:: If the process has not finished executing, this will forcibly
  ##   terminate the process. Doing so may result in zombie processes and
  ##   `pty leaks <https://stackoverflow.com/questions/27021641/how-to-fix-request-failed-on-channel-0>`_.

proc suspend*(p: Process) {.rtl, extern: "nosp$1", tags: [].}
  ## Suspends the process `p`.
  ##
  ## See also:
  ## * `resume proc <#resume,Process>`_
  ## * `terminate proc <#terminate,Process>`_
  ## * `kill proc <#kill,Process>`_


proc resume*(p: Process) {.rtl, extern: "nosp$1", tags: [].}
  ## Resumes the process `p`.
  ##
  ## See also:
  ## * `suspend proc <#suspend,Process>`_
  ## * `terminate proc <#terminate,Process>`_
  ## * `kill proc <#kill,Process>`_

proc terminate*(p: Process) {.rtl, extern: "nosp$1", tags: [].}
  ## Stop the process `p`.
  ##
  ## On Posix OSes the procedure sends ``SIGTERM`` to the process.
  ## On Windows the Win32 API function ``TerminateProcess()``
  ## is called to stop the process.
  ##
  ## See also:
  ## * `suspend proc <#suspend,Process>`_
  ## * `resume proc <#resume,Process>`_
  ## * `kill proc <#kill,Process>`_
  ## * `posix_utils.sendSignal(pid: Pid, signal: int) <posix_utils.html#sendSignal,Pid,int>`_

proc kill*(p: Process) {.rtl, extern: "nosp$1", tags: [].}
  ## Kill the process `p`.
  ##
  ## On Posix OSes the procedure sends ``SIGKILL`` to the process.
  ## On Windows ``kill`` is simply an alias for `terminate() <#terminate,Process>`_.
  ##
  ## See also:
  ## * `suspend proc <#suspend,Process>`_
  ## * `resume proc <#resume,Process>`_
  ## * `terminate proc <#terminate,Process>`_
  ## * `posix_utils.sendSignal(pid: Pid, signal: int) <posix_utils.html#sendSignal,Pid,int>`_

proc running*(p: Process): bool {.rtl, extern: "nosp$1", raises: [OSError], tags: [].}
  ## Returns true if the process `p` is still running. Returns immediately.

proc processID*(p: Process): int {.rtl, extern: "nosp$1".} =
  ## Returns `p`'s process ID.
  ##
  ## See also:
  ## * `os.getCurrentProcessId proc <os.html#getCurrentProcessId>`_
  return p.id

proc waitForExit*(p: Process, timeout: int = -1): int {.rtl,
    extern: "nosp$1", raises: [OSError, ValueError], tags: [TimeEffect].}
  ## Waits for the process to finish and returns `p`'s error code.
  ##
  ## .. warning:: Be careful when using `waitForExit` for processes created without
  ##   `poParentStreams` because they may fill output buffers, causing deadlock.
  ##
  ## On posix, if the process has exited because of a signal, 128 + signal
  ## number will be returned.
  ##
  ## .. warning:: When working with `timeout` parameters, remember that the value is 
  ##   typically expressed in milliseconds, and ensure that the correct unit of time
  ##   is used to avoid unexpected behavior.

proc peekExitCode*(p: Process): int {.rtl, extern: "nosp$1", raises: [OSError], tags: [].}
  ## Return `-1` if the process is still running. Otherwise the process' exit code.
  ##
  ## On posix, if the process has exited because of a signal, 128 + signal
  ## number will be returned.

proc inputStream*(p: Process): Stream {.rtl, extern: "nosp$1", tags: [].}
  ## Returns ``p``'s input stream for writing to.
  ##
  ## .. warning:: The returned `Stream` should not be closed manually as it
  ##   is closed when closing the Process ``p``.
  ##
  ## See also:
  ## * `outputStream proc <#outputStream,Process>`_
  ## * `errorStream proc <#errorStream,Process>`_

proc outputStream*(p: Process): Stream {.rtl, extern: "nosp$1", raises: [IOError, OSError], tags: [].}
  ## Returns ``p``'s output stream for reading from.
  ##
  ## You cannot perform peek/write/setOption operations to this stream.
  ## Use `peekableOutputStream proc <#peekableOutputStream,Process>`_
  ## if you need to peek stream.
  ##
  ## .. warning:: The returned `Stream` should not be closed manually as it
  ##   is closed when closing the Process ``p``.
  ##
  ## See also:
  ## * `inputStream proc <#inputStream,Process>`_
  ## * `errorStream proc <#errorStream,Process>`_

proc errorStream*(p: Process): Stream {.rtl, extern: "nosp$1", tags: [].}
  ## Returns ``p``'s error stream for reading from.
  ##
  ## You cannot perform peek/write/setOption operations to this stream.
  ## Use `peekableErrorStream proc <#peekableErrorStream,Process>`_
  ## if you need to peek stream.
  ##
  ## .. warning:: The returned `Stream` should not be closed manually as it
  ##   is closed when closing the Process ``p``.
  ##
  ## See also:
  ## * `inputStream proc <#inputStream,Process>`_
  ## * `outputStream proc <#outputStream,Process>`_

proc peekableOutputStream*(p: Process): Stream {.rtl, extern: "nosp$1", tags: [], since: (1, 3).}
  ## Returns ``p``'s output stream for reading from.
  ##
  ## You can peek returned stream.
  ##
  ## .. warning:: The returned `Stream` should not be closed manually as it
  ##   is closed when closing the Process ``p``.
  ##
  ## See also:
  ## * `outputStream proc <#outputStream,Process>`_
  ## * `peekableErrorStream proc <#peekableErrorStream,Process>`_

proc peekableErrorStream*(p: Process): Stream {.rtl, extern: "nosp$1", tags: [], since: (1, 3).}
  ## Returns ``p``'s error stream for reading from.
  ##
  ## You can run peek operation to returned stream.
  ##
  ## .. warning:: The returned `Stream` should not be closed manually as it
  ##   is closed when closing the Process ``p``.
  ##
  ## See also:
  ## * `errorStream proc <#errorStream,Process>`_
  ## * `peekableOutputStream proc <#peekableOutputStream,Process>`_

proc inputHandle*(p: Process): FileHandle {.rtl, raises: [], extern: "nosp$1",
  tags: [].} =
  ## Returns ``p``'s input file handle for writing to.
  ##
  ## .. warning:: The returned `FileHandle` should not be closed manually as
  ##   it is closed when closing the Process ``p``.
  ##
  ## See also:
  ## * `outputHandle proc <#outputHandle,Process>`_
  ## * `errorHandle proc <#errorHandle,Process>`_
  result = p.inHandle

proc outputHandle*(p: Process): FileHandle {.rtl, extern: "nosp$1",
    raises: [], tags: [].} =
  ## Returns ``p``'s output file handle for reading from.
  ##
  ## .. warning:: The returned `FileHandle` should not be closed manually as
  ##   it is closed when closing the Process ``p``.
  ##
  ## See also:
  ## * `inputHandle proc <#inputHandle,Process>`_
  ## * `errorHandle proc <#errorHandle,Process>`_
  result = p.outHandle

proc errorHandle*(p: Process): FileHandle {.rtl, extern: "nosp$1",
    raises: [], tags: [].} =
  ## Returns ``p``'s error file handle for reading from.
  ##
  ## .. warning:: The returned `FileHandle` should not be closed manually as
  ##   it is closed when closing the Process ``p``.
  ##
  ## See also:
  ## * `inputHandle proc <#inputHandle,Process>`_
  ## * `outputHandle proc <#outputHandle,Process>`_
  result = p.errHandle

proc countProcessors*(): int {.rtl, extern: "nosp$1", raises: [].} =
  ## Returns the number of the processors/cores the machine has.
  ## Returns 0 if it cannot be detected.
  ## It is implemented just calling `cpuinfo.countProcessors`.
  result = cpuinfo.countProcessors()

when not defined(nimHasEffectsOf):
  {.pragma: effectsOf.}

proc execProcesses*(cmds: openArray[string],
    options = {poStdErrToStdOut, poParentStreams}, n = countProcessors(),
    beforeRunEvent: proc(idx: int) = nil,
    afterRunEvent: proc(idx: int, p: Process) = nil):
  int {.rtl, extern: "nosp$1",
        raises: [ValueError, OSError, IOError],
        tags: [ExecIOEffect, TimeEffect, ReadEnvEffect, RootEffect],
        effectsOf: [beforeRunEvent, afterRunEvent].} =
  ## Executes the commands `cmds` in parallel.
  ## Creates `n` processes that execute in parallel.
  ##
  ## The highest (absolute) return value of all processes is returned.
  ## Runs `beforeRunEvent` before running each command.
  result = 0
  assert n > 0
  if n > 1:
    var i = 0
    var q = newSeq[Process](n)
    var idxs = newSeq[int](n) # map process index to cmds index

    when defined(windows):
      var w: WOHandleArray
      var m = min(min(n, MAXIMUM_WAIT_OBJECTS), cmds.len)
      var wcount = m
    else:
      var m = min(n, cmds.len)

    while i < m:
      if beforeRunEvent != nil:
        beforeRunEvent(i)
      q[i] = startProcess(cmds[i], options = options + {poEvalCommand})
      idxs[i] = i
      when defined(windows):
        w[i] = q[i].fProcessHandle
      inc(i)

    var ecount = len(cmds)
    while ecount > 0:
      var rexit = -1
      when defined(windows):
        # waiting for all children, get result if any child exits
        var ret = waitForMultipleObjects(int32(wcount), addr(w), 0'i32,
                                         INFINITE)
        if ret == WAIT_TIMEOUT:
          # must not be happen
          discard
        elif ret == WAIT_FAILED:
          raiseOSError(osLastError())
        else:
          var status: int32
          for r in 0..m-1:
            if not isNil(q[r]) and q[r].fProcessHandle == w[ret]:
              discard getExitCodeProcess(q[r].fProcessHandle, status)
              q[r].exitFlag = true
              q[r].exitStatus = status
              rexit = r
              break
      else:
        var status: cint = 1
        # waiting for all children, get result if any child exits
        let res = waitpid(-1, status, 0)
        if res > 0:
          for r in 0..m-1:
            if not isNil(q[r]) and q[r].id == res:
              if WIFEXITED(status) or WIFSIGNALED(status):
                q[r].exitFlag = true
                q[r].exitStatus = status
                rexit = r
                break
        else:
          let err = osLastError()
          if err == OSErrorCode(ECHILD):
            # some child exits, we need to check our childs exit codes
            for r in 0..m-1:
              if (not isNil(q[r])) and (not running(q[r])):
                q[r].exitFlag = true
                q[r].exitStatus = status
                rexit = r
                break
          elif err == OSErrorCode(EINTR):
            # signal interrupted our syscall, lets repeat it
            continue
          else:
            # all other errors are exceptions
            raiseOSError(err)

      if rexit >= 0:
        when defined(windows):
          let processHandle = q[rexit].fProcessHandle
        result = max(result, abs(q[rexit].peekExitCode()))
        if afterRunEvent != nil: afterRunEvent(idxs[rexit], q[rexit])
        close(q[rexit])
        if i < len(cmds):
          if beforeRunEvent != nil: beforeRunEvent(i)
          q[rexit] = startProcess(cmds[i],
                                  options = options + {poEvalCommand})
          idxs[rexit] = i
          when defined(windows):
            w[rexit] = q[rexit].fProcessHandle
          inc(i)
        else:
          when defined(windows):
            for k in 0..wcount - 1:
              if w[k] == processHandle:
                w[k] = w[wcount - 1]
                w[wcount - 1] = 0
                dec(wcount)
                break
          q[rexit] = nil
        dec(ecount)
  else:
    for i in 0..high(cmds):
      if beforeRunEvent != nil:
        beforeRunEvent(i)
      var p = startProcess(cmds[i], options = options + {poEvalCommand})
      result = max(abs(waitForExit(p)), result)
      if afterRunEvent != nil: afterRunEvent(i, p)
      close(p)

iterator lines*(p: Process, keepNewLines = false): string {.since: (1, 3), raises: [OSError, IOError, ValueError], tags: [ReadIOEffect, TimeEffect].} =
  ## Convenience iterator for working with `startProcess` to read data from a
  ## background process.
  ##
  ## See also:
  ## * `readLines proc <#readLines,Process>`_
  ##
  ## Example:
  ##   ```Nim
  ##   const opts = {poUsePath, poDaemon, poStdErrToStdOut}
  ##   var ps: seq[Process]
  ##   for prog in ["a", "b"]: # run 2 progs in parallel
  ##     ps.add startProcess("nim", "", ["r", prog], nil, opts)
  ##   for p in ps:
  ##     var i = 0
  ##     for line in p.lines:
  ##       echo line
  ##       i.inc
  ##       if i > 100: break
  ##     p.close
  ##   ```
  var outp = p.outputStream
  var line = newStringOfCap(120)
  while outp.readLine(line):
    if keepNewLines:
      line.add("\n")
    yield line
  discard waitForExit(p)

proc readLines*(p: Process): (seq[string], int) {.since: (1, 3),
    raises: [OSError, IOError, ValueError], tags: [ReadIOEffect, TimeEffect].} =
  ## Convenience function for working with `startProcess` to read data from a
  ## background process.
  ##
  ## See also:
  ## * `lines iterator <#lines.i,Process>`_
  ##
  ## Example:
  ##   ```Nim
  ##   const opts = {poUsePath, poDaemon, poStdErrToStdOut}
  ##   var ps: seq[Process]
  ##   for prog in ["a", "b"]: # run 2 progs in parallel
  ##     ps.add startProcess("nim", "", ["r", prog], nil, opts)
  ##   for p in ps:
  ##     let (lines, exCode) = p.readLines
  ##     if exCode != 0:
  ##       for line in lines: echo line
  ##     p.close
  ##   ```
  result = (@[], 0)
  for line in p.lines: result[0].add(line)
  result[1] = p.peekExitCode

when not defined(useNimRtl):
  proc execProcess(command: string, workingDir: string = "",
      args: openArray[string] = [], env: StringTableRef = nil,
      options: set[ProcessOption] = {poStdErrToStdOut, poUsePath,
          poEvalCommand}):
    string =

    var p = startProcess(command, workingDir = workingDir, args = args,
        env = env, options = options)
    var outp = outputStream(p)
    result = ""
    var line = newStringOfCap(120)
    # consider `p.lines(keepNewLines=true)` to circumvent `running` busy-wait
    while true:
      # FIXME: converts CR-LF to LF.
      if outp.readLine(line):
        result.add(line)
        result.add("\n")
      elif not running(p): break
    close(p)

template streamAccess(p) =
  assert poParentStreams notin p.options, "API usage error: stream access not allowed when you use poParentStreams"

when defined(windows) and not defined(useNimRtl):
  # We need to implement a handle stream for Windows:
  type
    FileHandleStream = ref object of StreamObj
      handle: Handle
      atTheEnd: bool

  proc closeHandleCheck(handle: Handle) {.inline.} =
    if handle.closeHandle() == 0:
      raiseOSError(osLastError())

  proc fileClose[T: Handle | FileHandle](h: var T) {.inline.} =
    if h > 4:
      closeHandleCheck(h)
      h = INVALID_HANDLE_VALUE.T

  proc hsClose(s: Stream) =
    FileHandleStream(s).handle.fileClose()

  proc hsAtEnd(s: Stream): bool = return FileHandleStream(s).atTheEnd

  proc hsReadData(s: Stream, buffer: pointer, bufLen: int): int =
    var s = FileHandleStream(s)
    if s.atTheEnd: return 0
    var br: int32
    var a = winlean.readFile(s.handle, buffer, bufLen.cint, addr br, nil)
    # TRUE and zero bytes returned (EOF).
    # TRUE and n (>0) bytes returned (good data).
    # FALSE and bytes returned undefined (system error).
    if a == 0 and br != 0: raiseOSError(osLastError())
    s.atTheEnd = br == 0 #< bufLen
    result = br

  proc hsWriteData(s: Stream, buffer: pointer, bufLen: int) =
    var s = FileHandleStream(s)
    var bytesWritten: int32
    var a = winlean.writeFile(s.handle, buffer, bufLen.cint,
                              addr bytesWritten, nil)
    if a == 0: raiseOSError(osLastError())

  proc newFileHandleStream(handle: Handle): owned FileHandleStream =
    result = FileHandleStream(handle: handle, closeImpl: hsClose, atEndImpl: hsAtEnd,
      readDataImpl: hsReadData, writeDataImpl: hsWriteData)

  proc buildCommandLine(a: string, args: openArray[string]): string =
    result = quoteShell(a)
    for i in 0..high(args):
      result.add(' ')
      result.add(quoteShell(args[i]))

  proc buildEnv(env: StringTableRef): tuple[str: cstring, len: int] =
    var L = 0
    for key, val in pairs(env): inc(L, key.len + val.len + 2)
    var str = cast[cstring](alloc0(L+2))
    L = 0
    for key, val in pairs(env):
      var x = key & "=" & val
      copyMem(addr(str[L]), cstring(x), x.len+1) # copy \0
      inc(L, x.len+1)
    (str, L)

  #proc open_osfhandle(osh: Handle, mode: int): int {.
  #  importc: "_open_osfhandle", header: "<fcntl.h>".}

  #var
  #  O_WRONLY {.importc: "_O_WRONLY", header: "<fcntl.h>".}: int
  #  O_RDONLY {.importc: "_O_RDONLY", header: "<fcntl.h>".}: int
  proc myDup(h: Handle; inherit: WINBOOL = 1): Handle =
    let thisProc = getCurrentProcess()
    if duplicateHandle(thisProc, h, thisProc, addr result, 0, inherit,
                       DUPLICATE_SAME_ACCESS) == 0:
      raiseOSError(osLastError())

  proc createAllPipeHandles(si: var STARTUPINFO;
                            stdin, stdout, stderr: var Handle; hash: int) =
    var sa: SECURITY_ATTRIBUTES
    sa.nLength = sizeof(SECURITY_ATTRIBUTES).cint
    sa.lpSecurityDescriptor = nil
    sa.bInheritHandle = 1
    let pipeOutName = newWideCString(r"\\.\pipe\stdout" & $hash)
    let pipeInName = newWideCString(r"\\.\pipe\stdin" & $hash)
    let pipeOut = createNamedPipe(pipeOutName,
      dwOpenMode = PIPE_ACCESS_INBOUND or FILE_FLAG_WRITE_THROUGH,
      dwPipeMode = PIPE_NOWAIT,
      nMaxInstances = 1,
      nOutBufferSize = 1024, nInBufferSize = 1024,
      nDefaultTimeOut = 0, addr sa)
    if pipeOut == INVALID_HANDLE_VALUE:
      raiseOSError(osLastError())
    let pipeIn = createNamedPipe(pipeInName,
      dwOpenMode = PIPE_ACCESS_OUTBOUND or FILE_FLAG_WRITE_THROUGH,
      dwPipeMode = PIPE_NOWAIT,
      nMaxInstances = 1,
      nOutBufferSize = 1024, nInBufferSize = 1024,
      nDefaultTimeOut = 0, addr sa)
    if pipeIn == INVALID_HANDLE_VALUE:
      raiseOSError(osLastError())

    si.hStdOutput = createFileW(pipeOutName,
        FILE_WRITE_DATA or SYNCHRONIZE, 0, addr sa,
        OPEN_EXISTING, # very important flag!
      FILE_ATTRIBUTE_NORMAL,
      0 # no template file for OPEN_EXISTING
    )
    if si.hStdOutput == INVALID_HANDLE_VALUE:
      raiseOSError(osLastError())
    si.hStdError = myDup(si.hStdOutput)
    si.hStdInput = createFileW(pipeInName,
        FILE_READ_DATA or SYNCHRONIZE, 0, addr sa,
        OPEN_EXISTING, # very important flag!
      FILE_ATTRIBUTE_NORMAL,
      0 # no template file for OPEN_EXISTING
    )
    if si.hStdInput == INVALID_HANDLE_VALUE:
      raiseOSError(osLastError())

    stdin = myDup(pipeIn, 0)
    stdout = myDup(pipeOut, 0)
    closeHandleCheck(pipeIn)
    closeHandleCheck(pipeOut)
    stderr = stdout

  proc createPipeHandles(rdHandle, wrHandle: var Handle) =
    var sa: SECURITY_ATTRIBUTES
    sa.nLength = sizeof(SECURITY_ATTRIBUTES).cint
    sa.lpSecurityDescriptor = nil
    sa.bInheritHandle = 1
    if createPipe(rdHandle, wrHandle, sa, 0) == 0'i32:
      raiseOSError(osLastError())

  proc startProcess(command: string, workingDir: string = "",
      args: openArray[string] = [], env: StringTableRef = nil,
      options: set[ProcessOption] = {poStdErrToStdOut}):
    owned Process =
    var
      si: STARTUPINFO
      procInfo: PROCESS_INFORMATION
      success: int
      hi, ho, he: Handle
    new(result)
    result.options = options
    result.exitFlag = true
    si.cb = sizeof(si).cint
    if poParentStreams notin options:
      si.dwFlags = STARTF_USESTDHANDLES # STARTF_USESHOWWINDOW or
      if poInteractive notin options:
        createPipeHandles(si.hStdInput, hi)
        createPipeHandles(ho, si.hStdOutput)
        if poStdErrToStdOut in options:
          si.hStdError = si.hStdOutput
          he = ho
        else:
          createPipeHandles(he, si.hStdError)
          if setHandleInformation(he, DWORD(1), DWORD(0)) == 0'i32:
            raiseOSError(osLastError())
        if setHandleInformation(hi, DWORD(1), DWORD(0)) == 0'i32:
          raiseOSError(osLastError())
        if setHandleInformation(ho, DWORD(1), DWORD(0)) == 0'i32:
          raiseOSError(osLastError())
      else:
        createAllPipeHandles(si, hi, ho, he, cast[int](result))
      result.inHandle = FileHandle(hi)
      result.outHandle = FileHandle(ho)
      result.errHandle = FileHandle(he)
    else:
      si.hStdError = getStdHandle(STD_ERROR_HANDLE)
      si.hStdInput = getStdHandle(STD_INPUT_HANDLE)
      si.hStdOutput = getStdHandle(STD_OUTPUT_HANDLE)
      result.inHandle = FileHandle(si.hStdInput)
      result.outHandle = FileHandle(si.hStdOutput)
      result.errHandle = FileHandle(si.hStdError)

    var cmdl: cstring
    var cmdRoot: string
    if poEvalCommand in options:
      cmdl = command
      assert args.len == 0
    else:
      cmdRoot = buildCommandLine(command, args)
      cmdl = cstring(cmdRoot)
    var wd: cstring = nil
    var e = (str: nil.cstring, len: -1)
    if len(workingDir) > 0: wd = workingDir
    if env != nil: e = buildEnv(env)
    if poEchoCmd in options: echo($cmdl)
    var tmp = newWideCString(cmdl)
    var ee =
      if e.str.isNil: newWideCString(cstring(nil))
      else: newWideCString(e.str, e.len)
    var wwd = newWideCString(wd)
    var flags = NORMAL_PRIORITY_CLASS or CREATE_UNICODE_ENVIRONMENT
    if poDaemon in options: flags = flags or CREATE_NO_WINDOW
    success = winlean.createProcessW(nil, tmp, nil, nil, 1, flags,
      ee, wwd, si, procInfo)
    let lastError = osLastError()

    if poParentStreams notin options:
      fileClose(si.hStdInput)
      fileClose(si.hStdOutput)
      if poStdErrToStdOut notin options:
        fileClose(si.hStdError)

    if e.str != nil: dealloc(e.str)
    if success == 0:
      if poInteractive in result.options: close(result)
      const errInvalidParameter = 87.int
      const errFileNotFound = 2.int
      case lastError.int
      of errInvalidParameter, errFileNotFound:
        raiseOSError(lastError,
              "Requested command not found: '" & command & "'. OS error:")
      else:
        raiseOSError(lastError, command)
    result.fProcessHandle = procInfo.hProcess
    result.fThreadHandle = procInfo.hThread
    result.id = procInfo.dwProcessId
    result.exitFlag = false

  proc closeThreadAndProcessHandle(p: Process) =
    if p.fThreadHandle != 0:
      closeHandleCheck(p.fThreadHandle)
      p.fThreadHandle = 0

    if p.fProcessHandle != 0:
      closeHandleCheck(p.fProcessHandle)
      p.fProcessHandle = 0

  proc close(p: Process) =
    if poParentStreams notin p.options:
      if p.inStream == nil:
        p.inHandle.fileClose()
      else:
        # p.inHandle can be already closed via inputStream.
        p.inStream.close

      # You may NOT close outputStream and errorStream.
      assert p.outStream == nil or FileHandleStream(p.outStream).handle != INVALID_HANDLE_VALUE
      assert p.errStream == nil or FileHandleStream(p.errStream).handle != INVALID_HANDLE_VALUE

      if p.outHandle != p.errHandle:
        p.errHandle.fileClose()
      p.outHandle.fileClose()
    p.closeThreadAndProcessHandle()

  proc suspend(p: Process) =
    discard suspendThread(p.fThreadHandle)

  proc resume(p: Process) =
    discard resumeThread(p.fThreadHandle)

  proc running(p: Process): bool =
    if p.exitFlag:
      return false
    else:
      var x = waitForSingleObject(p.fProcessHandle, 0)
      return x == WAIT_TIMEOUT

  proc terminate(p: Process) =
    if running(p):
      discard terminateProcess(p.fProcessHandle, 0)

  proc kill(p: Process) =
    terminate(p)

  proc waitForExit(p: Process, timeout: int = -1): int =
    if p.exitFlag:
      return p.exitStatus

    let res = waitForSingleObject(p.fProcessHandle, timeout.int32)
    if res == WAIT_TIMEOUT:
      terminate(p)
    var status: int32
    discard getExitCodeProcess(p.fProcessHandle, status)
    if status != STILL_ACTIVE:
      p.exitFlag = true
      p.exitStatus = status
      p.closeThreadAndProcessHandle()
      result = status
    else:
      result = -1

  proc peekExitCode(p: Process): int =
    if p.exitFlag:
      return p.exitStatus

    result = -1
    var b = waitForSingleObject(p.fProcessHandle, 0) == WAIT_TIMEOUT
    if not b:
      var status: int32
      discard getExitCodeProcess(p.fProcessHandle, status)
      p.exitFlag = true
      p.exitStatus = status
      p.closeThreadAndProcessHandle()
      result = status

  proc inputStream(p: Process): Stream =
    streamAccess(p)
    if p.inStream == nil:
      p.inStream = newFileHandleStream(p.inHandle)
    result = p.inStream

  proc outputStream(p: Process): Stream =
    streamAccess(p)
    if p.outStream == nil:
      p.outStream = newFileHandleStream(p.outHandle)
    result = p.outStream

  proc errorStream(p: Process): Stream =
    streamAccess(p)
    if p.errStream == nil:
      p.errStream = newFileHandleStream(p.errHandle)
    result = p.errStream

  proc peekableOutputStream(p: Process): Stream =
    streamAccess(p)
    if p.outStream == nil:
      p.outStream = newFileHandleStream(p.outHandle).newPipeOutStream
    result = p.outStream

  proc peekableErrorStream(p: Process): Stream =
    streamAccess(p)
    if p.errStream == nil:
      p.errStream = newFileHandleStream(p.errHandle).newPipeOutStream
    result = p.errStream

  proc execCmd(command: string): int =
    var
      si: STARTUPINFO
      procInfo: PROCESS_INFORMATION
      process: Handle
      L: int32
    si.cb = sizeof(si).cint
    si.hStdError = getStdHandle(STD_ERROR_HANDLE)
    si.hStdInput = getStdHandle(STD_INPUT_HANDLE)
    si.hStdOutput = getStdHandle(STD_OUTPUT_HANDLE)
    var c = newWideCString(command)
    var res = winlean.createProcessW(nil, c, nil, nil, 0,
      NORMAL_PRIORITY_CLASS, nil, nil, si, procInfo)
    if res == 0:
      raiseOSError(osLastError())
    else:
      process = procInfo.hProcess
      discard closeHandle(procInfo.hThread)
      if waitForSingleObject(process, INFINITE) != -1:
        discard getExitCodeProcess(process, L)
        result = int(L)
      else:
        result = -1
      discard closeHandle(process)

  proc select(readfds: var seq[Process], timeout = 500): int =
    assert readfds.len <= MAXIMUM_WAIT_OBJECTS
    var rfds: WOHandleArray
    for i in 0..readfds.len()-1:
      rfds[i] = readfds[i].outHandle #fProcessHandle

    var ret = waitForMultipleObjects(readfds.len.int32,
                                     addr(rfds), 0'i32, timeout.int32)
    case ret
    of WAIT_TIMEOUT:
      return 0
    of WAIT_FAILED:
      raiseOSError(osLastError())
    else:
      var i = ret - WAIT_OBJECT_0
      readfds.del(i)
      return 1

  proc hasData*(p: Process): bool =
    var x: int32
    if peekNamedPipe(p.outHandle, lpTotalBytesAvail = addr x):
      result = x > 0

elif not defined(useNimRtl):
  const
    readIdx = 0
    writeIdx = 1

  proc isExitStatus(status: cint): bool =
    WIFEXITED(status) or WIFSIGNALED(status)

  proc envToCStringArray(t: StringTableRef): cstringArray =
    result = cast[cstringArray](alloc0((t.len + 1) * sizeof(cstring)))
    var i = 0
    for key, val in pairs(t):
      var x = key & "=" & val
      result[i] = cast[cstring](alloc(x.len+1))
      copyMem(result[i], addr(x[0]), x.len+1)
      inc(i)

  proc envToCStringArray(): cstringArray =
    var counter = 0
    for key, val in envPairs(): inc counter
    result = cast[cstringArray](alloc0((counter + 1) * sizeof(cstring)))
    var i = 0
    for key, val in envPairs():
      var x = key & "=" & val
      result[i] = cast[cstring](alloc(x.len+1))
      copyMem(result[i], addr(x[0]), x.len+1)
      inc(i)

  type
    StartProcessData = object
      sysCommand: string
      sysArgs: cstringArray
      sysEnv: cstringArray
      workingDir: cstring
      pStdin, pStdout, pStderr, pErrorPipe: array[0..1, cint]
      options: set[ProcessOption]

  const useProcessAuxSpawn = declared(posix_spawn) and not defined(useFork) and
                             not defined(useClone) and not defined(linux)
  when useProcessAuxSpawn:
    proc startProcessAuxSpawn(data: StartProcessData): Pid {.
      raises: [OSError], tags: [ExecIOEffect, ReadEnvEffect, ReadDirEffect, RootEffect], gcsafe.}
  else:
    proc startProcessAuxFork(data: StartProcessData): Pid {.
      raises: [OSError], tags: [ExecIOEffect, ReadEnvEffect, ReadDirEffect, RootEffect], gcsafe.}
    {.push stacktrace: off, profiler: off.}
    proc startProcessAfterFork(data: ptr StartProcessData) {.
      raises: [OSError], tags: [ExecIOEffect, ReadEnvEffect, ReadDirEffect, RootEffect], cdecl, gcsafe.}
    {.pop.}

  proc startProcess(command: string, workingDir: string = "",
      args: openArray[string] = [], env: StringTableRef = nil,
      options: set[ProcessOption] = {poStdErrToStdOut}):
    owned Process =
    var
      pStdin, pStdout, pStderr: array[0..1, cint] = default(array[0..1, cint])
    new(result)
    result.options = options
    result.exitFlag = true

    if poParentStreams notin options:
      if pipe(pStdin) != 0'i32 or pipe(pStdout) != 0'i32 or
         pipe(pStderr) != 0'i32:
        raiseOSError(osLastError())

    var data: StartProcessData = default(StartProcessData)
    var sysArgsRaw: seq[string]
    if poEvalCommand in options:
      const useShPath {.strdefine.} =
        when not defined(android): "/bin/sh"
        else: "/system/bin/sh"
      data.sysCommand = useShPath
      sysArgsRaw = @[useShPath, "-c", command]
      assert args.len == 0, "`args` has to be empty when using poEvalCommand."
    else:
      data.sysCommand = command
      sysArgsRaw = @[command]
      for arg in args.items:
        sysArgsRaw.add arg

    var pid: Pid

    var sysArgs = allocCStringArray(sysArgsRaw)
    defer: deallocCStringArray(sysArgs)

    var sysEnv = if env == nil:
        envToCStringArray()
      else:
        envToCStringArray(env)

    defer: deallocCStringArray(sysEnv)

    data.sysArgs = sysArgs
    data.sysEnv = sysEnv
    data.pStdin = pStdin
    data.pStdout = pStdout
    data.pStderr = pStderr
    data.workingDir = workingDir
    data.options = options

    when useProcessAuxSpawn:
      var currentDir = getCurrentDir()
      pid = startProcessAuxSpawn(data)
      if workingDir.len > 0:
        setCurrentDir(currentDir)
    else:
      pid = startProcessAuxFork(data)

    # Parent process. Copy process information.
    if poEchoCmd in options:
      echo(command, " ", join(args, " "))
    result.id = pid
    result.exitFlag = false

    if poParentStreams in options:
      # does not make much sense, but better than nothing:
      result.inHandle = 0
      result.outHandle = 1
      if poStdErrToStdOut in options:
        result.errHandle = result.outHandle
      else:
        result.errHandle = 2
    else:
      result.inHandle = pStdin[writeIdx]
      result.outHandle = pStdout[readIdx]
      if poStdErrToStdOut in options:
        result.errHandle = result.outHandle
        discard close(pStderr[readIdx])
      else:
        result.errHandle = pStderr[readIdx]
      discard close(pStderr[writeIdx])
      discard close(pStdin[readIdx])
      discard close(pStdout[writeIdx])

  when useProcessAuxSpawn:
    proc startProcessAuxSpawn(data: StartProcessData): Pid =
      var attr: Tposix_spawnattr
      var fops: Tposix_spawn_file_actions

      template chck(e: untyped) =
        if e != 0'i32: raiseOSError(osLastError())

      chck posix_spawn_file_actions_init(fops)
      chck posix_spawnattr_init(attr)

      var mask: Sigset
      chck sigemptyset(mask)
      chck posix_spawnattr_setsigmask(attr, mask)
      when not defined(nuttx):
        if poDaemon in data.options:
          chck posix_spawnattr_setpgroup(attr, 0'i32)

      var flags = POSIX_SPAWN_USEVFORK or
                  POSIX_SPAWN_SETSIGMASK
      when not defined(nuttx):
        if poDaemon in data.options:
          flags = flags or POSIX_SPAWN_SETPGROUP
      chck posix_spawnattr_setflags(attr, flags)

      if not (poParentStreams in data.options):
        chck posix_spawn_file_actions_addclose(fops, data.pStdin[writeIdx])
        chck posix_spawn_file_actions_adddup2(fops, data.pStdin[readIdx], readIdx)
        chck posix_spawn_file_actions_addclose(fops, data.pStdout[readIdx])
        chck posix_spawn_file_actions_adddup2(fops, data.pStdout[writeIdx], writeIdx)
        chck posix_spawn_file_actions_addclose(fops, data.pStderr[readIdx])
        if poStdErrToStdOut in data.options:
          chck posix_spawn_file_actions_adddup2(fops, data.pStdout[writeIdx], 2)
        else:
          chck posix_spawn_file_actions_adddup2(fops, data.pStderr[writeIdx], 2)

      var res: cint
      if data.workingDir.len > 0:
        setCurrentDir($data.workingDir)
      var pid: Pid

      if (poUsePath in data.options):
        res = posix_spawnp(pid, data.sysCommand.cstring, fops, attr, data.sysArgs, data.sysEnv)
      else:
        res = posix_spawn(pid, data.sysCommand.cstring, fops, attr, data.sysArgs, data.sysEnv)

      discard posix_spawn_file_actions_destroy(fops)
      discard posix_spawnattr_destroy(attr)
      if res != 0'i32: raiseOSError(OSErrorCode(res), data.sysCommand)

      return pid
  else:
    proc startProcessAuxFork(data: StartProcessData): Pid =
      if pipe(data.pErrorPipe) != 0:
        raiseOSError(osLastError())

      defer:
        discard close(data.pErrorPipe[readIdx])

      var pid: Pid
      var dataCopy = data

      when defined(useClone):
        const stackSize = 65536
        let stackEnd = cast[clong](alloc(stackSize))
        let stack = cast[pointer](stackEnd + stackSize)
        let fn: pointer = startProcessAfterFork
        pid = clone(fn, stack,
                    cint(CLONE_VM or CLONE_VFORK or SIGCHLD),
                    pointer(addr dataCopy), nil, nil, nil)
        discard close(data.pErrorPipe[writeIdx])
        dealloc(stack)
      else:
        pid = fork()
        if pid == 0:
          startProcessAfterFork(addr(dataCopy))
          exitnow(1)

      discard close(data.pErrorPipe[writeIdx])
      if pid < 0: raiseOSError(osLastError())

      var error: cint = cint(0)
      let sizeRead = read(data.pErrorPipe[readIdx], addr error, sizeof(error))
      if sizeRead == sizeof(error):
        raiseOSError(OSErrorCode(error),
                      "Could not find command: '" & $data.sysCommand & "'. OS error: " & $strerror(error))

      return pid

    {.push stacktrace: off, profiler: off.}
    proc startProcessFail(data: ptr StartProcessData, error: cint = errno) =
      discard write(data.pErrorPipe[writeIdx], addr error, sizeof(error))
      exitnow(1)

    when not defined(uClibc) and (not defined(linux) or defined(android)) and
         not defined(haiku):
      var environ {.importc.}: cstringArray

    proc startProcessAfterFork(data: ptr StartProcessData) =
      # Warning: no GC here!
      # Or anything that touches global structures - all called nim procs
      # must be marked with stackTrace:off. Inspect C code after making changes.
      if not (poParentStreams in data.options):
        discard close(data.pStdin[writeIdx])
        if dup2(data.pStdin[readIdx], readIdx) < 0:
          startProcessFail(data)
        discard close(data.pStdout[readIdx])
        if dup2(data.pStdout[writeIdx], writeIdx) < 0:
          startProcessFail(data)
        discard close(data.pStderr[readIdx])
        if (poStdErrToStdOut in data.options):
          if dup2(data.pStdout[writeIdx], 2) < 0:
            startProcessFail(data)
        else:
          if dup2(data.pStderr[writeIdx], 2) < 0:
            startProcessFail(data)

      if data.workingDir.len > 0:
        if chdir(data.workingDir) < 0:
          startProcessFail(data)

      discard close(data.pErrorPipe[readIdx])
      discard fcntl(data.pErrorPipe[writeIdx], F_SETFD, FD_CLOEXEC)

      if (poUsePath in data.options):
        when defined(uClibc) or defined(linux) or defined(haiku):
          # uClibc environment (OpenWrt included) doesn't have the full execvpe
          var exe: string = ""
          try:
            exe = findExe(data.sysCommand)
          except OSError as e:
            startProcessFail(data, e.errorCode)
          discard execve(exe.cstring, data.sysArgs, data.sysEnv)
        else:
          # MacOSX doesn't have execvpe, so we need workaround.
          # On MacOSX we can arrive here only from fork, so this is safe:
          environ = data.sysEnv
          discard execvp(data.sysCommand.cstring, data.sysArgs)
      else:
        discard execve(data.sysCommand.cstring, data.sysArgs, data.sysEnv)

      startProcessFail(data)
    {.pop.}

  proc close(p: Process) =
    if poParentStreams notin p.options:
      if p.inStream != nil:
        close(p.inStream)
      else:
        discard close(p.inHandle)

      if p.outStream != nil:
        close(p.outStream)
      else:
        discard close(p.outHandle)

      if p.errStream != nil:
        close(p.errStream)
      else:
        discard close(p.errHandle)

  proc suspend(p: Process) =
    if kill(p.id, SIGSTOP) != 0'i32: raiseOSError(osLastError())

  proc resume(p: Process) =
    if kill(p.id, SIGCONT) != 0'i32: raiseOSError(osLastError())

  proc running(p: Process): bool =
    if p.exitFlag:
      return false
    else:
      var status: cint = 1
      let ret = waitpid(p.id, status, WNOHANG)
      if ret == int(p.id):
        if isExitStatus(status):
          p.exitFlag = true
          p.exitStatus = status
          return false
        else:
          return true
      elif ret == 0:
        return true # Can't establish status. Assume running.
      else:
        result = false
        raiseOSError(osLastError())

  proc terminate(p: Process) =
    if kill(p.id, SIGTERM) != 0'i32:
      raiseOSError(osLastError())

  proc kill(p: Process) =
    if kill(p.id, SIGKILL) != 0'i32:
      raiseOSError(osLastError())

  when defined(macosx) or defined(freebsd) or defined(netbsd) or
       defined(openbsd) or defined(dragonfly):
    import std/kqueue

    proc waitForExit(p: Process, timeout: int = -1): int =
      if p.exitFlag:
        return exitStatusLikeShell(p.exitStatus)

      if timeout == -1:
        var status: cint = 1
        if waitpid(p.id, status, 0) < 0:
          raiseOSError(osLastError())
        p.exitFlag = true
        p.exitStatus = status
      else:
        var kqFD = kqueue()
        if kqFD == -1:
          raiseOSError(osLastError())

        var kevIn = KEvent(ident: p.id.uint, filter: EVFILT_PROC,
                         flags: EV_ADD, fflags: NOTE_EXIT)
        var kevOut: KEvent
        var tmspec: Timespec

        if timeout >= 1000:
          tmspec.tv_sec = posix.Time(timeout div 1_000)
          tmspec.tv_nsec = (timeout %% 1_000) * 1_000_000
        else:
          tmspec.tv_sec = posix.Time(0)
          tmspec.tv_nsec = (timeout * 1_000_000)

        try:
          while true:
            var status: cint = 1
            var count = kevent(kqFD, addr(kevIn), 1, addr(kevOut), 1,
                               addr(tmspec))
            if count < 0:
              let err = osLastError()
              if err.cint != EINTR:
                raiseOSError(osLastError())
            elif count == 0:
              # timeout expired, so we trying to kill process
              if posix.kill(p.id, SIGKILL) == -1:
                raiseOSError(osLastError())
              if waitpid(p.id, status, 0) < 0:
                raiseOSError(osLastError())
              p.exitFlag = true
              p.exitStatus = status
              break
            else:
              if kevOut.ident == p.id.uint and kevOut.filter == EVFILT_PROC:
                if waitpid(p.id, status, 0) < 0:
                  raiseOSError(osLastError())
                p.exitFlag = true
                p.exitStatus = status
                break
              else:
                raiseOSError(osLastError())
        finally:
          discard posix.close(kqFD)

      result = exitStatusLikeShell(p.exitStatus)
  elif defined(haiku):
    const
      B_OBJECT_TYPE_THREAD = 3
      B_EVENT_INVALID = 0x1000
      B_RELATIVE_TIMEOUT = 0x8

    type
      ObjectWaitInfo {.importc: "object_wait_info", header: "OS.h".} = object
        obj {.importc: "object".}: int32
        typ {.importc: "type".}: uint16
        events: uint16

    proc waitForObjects(infos: ptr ObjectWaitInfo, numInfos: cint, flags: uint32,
                        timeout: int64): clong
                       {.importc: "wait_for_objects_etc", header: "OS.h".}

    proc waitForExit(p: Process, timeout: int = -1): int =
      if p.exitFlag:
        return exitStatusLikeShell(p.exitStatus)

      if timeout == -1:
        var status: cint = 1
        if waitpid(p.id, status, 0) < 0:
          raiseOSError(osLastError())
        p.exitFlag = true
        p.exitStatus = status
      else:
        var info = ObjectWaitInfo(
          obj: p.id, # Haiku's PID is actually the main thread ID.
          typ: B_OBJECT_TYPE_THREAD,
          events: B_EVENT_INVALID # notify when the thread die.
        )

        while true:
          var status: cint = 1
          let count = waitForObjects(addr info, 1, B_RELATIVE_TIMEOUT, timeout)

          if count < 0:
            let err = count.cint
            if err == ETIMEDOUT:
              # timeout expired, so we try to kill the process
              if posix.kill(p.id, SIGKILL) == -1:
                raiseOSError(osLastError())
              if waitpid(p.id, status, 0) < 0:
                raiseOSError(osLastError())
              p.exitFlag = true
              p.exitStatus = status
              break
            elif err != EINTR:
              raiseOSError(err.OSErrorCode)
          elif count > 0:
            if waitpid(p.id, status, 0) < 0:
              raiseOSError(osLastError())
            p.exitFlag = true
            p.exitStatus = status
            break
          else:
            raiseAssert "unreachable!"

      result = exitStatusLikeShell(p.exitStatus)

  else:
    import std/times except getTime
    import std/monotimes

    proc waitForExit(p: Process, timeout: int = -1): int =
      if p.exitFlag:
        return exitStatusLikeShell(p.exitStatus)

      if timeout < 0:
        # Backwards compatibility with previous verison to
        # handle cases where timeout == -1, but extend
        # to handle cases where timeout < 0
        var status: cint = cint(0)
        if waitpid(p.id, status, 0) < 0:
          raiseOSError(osLastError())
        p.exitFlag = true
        p.exitStatus = status
      else:
        # Max 50ms delay
        const maxWait = initDuration(milliseconds = 50)
        let wait = initDuration(milliseconds = timeout)
        let deadline = getMonoTime() + wait
        # starting 50μs delay
        var delay = initDuration(microseconds = 50)
        
        while true:
          var status: cint = cint(0)
          let pid = waitpid(p.id, status, WNOHANG)
          if p.id == pid :
            p.exitFlag = true
            p.exitStatus = status
            break
          elif pid.int == -1:
            raiseOsError(osLastError())
          else:
            # Continue waiting if needed
            if getMonoTime() >= deadline:
              # Previous version of `waitForExit`
              # foricibly killed the process.
              # We keep this so we don't break programs
              # that depend on this behavior
              if posix.kill(p.id, SIGKILL) < 0:
                raiseOSError(osLastError())
            else:
              const max = 1_000_000_000
              let 
                newWait = getMonoTime() + delay
                ticks = newWait.ticks()
                ns = ticks mod max
                secs = ticks div max
              var 
                waitSpec: TimeSpec = default(TimeSpec)
                unused: Timespec = default(Timespec)
              waitSpec.tv_sec = posix.Time(secs)
              waitSpec.tv_nsec = clong ns 
              discard posix.clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, waitSpec, unused)
              let remaining = deadline - getMonoTime()
              delay = min([delay * 2, remaining, maxWait])

      result = exitStatusLikeShell(p.exitStatus)

  proc peekExitCode(p: Process): int =
    var status = cint(0)
    result = -1
    if p.exitFlag:
      return exitStatusLikeShell(p.exitStatus)

    var ret = waitpid(p.id, status, WNOHANG)
    if ret > 0:
      if isExitStatus(status):
        p.exitFlag = true
        p.exitStatus = status
        result = exitStatusLikeShell(status)

  proc createStream(handle: var FileHandle,
                    fileMode: FileMode): owned FileStream =
    var f: File = default(File)
    if not open(f, handle, fileMode): raiseOSError(osLastError())
    return newFileStream(f)

  proc inputStream(p: Process): Stream =
    streamAccess(p)
    if p.inStream == nil:
      p.inStream = createStream(p.inHandle, fmWrite)
    return p.inStream

  proc outputStream(p: Process): Stream =
    streamAccess(p)
    if p.outStream == nil:
      p.outStream = createStream(p.outHandle, fmRead)
    return p.outStream

  proc errorStream(p: Process): Stream =
    streamAccess(p)
    if p.errStream == nil:
      p.errStream = createStream(p.errHandle, fmRead)
    return p.errStream

  proc peekableOutputStream(p: Process): Stream =
    streamAccess(p)
    if p.outStream == nil:
      p.outStream = createStream(p.outHandle, fmRead).newPipeOutStream
    return p.outStream

  proc peekableErrorStream(p: Process): Stream =
    streamAccess(p)
    if p.errStream == nil:
      p.errStream = createStream(p.errHandle, fmRead).newPipeOutStream
    return p.errStream

  proc csystem(cmd: cstring): cint {.nodecl, importc: "system",
                                     header: "<stdlib.h>".}

  proc execCmd(command: string): int =
    when defined(posix):
      let tmp = csystem(command)
      result = if tmp == -1: tmp else: exitStatusLikeShell(tmp)
    else:
      result = csystem(command)

  proc createFdSet(fd: var TFdSet, s: seq[Process], m: var int) =
    FD_ZERO(fd)
    for i in items(s):
      m = max(m, int(i.outHandle))
      FD_SET(cint(i.outHandle), fd)

  proc pruneProcessSet(s: var seq[Process], fd: var TFdSet) =
    var i = 0
    var L = s.len
    while i < L:
      if FD_ISSET(cint(s[i].outHandle), fd) == 0'i32:
        s[i] = s[L-1]
        dec(L)
      else:
        inc(i)
    setLen(s, L)

  proc select(readfds: var seq[Process], timeout = 500): int =
    var tv: Timeval = Timeval(tv_sec: posix.Time(0), tv_usec: Suseconds(timeout * 1000))

    var rd: TFdSet = default(TFdSet)
    var m = 0
    createFdSet((rd), readfds, m)

    if timeout != -1:
      result = int(select(cint(m+1), addr(rd), nil, nil, addr(tv)))
    else:
      result = int(select(cint(m+1), addr(rd), nil, nil, nil))

    pruneProcessSet(readfds, (rd))

  proc hasData*(p: Process): bool =
    var rd: TFdSet = default(TFdSet)

    FD_ZERO(rd)
    let m = max(0, int(p.outHandle))
    FD_SET(cint(p.outHandle), rd)

    result = int(select(cint(m+1), addr(rd), nil, nil, nil)) == 1


proc execCmdEx*(command: string, options: set[ProcessOption] = {
                poStdErrToStdOut, poUsePath}, env: StringTableRef = nil,
                workingDir = "", input = ""): tuple[
                output: string,
                exitCode: int] {.raises: [OSError, IOError], tags:
                [ExecIOEffect, ReadIOEffect, RootEffect], gcsafe.} =
  ## A convenience proc that runs the `command`, and returns its `output` and
  ## `exitCode`. `env` and `workingDir` params behave as for `startProcess`.
  ## If `input.len > 0`, it is passed as stdin.
  ##
  ## Note: this could block if `input.len` is greater than your OS's maximum
  ## pipe buffer size.
  ##
  ## See also:
  ## * `execCmd proc <#execCmd,string>`_
  ## * `startProcess proc
  ##   <#startProcess,string,string,openArray[string],StringTableRef,set[ProcessOption]>`_
  ## * `execProcess proc
  ##   <#execProcess,string,string,openArray[string],StringTableRef,set[ProcessOption]>`_
  ##
  ## Example:
  ##   ```Nim
  ##   var result = execCmdEx("nim r --hints:off -", options = {}, input = "echo 3*4")
  ##   import std/[strutils, strtabs]
  ##   stripLineEnd(result[0]) ## portable way to remove trailing newline, if any
  ##   doAssert result == ("12", 0)
  ##   doAssert execCmdEx("ls --nonexistent").exitCode != 0
  ##   when defined(posix):
  ##     assert execCmdEx("echo $FO", env = newStringTable({"FO": "B"})) == ("B\n", 0)
  ##     assert execCmdEx("echo $PWD", workingDir = "/") == ("/\n", 0)
  ##   ```

  when (NimMajor, NimMinor, NimPatch) < (1, 3, 5):
    doAssert input.len == 0
    doAssert workingDir.len == 0
    doAssert env == nil

  var p = startProcess(command, options = options + {poEvalCommand},
    workingDir = workingDir, env = env)
  var outp = outputStream(p)

  if input.len > 0:
    # There is no way to provide input for the child process
    # anymore. Closing it will create EOF on stdin instead of eternal
    # blocking.
    # Writing in chunks would require a selectors (eg kqueue/epoll) to avoid
    # blocking on io.
    inputStream(p).write(input)
  close inputStream(p)

  # consider `p.lines(keepNewLines=true)` to avoid exit code test
  result = ("", -1)
  var line = newStringOfCap(120)
  while true:
    if outp.readLine(line):
      result[0].add(line)
      result[0].add("\n")
    else:
      result[1] = peekExitCode(p)
      if result[1] != -1: break
  close(p)

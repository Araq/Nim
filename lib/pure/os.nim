#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module contains basic operating system facilities like
## retrieving environment variables, working with directories,
## running shell commands, etc.

## .. importdoc:: symlinks.nim, appdirs.nim, dirs.nim, ospaths2.nim

runnableExamples:
  let myFile = "/path/to/my/file.nim"
  assert splitPath(myFile) == (head: "/path/to/my", tail: "file.nim")
  when defined(posix):
    assert parentDir(myFile) == "/path/to/my"
  assert splitFile(myFile) == (dir: "/path/to/my", name: "file", ext: ".nim")
  assert myFile.changeFileExt("c") == "/path/to/my/file.c"

## **See also:**
## * `paths <paths.html>`_ and `files <files.html>`_ modules for high-level file manipulation
## * `osproc module <osproc.html>`_ for process communication beyond
##   `execShellCmd proc`_
## * `uri module <uri.html>`_
## * `distros module <distros.html>`_
## * `dynlib module <dynlib.html>`_
## * `streams module <streams.html>`_
import std/private/ospaths2
export ospaths2

import std/private/oscommon

when supportedSystem:
  import std/private/osfiles
  export osfiles

  import std/private/osdirs
  export osdirs

  import std/private/ossymlinks
  export ossymlinks

import std/private/osappdirs
export osappdirs

include system/inclrtl
import std/private/since

import std/cmdline
export cmdline

import std/[strutils, pathnorm]

when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions, widestrs]

const weirdTarget = defined(nimscript) or defined(js)

since (1, 1):
  const
    invalidFilenameChars* = {'/', '\\', ':', '*', '?', '"', '<', '>', '|', '^', '\0'} ## \
    ## Characters that may produce invalid filenames across Linux, Windows and Mac.
    ## You can check if your filename contains any of these chars and strip them for safety.
    ## Mac bans ``':'``, Linux bans ``'/'``, Windows bans all others.
    invalidFilenames* = [
      "CON", "PRN", "AUX", "NUL",
      "COM0", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
      "LPT0", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"] ## \
    ## Filenames that may be invalid across Linux, Windows, Mac, etc.
    ## You can check if your filename match these and rename it for safety
    ## (Currently all invalid filenames are from Windows only).

when weirdTarget:
  discard
elif defined(windows):
  import std/[winlean, times]
elif defined(posix):
  import std/[posix, times]

  proc toTime(ts: Timespec): times.Time {.inline.} =
    result = initTime(ts.tv_sec.int64, ts.tv_nsec.int)

when weirdTarget:
  {.pragma: noWeirdTarget, error: "this proc is not available on the NimScript/js target".}
else:
  {.pragma: noWeirdTarget.}

when defined(nimscript):
  # for procs already defined in scriptconfig.nim
  template noNimJs(body): untyped = discard
elif defined(js):
  {.pragma: noNimJs, error: "this proc is not available on the js target".}
else:
  {.pragma: noNimJs.}


import std/oserrors
export oserrors
import std/envvars
export envvars

import std/private/osseps
export osseps



proc expandTilde*(path: string): string {.
  tags: [ReadEnvEffect, ReadIOEffect].} =
  ## Expands ``~`` or a path starting with ``~/`` to a full path, replacing
  ## ``~`` with `getHomeDir()`_ (otherwise returns ``path`` unmodified).
  ##
  ## Windows: this is still supported despite the Windows platform not having this
  ## convention; also, both ``~/`` and ``~\`` are handled.
  ##
  ## See also:
  ## * `getHomeDir proc`_
  ## * `getConfigDir proc`_
  ## * `getTempDir proc`_
  ## * `getCurrentDir proc`_
  ## * `setCurrentDir proc`_
  runnableExamples:
    assert expandTilde("~" / "appname.cfg") == getHomeDir() / "appname.cfg"
    assert expandTilde("~/foo/bar") == getHomeDir() / "foo/bar"
    assert expandTilde("/foo/bar") == "/foo/bar"

  if len(path) == 0 or path[0] != '~':
    result = path
  elif len(path) == 1:
    result = getHomeDir()
  elif (path[1] in {DirSep, AltSep}):
    result = getHomeDir() / path.substr(2)
  else:
    # TODO: handle `~bob` and `~bob/` which means home of bob
    result = path

proc quoteShellWindows*(s: string): string {.noSideEffect, rtl, extern: "nosp$1".} =
  ## Quote `s`, so it can be safely passed to Windows API.
  ##
  ## Based on Python's `subprocess.list2cmdline`.
  ## See `this link <https://msdn.microsoft.com/en-us/library/17w5ykft.aspx>`_
  ## for more details.
  let needQuote = {' ', '\t'} in s or s.len == 0
  result = ""
  var backslashBuff = ""
  if needQuote:
    result.add("\"")

  for c in s:
    if c == '\\':
      backslashBuff.add(c)
    elif c == '\"':
      for i in 0..<backslashBuff.len*2:
        result.add('\\')
      backslashBuff.setLen(0)
      result.add("\\\"")
    else:
      if backslashBuff.len != 0:
        result.add(backslashBuff)
        backslashBuff.setLen(0)
      result.add(c)

  if backslashBuff.len > 0:
    result.add(backslashBuff)
  if needQuote:
    result.add(backslashBuff)
    result.add("\"")


proc quoteShellPosix*(s: string): string {.noSideEffect, rtl, extern: "nosp$1".} =
  ## Quote ``s``, so it can be safely passed to POSIX shell.
  const safeUnixChars = {'%', '+', '-', '.', '/', '_', ':', '=', '@',
                         '0'..'9', 'A'..'Z', 'a'..'z'}
  if s.len == 0:
    result = "''"
  elif s.allCharsInSet(safeUnixChars):
    result = s
  else:
    result = "'" & s.replace("'", "'\"'\"'") & "'"

when defined(windows) or defined(posix) or defined(nintendoswitch):
  proc quoteShell*(s: string): string {.noSideEffect, rtl, extern: "nosp$1".} =
    ## Quote ``s``, so it can be safely passed to shell.
    ##
    ## When on Windows, it calls `quoteShellWindows proc`_.
    ## Otherwise, calls `quoteShellPosix proc`_.
    when defined(windows):
      result = quoteShellWindows(s)
    else:
      result = quoteShellPosix(s)

  proc quoteShellCommand*(args: openArray[string]): string =
    ## Concatenates and quotes shell arguments `args`.
    runnableExamples:
      when defined(posix):
        assert quoteShellCommand(["aaa", "", "c d"]) == "aaa '' 'c d'"
      when defined(windows):
        assert quoteShellCommand(["aaa", "", "c d"]) == "aaa \"\" \"c d\""

    # can't use `map` pending https://github.com/nim-lang/Nim/issues/8303
    result = ""
    for i in 0..<args.len:
      if i > 0: result.add " "
      result.add quoteShell(args[i])

when not weirdTarget:
  proc c_system(cmd: cstring): cint {.
    importc: "system", header: "<stdlib.h>".}

  when not defined(windows):
    proc c_free(p: pointer) {.
      importc: "free", header: "<stdlib.h>".}


const
  ExeExts* = ## Platform specific file extension for executables.
    ## On Windows ``["exe", "cmd", "bat"]``, on Posix ``[""]``.
    when defined(windows): ["exe", "cmd", "bat"] else: [""]

when supportedSystem:
  proc findExe*(exe: string, followSymlinks: bool = true;
                extensions: openArray[string]=ExeExts): string {.
    tags: [ReadDirEffect, ReadEnvEffect, ReadIOEffect], noNimJs.} =
    ## Searches for `exe` in the current working directory and then
    ## in directories listed in the ``PATH`` environment variable.
    ##
    ## Returns `""` if the `exe` cannot be found. `exe`
    ## is added the `ExeExts`_ file extensions if it has none.
    ##
    ## If the system supports symlinks it also resolves them until it
    ## meets the actual file. This behavior can be disabled if desired
    ## by setting `followSymlinks = false`.

    if exe.len == 0: return
    template checkCurrentDir() =
      for ext in extensions:
        result = addFileExt(exe, ext)
        if fileExists(result): return
    when defined(posix):
      if '/' in exe: checkCurrentDir()
    else:
      checkCurrentDir()
    let path = getEnv("PATH")
    for candidate in split(path, PathSep):
      if candidate.len == 0: continue
      when defined(windows):
        var x = (if candidate[0] == '"' and candidate[^1] == '"':
                  substr(candidate, 1, candidate.len-2) else: candidate) /
                exe
      else:
        var x = expandTilde(candidate) / exe
      for ext in extensions:
        var x = addFileExt(x, ext)
        if fileExists(x):
          when defined(posix): #not (defined(windows) or defined(nintendoswitch)):
            while followSymlinks: # doubles as if here
              if x.symlinkExists:
                var r = newString(maxSymlinkLen)
                var len = readlink(x.cstring, r.cstring, maxSymlinkLen)
                if len < 0:
                  raiseOSError(osLastError(), exe)
                if len > maxSymlinkLen:
                  r = newString(len+1)
                  len = readlink(x.cstring, r.cstring, len)
                setLen(r, len)
                if isAbsolute(r):
                  x = r
                else:
                  x = parentDir(x) / r
              else:
                break
          return x
    result = ""

  when weirdTarget:
    const times = "fake const"
    template Time(x: untyped): untyped = string

  proc getLastModificationTime*(file: string): times.Time {.rtl, extern: "nos$1", noWeirdTarget.} =
    ## Returns the `file`'s last modification time.
    ##
    ## See also:
    ## * `getLastAccessTime proc`_
    ## * `getCreationTime proc`_
    ## * `fileNewer proc`_
    when defined(posix):
      var res: Stat = default(Stat)
      if stat(file, res) < 0'i32: raiseOSError(osLastError(), file)
      result = res.st_mtim.toTime
    else:
      var f: WIN32_FIND_DATA
      var h = findFirstFile(file, f)
      if h == -1'i32: raiseOSError(osLastError(), file)
      result = fromWinTime(rdFileTime(f.ftLastWriteTime))
      findClose(h)

  proc getLastAccessTime*(file: string): times.Time {.rtl, extern: "nos$1", noWeirdTarget.} =
    ## Returns the `file`'s last read or write access time.
    ##
    ## See also:
    ## * `getLastModificationTime proc`_
    ## * `getCreationTime proc`_
    ## * `fileNewer proc`_
    when defined(posix):
      var res: Stat = default(Stat)
      if stat(file, res) < 0'i32: raiseOSError(osLastError(), file)
      result = res.st_atim.toTime
    else:
      var f: WIN32_FIND_DATA
      var h = findFirstFile(file, f)
      if h == -1'i32: raiseOSError(osLastError(), file)
      result = fromWinTime(rdFileTime(f.ftLastAccessTime))
      findClose(h)

  proc getCreationTime*(file: string): times.Time {.rtl, extern: "nos$1", noWeirdTarget.} =
    ## Returns the `file`'s creation time.
    ##
    ## **Note:** Under POSIX OS's, the returned time may actually be the time at
    ## which the file's attribute's were last modified. See
    ## `here <https://github.com/nim-lang/Nim/issues/1058>`_ for details.
    ##
    ## See also:
    ## * `getLastModificationTime proc`_
    ## * `getLastAccessTime proc`_
    ## * `fileNewer proc`_
    when defined(posix):
      var res: Stat = default(Stat)
      if stat(file, res) < 0'i32: raiseOSError(osLastError(), file)
      result = res.st_ctim.toTime
    else:
      var f: WIN32_FIND_DATA
      var h = findFirstFile(file, f)
      if h == -1'i32: raiseOSError(osLastError(), file)
      result = fromWinTime(rdFileTime(f.ftCreationTime))
      findClose(h)

  proc fileNewer*(a, b: string): bool {.rtl, extern: "nos$1", noWeirdTarget.} =
    ## Returns true if the file `a` is newer than file `b`, i.e. if `a`'s
    ## modification time is later than `b`'s.
    ##
    ## See also:
    ## * `getLastModificationTime proc`_
    ## * `getLastAccessTime proc`_
    ## * `getCreationTime proc`_
    when defined(posix):
      # If we don't have access to nanosecond resolution, use '>='
      when not StatHasNanoseconds:
        result = getLastModificationTime(a) >= getLastModificationTime(b)
      else:
        result = getLastModificationTime(a) > getLastModificationTime(b)
    else:
      result = getLastModificationTime(a) > getLastModificationTime(b)


  proc isAdmin*: bool {.noWeirdTarget.} =
    ## Returns whether the caller's process is a member of the Administrators local
    ## group (on Windows) or a root (on POSIX), via `geteuid() == 0`.
    when defined(windows):
      # Rewrite of the example from Microsoft Docs:
      # https://docs.microsoft.com/en-us/windows/win32/api/securitybaseapi/nf-securitybaseapi-checktokenmembership#examples
      # and corresponding PostgreSQL function:
      # https://doxygen.postgresql.org/win32security_8c.html#ae6b61e106fa5d6c5d077a9d14ee80569
      var ntAuthority = SID_IDENTIFIER_AUTHORITY(value: SECURITY_NT_AUTHORITY)
      var administratorsGroup: PSID
      if not isSuccess(allocateAndInitializeSid(addr ntAuthority,
                                                BYTE(2),
                                                SECURITY_BUILTIN_DOMAIN_RID,
                                                DOMAIN_ALIAS_RID_ADMINS,
                                                0, 0, 0, 0, 0, 0,
                                                addr administratorsGroup)):
        raiseOSError(osLastError(), "could not get SID for Administrators group")

      try:
        var b: WINBOOL
        if not isSuccess(checkTokenMembership(0, administratorsGroup, addr b)):
          raiseOSError(osLastError(), "could not check access token membership")

        result = isSuccess(b)
      finally:
        if freeSid(administratorsGroup) != nil:
          raiseOSError(osLastError(), "failed to free SID for Administrators group")

    else:
      result = geteuid() == 0

  proc expandFilename*(filename: string): string {.rtl, extern: "nos$1",
    tags: [ReadDirEffect], noWeirdTarget.} =
    ## Returns the full (`absolute`:idx:) path of an existing file `filename`.
    ##
    ## Raises `OSError` in case of an error. Follows symlinks.
    result = ""
    when defined(windows):
      var bufsize = MAX_PATH.int32
      var unused: WideCString = nil
      var res = newWideCString(bufsize)
      while true:
        var L = getFullPathNameW(newWideCString(filename), bufsize, res, unused)
        if L == 0'i32:
          raiseOSError(osLastError(), filename)
        elif L > bufsize:
          res = newWideCString(L)
          bufsize = L
        else:
          result = res$L
          break
      # getFullPathName doesn't do case corrections, so we have to use this convoluted
      # way of retrieving the true filename
      for x in walkFiles(result):
        result = x
      if not fileExists(result) and not dirExists(result):
        # consider using: `raiseOSError(osLastError(), result)`
        raise newException(OSError, "file '" & result & "' does not exist")
    else:
      # according to Posix we don't need to allocate space for result pathname.
      # But we need to free return value with free(3).
      var r = realpath(filename, nil)
      if r.isNil:
        raiseOSError(osLastError(), filename)
      else:
        result = $r
        c_free(cast[pointer](r))

  proc createHardlink*(src, dest: string) {.noWeirdTarget.} =
    ## Create a hard link at `dest` which points to the item specified
    ## by `src`.
    ##
    ## .. warning:: Some OS's restrict the creation of hard links to
    ##   root users (administrators).
    ##
    ## See also:
    ## * `createSymlink proc`_
    when defined(windows):
      var wSrc = newWideCString(src)
      var wDst = newWideCString(dest)
      if createHardLinkW(wDst, wSrc, nil) == 0:
        raiseOSError(osLastError(), $(src, dest))
    else:
      if link(src, dest) != 0:
        raiseOSError(osLastError(), $(src, dest))

  proc sleep*(milsecs: int) {.rtl, extern: "nos$1", tags: [TimeEffect], noWeirdTarget.} =
    ## Sleeps `milsecs` milliseconds.
    ## A negative `milsecs` causes sleep to return immediately.
    when defined(windows):
      if milsecs < 0:
        return  # fixes #23732
      winlean.sleep(int32(milsecs))
    else:
      var a, b: Timespec = default(Timespec)
      a.tv_sec = posix.Time(milsecs div 1000)
      a.tv_nsec = (milsecs mod 1000) * 1000 * 1000
      discard posix.nanosleep(a, b)

  proc getFileSize*(file: string): BiggestInt {.rtl, extern: "nos$1",
    tags: [ReadIOEffect], noWeirdTarget.} =
    ## Returns the file size of `file` (in bytes). ``OSError`` is
    ## raised in case of an error.
    when defined(windows):
      var a: WIN32_FIND_DATA
      var resA = findFirstFile(file, a)
      if resA == -1: raiseOSError(osLastError(), file)
      result = rdFileSize(a)
      findClose(resA)
    else:
      var rawInfo: Stat = default(Stat)
      if stat(file, rawInfo) < 0'i32:
        raiseOSError(osLastError(), file)
      rawInfo.st_size

  proc exitStatusLikeShell*(status: cint): cint =
    ## Converts exit code from `c_system` into a shell exit code.
    when defined(posix) and not weirdTarget:
      if WIFSIGNALED(status):
        # like the shell!
        128 + WTERMSIG(status)
      else:
        WEXITSTATUS(status)
    else:
      status

  proc execShellCmd*(command: string): int {.rtl, extern: "nos$1",
    tags: [ExecIOEffect], noWeirdTarget.} =
    ## Executes a `shell command`:idx:.
    ##
    ## Command has the form 'program args' where args are the command
    ## line arguments given to program. The proc returns the error code
    ## of the shell when it has finished (zero if there is no error).
    ## The proc does not return until the process has finished.
    ##
    ## To execute a program without having a shell involved, use `osproc.execProcess proc
    ## <osproc.html#execProcess,string,string,openArray[string],StringTableRef,set[ProcessOption]>`_.
    ##
    ## **Examples:**
    ##   ```Nim
    ##   discard execShellCmd("ls -la")
    ##   ```
    result = exitStatusLikeShell(c_system(command))

  proc inclFilePermissions*(filename: string,
                            permissions: set[FilePermission]) {.
    rtl, extern: "nos$1", tags: [ReadDirEffect, WriteDirEffect], noWeirdTarget.} =
    ## A convenience proc for:
    ##   ```nim
    ##   setFilePermissions(filename, getFilePermissions(filename)+permissions)
    ##   ```
    setFilePermissions(filename, getFilePermissions(filename)+permissions)

  proc exclFilePermissions*(filename: string,
                            permissions: set[FilePermission]) {.
    rtl, extern: "nos$1", tags: [ReadDirEffect, WriteDirEffect], noWeirdTarget.} =
    ## A convenience proc for:
    ##   ```nim
    ##   setFilePermissions(filename, getFilePermissions(filename)-permissions)
    ##   ```
    setFilePermissions(filename, getFilePermissions(filename)-permissions)

when not weirdTarget and (defined(freebsd) or defined(dragonfly) or defined(netbsd)):
  proc sysctl(name: ptr cint, namelen: cuint, oldp: pointer, oldplen: ptr csize_t,
              newp: pointer, newplen: csize_t): cint
       {.importc: "sysctl",header: """#include <sys/types.h>
                                      #include <sys/sysctl.h>""".}
  const
    CTL_KERN = 1
    KERN_PROC = 14
    MAX_PATH = 1024

  when defined(freebsd):
    const KERN_PROC_PATHNAME = 12
  elif defined(netbsd):
    const KERN_PROC_ARGS = 48
    const KERN_PROC_PATHNAME = 5
  else:
    const KERN_PROC_PATHNAME = 9

  proc getApplFreebsd(): string =
    var pathLength = csize_t(0)

    when defined(netbsd):
      var req = [CTL_KERN.cint, KERN_PROC_ARGS.cint, -1.cint, KERN_PROC_PATHNAME.cint]
    else:
      var req = [CTL_KERN.cint, KERN_PROC.cint, KERN_PROC_PATHNAME.cint, -1.cint]

    # first call to get the required length
    var res = sysctl(addr req[0], 4, nil, addr pathLength, nil, 0)

    if res < 0:
      return ""

    result.setLen(pathLength)
    res = sysctl(addr req[0], 4, addr result[0], addr pathLength, nil, 0)

    if res < 0:
      return ""

    let realLen = len(cstring(result))
    setLen(result, realLen)

when not weirdTarget and (defined(linux) or defined(solaris) or defined(bsd) or defined(aix)):
  proc getApplAux(procPath: string): string =
    result = newString(maxSymlinkLen)
    var len = readlink(procPath, result.cstring, maxSymlinkLen)
    if len > maxSymlinkLen:
      result = newString(len+1)
      len = readlink(procPath, result.cstring, len)
    setLen(result, len)

when not weirdTarget and defined(openbsd):
  proc getApplOpenBsd(): string =
    # similar to getApplHeuristic, but checks current working directory
    when declared(paramStr):
      result = ""

      # POSIX guaranties that this contains the executable
      # as it has been executed by the calling process
      let exePath = paramStr(0)

      if len(exePath) == 0:
        return ""

      if exePath[0] == DirSep:
        # path is absolute
        result = exePath
      else:
        # not an absolute path, check if it's relative to the current working directory
        for i in 1..<len(exePath):
          if exePath[i] == DirSep:
            result = joinPath(getCurrentDir(), exePath)
            break

      if len(result) > 0:
        return expandFilename(result)

      # search in path
      for p in split(getEnv("PATH"), {PathSep}):
        var x = joinPath(p, exePath)
        if fileExists(x):
          return expandFilename(x)
    else:
      result = ""

when not (defined(windows) or defined(macosx) or weirdTarget) and supportedSystem:
  proc getApplHeuristic(): string =
    when declared(paramStr):
      result = paramStr(0)
      # POSIX guaranties that this contains the executable
      # as it has been executed by the calling process
      if len(result) > 0 and result[0] != DirSep: # not an absolute path?
        # iterate over any path in the $PATH environment variable
        for p in split(getEnv("PATH"), {PathSep}):
          var x = joinPath(p, result)
          if fileExists(x): return x
    else:
      result = ""

when defined(macosx):
  type
    cuint32* {.importc: "unsigned int", nodecl.} = int
    ## This is the same as the type ``uint32_t`` in *C*.

  # a really hacky solution: since we like to include 2 headers we have to
  # define two procs which in reality are the same
  proc getExecPath1(c: cstring, size: var cuint32) {.
    importc: "_NSGetExecutablePath", header: "<sys/param.h>".}
  proc getExecPath2(c: cstring, size: var cuint32): bool {.
    importc: "_NSGetExecutablePath", header: "<mach-o/dyld.h>".}

when defined(haiku):
  const
    PATH_MAX = 1024
    B_FIND_PATH_IMAGE_PATH = 1000

  proc find_path(codePointer: pointer, baseDirectory: cint, subPath: cstring,
                 pathBuffer: cstring, bufferSize: csize_t): int32
                {.importc, header: "<FindDirectory.h>".}

  proc getApplHaiku(): string =
    result = newString(PATH_MAX)

    if find_path(nil, B_FIND_PATH_IMAGE_PATH, nil, result, PATH_MAX) == 0:
      let realLen = len(cstring(result))
      setLen(result, realLen)
    else:
      result = ""

when supportedSystem:
  proc getAppFilename*(): string {.rtl, extern: "nos$1", tags: [ReadIOEffect], noWeirdTarget, raises: [].} =
    ## Returns the filename of the application's executable.
    ## This proc will resolve symlinks.
    ##
    ## Returns empty string when name is unavailable
    ##
    ## See also:
    ## * `getAppDir proc`_
    ## * `getCurrentCompilerExe proc`_

    # Linux: /proc/<pid>/exe
    # Solaris:
    # /proc/<pid>/object/a.out (filename only)
    # /proc/<pid>/path/a.out (complete pathname)
    when defined(windows):
      var bufsize = int32(MAX_PATH)
      var buf = newWideCString(bufsize)
      while true:
        var L = getModuleFileNameW(0, buf, bufsize)
        if L == 0'i32:
          result = "" # error!
          break
        elif L > bufsize:
          buf = newWideCString(L)
          bufsize = L
        else:
          result = buf$L
          break
    elif defined(macosx):
      var size = cuint32(0)
      getExecPath1(nil, size)
      result = newString(int(size))
      if getExecPath2(result.cstring, size):
        result = "" # error!
      if result.len > 0:
        try:
          result = result.expandFilename
        except OSError:
          result = ""
    else:
      when defined(linux) or defined(aix):
        result = getApplAux("/proc/self/exe")
      elif defined(solaris):
        result = getApplAux("/proc/" & $getpid() & "/path/a.out")
      elif defined(genode):
        result = "" # Not supported
      elif defined(freebsd) or defined(dragonfly) or defined(netbsd):
        result = getApplFreebsd()
      elif defined(haiku):
        result = getApplHaiku()
      elif defined(openbsd):
        result = try: getApplOpenBsd() except OSError: ""
      elif defined(nintendoswitch):
        result = ""

      # little heuristic that may work on other POSIX-like systems:
      if result.len == 0:
        result = try: getApplHeuristic() except OSError: ""

  proc getAppDir*(): string {.rtl, extern: "nos$1", tags: [ReadIOEffect], noWeirdTarget.} =
    ## Returns the directory of the application's executable.
    ##
    ## See also:
    ## * `getAppFilename proc`_
    result = splitFile(getAppFilename()).dir

proc getCurrentCompilerExe*(): string {.compileTime.} =
  result = ""
  discard "implemented in the vmops"
  ## Returns the path of the currently running Nim compiler or nimble executable.
  ##
  ## Can be used to retrieve the currently executing
  ## Nim compiler from a Nim or nimscript program, or the nimble binary
  ## inside a nimble program (likewise with other binaries built from
  ## compiler API).

when defined(windows) or weirdTarget:
  type
    DeviceId* = int32
    FileId* = int64
elif defined(posix):
  type
    DeviceId* = Dev
    FileId* = Ino

when defined(js):
  when not declared(FileHandle):
    type FileHandle = distinct int32
  when not declared(File):
    type File = object

when weirdTarget or defined(windows) or defined(posix) or defined(nintendoswitch):
  type
    FileInfo* = object
      ## Contains information associated with a file object.
      ##
      ## See also:
      ## * `getFileInfo(handle) proc`_
      ## * `getFileInfo(file) proc`_
      ## * `getFileInfo(path, followSymlink) proc`_
      id*: tuple[device: DeviceId, file: FileId] ## Device and file id.
      kind*: PathComponent              ## Kind of file object - directory, symlink, etc.
      size*: BiggestInt                 ## Size of file.
      permissions*: set[FilePermission] ## File permissions
      linkCount*: BiggestInt            ## Number of hard links the file object has.
      lastAccessTime*: times.Time       ## Time file was last accessed.
      lastWriteTime*: times.Time        ## Time file was last modified/written to.
      creationTime*: times.Time         ## Time file was created. Not supported on all systems!
      blockSize*: int                   ## Preferred I/O block size for this object.
                                        ## In some filesystems, this may vary from file to file.
      isSpecial*: bool                  ## Is file special? (on Unix some "files"
                                        ## can be special=non-regular like FIFOs,
                                        ## devices); for directories `isSpecial`
                                        ## is always `false`, for symlinks it is
                                        ## the same as for the link's target.

  template rawToFormalFileInfo(rawInfo, path, formalInfo): untyped =
    ## Transforms the native file info structure into the one nim uses.
    ## 'rawInfo' is either a 'BY_HANDLE_FILE_INFORMATION' structure on Windows,
    ## or a 'Stat' structure on posix
    when defined(windows):
      template merge[T](a, b): untyped =
         cast[T](
          (uint64(cast[uint32](a))) or
          (uint64(cast[uint32](b)) shl 32)
         )
      formalInfo.id.device = rawInfo.dwVolumeSerialNumber
      formalInfo.id.file = merge[FileId](rawInfo.nFileIndexLow, rawInfo.nFileIndexHigh)
      formalInfo.size = merge[BiggestInt](rawInfo.nFileSizeLow, rawInfo.nFileSizeHigh)
      formalInfo.linkCount = rawInfo.nNumberOfLinks
      formalInfo.lastAccessTime = fromWinTime(rdFileTime(rawInfo.ftLastAccessTime))
      formalInfo.lastWriteTime = fromWinTime(rdFileTime(rawInfo.ftLastWriteTime))
      formalInfo.creationTime = fromWinTime(rdFileTime(rawInfo.ftCreationTime))
      formalInfo.blockSize = 8192 # xxx use Windows API instead of hardcoding

      # Retrieve basic permissions
      if (rawInfo.dwFileAttributes and FILE_ATTRIBUTE_READONLY) != 0'i32:
        formalInfo.permissions = {fpUserExec, fpUserRead, fpGroupExec,
                                  fpGroupRead, fpOthersExec, fpOthersRead}
      else:
        formalInfo.permissions = {fpUserExec..fpOthersRead}

      # Retrieve basic file kind
      if (rawInfo.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) != 0'i32:
        formalInfo.kind = pcDir
      else:
        formalInfo.kind = pcFile
      if (rawInfo.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT) != 0'i32:
        formalInfo.kind = succ(formalInfo.kind)

    else:
      template checkAndIncludeMode(rawMode, formalMode: untyped) =
        if (rawInfo.st_mode and rawMode.Mode) != 0.Mode:
          formalInfo.permissions.incl(formalMode)
      formalInfo.id = (rawInfo.st_dev, rawInfo.st_ino)
      formalInfo.size = rawInfo.st_size
      formalInfo.linkCount = rawInfo.st_nlink.BiggestInt
      formalInfo.lastAccessTime = rawInfo.st_atim.toTime
      formalInfo.lastWriteTime = rawInfo.st_mtim.toTime
      formalInfo.creationTime = rawInfo.st_ctim.toTime
      formalInfo.blockSize = rawInfo.st_blksize

      formalInfo.permissions = {}
      checkAndIncludeMode(S_IRUSR, fpUserRead)
      checkAndIncludeMode(S_IWUSR, fpUserWrite)
      checkAndIncludeMode(S_IXUSR, fpUserExec)

      checkAndIncludeMode(S_IRGRP, fpGroupRead)
      checkAndIncludeMode(S_IWGRP, fpGroupWrite)
      checkAndIncludeMode(S_IXGRP, fpGroupExec)

      checkAndIncludeMode(S_IROTH, fpOthersRead)
      checkAndIncludeMode(S_IWOTH, fpOthersWrite)
      checkAndIncludeMode(S_IXOTH, fpOthersExec)

      (formalInfo.kind, formalInfo.isSpecial) =
        if S_ISDIR(rawInfo.st_mode):
          (pcDir, false)
        elif S_ISLNK(rawInfo.st_mode):
          assert(path != "") # symlinks can't occur for file handles
          getSymlinkFileKind(path)
        else:
          (pcFile, not S_ISREG(rawInfo.st_mode))

  proc getFileInfo*(handle: FileHandle): FileInfo {.noWeirdTarget.} =
    ## Retrieves file information for the file object represented by the given
    ## handle.
    ##
    ## If the information cannot be retrieved, such as when the file handle
    ## is invalid, `OSError` is raised.
    ##
    ## See also:
    ## * `getFileInfo(file) proc`_
    ## * `getFileInfo(path, followSymlink) proc`_

    # Done: ID, Kind, Size, Permissions, Link Count
    result = default(FileInfo)
    when defined(windows):
      var rawInfo: BY_HANDLE_FILE_INFORMATION
      # We have to use the super special '_get_osfhandle' call (wrapped above)
      # To transform the C file descriptor to a native file handle.
      var realHandle = get_osfhandle(handle)
      if getFileInformationByHandle(realHandle, addr rawInfo) == 0:
        raiseOSError(osLastError(), $handle)
      rawToFormalFileInfo(rawInfo, "", result)
    else:
      var rawInfo: Stat = default(Stat)
      if fstat(handle, rawInfo) < 0'i32:
        raiseOSError(osLastError(), $handle)
      rawToFormalFileInfo(rawInfo, "", result)

  proc getFileInfo*(file: File): FileInfo {.noWeirdTarget.} =
    ## Retrieves file information for the file object.
    ##
    ## See also:
    ## * `getFileInfo(handle) proc`_
    ## * `getFileInfo(path, followSymlink) proc`_
    if file.isNil:
      raise newException(IOError, "File is nil")
    result = getFileInfo(file.getFileHandle())

  proc getFileInfo*(path: string, followSymlink = true): FileInfo {.noWeirdTarget.} =
    ## Retrieves file information for the file object pointed to by `path`.
    ##
    ## Due to intrinsic differences between operating systems, the information
    ## contained by the returned `FileInfo object`_ will be slightly
    ## different across platforms, and in some cases, incomplete or inaccurate.
    ##
    ## When `followSymlink` is true (default), symlinks are followed and the
    ## information retrieved is information related to the symlink's target.
    ## Otherwise, information on the symlink itself is retrieved (however,
    ## field `isSpecial` is still determined from the target on Unix).
    ##
    ## If the information cannot be retrieved, such as when the path doesn't
    ## exist, or when permission restrictions prevent the program from retrieving
    ## file information, `OSError` is raised.
    ##
    ## See also:
    ## * `getFileInfo(handle) proc`_
    ## * `getFileInfo(file) proc`_
    result = default(FileInfo)
    when defined(windows):
      var
        handle = openHandle(path, followSymlink)
        rawInfo: BY_HANDLE_FILE_INFORMATION
      if handle == INVALID_HANDLE_VALUE:
        raiseOSError(osLastError(), path)
      if getFileInformationByHandle(handle, addr rawInfo) == 0:
        raiseOSError(osLastError(), path)
      rawToFormalFileInfo(rawInfo, path, result)
      discard closeHandle(handle)
    else:
      var rawInfo: Stat = default(Stat)
      if followSymlink:
        if stat(path, rawInfo) < 0'i32:
          raiseOSError(osLastError(), path)
      else:
        if lstat(path, rawInfo) < 0'i32:
          raiseOSError(osLastError(), path)
      rawToFormalFileInfo(rawInfo, path, result)

  proc sameFileContent*(path1, path2: string): bool {.rtl, extern: "nos$1",
    tags: [ReadIOEffect], noWeirdTarget.} =
    ## Returns true if both pathname arguments refer to files with identical
    ## binary content.
    ##
    ## See also:
    ## * `sameFile proc`_
    result = false
    var
      a, b: File = default(File)
    if not open(a, path1): return false
    if not open(b, path2):
      close(a)
      return false
    let bufSize = getFileInfo(a).blockSize
    var bufA = alloc(bufSize)
    var bufB = alloc(bufSize)
    while true:
      var readA = readBuffer(a, bufA, bufSize)
      var readB = readBuffer(b, bufB, bufSize)
      if readA != readB:
        result = false
        break
      if readA == 0:
        result = true
        break
      result = equalMem(bufA, bufB, readA)
      if not result: break
      if readA != bufSize: break # end of file
    dealloc(bufA)
    dealloc(bufB)
    close(a)
    close(b)

  proc getCurrentProcessId*(): int {.noWeirdTarget.} =
    ## Return current process ID.
    ##
    ## See also:
    ## * `osproc.processID(p: Process) <osproc.html#processID,Process>`_
    when defined(windows):
      proc GetCurrentProcessId(): DWORD {.stdcall, dynlib: "kernel32",
                                          importc: "GetCurrentProcessId".}
      result = GetCurrentProcessId().int
    else:
      result = getpid()

  proc setLastModificationTime*(file: string, t: times.Time) {.noWeirdTarget.} =
    ## Sets the `file`'s last modification time. `OSError` is raised in case of
    ## an error.
    when defined(posix):
      let unixt = posix.Time(t.toUnix)
      let micro = convert(Nanoseconds, Microseconds, t.nanosecond)
      var timevals = [Timeval(tv_sec: unixt, tv_usec: micro),
        Timeval(tv_sec: unixt, tv_usec: micro)] # [last access, last modification]
      if utimes(file, timevals.addr) != 0: raiseOSError(osLastError(), file)
    else:
      let h = openHandle(path = file, writeAccess = true)
      if h == INVALID_HANDLE_VALUE: raiseOSError(osLastError(), file)
      var ft = t.toWinTime.toFILETIME
      let res = setFileTime(h, nil, nil, ft.addr)
      discard h.closeHandle
      if res == 0'i32: raiseOSError(osLastError(), file)

proc isHidden*(path: string): bool {.noWeirdTarget.} =
  ## Determines whether ``path`` is hidden or not, using `this
  ## reference <https://en.wikipedia.org/wiki/Hidden_file_and_hidden_directory>`_.
  ##
  ## On Windows: returns true if it exists and its "hidden" attribute is set.
  ##
  ## On posix: returns true if ``lastPathPart(path)`` starts with ``.`` and is
  ## not ``.`` or ``..``.
  ##
  ## **Note**: paths are not normalized to determine `isHidden`.
  runnableExamples:
    when defined(posix):
      assert ".foo".isHidden
      assert not ".foo/bar".isHidden
      assert not ".".isHidden
      assert not "..".isHidden
      assert not "".isHidden
      assert ".foo/".isHidden

  when defined(windows):
    wrapUnary(attributes, getFileAttributesW, path)
    if attributes != -1'i32:
      result = (attributes and FILE_ATTRIBUTE_HIDDEN) != 0'i32
  else:
    let fileName = lastPathPart(path)
    result = len(fileName) >= 2 and fileName[0] == '.' and fileName != ".."


func isValidFilename*(filename: string, maxLen = 259.Positive): bool {.since: (1, 1).} =
  ## Returns `true` if `filename` is valid for crossplatform use.
  ##
  ## This is useful if you want to copy or save files across Windows, Linux, Mac, etc.
  ## It uses `invalidFilenameChars`, `invalidFilenames` and `maxLen` to verify the specified `filename`.
  ##
  ## See also:
  ##
  ## * https://docs.microsoft.com/en-us/dotnet/api/system.io.pathtoolongexception
  ## * https://docs.microsoft.com/en-us/windows/win32/fileio/naming-a-file
  ## * https://msdn.microsoft.com/en-us/library/windows/desktop/aa365247%28v=vs.85%29.aspx
  ##
  ## .. warning:: This only checks filenames, not whole paths
  ##    (because basically you can mount anything as a path on Linux).
  runnableExamples:
    assert not isValidFilename(" foo")     # Leading white space
    assert not isValidFilename("foo ")     # Trailing white space
    assert not isValidFilename("foo.")     # Ends with dot
    assert not isValidFilename("con.txt")  # "CON" is invalid (Windows)
    assert not isValidFilename("OwO:UwU")  # ":" is invalid (Mac)
    assert not isValidFilename("aux.bat")  # "AUX" is invalid (Windows)
    assert not isValidFilename("")         # Empty string
    assert not isValidFilename("foo/")     # Filename is empty

  result = true
  let f = filename.splitFile()
  if unlikely(f.name.len + f.ext.len > maxLen or f.name.len == 0 or
    f.name[0] == ' ' or f.name[^1] == ' ' or f.name[^1] == '.' or
    find(f.name, invalidFilenameChars) != -1): return false
  for invalid in invalidFilenames:
    if cmpIgnoreCase(f.name, invalid) == 0: return false


# deprecated declarations
when not weirdTarget:
  template existsFile*(args: varargs[untyped]): untyped {.deprecated: "use fileExists".} =
    fileExists(args)
  template existsDir*(args: varargs[untyped]): untyped {.deprecated: "use dirExists".} =
    dirExists(args)

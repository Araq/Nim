#
#
#            Nim's Runtime Library
#        (c) Copyright 2021 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module creates temporary files and directories.
##
## Experimental API, subject to change.

#[
See also:
* `GetTempFileName` (on windows), refs https://docs.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-gettempfilenamea
* `mkstemp` (posix), refs https://man7.org/linux/man-pages/man3/mkstemp.3.html
]#

import std / [os, random]

when defined(nimPreviewSlimSystem):
  import std/syncio

const
  maxRetry = 10000
  letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  nimTempPathLength {.intdefine.} = 8


when defined(windows):
  import std/winlean
  when defined(nimPreviewSlimSystem):
    import std/widestrs

  var O_RDWR {.importc: "_O_RDWR", header: "<fcntl.h>".}: cint

  proc c_fdopen(
    filehandle: cint,
    mode: cstring
  ): File {.importc: "_fdopen",header: "<stdio.h>".}

  proc open_osfhandle(osh: Handle, mode: cint): cint {.
    importc: "_open_osfhandle", header: "<io.h>".}

  proc close_osfandle(fd: cint): cint {.
    importc: "_close", header: "<io.h>".}
else:
  import std/posix

  proc c_fdopen(
    filehandle: cint,
    mode: cstring
  ): File {.importc: "fdopen",header: "<stdio.h>".}


proc safeOpen(filename: string): File =
  ## Open files exclusively; returns `nil` if the file already exists.
  # xxx this should be clarified; it doesn't in particular prevent other processes
  # from opening the file, at least currently.
  when defined(windows):
    let dwShareMode = FILE_SHARE_DELETE or FILE_SHARE_READ or FILE_SHARE_WRITE
    let dwCreation = CREATE_NEW
    let dwFlags = FILE_FLAG_BACKUP_SEMANTICS or FILE_ATTRIBUTE_NORMAL
    let handle = createFileW(newWideCString(filename), GENERIC_READ or GENERIC_WRITE, dwShareMode,
                              nil, dwCreation, dwFlags, Handle(0))

    if handle == INVALID_HANDLE_VALUE:
      if getLastError() == ERROR_FILE_EXISTS:
        return nil
      else:
        raiseOSError(osLastError(), filename)

    let fileHandle = open_osfhandle(handle, O_RDWR)
    if fileHandle == -1:
      discard closeHandle(handle)
      raiseOSError(osLastError(), filename)

    result = c_fdopen(fileHandle, "w+")
    if result == nil:
      discard close_osfandle(fileHandle)
      raiseOSError(osLastError(), filename)
  else:
    # xxx we need a `proc toMode(a: FilePermission): Mode`, possibly by
    # exposing fusion/filepermissions.fromFilePermissions to stdlib; then we need
    # to expose a `perm` param so users can customize this (e.g. the temp file may
    # need execute permissions), and figure out how to make the API cross platform.
    let mode = Mode(S_IRUSR or S_IWUSR)
    let flags = posix.O_RDWR or posix.O_CREAT or posix.O_EXCL
    let fileHandle = posix.open(filename, flags, mode)
    if fileHandle == -1:
      if errno == EEXIST:
        # xxx `getLastError()` should be defined on posix too and resolve to `errno`?
        return nil
      else:
        raiseOSError(osLastError(), filename)

    result = c_fdopen(fileHandle, "w+")
    if result == nil:
      discard posix.close(fileHandle) # TODO handles failure when closing file
      raiseOSError(osLastError(), filename)


type
  NimTempPathState = object
    state: Rand
    isInit: bool

var nimTempPathState {.threadvar.}: NimTempPathState

template randomPathName(length: Natural): string =
  var res = newString(length)
  if not nimTempPathState.isInit:
    nimTempPathState.isInit = true
    nimTempPathState.state = initRand()

  for i in 0 ..< length:
    res[i] = nimTempPathState.state.sample(letters)
  res

proc getTempDirImpl(dir: string): string {.inline.} =
  result = dir
  if result.len == 0:
    result = getTempDir()

proc genTempPath*(prefix, suffix: string, dir = ""): string =
  ## Generates a path name in `dir`.
  ##
  ## The path begins with `prefix` and ends with `suffix`.
  ##
  ## .. note:: `dir` must exist (empty `dir` will resolve to `getTempDir <appdirs.html#getTempDir>`_).
  let dir = getTempDirImpl(dir)
  result = dir / (prefix & randomPathName(nimTempPathLength) & suffix)

proc createTempFile*(prefix, suffix: string, dir = ""): tuple[cfile: File, path: string] =
  ## Creates a new temporary file in the directory `dir`.
  ##
  ## This generates a path name using `genTempPath(prefix, suffix, dir)` and
  ## returns a file handle to an open file and the path of that file, possibly after
  ## retrying to ensure it doesn't already exist.
  ##
  ## If failing to create a temporary file, `OSError` will be raised.
  ##
  ## .. note:: It is the caller's responsibility to close `result.cfile` and
  ##    remove `result.file` when no longer needed.
  ## .. note:: `dir` must exist (empty `dir` will resolve to `getTempDir <appdirs.html#getTempDir>`_).
  runnableExamples:
    import std/os
    doAssertRaises(OSError): discard createTempFile("", "", "nonexistent")
    let (cfile, path) = createTempFile("tmpprefix_", "_end.tmp")
    # path looks like: getTempDir() / "tmpprefix_FDCIRZA0_end.tmp"
    cfile.write "foo"
    cfile.setFilePos 0
    assert readAll(cfile) == "foo"
    close cfile
    assert readFile(path) == "foo"
    removeFile(path)
  # xxx why does above work without `cfile.flushFile` ?
  result = default(tuple[cfile: File, path: string])
  let dir = getTempDirImpl(dir)
  for i in 0 ..< maxRetry:
    result.path = genTempPath(prefix, suffix, dir)
    result.cfile = safeOpen(result.path)
    if result.cfile != nil:
      return

  raise newException(OSError, "Failed to create a temporary file under directory " & dir)

proc createTempDir*(prefix, suffix: string, dir = ""): string =
  ## Creates a new temporary directory in the directory `dir`.
  ##
  ## This generates a dir name using `genTempPath(prefix, suffix, dir)`, creates
  ## the directory and returns it, possibly after retrying to ensure it doesn't
  ## already exist.
  ##
  ## If failing to create a temporary directory, `OSError` will be raised.
  ##
  ## .. note:: It is the caller's responsibility to remove the directory when no longer needed.
  ## .. note:: `dir` must exist (empty `dir` will resolve to `getTempDir <appdirs.html#getTempDir>`_).
  runnableExamples:
    import std/os
    doAssertRaises(OSError): discard createTempDir("", "", "nonexistent")
    let dir = createTempDir("tmpprefix_", "_end")
    # dir looks like: getTempDir() / "tmpprefix_YEl9VuVj_end"
    assert dirExists(dir)
    removeDir(dir)
  let dir = getTempDirImpl(dir)
  for i in 0 ..< maxRetry:
    result = genTempPath(prefix, suffix, dir)
    if not existsOrCreateDir(result):
      return

  raise newException(OSError, "Failed to create a temporary directory under directory " & dir)

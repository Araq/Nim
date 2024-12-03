#
#            Nim's Runtime Library
#    (c) Copyright 2019 Federico Ceratto and other Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## A set of helpers for the POSIX module.
## Raw interfaces are in the other ``posix*.nim`` files.

# Where possible, contribute OS-independent procs in `os <os.html>`_ instead.

import std/[posix, parsecfg, os]
import std/private/since

when defined(nimPreviewSlimSystem):
  import std/syncio

type Uname* = object
  sysname*, nodename*, release*, version*, machine*: string

template charArrayToString(input: typed): string =
  $cast[cstring](addr input)

proc uname*(): Uname =
  ## Provides system information in a `Uname` struct with sysname, nodename,
  ## release, version and machine attributes.

  when defined(posix):
    runnableExamples:
      echo uname().nodename, uname().release, uname().version
      doAssert uname().sysname.len != 0

  var u: Utsname
  if uname(u) != 0:
    raiseOSError(OSErrorCode(errno))

  result.sysname = charArrayToString u.sysname
  result.nodename = charArrayToString u.nodename
  result.release = charArrayToString u.release
  result.version = charArrayToString u.version
  result.machine = charArrayToString u.machine

proc fsync*(fd: int) =
  ## synchronize a file's buffer cache to the storage device
  if fsync(fd.cint) != 0:
    raiseOSError(OSErrorCode(errno))

proc stat*(path: string): Stat =
  ## Returns file status in a `Stat` structure
  if stat(path.cstring, result) != 0:
    raiseOSError(OSErrorCode(errno))

proc memoryLock*(a1: pointer, a2: int) =
  ## Locks pages starting from a1 for a1 bytes and prevent them from being swapped.
  if mlock(a1, a2) != 0:
    raiseOSError(OSErrorCode(errno))

proc memoryLockAll*(flags: int) =
  ## Locks all memory for the running process to prevent swapping.
  ##
  ## example:
  ##   ```nim
  ##   memoryLockAll(MCL_CURRENT or MCL_FUTURE)
  ##   ```
  if mlockall(flags.cint) != 0:
    raiseOSError(OSErrorCode(errno))

proc memoryUnlock*(a1: pointer, a2: int) =
  ## Unlock pages starting from a1 for a1 bytes and allow them to be swapped.
  if munlock(a1, a2) != 0:
    raiseOSError(OSErrorCode(errno))

proc memoryUnlockAll*() =
  ## Unlocks all memory for the running process to allow swapping.
  if munlockall() != 0:
    raiseOSError(OSErrorCode(errno))

proc sendSignal*(pid: Pid, signal: int) =
  ## Sends a signal to a running process by calling `kill`.
  ## Raise exception in case of failure e.g. process not running.
  if kill(pid, signal.cint) != 0:
    raiseOSError(OSErrorCode(errno))

proc mkstemp*(prefix: string, suffix=""): (string, File) =
  ## Creates a unique temporary file from a prefix string. A six-character string
  ## will be added. If suffix is provided it will be added to the string
  ## The file is created with perms 0600.
  ## Returns the filename and a file opened in r/w mode.
  var tmpl = cstring(prefix & "XXXXXX" & suffix)
  let fd =
    if len(suffix) == 0:
      when declared(mkostemp):
        mkostemp(tmpl, O_CLOEXEC)
      else:
        mkstemp(tmpl)
    else:
      when declared(mkostemps):
        mkostemps(tmpl, cint(len(suffix)), O_CLOEXEC)
      else:
        mkstemps(tmpl, cint(len(suffix)))
  var f: File
  if open(f, fd, fmReadWrite):
    return ($tmpl, f)
  raiseOSError(OSErrorCode(errno))

proc mkdtemp*(prefix: string): string =
  ## Creates a unique temporary directory from a prefix string. Adds a six chars suffix.
  ## The directory is created with permissions 0700. Returns the directory name.
  var tmpl = cstring(prefix & "XXXXXX")
  if mkdtemp(tmpl) == nil:
    raiseOSError(OSErrorCode(errno))
  return $tmpl

proc osReleaseFile*(): Config {.since: (1, 5).} =
  ## Gets system identification from `os-release` file and returns it as a `parsecfg.Config`.
  ## You also need to import the `parsecfg` module to gain access to this object.
  ## The `os-release` file is an official Freedesktop.org open standard.
  ## Available in Linux and BSD distributions, except Android and Android-based Linux.
  ## `os-release` file is not available on Windows and OS X by design.
  ## * https://www.freedesktop.org/software/systemd/man/os-release.html
  runnableExamples:
    import std/parsecfg
    when defined(linux):
      let data = osReleaseFile()
      echo "OS name: ", data.getSectionValue("", "NAME") ## the data is up to each distro.

  # We do not use a {.strdefine.} because Standard says it *must* be that path.
  for osReleaseFile in ["/etc/os-release", "/usr/lib/os-release"]:
    if fileExists(osReleaseFile):
      return loadConfig(osReleaseFile)
  raise newException(IOError, "File not found: /etc/os-release, /usr/lib/os-release")

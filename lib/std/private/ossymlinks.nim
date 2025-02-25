include system/inclrtl
import std/oserrors

import oscommon
when supportedSystem:
  export symlinkExists

when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions, widestrs]

when weirdTarget:
  discard
elif defined(windows):
  import std/[winlean, times]
elif defined(posix):
  import std/posix


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

## .. importdoc:: os.nim

proc createSymlink*(src, dest: string) {.noWeirdTarget.} =
  ## Create a symbolic link at `dest` which points to the item specified
  ## by `src`. On most operating systems, will fail if a link already exists.
  ##
  ## .. warning:: Some OS's (such as Microsoft Windows) restrict the creation
  ##   of symlinks to root users (administrators) or users with developer mode enabled.
  ##
  ## See also:
  ## * `createHardlink proc`_
  ## * `expandSymlink proc`_

  when defined(windows):
    const SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE = 2
    # allows anyone with developer mode on to create a link
    let flag = dirExists(src).int32 or SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE
    var wSrc = newWideCString(src)
    var wDst = newWideCString(dest)
    if createSymbolicLinkW(wDst, wSrc, flag) == 0 or getLastError() != 0:
      raiseOSError(osLastError(), $(src, dest))
  else:
    if symlink(src, dest) != 0:
      raiseOSError(osLastError(), $(src, dest))

proc expandSymlink*(symlinkPath: string): string {.noWeirdTarget.} =
  ## Returns a string representing the path to which the symbolic link points.
  ##
  ## On Windows this is a noop, `symlinkPath` is simply returned.
  ##
  ## See also:
  ## * `createSymlink proc`_
  when defined(windows) or defined(nintendoswitch):
    result = symlinkPath
  else:
    var bufLen = 1024
    while true:
      result = newString(bufLen)
      let len = readlink(symlinkPath.cstring, result.cstring, bufLen)
      if len < 0:
        raiseOSError(osLastError(), symlinkPath)
      if len < bufLen:
        result.setLen(len)
        break
      bufLen = bufLen shl 1

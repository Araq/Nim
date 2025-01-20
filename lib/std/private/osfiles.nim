include system/inclrtl
import std/private/since
import std/oserrors

import oscommon
export fileExists

import ospaths2, ossymlinks

## .. importdoc:: osdirs.nim, os.nim

when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions, widestrs]

when weirdTarget:
  discard
elif defined(windows):
  import std/winlean
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


type
  FilePermission* = enum   ## File access permission, modelled after UNIX.
    ##
    ## See also:
    ## * `getFilePermissions`_
    ## * `setFilePermissions`_
    ## * `FileInfo object`_
    fpUserExec,            ## execute access for the file owner
    fpUserWrite,           ## write access for the file owner
    fpUserRead,            ## read access for the file owner
    fpGroupExec,           ## execute access for the group
    fpGroupWrite,          ## write access for the group
    fpGroupRead,           ## read access for the group
    fpOthersExec,          ## execute access for others
    fpOthersWrite,         ## write access for others
    fpOthersRead           ## read access for others

proc getFilePermissions*(filename: string): set[FilePermission] {.
  rtl, extern: "nos$1", tags: [ReadDirEffect], noWeirdTarget.} =
  ## Retrieves file permissions for `filename`.
  ##
  ## `OSError` is raised in case of an error.
  ## On Windows, only the ``readonly`` flag is checked, every other
  ## permission is available in any case.
  ##
  ## See also:
  ## * `setFilePermissions proc`_
  ## * `FilePermission enum`_
  when defined(posix):
    var a: Stat
    if stat(filename, a) < 0'i32: raiseOSError(osLastError(), filename)
    result = {}
    if (a.st_mode and S_IRUSR.Mode) != 0.Mode: result.incl(fpUserRead)
    if (a.st_mode and S_IWUSR.Mode) != 0.Mode: result.incl(fpUserWrite)
    if (a.st_mode and S_IXUSR.Mode) != 0.Mode: result.incl(fpUserExec)

    if (a.st_mode and S_IRGRP.Mode) != 0.Mode: result.incl(fpGroupRead)
    if (a.st_mode and S_IWGRP.Mode) != 0.Mode: result.incl(fpGroupWrite)
    if (a.st_mode and S_IXGRP.Mode) != 0.Mode: result.incl(fpGroupExec)

    if (a.st_mode and S_IROTH.Mode) != 0.Mode: result.incl(fpOthersRead)
    if (a.st_mode and S_IWOTH.Mode) != 0.Mode: result.incl(fpOthersWrite)
    if (a.st_mode and S_IXOTH.Mode) != 0.Mode: result.incl(fpOthersExec)
  else:
    wrapUnary(res, getFileAttributesW, filename)
    if res == -1'i32: raiseOSError(osLastError(), filename)
    if (res and FILE_ATTRIBUTE_READONLY) != 0'i32:
      result = {fpUserExec, fpUserRead, fpGroupExec, fpGroupRead,
                fpOthersExec, fpOthersRead}
    else:
      result = {fpUserExec..fpOthersRead}

proc setFilePermissions*(filename: string, permissions: set[FilePermission],
                         followSymlinks = true)
  {.rtl, extern: "nos$1", tags: [ReadDirEffect, WriteDirEffect],
   noWeirdTarget.} =
  ## Sets the file permissions for `filename`.
  ##
  ## If `followSymlinks` set to true (default) and ``filename`` points to a
  ## symlink, permissions are set to the file symlink points to.
  ## `followSymlinks` set to false is a noop on Windows and some POSIX
  ## systems (including Linux) on which `lchmod` is either unavailable or always
  ## fails, given that symlinks permissions there are not observed.
  ##
  ## `OSError` is raised in case of an error.
  ## On Windows, only the ``readonly`` flag is changed, depending on
  ## ``fpUserWrite`` permission.
  ##
  ## See also:
  ## * `getFilePermissions proc`_
  ## * `FilePermission enum`_
  when defined(posix):
    var p = 0.Mode
    if fpUserRead in permissions: p = p or S_IRUSR.Mode
    if fpUserWrite in permissions: p = p or S_IWUSR.Mode
    if fpUserExec in permissions: p = p or S_IXUSR.Mode

    if fpGroupRead in permissions: p = p or S_IRGRP.Mode
    if fpGroupWrite in permissions: p = p or S_IWGRP.Mode
    if fpGroupExec in permissions: p = p or S_IXGRP.Mode

    if fpOthersRead in permissions: p = p or S_IROTH.Mode
    if fpOthersWrite in permissions: p = p or S_IWOTH.Mode
    if fpOthersExec in permissions: p = p or S_IXOTH.Mode

    if not followSymlinks and filename.symlinkExists:
      when declared(lchmod):
        if lchmod(filename, cast[Mode](p)) != 0:
          raiseOSError(osLastError(), $(filename, permissions))
    else:
      if chmod(filename, cast[Mode](p)) != 0:
        raiseOSError(osLastError(), $(filename, permissions))
  else:
    wrapUnary(res, getFileAttributesW, filename)
    if res == -1'i32: raiseOSError(osLastError(), filename)
    if fpUserWrite in permissions:
      res = res and not FILE_ATTRIBUTE_READONLY
    else:
      res = res or FILE_ATTRIBUTE_READONLY
    wrapBinary(res2, setFileAttributesW, filename, res)
    if res2 == - 1'i32: raiseOSError(osLastError(), $(filename, permissions))


const hasCCopyfile = defined(osx) and not defined(nimLegacyCopyFile)
  # xxx instead of `nimLegacyCopyFile`, support something like: `when osxVersion >= (10, 5)`

when hasCCopyfile:
  # `copyfile` API available since osx 10.5.
  {.push nodecl, header: "<copyfile.h>".}
  type
    copyfile_state_t {.nodecl.} = pointer
    copyfile_flags_t = cint
  proc copyfile_state_alloc(): copyfile_state_t
  proc copyfile_state_free(state: copyfile_state_t): cint
  proc c_copyfile(src, dst: cstring,  state: copyfile_state_t, flags: copyfile_flags_t): cint {.importc: "copyfile".}
  when (NimMajor, NimMinor) >= (1, 4):
    let
      COPYFILE_DATA {.nodecl.}: copyfile_flags_t
      COPYFILE_XATTR {.nodecl.}: copyfile_flags_t
  else:
    var
      COPYFILE_DATA {.nodecl.}: copyfile_flags_t
      COPYFILE_XATTR {.nodecl.}: copyfile_flags_t
  {.pop.}

type
  CopyFlag* = enum    ## Copy options.
    cfSymlinkAsIs,    ## Copy symlinks as symlinks
    cfSymlinkFollow,  ## Copy the files symlinks point to
    cfSymlinkIgnore   ## Ignore symlinks

const copyFlagSymlink = {cfSymlinkAsIs, cfSymlinkFollow, cfSymlinkIgnore}

proc copyFile*(source, dest: string, options = {cfSymlinkFollow}; bufferSize = 16_384) {.rtl,
  extern: "nos$1", tags: [ReadDirEffect, ReadIOEffect, WriteIOEffect],
  noWeirdTarget.} =
  ## Copies a file from `source` to `dest`, where `dest.parentDir` must exist.
  ##
  ## On non-Windows OSes, `options` specify the way file is copied; by default,
  ## if `source` is a symlink, copies the file symlink points to. `options` is
  ## ignored on Windows: symlinks are skipped.
  ##
  ## If this fails, `OSError` is raised.
  ##
  ## On the Windows platform this proc will
  ## copy the source file's attributes into dest.
  ##
  ## On other platforms you need
  ## to use `getFilePermissions`_ and
  ## `setFilePermissions`_
  ## procs
  ## to copy them by hand (or use the convenience `copyFileWithPermissions
  ## proc`_),
  ## otherwise `dest` will inherit the default permissions of a newly
  ## created file for the user.
  ##
  ## If `dest` already exists, the file attributes
  ## will be preserved and the content overwritten.
  ##
  ## On OSX, `copyfile` C api will be used (available since OSX 10.5) unless
  ## `-d:nimLegacyCopyFile` is used.
  ##
  ## `copyFile` allows to specify `bufferSize` to improve I/O performance.
  ##
  ## See also:
  ## * `CopyFlag enum`_
  ## * `copyDir proc`_
  ## * `copyFileWithPermissions proc`_
  ## * `tryRemoveFile proc`_
  ## * `removeFile proc`_
  ## * `moveFile proc`_

  doAssert card(copyFlagSymlink * options) == 1, "There should be exactly one cfSymlink* in options"
  let isSymlink = source.symlinkExists
  if isSymlink and (cfSymlinkIgnore in options or defined(windows)):
    return
  when defined(windows):
    let s = newWideCString(source)
    let d = newWideCString(dest)
    if copyFileW(s, d, 0'i32) == 0'i32:
      raiseOSError(osLastError(), $(source, dest))
  else:
    if isSymlink and cfSymlinkAsIs in options:
      createSymlink(expandSymlink(source), dest)
    else:
      when hasCCopyfile:
        let state = copyfile_state_alloc()
        # xxx `COPYFILE_STAT` could be used for one-shot
        # `copyFileWithPermissions`.
        let status = c_copyfile(source.cstring, dest.cstring, state,
                                COPYFILE_DATA)
        if status != 0:
          let err = osLastError()
          discard copyfile_state_free(state)
          raiseOSError(err, $(source, dest))
        let status2 = copyfile_state_free(state)
        if status2 != 0: raiseOSError(osLastError(), $(source, dest))
      else:
        # generic version of copyFile which works for any platform:
        var d, s: File
        if not open(s, source): raiseOSError(osLastError(), source)
        if not open(d, dest, fmWrite):
          close(s)
          raiseOSError(osLastError(), dest)

        # Hints for kernel-level aggressive sequential low-fragmentation read-aheads:
        # https://pubs.opengroup.org/onlinepubs/9699919799/functions/posix_fadvise.html
        when defined(linux) or defined(osx):
          discard posix_fadvise(getFileHandle(d), 0.cint, 0.cint, POSIX_FADV_SEQUENTIAL)
          discard posix_fadvise(getFileHandle(s), 0.cint, 0.cint, POSIX_FADV_SEQUENTIAL)

        var buf = alloc(bufferSize)
        while true:
          var bytesread = readBuffer(s, buf, bufferSize)
          if bytesread > 0:
            var byteswritten = writeBuffer(d, buf, bytesread)
            if bytesread != byteswritten:
              dealloc(buf)
              close(s)
              close(d)
              raiseOSError(osLastError(), dest)
          if bytesread != bufferSize: break
        dealloc(buf)
        close(s)
        flushFile(d)
        close(d)

proc copyFileToDir*(source, dir: string, options = {cfSymlinkFollow}; bufferSize = 16_384)
  {.noWeirdTarget, since: (1,3,7).} =
  ## Copies a file `source` into directory `dir`, which must exist.
  ##
  ## On non-Windows OSes, `options` specify the way file is copied; by default,
  ## if `source` is a symlink, copies the file symlink points to. `options` is
  ## ignored on Windows: symlinks are skipped.
  ##
  ## `copyFileToDir` allows to specify `bufferSize` to improve I/O performance.
  ##
  ## See also:
  ## * `CopyFlag enum`_
  ## * `copyFile proc`_
  if dir.len == 0: # treating "" as "." is error prone
    raise newException(ValueError, "dest is empty")
  copyFile(source, dir / source.lastPathPart, options, bufferSize)


proc copyFileWithPermissions*(source, dest: string,
                              ignorePermissionErrors = true,
                              options = {cfSymlinkFollow}) {.noWeirdTarget.} =
  ## Copies a file from `source` to `dest` preserving file permissions.
  ##
  ## On non-Windows OSes, `options` specify the way file is copied; by default,
  ## if `source` is a symlink, copies the file symlink points to. `options` is
  ## ignored on Windows: symlinks are skipped.
  ##
  ## This is a wrapper proc around `copyFile`_,
  ## `getFilePermissions`_ and `setFilePermissions`_
  ## procs on non-Windows platforms.
  ##
  ## On Windows this proc is just a wrapper for `copyFile proc`_ since
  ## that proc already copies attributes.
  ##
  ## On non-Windows systems permissions are copied after the file itself has
  ## been copied, which won't happen atomically and could lead to a race
  ## condition. If `ignorePermissionErrors` is true (default), errors while
  ## reading/setting file attributes will be ignored, otherwise will raise
  ## `OSError`.
  ##
  ## See also:
  ## * `CopyFlag enum`_
  ## * `copyFile proc`_
  ## * `copyDir proc`_
  ## * `tryRemoveFile proc`_
  ## * `removeFile proc`_
  ## * `moveFile proc`_
  ## * `copyDirWithPermissions proc`_
  copyFile(source, dest, options)
  when not defined(windows):
    try:
      setFilePermissions(dest, getFilePermissions(source), followSymlinks =
                         (cfSymlinkFollow in options))
    except:
      if not ignorePermissionErrors:
        raise

when not declared(ENOENT) and not defined(windows):
  when defined(nimscript):
    when not defined(haiku):
      const ENOENT = cint(2) # 2 on most systems including Solaris
    else:
      const ENOENT = cint(-2147459069)
  else:
    var ENOENT {.importc, header: "<errno.h>".}: cint

when defined(windows) and not weirdTarget:
  template deleteFile(file: untyped): untyped  = deleteFileW(file)
  template setFileAttributes(file, attrs: untyped): untyped =
    setFileAttributesW(file, attrs)

proc tryRemoveFile*(file: string): bool {.rtl, extern: "nos$1", tags: [WriteDirEffect], noWeirdTarget.} =
  ## Removes the `file`.
  ##
  ## If this fails, returns `false`. This does not fail
  ## if the file never existed in the first place.
  ##
  ## On Windows, ignores the read-only attribute.
  ##
  ## See also:
  ## * `copyFile proc`_
  ## * `copyFileWithPermissions proc`_
  ## * `removeFile proc`_
  ## * `moveFile proc`_
  result = true
  when defined(windows):
    let f = newWideCString(file)
    if deleteFile(f) == 0:
      result = false
      let err = getLastError()
      if err == ERROR_FILE_NOT_FOUND or err == ERROR_PATH_NOT_FOUND:
        result = true
      elif err == ERROR_ACCESS_DENIED and
         setFileAttributes(f, FILE_ATTRIBUTE_NORMAL) != 0 and
         deleteFile(f) != 0:
        result = true
  else:
    if unlink(file) != 0'i32 and errno != ENOENT:
      result = false

proc removeFile*(file: string) {.rtl, extern: "nos$1", tags: [WriteDirEffect], noWeirdTarget.} =
  ## Removes the `file`.
  ##
  ## If this fails, `OSError` is raised. This does not fail
  ## if the file never existed in the first place.
  ##
  ## On Windows, ignores the read-only attribute.
  ##
  ## See also:
  ## * `removeDir proc`_
  ## * `copyFile proc`_
  ## * `copyFileWithPermissions proc`_
  ## * `tryRemoveFile proc`_
  ## * `moveFile proc`_
  if not tryRemoveFile(file):
    raiseOSError(osLastError(), file)

proc moveFile*(source, dest: string) {.rtl, extern: "nos$1",
  tags: [ReadDirEffect, ReadIOEffect, WriteIOEffect], noWeirdTarget.} =
  ## Moves a file from `source` to `dest`.
  ##
  ## Symlinks are not followed: if `source` is a symlink, it is itself moved,
  ## not its target.
  ##
  ## If this fails, `OSError` is raised.
  ## If `dest` already exists, it will be overwritten.
  ##
  ## Can be used to `rename files`:idx:.
  ##
  ## See also:
  ## * `moveDir proc`_
  ## * `copyFile proc`_
  ## * `copyFileWithPermissions proc`_
  ## * `removeFile proc`_
  ## * `tryRemoveFile proc`_

  if not tryMoveFSObject(source, dest, isDir = false):
    when defined(windows):
      raiseAssert "unreachable"
    else:
      # Fallback to copy & del
      copyFileWithPermissions(source, dest, options={cfSymlinkAsIs})
      try:
        removeFile(source)
      except:
        discard tryRemoveFile(dest)
        raise

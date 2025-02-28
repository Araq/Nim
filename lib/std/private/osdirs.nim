## .. importdoc:: osfiles.nim, appdirs.nim, paths.nim

include system/inclrtl
import std/oserrors


import ospaths2, osfiles
import oscommon
import std/staticos
when supportedSystem:
  export dirExists, PathComponent


when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions, widestrs]


when weirdTarget:
  discard
elif defined(windows):
  import std/[winlean, times]
elif defined(posix):
  import std/[posix, times]


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

# Templates for filtering directories and files
when defined(windows) and not weirdTarget:
  template isDir(f: WIN32_FIND_DATA): bool =
    (f.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) != 0'i32
  template isFile(f: WIN32_FIND_DATA): bool =
    not isDir(f)
else:
  template isDir(f: string): bool {.dirty.} =
    dirExists(f)
  template isFile(f: string): bool {.dirty.} =
    fileExists(f)

template defaultWalkFilter(item): bool =
  ## Walk filter used to return true on both
  ## files and directories
  true

template walkCommon(pattern: string, filter) =
  ## Common code for getting the files and directories with the
  ## specified `pattern`
  when defined(windows):
    var
      f: WIN32_FIND_DATA
      res: int
    res = findFirstFile(pattern, f)
    if res != -1:
      defer: findClose(res)
      let dotPos = searchExtPos(pattern)
      while true:
        if not skipFindData(f) and filter(f):
          # Windows bug/gotcha: 't*.nim' matches 'tfoo.nims' -.- so we check
          # that the file extensions have the same length ...
          let ff = getFilename(f)
          let idx = ff.len - pattern.len + dotPos
          if dotPos < 0 or idx >= ff.len or (idx >= 0 and ff[idx] == '.') or
              (dotPos >= 0 and dotPos+1 < pattern.len and pattern[dotPos+1] == '*'):
            yield splitFile(pattern).dir / extractFilename(ff)
        if findNextFile(res, f) == 0'i32:
          let errCode = getLastError()
          if errCode == ERROR_NO_MORE_FILES: break
          else: raiseOSError(errCode.OSErrorCode)
  else: # here we use glob
    var
      f: Glob
      res: int
    f.gl_offs = 0
    f.gl_pathc = 0
    f.gl_pathv = nil
    res = glob(pattern, 0, nil, addr(f))
    defer: globfree(addr(f))
    if res == 0:
      for i in 0.. f.gl_pathc - 1:
        assert(f.gl_pathv[i] != nil)
        let path = $f.gl_pathv[i]
        if filter(path):
          yield path

iterator walkPattern*(pattern: string): string {.tags: [ReadDirEffect], noWeirdTarget.} =
  ## Iterate over all the files and directories that match the `pattern`.
  ##
  ## On POSIX this uses the `glob`:idx: call.
  ## `pattern` is OS dependent, but at least the `"*.ext"`
  ## notation is supported.
  ##
  ## See also:
  ## * `walkFiles iterator`_
  ## * `walkDirs iterator`_
  ## * `walkDir iterator`_
  ## * `walkDirRec iterator`_
  runnableExamples:
    import std/os
    import std/sequtils
    let paths = toSeq(walkPattern("lib/pure/*")) # works on Windows too
    assert "lib/pure/concurrency".unixToNativePath in paths
    assert "lib/pure/os.nim".unixToNativePath in paths
  walkCommon(pattern, defaultWalkFilter)

iterator walkFiles*(pattern: string): string {.tags: [ReadDirEffect], noWeirdTarget.} =
  ## Iterate over all the files that match the `pattern`.
  ##
  ## On POSIX this uses the `glob`:idx: call.
  ## `pattern` is OS dependent, but at least the `"*.ext"`
  ## notation is supported.
  ##
  ## See also:
  ## * `walkPattern iterator`_
  ## * `walkDirs iterator`_
  ## * `walkDir iterator`_
  ## * `walkDirRec iterator`_
  runnableExamples:
    import std/os
    import std/sequtils
    assert "lib/pure/os.nim".unixToNativePath in toSeq(walkFiles("lib/pure/*.nim")) # works on Windows too
  walkCommon(pattern, isFile)

iterator walkDirs*(pattern: string): string {.tags: [ReadDirEffect], noWeirdTarget.} =
  ## Iterate over all the directories that match the `pattern`.
  ##
  ## On POSIX this uses the `glob`:idx: call.
  ## `pattern` is OS dependent, but at least the `"*.ext"`
  ## notation is supported.
  ##
  ## See also:
  ## * `walkPattern iterator`_
  ## * `walkFiles iterator`_
  ## * `walkDir iterator`_
  ## * `walkDirRec iterator`_
  runnableExamples:
    import std/os
    import std/sequtils
    let paths = toSeq(walkDirs("lib/pure/*")) # works on Windows too
    assert "lib/pure/concurrency".unixToNativePath in paths
  walkCommon(pattern, isDir)

iterator walkDir*(dir: string; relative = false, checkDir = false,
                  skipSpecial = false):
  tuple[kind: PathComponent, path: string] {.tags: [ReadDirEffect].} =
  ## Walks over the directory `dir` and yields for each directory or file in
  ## `dir`. The component type and full path for each item are returned.
  ##
  ## Walking is not recursive.
  ## * If `relative` is true (default: false)
  ##   the resulting path is shortened to be relative to ``dir``,
  ##   otherwise the full path is returned.
  ## * If `checkDir` is true, `OSError` is raised when `dir`
  ##   doesn't exist.
  ## * If `skipSpecial` is true, then (besides all directories) only *regular*
  ##   files (**without** special "file" objects like FIFOs, device files,
  ##   etc) will be yielded on Unix.
  ##
  ## **Example:**
  ##
  ## This directory structure:
  ##
  ##     dirA / dirB / fileB1.txt
  ##          / dirC
  ##          / fileA1.txt
  ##          / fileA2.txt
  ##
  ## and this code:
  runnableExamples("-r:off"):
    import std/[strutils, sugar]
    # note: order is not guaranteed
    # this also works at compile time
    assert collect(for k in walkDir("dirA"): k.path).join(" ") ==
                          "dirA/dirB dirA/dirC dirA/fileA2.txt dirA/fileA1.txt"
  ## See also:
  ## * `walkPattern iterator`_
  ## * `walkFiles iterator`_
  ## * `walkDirs iterator`_
  ## * `walkDirRec iterator`_

  when nimvm:
    for k, v in items(staticWalkDir(dir, relative)):
      yield (k, v)
  else:
    when weirdTarget:
      for k, v in items(staticWalkDir(dir, relative)):
        yield (k, v)
    elif defined(windows):
      var f: WIN32_FIND_DATA
      var h = findFirstFile(dir / "*", f)
      if h == -1:
        if checkDir:
          raiseOSError(osLastError(), dir)
      else:
        defer: findClose(h)
        while true:
          var k = pcFile
          if not skipFindData(f):
            if (f.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) != 0'i32:
              k = pcDir
            if (f.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT) != 0'i32:
              k = succ(k)
            let xx = if relative: extractFilename(getFilename(f))
                     else: dir / extractFilename(getFilename(f))
            yield (k, xx)
          if findNextFile(h, f) == 0'i32:
            let errCode = getLastError()
            if errCode == ERROR_NO_MORE_FILES: break
            else: raiseOSError(errCode.OSErrorCode)
    else:
      var d = opendir(dir)
      if d == nil:
        if checkDir:
          raiseOSError(osLastError(), dir)
      else:
        defer: discard closedir(d)
        while true:
          var x = readdir(d)
          if x == nil: break
          var y = $cast[cstring](addr x.d_name)
          if y != "." and y != "..":
            var s: Stat
            let path = dir / y
            if not relative:
              y = path
            var k = pcFile

            template resolveSymlink() =
              var isSpecial: bool
              (k, isSpecial) = getSymlinkFileKind(path)
              if skipSpecial and isSpecial: continue

            template kSetGeneric() =  # pure Posix component `k` resolution
              if lstat(path.cstring, s) < 0'i32: continue  # don't yield
              elif S_ISDIR(s.st_mode):
                k = pcDir
              elif S_ISLNK(s.st_mode):
                resolveSymlink()
              elif skipSpecial and not S_ISREG(s.st_mode): continue

            when defined(linux) or defined(macosx) or
                 defined(bsd) or defined(genode) or defined(nintendoswitch):
              case x.d_type
              of DT_DIR: k = pcDir
              of DT_LNK:
                resolveSymlink()
              of DT_UNKNOWN:
                kSetGeneric()
              else: # DT_REG or special "files" like FIFOs
                if skipSpecial and x.d_type != DT_REG: continue
                else: discard # leave it as pcFile
            else:  # assuming that field `d_type` is not present
              kSetGeneric()

            yield (k, y)

iterator walkDirRec*(dir: string,
                     yieldFilter = {pcFile}, followFilter = {pcDir},
                     relative = false, checkDir = false, skipSpecial = false):
                    string {.tags: [ReadDirEffect].} =
  ## Recursively walks over the directory `dir` and yields for each file
  ## or directory in `dir`.
  ##
  ## Options `relative`, `checkdir`, `skipSpecial` are explained in
  ## [walkDir iterator] description.
  ##
  ## .. warning:: Modifying the directory structure while the iterator
  ##   is traversing may result in undefined behavior!
  ##
  ## Walking is recursive. `followFilter` controls the behaviour of the iterator:
  ##
  ## =====================   =============================================
  ## yieldFilter             meaning
  ## =====================   =============================================
  ## ``pcFile``              yield real files (default)
  ## ``pcLinkToFile``        yield symbolic links to files
  ## ``pcDir``               yield real directories
  ## ``pcLinkToDir``         yield symbolic links to directories
  ## =====================   =============================================
  ##
  ## =====================   =============================================
  ## followFilter            meaning
  ## =====================   =============================================
  ## ``pcDir``               follow real directories (default)
  ## ``pcLinkToDir``         follow symbolic links to directories
  ## =====================   =============================================
  ##
  ##
  ## See also:
  ## * `walkPattern iterator`_
  ## * `walkFiles iterator`_
  ## * `walkDirs iterator`_
  ## * `walkDir iterator`_

  var stack = @[""]
  var checkDir = checkDir
  while stack.len > 0:
    let d = stack.pop()
    for k, p in walkDir(dir / d, relative = true, checkDir = checkDir,
                        skipSpecial = skipSpecial):
      let rel = d / p
      if k in {pcDir, pcLinkToDir} and k in followFilter:
        stack.add rel
      if k in yieldFilter:
        yield if relative: rel else: dir / rel
    checkDir = false
      # We only check top-level dir, otherwise if a subdir is invalid (eg. wrong
      # permissions), it'll abort iteration and there would be no way to
      # continue iteration.
      # Future work can provide a way to customize this and do error reporting.

proc rawRemoveDir(dir: string) {.noWeirdTarget.} =
  when defined(windows):
    wrapUnary(res, removeDirectoryW, dir)
    let lastError = osLastError()
    if res == 0'i32 and lastError.int32 != 3'i32 and
        lastError.int32 != 18'i32 and lastError.int32 != 2'i32:
      raiseOSError(lastError, dir)
  else:
    if rmdir(dir) != 0'i32 and errno != ENOENT: raiseOSError(osLastError(), dir)

proc removeDir*(dir: string, checkDir = false) {.rtl, extern: "nos$1", tags: [
  WriteDirEffect, ReadDirEffect], benign, noWeirdTarget.} =
  ## Removes the directory `dir` including all subdirectories and files
  ## in `dir` (recursively).
  ##
  ## If this fails, `OSError` is raised. This does not fail if the directory never
  ## existed in the first place, unless `checkDir` = true.
  ##
  ## See also:
  ## * `tryRemoveFile proc`_
  ## * `removeFile proc`_
  ## * `existsOrCreateDir proc`_
  ## * `createDir proc`_
  ## * `copyDir proc`_
  ## * `copyDirWithPermissions proc`_
  ## * `moveDir proc`_
  for kind, path in walkDir(dir, checkDir = checkDir):
    case kind
    of pcFile, pcLinkToFile, pcLinkToDir: removeFile(path)
    of pcDir: removeDir(path, true)
      # for subdirectories there is no benefit in `checkDir = false`
      # (unless perhaps for edge case of concurrent processes also deleting
      # the same files)
  rawRemoveDir(dir)

proc rawCreateDir(dir: string): bool {.noWeirdTarget.} =
  # Try to create one directory (not the whole path).
  # returns `true` for success, `false` if the path has previously existed
  #
  # This is a thin wrapper over mkDir (or alternatives on other systems),
  # so in case of a pre-existing path we don't check that it is a directory.
  when defined(solaris):
    let res = mkdir(dir, 0o777)
    if res == 0'i32:
      result = true
    elif errno in {EEXIST, ENOSYS}:
      result = false
    else:
      raiseOSError(osLastError(), dir)
  elif defined(haiku):
    let res = mkdir(dir, 0o777)
    if res == 0'i32:
      result = true
    elif errno == EEXIST or errno == EROFS:
      result = false
    else:
      raiseOSError(osLastError(), dir)
  elif defined(posix):
    let res = mkdir(dir, 0o777)
    if res == 0'i32:
      result = true
    elif errno == EEXIST:
      result = false
    else:
      #echo res
      raiseOSError(osLastError(), dir)
  else:
    wrapUnary(res, createDirectoryW, dir)

    if res != 0'i32:
      result = true
    elif getLastError() == 183'i32:
      result = false
    else:
      raiseOSError(osLastError(), dir)

proc existsOrCreateDir*(dir: string): bool {.rtl, extern: "nos$1",
  tags: [WriteDirEffect, ReadDirEffect], noWeirdTarget.} =
  ## Checks if a `directory`:idx: `dir` exists, and creates it otherwise.
  ##
  ## Does not create parent directories (raises `OSError` if parent directories do not exist).
  ## Returns `true` if the directory already exists, and `false` otherwise.
  ##
  ## See also:
  ## * `removeDir proc`_
  ## * `createDir proc`_
  ## * `copyDir proc`_
  ## * `copyDirWithPermissions proc`_
  ## * `moveDir proc`_
  result = not rawCreateDir(dir)
  if result:
    # path already exists - need to check that it is indeed a directory
    if not dirExists(dir):
      raise newException(IOError, "Failed to create '" & dir & "'")

proc createDir*(dir: string) {.rtl, extern: "nos$1",
  tags: [WriteDirEffect, ReadDirEffect], noWeirdTarget.} =
  ## Creates the `directory`:idx: `dir`.
  ##
  ## The directory may contain several subdirectories that do not exist yet.
  ## The full path is created. If this fails, `OSError` is raised.
  ##
  ## It does **not** fail if the directory already exists because for
  ## most usages this does not indicate an error.
  ##
  ## See also:
  ## * `removeDir proc`_
  ## * `existsOrCreateDir proc`_
  ## * `copyDir proc`_
  ## * `copyDirWithPermissions proc`_
  ## * `moveDir proc`_
  if dir == "":
    return
  var omitNext = isAbsolute(dir)
  for p in parentDirs(dir, fromRoot=true):
    if omitNext:
      omitNext = false
    else:
      discard existsOrCreateDir(p)

proc copyDir*(source, dest: string, skipSpecial = false) {.rtl, extern: "nos$1",
  tags: [ReadDirEffect, WriteIOEffect, ReadIOEffect], benign, noWeirdTarget.} =
  ## Copies a directory from `source` to `dest`.
  ##
  ## On non-Windows OSes, symlinks are copied as symlinks. On Windows, symlinks
  ## are skipped.
  ##
  ## If `skipSpecial` is true, then (besides all directories) only *regular*
  ## files (**without** special "file" objects like FIFOs, device files,
  ## etc) will be copied on Unix.
  ##
  ## If this fails, `OSError` is raised.
  ##
  ## On the Windows platform this proc will copy the attributes from
  ## `source` into `dest`.
  ##
  ## On other platforms created files and directories will inherit the
  ## default permissions of a newly created file/directory for the user.
  ## Use `copyDirWithPermissions proc`_
  ## to preserve attributes recursively on these platforms.
  ##
  ## See also:
  ## * `copyDirWithPermissions proc`_
  ## * `copyFile proc`_
  ## * `copyFileWithPermissions proc`_
  ## * `removeDir proc`_
  ## * `existsOrCreateDir proc`_
  ## * `createDir proc`_
  ## * `moveDir proc`_
  createDir(dest)
  for kind, path in walkDir(source, skipSpecial = skipSpecial):
    var noSource = splitPath(path).tail
    if kind == pcDir:
      copyDir(path, dest / noSource, skipSpecial = skipSpecial)
    else:
      copyFile(path, dest / noSource, {cfSymlinkAsIs})


proc copyDirWithPermissions*(source, dest: string,
                             ignorePermissionErrors = true,
                             skipSpecial = false)
  {.rtl, extern: "nos$1", tags: [ReadDirEffect, WriteIOEffect, ReadIOEffect],
   benign, noWeirdTarget.} =
  ## Copies a directory from `source` to `dest` preserving file permissions.
  ##
  ## On non-Windows OSes, symlinks are copied as symlinks. On Windows, symlinks
  ## are skipped.
  ##
  ## If `skipSpecial` is true, then (besides all directories) only *regular*
  ## files (**without** special "file" objects like FIFOs, device files,
  ## etc) will be copied on Unix.
  ##
  ## If this fails, `OSError` is raised. This is a wrapper proc around
  ## `copyDir`_ and `copyFileWithPermissions`_ procs
  ## on non-Windows platforms.
  ##
  ## On Windows this proc is just a wrapper for `copyDir proc`_ since
  ## that proc already copies attributes.
  ##
  ## On non-Windows systems permissions are copied after the file or directory
  ## itself has been copied, which won't happen atomically and could lead to a
  ## race condition. If `ignorePermissionErrors` is true (default), errors while
  ## reading/setting file attributes will be ignored, otherwise will raise
  ## `OSError`.
  ##
  ## See also:
  ## * `copyDir proc`_
  ## * `copyFile proc`_
  ## * `copyFileWithPermissions proc`_
  ## * `removeDir proc`_
  ## * `moveDir proc`_
  ## * `existsOrCreateDir proc`_
  ## * `createDir proc`_
  createDir(dest)
  when not defined(windows):
    try:
      setFilePermissions(dest, getFilePermissions(source), followSymlinks =
                         false)
    except:
      if not ignorePermissionErrors:
        raise
  for kind, path in walkDir(source, skipSpecial = skipSpecial):
    var noSource = splitPath(path).tail
    if kind == pcDir:
      copyDirWithPermissions(path, dest / noSource, ignorePermissionErrors, skipSpecial = skipSpecial)
    else:
      copyFileWithPermissions(path, dest / noSource, ignorePermissionErrors, {cfSymlinkAsIs})

proc moveDir*(source, dest: string) {.tags: [ReadIOEffect, WriteIOEffect], noWeirdTarget.} =
  ## Moves a directory from `source` to `dest`.
  ##
  ## Symlinks are not followed: if `source` contains symlinks, they themself are
  ## moved, not their target.
  ##
  ## If this fails, `OSError` is raised.
  ##
  ## See also:
  ## * `moveFile proc`_
  ## * `copyDir proc`_
  ## * `copyDirWithPermissions proc`_
  ## * `removeDir proc`_
  ## * `existsOrCreateDir proc`_
  ## * `createDir proc`_
  if not tryMoveFSObject(source, dest, isDir = true):
    # Fallback to copy & del
    copyDir(source, dest)
    removeDir(source)

proc setCurrentDir*(newDir: string) {.inline, tags: [], noWeirdTarget.} =
  ## Sets the `current working directory`:idx:; `OSError`
  ## is raised if `newDir` cannot been set.
  ##
  ## See also:
  ## * `getHomeDir proc`_
  ## * `getConfigDir proc`_
  ## * `getTempDir proc`_
  ## * `getCurrentDir proc`_
  when defined(windows):
    if setCurrentDirectoryW(newWideCString(newDir)) == 0'i32:
      raiseOSError(osLastError(), newDir)
  else:
    if chdir(newDir) != 0'i32: raiseOSError(osLastError(), newDir)

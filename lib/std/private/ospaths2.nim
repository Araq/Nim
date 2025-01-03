include system/inclrtl
import std/private/since

import std/[strutils, pathnorm]
import std/oserrors

import oscommon
export ReadDirEffect, WriteDirEffect

when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions, widestrs]

## .. importdoc:: osappdirs.nim, osdirs.nim, osseps.nim, os.nim

const weirdTarget = defined(nimscript) or defined(js)

when weirdTarget:
  discard
elif defined(windows):
  import std/winlean
elif defined(posix):
  import std/posix, system/ansi_c
else:
  {.error: "OS module not ported to your operating system!".}

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


proc normalizePathAux(path: var string){.inline, raises: [], noSideEffect.}


import std/private/osseps
export osseps

proc absolutePathInternal(path: string): string {.gcsafe.}

proc normalizePathEnd*(path: var string, trailingSep = false) =
  ## Ensures ``path`` has exactly 0 or 1 trailing `DirSep`, depending on
  ## ``trailingSep``, and taking care of edge cases: it preservers whether
  ## a path is absolute or relative, and makes sure trailing sep is `DirSep`,
  ## not `AltSep`. Trailing `/.` are compressed, see examples.
  if path.len == 0: return
  var i = path.len
  while i >= 1:
    if path[i-1] in {DirSep, AltSep}: dec(i)
    elif path[i-1] == '.' and i >= 2 and path[i-2] in {DirSep, AltSep}: dec(i)
    else: break
  if trailingSep:
    # foo// => foo
    path.setLen(i)
    # foo => foo/
    path.add DirSep
  elif i > 0:
    # foo// => foo
    path.setLen(i)
  else:
    # // => / (empty case was already taken care of)
    path = $DirSep

proc normalizePathEnd*(path: string, trailingSep = false): string =
  ## outplace overload
  runnableExamples:
    when defined(posix):
      assert normalizePathEnd("/lib//.//", trailingSep = true) == "/lib/"
      assert normalizePathEnd("lib/./.", trailingSep = false) == "lib"
      assert normalizePathEnd(".//./.", trailingSep = false) == "."
      assert normalizePathEnd("", trailingSep = true) == "" # not / !
      assert normalizePathEnd("/", trailingSep = false) == "/" # not "" !
  result = path
  result.normalizePathEnd(trailingSep)

template endsWith(a: string, b: set[char]): bool =
  a.len > 0 and a[^1] in b

proc joinPathImpl(result: var string, state: var int, tail: string) =
  let trailingSep = tail.endsWith({DirSep, AltSep}) or tail.len == 0 and result.endsWith({DirSep, AltSep})
  normalizePathEnd(result, trailingSep=false)
  addNormalizePath(tail, result, state, DirSep)
  normalizePathEnd(result, trailingSep=trailingSep)

proc joinPath*(head, tail: string): string {.
  noSideEffect, rtl, extern: "nos$1".} =
  ## Joins two directory names to one.
  ##
  ## returns normalized path concatenation of `head` and `tail`, preserving
  ## whether or not `tail` has a trailing slash (or, if tail if empty, whether
  ## head has one).
  ##
  ## See also:
  ## * `joinPath(parts: varargs[string]) proc`_
  ## * `/ proc`_
  ## * `splitPath proc`_
  ## * `uri.combine proc <uri.html#combine,Uri,Uri>`_
  ## * `uri./ proc <uri.html#/,Uri,string>`_
  runnableExamples:
    when defined(posix):
      assert joinPath("usr", "lib") == "usr/lib"
      assert joinPath("usr", "lib/") == "usr/lib/"
      assert joinPath("usr", "") == "usr"
      assert joinPath("usr/", "") == "usr/"
      assert joinPath("", "") == ""
      assert joinPath("", "lib") == "lib"
      assert joinPath("", "/lib") == "/lib"
      assert joinPath("usr/", "/lib") == "usr/lib"
      assert joinPath("usr/lib", "../bin") == "usr/bin"

  result = newStringOfCap(head.len + tail.len)
  var state = 0
  joinPathImpl(result, state, head)
  joinPathImpl(result, state, tail)
  when false:
    if len(head) == 0:
      result = tail
    elif head[len(head)-1] in {DirSep, AltSep}:
      if tail.len > 0 and tail[0] in {DirSep, AltSep}:
        result = head & substr(tail, 1)
      else:
        result = head & tail
    else:
      if tail.len > 0 and tail[0] in {DirSep, AltSep}:
        result = head & tail
      else:
        result = head & DirSep & tail

proc joinPath*(parts: varargs[string]): string {.noSideEffect,
  rtl, extern: "nos$1OpenArray".} =
  ## The same as `joinPath(head, tail) proc`_,
  ## but works with any number of directory parts.
  ##
  ## You need to pass at least one element or the proc
  ## will assert in debug builds and crash on release builds.
  ##
  ## See also:
  ## * `joinPath(head, tail) proc`_
  ## * `/ proc`_
  ## * `/../ proc`_
  ## * `splitPath proc`_
  runnableExamples:
    when defined(posix):
      assert joinPath("a") == "a"
      assert joinPath("a", "b", "c") == "a/b/c"
      assert joinPath("usr/lib", "../../var", "log") == "var/log"

  var estimatedLen = 0
  for p in parts: estimatedLen += p.len
  result = newStringOfCap(estimatedLen)
  var state = 0
  for i in 0..high(parts):
    joinPathImpl(result, state, parts[i])

proc `/`*(head, tail: string): string {.noSideEffect, inline.} =
  ## The same as `joinPath(head, tail) proc`_.
  ##
  ## See also:
  ## * `/../ proc`_
  ## * `joinPath(head, tail) proc`_
  ## * `joinPath(parts: varargs[string]) proc`_
  ## * `splitPath proc`_
  ## * `uri.combine proc <uri.html#combine,Uri,Uri>`_
  ## * `uri./ proc <uri.html#/,Uri,string>`_
  runnableExamples:
    when defined(posix):
      assert "usr" / "" == "usr"
      assert "" / "lib" == "lib"
      assert "" / "/lib" == "/lib"
      assert "usr/" / "/lib/" == "usr/lib/"
      assert "usr" / "lib" / "../bin" == "usr/bin"

  result = joinPath(head, tail)

when doslikeFileSystem:
  import std/private/ntpath

proc splitPath*(path: string): tuple[head, tail: string] {.
  noSideEffect, rtl, extern: "nos$1".} =
  ## Splits a directory into `(head, tail)` tuple, so that
  ## ``head / tail == path`` (except for edge cases like "/usr").
  ##
  ## See also:
  ## * `joinPath(head, tail) proc`_
  ## * `joinPath(parts: varargs[string]) proc`_
  ## * `/ proc`_
  ## * `/../ proc`_
  ## * `relativePath proc`_
  runnableExamples:
    assert splitPath("usr/local/bin") == ("usr/local", "bin")
    assert splitPath("usr/local/bin/") == ("usr/local/bin", "")
    assert splitPath("/bin/") == ("/bin", "")
    when (NimMajor, NimMinor) <= (1, 0):
      assert splitPath("/bin") == ("", "bin")
    else:
      assert splitPath("/bin") == ("/", "bin")
    assert splitPath("bin") == ("", "bin")
    assert splitPath("") == ("", "")

  when doslikeFileSystem:
    let (drive, splitpath) = splitDrive(path)
    let stop = drive.len
  else:
    const stop = 0

  var sepPos = -1
  for i in countdown(len(path)-1, stop):
    if path[i] in {DirSep, AltSep}:
      sepPos = i
      break
  if sepPos >= 0:
    result.head = substr(path, 0,
      when (NimMajor, NimMinor) <= (1, 0):
        sepPos-1
      else:
        if likely(sepPos >= 1): sepPos-1 else: 0
    )
    result.tail = substr(path, sepPos+1)
  else:
    when doslikeFileSystem:
      result.head = drive
      result.tail = splitpath
    else:
      result.head = ""
      result.tail = path

proc isAbsolute*(path: string): bool {.rtl, noSideEffect, extern: "nos$1", raises: [].} =
  ## Checks whether a given `path` is absolute.
  ##
  ## On Windows, network paths are considered absolute too.
  runnableExamples:
    assert not "".isAbsolute
    assert not ".".isAbsolute
    when defined(posix):
      assert "/".isAbsolute
      assert not "a/".isAbsolute
      assert "/a/".isAbsolute

  if len(path) == 0: return false

  when doslikeFileSystem:
    var len = len(path)
    result = (path[0] in {'/', '\\'}) or
              (len > 1 and path[0] in {'a'..'z', 'A'..'Z'} and path[1] == ':')
  elif defined(macos):
    # according to https://perldoc.perl.org/File/Spec/Mac.html `:a` is a relative path
    result = path[0] != ':'
  elif defined(RISCOS):
    result = path[0] == '$'
  elif defined(posix):
    result = path[0] == '/'
  elif defined(nodejs):
    {.emit: [result," = require(\"path\").isAbsolute(",path.cstring,");"].}
  else:
    raiseAssert "unreachable" # if ever hits here, adapt as needed

when FileSystemCaseSensitive:
  template `!=?`(a, b: char): bool = a != b
else:
  template `!=?`(a, b: char): bool = toLowerAscii(a) != toLowerAscii(b)

when doslikeFileSystem:
  proc isAbsFromCurrentDrive(path: string): bool {.noSideEffect, raises: [].} =
    ## An absolute path from the root of the current drive (e.g. "\foo")
    path.len > 0 and
    (path[0] == AltSep or
     (path[0] == DirSep and
      (path.len == 1 or path[1] notin {DirSep, AltSep, ':'})))

  proc sameRoot(path1, path2: string): bool {.noSideEffect, raises: [].} =
    ## Return true if path1 and path2 have a same root.
    ##
    ## Detail of Windows path formats:
    ## https://docs.microsoft.com/en-us/dotnet/standard/io/file-path-formats

    assert(isAbsolute(path1))
    assert(isAbsolute(path2))

    if isAbsFromCurrentDrive(path1) and isAbsFromCurrentDrive(path2):
      result = true
    elif cmpIgnoreCase(splitDrive(path1).drive, splitDrive(path2).drive) == 0:
      result = true
    else:
      result = false

proc relativePath*(path, base: string, sep = DirSep): string {.
  rtl, extern: "nos$1".} =
  ## Converts `path` to a path relative to `base`.
  ##
  ## The `sep` (default: DirSep_) is used for the path normalizations,
  ## this can be useful to ensure the relative path only contains `'/'`
  ## so that it can be used for URL constructions.
  ##
  ## On Windows, if a root of `path` and a root of `base` are different,
  ## returns `path` as is because it is impossible to make a relative path.
  ## That means an absolute path can be returned.
  ##
  ## See also:
  ## * `splitPath proc`_
  ## * `parentDir proc`_
  ## * `tailDir proc`_
  runnableExamples:
    assert relativePath("/Users/me/bar/z.nim", "/Users/other/bad", '/') == "../../me/bar/z.nim"
    assert relativePath("/Users/me/bar/z.nim", "/Users/other", '/') == "../me/bar/z.nim"
    when not doslikeFileSystem: # On Windows, UNC-paths start with `//`
      assert relativePath("/Users///me/bar//z.nim", "//Users/", '/') == "me/bar/z.nim"
    assert relativePath("/Users/me/bar/z.nim", "/Users/me", '/') == "bar/z.nim"
    assert relativePath("", "/users/moo", '/') == ""
    assert relativePath("foo", ".", '/') == "foo"
    assert relativePath("foo", "foo", '/') == "."

  if path.len == 0: return ""
  var base = if base == ".": "" else: base
  var path = path
  path.normalizePathAux
  base.normalizePathAux
  let a1 = isAbsolute(path)
  let a2 = isAbsolute(base)
  if a1 and not a2:
    base = absolutePathInternal(base)
  elif a2 and not a1:
    path = absolutePathInternal(path)

  when doslikeFileSystem:
    if isAbsolute(path) and isAbsolute(base):
      if not sameRoot(path, base):
        return path

  var f = default PathIter
  var b = default PathIter
  var ff = (0, -1)
  var bb = (0, -1) # (int, int)
  result = newStringOfCap(path.len)
  # skip the common prefix:
  while f.hasNext(path) and b.hasNext(base):
    ff = next(f, path)
    bb = next(b, base)
    let diff = ff[1] - ff[0]
    if diff != bb[1] - bb[0]: break
    var same = true
    for i in 0..diff:
      if path[i + ff[0]] !=? base[i + bb[0]]:
        same = false
        break
    if not same: break
    ff = (0, -1)
    bb = (0, -1)
  #  for i in 0..diff:
  #    result.add base[i + bb[0]]

  # /foo/bar/xxx/ -- base
  # /foo/bar/baz  -- path path
  #   ../baz
  # every directory that is in 'base', needs to add '..'
  while true:
    if bb[1] >= bb[0]:
      if result.len > 0 and result[^1] != sep:
        result.add sep
      result.add ".."
    if not b.hasNext(base): break
    bb = b.next(base)

  # add the rest of 'path':
  while true:
    if ff[1] >= ff[0]:
      if result.len > 0 and result[^1] != sep:
        result.add sep
      for i in 0..ff[1] - ff[0]:
        result.add path[i + ff[0]]
    if not f.hasNext(path): break
    ff = f.next(path)

  when not defined(nimOldRelativePathBehavior):
    if result.len == 0: result.add "."

proc isRelativeTo*(path: string, base: string): bool {.since: (1, 1).} =
  ## Returns true if `path` is relative to `base`.
  runnableExamples:
    doAssert isRelativeTo("./foo//bar", "foo")
    doAssert isRelativeTo("foo/bar", ".")
    doAssert isRelativeTo("/foo/bar.nim", "/foo/bar.nim")
    doAssert not isRelativeTo("foo/bar.nims", "foo/bar.nim")
  let path = path.normalizePath
  let base = base.normalizePath
  let ret = relativePath(path, base)
  result = path.len > 0 and not ret.startsWith ".."

proc parentDirPos(path: string): int =
  var q = 1
  if len(path) >= 1 and path[len(path)-1] in {DirSep, AltSep}: q = 2
  for i in countdown(len(path)-q, 0):
    if path[i] in {DirSep, AltSep}: return i
  result = -1

proc parentDir*(path: string): string {.
  noSideEffect, rtl, extern: "nos$1".} =
  ## Returns the parent directory of `path`.
  ##
  ## This is similar to ``splitPath(path).head`` when ``path`` doesn't end
  ## in a dir separator, but also takes care of path normalizations.
  ## The remainder can be obtained with `lastPathPart(path) proc`_.
  ##
  ## See also:
  ## * `relativePath proc`_
  ## * `splitPath proc`_
  ## * `tailDir proc`_
  ## * `parentDirs iterator`_
  runnableExamples:
    assert parentDir("") == ""
    when defined(posix):
      assert parentDir("/usr/local/bin") == "/usr/local"
      assert parentDir("foo/bar//") == "foo"
      assert parentDir("//foo//bar//.") == "/foo"
      assert parentDir("./foo") == "."
      assert parentDir("/./foo//./") == "/"
      assert parentDir("a//./") == "."
      assert parentDir("a/b/c/..") == "a"
  result = pathnorm.normalizePath(path)
  when doslikeFileSystem:
    let (drive, splitpath) = splitDrive(result)
    result = splitpath
  var sepPos = parentDirPos(result)
  if sepPos >= 0:
    result = substr(result, 0, sepPos)
    normalizePathEnd(result)
  elif result == ".." or result == "." or result.len == 0 or result[^1] in {DirSep, AltSep}:
    # `.` => `..` and .. => `../..`(etc) would be a sensible alternative
    # `/` => `/` (as done with splitFile) would be a sensible alternative
    result = ""
  else:
    result = "."
  when doslikeFileSystem:
    if result.len == 0:
      discard
    elif drive.len > 0 and result.len == 1 and result[0] in {DirSep, AltSep}:
      result = drive
    else:
      result = drive & result

proc tailDir*(path: string): string {.
  noSideEffect, rtl, extern: "nos$1".} =
  ## Returns the tail part of `path`.
  ##
  ## See also:
  ## * `relativePath proc`_
  ## * `splitPath proc`_
  ## * `parentDir proc`_
  runnableExamples:
    assert tailDir("/bin") == "bin"
    assert tailDir("bin") == ""
    assert tailDir("bin/") == ""
    assert tailDir("/usr/local/bin") == "usr/local/bin"
    assert tailDir("//usr//local//bin//") == "usr//local//bin//"
    assert tailDir("./usr/local/bin") == "usr/local/bin"
    assert tailDir("usr/local/bin") == "local/bin"

  var i = 0
  when doslikeFileSystem:
    let (drive, splitpath) = path.splitDrive
    if drive != "":
      return splitpath.strip(chars = {DirSep, AltSep}, trailing = false)
  while i < len(path):
    if path[i] in {DirSep, AltSep}:
      while i < len(path) and path[i] in {DirSep, AltSep}: inc i
      return substr(path, i)
    inc i
  result = ""

proc isRootDir*(path: string): bool {.
  noSideEffect, rtl, extern: "nos$1".} =
  ## Checks whether a given `path` is a root directory.
  runnableExamples:
    assert isRootDir("")
    assert isRootDir(".")
    assert isRootDir("/")
    assert isRootDir("a")
    assert not isRootDir("/a")
    assert not isRootDir("a/b/c")

  when doslikeFileSystem:
    if splitDrive(path).path == "":
      return true
  result = parentDirPos(path) < 0

iterator parentDirs*(path: string, fromRoot=false, inclusive=true): string =
  ## Walks over all parent directories of a given `path`.
  ##
  ## If `fromRoot` is true (default: false), the traversal will start from
  ## the file system root directory.
  ## If `inclusive` is true (default), the original argument will be included
  ## in the traversal.
  ##
  ## Relative paths won't be expanded by this iterator. Instead, it will traverse
  ## only the directories appearing in the relative path.
  ##
  ## See also:
  ## * `parentDir proc`_
  ##
  runnableExamples:
    let g = "a/b/c"

    for p in g.parentDirs:
      echo p
      # a/b/c
      # a/b
      # a

    for p in g.parentDirs(fromRoot=true):
      echo p
      # a/
      # a/b/
      # a/b/c

    for p in g.parentDirs(inclusive=false):
      echo p
      # a/b
      # a

  if not fromRoot:
    var current = path
    if inclusive: yield path
    while true:
      if current.isRootDir: break
      current = current.parentDir
      yield current
  else:
    when doslikeFileSystem:
      let start = path.splitDrive.drive.len
    else:
      const start = 0
    for i in countup(start, path.len - 2): # ignore the last /
      # deal with non-normalized paths such as /foo//bar//baz
      if path[i] in {DirSep, AltSep} and
          (i == 0 or path[i-1] notin {DirSep, AltSep}):
        yield path.substr(0, i)

    if inclusive: yield path

proc `/../`*(head, tail: string): string {.noSideEffect.} =
  ## The same as ``parentDir(head) / tail``, unless there is no parent
  ## directory. Then ``head / tail`` is performed instead.
  ##
  ## See also:
  ## * `/ proc`_
  ## * `parentDir proc`_
  runnableExamples:
    when defined(posix):
      assert "a/b/c" /../ "d/e" == "a/b/d/e"
      assert "a" /../ "d/e" == "a/d/e"

  when doslikeFileSystem:
    let (drive, head) = splitDrive(head)
  let sepPos = parentDirPos(head)
  if sepPos >= 0:
    result = substr(head, 0, sepPos-1) / tail
  else:
    result = head / tail
  when doslikeFileSystem:
    result = drive / result

proc normExt(ext: string): string =
  if ext == "" or ext[0] == ExtSep: result = ext # no copy needed here
  else: result = ExtSep & ext

proc searchExtPos*(path: string): int =
  ## Returns index of the `'.'` char in `path` if it signifies the beginning
  ## of the file extension. Returns -1 otherwise.
  ##
  ## See also:
  ## * `splitFile proc`_
  ## * `extractFilename proc`_
  ## * `lastPathPart proc`_
  ## * `changeFileExt proc`_
  ## * `addFileExt proc`_
  runnableExamples:
    assert searchExtPos("a/b/c") == -1
    assert searchExtPos("c.nim") == 1
    assert searchExtPos("a/b/c.nim") == 5
    assert searchExtPos("a.b.c.nim") == 5
    assert searchExtPos(".nim") == -1
    assert searchExtPos("..nim") == -1
    assert searchExtPos("a..nim") == 2

  # Unless there is any char that is not `ExtSep` before last `ExtSep` in the file name,
  # it is not a file extension.
  const DirSeps = when doslikeFileSystem: {DirSep, AltSep, ':'} else: {DirSep, AltSep}
  result = -1
  var i = path.high
  while i >= 1:
    if path[i] == ExtSep:
      break
    elif path[i] in DirSeps:
      return -1 # do not skip over path
    dec i

  for j in countdown(i - 1, 0):
    if path[j] in DirSeps:
      return -1
    elif path[j] != ExtSep:
      result = i
      break

proc splitFile*(path: string): tuple[dir, name, ext: string] {.
  noSideEffect, rtl, extern: "nos$1".} =
  ## Splits a filename into `(dir, name, extension)` tuple.
  ##
  ## `dir` does not end in DirSep_ unless it's `/`.
  ## `extension` includes the leading dot.
  ##
  ## If `path` has no extension, `ext` is the empty string.
  ## If `path` has no directory component, `dir` is the empty string.
  ## If `path` has no filename component, `name` and `ext` are empty strings.
  ##
  ## See also:
  ## * `searchExtPos proc`_
  ## * `extractFilename proc`_
  ## * `lastPathPart proc`_
  ## * `changeFileExt proc`_
  ## * `addFileExt proc`_
  runnableExamples:
    var (dir, name, ext) = splitFile("usr/local/nimc.html")
    assert dir == "usr/local"
    assert name == "nimc"
    assert ext == ".html"
    (dir, name, ext) = splitFile("/usr/local/os")
    assert dir == "/usr/local"
    assert name == "os"
    assert ext == ""
    (dir, name, ext) = splitFile("/usr/local/")
    assert dir == "/usr/local"
    assert name == ""
    assert ext == ""
    (dir, name, ext) = splitFile("/tmp.txt")
    assert dir == "/"
    assert name == "tmp"
    assert ext == ".txt"

  var namePos = 0
  var dotPos = 0
  when doslikeFileSystem:
    let (drive, _) = splitDrive(path)
    let stop = len(drive)
    result.dir = drive
  else:
    const stop = 0
  for i in countdown(len(path) - 1, stop):
    if path[i] in {DirSep, AltSep} or i == 0:
      if path[i] in {DirSep, AltSep}:
        result.dir = substr(path, 0, if likely(i >= 1): i - 1 else: 0)
        namePos = i + 1
      if dotPos > i:
        result.name = substr(path, namePos, dotPos - 1)
        result.ext = substr(path, dotPos)
      else:
        result.name = substr(path, namePos)
      break
    elif path[i] == ExtSep and i > 0 and i < len(path) - 1 and
         path[i - 1] notin {DirSep, AltSep} and
         path[i + 1] != ExtSep and dotPos == 0:
      dotPos = i

proc extractFilename*(path: string): string {.
  noSideEffect, rtl, extern: "nos$1".} =
  ## Extracts the filename of a given `path`.
  ##
  ## This is the same as ``name & ext`` from `splitFile(path) proc`_.
  ##
  ## See also:
  ## * `searchExtPos proc`_
  ## * `splitFile proc`_
  ## * `lastPathPart proc`_
  ## * `changeFileExt proc`_
  ## * `addFileExt proc`_
  runnableExamples:
    assert extractFilename("foo/bar/") == ""
    assert extractFilename("foo/bar") == "bar"
    assert extractFilename("foo/bar.baz") == "bar.baz"

  if path.len == 0 or path[path.len-1] in {DirSep, AltSep}:
    result = ""
  else:
    result = splitPath(path).tail

proc lastPathPart*(path: string): string {.
  noSideEffect, rtl, extern: "nos$1".} =
  ## Like `extractFilename proc`_, but ignores
  ## trailing dir separator; aka: `baseName`:idx: in some other languages.
  ##
  ## See also:
  ## * `searchExtPos proc`_
  ## * `splitFile proc`_
  ## * `extractFilename proc`_
  ## * `changeFileExt proc`_
  ## * `addFileExt proc`_
  runnableExamples:
    assert lastPathPart("foo/bar/") == "bar"
    assert lastPathPart("foo/bar") == "bar"

  let path = path.normalizePathEnd(trailingSep = false)
  result = extractFilename(path)

proc changeFileExt*(filename, ext: string): string {.
  noSideEffect, rtl, extern: "nos$1".} =
  ## Changes the file extension to `ext`.
  ##
  ## If the `filename` has no extension, `ext` will be added.
  ## If `ext` == "" then any extension is removed.
  ##
  ## `Ext` should be given without the leading `'.'`, because some
  ## filesystems may use a different character. (Although I know
  ## of none such beast.)
  ##
  ## See also:
  ## * `searchExtPos proc`_
  ## * `splitFile proc`_
  ## * `extractFilename proc`_
  ## * `lastPathPart proc`_
  ## * `addFileExt proc`_
  runnableExamples:
    assert changeFileExt("foo.bar", "baz") == "foo.baz"
    assert changeFileExt("foo.bar", "") == "foo"
    assert changeFileExt("foo", "baz") == "foo.baz"

  var extPos = searchExtPos(filename)
  if extPos < 0: result = filename & normExt(ext)
  else: result = substr(filename, 0, extPos-1) & normExt(ext)

proc addFileExt*(filename, ext: string): string {.
  noSideEffect, rtl, extern: "nos$1".} =
  ## Adds the file extension `ext` to `filename`, unless
  ## `filename` already has an extension.
  ##
  ## `Ext` should be given without the leading `'.'`, because some
  ## filesystems may use a different character.
  ## (Although I know of none such beast.)
  ##
  ## See also:
  ## * `searchExtPos proc`_
  ## * `splitFile proc`_
  ## * `extractFilename proc`_
  ## * `lastPathPart proc`_
  ## * `changeFileExt proc`_
  runnableExamples:
    assert addFileExt("foo.bar", "baz") == "foo.bar"
    assert addFileExt("foo.bar", "") == "foo.bar"
    assert addFileExt("foo", "baz") == "foo.baz"

  var extPos = searchExtPos(filename)
  if extPos < 0: result = filename & normExt(ext)
  else: result = filename

proc cmpPaths*(pathA, pathB: string): int {.
  noSideEffect, rtl, extern: "nos$1".} =
  ## Compares two paths.
  ##
  ## On a case-sensitive filesystem this is done
  ## case-sensitively otherwise case-insensitively. Returns:
  ##
  ## | `0` if pathA == pathB
  ## | `< 0` if pathA < pathB
  ## | `> 0` if pathA > pathB
  runnableExamples:
    when defined(macosx):
      assert cmpPaths("foo", "Foo") == 0
    elif defined(posix):
      assert cmpPaths("foo", "Foo") > 0

  let a = normalizePath(pathA)
  let b = normalizePath(pathB)
  if FileSystemCaseSensitive:
    result = cmp(a, b)
  else:
    when defined(nimscript):
      result = cmpic(a, b)
    elif defined(nimdoc): discard
    else:
      result = cmpIgnoreCase(a, b)

proc unixToNativePath*(path: string, drive=""): string {.
  noSideEffect, rtl, extern: "nos$1".} =
  ## Converts an UNIX-like path to a native one.
  ##
  ## On an UNIX system this does nothing. Else it converts
  ## `'/'`, `'.'`, `'..'` to the appropriate things.
  ##
  ## On systems with a concept of "drives", `drive` is used to determine
  ## which drive label to use during absolute path conversion.
  ## `drive` defaults to the drive of the current working directory, and is
  ## ignored on systems that do not have a concept of "drives".
  when defined(unix):
    result = path
  else:
    if path.len == 0: return ""

    var start: int
    if path[0] == '/':
      # an absolute path
      when doslikeFileSystem:
        if drive != "":
          result = drive & ":" & DirSep
        else:
          result = $DirSep
      elif defined(macos):
        result = "" # must not start with ':'
      else:
        result = $DirSep
      start = 1
    elif path[0] == '.' and (path.len == 1 or path[1] == '/'):
      # current directory
      result = $CurDir
      start = when doslikeFileSystem: 1 else: 2
    else:
      result = ""
      start = 0

    var i = start
    while i < len(path): # ../../../ --> ::::
      if i+2 < path.len and path[i] == '.' and path[i+1] == '.' and path[i+2] == '/':
        # parent directory
        when defined(macos):
          if result[high(result)] == ':':
            add result, ':'
          else:
            add result, ParDir
        else:
          add result, ParDir & DirSep
        inc(i, 3)
      elif path[i] == '/':
        add result, DirSep
        inc(i)
      else:
        add result, path[i]
        inc(i)


when not defined(nimscript):
  proc getCurrentDir*(): string {.rtl, extern: "nos$1", tags: [].} =
    ## Returns the `current working directory`:idx: i.e. where the built
    ## binary is run.
    ##
    ## So the path returned by this proc is determined at run time.
    ##
    ## See also:
    ## * `getHomeDir proc`_
    ## * `getConfigDir proc`_
    ## * `getTempDir proc`_
    ## * `setCurrentDir proc`_
    ## * `currentSourcePath template <system.html#currentSourcePath.t>`_
    ## * `getProjectPath proc <macros.html#getProjectPath>`_
    when defined(nodejs):
      var ret: cstring
      {.emit: "`ret` = process.cwd();".}
      return $ret
    elif defined(js):
      raiseAssert "use -d:nodejs to have `getCurrentDir` defined"
    elif defined(windows):
      var bufsize = MAX_PATH.int32
      var res = newWideCString(bufsize)
      while true:
        var L = getCurrentDirectoryW(bufsize, res)
        if L == 0'i32:
          raiseOSError(osLastError())
        elif L > bufsize:
          res = newWideCString(L)
          bufsize = L
        else:
          result = res$L
          break
    else:
      var bufsize = 1024 # should be enough
      result = newString(bufsize)
      while true:
        if getcwd(result.cstring, bufsize) != nil:
          setLen(result, c_strlen(result.cstring))
          break
        else:
          let err = osLastError()
          if err.int32 == ERANGE:
            bufsize = bufsize shl 1
            doAssert(bufsize >= 0)
            result = newString(bufsize)
          else:
            raiseOSError(osLastError())

proc absolutePath*(path: string, root = getCurrentDir()): string =
  ## Returns the absolute path of `path`, rooted at `root` (which must be absolute;
  ## default: current directory).
  ## If `path` is absolute, return it, ignoring `root`.
  ##
  ## See also:
  ## * `normalizedPath proc`_
  ## * `normalizePath proc`_
  runnableExamples:
    assert absolutePath("a") == getCurrentDir() / "a"

  if isAbsolute(path): path
  else:
    if not root.isAbsolute:
      raise newException(ValueError, "The specified root is not absolute: " & root)
    joinPath(root, path)

proc absolutePathInternal(path: string): string =
  absolutePath(path, getCurrentDir())


proc normalizePath*(path: var string) {.rtl, extern: "nos$1", tags: [].} =
  ## Normalize a path.
  ##
  ## Consecutive directory separators are collapsed, including an initial double slash.
  ##
  ## On relative paths, double dot (`..`) sequences are collapsed if possible.
  ## On absolute paths they are always collapsed.
  ##
  ## .. warning:: URL-encoded and Unicode attempts at directory traversal are not detected.
  ##   Triple dot is not handled.
  ##
  ## See also:
  ## * `absolutePath proc`_
  ## * `normalizedPath proc`_ for outplace version
  ## * `normalizeExe proc`_
  runnableExamples:
    when defined(posix):
      var a = "a///b//..//c///d"
      a.normalizePath()
      assert a == "a/c/d"

  path = pathnorm.normalizePath(path)
  when false:
    let isAbs = isAbsolute(path)
    var stack: seq[string] = @[]
    for p in split(path, {DirSep}):
      case p
      of "", ".":
        continue
      of "..":
        if stack.len == 0:
          if isAbs:
            discard  # collapse all double dots on absoluta paths
          else:
            stack.add(p)
        elif stack[^1] == "..":
          stack.add(p)
        else:
          discard stack.pop()
      else:
        stack.add(p)

    if isAbs:
      path = DirSep & join(stack, $DirSep)
    elif stack.len > 0:
      path = join(stack, $DirSep)
    else:
      path = "."

proc normalizePathAux(path: var string) = normalizePath(path)

proc normalizedPath*(path: string): string {.rtl, extern: "nos$1", tags: [].} =
  ## Returns a normalized path for the current OS.
  ##
  ## See also:
  ## * `absolutePath proc`_
  ## * `normalizePath proc`_ for the in-place version
  runnableExamples:
    when defined(posix):
      assert normalizedPath("a///b//..//c///d") == "a/c/d"
  result = pathnorm.normalizePath(path)

proc normalizeExe*(file: var string) {.since: (1, 3, 5).} =
  ## on posix, prepends `./` if `file` doesn't contain `/` and is not `"", ".", ".."`.
  runnableExamples:
    import std/sugar
    when defined(posix):
      doAssert "foo".dup(normalizeExe) == "./foo"
      doAssert "foo/../bar".dup(normalizeExe) == "foo/../bar"
    doAssert "".dup(normalizeExe) == ""
  when defined(posix):
    if file.len > 0 and DirSep notin file and file != "." and file != "..":
      file = "./" & file

proc sameFile*(path1, path2: string): bool {.rtl, extern: "nos$1",
  tags: [ReadDirEffect], noWeirdTarget.} =
  ## Returns true if both pathname arguments refer to the same physical
  ## file or directory.
  ##
  ## Raises `OSError` if any of the files does not
  ## exist or information about it can not be obtained.
  ##
  ## This proc will return true if given two alternative hard-linked or
  ## sym-linked paths to the same file or directory.
  ##
  ## See also:
  ## * `sameFileContent proc`_
  result = false
  when defined(windows):
    var success = true
    var f1 = openHandle(path1)
    var f2 = openHandle(path2)

    var lastErr: OSErrorCode
    if f1 != INVALID_HANDLE_VALUE and f2 != INVALID_HANDLE_VALUE:
      var fi1, fi2: BY_HANDLE_FILE_INFORMATION

      if getFileInformationByHandle(f1, addr(fi1)) != 0 and
         getFileInformationByHandle(f2, addr(fi2)) != 0:
        result = fi1.dwVolumeSerialNumber == fi2.dwVolumeSerialNumber and
                 fi1.nFileIndexHigh == fi2.nFileIndexHigh and
                 fi1.nFileIndexLow == fi2.nFileIndexLow
      else:
        lastErr = osLastError()
        success = false
    else:
      lastErr = osLastError()
      success = false

    discard closeHandle(f1)
    discard closeHandle(f2)

    if not success: raiseOSError(lastErr, $(path1, path2))
  else:
    var a, b: Stat
    if stat(path1, a) < 0'i32 or stat(path2, b) < 0'i32:
      raiseOSError(osLastError(), $(path1, path2))
    else:
      result = a.st_dev == b.st_dev and a.st_ino == b.st_ino

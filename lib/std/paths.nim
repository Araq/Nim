## This module implements path handling.
##
## **See also:**
## * `files module <files.html>`_ for file access

import std/private/osseps
export osseps

import std/envvars
import std/private/osappdirs

import std/[pathnorm, hashes, sugar, strutils]

from std/private/ospaths2 import  joinPath, splitPath,
                                  ReadDirEffect, WriteDirEffect,
                                  isAbsolute, relativePath,
                                  normalizePathEnd, isRelativeTo, parentDir,
                                  tailDir, isRootDir, parentDirs, `/../`,
                                  extractFilename, lastPathPart,
                                  changeFileExt, addFileExt, cmpPaths, splitFile,
                                  unixToNativePath, absolutePath, normalizeExe,
                                  normalizePath
export ReadDirEffect, WriteDirEffect

type
  Path* = distinct string

func hash*(x: Path): Hash =
  let x = x.string.dup(normalizePath)
  if FileSystemCaseSensitive:
    result = x.hash
  else:
    result = x.toLowerAscii.hash

template `$`*(x: Path): string =
  string(x)

func `==`*(x, y: Path): bool {.inline.} =
  ## Compares two paths.
  ##
  ## On a case-sensitive filesystem this is done
  ## case-sensitively otherwise case-insensitively.
  result = cmpPaths(x.string, y.string) == 0

template endsWith(a: string, b: set[char]): bool =
  a.len > 0 and a[^1] in b

func add(x: var string, tail: string) =
  var state = 0
  let trailingSep = tail.endsWith({DirSep, AltSep}) or tail.len == 0 and x.endsWith({DirSep, AltSep})
  normalizePathEnd(x, trailingSep=false)
  addNormalizePath(tail, x, state, DirSep)
  normalizePathEnd(x, trailingSep=trailingSep)

func add*(x: var Path, y: Path) {.borrow.}

func `/`*(head, tail: Path): Path {.inline.} =
  ## Joins two directory names to one.
  ##
  ## returns normalized path concatenation of `head` and `tail`, preserving
  ## whether or not `tail` has a trailing slash (or, if tail if empty, whether
  ## head has one).
  ##
  ## See also:
  ## * `splitPath proc`_
  ## * `uri.combine proc <uri.html#combine,Uri,Uri>`_
  ## * `uri./ proc <uri.html#/,Uri,string>`_
  Path(joinPath(head.string, tail.string))

func splitPath*(path: Path): tuple[head, tail: Path] {.inline.} =
  ## Splits a directory into `(head, tail)` tuple, so that
  ## ``head / tail == path`` (except for edge cases like "/usr").
  ##
  ## See also:
  ## * `add proc`_
  ## * `/ proc`_
  ## * `/../ proc`_
  ## * `relativePath proc`_
  let res = splitPath(path.string)
  result = (Path(res.head), Path(res.tail))

func splitFile*(path: Path): tuple[dir, name: Path, ext: string] {.inline.} =
  ## Splits a filename into `(dir, name, extension)` tuple.
  ##
  ## `dir` does not end in DirSep unless it's `/`.
  ## `extension` includes the leading dot.
  ##
  ## If `path` has no extension, `ext` is the empty string.
  ## If `path` has no directory component, `dir` is the empty string.
  ## If `path` has no filename component, `name` and `ext` are empty strings.
  ##
  ## See also:
  ## * `extractFilename proc`_
  ## * `lastPathPart proc`_
  ## * `changeFileExt proc`_
  ## * `addFileExt proc`_
  let res = splitFile(path.string)
  result = (Path(res.dir), Path(res.name), res.ext)

func isAbsolute*(path: Path): bool {.inline, raises: [].} =
  ## Checks whether a given `path` is absolute.
  ##
  ## On Windows, network paths are considered absolute too.
  result = isAbsolute(path.string)

proc relativePath*(path, base: Path, sep = DirSep): Path {.inline.} =
  ## Converts `path` to a path relative to `base`.
  ##
  ## The `sep` (default: DirSep) is used for the path normalizations,
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
  result = Path(relativePath(path.string, base.string, sep))

proc isRelativeTo*(path: Path, base: Path): bool {.inline.} =
  ## Returns true if `path` is relative to `base`.
  result = isRelativeTo(path.string, base.string)


func parentDir*(path: Path): Path {.inline.} =
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
  result = Path(parentDir(path.string))

func tailDir*(path: Path): Path {.inline.} =
  ## Returns the tail part of `path`.
  ##
  ## See also:
  ## * `relativePath proc`_
  ## * `splitPath proc`_
  ## * `parentDir proc`_
  result = Path(tailDir(path.string))

func isRootDir*(path: Path): bool {.inline.} =
  ## Checks whether a given `path` is a root directory.
  result = isRootDir(path.string)

iterator parentDirs*(path: Path, fromRoot=false, inclusive=true): Path =
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
  for p in parentDirs(path.string, fromRoot, inclusive):
    yield Path(p)

func `/../`*(head, tail: Path): Path {.inline.} =
  ## The same as ``parentDir(head) / tail``, unless there is no parent
  ## directory. Then ``head / tail`` is performed instead.
  ##
  ## See also:
  ## * `/ proc`_
  ## * `parentDir proc`_
  Path(`/../`(head.string, tail.string))

func extractFilename*(path: Path): Path {.inline.} =
  ## Extracts the filename of a given `path`.
  ##
  ## This is the same as ``name & ext`` from `splitFile(path) proc`_.
  ##
  ## See also:
  ## * `splitFile proc`_
  ## * `lastPathPart proc`_
  ## * `changeFileExt proc`_
  ## * `addFileExt proc`_
  result = Path(extractFilename(path.string))

func lastPathPart*(path: Path): Path {.inline.} =
  ## Like `extractFilename proc`_, but ignores
  ## trailing dir separator; aka: `baseName`:idx: in some other languages.
  ##
  ## See also:
  ## * `splitFile proc`_
  ## * `extractFilename proc`_
  ## * `changeFileExt proc`_
  ## * `addFileExt proc`_
  result = Path(lastPathPart(path.string))

func changeFileExt*(filename: Path, ext: string): Path {.inline.} =
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
  ## * `splitFile proc`_
  ## * `extractFilename proc`_
  ## * `lastPathPart proc`_
  ## * `addFileExt proc`_
  result = Path(changeFileExt(filename.string, ext))

func addFileExt*(filename: Path, ext: string): Path {.inline.} =
  ## Adds the file extension `ext` to `filename`, unless
  ## `filename` already has an extension.
  ##
  ## `Ext` should be given without the leading `'.'`, because some
  ## filesystems may use a different character.
  ## (Although I know of none such beast.)
  ##
  ## See also:
  ## * `splitFile proc`_
  ## * `extractFilename proc`_
  ## * `lastPathPart proc`_
  ## * `changeFileExt proc`_
  result = Path(addFileExt(filename.string, ext))

func unixToNativePath*(path: Path, drive=Path("")): Path {.inline.} =
  ## Converts an UNIX-like path to a native one.
  ##
  ## On an UNIX system this does nothing. Else it converts
  ## `'/'`, `'.'`, `'..'` to the appropriate things.
  ##
  ## On systems with a concept of "drives", `drive` is used to determine
  ## which drive label to use during absolute path conversion.
  ## `drive` defaults to the drive of the current working directory, and is
  ## ignored on systems that do not have a concept of "drives".
  result = Path(unixToNativePath(path.string, drive.string))

proc getCurrentDir*(): Path {.inline, tags: [].} =
  ## Returns the `current working directory`:idx: i.e. where the built
  ## binary is run.
  ##
  ## So the path returned by this proc is determined at run time.
  ##
  ## See also:
  ## * `getHomeDir proc <appdirs.html#getHomeDir>`_
  ## * `getConfigDir proc <appdirs.html#getConfigDir>`_
  ## * `getTempDir proc <appdirs.html#getTempDir>`_
  ## * `setCurrentDir proc <dirs.html#setCurrentDir>`_
  ## * `currentSourcePath template <system.html#currentSourcePath.t>`_
  ## * `getProjectPath proc <macros.html#getProjectPath>`_
  result = Path(ospaths2.getCurrentDir())

proc normalizeExe*(file: var Path) {.borrow.}

proc normalizePath*(path: var Path) {.borrow.}

proc normalizePathEnd*(path: var Path, trailingSep = false) {.borrow.}

proc absolutePath*(path: Path, root = getCurrentDir()): Path =
  ## Returns the absolute path of `path`, rooted at `root` (which must be absolute;
  ## default: current directory).
  ## If `path` is absolute, return it, ignoring `root`.
  ##
  ## See also:
  ## * `normalizePath proc`_
  result = Path(absolutePath(path.string, root.string))

proc expandTildeImpl(path: string): string {.
  tags: [ReadEnvEffect, ReadIOEffect].} =
  if len(path) == 0 or path[0] != '~':
    result = path
  elif len(path) == 1:
    result = getHomeDir()
  elif (path[1] in {DirSep, AltSep}):
    result = joinPath(getHomeDir(), path.substr(2))
  else:
    # TODO: handle `~bob` and `~bob/` which means home of bob
    result = path

proc expandTilde*(path: Path): Path {.inline,
  tags: [ReadEnvEffect, ReadIOEffect].} =
  ## Expands ``~`` or a path starting with ``~/`` to a full path, replacing
  ## ``~`` with `getHomeDir() <appdirs.html#getHomeDir>`_ (otherwise returns ``path`` unmodified).
  ##
  ## Windows: this is still supported despite the Windows platform not having this
  ## convention; also, both ``~/`` and ``~\`` are handled.
  runnableExamples:
    import std/appdirs
    assert expandTilde(Path("~") / Path("appname.cfg")) == getHomeDir() / Path("appname.cfg")
    assert expandTilde(Path("~/foo/bar")) == getHomeDir() / Path("foo/bar")
    assert expandTilde(Path("/foo/bar")) == Path("/foo/bar")
  result = Path(expandTildeImpl(path.string))

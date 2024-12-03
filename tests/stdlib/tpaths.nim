discard """
  matrix: "--mm:refc; --mm:orc"
"""

import std/paths
import std/assertions
import pathnorm
from std/private/ospaths2 {.all.} import joinPathImpl
import std/[sugar, sets]


proc normalizePath*(path: Path; dirSep = DirSep): Path =
  result = Path(pathnorm.normalizePath(path.string, dirSep))

func joinPath*(parts: varargs[Path]): Path =
  var estimatedLen = 0
  var state = 0
  for p in parts: estimatedLen += p.string.len
  var res = newStringOfCap(estimatedLen)
  for i in 0..high(parts):
    joinPathImpl(res, state, parts[i].string)
  result = Path(res)


func joinPath(head, tail: Path): Path {.inline.} =
  head / tail

block absolutePath:
  doAssertRaises(ValueError): discard absolutePath(Path"a", Path"b")
  doAssert absolutePath(Path"a") == getCurrentDir() / Path"a"
  doAssert absolutePath(Path"a", Path"/b") == Path"/b" / Path"a"
  when defined(posix):
    doAssert absolutePath(Path"a", Path"/b/") == Path"/b" / Path"a"
    doAssert absolutePath(Path"a", Path"/b/c") == Path"/b/c" / Path"a"
    doAssert absolutePath(Path"/a", Path"b/") == Path"/a"

block splitFile:
  doAssert splitFile(Path"") == (Path"", Path"", "")
  doAssert splitFile(Path"abc/") == (Path"abc", Path"", "")
  doAssert splitFile(Path"/") == (Path"/", Path"", "")
  doAssert splitFile(Path"./abc") == (Path".", Path"abc", "")
  doAssert splitFile(Path".txt") == (Path"", Path".txt", "")
  doAssert splitFile(Path"abc/.txt") == (Path"abc", Path".txt", "")
  doAssert splitFile(Path"abc") == (Path"", Path"abc", "")
  doAssert splitFile(Path"abc.txt") == (Path"", Path"abc", ".txt")
  doAssert splitFile(Path"/abc.txt") == (Path"/", Path"abc", ".txt")
  doAssert splitFile(Path"/foo/abc.txt") == (Path"/foo", Path"abc", ".txt")
  doAssert splitFile(Path"/foo/abc.txt.gz") == (Path"/foo", Path"abc.txt", ".gz")
  doAssert splitFile(Path".") == (Path"", Path".", "")
  doAssert splitFile(Path"abc/.") == (Path"abc", Path".", "")
  doAssert splitFile(Path"..") == (Path"", Path"..", "")
  doAssert splitFile(Path"a/..") == (Path"a", Path"..", "")
  doAssert splitFile(Path"/foo/abc....txt") == (Path"/foo", Path"abc...", ".txt")

# execShellCmd is tested in tosproc

block ospaths:
  doAssert unixToNativePath(Path"") == Path""
  doAssert unixToNativePath(Path".") == Path($CurDir)
  doAssert unixToNativePath(Path"..") == Path($ParDir)
  doAssert isAbsolute(unixToNativePath(Path"/"))
  doAssert isAbsolute(unixToNativePath(Path"/", Path"a"))
  doAssert isAbsolute(unixToNativePath(Path"/a"))
  doAssert isAbsolute(unixToNativePath(Path"/a", Path"a"))
  doAssert isAbsolute(unixToNativePath(Path"/a/b"))
  doAssert isAbsolute(unixToNativePath(Path"/a/b", Path"a"))
  doAssert unixToNativePath(Path"a/b") == joinPath(Path"a", Path"b")

  when defined(macos):
    doAssert unixToNativePath(Path"./") == Path":"
    doAssert unixToNativePath(Path"./abc") == Path":abc"
    doAssert unixToNativePath(Path"../abc") == Path"::abc"
    doAssert unixToNativePath(Path"../../abc") == Path":::abc"
    doAssert unixToNativePath(Path"/abc", Path"a") == Path"abc"
    doAssert unixToNativePath(Path"/abc/def", Path"a") == Path"abc:def"
  elif doslikeFileSystem:
    doAssert unixToNativePath(Path"./") == Path(".\\")
    doAssert unixToNativePath(Path"./abc") == Path(".\\abc")
    doAssert unixToNativePath(Path"../abc") == Path("..\\abc")
    doAssert unixToNativePath(Path"../../abc") == Path("..\\..\\abc")
    doAssert unixToNativePath(Path"/abc", Path"a") == Path("a:\\abc")
    doAssert unixToNativePath(Path"/abc/def", Path"a") == Path("a:\\abc\\def")
  else:
    #Tests for unix
    doAssert unixToNativePath(Path"./") == Path"./"
    doAssert unixToNativePath(Path"./abc") == Path"./abc"
    doAssert unixToNativePath(Path"../abc") == Path"../abc"
    doAssert unixToNativePath(Path"../../abc") == Path"../../abc"
    doAssert unixToNativePath(Path"/abc", Path"a") == Path"/abc"
    doAssert unixToNativePath(Path"/abc/def", Path"a") == Path"/abc/def"

  block extractFilenameTest:
    doAssert extractFilename(Path"") == Path""
    when defined(posix):
      doAssert extractFilename(Path"foo/bar") == Path"bar"
      doAssert extractFilename(Path"foo/bar.txt") == Path"bar.txt"
      doAssert extractFilename(Path"foo/") == Path""
      doAssert extractFilename(Path"/") == Path""
    when doslikeFileSystem:
      doAssert extractFilename(Path(r"foo\bar")) == Path"bar"
      doAssert extractFilename(Path(r"foo\bar.txt")) == Path"bar.txt"
      doAssert extractFilename(Path(r"foo\")) == Path""
      doAssert extractFilename(Path(r"C:\")) == Path""

  block lastPathPartTest:
    doAssert lastPathPart(Path"") == Path""
    when defined(posix):
      doAssert lastPathPart(Path"foo/bar.txt") == Path"bar.txt"
      doAssert lastPathPart(Path"foo/") == Path"foo"
      doAssert lastPathPart(Path"/") == Path""
    when doslikeFileSystem:
      doAssert lastPathPart(Path(r"foo\bar.txt")) == Path"bar.txt"
      doAssert lastPathPart(Path(r"foo\")) == Path"foo"

  template canon(x): Path = normalizePath(Path(x), '/')
  doAssert canon"/foo/../bar" == Path"/bar"
  doAssert canon"foo/../bar" == Path"bar"

  doAssert canon"/f/../bar///" == Path"/bar"
  doAssert canon"f/..////bar" == Path"bar"

  doAssert canon"../bar" == Path"../bar"
  doAssert canon"/../bar" == Path"/../bar"

  doAssert canon("foo/../../bar/") == Path"../bar"
  doAssert canon("./bla/blob/") == Path"bla/blob"
  doAssert canon(".hiddenFile") == Path".hiddenFile"
  doAssert canon("./bla/../../blob/./zoo.nim") == Path"../blob/zoo.nim"

  doAssert canon("C:/file/to/this/long") == Path"C:/file/to/this/long"
  doAssert canon("") == Path""
  doAssert canon("foobar") == Path"foobar"
  doAssert canon("f/////////") == Path"f"

  doAssert relativePath(Path"/foo/bar//baz.nim", Path"/foo", '/') == Path"bar/baz.nim"
  doAssert normalizePath(Path"./foo//bar/../baz", '/') == Path"foo/baz"

  doAssert relativePath(Path"/Users/me/bar/z.nim", Path"/Users/other/bad", '/') == Path"../../me/bar/z.nim"

  doAssert relativePath(Path"/Users/me/bar/z.nim", Path"/Users/other", '/') == Path"../me/bar/z.nim"

  # `//` is a UNC path, `/` is the current working directory's drive, so can't
  # run this test on Windows.
  when not doslikeFileSystem:
    doAssert relativePath(Path"/Users///me/bar//z.nim", Path"//Users/", '/') == Path"me/bar/z.nim"
  doAssert relativePath(Path"/Users/me/bar/z.nim", Path"/Users/me", '/') == Path"bar/z.nim"
  doAssert relativePath(Path"", Path"/users/moo", '/') == Path""
  doAssert relativePath(Path"foo", Path"", '/') == Path"foo"
  doAssert relativePath(Path"/foo", Path"/Foo", '/') == (when FileSystemCaseSensitive: Path"../foo" else: Path".")
  doAssert relativePath(Path"/Foo", Path"/foo", '/') == (when FileSystemCaseSensitive: Path"../Foo" else: Path".")
  doAssert relativePath(Path"/foo", Path"/fOO", '/') == (when FileSystemCaseSensitive: Path"../foo" else: Path".")
  doAssert relativePath(Path"/foO", Path"/foo", '/') == (when FileSystemCaseSensitive: Path"../foO" else: Path".")

  doAssert relativePath(Path"foo", Path".", '/') == Path"foo"
  doAssert relativePath(Path".", Path".", '/') == Path"."
  doAssert relativePath(Path"..", Path".", '/') == Path".."

  doAssert relativePath(Path"foo", Path"foo") == Path"."
  doAssert relativePath(Path"", Path"foo") == Path""
  doAssert relativePath(Path"././/foo", Path"foo//./") == Path"."

  doAssert relativePath(getCurrentDir() / Path"bar", Path"foo") == Path"../bar".unixToNativePath
  doAssert relativePath(Path"bar", getCurrentDir() / Path"foo") == Path"../bar".unixToNativePath

  when doslikeFileSystem:
    doAssert relativePath(r"c:\foo.nim".Path, r"C:\".Path) == r"foo.nim".Path
    doAssert relativePath(r"c:\foo\bar\baz.nim".Path, r"c:\foo".Path) == r"bar\baz.nim".Path
    doAssert relativePath(r"c:\foo\bar\baz.nim".Path, r"d:\foo".Path) == r"c:\foo\bar\baz.nim".Path
    doAssert relativePath(r"\foo\baz.nim".Path, r"\foo".Path) == r"baz.nim".Path
    doAssert relativePath(r"\foo\bar\baz.nim".Path, r"\bar".Path) == r"..\foo\bar\baz.nim".Path
    doAssert relativePath(r"\\foo\bar\baz.nim".Path, r"\\foo\bar".Path) == r"baz.nim".Path
    doAssert relativePath(r"\\foo\bar\baz.nim".Path, r"\\foO\bar".Path) == r"baz.nim".Path
    doAssert relativePath(r"\\foo\bar\baz.nim".Path, r"\\bar\bar".Path) == r"\\foo\bar\baz.nim".Path
    doAssert relativePath(r"\\foo\bar\baz.nim".Path, r"\\foo\car".Path) == r"\\foo\bar\baz.nim".Path
    doAssert relativePath(r"\\foo\bar\baz.nim".Path, r"\\goo\bar".Path) == r"\\foo\bar\baz.nim".Path
    doAssert relativePath(r"\\foo\bar\baz.nim".Path, r"c:\".Path) == r"\\foo\bar\baz.nim".Path
    doAssert relativePath(r"\\foo\bar\baz.nim".Path, r"\foo".Path) == r"\\foo\bar\baz.nim".Path
    doAssert relativePath(r"c:\foo.nim".Path, r"\foo".Path) == r"c:\foo.nim".Path

  doAssert joinPath(Path"usr", Path"") == unixToNativePath(Path"usr")
  doAssert joinPath(Path"usr", Path"") == (Path"usr").dup(add Path"")
  doAssert joinPath(Path"", Path"lib") == Path"lib"
  doAssert joinPath(Path"", Path"lib") == Path"".dup(add Path"lib")
  doAssert joinPath(Path"", Path"/lib") == unixToNativePath(Path"/lib")
  doAssert joinPath(Path"", Path"/lib") == unixToNativePath(Path"/lib")
  doAssert joinPath(Path"usr/", Path"/lib") == Path"usr/".dup(add Path"/lib")
  doAssert joinPath(Path"", Path"") == unixToNativePath(Path"") # issue #13455
  doAssert joinPath(Path"", Path"") == Path"".dup(add Path"")
  doAssert joinPath(Path"", Path"/") == unixToNativePath(Path"/")
  doAssert joinPath(Path"", Path"/") == Path"".dup(add Path"/")
  doAssert joinPath(Path"/", Path"/") == unixToNativePath(Path"/")
  doAssert joinPath(Path"/", Path"/") == Path"/".dup(add Path"/")
  doAssert joinPath(Path"/", Path"") == unixToNativePath(Path"/")
  doAssert joinPath(Path"/" / Path"") == unixToNativePath(Path"/") # weird test case...
  doAssert joinPath(Path"/", Path"/a/b/c") == unixToNativePath(Path"/a/b/c")
  doAssert joinPath(Path"foo/", Path"") == unixToNativePath(Path"foo/")
  doAssert joinPath(Path"foo/", Path"abc") == unixToNativePath(Path"foo/abc")
  doAssert joinPath(Path"foo//./", Path"abc/.//") == unixToNativePath(Path"foo/abc/")
  doAssert Path"foo//./".dup(add Path"abc/.//") == unixToNativePath(Path"foo/abc/")
  doAssert joinPath(Path"foo", Path"abc") == unixToNativePath(Path"foo/abc")
  doAssert Path"foo".dup(add Path"abc") == unixToNativePath(Path"foo/abc")
  doAssert joinPath(Path"", Path"abc") == unixToNativePath(Path"abc")

  doAssert joinPath(Path"zook/.", Path"abc") == unixToNativePath(Path"zook/abc")

  # controversial: inconsistent with `joinPath("zook/.","abc")`
  # on linux, `./foo` and `foo` are treated a bit differently for executables
  # but not `./foo/bar` and `foo/bar`
  doAssert joinPath(Path".", Path"/lib") == unixToNativePath(Path"./lib")
  doAssert joinPath(Path".", Path"abc") == unixToNativePath(Path"./abc")

  # cases related to issue #13455
  doAssert joinPath(Path"foo", Path"", Path"") == Path"foo"
  doAssert joinPath(Path"foo", Path"") == Path"foo"
  doAssert joinPath(Path"foo/", Path"") == unixToNativePath(Path"foo/")
  doAssert joinPath(Path"foo/", Path".") == Path"foo"
  doAssert joinPath(Path"foo", Path"./") == unixToNativePath(Path"foo/")
  doAssert joinPath(Path"foo", Path"", Path"bar/") == unixToNativePath(Path"foo/bar/")

  # issue #13579
  doAssert joinPath(Path"/foo", Path"../a") == unixToNativePath(Path"/a")
  doAssert joinPath(Path"/foo/", Path"../a") == unixToNativePath(Path"/a")
  doAssert joinPath(Path"/foo/.", Path"../a") == unixToNativePath(Path"/a")
  doAssert joinPath(Path"/foo/.b", Path"../a") == unixToNativePath(Path"/foo/a")
  doAssert joinPath(Path"/foo///", Path"..//a/") == unixToNativePath(Path"/a/")
  doAssert joinPath(Path"foo/", Path"../a") == unixToNativePath(Path"a")

  when doslikeFileSystem:
    doAssert joinPath(Path"C:\\Program Files (x86)\\Microsoft Visual Studio 14.0\\Common7\\Tools\\", Path"..\\..\\VC\\vcvarsall.bat") == r"C:\Program Files (x86)\Microsoft Visual Studio 14.0\VC\vcvarsall.bat".Path
    doAssert joinPath(Path"C:\\foo", Path"..\\a") == r"C:\a".Path
    doAssert joinPath(Path"C:\\foo\\", Path"..\\a") == r"C:\a".Path


block: # bug #23663
  var s: HashSet[Path]
  s.incl("/a/b/c/..".Path)
  doAssert "/a/b/".Path in s
  doAssert "/a/b/c".Path notin s

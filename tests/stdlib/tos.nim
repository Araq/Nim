discard """
  output: '''
All:
__really_obscure_dir_name/are.x
__really_obscure_dir_name/created
__really_obscure_dir_name/dirs
__really_obscure_dir_name/files.q
__really_obscure_dir_name/some
__really_obscure_dir_name/test
__really_obscure_dir_name/testing.r
__really_obscure_dir_name/these.txt
Files:
__really_obscure_dir_name/are.x
__really_obscure_dir_name/files.q
__really_obscure_dir_name/testing.r
__really_obscure_dir_name/these.txt
Dirs:
__really_obscure_dir_name/created
__really_obscure_dir_name/dirs
__really_obscure_dir_name/some
__really_obscure_dir_name/test
Raises
Raises
'''
  matrix: "--mm:refc; --mm:orc"
  joinable: false
"""
# test os path creation, iteration, and deletion

from stdtest/specialpaths import buildDir
import std/[syncio, assertions, osproc, os, strutils, pathnorm]

block fileOperations:
  let files = @["these.txt", "are.x", "testing.r", "files.q"]
  let dirs = @["some", "created", "test", "dirs"]

  let dname = "__really_obscure_dir_name"

  createDir(dname)
  doAssert dirExists(dname)

  block: # copyFile, copyFileToDir
    doAssertRaises(OSError): copyFile(dname/"nonexistent.txt", dname/"nonexistent.txt")
    let fname = "D20201009T112235"
    let fname2 = "D20201009T112235.2"
    let str = "foo1\0foo2\nfoo3\0"
    let file = dname/fname
    let file2 = dname/fname2
    writeFile(file, str)
    doAssert readFile(file) == str
    let sub = "sub"
    doAssertRaises(OSError): copyFile(file, dname/sub/fname2)
    doAssertRaises(OSError): copyFileToDir(file, dname/sub)
    doAssertRaises(ValueError): copyFileToDir(file, "")
    copyFile(file, file2)
    doAssert fileExists(file2)
    doAssert readFile(file2) == str
    createDir(dname/sub)
    copyFileToDir(file, dname/sub)
    doAssert fileExists(dname/sub/fname)
    removeDir(dname/sub)
    doAssert not dirExists(dname/sub)
    removeFile(file)
    removeFile(file2)

  # Test creating files and dirs
  for dir in dirs:
    createDir(dname/dir)
    doAssert dirExists(dname/dir)

  for file in files:
    let fh = open(dname/file, fmReadWrite)
    fh.close()
    doAssert fileExists(dname/file)

  echo "All:"

  template norm(x): untyped =
    (when defined(windows): x.replace('\\', '/') else: x)

  for path in walkPattern(dname/"*"):
    echo path.norm

  echo "Files:"

  for path in walkFiles(dname/"*"):
    echo path.norm

  echo "Dirs:"

  for path in walkDirs(dname/"*"):
    echo path.norm

  # Test removal of files dirs
  for dir in dirs:
    removeDir(dname/dir)
    doAssert: not dirExists(dname/dir)

  for file in files:
    removeFile(dname/file)
    doAssert: not fileExists(dname/file)

  removeDir(dname)
  doAssert: not dirExists(dname)

  # createDir should create recursive directories
  createDir(dirs[0] / dirs[1])
  doAssert dirExists(dirs[0] / dirs[1]) # true
  removeDir(dirs[0])

  # createDir should properly handle trailing separator
  createDir(dname / "")
  doAssert dirExists(dname) # true
  removeDir(dname)

  # createDir should raise IOError if the path exists
  # and is not a directory
  open(dname, fmWrite).close
  try:
    createDir(dname)
  except IOError:
    echo "Raises"
  removeFile(dname)

  # removeFile should not remove directory
  createDir(dname)
  try:
    removeFile(dname)
  except OSError:
    echo "Raises"
  removeDir(dname)

  # test copyDir:
  createDir("a/b")
  open("a/b/file.txt", fmWrite).close
  createDir("a/b/c")
  open("a/b/c/fileC.txt", fmWrite).close

  copyDir("a", "../dest/a")
  removeDir("a")

  doAssert dirExists("../dest/a/b")
  doAssert fileExists("../dest/a/b/file.txt")

  doAssert fileExists("../dest/a/b/c/fileC.txt")
  removeDir("../dest")

  # test copyDir:
  # if separator at the end of a path
  createDir("a/b")
  open("a/file.txt", fmWrite).close

  copyDir("a/", "../dest/a/")
  removeDir("a")

  doAssert dirExists("../dest/a/b")
  doAssert fileExists("../dest/a/file.txt")
  removeDir("../dest")

  # createDir should not fail if `dir` is empty
  createDir("")


  when defined(linux): # bug #24174
    createDir("a/b")
    open("a/file.txt", fmWrite).close

    if not fileExists("a/fifoFile"):
      doAssert execCmd("mkfifo -m 600 a/fifoFile") == 0

    copyDir("a/", "../dest/a/", skipSpecial = true)
    copyDirWithPermissions("a/", "../dest2/a/", skipSpecial = true)
    removeDir("a")

  # Symlink handling in `copyFile`, `copyFileWithPermissions`, `copyFileToDir`,
  # `copyDir`, `copyDirWithPermissions`, `moveFile`, and `moveDir`.
  block:
    const symlinksAreHandled = not defined(windows)
    const dname = buildDir/"D20210116T140629"
    const subDir = dname/"sub"
    const subDir2 = dname/"sub2"
    const brokenSymlinkName = "D20210101T191320_BROKEN_SYMLINK"
    const brokenSymlink = dname/brokenSymlinkName
    const brokenSymlinkSrc = "D20210101T191320_nonexistent"
    const brokenSymlinkCopy = brokenSymlink & "_COPY"
    const brokenSymlinkInSubDir = subDir/brokenSymlinkName
    const brokenSymlinkInSubDir2 = subDir2/brokenSymlinkName

    createDir(subDir)
    createSymlink(brokenSymlinkSrc, brokenSymlink)

    # Test copyFile
    when symlinksAreHandled:
      doAssertRaises(OSError):
        copyFile(brokenSymlink, brokenSymlinkCopy)
      doAssertRaises(OSError):
        copyFile(brokenSymlink, brokenSymlinkCopy, {cfSymlinkFollow})
    copyFile(brokenSymlink, brokenSymlinkCopy, {cfSymlinkIgnore})
    doAssert not fileExists(brokenSymlinkCopy)
    copyFile(brokenSymlink, brokenSymlinkCopy, {cfSymlinkAsIs})
    when symlinksAreHandled:
      doAssert expandSymlink(brokenSymlinkCopy) == brokenSymlinkSrc
      removeFile(brokenSymlinkCopy)
    else:
      doAssert not fileExists(brokenSymlinkCopy)
    doAssertRaises(AssertionDefect):
      copyFile(brokenSymlink, brokenSymlinkCopy,
               {cfSymlinkAsIs, cfSymlinkFollow})

    # Test copyFileWithPermissions
    when symlinksAreHandled:
      doAssertRaises(OSError):
        copyFileWithPermissions(brokenSymlink, brokenSymlinkCopy)
      doAssertRaises(OSError):
        copyFileWithPermissions(brokenSymlink, brokenSymlinkCopy,
                                options = {cfSymlinkFollow})
    copyFileWithPermissions(brokenSymlink, brokenSymlinkCopy,
                            options = {cfSymlinkIgnore})
    doAssert not fileExists(brokenSymlinkCopy)
    copyFileWithPermissions(brokenSymlink, brokenSymlinkCopy,
                            options = {cfSymlinkAsIs})
    when symlinksAreHandled:
      doAssert expandSymlink(brokenSymlinkCopy) == brokenSymlinkSrc
      removeFile(brokenSymlinkCopy)
    else:
      doAssert not fileExists(brokenSymlinkCopy)
    doAssertRaises(AssertionDefect):
      copyFileWithPermissions(brokenSymlink, brokenSymlinkCopy,
                              options = {cfSymlinkAsIs, cfSymlinkFollow})

    # Test copyFileToDir
    when symlinksAreHandled:
      doAssertRaises(OSError):
        copyFileToDir(brokenSymlink, subDir)
      doAssertRaises(OSError):
        copyFileToDir(brokenSymlink, subDir, {cfSymlinkFollow})
    copyFileToDir(brokenSymlink, subDir, {cfSymlinkIgnore})
    doAssert not fileExists(brokenSymlinkInSubDir)
    copyFileToDir(brokenSymlink, subDir, {cfSymlinkAsIs})
    when symlinksAreHandled:
      doAssert expandSymlink(brokenSymlinkInSubDir) == brokenSymlinkSrc
      removeFile(brokenSymlinkInSubDir)
    else:
      doAssert not fileExists(brokenSymlinkInSubDir)

    createSymlink(brokenSymlinkSrc, brokenSymlinkInSubDir)

    # Test copyDir
    copyDir(subDir, subDir2)
    when symlinksAreHandled:
      doAssert expandSymlink(brokenSymlinkInSubDir2) == brokenSymlinkSrc
    else:
      doAssert not fileExists(brokenSymlinkInSubDir2)
    removeDir(subDir2)

    # Test copyDirWithPermissions
    copyDirWithPermissions(subDir, subDir2)
    when symlinksAreHandled:
      doAssert expandSymlink(brokenSymlinkInSubDir2) == brokenSymlinkSrc
    else:
      doAssert not fileExists(brokenSymlinkInSubDir2)
    removeDir(subDir2)

    # Test moveFile
    moveFile(brokenSymlink, brokenSymlinkCopy)
    when not defined(windows):
      doAssert expandSymlink(brokenSymlinkCopy) == brokenSymlinkSrc
    else:
      doAssert symlinkExists(brokenSymlinkCopy)
    removeFile(brokenSymlinkCopy)

    # Test moveDir
    moveDir(subDir, subDir2)
    when not defined(windows):
      doAssert expandSymlink(brokenSymlinkInSubDir2) == brokenSymlinkSrc
    else:
      doAssert symlinkExists(brokenSymlinkInSubDir2)

    removeDir(dname)

block: # moveFile
  let tempDir = getTempDir() / "D20210609T151608"
  createDir(tempDir)
  defer: removeDir(tempDir)

  writeFile(tempDir / "a.txt", "")
  moveFile(tempDir / "a.txt", tempDir / "b.txt")
  doAssert not fileExists(tempDir / "a.txt")
  doAssert fileExists(tempDir / "b.txt")
  removeFile(tempDir / "b.txt")

  createDir(tempDir / "moveFile_test")
  writeFile(tempDir / "moveFile_test/a.txt", "")
  moveFile(tempDir / "moveFile_test/a.txt", tempDir / "moveFile_test/b.txt")
  doAssert not fileExists(tempDir / "moveFile_test/a.txt")
  doAssert fileExists(tempDir / "moveFile_test/b.txt")
  removeDir(tempDir / "moveFile_test")

  createDir(tempDir / "moveFile_test")
  writeFile(tempDir / "a.txt", "")
  moveFile(tempDir / "a.txt", tempDir / "moveFile_test/b.txt")
  doAssert not fileExists(tempDir / "a.txt")
  doAssert fileExists(tempDir / "moveFile_test/b.txt")
  removeDir(tempDir / "moveFile_test")

block: # moveDir
  let tempDir = getTempDir() / "D20210609T161443"
  createDir(tempDir)
  defer: removeDir(tempDir)

  createDir(tempDir / "moveDir_test")
  moveDir(tempDir / "moveDir_test/", tempDir / "moveDir_test_dest")
  doAssert not dirExists(tempDir / "moveDir_test")
  doAssert dirExists(tempDir / "moveDir_test_dest")
  removeDir(tempDir / "moveDir_test_dest")

  createDir(tempDir / "moveDir_test")
  writeFile(tempDir / "moveDir_test/a.txt", "")
  moveDir(tempDir / "moveDir_test", tempDir / "moveDir_test_dest")
  doAssert not dirExists(tempDir / "moveDir_test")
  doAssert not fileExists(tempDir / "moveDir_test/a.txt")
  doAssert dirExists(tempDir / "moveDir_test_dest")
  doAssert fileExists(tempDir / "moveDir_test_dest/a.txt")
  removeDir(tempDir / "moveDir_test_dest")

import times
block modificationTime:
  # Test get/set modification times
  # Should support at least microsecond resolution
  let tm = fromUnix(0) + 100.microseconds
  writeFile("a", "")
  setLastModificationTime("a", tm)

  when defined(macosx):
    doAssert true
  else:
    doAssert getLastModificationTime("a") == tm
  removeFile("a")

block walkDirRec:
  createDir("walkdir_test/a/b")
  open("walkdir_test/a/b/file_1", fmWrite).close()
  open("walkdir_test/a/file_2", fmWrite).close()

  for p in walkDirRec("walkdir_test"):
    doAssert p.fileExists
    doAssert p.startsWith("walkdir_test")

  var s: seq[string]
  for p in walkDirRec("walkdir_test", {pcFile}, {pcDir}, relative = true):
    s.add(p)

  doAssert s.len == 2
  doAssert "a" / "b" / "file_1" in s
  doAssert "a" / "file_2" in s

  removeDir("walkdir_test")

import std/sequtils

block: # walkDir
  doAssertRaises(OSError):
    for a in walkDir("nonexistent", checkDir = true): discard
  doAssertRaises(OSError):
    for p in walkDirRec("nonexistent", checkDir = true): discard

  when not defined(windows):
    block walkDirRelative:
      createDir("walkdir_test")
      createSymlink(".", "walkdir_test/c")
      for k, p in walkDir("walkdir_test", true):
        doAssert k == pcLinkToDir
      removeDir("walkdir_test")

  when defined(posix):
    block walkDirSpecial:
      createDir("walkdir_test")
      doAssert execShellCmd("mkfifo walkdir_test/fifo") == 0
      createSymlink("fifo", "walkdir_test/fifo_link")
      let withSpecialFiles = toSeq(walkDir("walkdir_test", relative = true))
      doAssert (withSpecialFiles.len == 2 and
                (pcFile, "fifo") in withSpecialFiles and
                (pcLinkToFile, "fifo_link") in withSpecialFiles)
      # now Unix special files are excluded from walkdir output:
      let skipSpecialFiles = toSeq(walkDir("walkdir_test", relative = true,
                                           skipSpecial = true))
      doAssert skipSpecialFiles.len == 0
      removeDir("walkdir_test")

block normalizedPath:
  doAssert normalizedPath("") == ""
  block relative:
    doAssert normalizedPath(".") == "."
    doAssert normalizedPath("foo/..") == "."
    doAssert normalizedPath("foo//../bar/.") == "bar"
    doAssert normalizedPath("..") == ".."
    doAssert normalizedPath("../") == ".."
    doAssert normalizedPath("../..") == unixToNativePath"../.."
    doAssert normalizedPath("../a/..") == ".."
    doAssert normalizedPath("../a/../") == ".."
    doAssert normalizedPath("./") == "."

  block absolute:
    doAssert normalizedPath("/") == unixToNativePath"/"
    doAssert normalizedPath("/.") == unixToNativePath"/"
    doAssert normalizedPath("/..") == unixToNativePath"/.."
    doAssert normalizedPath("/../") == unixToNativePath"/.."
    doAssert normalizedPath("/../..") == unixToNativePath"/../.."
    doAssert normalizedPath("/../../") == unixToNativePath"/../.."
    doAssert normalizedPath("/../../../") == unixToNativePath"/../../.."
    doAssert normalizedPath("/a/b/../../foo") == unixToNativePath"/foo"
    doAssert normalizedPath("/a/b/../../../foo") == unixToNativePath"/../foo"
    doAssert normalizedPath("/./") == unixToNativePath"/"
    doAssert normalizedPath("//") == unixToNativePath"/"
    doAssert normalizedPath("///") == unixToNativePath"/"
    doAssert normalizedPath("/a//b") == unixToNativePath"/a/b"
    doAssert normalizedPath("/a///b") == unixToNativePath"/a/b"
    doAssert normalizedPath("/a/b/c/..") == unixToNativePath"/a/b"
    doAssert normalizedPath("/a/b/c/../") == unixToNativePath"/a/b"

block isHidden:
  when defined(posix):
    doAssert ".foo.txt".isHidden
    doAssert "bar/.foo.ext".isHidden
    doAssert not "bar".isHidden
    doAssert not "foo/".isHidden
    doAssert ".foo/.".isHidden
    # Corner cases: `isHidden` is not yet `..` aware
    doAssert not ".foo/..".isHidden

block absolutePath:
  doAssertRaises(ValueError): discard absolutePath("a", "b")
  doAssert absolutePath("a") == getCurrentDir() / "a"
  doAssert absolutePath("a", "/b") == "/b" / "a"
  when defined(posix):
    doAssert absolutePath("a", "/b/") == "/b" / "a"
    doAssert absolutePath("a", "/b/c") == "/b/c" / "a"
    doAssert absolutePath("/a", "b/") == "/a"

block splitFile:
  doAssert splitFile("") == ("", "", "")
  doAssert splitFile("abc/") == ("abc", "", "")
  doAssert splitFile("/") == ("/", "", "")
  doAssert splitFile("./abc") == (".", "abc", "")
  doAssert splitFile(".txt") == ("", ".txt", "")
  doAssert splitFile("abc/.txt") == ("abc", ".txt", "")
  doAssert splitFile("abc") == ("", "abc", "")
  doAssert splitFile("abc.txt") == ("", "abc", ".txt")
  doAssert splitFile("/abc.txt") == ("/", "abc", ".txt")
  doAssert splitFile("/foo/abc.txt") == ("/foo", "abc", ".txt")
  doAssert splitFile("/foo/abc.txt.gz") == ("/foo", "abc.txt", ".gz")
  doAssert splitFile(".") == ("", ".", "")
  doAssert splitFile("abc/.") == ("abc", ".", "")
  doAssert splitFile("..") == ("", "..", "")
  doAssert splitFile("a/..") == ("a", "..", "")
  doAssert splitFile("/foo/abc....txt") == ("/foo", "abc...", ".txt")

# execShellCmd is tested in tosproc

block ospaths:
  doAssert unixToNativePath("") == ""
  doAssert unixToNativePath(".") == $CurDir
  doAssert unixToNativePath("..") == $ParDir
  doAssert isAbsolute(unixToNativePath("/"))
  doAssert isAbsolute(unixToNativePath("/", "a"))
  doAssert isAbsolute(unixToNativePath("/a"))
  doAssert isAbsolute(unixToNativePath("/a", "a"))
  doAssert isAbsolute(unixToNativePath("/a/b"))
  doAssert isAbsolute(unixToNativePath("/a/b", "a"))
  doAssert unixToNativePath("a/b") == joinPath("a", "b")

  when defined(macos):
    doAssert unixToNativePath("./") == ":"
    doAssert unixToNativePath("./abc") == ":abc"
    doAssert unixToNativePath("../abc") == "::abc"
    doAssert unixToNativePath("../../abc") == ":::abc"
    doAssert unixToNativePath("/abc", "a") == "abc"
    doAssert unixToNativePath("/abc/def", "a") == "abc:def"
  elif doslikeFileSystem:
    doAssert unixToNativePath("./") == ".\\"
    doAssert unixToNativePath("./abc") == ".\\abc"
    doAssert unixToNativePath("../abc") == "..\\abc"
    doAssert unixToNativePath("../../abc") == "..\\..\\abc"
    doAssert unixToNativePath("/abc", "a") == "a:\\abc"
    doAssert unixToNativePath("/abc/def", "a") == "a:\\abc\\def"
  else:
    #Tests for unix
    doAssert unixToNativePath("./") == "./"
    doAssert unixToNativePath("./abc") == "./abc"
    doAssert unixToNativePath("../abc") == "../abc"
    doAssert unixToNativePath("../../abc") == "../../abc"
    doAssert unixToNativePath("/abc", "a") == "/abc"
    doAssert unixToNativePath("/abc/def", "a") == "/abc/def"

  block extractFilenameTest:
    doAssert extractFilename("") == ""
    when defined(posix):
      doAssert extractFilename("foo/bar") == "bar"
      doAssert extractFilename("foo/bar.txt") == "bar.txt"
      doAssert extractFilename("foo/") == ""
      doAssert extractFilename("/") == ""
    when doslikeFileSystem:
      doAssert extractFilename(r"foo\bar") == "bar"
      doAssert extractFilename(r"foo\bar.txt") == "bar.txt"
      doAssert extractFilename(r"foo\") == ""
      doAssert extractFilename(r"C:\") == ""

  block lastPathPartTest:
    doAssert lastPathPart("") == ""
    when defined(posix):
      doAssert lastPathPart("foo/bar.txt") == "bar.txt"
      doAssert lastPathPart("foo/") == "foo"
      doAssert lastPathPart("/") == ""
    when doslikeFileSystem:
      doAssert lastPathPart(r"foo\bar.txt") == "bar.txt"
      doAssert lastPathPart(r"foo\") == "foo"

  template canon(x): untyped = normalizePath(x, '/')
  doAssert canon"/foo/../bar" == "/bar"
  doAssert canon"foo/../bar" == "bar"

  doAssert canon"/f/../bar///" == "/bar"
  doAssert canon"f/..////bar" == "bar"

  doAssert canon"../bar" == "../bar"
  doAssert canon"/../bar" == "/../bar"

  doAssert canon("foo/../../bar/") == "../bar"
  doAssert canon("./bla/blob/") == "bla/blob"
  doAssert canon(".hiddenFile") == ".hiddenFile"
  doAssert canon("./bla/../../blob/./zoo.nim") == "../blob/zoo.nim"

  doAssert canon("C:/file/to/this/long") == "C:/file/to/this/long"
  doAssert canon("") == ""
  doAssert canon("foobar") == "foobar"
  doAssert canon("f/////////") == "f"

  doAssert relativePath("/foo/bar//baz.nim", "/foo", '/') == "bar/baz.nim"
  doAssert normalizePath("./foo//bar/../baz", '/') == "foo/baz"

  doAssert relativePath("/Users/me/bar/z.nim", "/Users/other/bad", '/') == "../../me/bar/z.nim"

  doAssert relativePath("/Users/me/bar/z.nim", "/Users/other", '/') == "../me/bar/z.nim"

  # `//` is a UNC path, `/` is the current working directory's drive, so can't
  # run this test on Windows.
  when not doslikeFileSystem:
    doAssert relativePath("/Users///me/bar//z.nim", "//Users/", '/') == "me/bar/z.nim"
  doAssert relativePath("/Users/me/bar/z.nim", "/Users/me", '/') == "bar/z.nim"
  doAssert relativePath("", "/users/moo", '/') == ""
  doAssert relativePath("foo", "", '/') == "foo"
  doAssert relativePath("/foo", "/Foo", '/') == (when FileSystemCaseSensitive: "../foo" else: ".")
  doAssert relativePath("/Foo", "/foo", '/') == (when FileSystemCaseSensitive: "../Foo" else: ".")
  doAssert relativePath("/foo", "/fOO", '/') == (when FileSystemCaseSensitive: "../foo" else: ".")
  doAssert relativePath("/foO", "/foo", '/') == (when FileSystemCaseSensitive: "../foO" else: ".")

  doAssert relativePath("foo", ".", '/') == "foo"
  doAssert relativePath(".", ".", '/') == "."
  doAssert relativePath("..", ".", '/') == ".."

  doAssert relativePath("foo", "foo") == "."
  doAssert relativePath("", "foo") == ""
  doAssert relativePath("././/foo", "foo//./") == "."

  doAssert relativePath(getCurrentDir() / "bar", "foo") == "../bar".unixToNativePath
  doAssert relativePath("bar", getCurrentDir() / "foo") == "../bar".unixToNativePath

  when doslikeFileSystem:
    doAssert relativePath(r"c:\foo.nim", r"C:\") == r"foo.nim"
    doAssert relativePath(r"c:\foo\bar\baz.nim", r"c:\foo") == r"bar\baz.nim"
    doAssert relativePath(r"c:\foo\bar\baz.nim", r"d:\foo") == r"c:\foo\bar\baz.nim"
    doAssert relativePath(r"\foo\baz.nim", r"\foo") == r"baz.nim"
    doAssert relativePath(r"\foo\bar\baz.nim", r"\bar") == r"..\foo\bar\baz.nim"
    doAssert relativePath(r"\\foo\bar\baz.nim", r"\\foo\bar") == r"baz.nim"
    doAssert relativePath(r"\\foo\bar\baz.nim", r"\\foO\bar") == r"baz.nim"
    doAssert relativePath(r"\\foo\bar\baz.nim", r"\\bar\bar") == r"\\foo\bar\baz.nim"
    doAssert relativePath(r"\\foo\bar\baz.nim", r"\\foo\car") == r"\\foo\bar\baz.nim"
    doAssert relativePath(r"\\foo\bar\baz.nim", r"\\goo\bar") == r"\\foo\bar\baz.nim"
    doAssert relativePath(r"\\foo\bar\baz.nim", r"c:\") == r"\\foo\bar\baz.nim"
    doAssert relativePath(r"\\foo\bar\baz.nim", r"\foo") == r"\\foo\bar\baz.nim"
    doAssert relativePath(r"c:\foo.nim", r"\foo") == r"c:\foo.nim"

  doAssert joinPath("usr", "") == unixToNativePath"usr"
  doAssert joinPath("", "lib") == "lib"
  doAssert joinPath("", "/lib") == unixToNativePath"/lib"
  doAssert joinPath("usr/", "/lib") == unixToNativePath"usr/lib"
  doAssert joinPath("", "") == unixToNativePath"" # issue #13455
  doAssert joinPath("", "/") == unixToNativePath"/"
  doAssert joinPath("/", "/") == unixToNativePath"/"
  doAssert joinPath("/", "") == unixToNativePath"/"
  doAssert joinPath("/" / "") == unixToNativePath"/" # weird test case...
  doAssert joinPath("/", "/a/b/c") == unixToNativePath"/a/b/c"
  doAssert joinPath("foo/", "") == unixToNativePath"foo/"
  doAssert joinPath("foo/", "abc") == unixToNativePath"foo/abc"
  doAssert joinPath("foo//./", "abc/.//") == unixToNativePath"foo/abc/"
  doAssert joinPath("foo", "abc") == unixToNativePath"foo/abc"
  doAssert joinPath("", "abc") == unixToNativePath"abc"

  doAssert joinPath("zook/.", "abc") == unixToNativePath"zook/abc"

  # controversial: inconsistent with `joinPath("zook/.","abc")`
  # on linux, `./foo` and `foo` are treated a bit differently for executables
  # but not `./foo/bar` and `foo/bar`
  doAssert joinPath(".", "/lib") == unixToNativePath"./lib"
  doAssert joinPath(".", "abc") == unixToNativePath"./abc"

  # cases related to issue #13455
  doAssert joinPath("foo", "", "") == "foo"
  doAssert joinPath("foo", "") == "foo"
  doAssert joinPath("foo/", "") == unixToNativePath"foo/"
  doAssert joinPath("foo/", ".") == "foo"
  doAssert joinPath("foo", "./") == unixToNativePath"foo/"
  doAssert joinPath("foo", "", "bar/") == unixToNativePath"foo/bar/"

  # issue #13579
  doAssert joinPath("/foo", "../a") == unixToNativePath"/a"
  doAssert joinPath("/foo/", "../a") == unixToNativePath"/a"
  doAssert joinPath("/foo/.", "../a") == unixToNativePath"/a"
  doAssert joinPath("/foo/.b", "../a") == unixToNativePath"/foo/a"
  doAssert joinPath("/foo///", "..//a/") == unixToNativePath"/a/"
  doAssert joinPath("foo/", "../a") == unixToNativePath"a"

  when doslikeFileSystem:
    doAssert joinPath("C:\\Program Files (x86)\\Microsoft Visual Studio 14.0\\Common7\\Tools\\", "..\\..\\VC\\vcvarsall.bat") == r"C:\Program Files (x86)\Microsoft Visual Studio 14.0\VC\vcvarsall.bat"
    doAssert joinPath("C:\\foo", "..\\a") == r"C:\a"
    doAssert joinPath("C:\\foo\\", "..\\a") == r"C:\a"

block getTempDir:
  block TMPDIR:
    # TMPDIR env var is not used if either of these are defined.
    when not (defined(tempDir) or defined(windows) or defined(android)):
      if existsEnv("TMPDIR"):
        let origTmpDir = getEnv("TMPDIR")
        putEnv("TMPDIR", "/mytmp")
        doAssert getTempDir() == "/mytmp/"
        delEnv("TMPDIR")
        doAssert getTempDir() == "/tmp/"
        putEnv("TMPDIR", origTmpDir)
      else:
        doAssert getTempDir() == "/tmp/"

block: # getCacheDir
  doAssert getCacheDir().dirExists

block isRelativeTo:
  doAssert isRelativeTo("/foo", "/")
  doAssert isRelativeTo("/foo/bar", "/foo")
  doAssert isRelativeTo("foo/bar", "foo")
  doAssert isRelativeTo("/foo/bar.nim", "/foo/bar.nim")
  doAssert isRelativeTo("./foo/", "foo")
  doAssert isRelativeTo("foo", "./foo/")
  doAssert isRelativeTo(".", ".")
  doAssert isRelativeTo("foo/bar", ".")
  doAssert not isRelativeTo("foo/bar.nims", "foo/bar.nim")
  doAssert not isRelativeTo("/foo2", "/foo")

block: # quoteShellWindows
  doAssert quoteShellWindows("aaa") == "aaa"
  doAssert quoteShellWindows("aaa\"") == "aaa\\\""
  doAssert quoteShellWindows("") == "\"\""

block: # quoteShellCommand
  when defined(windows):
    doAssert quoteShellCommand(["a b c", "d", "e"]) == """"a b c" d e"""
    doAssert quoteShellCommand(["""ab"c""", r"\", "d"]) == """ab\"c \ d"""
    doAssert quoteShellCommand(["""ab"c""", """ \""", "d"]) == """ab\"c " \\" d"""
    doAssert quoteShellCommand(["""a\\\b""", """de fg""", "h"]) == """a\\\b "de fg" h"""
    doAssert quoteShellCommand(["""a\"b""", "c", "d"]) == """a\\\"b c d"""
    doAssert quoteShellCommand(["""a\\b c""", "d", "e"]) == """"a\\b c" d e"""
    doAssert quoteShellCommand(["""a\\b\ c""", "d", "e"]) == """"a\\b\ c" d e"""
    doAssert quoteShellCommand(["ab", ""]) == """ab """""

block: # quoteShellPosix
  doAssert quoteShellPosix("aaa") == "aaa"
  doAssert quoteShellPosix("aaa a") == "'aaa a'"
  doAssert quoteShellPosix("") == "''"
  doAssert quoteShellPosix("a'a") == "'a'\"'\"'a'"

block: # quoteShell
  when defined(posix):
    doAssert quoteShell("") == "''"

block: # normalizePathEnd
  # handle edge cases correctly: shouldn't affect whether path is
  # absolute/relative
  doAssert "".normalizePathEnd(true) == ""
  doAssert "".normalizePathEnd(false) == ""
  doAssert "/".normalizePathEnd(true) == $DirSep
  doAssert "/".normalizePathEnd(false) == $DirSep

  when defined(posix):
    doAssert "//".normalizePathEnd(false) == "/"
    doAssert "foo.bar//".normalizePathEnd == "foo.bar"
    doAssert "bar//".normalizePathEnd(trailingSep = true) == "bar/"
  when defined(windows):
    doAssert r"C:\foo\\".normalizePathEnd == r"C:\foo"
    doAssert r"C:\foo".normalizePathEnd(trailingSep = true) == r"C:\foo\"
    # this one is controversial: we could argue for returning `D:\` instead,
    # but this is simplest.
    doAssert r"D:\".normalizePathEnd == r"D:"
    doAssert r"E:/".normalizePathEnd(trailingSep = true) == r"E:\"
    doAssert "/".normalizePathEnd == r"\"


import sugar

block: # normalizeExe
  doAssert "".dup(normalizeExe) == ""
  when defined(posix):
    doAssert "foo".dup(normalizeExe) == "./foo"
    doAssert "foo/../bar".dup(normalizeExe) == "foo/../bar"
  when defined(windows):
    doAssert "foo".dup(normalizeExe) == "foo"

block: # isAdmin
  let isAzure = existsEnv("TF_BUILD") # xxx factor with testament.specs.isAzure
  # In Azure on Windows tests run as an admin user
  if isAzure and defined(windows): doAssert isAdmin()
  # In Azure on POSIX tests run as a normal user
  if isAzure and defined(posix): doAssert not isAdmin()


import sugar

block: # normalizeExe
  doAssert "".dup(normalizeExe) == ""
  when defined(posix):
    doAssert "foo".dup(normalizeExe) == "./foo"
    doAssert "foo/../bar".dup(normalizeExe) == "foo/../bar"
  when defined(windows):
    doAssert "foo".dup(normalizeExe) == "foo"

block: # isAdmin
  let isAzure = existsEnv("TF_BUILD") # xxx factor with testament.specs.isAzure
  # In Azure on Windows tests run as an admin user
  if isAzure and defined(windows): doAssert isAdmin()
  # In Azure on POSIX tests run as a normal user
  if isAzure and defined(posix): doAssert not isAdmin()

when doslikeFileSystem:
  import std/private/ntpath

  block: # Bug #19103 UNC paths

    # Easiest way of generating a valid, readable and writable UNC path
    let tempDir = r"\\?\" & getTempDir()
    doAssert dirExists tempDir
    createDir tempDir / "test"
    removeDir tempDir / "test"
    createDir tempDir / "recursive" / "test"
    removeDir tempDir / "recursive" / "test"

    let tempDir2 = getTempDir()
    let (drive, pathNoDrive) = splitDrive(tempDir2)
    setCurrentDir drive
    doAssert cmpIgnoreCase(getCurrentDir().splitDrive.drive, drive) == 0

    # Test `\Users` path syntax on Windows by stripping away drive. `\`
    # resolves to the drive in current working directory. This drive will be
    # the same as `tempDir2` because of the `setCurrentDir` above.
    doAssert pathNoDrive[0] == '\\'
    createDir pathNoDrive / "test"
    doAssert dirExists pathNoDrive / "test"
    removeDir pathNoDrive / "test"

    doAssert splitPath("//?/c:") == ("//?/c:", "")

    doAssert relativePath("//?/c:///Users//me", "//?/c:", '/') == "Users/me"

    doAssert parentDir(r"\\?\c:") == r""
    doAssert parentDir(r"//?/c:/Users") == r"\\?\c:"
    doAssert parentDir(r"\\localhost\c$") == r""
    doAssert parentDir(r"\Users") == r"\"

    doAssert tailDir("//?/c:") == ""
    doAssert tailDir("//?/c:/Users") == "Users"
    doAssert tailDir(r"\\localhost\c$\Windows\System32") == r"Windows\System32"

    doAssert isRootDir("//?/c:")
    doAssert isRootDir("//?/UNC/localhost/c$")
    doAssert not isRootDir(r"\\?\c:\Users")

    doAssert parentDirs(r"C:\Users", fromRoot = true).toSeq == @[r"C:\", r"C:\Users"]
    doAssert parentDirs(r"C:\Users", fromRoot = false).toSeq == @[r"C:\Users", r"C:"]
    doAssert parentDirs(r"\\?\c:\Users", fromRoot = true).toSeq ==
      @[r"\\?\c:\", r"\\?\c:\Users"]
    doAssert parentDirs(r"\\?\c:\Users", fromRoot = false).toSeq ==
      @[r"\\?\c:\Users", r"\\?\c:"]
    doAssert parentDirs(r"//localhost/c$/Users", fromRoot = true).toSeq ==
      @[r"//localhost/c$/", r"//localhost/c$/Users"]
    doAssert parentDirs(r"//?/UNC/localhost/c$/Users", fromRoot = false).toSeq ==
      @[r"//?/UNC/localhost/c$/Users", r"\\?\UNC\localhost\c$"]
    doAssert parentDirs(r"\Users", fromRoot = true).toSeq == @[r"\", r"\Users"]
    doAssert parentDirs(r"\Users", fromRoot = false).toSeq == @[r"\Users", r"\"]

    doAssert r"//?/c:" /../ "d/e" == r"\\?\c:\d\e"
    doAssert r"//?/c:/Users" /../ "d/e" == r"\\?\c:\d\e"
    doAssert r"\\localhost\c$" /../ "d/e" == r"\\localhost\c$\d\e"

    doAssert splitFile("//?/c:") == ("//?/c:", "", "")
    doAssert splitFile("//?/c:/Users") == ("//?/c:", "Users", "")
    doAssert splitFile(r"\\localhost\c$\test.txt") == (r"\\localhost\c$", "test", ".txt")

else:
  block: # parentDirs
    doAssert parentDirs("/home", fromRoot=true).toSeq == @["/", "/home"]
    doAssert parentDirs("/home", fromRoot=false).toSeq == @["/home", "/"]
    doAssert parentDirs("home", fromRoot=true).toSeq == @["home"]
    doAssert parentDirs("home", fromRoot=false).toSeq == @["home"]

    doAssert parentDirs("/home/user", fromRoot=true).toSeq == @["/", "/home/", "/home/user"]
    doAssert parentDirs("/home/user", fromRoot=false).toSeq == @["/home/user", "/home", "/"]
    doAssert parentDirs("home/user", fromRoot=true).toSeq == @["home/", "home/user"]
    doAssert parentDirs("home/user", fromRoot=false).toSeq == @["home/user", "home"]


# https://github.com/nim-lang/Nim/pull/19643#issuecomment-1235102314
block:  # isValidFilename
  # Negative Tests.
  doAssert not isValidFilename("abcd", maxLen = 2)
  doAssert not isValidFilename("0123456789", maxLen = 8)
  doAssert not isValidFilename("con")
  doAssert not isValidFilename("aux")
  doAssert not isValidFilename("prn")
  doAssert not isValidFilename("OwO|UwU")
  doAssert not isValidFilename(" foo")
  doAssert not isValidFilename("foo ")
  doAssert not isValidFilename("foo.")
  doAssert not isValidFilename("con.txt")
  doAssert not isValidFilename("aux.bat")
  doAssert not isValidFilename("prn.exe")
  doAssert not isValidFilename("nim>.nim")
  doAssert not isValidFilename(" foo.log")
  # Positive Tests.
  doAssert isValidFilename("abcd", maxLen = 42.Positive)
  doAssert isValidFilename("c0n")
  doAssert isValidFilename("foo.aux")
  doAssert isValidFilename("bar.prn")
  doAssert isValidFilename("OwO_UwU")
  doAssert isValidFilename("cron")
  doAssert isValidFilename("ux.bat")
  doAssert isValidFilename("nim.nim")
  doAssert isValidFilename("foo.log")

block: # searchExtPos
  doAssert "foo.nim".searchExtPos == 3
  doAssert "/foo.nim".searchExtPos == 4
  doAssert "".searchExtPos == -1
  doAssert "/".searchExtPos == -1
  doAssert "a.b/foo".searchExtPos == -1
  doAssert ".".searchExtPos == -1
  doAssert "foo.".searchExtPos == 3
  doAssert "foo..".searchExtPos == 4
  doAssert "..".searchExtPos == -1
  doAssert "...".searchExtPos == -1
  doAssert "./".searchExtPos == -1
  doAssert "../".searchExtPos == -1
  doAssert "/.".searchExtPos == -1
  doAssert "/..".searchExtPos == -1
  doAssert ".b".searchExtPos == -1
  doAssert "..b".searchExtPos == -1
  doAssert "/.b".searchExtPos == -1
  doAssert "a/.b".searchExtPos == -1
  doAssert ".a.b".searchExtPos == 2
  doAssert "a/.b.c".searchExtPos == 4
  doAssert "a/..b".searchExtPos == -1
  doAssert "a/b..c".searchExtPos == 4

  when doslikeFileSystem:
    doAssert "c:a.b".searchExtPos == 3
    doAssert "c:.a".searchExtPos == -1
    doAssert r"c:\.a".searchExtPos == -1
    doAssert "c:..a".searchExtPos == -1
    doAssert r"c:\..a".searchExtPos == -1
    doAssert "c:.a.b".searchExtPos == 4

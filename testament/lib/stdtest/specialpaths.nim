#[
todo: move findNimStdLibCompileTime, findNimStdLib here
xxx: factor pending https://github.com/timotheecour/Nim/issues/616

## note: $lib vs $nim
note: these can resolve to 3 different paths if running via `nim c --lib:lib foo`,
eg if compiler was installed via nimble (or is in nim path), and nim is external
(ie not in `$lib/../bin/` dir)

import "$lib/../compiler/nimpaths" # <- most robust if you want to favor --lib:lib
import "$nim/compiler/nimpaths"
import compiler/nimpaths
]#

import os
when defined(nimPreviewSlimSystem):
  import std/assertions

# Note: all the const paths defined here are known at compile time and valid
# so long Nim repo isn't relocated after compilation.
# This means the binaries they produce will embed hardcoded paths, which
# isn't appropriate for some applications that need to be relocatable.

const
  sourcePath = currentSourcePath()
    # robust way to derive other paths here
    # We don't depend on PATH so this is robust to having multiple nim binaries
  nimRootDir* = sourcePath.parentDir.parentDir.parentDir.parentDir ## root of Nim repo
  testsFname* = "tests"
  stdlibDir* = nimRootDir / "lib"
  systemPath* = stdlibDir / "system.nim"
  testsDir* = nimRootDir / testsFname
  buildDir* = nimRootDir / "build"
    ## refs #10268: all testament generated files should go here to avoid
    ## polluting .gitignore

proc splitTestFile*(file: string): tuple[cat: string, path: string] =
  ## At least one directory is required in the path, to use as a category name
  runnableExamples:
    doAssert splitTestFile("tests/fakedir/tfakename.nim") == ("fakedir", "tests/fakedir/tfakename.nim".unixToNativePath)
  result = ("", "")
  for p in file.parentDirs(inclusive = false):
    let parent = p.parentDir
    if parent.lastPathPart == testsFname:
      result.cat = p.lastPathPart
      let dir = getCurrentDir()
      if file.isRelativeTo(dir):
        result.path = file.relativePath(dir)
      else:
        result.path = file
      return result
  raiseAssert "file must match this pattern: '/pathto/tests/dir/**/tfile.nim', got: '" & file & "'"

static:
  # sanity check
  doAssert fileExists(systemPath)

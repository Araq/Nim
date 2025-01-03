## This module implements path handling like os module but works at only compile-time.
## This module works even when cross compiling to OS that is not supported by os module.

when defined(nimPreviewSlimSystem):
  import std/assertions

proc staticFileExists*(filename: string): bool {.compileTime.} =
  ## Returns true if `filename` exists and is a regular file or symlink.
  ##
  ## Directories, device files, named pipes and sockets return false.
  raiseAssert "implemented in the vmops"

proc staticDirExists*(dir: string): bool {.compileTime.} =
  ## Returns true if the directory `dir` exists. If `dir` is a file, false
  ## is returned. Follows symlinks.
  raiseAssert "implemented in the vmops"

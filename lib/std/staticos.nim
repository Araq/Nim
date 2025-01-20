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

type
  PathComponent* = enum   ## Enumeration specifying a path component.
    ##
    ## See also:
    ## * `walkDirRec iterator`_
    ## * `FileInfo object`_
    pcFile,               ## path refers to a file
    pcLinkToFile,         ## path refers to a symbolic link to a file
    pcDir,                ## path refers to a directory
    pcLinkToDir           ## path refers to a symbolic link to a directory

proc staticWalkDir*(dir: string; relative: bool = false): seq[
                  tuple[kind: PathComponent, path: string]] =
  discard

#
#
#              Nim's Runtime Library
#        (c) Copyright 2020 Nim Contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module allows querying the compiler about
## diverse configuration settings. See also `compileOption`.

# Note: Only add new enum values at the end to ensure binary compatibility with
# other Nim compiler versions!

when defined(nimPreviewSlimSystem):
  import std/assertions

type
  SingleValueSetting* {.pure.} = enum ## \
                      ## settings resulting in a single string value
    arguments,        ## experimental: the arguments passed after '-r'
    outFile,          ## experimental: the output file
    outDir,           ## the output directory
    nimcacheDir,      ## the location of the 'nimcache' directory
    projectName,      ## the project's name that is being compiled
    projectPath,      ## experimental: some path to the project that is being compiled
    projectFull,      ## the full path to the project that is being compiled
    command,          ## experimental: the command (e.g. 'c', 'cpp', 'doc') passed to
                      ## the Nim compiler
    commandLine,      ## experimental: the command line passed to Nim
    linkOptions,      ## additional options passed to the linker
    compileOptions,   ## additional options passed to the C/C++ compiler
    ccompilerPath     ## the path to the C/C++ compiler
    backend           ## the backend (eg: c|cpp|objc|js); both `nim doc --backend:js`
                      ## and `nim js` would imply backend=js
    libPath           ## the absolute path to the stdlib library, i.e. nim's `--lib`, since 1.5.1
    gc {.deprecated.} ## gc selected
    mm                ## memory management selected

  MultipleValueSetting* {.pure.} = enum ## \
                      ## settings resulting in a seq of string values
    nimblePaths,      ## the nimble path(s)
    searchPaths,      ## the search path for modules
    lazyPaths,        ## experimental: even more paths
    commandArgs,      ## the arguments passed to the Nim compiler
    cincludes,        ## the #include paths passed to the C/C++ compiler
    clibs             ## libraries passed to the C/C++ compiler

proc querySetting*(setting: SingleValueSetting): string {.
  compileTime, noSideEffect.} =
  ## Can be used to get a string compile-time option.
  ##
  ## See also:
  ## * `compileOption <system.html#compileOption,string>`_ for `on|off` options
  ## * `compileOption <system.html#compileOption,string,string>`_ for enum options
  ##
  runnableExamples:
    const nimcache = querySetting(SingleValueSetting.nimcacheDir)
  raiseAssert "implemented in the vmops"

proc querySettingSeq*(setting: MultipleValueSetting): seq[string] {.
  compileTime, noSideEffect.} =
  ## Can be used to get a multi-string compile-time option.
  ##
  ## See also:
  ## * `compileOption <system.html#compileOption,string>`_ for `on|off` options
  ## * `compileOption <system.html#compileOption,string,string>`_ for enum options
  runnableExamples:
    const nimblePaths = querySettingSeq(MultipleValueSetting.nimblePaths)
  raiseAssert "implemented in the vmops"

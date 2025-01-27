#
#
#            Nim's Runtime Library
#        (c) Copyright 2019 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

when defined(nimdoc):
  type
    Impl = distinct int64
    Time* = Impl ## \
      ## Wrapper for `time_t`. On posix, this is an alias to `posix.Time`.
elif defined(windows):
  when defined(i386) and defined(gcc):
    type Time* {.importc: "time_t", header: "<time.h>".} = distinct clong
  else:
    # newest version of Visual C++ defines time_t to be of 64 bits
    type Time* {.importc: "time_t", header: "<time.h>".} = distinct int64
elif defined(posix):
  import std/posix
  export posix.Time
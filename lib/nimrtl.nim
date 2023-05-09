discard """
batchable: false
"""

#
#
#            Nim's Runtime Library
#        (c) Copyright 2010 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Main file to generate a DLL from the standard library.
## The default Nimrtl does not only contain the `system` module, but these
## too:
##
## * parseutils
## * strutils
## * parseopt
## * parsecfg
## * strtabs
## * times
## * os
## * osproc
## * unicode
## * pegs
## * ropes
## * cstrutils
##

when system.appType != "lib":
  {.error: "This file has to be compiled as a library!".}

when not defined(createNimRtl):
  {.error: "This file has to be compiled with '-d:createNimRtl'".}

when defined(gcDestructors):
  # XXX nimPrepareStrMutationV2, nimAddCharV1, isObjDisplayCheck
  # all give multiple definition error on ARC/ORC
  when defined(clang):
    {.passL: "-Wl,-Xlink=-force:multiple".}
  else:
    {.passL: "-Wl,--allow-multiple-definition".}

import
  parseutils, strutils, parseopt, parsecfg, strtabs, unicode, pegs, ropes,
  os, osproc, times, cstrutils

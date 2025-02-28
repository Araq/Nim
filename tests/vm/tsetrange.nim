# issue #24736

import std/setutils

type CcsCatType = enum cctNone, cctHeader, cctIndex, cctSetup, cctUnk1, cctStream

block: # original issue
  const CCS_CAT_TYPES = fullSet(CcsCatType)
  proc test(t: int): bool = t.CcsCatType in CCS_CAT_TYPES
  discard test(5)

block: # minimized
  func foo(): set[CcsCatType] =
    {cctNone..cctHeader}
  const CCS_CAT_TYPES = foo()
  proc test(t: int): bool = t.CcsCatType in CCS_CAT_TYPES
  discard test(5)

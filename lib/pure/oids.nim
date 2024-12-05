#
#
#            Nim's Runtime Library
#        (c) Copyright 2013 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Nim OID support. An OID is a global ID that consists of a timestamp,
## a unique counter and a random value. This combination should suffice to
## produce a globally distributed unique ID.
##
## This implementation calls `initRand()` for the first call of
## `genOid`.

import std/[hashes, times, endians, random]
from std/private/decode_helpers import handleHexChar

when defined(nimPreviewSlimSystem):
  import std/sysatomics

type
  Oid* = object ## An OID.
    time: int64
    fuzz: int32
    count: int32

proc `==`*(oid1: Oid, oid2: Oid): bool {.inline.} =
  ## Compares two OIDs for equality.
  result = (oid1.time == oid2.time) and (oid1.fuzz == oid2.fuzz) and
          (oid1.count == oid2.count)

proc hash*(oid: Oid): Hash =
  ## Generates the hash of an OID for use in hashtables.
  var h: Hash = 0
  h = h !& hash(oid.time)
  h = h !& hash(oid.fuzz)
  h = h !& hash(oid.count)
  result = !$h

proc hexbyte*(hex: char): int {.inline.} =
  result = handleHexChar(hex)

proc parseOid*(str: cstring): Oid =
  ## Parses an OID.
  result = Oid()
  var bytes = cast[cstring](cast[pointer](cast[int](addr(result.time)) + 4))
  var i = 0
  while i < 12:
    bytes[i] = chr((hexbyte(str[2 * i]) shl 4) or hexbyte(str[2 * i + 1]))
    inc(i)

proc `$`*(oid: Oid): string =
  ## Converts an OID to a string.
  const hex = "0123456789abcdef"
  result = ""
  result.setLen 24

  var o = oid
  var bytes = cast[cstring](cast[pointer](cast[int](addr(o)) + 4))
  var i = 0
  while i < 12:
    let b = bytes[i].ord
    result[2 * i] = hex[(b and 0xF0) shr 4]
    result[2 * i + 1] = hex[b and 0xF]
    inc(i)

let
  t = getTime().toUnix

var
  seed = initRand(t)
  incr: int = seed.rand(int.high)

let fuzz = cast[int32](seed.rand(high(int)))


template genOid(result: var Oid, incr: var int, fuzz: int32) =
  var time = getTime().toUnix
  var i = cast[int32](atomicInc(incr))

  bigEndian64(addr result.time, addr(time))
  result.fuzz = fuzz
  bigEndian32(addr result.count, addr(i))

proc genOid*(): Oid =
  ## Generates a new OID.
  runnableExamples:
    doAssert ($genOid()).len == 24
  runnableExamples("-r:off"):
    echo $genOid() # for example, "5fc7f546ddbbc84800006aaf"
  result = Oid()
  genOid(result, incr, fuzz)

proc generatedTime*(oid: Oid): Time =
  ## Returns the generated timestamp of the OID.
  var tmp: int64 = int64(0)
  var dummy = oid.time
  bigEndian64(addr(tmp), addr(dummy))
  result = fromUnix(tmp)

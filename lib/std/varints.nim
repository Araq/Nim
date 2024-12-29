#
#
#            Nim's Runtime Library
#        (c) Copyright 2018 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## A variable length integer
## encoding implementation inspired by SQLite.
##
## Unstable API.

const
  maxVarIntLen* = 9 ## the maximal number of bytes a varint can take

proc readVu64*(z: openArray[byte]; pResult: var uint64): int =
  if z[0] <= 240:
    pResult = z[0]
    return 1
  if z[0] <= 248:
    if z.len < 2: return 0
    pResult = (uint64 z[0] - 241) * 256 + z[1].uint64 + 240
    return 2
  if z.len < int(z[0]-246): return 0
  if z[0] == 249:
    pResult = 2288u64 + 256u64*z[1].uint64 + z[2].uint64
    return 3
  if z[0] == 250:
    pResult = (z[1].uint64 shl 16u64) + (z[2].uint64 shl 8u64) + z[3].uint64
    return 4
  let x = (z[1].uint64 shl 24) + (z[2].uint64 shl 16) + (z[3].uint64 shl 8) + z[4].uint64
  if z[0] == 251:
    pResult = x
    return 5
  if z[0] == 252:
    pResult = (((uint64)x) shl 8) + z[5].uint64
    return 6
  if z[0] == 253:
    pResult = (((uint64)x) shl 16) + (z[5].uint64 shl 8) + z[6].uint64
    return 7
  if z[0] == 254:
    pResult = (((uint64)x) shl 24) + (z[5].uint64 shl 16) + (z[6].uint64 shl 8) + z[7].uint64
    return 8
  pResult = (((uint64)x) shl 32) +
              (0xffffffff'u64 and ((z[5].uint64 shl 24) +
              (z[6].uint64 shl 16) + (z[7].uint64 shl 8) + z[8].uint64))
  return 9

proc varintWrite32(z: var openArray[byte]; y: uint32) =
  z[0] = cast[uint8](y shr 24)
  z[1] = cast[uint8](y shr 16)
  z[2] = cast[uint8](y shr 8)
  z[3] = cast[uint8](y)

proc writeVu64*(z: var openArray[byte], x: uint64): int =
  ## Write a varint into z. The buffer z must be at least 9 characters
  ## long to accommodate the largest possible varint. Returns the number of
  ## bytes used.
  if x <= 240:
    z[0] = cast[uint8](x)
    return 1
  if x <= 2287:
    let y = cast[uint32](x - 240)
    z[0] = cast[uint8](y shr 8 + 241)
    z[1] = cast[uint8](y and 255)
    return 2
  if x <= 67823:
    let y = cast[uint32](x - 2288)
    z[0] = 249
    z[1] = cast[uint8](y shr 8)
    z[2] = cast[uint8](y and 255)
    return 3
  let y = cast[uint32](x)
  let w = cast[uint32](x shr 32)
  if w == 0:
    if y <= 16777215:
      z[0] = 250
      z[1] = cast[uint8](y shr 16)
      z[2] = cast[uint8](y shr 8)
      z[3] = cast[uint8](y)
      return 4
    z[0] = 251
    varintWrite32(toOpenArray(z, 1, 4), y)
    return 5
  if w <= 255:
    z[0] = 252
    z[1] = cast[uint8](w)
    varintWrite32(toOpenArray(z, 2, 5), y)
    return 6
  if w <= 65535:
    z[0] = 253
    z[1] = cast[uint8](w shr 8)
    z[2] = cast[uint8](w)
    varintWrite32(toOpenArray(z, 3, 6), y)
    return 7
  if w <= 16777215:
    z[0] = 254
    z[1] = cast[uint8](w shr 16)
    z[2] = cast[uint8](w shr 8)
    z[3] = cast[uint8](w)
    varintWrite32(toOpenArray(z, 4, 7), y)
    return 8
  z[0] = 255
  varintWrite32(toOpenArray(z, 1, 4), w)
  varintWrite32(toOpenArray(z, 5, 8), y)
  return 9

proc encodeZigzag*(x: int64): uint64 {.inline.} =
  let xu = uint64(x)
  (xu shl 1) xor (xu shr 63)

proc decodeZigzag*(x: uint64): int64 {.inline.} =
  cast[int64]((x shr 1) xor (x shl 63))

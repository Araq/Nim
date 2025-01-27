#
#
#           The Nim Compiler
#        (c) Copyright 2024 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# For the line information we use 32 bits. They are used as follows:
# Bit 0 (AsideBit): If we have inline line information or not. If not, the
# remaining 31 bits are used as an index into a seq[(LitId, int, int)].
#
# We use 10 bits for the "file ID", this means a program can consist of as much
# as 1024 different files. (If it uses more files than that, the overflow bit
# would be set.)
# This means we have 21 bits left to encode the (line, col) pair. We use 7 bits for the column
# so 128 is the limit and 14 bits for the line number.
# The packed representation supports files with up to 16384 lines.
# Keep in mind that whenever any limit is reached the AsideBit is set and the real line
# information is kept in a side channel.

import std / assertions

const
  AsideBit = 1
  FileBits = 10
  LineBits = 14
  ColBits = 7
  FileMax = (1 shl FileBits) - 1
  LineMax = (1 shl LineBits) - 1
  ColMax = (1 shl ColBits) - 1

static:
  assert AsideBit + FileBits + LineBits + ColBits == 32

import .. / ic / [bitabs, rodfiles] # for LitId

type
  PackedLineInfo* = distinct uint32

  LineInfoManager* = object
    aside: seq[(LitId, int32, int32)]

const
  NoLineInfo* = PackedLineInfo(0'u32)

proc pack*(m: var LineInfoManager; file: LitId; line, col: int32): PackedLineInfo =
  if file.uint32 <= FileMax.uint32 and line <= LineMax and col <= ColMax:
    let col = if col < 0'i32: 0'u32 else: col.uint32
    let line = if line < 0'i32: 0'u32 else: line.uint32
    # use inline representation:
    result = PackedLineInfo((file.uint32 shl 1'u32) or (line shl uint32(AsideBit + FileBits)) or
      (col shl uint32(AsideBit + FileBits + LineBits)))
  else:
    result = PackedLineInfo((m.aside.len shl 1) or AsideBit)
    m.aside.add (file, line, col)

proc unpack*(m: LineInfoManager; i: PackedLineInfo): (LitId, int32, int32) =
  let i = i.uint32
  if (i and 1'u32) == 0'u32:
    # inline representation:
    result = (LitId((i shr 1'u32) and FileMax.uint32),
      int32((i shr uint32(AsideBit + FileBits)) and LineMax.uint32),
      int32((i shr uint32(AsideBit + FileBits + LineBits)) and ColMax.uint32))
  else:
    result = m.aside[int(i shr 1'u32)]

proc getFileId*(m: LineInfoManager; i: PackedLineInfo): LitId =
  result = unpack(m, i)[0]

proc store*(r: var RodFile; m: LineInfoManager) = storeSeq(r, m.aside)
proc load*(r: var RodFile; m: var LineInfoManager) = loadSeq(r, m.aside)

when isMainModule:
  var m = LineInfoManager(aside: @[])
  for i in 0'i32..<16388'i32:
    for col in 0'i32..<100'i32:
      let packed = pack(m, LitId(1023), i, col)
      let u = unpack(m, packed)
      assert u[0] == LitId(1023)
      assert u[1] == i
      assert u[2] == col
  echo m.aside.len

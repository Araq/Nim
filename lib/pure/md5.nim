#
#
#            Nim's Runtime Library
#        (c) Copyright 2010 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Module for computing [MD5 checksums](https://en.wikipedia.org/wiki/MD5).
##
## This module also works at compile time and in JavaScript.
##
## See also
## ========
## * `base64 module<base64.html>`_ for a Base64 encoder and decoder
## * `sha1 module <sha1.html>`_ for the SHA-1 checksum algorithm
## * `hashes module<hashes.html>`_ for efficient computations of hash values
##   for diverse Nim types

{.deprecated: "use command `nimble install checksums` and import `checksums/md5` instead".}

when defined(nimHasStyleChecks):
  {.push styleChecks: off.}

type
  MD5State = array[0..3, uint32]
  MD5Block = array[0..15, uint32]
  MD5CBits = array[0..7, uint8]
  MD5Digest* = array[0..15, uint8]
    ## MD5 checksum of a string, obtained with the `toMD5 proc <#toMD5,string>`_.
  MD5Buffer = array[0..63, uint8]
  MD5Context* {.final.} = object
    state: MD5State
    count: array[0..1, uint32]
    buffer: MD5Buffer

const
  padding: array[0..63, uint8] = [
    0x80'u8, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0
  ]

proc F(x, y, z: uint32): uint32 {.inline.} =
  result = (x and y) or ((not x) and z)

proc G(x, y, z: uint32): uint32 {.inline.} =
  result = (x and z) or (y and (not z))

proc H(x, y, z: uint32): uint32 {.inline.} =
  result = x xor y xor z

proc I(x, y, z: uint32): uint32 {.inline.} =
  result = y xor (x or (not z))

proc rot(x: var uint32, n: uint8) {.inline.} =
  x = (x shl n) or (x shr (32'u32 - n))

proc FF(a: var uint32, b, c, d, x: uint32, s: uint8, ac: uint32) =
  a = a + F(b, c, d) + x + ac
  rot(a, s)
  a = a + b

proc GG(a: var uint32, b, c, d, x: uint32, s: uint8, ac: uint32) =
  a = a + G(b, c, d) + x + ac
  rot(a, s)
  a = a + b

proc HH(a: var uint32, b, c, d, x: uint32, s: uint8, ac: uint32) =
  a = a + H(b, c, d) + x + ac
  rot(a, s)
  a = a + b

proc II(a: var uint32, b, c, d, x: uint32, s: uint8, ac: uint32) =
  a = a + I(b, c, d) + x + ac
  rot(a, s)
  a = a + b

proc encode(dest: var MD5Block, src: openArray[uint8]) =
  var j = 0
  for i in 0..high(dest):
    dest[i] = uint32(ord(src[j])) or
              uint32(ord(src[j+1])) shl 8 or
              uint32(ord(src[j+2])) shl 16 or
              uint32(ord(src[j+3])) shl 24
    inc(j, 4)

proc decode(dest: var openArray[uint8], src: openArray[uint32]) =
  var i = 0
  for j in 0..high(src):
    dest[i] = uint8(src[j] and 0xff'u32)
    dest[i+1] = uint8(src[j] shr 8 and 0xff'u32)
    dest[i+2] = uint8(src[j] shr 16 and 0xff'u32)
    dest[i+3] = uint8(src[j] shr 24 and 0xff'u32)
    inc(i, 4)

template slice(s: cstring, a, b): openArray[uint8] =
  when nimvm:
    # toOpenArray is not implemented in VM
    toOpenArrayByte($s, a, b)
  else:
    when defined(js):
      # toOpenArrayByte for cstring is not implemented in JS
      toOpenArrayByte($s, a, b)
    else:
      s.toOpenArrayByte(a, b)

template slice(s: openArray[uint8], a, b): openArray[uint8] =
  s.toOpenArray(a, b)

const useMem = declared(copyMem)

template memOrNot(withMem, withoutMem): untyped =
  when nimvm:
    withoutMem
  else:
    when useMem:
      withMem
    else:
      withoutMem

proc transform(buffer: openArray[uint8], state: var MD5State) =
  var
    myBlock: MD5Block = default(MD5Block)
  encode(myBlock, buffer)
  var a = state[0]
  var b = state[1]
  var c = state[2]
  var d = state[3]
  FF(a, b, c, d, myBlock[0], 7'u8, 0xD76AA478'u32)
  FF(d, a, b, c, myBlock[1], 12'u8, 0xE8C7B756'u32)
  FF(c, d, a, b, myBlock[2], 17'u8, 0x242070DB'u32)
  FF(b, c, d, a, myBlock[3], 22'u8, 0xC1BDCEEE'u32)
  FF(a, b, c, d, myBlock[4], 7'u8, 0xF57C0FAF'u32)
  FF(d, a, b, c, myBlock[5], 12'u8, 0x4787C62A'u32)
  FF(c, d, a, b, myBlock[6], 17'u8, 0xA8304613'u32)
  FF(b, c, d, a, myBlock[7], 22'u8, 0xFD469501'u32)
  FF(a, b, c, d, myBlock[8], 7'u8, 0x698098D8'u32)
  FF(d, a, b, c, myBlock[9], 12'u8, 0x8B44F7AF'u32)
  FF(c, d, a, b, myBlock[10], 17'u8, 0xFFFF5BB1'u32)
  FF(b, c, d, a, myBlock[11], 22'u8, 0x895CD7BE'u32)
  FF(a, b, c, d, myBlock[12], 7'u8, 0x6B901122'u32)
  FF(d, a, b, c, myBlock[13], 12'u8, 0xFD987193'u32)
  FF(c, d, a, b, myBlock[14], 17'u8, 0xA679438E'u32)
  FF(b, c, d, a, myBlock[15], 22'u8, 0x49B40821'u32)
  GG(a, b, c, d, myBlock[1], 5'u8, 0xF61E2562'u32)
  GG(d, a, b, c, myBlock[6], 9'u8, 0xC040B340'u32)
  GG(c, d, a, b, myBlock[11], 14'u8, 0x265E5A51'u32)
  GG(b, c, d, a, myBlock[0], 20'u8, 0xE9B6C7AA'u32)
  GG(a, b, c, d, myBlock[5], 5'u8, 0xD62F105D'u32)
  GG(d, a, b, c, myBlock[10], 9'u8, 0x02441453'u32)
  GG(c, d, a, b, myBlock[15], 14'u8, 0xD8A1E681'u32)
  GG(b, c, d, a, myBlock[4], 20'u8, 0xE7D3FBC8'u32)
  GG(a, b, c, d, myBlock[9], 5'u8, 0x21E1CDE6'u32)
  GG(d, a, b, c, myBlock[14], 9'u8, 0xC33707D6'u32)
  GG(c, d, a, b, myBlock[3], 14'u8, 0xF4D50D87'u32)
  GG(b, c, d, a, myBlock[8], 20'u8, 0x455A14ED'u32)
  GG(a, b, c, d, myBlock[13], 5'u8, 0xA9E3E905'u32)
  GG(d, a, b, c, myBlock[2], 9'u8, 0xFCEFA3F8'u32)
  GG(c, d, a, b, myBlock[7], 14'u8, 0x676F02D9'u32)
  GG(b, c, d, a, myBlock[12], 20'u8, 0x8D2A4C8A'u32)
  HH(a, b, c, d, myBlock[5], 4'u8, 0xFFFA3942'u32)
  HH(d, a, b, c, myBlock[8], 11'u8, 0x8771F681'u32)
  HH(c, d, a, b, myBlock[11], 16'u8, 0x6D9D6122'u32)
  HH(b, c, d, a, myBlock[14], 23'u8, 0xFDE5380C'u32)
  HH(a, b, c, d, myBlock[1], 4'u8, 0xA4BEEA44'u32)
  HH(d, a, b, c, myBlock[4], 11'u8, 0x4BDECFA9'u32)
  HH(c, d, a, b, myBlock[7], 16'u8, 0xF6BB4B60'u32)
  HH(b, c, d, a, myBlock[10], 23'u8, 0xBEBFBC70'u32)
  HH(a, b, c, d, myBlock[13], 4'u8, 0x289B7EC6'u32)
  HH(d, a, b, c, myBlock[0], 11'u8, 0xEAA127FA'u32)
  HH(c, d, a, b, myBlock[3], 16'u8, 0xD4EF3085'u32)
  HH(b, c, d, a, myBlock[6], 23'u8, 0x04881D05'u32)
  HH(a, b, c, d, myBlock[9], 4'u8, 0xD9D4D039'u32)
  HH(d, a, b, c, myBlock[12], 11'u8, 0xE6DB99E5'u32)
  HH(c, d, a, b, myBlock[15], 16'u8, 0x1FA27CF8'u32)
  HH(b, c, d, a, myBlock[2], 23'u8, 0xC4AC5665'u32)
  II(a, b, c, d, myBlock[0], 6'u8, 0xF4292244'u32)
  II(d, a, b, c, myBlock[7], 10'u8, 0x432AFF97'u32)
  II(c, d, a, b, myBlock[14], 15'u8, 0xAB9423A7'u32)
  II(b, c, d, a, myBlock[5], 21'u8, 0xFC93A039'u32)
  II(a, b, c, d, myBlock[12], 6'u8, 0x655B59C3'u32)
  II(d, a, b, c, myBlock[3], 10'u8, 0x8F0CCC92'u32)
  II(c, d, a, b, myBlock[10], 15'u8, 0xFFEFF47D'u32)
  II(b, c, d, a, myBlock[1], 21'u8, 0x85845DD1'u32)
  II(a, b, c, d, myBlock[8], 6'u8, 0x6FA87E4F'u32)
  II(d, a, b, c, myBlock[15], 10'u8, 0xFE2CE6E0'u32)
  II(c, d, a, b, myBlock[6], 15'u8, 0xA3014314'u32)
  II(b, c, d, a, myBlock[13], 21'u8, 0x4E0811A1'u32)
  II(a, b, c, d, myBlock[4], 6'u8, 0xF7537E82'u32)
  II(d, a, b, c, myBlock[11], 10'u8, 0xBD3AF235'u32)
  II(c, d, a, b, myBlock[2], 15'u8, 0x2AD7D2BB'u32)
  II(b, c, d, a, myBlock[9], 21'u8, 0xEB86D391'u32)
  state[0] = state[0] + a
  state[1] = state[1] + b
  state[2] = state[2] + c
  state[3] = state[3] + d

proc md5Init*(c: var MD5Context) {.raises: [], tags: [], gcsafe.}
proc md5Update*(c: var MD5Context, input: openArray[uint8]) {.raises: [],
    tags: [], gcsafe.}
proc md5Final*(c: var MD5Context, digest: var MD5Digest) {.raises: [], tags: [], gcsafe.}

proc md5Update*(c: var MD5Context, input: cstring, len: int) {.raises: [],
    tags: [], gcsafe.} =
  ## Updates the `MD5Context` with the `input` data of length `len`.
  ##
  ## If you use the `toMD5 proc <#toMD5,string>`_, there's no need to call this
  ## function explicitly.
  md5Update(c, input.slice(0, len - 1))


proc toMD5*(s: string): MD5Digest =
  ## Computes the `MD5Digest` value for a string `s`.
  ##
  ## **See also:**
  ## * `getMD5 proc <#getMD5,string>`_ which returns a string representation
  ##   of the `MD5Digest`
  ## * `$ proc <#$,MD5Digest>`_ for converting MD5Digest to string
  runnableExamples:
    assert $toMD5("abc") == "900150983cd24fb0d6963f7d28e17f72"
  result = default(MD5Digest)
  var c: MD5Context = default(MD5Context)
  md5Init(c)
  md5Update(c, s.slice(0, s.len - 1))
  md5Final(c, result)

proc `$`*(d: MD5Digest): string =
  ## Converts a `MD5Digest` value into its string representation.
  const digits = "0123456789abcdef"
  result = ""
  for i in 0..15:
    add(result, digits[(d[i].int shr 4) and 0xF])
    add(result, digits[d[i].int and 0xF])

proc getMD5*(s: string): string =
  ## Computes an MD5 value of `s` and returns its string representation.
  ##
  ## **See also:**
  ## * `toMD5 proc <#toMD5,string>`_ which returns the `MD5Digest` of a string
  runnableExamples:
    assert getMD5("abc") == "900150983cd24fb0d6963f7d28e17f72"

  var
    c: MD5Context = default(MD5Context)
    d: MD5Digest = default(MD5Digest)
  md5Init(c)
  md5Update(c, s.slice(0, s.len - 1))
  md5Final(c, d)
  result = $d

proc `==`*(D1, D2: MD5Digest): bool =
  ## Checks if two `MD5Digest` values are identical.
  for i in 0..15:
    if D1[i] != D2[i]: return false
  return true


proc clearBuffer(c: var MD5Context) {.inline.} =
  memOrNot:
    zeroMem(addr(c.buffer), sizeof(MD5Buffer))
  do:
    reset(c.buffer)

proc md5Init*(c: var MD5Context) =
  ## Initializes an `MD5Context`.
  ##
  ## If you use the `toMD5 proc <#toMD5,string>`_, there's no need to call this
  ## function explicitly.
  c.state[0] = 0x67452301'u32
  c.state[1] = 0xEFCDAB89'u32
  c.state[2] = 0x98BADCFE'u32
  c.state[3] = 0x10325476'u32
  c.count[0] = 0'u32
  c.count[1] = 0'u32
  clearBuffer(c)

proc writeBuffer(c: var MD5Context, index: int,
                 input: openArray[uint8], inputIndex, len: int) {.inline.} =
  memOrNot:
    copyMem(addr(c.buffer[index]), unsafeAddr(input[inputIndex]), len)
  do:
    # cannot use system.`[]=` for arrays and openarrays as
    # it can raise RangeDefect which gets tracked
    for i in 0..<len:
      c.buffer[index + i] = input[inputIndex + i]

proc md5Update*(c: var MD5Context, input: openArray[uint8]) =
  ## Updates the `MD5Context` with the `input` data.
  ##
  ## If you use the `toMD5 proc <#toMD5,string>`_, there's no need to call this
  ## function explicitly.
  var Index = int((c.count[0] shr 3) and 0x3F)
  c.count[0] = c.count[0] + (uint32(input.len) shl 3)
  if c.count[0] < (uint32(input.len) shl 3): c.count[1] = c.count[1] + 1'u32
  c.count[1] = c.count[1] + (uint32(input.len) shr 29)
  var PartLen = 64 - Index
  if input.len >= PartLen:
    writeBuffer(c, Index, input, 0, PartLen)
    transform(c.buffer, c.state)
    var i = PartLen
    while i + 63 < input.len:
      transform(input.slice(i, i + 63), c.state)
      inc(i, 64)
    if i < input.len:
      writeBuffer(c, 0, input, i, input.len - i)
  elif input.len > 0:
    writeBuffer(c, Index, input, 0, input.len)

proc md5Final*(c: var MD5Context, digest: var MD5Digest) =
  ## Finishes the `MD5Context` and stores the result in `digest`.
  ##
  ## If you use the `toMD5 proc <#toMD5,string>`_, there's no need to call this
  ## function explicitly.
  var
    Bits: MD5CBits = default(MD5CBits)
    PadLen: int
  decode(Bits, c.count)
  var Index = int((c.count[0] shr 3) and 0x3F)
  if Index < 56: PadLen = 56 - Index
  else: PadLen = 120 - Index
  md5Update(c, padding.slice(0, PadLen - 1))
  md5Update(c, Bits)
  decode(digest, c.state)
  clearBuffer(c)


when defined(nimHasStyleChecks):
  {.pop.} #{.push styleChecks: off.}
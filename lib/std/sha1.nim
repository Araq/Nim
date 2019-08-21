#
#
#           The Nim Compiler
#        (c) Copyright 2015 Nim Contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## **Note:** Import ``std/sha1`` to use this module
##
## SHA-1 (Secure Hash Algorithm 1) is a cryptographic hash function which
## takes an input and produces a 160-bit (20-byte) hash value known as a
## message digest.
##
## .. code-block::
##    import std/sha1
##
##    let accessName = secureHash("John Doe")
##    assert $accessName == "AE6E4D1209F17B460503904FAD297B31E9CF6362"
##
## .. code-block::
##    import std/sha1
##
##    let
##      a = secureHashFile("myFile.nim")
##      b = parseSecureHash("10DFAEBF6BFDBC7939957068E2EFACEC4972933C")
##
##    if a == b:
##      echo "Files match"
##
## **See also:**
## * `base64 module<base64.html>`_ implements a base64 encoder and decoder
## * `hashes module<hashes.html>`_ for efficient computations of hash values for diverse Nim types
## * `md5 module<md5.html>`_ implements the MD5 checksum algorithm

import strutils
from endians import bigEndian32, bigEndian64

const Sha1DigestSize = 20

type
  Sha1Digest* = array[0 .. Sha1DigestSize-1, uint8]
  SecureHash* = distinct Sha1Digest

type
  Sha1State* = object
    count: int
    state: array[5, uint32]
    buf:   array[64, byte]

# This implementation of the SHA1 algorithm was ported from the Chromium OS one
# with minor modifications that should not affect its functionality.

proc newSha1State*(): Sha1State =
  result.count = 0
  result.state[0] = 0x67452301'u32
  result.state[1] = 0xEFCDAB89'u32
  result.state[2] = 0x98BADCFE'u32
  result.state[3] = 0x10325476'u32
  result.state[4] = 0xC3D2E1F0'u32

template ror27(val: uint32): uint32 = (val shr 27) or (val shl  5)
template ror2 (val: uint32): uint32 = (val shr  2) or (val shl 30)
template ror31(val: uint32): uint32 = (val shr 31) or (val shl  1)

proc transform(ctx: var Sha1State) =
  var w: array[80, uint32]
  var a, b, c, d, e: uint32
  var t = 0

  a = ctx.state[0]
  b = ctx.state[1]
  c = ctx.state[2]
  d = ctx.state[3]
  e = ctx.state[4]

  template shaF1(a, b, c, d, e, t: untyped) =
    bigEndian32(addr w[t], addr ctx.buf[t * 4])
    e += ror27(a) + w[t] + (d xor (b and (c xor d))) + 0x5A827999'u32
    b = ror2(b)

  while t < 15:
    shaF1(a, b, c, d, e, t + 0)
    shaF1(e, a, b, c, d, t + 1)
    shaF1(d, e, a, b, c, t + 2)
    shaF1(c, d, e, a, b, t + 3)
    shaF1(b, c, d, e, a, t + 4)
    t += 5
  shaF1(a, b, c, d, e, t + 0) # 16th one, t == 15

  template shaF11(a, b, c, d, e, t: untyped) =
    w[t] = ror31(w[t-3] xor w[t-8] xor w[t-14] xor w[t-16])
    e += ror27(a) + w[t] + (d xor (b and (c xor d))) + 0x5A827999'u32
    b = ror2(b)

  shaF11(e, a, b, c, d, t + 1)
  shaF11(d, e, a, b, c, t + 2)
  shaF11(c, d, e, a, b, t + 3)
  shaF11(b, c, d, e, a, t + 4)

  template shaF2(a, b, c, d, e, t: untyped) =
    w[t] = ror31(w[t-3] xor w[t-8] xor w[t-14] xor w[t-16])
    e += ror27(a) + w[t] + (b xor c xor d) + 0x6ED9EBA1'u32
    b = ror2(b)

  t = 20
  while t < 40:
    shaF2(a, b, c, d, e, t + 0)
    shaF2(e, a, b, c, d, t + 1)
    shaF2(d, e, a, b, c, t + 2)
    shaF2(c, d, e, a, b, t + 3)
    shaF2(b, c, d, e, a, t + 4)
    t += 5

  template shaF3(a, b, c, d, e, t: untyped) =
    w[t] = ror31(w[t-3] xor w[t-8] xor w[t-14] xor w[t-16])
    e += ror27(a) + w[t] + ((b and c) or (d and (b or c))) + 0x8F1BBCDC'u32
    b = ror2(b)

  while t < 60:
    shaF3(a, b, c, d, e, t + 0)
    shaF3(e, a, b, c, d, t + 1)
    shaF3(d, e, a, b, c, t + 2)
    shaF3(c, d, e, a, b, t + 3)
    shaF3(b, c, d, e, a, t + 4)
    t += 5

  template shaF4(a, b, c, d, e, t: untyped) =
    w[t] = ror31(w[t-3] xor w[t-8] xor w[t-14] xor w[t-16])
    e += ror27(a) + w[t] + (b xor c xor d) + 0xCA62C1D6'u32
    b = ror2(b)

  while t < 80:
    shaF4(a, b, c, d, e, t + 0)
    shaF4(e, a, b, c, d, t + 1)
    shaF4(d, e, a, b, c, t + 2)
    shaF4(c, d, e, a, b, t + 3)
    shaF4(b, c, d, e, a, t + 4)
    t += 5

  ctx.state[0] += a
  ctx.state[1] += b
  ctx.state[2] += c
  ctx.state[3] += d
  ctx.state[4] += e

proc update*(ctx: var Sha1State, data: openArray[char]) =
  var i = ctx.count mod 64
  var j = 0
  var len = data.len
  # Gather 64-bytes worth of data in order to perform a round with the leftover
  # data we had stored (but not processed yet)
  if len > 64 - i:
    copyMem(addr ctx.buf[i], unsafeAddr data[j], 64 - i)
    len -= 64 - i
    j += 64 - i
    transform(ctx)
    # Update the index since it's used in the while loop below _and_ we want to
    # keep its value if this code path isn't executed
    i = 0
  # Process the bulk of the payload
  while len >= 64:
    copyMem(addr ctx.buf[0], unsafeAddr data[j], 64)
    len -= 64
    j += 64
    transform(ctx)
  # Process the tail of the payload (len is < 64)
  while len > 0:
    dec len
    ctx.buf[i] = byte(data[j])
    inc i
    inc j
    if i == 64:
      transform(ctx)
      i = 0
  ctx.count += data.len

proc finalize*(ctx: var Sha1State): Sha1Digest =
  var cnt = uint64(ctx.count * 8)
  # a 1 bit
  update(ctx, "\x80")
  # Add padding until we reach a complexive size of 64 - 8 bytes
  while (ctx.count mod 64) != (64 - 8):
    update(ctx, "\x00")
  # The message length as a 64bit BE number completes the block
  var tmp: array[8, char]
  bigEndian64(addr tmp[0], addr cnt)
  update(ctx, tmp)
  # Turn the result into a single 160-bit number
  for i in 0 ..< 5:
    bigEndian32(addr ctx.state[i], addr ctx.state[i])
  copyMem(addr result[0], addr ctx.state[0], Sha1DigestSize)

# Public API

proc secureHash*(str: openArray[char]): SecureHash =
  ## Generates a ``SecureHash`` from a ``str``.
  ##
  ## **See also:**
  ## * `secureHashFile proc <#secureHashFile,string>`_ for generating a ``SecureHash`` from a file
  ## * `parseSecureHash proc <#parseSecureHash,string>`_ for converting a string ``hash`` to ``SecureHash``
  runnableExamples:
    let hash = secureHash("Hello World")
    assert hash == parseSecureHash("0A4D55A8D778E5022FAB701977C5D840BBC486D0")
  var state = newSha1State()
  state.update(str)
  SecureHash(state.finalize())

proc secureHashFile*(filename: string): SecureHash =
  ## Generates a ``SecureHash`` from a file.
  ##
  ## **See also:**
  ## * `secureHash proc <#secureHash,string>`_ for generating a ``SecureHash`` from a string
  ## * `parseSecureHash proc <#parseSecureHash,string>`_ for converting a string ``hash`` to ``SecureHash``
  secureHash(readFile(filename))

proc `$`*(self: SecureHash): string =
  ## Returns the string representation of a ``SecureHash``.
  ##
  ## **See also:**
  ## * `secureHash proc <#secureHash,string>`_ for generating a ``SecureHash`` from a string
  runnableExamples:
    let hash = secureHash("Hello World")
    assert $hash == "0A4D55A8D778E5022FAB701977C5D840BBC486D0"
  result = ""
  for v in Sha1Digest(self):
    result.add(toHex(int(v), 2))

proc parseSecureHash*(hash: string): SecureHash =
  ## Converts a string ``hash`` to ``SecureHash``.
  ##
  ## **See also:**
  ## * `secureHash proc <#secureHash,string>`_ for generating a ``SecureHash`` from a string
  ## * `secureHashFile proc <#secureHashFile,string>`_ for generating a ``SecureHash`` from a file
  runnableExamples:
    let
      hashStr = "0A4D55A8D778E5022FAB701977C5D840BBC486D0"
      secureHash = secureHash("Hello World")
    assert secureHash == parseSecureHash(hashStr)
  for i in 0 ..< Sha1DigestSize:
    Sha1Digest(result)[i] = uint8(parseHexInt(hash[i*2] & hash[i*2 + 1]))

proc `==`*(a, b: SecureHash): bool =
  ## Checks if two ``SecureHash`` values are identical.
  runnableExamples:
    let
      a = secureHash("Hello World")
      b = secureHash("Goodbye World")
      c = parseSecureHash("0A4D55A8D778E5022FAB701977C5D840BBC486D0")
    assert a != b
    assert a == c
  # Not a constant-time comparison, but that's acceptable in this context
  Sha1Digest(a) == Sha1Digest(b)

when isMainModule:
  let hash1 = secureHash("a93tgj0p34jagp9[agjp98ajrhp9aej]")
  doAssert hash1 == hash1
  doAssert parseSecureHash($hash1) == hash1

  template checkVector(s, exp: string) =
    doAssert secureHash(s) == parseSecureHash(exp)

  checkVector("", "da39a3ee5e6b4b0d3255bfef95601890afd80709")
  checkVector("abc", "a9993e364706816aba3e25717850c26c9cd0d89d")
  checkVector("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
              "84983e441c3bd26ebaae4aa1f95129e5e54670f1")

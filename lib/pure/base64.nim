#
#
#            Nim's Runtime Library
#        (c) Copyright 2010 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements a base64 encoder and decoder.
##
## Unstable API.
##
## Base64 is an encoding and decoding technique used to convert binary
## data to an ASCII string format.
## Each Base64 digit represents exactly 6 bits of data. Three 8-bit
## bytes (i.e., a total of 24 bits) can therefore be represented by
## four 6-bit Base64 digits.

##[
# Basic usage
## Encoding data
]##

runnableExamples:
  let encoded = encode("Hello World")
  assert encoded == "SGVsbG8gV29ybGQ="

##
## Apart from strings you can also encode lists of integers or characters:
##

runnableExamples:
  let encodedInts = encode([1'u8,2,3])
  assert encodedInts == "AQID"
  let encodedChars = encode(['h','e','y'])
  assert encodedChars == "aGV5"

##[
## Decoding data
]##

runnableExamples:
  let decoded = decode("SGVsbG8gV29ybGQ=")
  assert decoded == "Hello World"

##[
## URL Safe Base64
]##

runnableExamples:
  assert encode("c\xf7>", safe = true) == "Y_c-"
  assert encode("c\xf7>", safe = false) == "Y/c+"

## See also
## ========
##
## * `hashes module<hashes.html>`_ for efficient computations of hash values for diverse Nim types
## * `md5 module<md5.html>`_ for the MD5 checksum algorithm
## * `sha1 module<sha1.html>`_ for the SHA-1 checksum algorithm

template cbBase(a, b): untyped = [
  'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
  'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
  'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
  'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', a, b]

const
  cb64 = cbBase('+', '/')
  cb64safe = cbBase('-', '_')

const
  invalidChar = 255

template encodeSize(size: int): int = (size div 3 + size) + 6

template encodeInternal(s, alphabet: typed): untyped =
  ## encodes `s` into base64 representation.

  result.setLen(encodeSize(s.len))

  let
    padding = s.len mod 3
    inputEnds = s.len - padding

  var
    inputIndex = 0
    outputIndex = 0
    n: uint32
    b: uint32

  template inputByte(exp: untyped) =
    b = uint32(s[inputIndex])
    n = exp
    inc inputIndex

  template outputChar(x: typed) =
    result[outputIndex] = alphabet[x and 63]
    inc outputIndex

  template outputChar(c: char) =
    result[outputIndex] = c
    inc outputIndex

  while inputIndex != inputEnds:
    inputByte(b shl 16)
    inputByte(n or b shl 8)
    inputByte(n or b shl 0)
    outputChar(n shr 18)
    outputChar(n shr 12)
    outputChar(n shr 6)
    outputChar(n shr 0)

  if padding == 1:
    inputByte(b shl 16)
    outputChar(n shr 18)
    outputChar(n shr 12)
    outputChar('=')
    outputChar('=')

  elif padding == 2:
    inputByte(b shl 16)
    inputByte(n or b shl 8)
    outputChar(n shr 18)
    outputChar(n shr 12)
    outputChar(n shr 6)
    outputChar('=')

  result.setLen(outputIndex)

template encodeImpl() {.dirty.} =
  if safe:
    encodeInternal(s, cb64safe)
  else:
    encodeInternal(s, cb64)

proc encode*[T: byte|char](s: openArray[T], safe = false): string =
  ## Encodes `s` into base64 representation.
  ##
  ## If `safe` is `true` then it will encode using the
  ## URL-Safe and Filesystem-safe standard alphabet characters,
  ## which substitutes `-` instead of `+` and `_` instead of `/`.
  ## * https://en.wikipedia.org/wiki/Base64#URL_applications
  ## * https://tools.ietf.org/html/rfc4648#page-7
  ##
  ## **See also:**
  ## * `decode proc<#decode,string>`_ for decoding a string
  runnableExamples:
    assert encode("Hello World") == "SGVsbG8gV29ybGQ="
    assert encode(['n', 'i', 'm']) == "bmlt"
    assert encode(@['n', 'i', 'm']) == "bmlt"
    assert encode([1'u8, 2, 3, 4, 5]) == "AQIDBAU="
  result = ""
  encodeImpl()

proc encode*[T: SomeInteger and not byte](s: openArray[T], safe = false): string
  {.deprecated: "use `byte` or `char` instead".} =
  result = ""
  encodeImpl()

proc encodeMime*(s: string, lineLen = 75.Positive, newLine = "\r\n",
                 safe = false): string =
  ## Encodes `s` into base64 representation as lines.
  ## Used in email MIME format, use `lineLen` and `newline`.
  ##
  ## This procedure encodes a string according to MIME spec.
  ##
  ## If `safe` is `true` then it will encode using the
  ## URL-Safe and Filesystem-safe standard alphabet characters,
  ## which substitutes `-` instead of `+` and `_` instead of `/`.
  ## * https://en.wikipedia.org/wiki/Base64#URL_applications
  ## * https://tools.ietf.org/html/rfc4648#page-7
  ##
  ## **See also:**
  ## * `encode proc<#encode,openArray[T]>`_ for encoding an openArray
  ## * `decode proc<#decode,string>`_ for decoding a string
  runnableExamples:
    assert encodeMime("Hello World", 4, "\n") == "SGVs\nbG8g\nV29y\nbGQ="
  template cpy(l, src, idx) =
    b = l
    while i < b:
      result[i] = src[idx]
      inc i
      inc idx

  if s.len == 0: return
  let e = encode(s, safe)
  if e.len <= lineLen or newLine.len == 0:
    return e
  result = newString(e.len + newLine.len * ((e.len div lineLen) - int(e.len mod lineLen == 0)))
  var i, j, k, b: int = 0
  let nd = e.len - lineLen
  while j < nd:
    cpy(i + lineLen, e, j)
    cpy(i + newLine.len, newLine, k)
    k = 0
  cpy(result.len, e, j)

proc initDecodeTable*(): array[256, char] =
  # computes a decode table at compile time
  result = default(array[256, char])
  for i in 0 ..< 256:
    let ch = char(i)
    var code = invalidChar
    if ch >= 'A' and ch <= 'Z': code = i - 0x00000041
    if ch >= 'a' and ch <= 'z': code = i - 0x00000047
    if ch >= '0' and ch <= '9': code = i + 0x00000004
    if ch == '+' or ch == '-': code = 0x0000003E
    if ch == '/' or ch == '_': code = 0x0000003F
    result[i] = char(code)

const
  decodeTable = initDecodeTable()

proc decode*(s: string): string =
  ## Decodes string `s` in base64 representation back into its original form.
  ## The initial whitespace is skipped.
  ##
  ## **See also:**
  ## * `encode proc<#encode,openArray[T]>`_ for encoding an openarray
  runnableExamples:
    assert decode("SGVsbG8gV29ybGQ=") == "Hello World"
    assert decode("  SGVsbG8gV29ybGQ=") == "Hello World"
  result = ""
  if s.len == 0: return

  proc decodeSize(size: int): int =
    return (size * 3 div 4) + 6

  template inputChar(x: untyped) =
    let x = int decodeTable[ord(s[inputIndex])]
    if x == invalidChar:
      raise newException(ValueError,
        "Invalid base64 format character `" & s[inputIndex] &
        "` (ord " & $s[inputIndex].ord & ") at location " & $inputIndex & ".")
    inc inputIndex

  template outputChar(x: untyped) =
    result[outputIndex] = char(x and 255)
    inc outputIndex

  # pre allocate output string once
  result.setLen(decodeSize(s.len))
  var
    inputIndex = 0
    outputIndex = 0
    inputLen = s.len
    inputEnds = 0
  # strip trailing characters
  while inputLen > 0 and s[inputLen - 1] in {'\n', '\r', ' ', '='}:
    dec inputLen
  # hot loop: read 4 characters at at time
  inputEnds = inputLen - 4
  while inputIndex <= inputEnds:
    while s[inputIndex] in {'\n', '\r', ' '}:
      inc inputIndex
    inputChar(a)
    inputChar(b)
    inputChar(c)
    inputChar(d)
    outputChar(a shl 2 or b shr 4)
    outputChar(b shl 4 or c shr 2)
    outputChar(c shl 6 or d shr 0)
  # do the last 2 or 3 characters
  var leftLen = abs((inputIndex - inputLen) mod 4)
  if leftLen == 2:
    inputChar(a)
    inputChar(b)
    outputChar(a shl 2 or b shr 4)
  elif leftLen == 3:
    inputChar(a)
    inputChar(b)
    inputChar(c)
    outputChar(a shl 2 or b shr 4)
    outputChar(b shl 4 or c shr 2)
  result.setLen(outputIndex)

#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements efficient computations of hash values for diverse
## Nim types. All the procs are based on these two building blocks:
## - `!& proc <#!&,Hash,int>`_ used to start or mix a hash value, and
## - `!$ proc <#!$,Hash>`_ used to finish the hash value.
##
## If you want to implement hash procs for your custom types,
## you will end up writing the following kind of skeleton of code:

runnableExamples:
  type
    Something = object
      foo: int
      bar: string

  iterator items(x: Something): Hash =
    yield hash(x.foo)
    yield hash(x.bar)

  proc hash(x: Something): Hash =
    ## Computes a Hash from `x`.
    var h: Hash = 0
    # Iterate over parts of `x`.
    for xAtom in x:
      # Mix the atom with the partial hash.
      h = h !& xAtom
    # Finish the hash.
    result = !$h

## If your custom types contain fields for which there already is a `hash` proc,
## you can simply hash together the hash values of the individual fields:

runnableExamples:
  type
    Something = object
      foo: int
      bar: string

  proc hash(x: Something): Hash =
    ## Computes a Hash from `x`.
    var h: Hash = 0
    h = h !& hash(x.foo)
    h = h !& hash(x.bar)
    result = !$h

## .. important:: Use `-d:nimPreviewHashRef` to
##    enable hashing `ref`s. It is expected that this behavior
##    becomes the new default in upcoming versions.
##
## .. note:: If the type has a `==` operator, the following must hold:
##    If two values compare equal, their hashes must also be equal.
##
## See also
## ========
## * `md5 module <md5.html>`_ for the MD5 checksum algorithm
## * `base64 module <base64.html>`_ for a Base64 encoder and decoder
## * `sha1 module <sha1.html>`_ for the SHA-1 checksum algorithm
## * `tables module <tables.html>`_ for hash tables

import std/private/[since, jsutils]

when defined(nimPreviewSlimSystem):
  import std/assertions


type
  Hash* = int ## A hash value. Hash tables using these values should
              ## always have a size of a power of two so they can use the `and`
              ## operator instead of `mod` for truncation of the hash value.

proc `!&`*(h: Hash, val: int): Hash {.inline.} =
  ## Mixes a hash value `h` with `val` to produce a new hash value.
  ##
  ## This is only needed if you need to implement a `hash` proc for a new datatype.
  let h = cast[uint](h)
  let val = cast[uint](val)
  var res = h + val
  res = res + res shl 10
  res = res xor (res shr 6)
  result = cast[Hash](res)

proc `!$`*(h: Hash): Hash {.inline.} =
  ## Finishes the computation of the hash value.
  ##
  ## This is only needed if you need to implement a `hash` proc for a new datatype.
  let h = cast[uint](h) # Hash is practically unsigned.
  var res = h + h shl 3
  res = res xor (res shr 11)
  res = res + res shl 15
  result = cast[Hash](res)

proc hiXorLoFallback64(a, b: uint64): uint64 {.inline.} =
  let # Fall back in 64-bit arithmetic
    aH = a shr 32
    aL = a and 0xFFFFFFFF'u64
    bH = b shr 32
    bL = b and 0xFFFFFFFF'u64
    rHH = aH * bH
    rHL = aH * bL
    rLH = aL * bH
    rLL = aL * bL
    t = rLL + (rHL shl 32)
  var c = if t < rLL: 1'u64 else: 0'u64
  let lo = t + (rLH shl 32)
  c += (if lo < t: 1'u64 else: 0'u64)
  let hi = rHH + (rHL shr 32) + (rLH shr 32) + c
  return hi xor lo

proc hiXorLo(a, b: uint64): uint64 {.inline.} =
  # XOR of the high & low 8 bytes of the full 16 byte product.
  when nimvm:
    result = hiXorLoFallback64(a, b) # `result =` is necessary here.
  else:
    when Hash.sizeof < 8:
      result = hiXorLoFallback64(a, b)
    elif defined(gcc) or defined(llvm_gcc) or defined(clang):
      result = uint64(0)
      {.emit: """__uint128_t r = `a`; r *= `b`; `result` = (r >> 64) ^ r;""".}
    elif defined(windows) and not defined(tcc):
      proc umul128(a, b: uint64, c: ptr uint64): uint64 {.importc: "_umul128", header: "intrin.h".}
      var b = b
      let c = umul128(a, b, addr b)
      result = c xor b
    else:
      result = hiXorLoFallback64(a, b)

when defined(js):
  import std/jsbigints
  import std/private/jsutils

  proc hiXorLoJs(a, b: JsBigInt): JsBigInt =
    let
      prod = a * b
      mask = big"0xffffffffffffffff" # (big"1" shl big"64") - big"1"
    result = (prod shr big"64") xor (prod and mask)

  template hashWangYiJS(x: JsBigInt): Hash =
    let
      P0 = big"0xa0761d6478bd642f"
      P1 = big"0xe7037ed1a0b428db"
      P58 = big"0xeb44accab455d16d" # big"0xeb44accab455d165" xor big"8"
      res = hiXorLoJs(hiXorLoJs(P0, x xor P1), P58)
    cast[Hash](toNumber(wrapToInt(res, 32)))

  template toBits(num: float): JsBigInt =
    let
      x = newArrayBuffer(8)
      y = newFloat64Array(x)
    if hasBigUint64Array():
      let z = newBigUint64Array(x)
      y[0] = num
      z[0]
    else:
      let z = newUint32Array(x)
      y[0] = num
      big(z[0]) + big(z[1]) shl big(32)

proc hashWangYi1*(x: int64|uint64|Hash): Hash {.inline.} =
  ## Wang Yi's hash_v1 for 64-bit ints (see https://github.com/rurban/smhasher for
  ## more details). This passed all scrambling tests in Spring 2019 and is simple.
  ##
  ## **Note:** It's ok to define `proc(x: int16): Hash = hashWangYi1(Hash(x))`.
  const P0  = 0xa0761d6478bd642f'u64
  const P1  = 0xe7037ed1a0b428db'u64
  const P58 = 0xeb44accab455d165'u64 xor 8'u64
  template h(x): untyped = hiXorLo(hiXorLo(P0, uint64(x) xor P1), P58)
  when nimvm:
    when defined(js): # Nim int64<->JS Number & VM match => JS gets 32-bit hash
      result = cast[Hash](h(x)) and cast[Hash](0xFFFFFFFF)
    else:
      result = cast[Hash](h(x))
  else:
    when defined(js):
      if hasJsBigInt():
        result = hashWangYiJS(big(x))
      else:
        result = cast[Hash](x) and cast[Hash](0xFFFFFFFF)
    else:
      result = cast[Hash](h(x))

proc hashData*(data: pointer, size: int): Hash =
  ## Hashes an array of bytes of size `size`.
  var h: Hash = 0
  when defined(js):
    var p: cstring
    {.emit: """`p` = `Data`;""".}
  else:
    var p = cast[cstring](data)
  var i = 0
  var s = size
  while s > 0:
    h = h !& ord(p[i])
    inc(i)
    dec(s)
  result = !$h

proc hashIdentity*[T: Ordinal|enum](x: T): Hash {.inline, since: (1, 3).} =
  ## The identity hash, i.e. `hashIdentity(x) = x`.
  cast[Hash](ord(x))

when defined(nimIntHash1):
  proc hash*[T: Ordinal|enum](x: T): Hash {.inline.} =
    ## Efficient hashing of integers.
    cast[Hash](ord(x))
else:
  proc hash*[T: Ordinal|enum](x: T): Hash {.inline.} =
    ## Efficient hashing of integers.
    hashWangYi1(uint64(ord(x)))

when defined(js):
  var objectID = 0
  proc getObjectId(x: pointer): int =
    {.emit: """
      if (typeof `x` == "object") {
        if ("_NimID" in `x`)
          `result` = `x`["_NimID"];
        else {
          `result` = ++`objectID`;
          `x`["_NimID"] = `result`;
        }
      }
    """.}

proc hash*(x: pointer): Hash {.inline.} =
  ## Efficient `hash` overload.
  when defined(js):
    let y = getObjectId(x)
  else:
    let y = cast[int](x)
  hash(y) # consistent with code expecting scrambled hashes depending on `nimIntHash1`.

proc hash*[T](x: ptr[T]): Hash {.inline.} =
  ## Efficient `hash` overload.
  runnableExamples:
    var a: array[10, uint8]
    assert a[0].addr.hash != a[1].addr.hash
    assert cast[pointer](a[0].addr).hash == a[0].addr.hash
  hash(cast[pointer](x))

when defined(nimPreviewHashRef) or defined(nimdoc):
  proc hash*[T](x: ref[T]): Hash {.inline.} =
    ## Efficient `hash` overload.
    ##
    ## .. important:: Use `-d:nimPreviewHashRef` to
    ##    enable hashing `ref`s. It is expected that this behavior
    ##    becomes the new default in upcoming versions.
    runnableExamples("-d:nimPreviewHashRef"):
      type A = ref object
        x: int
      let a = A(x: 3)
      let ha = a.hash
      assert ha != A(x: 3).hash # A(x: 3) is a different ref object from `a`.
      a.x = 4
      assert ha == a.hash # the hash only depends on the address
    runnableExamples("-d:nimPreviewHashRef"):
      # you can overload `hash` if you want to customize semantics
      type A[T] = ref object
        x, y: T
      proc hash(a: A): Hash = hash(a.x)
      assert A[int](x: 3, y: 4).hash == A[int](x: 3, y: 5).hash
    # xxx pending bug #17733, merge as `proc hash*(pointer | ref | ptr): Hash`
    # or `proc hash*[T: ref | ptr](x: T): Hash`
    hash(cast[pointer](x))

proc hash*(x: float): Hash {.inline.} =
  ## Efficient hashing of floats.
  let y = x + 0.0 # for denormalization
  when nimvm:
    # workaround a JS VM bug: bug #16547
    result = hashWangYi1(cast[int64](float64(y)))
  else:
    when not defined(js):
      result = hashWangYi1(cast[Hash](y))
    else:
      result = hashWangYiJS(toBits(y))

# Forward declarations before methods that hash containers. This allows
# containers to contain other containers
proc hash*[A](x: openArray[A]): Hash
proc hash*[A](x: set[A]): Hash


when defined(js):
  proc imul(a, b: uint32): uint32 =
    # https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Math/imul
    let mask = 0xffff'u32
    var
      aHi = (a shr 16) and mask
      aLo = a and mask
      bHi = (b shr 16) and mask
      bLo = b and mask
    result = (aLo * bLo) + (aHi * bLo + aLo * bHi) shl 16
else:
  template imul(a, b: uint32): untyped = a * b

proc rotl32(x: uint32, r: int): uint32 {.inline.} =
  (x shl r) or (x shr (32 - r))

proc murmurHash(x: openArray[byte]): Hash =
  # https://github.com/PeterScott/murmur3/blob/master/murmur3.c
  const
    c1 = 0xcc9e2d51'u32
    c2 = 0x1b873593'u32
    n1 = 0xe6546b64'u32
    m1 = 0x85ebca6b'u32
    m2 = 0xc2b2ae35'u32
  let
    size = len(x)
    stepSize = 4 # 32-bit
    n = size div stepSize
  var
    h1: uint32 = uint32(0)
    i = 0


  template impl =
    var j = stepSize
    while j > 0:
      dec j
      k1 = (k1 shl 8) or (ord(x[i+j])).uint32

  # body
  while i < n * stepSize:
    var k1: uint32 = uint32(0)

    when nimvm:
      impl()
    else:
      when declared(copyMem):
        copyMem(addr k1, addr x[i], 4)
      else:
        impl()
    inc i, stepSize

    k1 = imul(k1, c1)
    k1 = rotl32(k1, 15)
    k1 = imul(k1, c2)

    h1 = h1 xor k1
    h1 = rotl32(h1, 13)
    h1 = h1*5 + n1

  # tail
  var k1: uint32 = uint32(0)
  var rem = size mod stepSize
  while rem > 0:
    dec rem
    k1 = (k1 shl 8) or (ord(x[i+rem])).uint32
  k1 = imul(k1, c1)
  k1 = rotl32(k1, 15)
  k1 = imul(k1, c2)
  h1 = h1 xor k1

  # finalization
  h1 = h1 xor size.uint32
  h1 = h1 xor (h1 shr 16)
  h1 = imul(h1, m1)
  h1 = h1 xor (h1 shr 13)
  h1 = imul(h1, m2)
  h1 = h1 xor (h1 shr 16)
  return cast[Hash](h1)

proc hashVmImpl(x: cstring, sPos, ePos: int): Hash =
  raiseAssert "implementation override in compiler/vmops.nim"

proc hashVmImpl(x: string, sPos, ePos: int): Hash =
  raiseAssert "implementation override in compiler/vmops.nim"

proc hashVmImplChar(x: openArray[char], sPos, ePos: int): Hash =
  raiseAssert "implementation override in compiler/vmops.nim"

proc hashVmImplByte(x: openArray[byte], sPos, ePos: int): Hash =
  raiseAssert "implementation override in compiler/vmops.nim"

const k0 = 0xc3a5c85c97cb3127u64 # Primes on (2^63, 2^64) for various uses
const k1 = 0xb492b66fbe98f273u64
const k2 = 0x9ae16a3b2f90404fu64

proc load4e(s: openArray[byte], o=0): uint32 {.inline.} =
  uint32(s[o + 3]) shl 24 or uint32(s[o + 2]) shl 16 or
  uint32(s[o + 1]) shl  8 or uint32(s[o + 0])

proc load8e(s: openArray[byte], o=0): uint64 {.inline.} =
  uint64(s[o + 7]) shl 56 or uint64(s[o + 6]) shl 48 or
  uint64(s[o + 5]) shl 40 or uint64(s[o + 4]) shl 32 or
  uint64(s[o + 3]) shl 24 or uint64(s[o + 2]) shl 16 or
  uint64(s[o + 1]) shl  8 or uint64(s[o + 0])

proc load4(s: openArray[byte], o=0): uint32 {.inline.} =
  when nimvm: result = load4e(s, o)
  else:
    when declared copyMem:
      result = uint32(0)
      copyMem result.addr, s[o].addr, result.sizeof
    else: result = load4e(s, o)

proc load8(s: openArray[byte], o=0): uint64 {.inline.} =
  when nimvm: result = load8e(s, o)
  else:
    when declared copyMem:
      result = uint64(0)
      copyMem result.addr, s[o].addr, result.sizeof
    else: result = load8e(s, o)

proc lenU(s: openArray[byte]): uint64 {.inline.} = s.len.uint64

proc shiftMix(v: uint64): uint64 {.inline.} = v xor (v shr 47)

proc rotR(v: uint64; bits: cint): uint64 {.inline.} =
  (v shr bits) or (v shl (64 - bits))

proc len16(u: uint64; v: uint64; mul: uint64): uint64 {.inline.} =
  var a = (u xor v)*mul
  a = a xor (a shr 47)
  var b = (v xor a)*mul
  b = b xor (b shr 47)
  b*mul

proc len0_16(s: openArray[byte]): uint64 {.inline.} =
  if s.len >= 8:
    let mul = k2 + 2*s.lenU
    let a   = load8(s) + k2
    let b   = load8(s, s.len - 8)
    let c   = rotR(b, 37)*mul + a
    let d   = (rotR(a, 25) + b)*mul
    len16 c, d, mul
  elif s.len >= 4:
    let mul = k2 + 2*s.lenU
    let a   = load4(s).uint64
    len16 s.lenU + (a shl 3), load4(s, s.len - 4), mul
  elif s.len > 0:
    let a = uint32(s[0])
    let b = uint32(s[s.len shr 1])
    let c = uint32(s[s.len - 1])
    let y = a      + (b shl 8)
    let z = s.lenU + (c shl 2)
    shiftMix(y*k2 xor z*k0)*k2
  else: k2      # s.len == 0

proc len17_32(s: openArray[byte]): uint64 {.inline.} =
  let mul = k2 + 2*s.lenU
  let a = load8(s)*k1
  let b = load8(s, 8)
  let c = load8(s, s.len - 8)*mul
  let d = load8(s, s.len - 16)*k2
  len16 rotR(a + b, 43) + rotR(c, 30) + d, a + rotR(b + k2, 18) + c, mul

proc len33_64(s: openArray[byte]): uint64 {.inline.} =
  let mul = k2 + 2*s.lenU
  let a = load8(s)*k2
  let b = load8(s, 8)
  let c = load8(s, s.len - 8)*mul
  let d = load8(s, s.len - 16)*k2
  let y = rotR(a + b, 43) + rotR(c, 30) + d
  let z = len16(y, a + rotR(b + k2, 18) + c, mul)
  let e = load8(s, 16)*mul
  let f = load8(s, 24)
  let g = (y + load8(s, s.len - 32))*mul
  let h = (z + load8(s, s.len - 24))*mul
  len16 rotR(e + f, 43) + rotR(g, 30) + h, e + rotR(f + a, 18) + g, mul

type Pair = tuple[first, second: uint64]

proc weakLen32withSeeds2(w, x, y, z, a, b: uint64): Pair {.inline.} =
  var a = a + w
  var b = rotR(b + a + z, 21)
  let c = a
  a += x
  a += y
  b += rotR(a, 44)
  result[0] = a + z
  result[1] = b + c

proc weakLen32withSeeds(s: openArray[byte]; o: int; a,b: uint64): Pair {.inline.} =
  weakLen32withSeeds2 load8(s, o     ), load8(s, o + 8),
                      load8(s, o + 16), load8(s, o + 24), a, b

proc hashFarm(s: openArray[byte]): uint64 {.inline.} =
  if s.len <= 16: return len0_16(s)
  if s.len <= 32: return len17_32(s)
  if s.len <= 64: return len33_64(s)
  const seed = 81u64 # not const to use input `h`
  var
    o = 0         # s[] ptr arith -> variable origin variable `o`
    x = seed
    y = seed*k1 + 113
    z = shiftMix(y*k2 + 113)*k2
    v, w: Pair = default(Pair)
  x = x*k2 + load8(s)
  let eos = ((s.len - 1) div 64)*64
  let last64 = eos + ((s.len - 1) and 63) - 63
  while true:
    x = rotR(x + y + v[0] + load8(s, o+8), 37)*k1
    y = rotR(y + v[1] + load8(s, o+48), 42)*k1
    x = x xor w[1]
    y += v[0] + load8(s, o+40)
    z = rotR(z + w[0], 33)*k1
    v = weakLen32withSeeds(s, o+0 , v[1]*k1, x + w[0])
    w = weakLen32withSeeds(s, o+32, z + w[1], y + load8(s, o+16))
    swap z, x
    inc o, 64
    if o == eos: break
  let mul = k1 + ((z and 0xff) shl 1)
  o = last64
  w[0] += (s.lenU - 1) and 63
  v[0] += w[0]
  w[0] += v[0]
  x = rotR(x + y + v[0] + load8(s, o+8), 37)*mul
  y = rotR(y + v[1] + load8(s, o+48), 42)*mul
  x = x xor w[1]*9
  y += v[0]*9 + load8(s, o+40)
  z = rotR(z + w[0], 33)*mul
  v = weakLen32withSeeds(s, o+0 , v[1]*mul, x + w[0])
  w = weakLen32withSeeds(s, o+32, z + w[1], y + load8(s, o+16))
  swap z, x
  len16 len16(v[0],w[0],mul) + shiftMix(y)*k0 + z, len16(v[1],w[1],mul) + x, mul

const sHash2 = defined(nimStringHash2) or jsNoBigInt64

template maybeFailJS_Number =
  when jsNoBigInt64 and not defined(nimStringHash2):
    {.error: "Must use `-d:nimStringHash2` when using `--jsbigint64:off`".}

proc hash*(x: string): Hash =
  ## Efficient hashing of strings.
  ##
  ## **See also:**
  ## * `hashIgnoreStyle <#hashIgnoreStyle,string>`_
  ## * `hashIgnoreCase <#hashIgnoreCase,string>`_
  runnableExamples:
    doAssert hash("abracadabra") != hash("AbracadabrA")
  maybeFailJS_Number()
  when not sHash2:
    result = cast[Hash](hashFarm(toOpenArrayByte(x, 0, x.high)))
  else:
    #when nimvm:
    #  result = hashVmImpl(x, 0, high(x))
    when true:
      result = murmurHash(toOpenArrayByte(x, 0, high(x)))

proc hash*(x: cstring): Hash =
  ## Efficient hashing of null-terminated strings.
  runnableExamples:
    doAssert hash(cstring"abracadabra") == hash("abracadabra")
    doAssert hash(cstring"AbracadabrA") == hash("AbracadabrA")
    doAssert hash(cstring"abracadabra") != hash(cstring"AbracadabrA")

  maybeFailJS_Number()
  when not sHash2:
    when defined js:
      let xx = $x
      result = cast[Hash](hashFarm(toOpenArrayByte(xx, 0, xx.high)))
    else:
      result = cast[Hash](hashFarm(toOpenArrayByte(x, 0, x.high)))
  else:
    #when nimvm:
    #  result = hashVmImpl(x, 0, high(x))
    when true:
      when not defined(js):
        result = murmurHash(toOpenArrayByte(x, 0, x.high))
      else:
        let xx = $x
        result = murmurHash(toOpenArrayByte(xx, 0, high(xx)))

proc hash*(sBuf: string, sPos, ePos: int): Hash =
  ## Efficient hashing of a string buffer, from starting
  ## position `sPos` to ending position `ePos` (included).
  ##
  ## `hash(myStr, 0, myStr.high)` is equivalent to `hash(myStr)`.
  runnableExamples:
    var a = "abracadabra"
    doAssert hash(a, 0, 3) == hash(a, 7, 10)

  maybeFailJS_Number()
  when not sHash2:
    result = cast[Hash](hashFarm(toOpenArrayByte(sBuf, sPos, ePos)))
  else:
    murmurHash(toOpenArrayByte(sBuf, sPos, ePos))

proc hashIgnoreStyle*(x: string): Hash =
  ## Efficient hashing of strings; style is ignored.
  ##
  ## **Note:** This uses a different hashing algorithm than `hash(string)`.
  ##
  ## **See also:**
  ## * `hashIgnoreCase <#hashIgnoreCase,string>`_
  runnableExamples:
    doAssert hashIgnoreStyle("aBr_aCa_dAB_ra") == hashIgnoreStyle("abracadabra")
    doAssert hashIgnoreStyle("abcdefghi") != hash("abcdefghi")

  var h: Hash = 0
  var i = 0
  let xLen = x.len
  while i < xLen:
    var c = x[i]
    if c == '_':
      inc(i)
    else:
      if c in {'A'..'Z'}:
        c = chr(ord(c) + (ord('a') - ord('A'))) # toLower()
      h = h !& ord(c)
      inc(i)
  result = !$h

proc hashIgnoreStyle*(sBuf: string, sPos, ePos: int): Hash =
  ## Efficient hashing of a string buffer, from starting
  ## position `sPos` to ending position `ePos` (included); style is ignored.
  ##
  ## **Note:** This uses a different hashing algorithm than `hash(string)`.
  ##
  ## `hashIgnoreStyle(myBuf, 0, myBuf.high)` is equivalent
  ## to `hashIgnoreStyle(myBuf)`.
  runnableExamples:
    var a = "ABracada_b_r_a"
    doAssert hashIgnoreStyle(a, 0, 3) == hashIgnoreStyle(a, 7, a.high)

  var h: Hash = 0
  var i = sPos
  while i <= ePos:
    var c = sBuf[i]
    if c == '_':
      inc(i)
    else:
      if c in {'A'..'Z'}:
        c = chr(ord(c) + (ord('a') - ord('A'))) # toLower()
      h = h !& ord(c)
      inc(i)
  result = !$h

proc hashIgnoreCase*(x: string): Hash =
  ## Efficient hashing of strings; case is ignored.
  ##
  ## **Note:** This uses a different hashing algorithm than `hash(string)`.
  ##
  ## **See also:**
  ## * `hashIgnoreStyle <#hashIgnoreStyle,string>`_
  runnableExamples:
    doAssert hashIgnoreCase("ABRAcaDABRA") == hashIgnoreCase("abRACAdabra")
    doAssert hashIgnoreCase("abcdefghi") != hash("abcdefghi")

  var h: Hash = 0
  for i in 0..x.len-1:
    var c = x[i]
    if c in {'A'..'Z'}:
      c = chr(ord(c) + (ord('a') - ord('A'))) # toLower()
    h = h !& ord(c)
  result = !$h

proc hashIgnoreCase*(sBuf: string, sPos, ePos: int): Hash =
  ## Efficient hashing of a string buffer, from starting
  ## position `sPos` to ending position `ePos` (included); case is ignored.
  ##
  ## **Note:** This uses a different hashing algorithm than `hash(string)`.
  ##
  ## `hashIgnoreCase(myBuf, 0, myBuf.high)` is equivalent
  ## to `hashIgnoreCase(myBuf)`.
  runnableExamples:
    var a = "ABracadabRA"
    doAssert hashIgnoreCase(a, 0, 3) == hashIgnoreCase(a, 7, 10)

  var h: Hash = 0
  for i in sPos..ePos:
    var c = sBuf[i]
    if c in {'A'..'Z'}:
      c = chr(ord(c) + (ord('a') - ord('A'))) # toLower()
    h = h !& ord(c)
  result = !$h

proc hash*[T: tuple | object | proc | iterator {.closure.}](x: T): Hash =
  ## Efficient `hash` overload.
  runnableExamples:
    # for `tuple|object`, `hash` must be defined for each component of `x`.
    type Obj = object
      x: int
      y: string
    type Obj2[T] = object
      x: int
      y: string
    assert hash(Obj(x: 520, y: "Nim")) != hash(Obj(x: 520, y: "Nim2"))
    # you can define custom hashes for objects (even if they're generic):
    proc hash(a: Obj2): Hash = hash((a.x))
    assert hash(Obj2[float](x: 520, y: "Nim")) == hash(Obj2[float](x: 520, y: "Nim2"))
  runnableExamples:
    # proc
    proc fn1() = discard
    const fn1b = fn1
    assert hash(fn1b) == hash(fn1)

    # closure
    proc outer =
      var a = 0
      proc fn2() = a.inc
      assert fn2 is "closure"
      let fn2b = fn2
      assert hash(fn2b) == hash(fn2)
      assert hash(fn2) != hash(fn1)
    outer()

  when T is "closure":
    result = hash((rawProc(x), rawEnv(x)))
  elif T is (proc):
    result = hash(cast[pointer](x))
  else:
    result = 0
    for f in fields(x):
      result = result !& hash(f)
    result = !$result

proc hash*[A](x: openArray[A]): Hash =
  ## Efficient hashing of arrays and sequences.
  ## There must be a `hash` proc defined for the element type `A`.
  when A is byte:
    when not sHash2:
      result = cast[Hash](hashFarm(x))
    else:
      result = murmurHash(x)
  elif A is char:
    when not sHash2:
      result = cast[Hash](hashFarm(toOpenArrayByte(x, 0, x.high)))
    else:
      #when nimvm:
      #  result = hashVmImplChar(x, 0, x.high)
      when true:
        result = murmurHash(toOpenArrayByte(x, 0, x.high))
  else:
    result = 0
    for a in x:
      result = result !& hash(a)
    result = !$result

proc hash*[A](aBuf: openArray[A], sPos, ePos: int): Hash =
  ## Efficient hashing of portions of arrays and sequences, from starting
  ## position `sPos` to ending position `ePos` (included).
  ## There must be a `hash` proc defined for the element type `A`.
  ##
  ## `hash(myBuf, 0, myBuf.high)` is equivalent to `hash(myBuf)`.
  runnableExamples:
    let a = [1, 2, 5, 1, 2, 6]
    doAssert hash(a, 0, 1) == hash(a, 3, 4)
  when A is byte:
    maybeFailJS_Number()
    when not sHash2:
      result = cast[Hash](hashFarm(toOpenArray(aBuf, sPos, ePos)))
    else:
      #when nimvm:
      #  result = hashVmImplByte(aBuf, sPos, ePos)
      when true:
        result = murmurHash(toOpenArray(aBuf, sPos, ePos))
  elif A is char:
    maybeFailJS_Number()
    when not sHash2:
      result = cast[Hash](hashFarm(toOpenArrayByte(aBuf, sPos, ePos)))
    else:
      #when nimvm:
      #  result = hashVmImplChar(aBuf, sPos, ePos)
      when true:
        result = murmurHash(toOpenArrayByte(aBuf, sPos, ePos))
  else:
    for i in sPos .. ePos:
      result = result !& hash(aBuf[i])
    result = !$result

proc hash*[A](x: set[A]): Hash =
  ## Efficient hashing of sets.
  ## There must be a `hash` proc defined for the element type `A`.
  result = 0
  for it in items(x):
    result = result !& hash(it)
  result = !$result

#
#
#            Nim's Runtime Library
#        (c) Copyright 2017 Nim Authors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements a series of low level methods for bit manipulation.
## By default, this module use compiler intrinsics to improve performance
## on supported compilers: ``GCC``, ``LLVM_GCC``, ``CLANG``, ``VCC``, ``ICC``.
##
## The module will fallback to pure nim procs incase the backend is not supported.
## You can also use the flag `noIntrinsicsBitOpts` to disable compiler intrinsics.
##
## This module is also compatible with other backends: ``Javascript``, ``Nimscript``
## as well as the ``compiletime VM``.
##
## As a result of using optimized function/intrinsics some functions can return
## undefined results if the input is invalid. You can use the flag `noUndefinedBitOpts`
## to force predictable behaviour for all input, causing a small performance hit.
##
## At this time only `fastLog2`, `firstSetBit, `countLeadingZeroBits`, `countTrailingZeroBits`
## may return undefined and/or platform dependant value if given invalid input.


const useBuiltins = not defined(noIntrinsicsBitOpts)
const noUndefined = defined(noUndefinedBitOpts)
const useGCC_builtins = (defined(gcc) or defined(llvm_gcc) or defined(clang)) and useBuiltins
const useICC_builtins = defined(icc) and useBuiltins
const useVCC_builtins = defined(vcc) and useBuiltins
const arch64 = sizeof(int) == 8

template toUint32[T](x: T): uint32 =
  when sizeof(x) == 1: cast[uint8](x).uint32
  elif sizeof(x) == 2: cast[uint16](x).uint32
  else:                cast[uint32](x)

template toUint16[T](x: T): uint16 =
  when sizeof(x) == 1: cast[uint8](x).uint16
  else:                cast[uint16](x)

template gen_bswap64_impl[T](x: uint64; retype: typedesc[T]): uint64 =
  # get lo and hi DWORD, use bswap32 and recombine, swapping lo and hi DWORD
  let lo = builtin_bswap32(cast[T]( (x and 0xFFFFFFFF'u64).uint32) )
  let hi = builtin_bswap32(cast[T]( (x shr 32).uint32) )
  cast[uint32](hi).uint64 or (cast[uint32](lo).uint64 shl 32)


# #### Pure Nim version ####

proc firstSetBit_nim(x: uint32): int {.inline, nosideeffect.} =
  ## Returns the 1-based index of the least significant set bit of x, or if x is zero, returns zero.
  # https://graphics.stanford.edu/%7Eseander/bithacks.html#ZerosOnRightMultLookup
  const lookup: array[32, uint8] = [0'u8, 1, 28, 2, 29, 14, 24, 3, 30, 22, 20, 15,
    25, 17, 4, 8, 31, 27, 13, 23, 21, 19, 16, 7, 26, 12, 18, 6, 11, 5, 10, 9]
  var v = x.uint32
  var k = not v + 1 # get two's complement # cast[uint32](-cast[int32](v))
  result = 1 + lookup[uint32((v and k) * 0x077CB531'u32) shr 27].int

proc firstSetBit_nim(x: uint64): int {.inline, nosideeffect.} =
  ## Returns the 1-based index of the least significant set bit of x, or if x is zero, returns zero.
  # https://graphics.stanford.edu/%7Eseander/bithacks.html#ZerosOnRightMultLookup
  var v = uint64(x)
  var k = uint32(v and 0xFFFFFFFF'u32)
  if k == 0:
    k = uint32(v shr 32'u32) and 0xFFFFFFFF'u32
    result = 32
  result += firstSetBit_nim(k)

proc fastlog2_nim(x: uint32): int {.inline, nosideeffect.} =
  ## Quickly find the log base 2 of a 32-bit or less integer.
  # https://graphics.stanford.edu/%7Eseander/bithacks.html#IntegerLogDeBruijn
  # https://stackoverflow.com/questions/11376288/fast-computing-of-log2-for-64-bit-integers
  const lookup: array[32, uint8] = [0'u8, 9, 1, 10, 13, 21, 2, 29, 11, 14, 16, 18,
    22, 25, 3, 30, 8, 12, 20, 28, 15, 17, 24, 7, 19, 27, 23, 6, 26, 5, 4, 31]
  var v = x.uint32
  v = v or v shr 1 # first round down to one less than a power of 2
  v = v or v shr 2
  v = v or v shr 4
  v = v or v shr 8
  v = v or v shr 16
  result = lookup[uint32(v * 0x07C4ACDD'u32) shr 27].int

proc fastlog2_nim(x: uint64): int {.inline, nosideeffect.} =
  ## Quickly find the log base 2 of a 64-bit integer.
  # https://graphics.stanford.edu/%7Eseander/bithacks.html#IntegerLogDeBruijn
  # https://stackoverflow.com/questions/11376288/fast-computing-of-log2-for-64-bit-integers
  const lookup: array[64, uint8] = [0'u8, 58, 1, 59, 47, 53, 2, 60, 39, 48, 27, 54,
    33, 42, 3, 61, 51, 37, 40, 49, 18, 28, 20, 55, 30, 34, 11, 43, 14, 22, 4, 62,
    57, 46, 52, 38, 26, 32, 41, 50, 36, 17, 19, 29, 10, 13, 21, 56, 45, 25, 31,
    35, 16, 9, 12, 44, 24, 15, 8, 23, 7, 6, 5, 63]
  var v = x.uint64
  v = v or v shr 1 # first round down to one less than a power of 2
  v = v or v shr 2
  v = v or v shr 4
  v = v or v shr 8
  v = v or v shr 16
  v = v or v shr 32
  result = lookup[(v * 0x03F6EAF2CD271461'u64) shr 58].int


proc countSetBits_nim(n: uint32): int {.inline, noSideEffect.} =
  ## Counts the set bits in integer. (also called Hamming weight.)
  # generic formula is from: https://graphics.stanford.edu/~seander/bithacks.html#CountBitsSetParallel

  var v = uint32(n)
  v = v - ((v shr 1) and 0x55555555)
  v = (v and 0x33333333) + ((v shr 2) and 0x33333333)
  result = (((v + (v shr 4) and 0xF0F0F0F) * 0x1010101) shr 24).int

proc countSetBits_nim(n: uint64): int {.inline, noSideEffect.} =
  ## Counts the set bits in integer. (also called Hamming weight.)
  # generic formula is from: https://graphics.stanford.edu/~seander/bithacks.html#CountBitsSetParallel
  var v = uint64(n)
  v = v - ((v shr 1'u64) and 0x5555555555555555'u64)
  v = (v and 0x3333333333333333'u64) + ((v shr 2'u64) and 0x3333333333333333'u64)
  v = (v + (v shr 4'u64) and 0x0F0F0F0F0F0F0F0F'u64)
  result = ((v * 0x0101010101010101'u64) shr 56'u64).int

proc swapEndian_nim(val: uint16): uint16 {.inline, noSideEffect.} =
  ## Reverse byte order in integer.
  result =  ((val and 0xFF00'u16) shr  8) or
            ((val and 0x00FF'u16) shl 8)

proc swapEndian_nim(val: uint32): uint32 {.inline, noSideEffect.} =
  ## Reverse byte order in integer.
  result =  ((val and 0xFF000000'u32) shr 24) or
            ((val and 0x00FF0000'u32) shr  8) or
            ((val and 0x0000FF00'u32) shl  8) or
            ((val and 0x000000FF'u32) shl 24)

proc swapEndian_nim(val: uint64): uint64 {.inline, noSideEffect.} =
  ## Reverse byte order in integer.
  result =  ((val and 0x00000000000000FF'u64) shl 56) or
            ((val and 0x000000000000FF00'u64) shl 40) or
            ((val and 0x0000000000FF0000'u64) shl 24) or
            ((val and 0x00000000FF000000'u64) shl  8) or
            ((val and 0x000000FF00000000'u64) shr  8) or
            ((val and 0x0000FF0000000000'u64) shr 24) or
            ((val and 0x00FF000000000000'u64) shr 40) or
            ((val and 0xFF00000000000000'u64) shr 56)


proc parity_nim[T](value: T): int =
  # formula id from: https://graphics.stanford.edu/%7Eseander/bithacks.html#ParityParallel
  var v = value
  when sizeof(T) == 8:
    v = v xor (v shr 32)
  when sizeof(T) >= 4:
    v = v xor (v shr 16)
  when sizeof(T) >= 2:
    v = v xor (v shr 8)
  v = v xor (v shr 4)
  v = v and 0xf
  ((0x6996'u shr v) and 1).int


when useGCC_builtins:
  # Returns the number of set 1-bits in value.
  proc builtin_popcount(x: cuint): cint {.importc: "__builtin_popcount", cdecl.}
  proc builtin_popcountll(x: culonglong): cint {.importc: "__builtin_popcountll", cdecl.}

  # Returns the bit parity in value
  proc builtin_parity(x: cuint): cint {.importc: "__builtin_parity", cdecl.}
  proc builtin_parityll(x: culonglong): cint {.importc: "__builtin_parityll", cdecl.}

  # Returns one plus the index of the least significant 1-bit of x, or if x is zero, returns zero.
  proc builtin_ffs(x: cint): cint {.importc: "__builtin_ffs", cdecl.}
  proc builtin_ffsll(x: clonglong): cint {.importc: "__builtin_ffsll", cdecl.}

  # Returns the number of leading 0-bits in x, starting at the most significant bit position. If x is 0, the result is undefined.
  proc builtin_clz(x: cuint): cint {.importc: "__builtin_clz", cdecl.}
  proc builtin_clzll(x: culonglong): cint {.importc: "__builtin_clzll", cdecl.}

  # Returns the number of trailing 0-bits in x, starting at the least significant bit position. If x is 0, the result is undefined.
  proc builtin_ctz(x: cuint): cint {.importc: "__builtin_ctz", cdecl.}
  proc builtin_ctzll(x: culonglong): cint {.importc: "__builtin_ctzll", cdecl.}

  # Returns x with the order of the bytes reversed; for example, 0xaabb becomes 0xbbaa. Byte here always means exactly 8 bits.
  proc builtin_bswap16(x: uint16): uint16 {.importc: "__builtin_bswap16", nodecl, nosideeffect.}
  proc builtin_bswap32(x: uint32): uint32 {.importc: "__builtin_bswap32", nodecl, nosideeffect.}
  proc builtin_bswap64(x: uint64): uint64 {.importc: "__builtin_bswap64", nodecl, nosideeffect.}

elif useVCC_builtins:
  # Counts the number of one bits (population count) in a 16-, 32-, or 64-byte unsigned integer.
  proc builtin_popcnt16(a2: uint16): uint16 {.importc: "__popcnt16" header: "<intrin.h>", nosideeffect.}
  proc builtin_popcnt32(a2: uint32): uint32 {.importc: "__popcnt" header: "<intrin.h>", nosideeffect.}
  proc builtin_popcnt64(a2: uint64): uint64 {.importc: "__popcnt64" header: "<intrin.h>", nosideeffect.}

  # Search the mask data from most significant bit (MSB) to least significant bit (LSB) for a set bit (1).
  proc bitScanReverse(index: ptr culong, mask: culong): cuchar {.importc: "_BitScanReverse", header: "<intrin.h>", nosideeffect.}
  proc bitScanReverse64(index: ptr culong, mask: uint64): cuchar {.importc: "_BitScanReverse64", header: "<intrin.h>", nosideeffect.}

  # Search the mask data from least significant bit (LSB) to the most significant bit (MSB) for a set bit (1).
  proc bitScanForward(index: ptr culong, mask: culong): cuchar {.importc: "_BitScanForward", header: "<intrin.h>", nosideeffect.}
  proc bitScanForward64(index: ptr culong, mask: uint64): cuchar {.importc: "_BitScanForward64", header: "<intrin.h>", nosideeffect.}

  # https://msdn.microsoft.com/en-us/library/a3140177.aspx?query=
  proc builtin_bswap16(a: cushort): cushort {.importc: "_byteswap_ushort", nodecl, header: "<intrin.h>", nosideeffect.}
  proc builtin_bswap32(a: culong): culong {.importc: "_byteswap_ulong", nodecl, header: "<intrin.h>", nosideeffect.}
  proc builtin_bswap64(a: uint64): uint64 {.importc: "_byteswap_uint64", nodecl, header: "<intrin.h>", nosideeffect.}

  template vcc_scan_impl(fnc: untyped; v: untyped): int =
    var index: culong
    discard fnc(index.addr, v)
    index.int

elif useICC_builtins:

  # Intel compiler intrinsics: http://fulla.fnal.gov/intel/compiler_c/main_cls/intref_cls/common/intref_allia_misc.htm
  # see also: https://software.intel.com/en-us/node/523362
  # Count the number of bits set to 1 in an integer a, and return that count in dst.
  proc builtin_popcnt32(a: cint): cint {.importc: "_popcnt" header: "<immintrin.h>", nosideeffect.}
  proc builtin_popcnt64(a: uint64): cint {.importc: "_popcnt64" header: "<immintrin.h>", nosideeffect.}

  # Returns the number of trailing 0-bits in x, starting at the least significant bit position. If x is 0, the result is undefined.
  proc bitScanForward(p: ptr uint32, b: uint32): cuchar {.importc: "_BitScanForward", header: "<immintrin.h>", nosideeffect.}
  proc bitScanForward64(p: ptr uint32, b: uint64): cuchar {.importc: "_BitScanForward64", header: "<immintrin.h>", nosideeffect.}

  # Returns the number of leading 0-bits in x, starting at the most significant bit position. If x is 0, the result is undefined.
  proc bitScanReverse(p: ptr uint32, b: uint32): cuchar {.importc: "_BitScanReverse", header: "<immintrin.h>", nosideeffect.}
  proc bitScanReverse64(p: ptr uint32, b: uint64): cuchar {.importc: "_BitScanReverse64", header: "<immintrin.h>", nosideeffect.}

  # Swap byte order in integer
  # https://software.intel.com/sites/landingpage/IntrinsicsGuide/#techs=MMX,SSE,SSE2,SSE3,SSSE3,SSE4_1,SSE4_2,AVX,AVX2,FMA,AVX_512,KNC,SVML,Other&text=swap&expand=559,3035,559,558
  proc builtin_bswap32(a: cint): cint {.importc: "_bswap", header: "<immintrin.h>", nodecl, nosideeffect.}
  proc builtin_bswap64(a: int64): int64 {.importc: "_bswap64", header: "<immintrin.h>", nodecl, nosideeffect.}

  template icc_scan_impl(fnc: untyped; v: untyped): int =
    var index: uint32
    discard fnc(index.addr, v)
    index.int


proc countSetBits*(x: SomeInteger): int {.inline, nosideeffect.} =
  ## Counts the set bits in integer. (also called `Hamming weight`:idx:.)
  # TODO: figure out if ICC support _popcnt32/_popcnt64 on platform without POPCNT.
  # like GCC and MSVC
  when nimvm:
    when sizeof(x) <= 4: result = countSetBits_nim(x.toUint32)
    else:                result = countSetBits_nim(x.uint64)
  else:
    when useGCC_builtins:
      when sizeof(x) <= 4: result = builtin_popcount(cast[cuint](x.toUint32)).int
      else:                result = builtin_popcountll(cast[culonglong](x.uint64)).int
    elif useVCC_builtins:
      when sizeof(x) <= 2: result = builtin_popcnt16(x.toUint16).int
      elif sizeof(x) <= 4: result = builtin_popcnt32(x.toUint32).int
      elif arch64:         result = builtin_popcnt64(x.uint64).int
      else:                result = builtin_popcnt32((x.uint64 and 0xFFFFFFFF'u64).uint32 ).int +
                                    builtin_popcnt32((x.uint64 shr 32'u64).uint32 ).int
    elif useICC_builtins:
      when sizeof(x) <= 4: result = builtin_popcnt32(cast[cint](x.toUint32)).int
      elif arch64:         result = builtin_popcnt64(x.uint64).int
      else:                result = builtin_popcnt32((x.uint64 and 0xFFFFFFFF'u64).cint ).int +
                                    builtin_popcnt32((x.uint64 shr 32'u64).cint ).int
    else:
      when sizeof(x) <= 4: result = countSetBits_nim(x.toUint32)
      else:                result = countSetBits_nim(x.uint64)

proc popcount*(x: SomeInteger): int {.inline, nosideeffect.} =
  ## Alias for for countSetBits (Hamming weight.)
  result = countSetBits(x)

proc parityBits*(x: SomeInteger): int {.inline, nosideeffect.} =
  ## Calculate the bit parity in integer. If number of 1-bit
  ## is odd parity is 1, otherwise 0.
  # Can be used a base if creating ASM version.
  # https://stackoverflow.com/questions/21617970/how-to-check-if-value-has-even-parity-of-bits-or-odd
  when nimvm:
    when sizeof(x) <= 4: result = parity_nim(x.toUint32)
    else:                result = parity_nim(x.uint64)
  else:
    when useGCC_builtins:
      when sizeof(x) <= 4: result = builtin_parity(cast[cuint](x.toUint32)).int
      else:                result = builtin_parityll(x.uint64).int
    else:
      when sizeof(x) <= 4: result = parity_nim(x.toUint32)
      else:                result = parity_nim(x.uint64)

proc firstSetBit*(x: SomeInteger): int {.inline, nosideeffect.} =
  ## Returns the 1-based index of the least significant set bit of x.
  ## If `x` is zero, when ``noUndefinedBitOpts`` is set, result is 0,
  ## otherwise result is undefined.
  # GCC builtin 'builtin_ffs' already handle zero input.
  when nimvm:
    when noUndefined:
      if x == 0:
        return 0
    when sizeof(x) <= 4: result = firstSetBit_nim(x.toUint32)
    else:                result = firstSetBit_nim(x.uint64)
  else:
    when noUndefined and not useGCC_builtins:
      if x == 0:
        return 0
    when useGCC_builtins:
      when sizeof(x) <= 4: result = builtin_ffs(cast[cint](x.toUint32)).int
      else:                result = builtin_ffsll(cast[clonglong](x)).int
    elif useVCC_builtins:
      when sizeof(x) <= 4:
        result = 1 + vcc_scan_impl(bitScanForward, cast[culong](x.toUint32))
      elif arch64:
        result = 1 + vcc_scan_impl(bitScanForward64, x.uint64)
      else:
        result = firstSetBit_nim(x.uint64)
    elif useICC_builtins:
      when sizeof(x) <= 4:
        result = 1 + icc_scan_impl(bitScanForward, x.toUint32)
      elif arch64:
        result = 1 + icc_scan_impl(bitScanForward64, x.uint64)
      else:
        result = firstSetBit_nim(x.uint64)
    else:
      when sizeof(x) <= 4: result = firstSetBit_nim(x.toUint32)
      else:                result = firstSetBit_nim(x.uint64)

proc fastLog2*(x: SomeInteger): int {.inline, nosideeffect.} =
  ## Quickly find the log base 2 of an integer.
  ## If `x` is zero, when ``noUndefinedBitOpts`` is set, result is -1,
  ## otherwise result is undefined.
  when noUndefined:
    if x == 0:
      return -1
  when nimvm:
    when sizeof(x) <= 4: result = fastlog2_nim(x.toUint32)
    else:                result = fastlog2_nim(x.uint64)
  else:
    when useGCC_builtins:
      when sizeof(x) <= 4: result = 31 - builtin_clz(x.toUint32).int
      else:                result = 63 - builtin_clzll(x.uint64).int
    elif useVCC_builtins:
      when sizeof(x) <= 4:
        result = vcc_scan_impl(bitScanReverse, cast[culong](x.toUint32))
      elif arch64:
        result = vcc_scan_impl(bitScanReverse64, x.uint64)
      else:
        result = fastlog2_nim(x.uint64)
    elif useICC_builtins:
      when sizeof(x) <= 4:
        result = icc_scan_impl(bitScanReverse, x.toUint32)
      elif arch64:
        result = icc_scan_impl(bitScanReverse64, x.uint64)
      else:
        result = fastlog2_nim(x.uint64)
    else:
      when sizeof(x) <= 4: result = fastlog2_nim(x.toUint32)
      else:                result = fastlog2_nim(x.uint64)

proc countLeadingZeroBits*(x: SomeInteger): int {.inline, nosideeffect.} =
  ## Returns the number of leading zero bits in integer.
  ## If `x` is zero, when ``noUndefinedBitOpts`` is set, result is 0,
  ## otherwise result is undefined.
  when noUndefined:
    if x == 0:
      return 0
  when nimvm:
      when sizeof(x) <= 4: result = sizeof(x)*8 - 1 - fastlog2_nim(x.toUint32)
      else:                result = sizeof(x)*8 - 1 - fastlog2_nim(x.uint64)
  else:
    when useGCC_builtins:
      when sizeof(x) <= 4: result = builtin_clz(x.toUint32).int - (32 - sizeof(x)*8)
      else:                result = builtin_clzll(x.uint64).int
    else:
      when sizeof(x) <= 4: result = sizeof(x)*8 - 1 - fastlog2_nim(x.toUint32)
      else:                result = sizeof(x)*8 - 1 - fastlog2_nim(x.uint64)

proc countTrailingZeroBits*(x: SomeInteger): int {.inline, nosideeffect.} =
  ## Returns the number of trailing zeros in integer.
  ## If `x` is zero, when ``noUndefinedBitOpts`` is set, result is 0,
  ## otherwise result is undefined.
  when noUndefined:
    if x == 0:
      return 0
  when nimvm:
    result = firstSetBit(x) - 1
  else:
    when useGCC_builtins:
      when sizeof(x) <= 4: result = builtin_ctz(x.toUint32).int
      else:                result = builtin_ctzll(x.uint64).int
    else:
      result = firstSetBit(x) - 1

proc swapEndian*[T:SomeInteger](x: T): T {.inline, nosideeffect.} =
  ## Reverse byte order in integer.
  when nimvm:
    when sizeof(x) == 1: result = x
    elif sizeof(x) == 2: result = cast[T](swapEndian_nim(x.toUint16))
    elif sizeof(x) == 4: result = cast[T](swapEndian_nim(x.toUint32))
    else:                result = cast[T](swapEndian_nim(x.uint64))
  else:
    when sizeof(x) == 1: result = x
    elif useGCC_builtins:
      when sizeof(x) == 2: result = cast[T](builtin_bswap16(x.toUint16))
      elif sizeof(x) == 4: result = cast[T](builtin_bswap32(x.toUint32))
      else:                result = cast[T](builtin_bswap64(x.uint64))
    elif useVCC_builtins:
      when sizeof(x) == 2: result = cast[T](builtin_bswap16(cast[cushort](x.toUint16)))
      elif sizeof(x) == 4: result = cast[T](builtin_bswap32(cast[culong](x.toUint32)))
      elif arch64:         result = cast[T](builtin_bswap64(x.uint64))
      else:                result = cast[T](gen_bswap64_impl(x.uint64, culong))
    elif useICC_builtins:
      when sizeof(x) == 2: result = cast[T](swapEndian_nim(x.toUint16)) # no builtin bswap16 for ICC
      elif sizeof(x) == 4: result = cast[T](builtin_bswap32(cast[cint](x.toUint32)))
      elif arch64:         result = cast[T](builtin_bswap64(x.int64))
      else:                result = cast[T](gen_bswap64_impl(x.uint64, cint))
    else:
      when sizeof(x) == 2: result = cast[T](swapEndian_nim(x.toUint16))
      elif sizeof(x) == 4: result = cast[T](swapEndian_nim(x.toUint32))
      else:                result = cast[T](swapEndian_nim(x.uint64))

template rotateLeft_impl[T](value: T; amount: int; shift: int): T =
  let amnt = amount and shift
  (value shl amnt) or (value shr ( (-amnt) and shift))

template rotateRight_impl[T](value: T; amount: int; shift: int): T =
  let amnt = amount and shift
  (value shr amnt) or (value shl ( (-amnt) and shift))

proc rotateLeftBits*[T: SomeInteger](value: T;
           amount: Natural): T {.inline, noSideEffect.} =
  ## Left-rotate bits in an integer by ``amount``.
  # using this form instead of the one below should handle any value
  # out of range as well as negative values.
  # result = (value shl amount) or (value shr (8 - amount))
  # taken from: https://en.wikipedia.org/wiki/Circular_shift#Implementing_circular_shifts
  when sizeof(value) == 1: cast[T](rotateLeft_impl(cast[uint8] (value), amount, 7))
  elif sizeof(value) == 2: cast[T](rotateLeft_impl(cast[uint16](value), amount, 15))
  elif sizeof(value) == 4: cast[T](rotateLeft_impl(cast[uint32](value), amount, 31))
  else:                    cast[T](rotateLeft_impl(cast[uint64](value), amount, 63))

proc rotateRightBits*[T](value: T;
            amount: Natural): T {.inline, noSideEffect.} =
  ## Right-rotate bits in an integer by ``amount``.
  when sizeof(value) == 1: cast[T](rotateRight_impl(cast[uint8](value), amount, 7))
  elif sizeof(value) == 2: cast[T](rotateRight_impl(cast[uint16](value), amount, 15))
  elif sizeof(value) == 4: cast[T](rotateRight_impl(cast[uint32](value), amount, 31))
  else:                    cast[T](rotateRight_impl(cast[uint64](value), amount, 63))

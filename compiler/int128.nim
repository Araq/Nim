## This module is for compiler internal use only. For reliable error
## messages and range checks, the compiler needs a data type that can
## hold all from `low(BiggestInt)` to `high(BiggestUInt)`, This
## type is for that purpose.

from std/math import trunc

when defined(nimPreviewSlimSystem):
  import std/assertions

type
  Int128* = object
    udata: array[4, uint32]

template sdata(arg: Int128, idx: int): int32 =
  # udata and sdata was supposed to be in a union, but unions are
  # handled incorrectly in the VM.
  cast[ptr int32](arg.udata[idx].unsafeAddr)[]

# encoding least significant int first (like LittleEndian)

const
  Zero* = Int128(udata: [0'u32, 0, 0, 0])
  One* = Int128(udata: [1'u32, 0, 0, 0])
  Ten* = Int128(udata: [10'u32, 0, 0, 0])
  Min = Int128(udata: [0'u32, 0, 0, 0x80000000'u32])
  Max = Int128(udata: [high(uint32), high(uint32), high(uint32), uint32(high(int32))])
  NegOne* = Int128(udata: [0xffffffff'u32, 0xffffffff'u32, 0xffffffff'u32, 0xffffffff'u32])

template low*(t: typedesc[Int128]): Int128 = Min
template high*(t: typedesc[Int128]): Int128 = Max

proc `$`*(a: Int128): string

proc toInt128*[T: SomeInteger | bool](arg: T): Int128 =
  {.noSideEffect.}:
    result = Zero
    when T is bool: result.sdata(0) = int32(arg)
    elif T is SomeUnsignedInt:
      when sizeof(arg) <= 4:
        result.udata[0] = uint32(arg)
      else:
        result.udata[0] = uint32(arg and T(0xffffffff))
        result.udata[1] = uint32(arg shr 32)
    elif sizeof(arg) <= 4:
      result.sdata(0) = int32(arg)
      if arg < 0: # sign extend
        result.sdata(1) = -1
        result.sdata(2) = -1
        result.sdata(3) = -1
    else:
      let tmp = int64(arg)
      result.udata[0] = uint32(tmp and 0xffffffff)
      result.sdata(1) = int32(tmp shr 32)
      if arg < 0: # sign extend
        result.sdata(2) = -1
        result.sdata(3) = -1

template isNegative(arg: Int128): bool =
  arg.sdata(3) < 0

proc bitconcat(a, b: uint32): uint64 =
  (uint64(a) shl 32) or uint64(b)

proc toInt64*(arg: Int128): int64 =
  if isNegative(arg):
    assert(arg.sdata(3) == -1, "out of range")
    assert(arg.sdata(2) == -1, "out of range")
  else:
    assert(arg.sdata(3) == 0, "out of range")
    assert(arg.sdata(2) == 0, "out of range")

  cast[int64](bitconcat(arg.udata[1], arg.udata[0]))

proc toInt64Checked*(arg: Int128; onError: int64): int64 =
  if isNegative(arg):
    if arg.sdata(3) != -1 or arg.sdata(2) != -1:
      return onError
  else:
    if arg.sdata(3) != 0 or arg.sdata(2) != 0:
      return onError
  return cast[int64](bitconcat(arg.udata[1], arg.udata[0]))

proc toInt32*(arg: Int128): int32 =
  if isNegative(arg):
    assert(arg.sdata(3) == -1, "out of range")
    assert(arg.sdata(2) == -1, "out of range")
    assert(arg.sdata(1) == -1, "out of range")
  else:
    assert(arg.sdata(3) == 0, "out of range")
    assert(arg.sdata(2) == 0, "out of range")
    assert(arg.sdata(1) == 0, "out of range")

  arg.sdata(0)

proc toInt16*(arg: Int128): int16 =
  if isNegative(arg):
    assert(arg.sdata(3) == -1, "out of range")
    assert(arg.sdata(2) == -1, "out of range")
    assert(arg.sdata(1) == -1, "out of range")
  else:
    assert(arg.sdata(3) == 0, "out of range")
    assert(arg.sdata(2) == 0, "out of range")
    assert(arg.sdata(1) == 0, "out of range")

  int16(arg.sdata(0))

proc toInt8*(arg: Int128): int8 =
  if isNegative(arg):
    assert(arg.sdata(3) == -1, "out of range")
    assert(arg.sdata(2) == -1, "out of range")
    assert(arg.sdata(1) == -1, "out of range")
  else:
    assert(arg.sdata(3) == 0, "out of range")
    assert(arg.sdata(2) == 0, "out of range")
    assert(arg.sdata(1) == 0, "out of range")

  int8(arg.sdata(0))

proc toInt*(arg: Int128): int =
  when sizeof(int) == 4:
    cast[int](toInt32(arg))
  else:
    cast[int](toInt64(arg))

proc toUInt64*(arg: Int128): uint64 =
  assert(arg.udata[3] == 0)
  assert(arg.udata[2] == 0)
  bitconcat(arg.udata[1], arg.udata[0])

proc toUInt32*(arg: Int128): uint32 =
  assert(arg.udata[3] == 0)
  assert(arg.udata[2] == 0)
  assert(arg.udata[1] == 0)
  arg.udata[0]

proc toUInt16*(arg: Int128): uint16 =
  assert(arg.udata[3] == 0)
  assert(arg.udata[2] == 0)
  assert(arg.udata[1] == 0)
  uint16(arg.udata[0])

proc toUInt8*(arg: Int128): uint8 =
  assert(arg.udata[3] == 0)
  assert(arg.udata[2] == 0)
  assert(arg.udata[1] == 0)
  uint8(arg.udata[0])

proc toUInt*(arg: Int128): uint =
  when sizeof(int) == 4:
    cast[uint](toInt32(arg))
  else:
    cast[uint](toInt64(arg))

proc castToInt64*(arg: Int128): int64 =
  ## Conversion to int64 without range check.
  cast[int64](bitconcat(arg.udata[1], arg.udata[0]))

proc castToUInt64*(arg: Int128): uint64 =
  ## Conversion to uint64 without range check.
  cast[uint64](bitconcat(arg.udata[1], arg.udata[0]))

proc addToHex(result: var string; arg: uint32) =
  for i in 0..<8:
    let idx = (arg shr ((7-i) * 4)) and 0xf
    result.add "0123456789abcdef"[idx]

proc addToHex*(result: var string; arg: Int128) =
  var i = 3
  while i >= 0:
    result.addToHex(arg.udata[i])
    i -= 1

proc toHex*(arg: Int128): string =
  result = ""
  result.addToHex(arg)

proc inc*(a: var Int128, y: uint32 = 1) =
  a.udata[0] += y
  if unlikely(a.udata[0] < y):
    a.udata[1].inc
    if unlikely(a.udata[1] == 0):
      a.udata[2].inc
      if unlikely(a.udata[2] == 0):
        a.udata[3].inc
        doAssert(a.sdata(3) != low(int32), "overflow")

proc cmp*(a, b: Int128): int =
  let tmp1 = cmp(a.sdata(3), b.sdata(3))
  if tmp1 != 0: return tmp1
  let tmp2 = cmp(a.udata[2], b.udata[2])
  if tmp2 != 0: return tmp2
  let tmp3 = cmp(a.udata[1], b.udata[1])
  if tmp3 != 0: return tmp3
  let tmp4 = cmp(a.udata[0], b.udata[0])
  return tmp4

proc `<`*(a, b: Int128): bool =
  cmp(a, b) < 0

proc `<=`*(a, b: Int128): bool =
  cmp(a, b) <= 0

proc `==`*(a, b: Int128): bool =
  if a.udata[0] != b.udata[0]: return false
  if a.udata[1] != b.udata[1]: return false
  if a.udata[2] != b.udata[2]: return false
  if a.udata[3] != b.udata[3]: return false
  return true

proc bitnot*(a: Int128): Int128 =
  result = Zero
  result.udata[0] = not a.udata[0]
  result.udata[1] = not a.udata[1]
  result.udata[2] = not a.udata[2]
  result.udata[3] = not a.udata[3]

proc bitand*(a, b: Int128): Int128 =
  result = Zero
  result.udata[0] = a.udata[0] and b.udata[0]
  result.udata[1] = a.udata[1] and b.udata[1]
  result.udata[2] = a.udata[2] and b.udata[2]
  result.udata[3] = a.udata[3] and b.udata[3]

proc bitor*(a, b: Int128): Int128 =
  result = Zero
  result.udata[0] = a.udata[0] or b.udata[0]
  result.udata[1] = a.udata[1] or b.udata[1]
  result.udata[2] = a.udata[2] or b.udata[2]
  result.udata[3] = a.udata[3] or b.udata[3]

proc bitxor*(a, b: Int128): Int128 =
  result = Zero
  result.udata[0] = a.udata[0] xor b.udata[0]
  result.udata[1] = a.udata[1] xor b.udata[1]
  result.udata[2] = a.udata[2] xor b.udata[2]
  result.udata[3] = a.udata[3] xor b.udata[3]

proc `shr`*(a: Int128, b: int): Int128 =
  result = Zero
  let b = b and 127
  if b < 32:
    result.sdata(3) = a.sdata(3) shr b
    result.udata[2] = cast[uint32](bitconcat(a.udata[3], a.udata[2]) shr b)
    result.udata[1] = cast[uint32](bitconcat(a.udata[2], a.udata[1]) shr b)
    result.udata[0] = cast[uint32](bitconcat(a.udata[1], a.udata[0]) shr b)
  elif b < 64:
    if isNegative(a):
      result.sdata(3) = -1
    result.sdata(2) = a.sdata(3) shr (b and 31)
    result.udata[1] = cast[uint32](bitconcat(a.udata[3], a.udata[2]) shr (b and 31))
    result.udata[0] = cast[uint32](bitconcat(a.udata[2], a.udata[1]) shr (b and 31))
  elif b < 96:
    if isNegative(a):
      result.sdata(3) = -1
      result.sdata(2) = -1
    result.sdata(1) = a.sdata(3) shr (b and 31)
    result.udata[0] = cast[uint32](bitconcat(a.udata[3], a.udata[2]) shr (b and 31))
  else: # b < 128
    if isNegative(a):
      result.sdata(3) = -1
      result.sdata(2) = -1
      result.sdata(1) = -1
    result.sdata(0) = a.sdata(3) shr (b and 31)

proc `shl`*(a: Int128, b: int): Int128 =
  result = Zero
  let b = b and 127
  if b < 32:
    result.udata[0] = a.udata[0] shl b
    result.udata[1] = cast[uint32]((bitconcat(a.udata[1], a.udata[0]) shl b) shr 32)
    result.udata[2] = cast[uint32]((bitconcat(a.udata[2], a.udata[1]) shl b) shr 32)
    result.udata[3] = cast[uint32]((bitconcat(a.udata[3], a.udata[2]) shl b) shr 32)
  elif b < 64:
    result.udata[0] = 0
    result.udata[1] = a.udata[0] shl (b and 31)
    result.udata[2] = cast[uint32]((bitconcat(a.udata[1], a.udata[0]) shl (b and 31)) shr 32)
    result.udata[3] = cast[uint32]((bitconcat(a.udata[2], a.udata[1]) shl (b and 31)) shr 32)
  elif b < 96:
    result.udata[0] = 0
    result.udata[1] = 0
    result.udata[2] = a.udata[0] shl (b and 31)
    result.udata[3] = cast[uint32]((bitconcat(a.udata[1], a.udata[0]) shl (b and 31)) shr 32)
  else:
    result.udata[0] = 0
    result.udata[1] = 0
    result.udata[2] = 0
    result.udata[3] = a.udata[0] shl (b and 31)

proc `+`*(a, b: Int128): Int128 =
  result = Zero
  let tmp0 = uint64(a.udata[0]) + uint64(b.udata[0])
  result.udata[0] = cast[uint32](tmp0)
  let tmp1 = uint64(a.udata[1]) + uint64(b.udata[1]) + (tmp0 shr 32)
  result.udata[1] = cast[uint32](tmp1)
  let tmp2 = uint64(a.udata[2]) + uint64(b.udata[2]) + (tmp1 shr 32)
  result.udata[2] = cast[uint32](tmp2)
  let tmp3 = uint64(a.udata[3]) + uint64(b.udata[3]) + (tmp2 shr 32)
  result.udata[3] = cast[uint32](tmp3)

proc `+=`*(a: var Int128, b: Int128) =
  a = a + b

proc `-`*(a: Int128): Int128 =
  result = bitnot(a)
  result.inc

proc `-`*(a, b: Int128): Int128 =
  a + (-b)

proc `-=`*(a: var Int128, b: Int128) =
  a = a - b

proc abs*(a: Int128): Int128 =
  if isNegative(a):
    -a
  else:
    a

proc abs(a: int32): int =
  if a < 0: -a else: a

proc `*`(a: Int128, b: uint32): Int128 =
  result = Zero
  let tmp0 = uint64(a.udata[0]) * uint64(b)
  let tmp1 = uint64(a.udata[1]) * uint64(b)
  let tmp2 = uint64(a.udata[2]) * uint64(b)
  let tmp3 = uint64(a.udata[3]) * uint64(b)

  if unlikely(tmp3 > uint64(high(int32))):
    assert(false, "overflow")

  result.udata[0] = cast[uint32](tmp0)
  result.udata[1] = cast[uint32](tmp1) + cast[uint32](tmp0 shr 32)
  result.udata[2] = cast[uint32](tmp2) + cast[uint32](tmp1 shr 32)
  result.udata[3] = cast[uint32](tmp3) + cast[uint32](tmp2 shr 32)

proc `*`*(a: Int128, b: int32): Int128 =
  result = a * cast[uint32](abs(b))
  if b < 0:
    result = -result

proc `*=`(a: var Int128, b: int32) =
  a = a * b

proc makeInt128(high, low: uint64): Int128 =
  result = Zero
  result.udata[0] = cast[uint32](low)
  result.udata[1] = cast[uint32](low shr 32)
  result.udata[2] = cast[uint32](high)
  result.udata[3] = cast[uint32](high shr 32)

proc high64(a: Int128): uint64 =
  bitconcat(a.udata[3], a.udata[2])

proc low64(a: Int128): uint64 =
  bitconcat(a.udata[1], a.udata[0])

proc `*`*(lhs, rhs: Int128): Int128 =
  let a32 = uint64(lhs.udata[1])
  let a00 = uint64(lhs.udata[0])
  let b32 = uint64(rhs.udata[1])
  let b00 = uint64(rhs.udata[0])
  result = makeInt128(high64(lhs) * low64(rhs) + low64(lhs) * high64(rhs) + a32 * b32, a00 * b00)
  result += toInt128(a32 * b00) shl 32
  result += toInt128(a00 * b32) shl 32

proc `*=`*(a: var Int128, b: Int128) =
  a = a * b

import std/bitops

proc fastLog2*(a: Int128): int =
  result = 0
  if a.udata[3] != 0:
    return 96 + fastLog2(a.udata[3])
  if a.udata[2] != 0:
    return 64 + fastLog2(a.udata[2])
  if a.udata[1] != 0:
    return 32 + fastLog2(a.udata[1])
  if a.udata[0] != 0:
    return fastLog2(a.udata[0])

proc divMod*(dividend, divisor: Int128): tuple[quotient, remainder: Int128] =
  assert(divisor != Zero)
  result = (Zero, Zero)

  let isNegativeA = isNegative(dividend)
  let isNegativeB = isNegative(divisor)

  var dividend = abs(dividend)
  let divisor = abs(divisor)

  if divisor > dividend:
    result.quotient = Zero
    if isNegativeA:
      result.remainder = -dividend
    else:
      result.remainder = dividend
    return

  if divisor == dividend:
    if isNegativeA xor isNegativeB:
      result.quotient = NegOne
    else:
      result.quotient = One
    result.remainder = Zero
    return

  var denominator = divisor
  var quotient = Zero

  # Left aligns the MSB of the denominator and the dividend.
  let shift = fastLog2(dividend) - fastLog2(denominator)
  denominator = denominator shl shift

  # Uses shift-subtract algorithm to divide dividend by denominator. The
  # remainder will be left in dividend.
  for i in 0..shift:
    quotient = quotient shl 1
    if dividend >= denominator:
      dividend -= denominator
      quotient = bitor(quotient, One)

    denominator = denominator shr 1

  if isNegativeA xor isNegativeB:
    result.quotient = -quotient
  else:
    result.quotient = quotient
  if isNegativeA:
    result.remainder = -dividend
  else:
    result.remainder = dividend

proc `div`*(a, b: Int128): Int128 =
  let (a, _) = divMod(a, b)
  return a

proc `mod`*(a, b: Int128): Int128 =
  let (_, b) = divMod(a, b)
  return b

proc addInt128*(result: var string; value: Int128) =
  let initialSize = result.len
  if value == Zero:
    result.add '0'
  elif value == low(Int128):
    result.add "-170141183460469231731687303715884105728"
  else:
    let isNegative = isNegative(value)
    var value = abs(value)
    while value > Zero:
      let (quot, rem) = divMod(value, Ten)
      result.add "0123456789"[rem.toInt64]
      value = quot
    if isNegative:
      result.add '-'

    var i = initialSize
    var j = high(result)
    while i < j:
      swap(result[i], result[j])
      i += 1
      j -= 1

proc `$`*(a: Int128): string =
  # "-170141183460469231731687303715884105728".len == 41
  result = newStringOfCap(41)
  result.addInt128(a)

proc parseDecimalInt128*(arg: string, pos: int = 0): Int128 =
  assert(pos < arg.len)
  assert(arg[pos] in {'-', '0'..'9'})

  var isNegative = false
  var pos = pos
  if arg[pos] == '-':
    isNegative = true
    pos += 1

  result = Zero
  while pos < arg.len and arg[pos] in '0'..'9':
    result = result * Ten
    result.inc(uint32(arg[pos]) - uint32('0'))
    pos += 1

  if isNegative:
    result = -result

# fluff

proc `<`*(a: Int128, b: BiggestInt): bool =
  cmp(a, toInt128(b)) < 0

proc `<`*(a: BiggestInt, b: Int128): bool =
  cmp(toInt128(a), b) < 0

proc `<=`*(a: Int128, b: BiggestInt): bool =
  cmp(a, toInt128(b)) <= 0

proc `<=`*(a: BiggestInt, b: Int128): bool =
  cmp(toInt128(a), b) <= 0

proc `==`*(a: Int128, b: BiggestInt): bool =
  a == toInt128(b)

proc `==`*(a: BiggestInt, b: Int128): bool =
  toInt128(a) == b

proc `-`*(a: BiggestInt, b: Int128): Int128 =
  toInt128(a) - b

proc `-`*(a: Int128, b: BiggestInt): Int128 =
  a - toInt128(b)

proc `+`*(a: BiggestInt, b: Int128): Int128 =
  toInt128(a) + b

proc `+`*(a: Int128, b: BiggestInt): Int128 =
  a + toInt128(b)

proc toFloat64*(arg: Int128): float64 =
  let isNegative = isNegative(arg)
  let arg = abs(arg)

  let a = float64(bitconcat(arg.udata[1], arg.udata[0]))
  let b = float64(bitconcat(arg.udata[3], arg.udata[2]))

  result = a + 18446744073709551616'f64 * b # a + 2^64 * b
  if isNegative:
    result = -result

proc ldexp(x: float64, exp: cint): float64 {.importc: "ldexp", header: "<math.h>".}

template bitor(a, b, c: Int128): Int128 = bitor(bitor(a, b), c)

proc toInt128*(arg: float64): Int128 =
  let isNegative = arg < 0
  let v0 = ldexp(abs(arg), -100)
  let w0 = uint64(trunc(v0))
  let v1 = ldexp(v0 - float64(w0), 50)
  let w1 = uint64(trunc(v1))
  let v2 = ldexp(v1 - float64(w1), 50)
  let w2 = uint64(trunc(v2))

  let res = bitor(toInt128(w0) shl 100, toInt128(w1) shl 50, toInt128(w2))
  if isNegative:
    return -res
  else:
    return res

proc maskUInt64*(arg: Int128): Int128 {.noinit, inline.} =
  result = Zero
  result.udata[0] = arg.udata[0]
  result.udata[1] = arg.udata[1]
  result.udata[2] = 0
  result.udata[3] = 0

proc maskUInt32*(arg: Int128): Int128 {.noinit, inline.} =
  result = Zero
  result.udata[0] = arg.udata[0]
  result.udata[1] = 0
  result.udata[2] = 0
  result.udata[3] = 0

proc maskUInt16*(arg: Int128): Int128 {.noinit, inline.} =
  result = Zero
  result.udata[0] = arg.udata[0] and 0xffff
  result.udata[1] = 0
  result.udata[2] = 0
  result.udata[3] = 0

proc maskUInt8*(arg: Int128): Int128 {.noinit, inline.} =
  result = Zero
  result.udata[0] = arg.udata[0] and 0xff
  result.udata[1] = 0
  result.udata[2] = 0
  result.udata[3] = 0

proc maskBytes*(arg: Int128, numbytes: int): Int128 {.noinit.} =
  case numbytes
  of 1:
    return maskUInt8(arg)
  of 2:
    return maskUInt16(arg)
  of 4:
    return maskUInt32(arg)
  of 8:
    return maskUInt64(arg)
  else:
    raiseAssert "masking only implemented for 1, 2, 4 and 8 bytes"

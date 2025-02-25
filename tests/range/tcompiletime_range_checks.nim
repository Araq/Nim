discard """
  cmd: "nim check --hint:Processing:off --hint:Conf:off $file"
  errormsg: "18446744073709551615 can't be converted to int8"
  nimout: '''
tcompiletime_range_checks.nim(36, 21) Error: 2147483648 can't be converted to int32
tcompiletime_range_checks.nim(38, 34) Error: 255 can't be converted to FullNegativeRange
tcompiletime_range_checks.nim(39, 34) Error: 18446744073709551615 can't be converted to HalfNegativeRange
tcompiletime_range_checks.nim(40, 34) Error: 300 can't be converted to FullPositiveRange
tcompiletime_range_checks.nim(41, 30) Error: 101 can't be converted to UnsignedRange
tcompiletime_range_checks.nim(42, 32) Error: -9223372036854775808 can't be converted to SemiOutOfBounds
tcompiletime_range_checks.nim(44, 22) Error: nan can't be converted to int32
tcompiletime_range_checks.nim(46, 23) Error: 1e+100 can't be converted to uint64
tcompiletime_range_checks.nim(49, 22) Error: 18446744073709551615 can't be converted to int64
tcompiletime_range_checks.nim(50, 22) Error: 18446744073709551615 can't be converted to int32
tcompiletime_range_checks.nim(51, 22) Error: 18446744073709551615 can't be converted to int16
tcompiletime_range_checks.nim(52, 21) Error: 18446744073709551615 can't be converted to int8
  '''
"""

type
  UnsignedRange* = range[0'u64 .. 100'u64]
  SemiOutOfBounds* = range[0x7ffffffffffffe00'u64 .. 0x8000000000000100'u64]
  FullOutOfBounds* = range[0x8000000000000000'u64 .. 0x8000000000000200'u64]

  FullNegativeRange* = range[-200 .. -100]
  HalfNegativeRange* = range[-50 .. 50]
  FullPositiveRange* = range[100 .. 200]

let acceptA* = int32(0x7fffffff'i64)
let acceptB* = (uint64(0'i64))
let acceptD* = (HalfNegativeRange(25'u64))
let acceptE* = (UnsignedRange(50'u64))
let acceptF* = (SemiOutOfBounds(0x7ffffffffffffe00'i64))
let acceptH* = (SemiOutOfBounds(0x8000000000000000'u64))

let rejectA* = int32(0x80000000'i64)
let rejectB* = (uint64(-1'i64))
let rejectC* = (FullNegativeRange(0xff'u32))
let rejectD* = (HalfNegativeRange(0xffffffffffffffff'u64)) # internal `intVal` is `-1` which would be in range.
let rejectE* = (FullPositiveRange(300'u64))
let rejectF* = (UnsignedRange(101'u64))
let rejectG* = (SemiOutOfBounds(0x8000000000000000'i64))  #

let rejectH* = (int32(NaN))
let rejectI* = (int64(1e100))
let rejectJ* = (uint64(1e100))

# removed cross checks from tarithm.nim
let rejectK* = (int64(0xFFFFFFFFFFFFFFFF'u64))
let rejectL* = (int32(0xFFFFFFFFFFFFFFFF'u64))
let rejectM* = (int16(0xFFFFFFFFFFFFFFFF'u64))
let rejectN* = (int8(0xFFFFFFFFFFFFFFFF'u64))

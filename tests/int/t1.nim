discard """
  targets: "c cpp"
"""

doAssert typeOf(1.int64 + 1.int) is int64
doAssert typeOf(1.uint64 + 1.uint) is uint64
doAssert int64 is SomeNumber
doAssert int64 is (SomeNumber and not(uint32|uint64|uint|int))
doAssert int64 is (not(uint32|uint64|uint|int))
doAssert int isnot int64
doAssert int64 isnot int
var myInt16 = 5i16
var myInt: int
doAssert typeOf(myInt16 + 34) is int16    # of type `int16`
doAssert typeOf(myInt16 + myInt) is int   # of type `int`
doAssert typeOf(myInt16 + 2i32) is int32  # of type `int32`
doAssert int32 isnot int64
doAssert int32 isnot int

block: # bug #23947
  template foo =
    let test_u64 : uint64 =   0xFF07.uint64
    let test_u8  : uint8  = test_u64.uint8
        # Error: illegal conversion from '65287' to '[0..255]'
    doAssert test_u8 == 7

  static: foo()
  foo()

block:
  # bug #22085
  const
    x = uint32(uint64.high) # vm error
    u = uint64.high
    v = uint32(u) # vm error

  let
    z = uint64.high
    y = uint32(z)  # runtime ok

  let
    w = uint32(uint64.high)  # semfold error

  doAssert x == w
  doAssert v == y

  # bug #14522
  doAssert 0xFF000000_00000000.uint64 == 18374686479671623680'u64

block: # bug #23954
  let testRT_u8 : uint8 = 0x107.uint8
  doAssert testRT_u8 == 7
  const testCT_u8 : uint8 = 0x107.uint8
  doAssert testCT_u8 == 7

block: # issue #24104
  type P = distinct uint  # uint, uint8, uint16, uint32, uint64 
  let v = 0.P
  case v
  of 0.P: discard
  else:   discard

proc succ*[T, V: Ordinal](x: T, y: V = 1): T {.magic: "Succ", noSideEffect.} =
  ## Returns the `y`-th successor (default: 1) of the value `x`.
  ##
  ## If such a value does not exist, `OverflowDefect` is raised
  ## or a compile time error occurs.
  runnableExamples:
    assert succ(5) == 6
    assert succ(5, 3) == 8

proc pred*[T, V: Ordinal](x: T, y: V = 1): T {.magic: "Pred", noSideEffect.} =
  ## Returns the `y`-th predecessor (default: 1) of the value `x`.
  ##
  ## If such a value does not exist, `OverflowDefect` is raised
  ## or a compile time error occurs.
  runnableExamples:
    assert pred(5) == 4
    assert pred(5, 3) == 2

proc inc*[T, V: Ordinal](x: var T, y: V = 1) {.magic: "Inc", noSideEffect.} =
  ## Increments the ordinal `x` by `y`.
  ##
  ## If such a value does not exist, `OverflowDefect` is raised or a compile
  ## time error occurs. This is a short notation for: `x = succ(x, y)`.
  runnableExamples:
    var i = 2
    inc(i)
    assert i == 3
    inc(i, 3)
    assert i == 6

proc dec*[T, V: Ordinal](x: var T, y: V = 1) {.magic: "Dec", noSideEffect.} =
  ## Decrements the ordinal `x` by `y`.
  ##
  ## If such a value does not exist, `OverflowDefect` is raised or a compile
  ## time error occurs. This is a short notation for: `x = pred(x, y)`.
  runnableExamples:
    var i = 2
    dec(i)
    assert i == 1
    dec(i, 3)
    assert i == -2



# --------------------------------------------------------------------------
# built-in operators

# integer calculations:
proc `+`*(x: int): int {.magic: "UnaryPlusI", noSideEffect.}
  ## Unary `+` operator for an integer. Has no effect.
proc `+`*(x: int8): int8 {.magic: "UnaryPlusI", noSideEffect.}
proc `+`*(x: int16): int16 {.magic: "UnaryPlusI", noSideEffect.}
proc `+`*(x: int32): int32 {.magic: "UnaryPlusI", noSideEffect.}
proc `+`*(x: int64): int64 {.magic: "UnaryPlusI", noSideEffect.}

proc `-`*(x: int): int {.magic: "UnaryMinusI", noSideEffect.}
  ## Unary `-` operator for an integer. Negates `x`.
proc `-`*(x: int8): int8 {.magic: "UnaryMinusI", noSideEffect.}
proc `-`*(x: int16): int16 {.magic: "UnaryMinusI", noSideEffect.}
proc `-`*(x: int32): int32 {.magic: "UnaryMinusI", noSideEffect.}
proc `-`*(x: int64): int64 {.magic: "UnaryMinusI64", noSideEffect.}

proc `not`*(x: int): int {.magic: "BitnotI", noSideEffect.} =
  ## Computes the `bitwise complement` of the integer `x`.
  runnableExamples:
    assert not 0'u8 == 255
    assert not 0'i8 == -1
    assert not 1000'u16 == 64535
    assert not 1000'i16 == -1001
proc `not`*(x: int8): int8 {.magic: "BitnotI", noSideEffect.}
proc `not`*(x: int16): int16 {.magic: "BitnotI", noSideEffect.}
proc `not`*(x: int32): int32 {.magic: "BitnotI", noSideEffect.}
proc `not`*(x: int64): int64 {.magic: "BitnotI", noSideEffect.}

proc `+`*(x, y: int): int {.magic: "AddI", noSideEffect.}
  ## Binary `+` operator for an integer.
proc `+`*(x, y: int8): int8 {.magic: "AddI", noSideEffect.}
proc `+`*(x, y: int16): int16 {.magic: "AddI", noSideEffect.}
proc `+`*(x, y: int32): int32 {.magic: "AddI", noSideEffect.}
proc `+`*(x, y: int64): int64 {.magic: "AddI", noSideEffect.}

proc `-`*(x, y: int): int {.magic: "SubI", noSideEffect.}
  ## Binary `-` operator for an integer.
proc `-`*(x, y: int8): int8 {.magic: "SubI", noSideEffect.}
proc `-`*(x, y: int16): int16 {.magic: "SubI", noSideEffect.}
proc `-`*(x, y: int32): int32 {.magic: "SubI", noSideEffect.}
proc `-`*(x, y: int64): int64 {.magic: "SubI", noSideEffect.}

proc `*`*(x, y: int): int {.magic: "MulI", noSideEffect.}
  ## Binary `*` operator for an integer.
proc `*`*(x, y: int8): int8 {.magic: "MulI", noSideEffect.}
proc `*`*(x, y: int16): int16 {.magic: "MulI", noSideEffect.}
proc `*`*(x, y: int32): int32 {.magic: "MulI", noSideEffect.}
proc `*`*(x, y: int64): int64 {.magic: "MulI", noSideEffect.}

proc `div`*(x, y: int): int {.magic: "DivI", noSideEffect.} =
  ## Computes the integer division.
  ##
  ## This is roughly the same as `math.trunc(x/y).int`.
  runnableExamples:
    assert (1 div 2) == 0
    assert (2 div 2) == 1
    assert (3 div 2) == 1
    assert (7 div 3) == 2
    assert (-7 div 3) == -2
    assert (7 div -3) == -2
    assert (-7 div -3) == 2
proc `div`*(x, y: int8): int8 {.magic: "DivI", noSideEffect.}
proc `div`*(x, y: int16): int16 {.magic: "DivI", noSideEffect.}
proc `div`*(x, y: int32): int32 {.magic: "DivI", noSideEffect.}
proc `div`*(x, y: int64): int64 {.magic: "DivI", noSideEffect.}

proc `mod`*(x, y: int): int {.magic: "ModI", noSideEffect.} =
  ## Computes the integer modulo operation (remainder).
  ##
  ## This is the same as `x - (x div y) * y`.
  runnableExamples:
    assert (7 mod 5) == 2
    assert (-7 mod 5) == -2
    assert (7 mod -5) == 2
    assert (-7 mod -5) == -2
proc `mod`*(x, y: int8): int8 {.magic: "ModI", noSideEffect.}
proc `mod`*(x, y: int16): int16 {.magic: "ModI", noSideEffect.}
proc `mod`*(x, y: int32): int32 {.magic: "ModI", noSideEffect.}
proc `mod`*(x, y: int64): int64 {.magic: "ModI", noSideEffect.}

when defined(nimOldShiftRight):
  const shrDepMessage = "`shr` will become sign preserving."
  proc `shr`*(x: int, y: SomeInteger): int {.magic: "ShrI", noSideEffect, deprecated: shrDepMessage.}
  proc `shr`*(x: int8, y: SomeInteger): int8 {.magic: "ShrI", noSideEffect, deprecated: shrDepMessage.}
  proc `shr`*(x: int16, y: SomeInteger): int16 {.magic: "ShrI", noSideEffect, deprecated: shrDepMessage.}
  proc `shr`*(x: int32, y: SomeInteger): int32 {.magic: "ShrI", noSideEffect, deprecated: shrDepMessage.}
  proc `shr`*(x: int64, y: SomeInteger): int64 {.magic: "ShrI", noSideEffect, deprecated: shrDepMessage.}
else:
  proc `shr`*(x: int, y: SomeInteger): int {.magic: "AshrI", noSideEffect.} =
    ## Computes the `shift right` operation of `x` and `y`, filling
    ## vacant bit positions with the sign bit.
    ##
    ## **Note**: `Operator precedence <manual.html#syntax-precedence>`_
    ## is different than in *C*.
    ##
    ## See also:
    ## * `ashr func<#ashr,int,SomeInteger>`_ for arithmetic shift right
    runnableExamples:
      assert 0b0001_0000'i8 shr 2 == 0b0000_0100'i8
      assert 0b0000_0001'i8 shr 1 == 0b0000_0000'i8
      assert 0b1000_0000'i8 shr 4 == 0b1111_1000'i8
      assert -1 shr 5 == -1
      assert 1 shr 5 == 0
      assert 16 shr 2 == 4
      assert -16 shr 2 == -4
  proc `shr`*(x: int8, y: SomeInteger): int8 {.magic: "AshrI", noSideEffect.}
  proc `shr`*(x: int16, y: SomeInteger): int16 {.magic: "AshrI", noSideEffect.}
  proc `shr`*(x: int32, y: SomeInteger): int32 {.magic: "AshrI", noSideEffect.}
  proc `shr`*(x: int64, y: SomeInteger): int64 {.magic: "AshrI", noSideEffect.}


proc `shl`*(x: int, y: SomeInteger): int {.magic: "ShlI", noSideEffect.} =
  ## Computes the `shift left` operation of `x` and `y`.
  ##
  ## **Note**: `Operator precedence <manual.html#syntax-precedence>`_
  ## is different than in *C*.
  runnableExamples:
    assert 1'i32 shl 4 == 0x0000_0010
    assert 1'i64 shl 4 == 0x0000_0000_0000_0010
proc `shl`*(x: int8, y: SomeInteger): int8 {.magic: "ShlI", noSideEffect.}
proc `shl`*(x: int16, y: SomeInteger): int16 {.magic: "ShlI", noSideEffect.}
proc `shl`*(x: int32, y: SomeInteger): int32 {.magic: "ShlI", noSideEffect.}
proc `shl`*(x: int64, y: SomeInteger): int64 {.magic: "ShlI", noSideEffect.}

proc ashr*(x: int, y: SomeInteger): int {.magic: "AshrI", noSideEffect.} =
  ## Shifts right by pushing copies of the leftmost bit in from the left,
  ## and let the rightmost bits fall off.
  ##
  ## Note that `ashr` is not an operator so use the normal function
  ## call syntax for it.
  ##
  ## See also:
  ## * `shr func<#shr,int,SomeInteger>`_
  runnableExamples:
    assert ashr(0b0001_0000'i8, 2) == 0b0000_0100'i8
    assert ashr(0b1000_0000'i8, 8) == 0b1111_1111'i8
    assert ashr(0b1000_0000'i8, 1) == 0b1100_0000'i8
proc ashr*(x: int8, y: SomeInteger): int8 {.magic: "AshrI", noSideEffect.}
proc ashr*(x: int16, y: SomeInteger): int16 {.magic: "AshrI", noSideEffect.}
proc ashr*(x: int32, y: SomeInteger): int32 {.magic: "AshrI", noSideEffect.}
proc ashr*(x: int64, y: SomeInteger): int64 {.magic: "AshrI", noSideEffect.}

proc `and`*(x, y: int): int {.magic: "BitandI", noSideEffect.} =
  ## Computes the `bitwise and` of numbers `x` and `y`.
  runnableExamples:
    assert (0b0011 and 0b0101) == 0b0001
    assert (0b0111 and 0b1100) == 0b0100
proc `and`*(x, y: int8): int8 {.magic: "BitandI", noSideEffect.}
proc `and`*(x, y: int16): int16 {.magic: "BitandI", noSideEffect.}
proc `and`*(x, y: int32): int32 {.magic: "BitandI", noSideEffect.}
proc `and`*(x, y: int64): int64 {.magic: "BitandI", noSideEffect.}

proc `or`*(x, y: int): int {.magic: "BitorI", noSideEffect.} =
  ## Computes the `bitwise or` of numbers `x` and `y`.
  runnableExamples:
    assert (0b0011 or 0b0101) == 0b0111
    assert (0b0111 or 0b1100) == 0b1111
proc `or`*(x, y: int8): int8 {.magic: "BitorI", noSideEffect.}
proc `or`*(x, y: int16): int16 {.magic: "BitorI", noSideEffect.}
proc `or`*(x, y: int32): int32 {.magic: "BitorI", noSideEffect.}
proc `or`*(x, y: int64): int64 {.magic: "BitorI", noSideEffect.}

proc `xor`*(x, y: int): int {.magic: "BitxorI", noSideEffect.} =
  ## Computes the `bitwise xor` of numbers `x` and `y`.
  runnableExamples:
    assert (0b0011 xor 0b0101) == 0b0110
    assert (0b0111 xor 0b1100) == 0b1011
proc `xor`*(x, y: int8): int8 {.magic: "BitxorI", noSideEffect.}
proc `xor`*(x, y: int16): int16 {.magic: "BitxorI", noSideEffect.}
proc `xor`*(x, y: int32): int32 {.magic: "BitxorI", noSideEffect.}
proc `xor`*(x, y: int64): int64 {.magic: "BitxorI", noSideEffect.}

# unsigned integer operations:
proc `not`*(x: uint): uint {.magic: "BitnotI", noSideEffect.}
  ## Computes the `bitwise complement` of the integer `x`.
proc `not`*(x: uint8): uint8 {.magic: "BitnotI", noSideEffect.}
proc `not`*(x: uint16): uint16 {.magic: "BitnotI", noSideEffect.}
proc `not`*(x: uint32): uint32 {.magic: "BitnotI", noSideEffect.}
proc `not`*(x: uint64): uint64 {.magic: "BitnotI", noSideEffect.}

proc `shr`*(x: uint, y: SomeInteger): uint {.magic: "ShrI", noSideEffect.}
  ## Computes the `shift right` operation of `x` and `y`.
proc `shr`*(x: uint8, y: SomeInteger): uint8 {.magic: "ShrI", noSideEffect.}
proc `shr`*(x: uint16, y: SomeInteger): uint16 {.magic: "ShrI", noSideEffect.}
proc `shr`*(x: uint32, y: SomeInteger): uint32 {.magic: "ShrI", noSideEffect.}
proc `shr`*(x: uint64, y: SomeInteger): uint64 {.magic: "ShrI", noSideEffect.}

proc `shl`*(x: uint, y: SomeInteger): uint {.magic: "ShlI", noSideEffect.}
  ## Computes the `shift left` operation of `x` and `y`.
proc `shl`*(x: uint8, y: SomeInteger): uint8 {.magic: "ShlI", noSideEffect.}
proc `shl`*(x: uint16, y: SomeInteger): uint16 {.magic: "ShlI", noSideEffect.}
proc `shl`*(x: uint32, y: SomeInteger): uint32 {.magic: "ShlI", noSideEffect.}
proc `shl`*(x: uint64, y: SomeInteger): uint64 {.magic: "ShlI", noSideEffect.}

proc `and`*(x, y: uint): uint {.magic: "BitandI", noSideEffect.}
  ## Computes the `bitwise and` of numbers `x` and `y`.
proc `and`*(x, y: uint8): uint8 {.magic: "BitandI", noSideEffect.}
proc `and`*(x, y: uint16): uint16 {.magic: "BitandI", noSideEffect.}
proc `and`*(x, y: uint32): uint32 {.magic: "BitandI", noSideEffect.}
proc `and`*(x, y: uint64): uint64 {.magic: "BitandI", noSideEffect.}

proc `or`*(x, y: uint): uint {.magic: "BitorI", noSideEffect.}
  ## Computes the `bitwise or` of numbers `x` and `y`.
proc `or`*(x, y: uint8): uint8 {.magic: "BitorI", noSideEffect.}
proc `or`*(x, y: uint16): uint16 {.magic: "BitorI", noSideEffect.}
proc `or`*(x, y: uint32): uint32 {.magic: "BitorI", noSideEffect.}
proc `or`*(x, y: uint64): uint64 {.magic: "BitorI", noSideEffect.}

proc `xor`*(x, y: uint): uint {.magic: "BitxorI", noSideEffect.}
  ## Computes the `bitwise xor` of numbers `x` and `y`.
proc `xor`*(x, y: uint8): uint8 {.magic: "BitxorI", noSideEffect.}
proc `xor`*(x, y: uint16): uint16 {.magic: "BitxorI", noSideEffect.}
proc `xor`*(x, y: uint32): uint32 {.magic: "BitxorI", noSideEffect.}
proc `xor`*(x, y: uint64): uint64 {.magic: "BitxorI", noSideEffect.}

proc `+`*(x, y: uint): uint {.magic: "AddU", noSideEffect.}
  ## Binary `+` operator for unsigned integers.
proc `+`*(x, y: uint8): uint8 {.magic: "AddU", noSideEffect.}
proc `+`*(x, y: uint16): uint16 {.magic: "AddU", noSideEffect.}
proc `+`*(x, y: uint32): uint32 {.magic: "AddU", noSideEffect.}
proc `+`*(x, y: uint64): uint64 {.magic: "AddU", noSideEffect.}

proc `-`*(x, y: uint): uint {.magic: "SubU", noSideEffect.}
  ## Binary `-` operator for unsigned integers.
proc `-`*(x, y: uint8): uint8 {.magic: "SubU", noSideEffect.}
proc `-`*(x, y: uint16): uint16 {.magic: "SubU", noSideEffect.}
proc `-`*(x, y: uint32): uint32 {.magic: "SubU", noSideEffect.}
proc `-`*(x, y: uint64): uint64 {.magic: "SubU", noSideEffect.}

proc `*`*(x, y: uint): uint {.magic: "MulU", noSideEffect.}
  ## Binary `*` operator for unsigned integers.
proc `*`*(x, y: uint8): uint8 {.magic: "MulU", noSideEffect.}
proc `*`*(x, y: uint16): uint16 {.magic: "MulU", noSideEffect.}
proc `*`*(x, y: uint32): uint32 {.magic: "MulU", noSideEffect.}
proc `*`*(x, y: uint64): uint64 {.magic: "MulU", noSideEffect.}

proc `div`*(x, y: uint): uint {.magic: "DivU", noSideEffect.}
  ## Computes the integer division for unsigned integers.
  ## This is roughly the same as `trunc(x/y)`.
proc `div`*(x, y: uint8): uint8 {.magic: "DivU", noSideEffect.}
proc `div`*(x, y: uint16): uint16 {.magic: "DivU", noSideEffect.}
proc `div`*(x, y: uint32): uint32 {.magic: "DivU", noSideEffect.}
proc `div`*(x, y: uint64): uint64 {.magic: "DivU", noSideEffect.}

proc `mod`*(x, y: uint): uint {.magic: "ModU", noSideEffect.}
  ## Computes the integer modulo operation (remainder) for unsigned integers.
  ## This is the same as `x - (x div y) * y`.
proc `mod`*(x, y: uint8): uint8 {.magic: "ModU", noSideEffect.}
proc `mod`*(x, y: uint16): uint16 {.magic: "ModU", noSideEffect.}
proc `mod`*(x, y: uint32): uint32 {.magic: "ModU", noSideEffect.}
proc `mod`*(x, y: uint64): uint64 {.magic: "ModU", noSideEffect.}

proc `+=`*[T: SomeInteger](x: var T, y: T) {.
  magic: "Inc", noSideEffect.}
  ## Increments an integer.

proc `-=`*[T: SomeInteger](x: var T, y: T) {.
  magic: "Dec", noSideEffect.}
  ## Decrements an integer.

proc `*=`*[T: SomeInteger](x: var T, y: T) {.
  inline, noSideEffect.} =
  ## Binary `*=` operator for integers.
  x = x * y

# floating point operations:
proc `+`*(x: float32): float32 {.magic: "UnaryPlusF64", noSideEffect.}
proc `-`*(x: float32): float32 {.magic: "UnaryMinusF64", noSideEffect.}
proc `+`*(x, y: float32): float32 {.magic: "AddF64", noSideEffect.}
proc `-`*(x, y: float32): float32 {.magic: "SubF64", noSideEffect.}
proc `*`*(x, y: float32): float32 {.magic: "MulF64", noSideEffect.}
proc `/`*(x, y: float32): float32 {.magic: "DivF64", noSideEffect.}

proc `+`*(x: float): float {.magic: "UnaryPlusF64", noSideEffect.}
proc `-`*(x: float): float {.magic: "UnaryMinusF64", noSideEffect.}
proc `+`*(x, y: float): float {.magic: "AddF64", noSideEffect.}
proc `-`*(x, y: float): float {.magic: "SubF64", noSideEffect.}
proc `*`*(x, y: float): float {.magic: "MulF64", noSideEffect.}
proc `/`*(x, y: float): float {.magic: "DivF64", noSideEffect.}

proc `+=`*[T: float|float32|float64] (x: var T, y: T) {.
  inline, noSideEffect.} =
  ## Increments in place a floating point number.
  x = x + y

proc `-=`*[T: float|float32|float64] (x: var T, y: T) {.
  inline, noSideEffect.} =
  ## Decrements in place a floating point number.
  x = x - y

proc `*=`*[T: float|float32|float64] (x: var T, y: T) {.
  inline, noSideEffect.} =
  ## Multiplies in place a floating point number.
  x = x * y

proc `/=`*(x: var float64, y: float64) {.inline, noSideEffect.} =
  ## Divides in place a floating point number.
  x = x / y

proc `/=`*[T: float|float32](x: var T, y: T) {.inline, noSideEffect.} =
  ## Divides in place a floating point number.
  x = x / y

# the following have to be included in system, not imported for some reason:

proc `+%`*(x, y: int): int {.inline.} =
  ## Treats `x` and `y` as unsigned and adds them.
  ##
  ## The result is truncated to fit into the result.
  ## This implements modulo arithmetic. No overflow errors are possible.
  cast[int](cast[uint](x) + cast[uint](y))
proc `+%`*(x, y: int8): int8 {.inline.}   = cast[int8](cast[uint8](x) + cast[uint8](y))
proc `+%`*(x, y: int16): int16 {.inline.} = cast[int16](cast[uint16](x) + cast[uint16](y))
proc `+%`*(x, y: int32): int32 {.inline.} = cast[int32](cast[uint32](x) + cast[uint32](y))
proc `+%`*(x, y: int64): int64 {.inline.} = cast[int64](cast[uint64](x) + cast[uint64](y))

proc `-%`*(x, y: int): int {.inline.} =
  ## Treats `x` and `y` as unsigned and subtracts them.
  ##
  ## The result is truncated to fit into the result.
  ## This implements modulo arithmetic. No overflow errors are possible.
  cast[int](cast[uint](x) - cast[uint](y))
proc `-%`*(x, y: int8): int8 {.inline.}   = cast[int8](cast[uint8](x) - cast[uint8](y))
proc `-%`*(x, y: int16): int16 {.inline.} = cast[int16](cast[uint16](x) - cast[uint16](y))
proc `-%`*(x, y: int32): int32 {.inline.} = cast[int32](cast[uint32](x) - cast[uint32](y))
proc `-%`*(x, y: int64): int64 {.inline.} = cast[int64](cast[uint64](x) - cast[uint64](y))

proc `*%`*(x, y: int): int {.inline.} =
  ## Treats `x` and `y` as unsigned and multiplies them.
  ##
  ## The result is truncated to fit into the result.
  ## This implements modulo arithmetic. No overflow errors are possible.
  cast[int](cast[uint](x) * cast[uint](y))
proc `*%`*(x, y: int8): int8 {.inline.}   = cast[int8](cast[uint8](x) * cast[uint8](y))
proc `*%`*(x, y: int16): int16 {.inline.} = cast[int16](cast[uint16](x) * cast[uint16](y))
proc `*%`*(x, y: int32): int32 {.inline.} = cast[int32](cast[uint32](x) * cast[uint32](y))
proc `*%`*(x, y: int64): int64 {.inline.} = cast[int64](cast[uint64](x) * cast[uint64](y))

proc `/%`*(x, y: int): int {.inline.} =
  ## Treats `x` and `y` as unsigned and divides them.
  ##
  ## The result is truncated to fit into the result.
  ## This implements modulo arithmetic. No overflow errors are possible.
  cast[int](cast[uint](x) div cast[uint](y))
proc `/%`*(x, y: int8): int8 {.inline.}   = cast[int8](cast[uint8](x) div cast[uint8](y))
proc `/%`*(x, y: int16): int16 {.inline.} = cast[int16](cast[uint16](x) div cast[uint16](y))
proc `/%`*(x, y: int32): int32 {.inline.} = cast[int32](cast[uint32](x) div cast[uint32](y))
proc `/%`*(x, y: int64): int64 {.inline.} = cast[int64](cast[uint64](x) div cast[uint64](y))

proc `%%`*(x, y: int): int {.inline.} =
  ## Treats `x` and `y` as unsigned and compute the modulo of `x` and `y`.
  ##
  ## The result is truncated to fit into the result.
  ## This implements modulo arithmetic. No overflow errors are possible.
  cast[int](cast[uint](x) mod cast[uint](y))
proc `%%`*(x, y: int8): int8 {.inline.}   = cast[int8](cast[uint8](x) mod cast[uint8](y))
proc `%%`*(x, y: int16): int16 {.inline.} = cast[int16](cast[uint16](x) mod cast[uint16](y))
proc `%%`*(x, y: int32): int32 {.inline.} = cast[int32](cast[uint32](x) mod cast[uint32](y))
proc `%%`*(x, y: int64): int64 {.inline.} = cast[int64](cast[uint64](x) mod cast[uint64](y))

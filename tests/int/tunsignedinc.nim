
block: # bug #2427
  var x = 0'u8
  dec x # OverflowDefect
  x -= 1 # OverflowDefect
  x = x - 1 # No error

  doAssert(x == 253'u8)

block:
  var x = 130'u8
  x += 130'u8
  doAssert(x == 4'u8)

block:
  var x = 40000'u16
  x = x + 40000'u16
  doAssert(x == 14464'u16)

block:
  var x = 4000000000'u32
  x = x + 4000000000'u32
  doAssert(x == 3705032704'u32)

block:
  var x = 123'u16
  x -= 125
  doAssert(x == 65534'u16)

block t4175:
  let i = 0u - 1u
  const j = 0u - 1u
  doAssert i == j
  doAssert j + 1u == 0u

block: # https://forum.nim-lang.org/t/12465#76998
  var a: int = 1
  var x: uint8 = 1
  a.inc(x)   # Error: type mismatch
  doAssert a == 2

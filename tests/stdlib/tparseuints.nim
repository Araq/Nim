discard """
  matrix: "--mm:refc; --mm:orc"
"""

import unittest, strutils

block: # parseutils
  check: parseBiggestUInt("0") == 0'u64
  check: parseBiggestUInt("1") == 1'u64
  check: parseBiggestUInt("2") == 2'u64
  check: parseBiggestUInt("10") == 10'u64
  check: parseBiggestUInt("11") == 11'u64
  check: parseBiggestUInt("99") == 99'u64
  check: parseBiggestUInt("123") == 123'u64
  check: parseBiggestUInt("9876") == 9876'u64
  check: parseBiggestUInt("1_234") == 1234'u64
  check: parseBiggestUInt("123__4") == 1234'u64
  for i in 1.BiggestUInt .. 9.BiggestUInt:
    var x = i
    for j in 1 .. 19:
      check parseBiggestUInt((i + '0'.uint).char.repeat j) == x
      x *= 10
      x += i
  check: parseBiggestUInt("18446744073709551609") == 0xFFFF_FFFF_FFFF_FFF9'u64
  check: parseBiggestUInt("18446744073709551610") == 0xFFFF_FFFF_FFFF_FFFA'u64
  check: parseBiggestUInt("18446744073709551611") == 0xFFFF_FFFF_FFFF_FFFB'u64
  check: parseBiggestUInt("18446744073709551612") == 0xFFFF_FFFF_FFFF_FFFC'u64
  check: parseBiggestUInt("18446744073709551613") == 0xFFFF_FFFF_FFFF_FFFD'u64
  check: parseBiggestUInt("18446744073709551614") == 0xFFFF_FFFF_FFFF_FFFE'u64
  check: parseBiggestUInt("18446744073709551615") == 0xFFFF_FFFF_FFFF_FFFF'u64
  expect(ValueError):
    discard parseBiggestUInt("18446744073709551616")
  expect(ValueError):
    discard parseBiggestUInt("18446744073709551617")
  expect(ValueError):
    discard parseBiggestUInt("18446744073709551618")
  expect(ValueError):
    discard parseBiggestUInt("18446744073709551619")
  expect(ValueError):
    discard parseBiggestUInt("18446744073709551620")
  expect(ValueError):
    discard parseBiggestUInt("18446744073709551621")
  expect(ValueError):
    discard parseBiggestUInt("18446744073709551622")
  expect(ValueError):
    discard parseBiggestUInt("18446744073709551623")
  expect(ValueError):
    for i in 0 .. 999:
      discard parseBiggestUInt("18446744073709552" & intToStr(i, 3))
  expect(ValueError):
    discard parseBiggestUInt("22751622367522324480000000")
  expect(ValueError):
    discard parseBiggestUInt("41404969074137497600000000")
  expect(ValueError):
    discard parseBiggestUInt("20701551093035827200000000000000000")
  expect(ValueError):
    discard parseBiggestUInt("225462255024603136000000000000000000")
  expect(ValueError):
    discard parseBiggestUInt("204963831854661632000000000000000000")

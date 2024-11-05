import ropes, int128

type
  Snippet* = string
  Builder* = object
    buf*: string

template newBuilder*(s: string): Builder =
  Builder(buf: s)

proc extract*(builder: Builder): Snippet =
  builder.buf

proc add*(builder: var Builder, s: string) =
  builder.buf.add(s)

proc add*(builder: var Builder, s: char) =
  builder.buf.add(s)

proc addIntValue*(builder: var Builder, val: int) =
  builder.buf.addInt(val)

proc addIntValue*(builder: var Builder, val: int64) =
  builder.buf.addInt(val)

proc addIntValue*(builder: var Builder, val: uint64) =
  builder.buf.addInt(val)

proc addIntValue*(builder: var Builder, val: Int128) =
  builder.buf.addInt128(val)

template cIntValue*(val: int): Snippet = $val
template cIntValue*(val: int64): Snippet = $val
template cIntValue*(val: uint64): Snippet = $val
template cIntValue*(val: Int128): Snippet = $val

template cUintValue*(val: uint): Snippet = $val & "U"

import std/formatfloat

proc addFloatValue*(builder: var Builder, val: float) =
  builder.buf.addFloat(val)

template cFloatValue*(val: float): Snippet = $val

proc addInt64Literal*(result: var Builder; i: BiggestInt) =
  if i > low(int64):
    result.add "IL64($1)" % [rope(i)]
  else:
    result.add "(IL64(-9223372036854775807) - IL64(1))"

proc addUint64Literal*(result: var Builder; i: uint64) =
  result.add rope($i & "ULL")

proc addIntLiteral*(result: var Builder; i: BiggestInt) =
  if i > low(int32) and i <= high(int32):
    result.addIntValue(i)
  elif i == low(int32):
    # Nim has the same bug for the same reasons :-)
    result.add "(-2147483647 -1)"
  elif i > low(int64):
    result.add "IL64($1)" % [rope(i)]
  else:
    result.add "(IL64(-9223372036854775807) - IL64(1))"

proc addIntLiteral*(result: var Builder; i: Int128) =
  addIntLiteral(result, toInt64(i))

proc cInt64Literal*(i: BiggestInt): Snippet =
  if i > low(int64):
    result = "IL64($1)" % [rope(i)]
  else:
    result = "(IL64(-9223372036854775807) - IL64(1))"

proc cUint64Literal*(i: uint64): Snippet =
  result = $i & "ULL"

proc cIntLiteral*(i: BiggestInt): Snippet =
  if i > low(int32) and i <= high(int32):
    result = rope(i)
  elif i == low(int32):
    # Nim has the same bug for the same reasons :-)
    result = "(-2147483647 -1)"
  elif i > low(int64):
    result = "IL64($1)" % [rope(i)]
  else:
    result = "(IL64(-9223372036854775807) - IL64(1))"

proc cIntLiteral*(i: Int128): Snippet =
  result = cIntLiteral(toInt64(i))

type
  Snippet = string
  Builder = string

template newBuilder(s: string): Builder =
  s

proc addIntValue(builder: var Builder, val: int) =
  builder.addInt(val)

proc addIntValue(builder: var Builder, val: int64) =
  builder.addInt(val)

proc addIntValue(builder: var Builder, val: uint64) =
  builder.addInt(val)

proc addIntValue(builder: var Builder, val: Int128) =
  builder.addInt128(val)

template cIntValue(val: int): Snippet = $val
template cIntValue(val: int64): Snippet = $val
template cIntValue(val: uint64): Snippet = $val
template cIntValue(val: Int128): Snippet = $val

import std/formatfloat

proc addFloatValue(builder: var Builder, val: float) =
  builder.addFloat(val)

template cFloatValue(val: float): Snippet = $val

proc int64Literal(i: BiggestInt; result: var Builder) =
  if i > low(int64):
    result.add "IL64($1)" % [rope(i)]
  else:
    result.add "(IL64(-9223372036854775807) - IL64(1))"

proc uint64Literal(i: uint64; result: var Builder) =
  result.add rope($i & "ULL")

proc intLiteral(i: BiggestInt; result: var Builder) =
  if i > low(int32) and i <= high(int32):
    result.addIntValue(i)
  elif i == low(int32):
    # Nim has the same bug for the same reasons :-)
    result.add "(-2147483647 -1)"
  elif i > low(int64):
    result.add "IL64($1)" % [rope(i)]
  else:
    result.add "(IL64(-9223372036854775807) - IL64(1))"

proc intLiteral(i: Int128; result: var Builder) =
  intLiteral(toInt64(i), result)

proc cInt64Literal(i: BiggestInt): Snippet =
  if i > low(int64):
    result = "IL64($1)" % [rope(i)]
  else:
    result = "(IL64(-9223372036854775807) - IL64(1))"

proc cUint64Literal(i: uint64): Snippet =
  result = $i & "ULL"

proc cIntLiteral(i: BiggestInt): Snippet =
  if i > low(int32) and i <= high(int32):
    result = rope(i)
  elif i == low(int32):
    # Nim has the same bug for the same reasons :-)
    result = "(-2147483647 -1)"
  elif i > low(int64):
    result = "IL64($1)" % [rope(i)]
  else:
    result = "(IL64(-9223372036854775807) - IL64(1))"

proc cIntLiteral(i: Int128): Snippet =
  result = cIntLiteral(toInt64(i))

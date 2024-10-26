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

proc cFloatValue(val: float): Snippet =
  result = ""
  result.addFloat(val)

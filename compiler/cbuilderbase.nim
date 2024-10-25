type
  Snippet = string
  Builder = string

template newBuilder(s: string): Builder =
  s

proc addIntValue(builder: var Builder, val: int | int64 | uint64) =
  builder.addInt(val)

proc addIntValue(builder: var Builder, val: Int128) =
  builder.addInt128(val)

template addIntValue(builder: var Builder, val: static int) =
  builder.add(static($val))

proc cIntValue(val: int | int64 | uint64): Snippet =
  result = ""
  result.addInt(val)

proc cIntValue(val: Int128): Snippet =
  result = ""
  result.addInt128(val)

template cIntValue(val: static int): Snippet =
  (static($val))

import std/formatfloat

proc addFloatValue(builder: var Builder, val: float) =
  builder.addFloat(val)

template addFloatValue(builder: var Builder, val: static float) =
  builder.add(static($val))

proc cFloatValue(val: float): Snippet =
  result = ""
  result.addFloat(val)

template cFloatValue(val: static float): Snippet =
  (static($val))

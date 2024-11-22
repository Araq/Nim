import ropes, int128

type
  Snippet* = string
  Builder* = object
    buf*: string
    indents*: int

template newBuilder*(s: string): Builder =
  Builder(buf: s)

proc extract*(builder: Builder): Snippet =
  builder.buf

proc add*(builder: var Builder, s: string) =
  builder.buf.add(s)

proc add*(builder: var Builder, s: char) =
  builder.buf.add(s)

proc addNewline*(builder: var Builder) =
  builder.add('\n')
  for i in 0 ..< builder.indents:
    builder.add('\t')

proc addLineEnd*(builder: var Builder, s: string) =
  builder.add(s)
  builder.addNewline()

proc addLineEndIndent*(builder: var Builder, s: string) =
  inc builder.indents
  builder.add(s)
  builder.addNewline()

proc addDedent*(builder: var Builder, s: string) =
  if builder.buf.len > 0 and builder.buf[^1] == '\t':
    builder.buf.setLen(builder.buf.len - 1)
  builder.add(s)
  dec builder.indents

proc addLineEndDedent*(builder: var Builder, s: string) =
  builder.addDedent(s)
  builder.addNewline()

proc addLineComment*(builder: var Builder, comment: string) =
  # probably no-op on nifc
  builder.add("// ")
  builder.add(comment)
  builder.addNewline()

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

const
  NimInt* = "NI"
  NimInt8* = "NI8"
  NimInt16* = "NI16"
  NimInt32* = "NI32"
  NimInt64* = "NI64"
  CInt* = "int"
  NimUint* = "NU"
  NimUint8* = "NU8"
  NimUint16* = "NU16"
  NimUint32* = "NU32"
  NimUint64* = "NU64"
  NimFloat* = "NF"
  NimFloat32* = "NF32"
  NimFloat64* = "NF64"
  NimFloat128* = "NF128" # not actually defined
  NimNan* = "NAN"
  NimInf* = "INF"
  NimBool* = "NIM_BOOL"
  NimTrue* = "NIM_TRUE"
  NimFalse* = "NIM_FALSE"
  NimChar* = "NIM_CHAR"
  CChar* = "char"
  NimCstring* = "NCSTRING"
  NimNil* = "NIM_NIL"
  CNil* = "NULL"
  NimStrlitFlag* = "NIM_STRLIT_FLAG"
  CVoid* = "void"
  CPointer* = "void*"
  CConstPointer* = "NIM_CONST void*"

proc cIntType*(bits: BiggestInt): Snippet =
  "NI" & $bits

proc cUintType*(bits: BiggestInt): Snippet =
  "NU" & $bits

type
  IfBuilderState* = enum
    WaitingIf, WaitingElseIf, InBlock
  IfBuilder* = object
    state*: IfBuilderState

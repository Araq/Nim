import ropes, int128, std/formatfloat

const buildNifc* = defined(nimCompileToNifc)

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
  when not buildNifc:
    builder.add("// ")
    builder.add(comment)
    builder.addNewline()

proc addIntValue*(builder: var Builder, val: int) =
  when buildNifc:
    if val >= 0:
      builder.buf.add('+')
  builder.buf.addInt(val)

proc addIntValue*(builder: var Builder, val: int64) =
  when buildNifc:
    if val >= 0:
      builder.buf.add('+')
  builder.buf.addInt(val)

proc addIntValue*(builder: var Builder, val: uint64) =
  when buildNifc:
    builder.buf.add('+')
  builder.buf.addInt(val)

proc addIntValue*(builder: var Builder, val: Int128) =
  when buildNifc:
    if val >= 0:
      builder.buf.add('+')
  builder.buf.addInt128(val)

when not buildNifc:
  template cIntValue*(val: int): Snippet = $val
  template cIntValue*(val: int64): Snippet = $val
  template cIntValue*(val: uint64): Snippet = $val
  template cIntValue*(val: Int128): Snippet = $val

  template cUintValue*(val: uint): Snippet = $val & "U"

  proc addFloatValue*(builder: var Builder, val: float) =
    builder.buf.addFloat(val)

  template cFloatValue*(val: float): Snippet = $val
else:
  proc cIntValue*(val: int): Snippet =
    result = if val >= 0: "+" else: ""
    result.addInt(val)
  proc cIntValue*(val: int64): Snippet =
    result = if val >= 0: "+" else: ""
    result.addInt(val)
  proc cIntValue*(val: uint64): Snippet =
    result = "+"
    result.addInt(val)
  proc cIntValue*(val: Int128): Snippet =
    result = if val >= 0: "+" else: ""
    result.addInt128(val)
  proc cUintValue*(val: uint): Snippet =
    result = "+"
    result.addInt(val)
    result.add('u')

  import std/math

  proc addFloatValue*(builder: var Builder, val: float) =
    let kind = classify(val)
    case kind
    of fcNan:
      builder.buf.add("(nan)")
    of fcInf:
      builder.buf.add("(inf)")
    of fcNegInf:
      builder.buf.add("(neginf)")
    else:
      if val >= 0:
        builder.buf.add("+")
      builder.buf.addFloat(val)

  proc cFloatValue*(val: float): Snippet =
    let kind = classify(val)
    case kind
    of fcNan:
      result = "(nan)"
    of fcInf:
      result = "(inf)"
    of fcNegInf:
      result = "(neginf)"
    else:
      result = if val >= 0: "+" else: "-"
      result.addFloat(val)

proc addInt64Literal*(result: var Builder; i: BiggestInt) =
  when buildNifc:
    result.add("(suf ")
    result.addIntValue(i)
    result.add(" \"i64\")")
  else:
    if i > low(int64):
      result.add "IL64($1)" % [rope(i)]
    else:
      result.add "(IL64(-9223372036854775807) - IL64(1))"

proc addUint64Literal*(result: var Builder; i: uint64) =
  when buildNifc:
    result.add("(suf ")
    result.addIntValue(i)
    result.add('u')
    result.add(" \"u64\")")
  else:
    result.add rope($i & "ULL")

proc addIntLiteral*(result: var Builder; i: BiggestInt) =
  when buildNifc:
    # nifc handles this
    result.addIntValue(i)
  else:
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
  when buildNifc:
    result = "(suf " & cIntValue(i) & " \"i64\")"
  else:
    if i > low(int64):
      result = "IL64($1)" % [rope(i)]
    else:
      result = "(IL64(-9223372036854775807) - IL64(1))"

proc cUint64Literal*(i: uint64): Snippet =
  when buildNifc:
    result = "(suf " & cUintValue(i) & " \"u64\")"
  else:
    result = $i & "ULL"

proc cIntLiteral*(i: BiggestInt): Snippet =
  when buildNifc:
    result = cIntValue(i)
  else:
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

when buildNifc:
  const
    NimInt* = "(i -1)"
    NimInt8* = "(i +8)"
    NimInt16* = "(i +16)"
    NimInt32* = "(i +32)"
    NimInt64* = "(i +64)"
    CInt* = "(i +32)" # int.c
    NimUint* = "(u -1)"
    NimUint8* = "(u +8)"
    NimUint16* = "(u +16)"
    NimUint32* = "(u +32)"
    NimUint64* = "(u +64)"
    NimFloat* = "(f +64)"
    NimFloat32* = "(f +32)"
    NimFloat64* = "(f +64)"
    NimFloat128* = "(f +128)"
    NimNan* = "(nan)"
    NimInf* = "(inf)"
    NimBool* = "(bool)"
    NimTrue* = "(true)"
    NimFalse* = "(false)"
    NimChar* = "(c +8)"
    CChar* = "(c +8)" # char.c
    NimCstring* = "(ptr (c +8))"
    NimNil* = "(nil)"
    CNil* = "(nil)" # NULL.c
    NimStrlitFlag* = "NIM_STRLIT_FLAG" # XXX
    CVoid* = "(void)"
    CPointer* = "(ptr (void))"
    CConstPointer* = "(ptr (void))" # (void (ro)) illegal
else:
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
  when buildNifc:
    "(i +" & $bits & ")"
  else:
    "NI" & $bits

proc cUintType*(bits: BiggestInt): Snippet =
  when buildNifc:
    "(u +" & $bits & ")"
  else:
    "NU" & $bits

type
  IfBuilderState* = enum
    WaitingIf, WaitingElseIf, InBlock
  IfBuilder* = object
    state*: IfBuilderState

when buildNifc:
  import std/assertions

  proc cSymbol*(s: string): Snippet =
    result = newStringOfCap(s.len)
    for c in s:
      case c
      of 'A'..'Z', 'a'..'z', '0'..'9', '_':
        result.add(c)
      else:
        const HexChars = "0123456789ABCDEF"
        result.add('\\')
        result.add(HexChars[(c.byte shr 4) and 0xF])
        result.add(HexChars[c.byte and 0xF])
    result.add(".c")
  
  proc getHexChar(c: char): byte =
    case c
    of '0'..'9': c.byte - '0'.byte
    of 'A'..'Z': c.byte - 'A'.byte + 10
    of 'a'..'z': c.byte - 'a'.byte + 10
    else: raiseAssert "invalid hex char " & c

  proc unescapeCSymbol*(s: string): Snippet =
    assert s.len >= 2 and s[^2 .. ^1] == ".c"
    let viewLen = s.len - 2
    result = newStringOfCap(viewLen)
    var i = 0
    while i < viewLen:
      case s[i]
      of 'A'..'Z', 'a'..'z', '0'..'9', '_':
        result.add(s[i])
      of '\\':
        assert i + 2 < viewLen
        let b = (getHexChar(s[i + 1]) shl 4) or getHexChar(s[i + 2])
        result.add(char(b))
        inc i, 2
      else:
        raiseAssert "invalid char in escaped c symbol " & s[i]
      inc i

else:
  template cSymbol*(x: string): Snippet = x
  template unescapeCSymbol*(x: Snippet): string = x

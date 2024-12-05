proc constType(t: Snippet): Snippet =
  when buildNifc:
    # XXX can't just string modify `t`, need to deeply insert (ro) somehow
    t
  else:
    "NIM_CONST " & t

proc ptrType(t: Snippet): Snippet =
  when buildNifc:
    "(ptr " & t & ")"
  else:
    t & "*"

proc constPtrType(t: Snippet): Snippet =
  when buildNifc:
    "(ptr " & t & " (ro))"
  else:
    t & "* NIM_CONST"

proc ptrConstType(t: Snippet): Snippet =
  # NIM_CONST `t`*
  ptrType(constType(t))

proc cppRefType(t: Snippet): Snippet =
  when buildNifc:
    # XXX not implemented in nifc
    ptrType(t)
  else:
    t & "&"

when buildNifc:
  const
    CallingConvToStr: array[TCallingConvention, string] = ["(fastcall)",
      "(stdcall)", "(cdecl)", "(safecall)",
      "(syscall)",
      "(inline)", "(noinline)", "(fastcall)", "(thiscall)", "(fastcall)", "(noconv)",
      "(member)"
      ]
else:
  const
    CallingConvToStr: array[TCallingConvention, string] = ["N_NIMCALL",
      "N_STDCALL", "N_CDECL", "N_SAFECALL",
      "N_SYSCALL", # this is probably not correct for all platforms,
                  # but one can #define it to what one wants
      "N_INLINE", "N_NOINLINE", "N_FASTCALL", "N_THISCALL", "N_CLOSURE", "N_NOCONV",
      "N_NOCONV" #ccMember is N_NOCONV
      ]

proc procPtrTypeUnnamed(rettype, params: Snippet, isVarargs = false): Snippet =
  when buildNifc:
    "(proctype . " & params & " " & rettype & " " &
      (if isVarargs: "(pragmas (varargs))" else: ".") & ")"
  else:
    rettype & "(*)" & params

proc procPtrTypeUnnamedNimCall(rettype, params: Snippet): Snippet =
  when buildNifc:
    "(proctype . " & params & " " & rettype & " (pragmas (fastcall)))"
  else:
    rettype & "(N_RAW_NIMCALL*)" & params

proc procPtrTypeUnnamed(callConv: TCallingConvention, rettype, params: Snippet): Snippet =
  when buildNifc:
    "(proctype . " & params & " " & rettype & " (pragmas " & CallingConvToStr[callConv] & "))"
  else:
    CallingConvToStr[callConv] & "_PTR(" & rettype & ", )" & params

type CppCaptureKind = enum None, ByReference, ByCopy

template addCppLambda(builder: var Builder, captures: CppCaptureKind, params: Snippet, body: typed) =
  when buildNifc:
    raiseAssert "not implemented"
  else:
    builder.add("[")
    case captures
    of None: discard
    of ByReference: builder.add("&")
    of ByCopy: builder.add("=")
    builder.add("] ")
    builder.add(params)
    builder.addLineEndIndent(" {")
    body
    builder.addLineEndDedent("}")

proc cCast(typ, value: Snippet): Snippet =
  when buildNifc:
    "(cast " & typ & " " & value & ")"
  else:
    "((" & typ & ") " & value & ")"

proc wrapPar(value: Snippet): Snippet =
  when buildNifc:
    value # already wrapped
  else:
    "(" & value & ")"

proc removeSinglePar(value: Snippet): Snippet =
  when buildNifc:
    value
  else:
    # removes a single paren layer expected to exist, to silence Wparentheses-equality
    assert value[0] == '(' and value[^1] == ')'
    value[1..^2]

template addCast(builder: var Builder, typ: Snippet, valueBody: typed) =
  ## adds a cast to `typ` with value built by `valueBody`
  when buildNifc:
    builder.add "(cast "
    builder.add typ
    builder.add " "
  else:
    builder.add "(("
    builder.add typ
    builder.add ") "
  valueBody
  builder.add ")"

proc cAddr(value: Snippet): Snippet =
  when buildNifc:
    "(addr " & value & ")"
  else:
    "(&" & value & ")"

proc cLabelAddr(value: TLabel): Snippet =
  when buildNifc:
    raiseAssert "unimplemented"
  else:
    "&&" & value

proc cDeref(value: Snippet): Snippet =
  when buildNifc:
    "(deref " & value & ")"
  else:
    "(*" & value & ")"

proc subscript(a, b: Snippet): Snippet =
  when buildNifc:
    "(at " & a & " " & b & ")"
  else:
    a & "[" & b & "]"

proc dotField(a, b: Snippet): Snippet =
  when buildNifc:
    "(dot " & a & " " & rawFieldName(b) & " +0)" # XXX inheritance field
  else:
    a & "." & b

proc derefField(a, b: Snippet): Snippet =
  when buildNifc:
    "(dot " & cDeref(a) & " " & rawFieldName(b) & " +0)" # XXX inheritance field
  else:
    a & "->" & b

type CallBuilder = object
  needsComma: bool

proc initCallBuilder(builder: var Builder, callee: Snippet): CallBuilder =
  result = CallBuilder(needsComma: false)
  when buildNifc:
    builder.add("(call ")
    builder.add(callee)
    builder.add(" ")
  else:
    builder.add(callee)
    builder.add("(")

when buildNifc:
  const cArgumentSeparator = " "
else:
  const cArgumentSeparator = ", "

proc addArgumentSeparator(builder: var Builder) =
  # no-op on NIFC
  # used by "single argument" builders
  builder.add(cArgumentSeparator)

template addArgument(builder: var Builder, call: var CallBuilder, valueBody: typed) =
  if call.needsComma:
    builder.addArgumentSeparator()
  else:
    call.needsComma = true
  valueBody

proc finishCallBuilder(builder: var Builder, call: CallBuilder) =
  builder.add(")")

template addCall(builder: var Builder, call: out CallBuilder, callee: Snippet, body: typed) =
  call = initCallBuilder(builder, callee)
  body
  finishCallBuilder(builder, call)

proc addCall(builder: var Builder, callee: Snippet, args: varargs[Snippet]) =
  when buildNifc:
    builder.add("(call ")
    builder.add(callee)
    builder.add(" ")
  else:
    builder.add(callee)
    builder.add("(")
  if args.len != 0:
    builder.add(args[0])
    for i in 1 ..< args.len:
      builder.add(cArgumentSeparator)
      builder.add(args[i])
  builder.add(")")

proc cCall(callee: Snippet, args: varargs[Snippet]): Snippet =
  when buildNifc:
    result = "(call "
    result.add(callee)
    result.add(" ")
  else:
    result = callee
    result.add("(")
  if args.len != 0:
    result.add(args[0])
    for i in 1 ..< args.len:
      result.add(cArgumentSeparator)
      result.add(args[i])
  result.add(")")

proc addSizeof(builder: var Builder, val: Snippet) =
  when buildNifc:
    builder.add("(sizeof ")
  else:
    builder.add("sizeof(")
  builder.add(val)
  builder.add(")")

proc addAlignof(builder: var Builder, val: Snippet) =
  when buildNifc:
    builder.add("(alignof ")
  else:
    builder.add("NIM_ALIGNOF(")
  builder.add(val)
  builder.add(")")

proc addOffsetof(builder: var Builder, val, member: Snippet) =
  when buildNifc:
    builder.add("(offsetof ")
  else:
    builder.add("offsetof(")
  builder.add(val)
  builder.add(cArgumentSeparator)
  builder.add(member)
  builder.add(")")

template cSizeof(val: Snippet): Snippet =
  when buildNifc:
    "(sizeof " & val & ")"
  else:
    "sizeof(" & val & ")"

template cAlignof(val: Snippet): Snippet =
  when buildNifc:
    "(alignof " & val & ")"
  else:
    "NIM_ALIGNOF(" & val & ")"

template cOffsetof(val, member: Snippet): Snippet =
  when buildNifc:
    "(offsetof " & val & " " & member & ")"
  else:
    "offsetof(" & val & ", " & member & ")"

type TypedBinaryOp = enum
  Add, Sub, Mul, Div, Mod
  Shr, Shl, BitAnd, BitOr, BitXor

when buildNifc:
  const typedBinaryOperators: array[TypedBinaryOp, string] = [
    Add: "add",
    Sub: "sub",
    Mul: "mul",
    Div: "div",
    Mod: "mod",
    Shr: "shr",
    Shl: "shl",
    BitAnd: "bitand",
    BitOr: "bitor",
    BitXor: "bitxor"
  ]
else:
  const typedBinaryOperators: array[TypedBinaryOp, string] = [
    Add: "+",
    Sub: "-",
    Mul: "*",
    Div: "/",
    Mod: "%",
    Shr: ">>",
    Shl: "<<",
    BitAnd: "&",
    BitOr: "|",
    BitXor: "^"
  ]

type TypedUnaryOp = enum
  Neg, BitNot

when buildNifc:
  const typedUnaryOperators: array[TypedUnaryOp, string] = [
    Neg: "neg",
    BitNot: "bitnot",
  ]
else:
  const typedUnaryOperators: array[TypedUnaryOp, string] = [
    Neg: "-",
    BitNot: "~",
  ]

type UntypedBinaryOp = enum
  LessEqual, LessThan, GreaterEqual, GreaterThan, Equal, NotEqual
  And, Or

when buildNifc:
  const untypedBinaryOperators: array[UntypedBinaryOp, string] = [
    LessEqual: "le",
    LessThan: "lt",
    GreaterEqual: "",
    GreaterThan: "",
    Equal: "eq",
    NotEqual: "neq",
    And: "and",
    Or: "or"
  ]
else:
  const untypedBinaryOperators: array[UntypedBinaryOp, string] = [
    LessEqual: "<=",
    LessThan: "<",
    GreaterEqual: ">=",
    GreaterThan: ">",
    Equal: "==",
    NotEqual: "!=",
    And: "&&",
    Or: "||"
  ]

type UntypedUnaryOp = enum
  Not

when buildNifc:
  const untypedUnaryOperators: array[UntypedUnaryOp, string] = [
    Not: "not"
  ]
else:
  const untypedUnaryOperators: array[UntypedUnaryOp, string] = [
    Not: "!"
  ]

proc addOp(builder: var Builder, binOp: TypedBinaryOp, t: Snippet, a, b: Snippet) =
  when buildNifc:
    builder.add('(')
    builder.add(typedBinaryOperators[binOp])
    builder.add(' ')
    builder.add(t)
    builder.add(' ')
    builder.add(a)
    builder.add(' ')
    builder.add(b)
    builder.add(')')
  else:
    builder.add('(')
    builder.add(a)
    builder.add(' ')
    builder.add(typedBinaryOperators[binOp])
    builder.add(' ')
    builder.add(b)
    builder.add(')')

proc addOp(builder: var Builder, unOp: TypedUnaryOp, t: Snippet, a: Snippet) =
  when buildNifc:
    builder.add('(')
    builder.add(typedUnaryOperators[unOp])
    builder.add(' ')
    builder.add(t)
    builder.add(' ')
    builder.add(a)
    builder.add(')')
  else:
    builder.add('(')
    builder.add(typedUnaryOperators[unOp])
    builder.add('(')
    builder.add(a)
    builder.add("))")

proc addOp(builder: var Builder, binOp: UntypedBinaryOp, a, b: Snippet) =
  when buildNifc:
    case binOp
    of GreaterEqual:
      builder.add("(not ")
      builder.addOp(LessThan, a, b)
      builder.add(')')
    of GreaterThan:
      builder.add("(not ")
      builder.addOp(LessEqual, a, b)
      builder.add(')')
    else:
      builder.add('(')
      builder.add(untypedBinaryOperators[binOp])
      builder.add(' ')
      builder.add(a)
      builder.add(' ')
      builder.add(b)
      builder.add(')')
  else:
    builder.add('(')
    builder.add(a)
    builder.add(' ')
    builder.add(untypedBinaryOperators[binOp])
    builder.add(' ')
    builder.add(b)
    builder.add(')')

proc addOp(builder: var Builder, unOp: UntypedUnaryOp, a: Snippet) =
  when buildNifc:
    builder.add('(')
    builder.add(untypedUnaryOperators[unOp])
    builder.add(' ')
    builder.add(a)
    builder.add(')')
  else:
    builder.add('(')
    builder.add(untypedUnaryOperators[unOp])
    builder.add('(')
    builder.add(a)
    builder.add("))")

when buildNifc:
  template cOp(binOp: TypedBinaryOp, t: Snippet, a, b: Snippet): Snippet =
    '(' & typedBinaryOperators[binOp] & ' ' & t & ' ' & a & ' ' & b & ')'

  template cOp(binOp: TypedUnaryOp, t: Snippet, a: Snippet): Snippet =
    '(' & typedUnaryOperators[binOp] & ' ' & t & ' ' & a & ')'

  proc cOp(binOp: UntypedBinaryOp, a, b: Snippet): Snippet =
    case binOp
    of GreaterEqual:
      "(not " & cOp(LessThan, a, b) & ')'
    of GreaterThan:
      "(not " & cOp(LessEqual, a, b) & ')'
    else:
      '(' & untypedBinaryOperators[binOp] & ' ' & a & ' ' & b & ')'

  template cOp(binOp: UntypedUnaryOp, a: Snippet): Snippet =
    '(' & untypedUnaryOperators[binOp] & ' ' & a & ')'
else:
  template cOp(binOp: TypedBinaryOp, t: Snippet, a, b: Snippet): Snippet =
    '(' & a & ' ' & typedBinaryOperators[binOp] & ' ' & b & ')'

  template cOp(binOp: TypedUnaryOp, t: Snippet, a: Snippet): Snippet =
    '(' & typedUnaryOperators[binOp] & '(' & a & "))"

  template cOp(binOp: UntypedBinaryOp, a, b: Snippet): Snippet =
    '(' & a & ' ' & untypedBinaryOperators[binOp] & ' ' & b & ')'

  template cOp(binOp: UntypedUnaryOp, a: Snippet): Snippet =
    '(' & untypedUnaryOperators[binOp] & '(' & a & "))"

template cIfExpr(cond, a, b: Snippet): Snippet =
  # XXX used for `min` and `max`, maybe add nifc primitives for these
  "(" & cond & " ? " & a & " : " & b & ")"

template cUnlikely(val: Snippet): Snippet =
  when buildNifc:
    val # not implemented
  else:
    "NIM_UNLIKELY(" & val & ")"

template arrayAddr(val: Snippet): Snippet =
  when buildNifc:
    cAddr(subscript(val, cIntValue(0)))
  else:
    val

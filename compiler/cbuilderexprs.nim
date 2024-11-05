# XXX make complex ones like bitOr use builder instead
# XXX add stuff like NI, NIM_NIL as constants

proc constType(t: Snippet): Snippet =
  # needs manipulation of `t` in nifc
  "NIM_CONST " & t

proc constPtrType(t: Snippet): Snippet =
  t & "* NIM_CONST"

proc ptrConstType(t: Snippet): Snippet =
  "NIM_CONST " & t & "*"

proc ptrType(t: Snippet): Snippet =
  t & "*"

const
  CallingConvToStr: array[TCallingConvention, string] = ["N_NIMCALL",
    "N_STDCALL", "N_CDECL", "N_SAFECALL",
    "N_SYSCALL", # this is probably not correct for all platforms,
                 # but one can #define it to what one wants
    "N_INLINE", "N_NOINLINE", "N_FASTCALL", "N_THISCALL", "N_CLOSURE", "N_NOCONV",
    "N_NOCONV" #ccMember is N_NOCONV
    ]

proc procPtrTypeUnnamed(rettype, params: Snippet): Snippet =
  rettype & "(*)" & params

proc procPtrTypeUnnamedNimCall(rettype, params: Snippet): Snippet =
  rettype & "(N_RAW_NIMCALL*)" & params

proc cCast(typ, value: Snippet): Snippet =
  "((" & typ & ") " & value & ")"

proc wrapPar(value: Snippet): Snippet =
  # used for expression group, no-op on sexp
  "(" & value & ")"

proc removeSinglePar(value: Snippet): Snippet =
  # removes a single paren layer expected to exist, to silence Wparentheses-equality
  assert value[0] == '(' and value[^1] == ')'
  value[1..^2]

template addCast(builder: var Builder, typ: Snippet, valueBody: typed) =
  ## adds a cast to `typ` with value built by `valueBody`
  builder.add "(("
  builder.add typ
  builder.add ") "
  valueBody
  builder.add ")"

proc cAddr(value: Snippet): Snippet =
  "&" & value

proc cDeref(value: Snippet): Snippet =
  "(*" & value & ")"

proc subscript(a, b: Snippet): Snippet =
  a & "[" & b & "]"

proc dotField(a, b: Snippet): Snippet =
  a & "." & b

proc derefField(a, b: Snippet): Snippet =
  a & "->" & b

proc bitOr(a, b: Snippet): Snippet =
  "(" & a & " | " & b & ")"

type CallBuilder = object
  needsComma: bool

proc initCallBuilder(builder: var Builder, callee: Snippet): CallBuilder =
  result = CallBuilder(needsComma: false)
  builder.add(callee)
  builder.add("(")

proc addArgumentSeparator(builder: var Builder) =
  # no-op on NIFC
  # used by "single argument" builders
  builder.add(", ")

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
  builder.add(callee)
  builder.add("(")
  if args.len != 0:
    builder.add(args[0])
    for i in 1 ..< args.len:
      builder.add(", ")
      builder.add(args[i])
  builder.add(")")

proc cCall(callee: Snippet, args: varargs[Snippet]): Snippet =
  result = callee
  result.add("(")
  if args.len != 0:
    result.add(args[0])
    for i in 1 ..< args.len:
      result.add(", ")
      result.add(args[i])
  result.add(")")

proc addSizeof(builder: var Builder, val: Snippet) =
  builder.add("sizeof(")
  builder.add(val)
  builder.add(")")

proc addAlignof(builder: var Builder, val: Snippet) =
  builder.add("NIM_ALIGNOF(")
  builder.add(val)
  builder.add(")")

proc addOffsetof(builder: var Builder, val, member: Snippet) =
  builder.add("offsetof(")
  builder.add(val)
  builder.add(", ")
  builder.add(member)
  builder.add(")")

template cSizeof(val: Snippet): Snippet =
  "sizeof(" & val & ")"

template cAlignof(val: Snippet): Snippet =
  "NIM_ALIGNOF(" & val & ")"

template cOffsetof(val, member: Snippet): Snippet =
  "offsetof(" & val & ", " & member & ")"

type TypedBinaryOp = enum
  Add, Sub, Mul, Div, Mod
  Shr, Shl, BitAnd, BitOr, BitXor

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

const typedUnaryOperators: array[TypedUnaryOp, string] = [
  Neg: "-",
  BitNot: "~",
]

type UntypedBinaryOp = enum
  LessEqual, LessThan, GreaterEqual, GreaterThan, Equal, NotEqual
  And, Or

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

const untypedUnaryOperators: array[UntypedUnaryOp, string] = [
  Not: "!"
]

proc addOp(builder: var Builder, binOp: TypedBinaryOp, t: Snippet, a, b: Snippet) =
  builder.add('(')
  builder.add(a)
  builder.add(' ')
  builder.add(typedBinaryOperators[binOp])
  builder.add(' ')
  builder.add(b)
  builder.add(')')

proc addOp(builder: var Builder, unOp: TypedUnaryOp, t: Snippet, a: Snippet) =
  builder.add('(')
  builder.add(typedUnaryOperators[unOp])
  builder.add('(')
  builder.add(a)
  builder.add("))")

proc addOp(builder: var Builder, binOp: UntypedBinaryOp, a, b: Snippet) =
  builder.add('(')
  builder.add(a)
  builder.add(' ')
  builder.add(untypedBinaryOperators[binOp])
  builder.add(' ')
  builder.add(b)
  builder.add(')')

proc addOp(builder: var Builder, unOp: UntypedUnaryOp, a: Snippet) =
  builder.add('(')
  builder.add(untypedUnaryOperators[unOp])
  builder.add('(')
  builder.add(a)
  builder.add("))")

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

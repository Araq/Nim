# XXX make complex ones like bitOr use builder instead
# XXX add stuff like NI, NIM_NIL as constants

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

proc procPtrType(conv: TCallingConvention, rettype: Snippet, name: string): Snippet =
  CallingConvToStr[conv] & "_PTR(" & rettype & ", " & name & ")"

proc cCast(typ, value: Snippet): Snippet =
  "((" & typ & ") " & value & ")"

proc wrapPar(value: Snippet): Snippet =
  # used for expression group, no-op on sexp
  "(" & value & ")"

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

template addArgument(builder: var Builder, call: var CallBuilder, valueBody: typed) =
  if call.needsComma:
    builder.add(", ")
  else:
    call.needsComma = true
  valueBody

proc finishCallBuilder(builder: var Builder, call: CallBuilder) =
  builder.add(")")

template addCall(builder: var Builder, call: out CallBuilder, callee: Snippet, body: typed) =
  call = initCallBuilder(builder, callee)
  body
  finishCallBuilder(builder, call)

proc addNullaryCall(builder: var Builder, callee: Snippet) =
  builder.add(callee)
  builder.add("()")

proc addUnaryCall(builder: var Builder, callee: Snippet, arg: Snippet) =
  builder.add(callee)
  builder.add("(")
  builder.add(arg)
  builder.add(")")

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

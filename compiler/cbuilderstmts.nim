template addAssignmentWithValue(builder: var Builder, lhs: Snippet, valueBody: typed) =
  when buildNifc:
    builder.add("(asgn ")
    builder.add(lhs)
    builder.add(' ')
    valueBody
    builder.addLineEnd(")")
  else:
    builder.add(lhs)
    builder.add(" = ")
    valueBody
    builder.addLineEnd(";")

template addFieldAssignmentWithValue(builder: var Builder, lhs: Snippet, name: string, valueBody: typed) =
  when buildNifc:
    builder.addAssignmentWithValue(dotField(lhs, name), valueBody)
  else:
    builder.add(lhs)
    builder.add("." & name & " = ")
    valueBody
    builder.addLineEnd(";")

template addAssignment(builder: var Builder, lhs, rhs: Snippet) =
  builder.addAssignmentWithValue(lhs):
    builder.add(rhs)

template addFieldAssignment(builder: var Builder, lhs: Snippet, name: string, rhs: Snippet) =
  builder.addFieldAssignmentWithValue(lhs, name):
    builder.add(rhs)

template addMutualFieldAssignment(builder: var Builder, lhs, rhs: Snippet, name: string) =
  builder.addFieldAssignmentWithValue(lhs, name):
    when buildNifc:
      builder.add(dotField(rhs, name))
    else:
      builder.add(rhs)
      builder.add("." & name)

template addAssignment(builder: var Builder, lhs: Snippet, rhs: int | int64 | uint64 | Int128) =
  builder.addAssignmentWithValue(lhs):
    builder.addIntValue(rhs)

template addFieldAssignment(builder: var Builder, lhs: Snippet, name: string, rhs: int | int64 | uint64 | Int128) =
  builder.addFieldAssignmentWithValue(lhs, name):
    builder.addIntValue(rhs)

template addDerefFieldAssignment(builder: var Builder, lhs: Snippet, name: string, rhs: Snippet) =
  when buildNifc:
    builder.addAssignment(derefField(lhs, name), rhs)
  else:
    builder.add(lhs)
    builder.add("->" & name & " = ")
    builder.add(rhs)
    builder.addLineEnd(";")

template addSubscriptAssignment(builder: var Builder, lhs: Snippet, index: Snippet, rhs: Snippet) =
  when buildNifc:
    builder.addAssignment(subscript(lhs, index), rhs)
  else:
    builder.add(lhs)
    builder.add("[" & index & "] = ")
    builder.add(rhs)
    builder.addLineEnd(";")

template addStmt(builder: var Builder, stmtBody: typed) =
  ## makes an expression built by `stmtBody` into a statement
  stmtBody
  when buildNifc:
    builder.addNewline()
  else:
    builder.addLineEnd(";")

proc addCallStmt(builder: var Builder, callee: Snippet, args: varargs[Snippet]) =
  builder.addStmt():
    builder.addCall(callee, args)

template addSingleIfStmt(builder: var Builder, cond: Snippet, body: typed) =
  when buildNifc:
    builder.add("(if (elif ")
    builder.add(cond)
    builder.addLineEndIndent(" (stmts")
    body
    builder.addLineEndDedent(")))")
  else:
    builder.add("if (")
    builder.add(cond)
    builder.addLineEndIndent(") {")
    body
    builder.addLineEndDedent("}")

template addSingleIfStmtWithCond(builder: var Builder, condBody: typed, body: typed) =
  when buildNifc:
    builder.add("(if (elif ")
    condBody
    builder.addLineEndIndent(" (stmts")
    body
    builder.addLineEndDedent(")))")
  else:
    builder.add("if (")
    condBody
    builder.addLineEndIndent(") {")
    body
    builder.addLineEndDedent("}")

proc initIfStmt(builder: var Builder): IfBuilder =
  when buildNifc:
    builder.add("(if")
  IfBuilder(state: WaitingIf)

proc finishIfStmt(builder: var Builder, stmt: IfBuilder) =
  assert stmt.state != InBlock
  when buildNifc:
    builder.addLineEnd(")")
  else:
    builder.addNewline()

template addIfStmt(builder: var Builder, stmt: out IfBuilder, body: typed) =
  stmt = initIfStmt(builder)
  body
  finishIfStmt(builder, stmt)

proc initElifBranch(builder: var Builder, stmt: var IfBuilder, cond: Snippet) =
  when buildNifc:
    case stmt.state
    of WaitingIf, WaitingElseIf:
      builder.add(" (elif ")
    else: assert false, $stmt.state
    builder.add(cond)
    builder.addLineEndIndent(" (stmts")
  else:
    case stmt.state
    of WaitingIf:
      builder.add("if (")
    of WaitingElseIf:
      builder.add(" else if (")
    else: assert false, $stmt.state
    builder.add(cond)
    builder.addLineEndIndent(") {")
  stmt.state = InBlock

proc initElseBranch(builder: var Builder, stmt: var IfBuilder) =
  assert stmt.state == WaitingElseIf, $stmt.state
  when buildNifc:
    builder.addLineEndIndent(" (else (stmts")
  else:
    builder.addLineEndIndent(" else {")
  stmt.state = InBlock

proc finishBranch(builder: var Builder, stmt: var IfBuilder) =
  when buildNifc:
    builder.addDedent("))")
  else:
    builder.addDedent("}")
  stmt.state = WaitingElseIf

template addElifBranch(builder: var Builder, stmt: var IfBuilder, cond: Snippet, body: typed) =
  initElifBranch(builder, stmt, cond)
  body
  finishBranch(builder, stmt)

template addElseBranch(builder: var Builder, stmt: var IfBuilder, body: typed) =
  initElseBranch(builder, stmt)
  body
  finishBranch(builder, stmt)

type WhileBuilder = object
  inside: bool

proc initWhileStmt(builder: var Builder, cond: Snippet): WhileBuilder =
  when buildNifc:
    builder.add("(while ")
    builder.add(cond)
    builder.addLineEndIndent(" (stmts")
  else:
    builder.add("while (")
    builder.add(cond)
    builder.addLineEndIndent(") {")
  result = WhileBuilder(inside: true)

proc finishWhileStmt(builder: var Builder, stmt: var WhileBuilder) =
  assert stmt.inside, "while stmt not inited"
  when buildNifc:
    builder.addLineEndDedent("))")
  else:
    builder.addLineEndDedent("}")
  stmt.inside = false

template addWhileStmt(builder: var Builder, cond: Snippet, body: typed) =
  when buildNifc:
    builder.add("(while ")
    builder.add(cond)
    builder.addLineEndIndent(" (stmts")
    body
    builder.addLineEndDedent("))")
  else:
    builder.add("while (")
    builder.add(cond)
    builder.addLineEndIndent(") {")
    body
    builder.addLineEndDedent("}")

proc addInPlaceOp(builder: var Builder, binOp: TypedBinaryOp, t: Snippet, a, b: Snippet) =
  when buildNifc:
    builder.addAssignmentWithValue(a):
      builder.addOp(binOp, t, a, b)
  else:
    builder.add(a)
    builder.add(' ')
    builder.add(typedBinaryOperators[binOp])
    builder.add("= ")
    builder.add(b)
    builder.addLineEnd(";")

proc addInPlaceOp(builder: var Builder, binOp: UntypedBinaryOp, a, b: Snippet) =
  when buildNifc:
    builder.addAssignmentWithValue(a):
      builder.addOp(binOp, a, b)
  else:
    builder.add(a)
    builder.add(' ')
    builder.add(untypedBinaryOperators[binOp])
    builder.add("= ")
    builder.add(b)
    builder.addLineEnd(";")

proc cInPlaceOp(binOp: TypedBinaryOp, t: Snippet, a, b: Snippet): Snippet =
  when buildNifc:
    result = "(asgn " & a & ' ' & cOp(binOp, t, a, b) & ')'
  else:
    result = ""
    result.add(a)
    result.add(' ')
    result.add(typedBinaryOperators[binOp])
    result.add("= ")
    result.add(b)
    result.add(";\n")

proc cInPlaceOp(binOp: UntypedBinaryOp, a, b: Snippet): Snippet =
  when buildNifc:
    result = "(asgn " & a & ' ' & cOp(binOp, a, b) & ')'
  else:
    result = ""
    result.add(a)
    result.add(' ')
    result.add(untypedBinaryOperators[binOp])
    result.add("= ")
    result.add(b)
    result.add(";\n")

proc addIncr(builder: var Builder, val, typ: Snippet) =
  when buildNifc:
    builder.addInPlaceOp(Add, typ, val, cIntValue(1))
  else:
    builder.add(val)
    builder.addLineEnd("++;")

proc addDecr(builder: var Builder, val, typ: Snippet) =
  when buildNifc:
    builder.addInPlaceOp(Sub, typ, val, cIntValue(1))
  else:
    builder.add(val)
    builder.addLineEnd("--;")

proc initForRange(builder: var Builder, i, start, bound: Snippet, inclusive: bool = false) =
  when buildNifc:
    builder.addAssignment(i, start)
    builder.add("(while (")
    if inclusive:
      builder.add("le ")
    else:
      builder.add("lt ")
    builder.add(i)
    builder.add(' ')
    builder.add(bound)
    builder.addLineEndIndent(") (stmts")
  else:
    builder.add("for (")
    builder.add(i)
    builder.add(" = ")
    builder.add(start)
    builder.add("; ")
    builder.add(i)
    if inclusive:
      builder.add(" <= ")
    else:
      builder.add(" < ")
    builder.add(bound)
    builder.add("; ")
    builder.add(i)
    builder.addLineEndIndent("++) {")

proc initForStep(builder: var Builder, i, start, bound, step: Snippet, inclusive: bool = false) =
  when buildNifc:
    builder.addAssignment(i, start)
    builder.add("(while (")
    if inclusive:
      builder.add("le ")
    else:
      builder.add("lt ")
    builder.add(i)
    builder.add(' ')
    builder.add(bound)
    builder.addLineEndIndent(") (stmts")
  else:
    builder.add("for (")
    builder.add(i)
    builder.add(" = ")
    builder.add(start)
    builder.add("; ")
    builder.add(i)
    if inclusive:
      builder.add(" <= ")
    else:
      builder.add(" < ")
    builder.add(bound)
    builder.add("; ")
    builder.add(i)
    builder.add(" += ")
    builder.add(step)
    builder.addLineEndIndent(") {")

proc finishForRange(builder: var Builder, i, typ: Snippet) {.inline.} =
  when buildNifc:
    builder.addIncr(i, typ)
    builder.addLineEndDedent("))")
  else:
    builder.addLineEndDedent("}")

proc finishForStep(builder: var Builder, i, step, typ: Snippet) {.inline.} =
  when buildNifc:
    builder.addInPlaceOp(Add, typ, i, step)
    builder.addLineEndDedent("))")
  else:
    builder.addLineEndDedent("}")

template addForRangeExclusive(builder: var Builder, i, start, bound, typ: Snippet, body: typed) =
  initForRange(builder, i, start, bound, false)
  body
  finishForRange(builder, i, typ)

template addForRangeInclusive(builder: var Builder, i, start, bound, typ: Snippet, body: typed) =
  initForRange(builder, i, start, bound, true)
  body
  finishForRange(builder, i, typ)

template addSwitchStmt(builder: var Builder, val: Snippet, body: typed) =
  when buildNifc:
    builder.add("(case ")
    builder.add(val)
    builder.addNewline() # no indent
    body
    builder.addLineEnd(")")
  else:
    builder.add("switch (")
    builder.add(val)
    builder.addLineEnd(") {") # no indent
    body
    builder.addLineEnd("}")

template addSingleSwitchCase(builder: var Builder, val: Snippet, body: typed) =
  when buildNifc:
    builder.add("(of (ranges ")
    builder.add(val)
    builder.addLineEndIndent(") (stmts")
    body
    builder.addLineEndDedent("))")
  else:
    builder.add("case ")
    builder.add(val)
    builder.addLineEndIndent(":")
    body
    builder.addLineEndDedent("")

type
  SwitchCaseState = enum
    None, Of, Else, Finished
  SwitchCaseBuilder = object
    state: SwitchCaseState

template addCaseRanges(builder: var Builder, info: var SwitchCaseBuilder, body: typed) =
  if info.state != Of:
    assert info.state == None
    info.state = Of
  when buildNifc:
    builder.add("(of (ranges")
  body
  when buildNifc:
    builder.addLineEndIndent(") (stmts")

proc addCase(builder: var Builder, info: var SwitchCaseBuilder, val: Snippet) =
  if info.state != Of:
    assert info.state == None
    info.state = Of
  when buildNifc:
    builder.add(" ")
    builder.add(val)
  else:
    builder.add("case ")
    builder.add(val)
    builder.addLineEndIndent(":")

proc addCaseRange(builder: var Builder, info: var SwitchCaseBuilder, first, last: Snippet) =
  if info.state != Of:
    assert info.state == None
    info.state = Of
  when buildNifc:
    builder.add(" (range ")
    builder.add(first)
    builder.add(" ")
    builder.add(last)
    builder.add(")")
  else:
    builder.add("case ")
    builder.add(first)
    builder.add(" ... ")
    builder.add(last)
    builder.addLineEndIndent(":")

proc addCaseElse(builder: var Builder, info: var SwitchCaseBuilder) =
  assert info.state == None
  info.state = Else
  when buildNifc:
    builder.addLineEndIndent("(else (stmts")
  else:
    builder.addLineEndIndent("default:")

template addSwitchCase(builder: var Builder, info: out SwitchCaseBuilder, caseBody, body: typed) =
  info = SwitchCaseBuilder(state: None)
  caseBody
  info.state = Finished
  body
  when buildNifc:
    builder.addLineEndDedent("))")
  else:
    builder.addLineEndDedent("")

template addSwitchElse(builder: var Builder, body: typed) =
  when buildNifc:
    builder.addLineEndIndent("(else (stmts")
    body
    builder.addLineEndDedent("))")
  else:
    builder.addLineEndIndent("default:")
    body
    builder.addLineEndDedent("")

proc addBreak(builder: var Builder) =
  when buildNifc:
    builder.addLineEnd("(break)")
  else:
    builder.addLineEnd("break;")

type ScopeBuilder = object
  inside: bool

proc initScope(builder: var Builder): ScopeBuilder =
  when buildNifc:
    builder.addLineEndIndent("(scope (stmts")
  else:
    builder.addLineEndIndent("{")
  result = ScopeBuilder(inside: true)

proc finishScope(builder: var Builder, scope: var ScopeBuilder) =
  assert scope.inside, "scope not inited"
  when buildNifc:
    builder.addLineEndDedent("))")
  else:
    builder.addLineEndDedent("}")
  scope.inside = false

template addScope(builder: var Builder, body: typed) =
  when buildNifc:
    builder.addLineEndIndent("(scope (stmts")
    body
    builder.addLineEndDedent("))")
  else:
    builder.addLineEndIndent("{")
    body
    builder.addLineEndDedent("}")

proc addLabel(builder: var Builder, name: TLabel) =
  when buildNifc:
    builder.add("(lab ")
    builder.add(name)
    builder.addLineEnd(")")
  else:
    builder.add(name)
    builder.addLineEnd(": ;")

proc addReturn(builder: var Builder) =
  when buildNifc:
    builder.addLineEnd("(ret .)")
  else:
    builder.addLineEnd("return;")

proc addReturn(builder: var Builder, value: Snippet) =
  when buildNifc:
    builder.add("(ret ")
    builder.add(value)
    builder.addLineEnd(")")
  else:
    builder.add("return ")
    builder.add(value)
    builder.addLineEnd(";")

proc addGoto(builder: var Builder, label: TLabel) =
  when buildNifc:
    builder.add("(jmp ")
    builder.add(label)
    builder.addLineEnd(")")
  else:
    builder.add("goto ")
    builder.add(label)
    builder.addLineEnd(";")

proc addComputedGoto(builder: var Builder, value: Snippet) =
  when buildNifc:
    doAssert false, "not implemented in nifc"
  else:
    builder.add("goto *")
    builder.add(value)
    builder.addLineEnd(";")

template addCPragma(builder: var Builder, val: Snippet) =
  when buildNifc:
    doAssert false, "not implememented in nifc"
  else:
    builder.addNewline()
    builder.add("#pragma ")
    builder.add(val)
    builder.addNewline()

proc addDiscard(builder: var Builder, val: Snippet) =
  when buildNifc:
    builder.add("(discard ")
    builder.add(val)
    builder.addLineEnd(")")
  else:
    builder.add("(void)")
    builder.add(val)
    builder.addLineEnd(";")

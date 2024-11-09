template addAssignmentWithValue(builder: var Builder, lhs: Snippet, valueBody: typed) =
  builder.add(lhs)
  builder.add(" = ")
  valueBody
  builder.add(";\n")

template addFieldAssignmentWithValue(builder: var Builder, lhs: Snippet, name: string, valueBody: typed) =
  builder.add(lhs)
  builder.add("." & name & " = ")
  valueBody
  builder.add(";\n")

template addAssignment(builder: var Builder, lhs, rhs: Snippet) =
  builder.addAssignmentWithValue(lhs):
    builder.add(rhs)

template addFieldAssignment(builder: var Builder, lhs: Snippet, name: string, rhs: Snippet) =
  builder.addFieldAssignmentWithValue(lhs, name):
    builder.add(rhs)

template addMutualFieldAssignment(builder: var Builder, lhs, rhs: Snippet, name: string) =
  builder.addFieldAssignmentWithValue(lhs, name):
    builder.add(rhs)
    builder.add("." & name)

template addAssignment(builder: var Builder, lhs: Snippet, rhs: int | int64 | uint64 | Int128) =
  builder.addAssignmentWithValue(lhs):
    builder.addIntValue(rhs)

template addFieldAssignment(builder: var Builder, lhs: Snippet, name: string, rhs: int | int64 | uint64 | Int128) =
  builder.addFieldAssignmentWithValue(lhs, name):
    builder.addIntValue(rhs)

template addDerefFieldAssignment(builder: var Builder, lhs: Snippet, name: string, rhs: Snippet) =
  builder.add(lhs)
  builder.add("->" & name & " = ")
  builder.add(rhs)
  builder.add(";\n")

template addSubscriptAssignment(builder: var Builder, lhs: Snippet, index: Snippet, rhs: Snippet) =
  builder.add(lhs)
  builder.add("[" & index & "] = ")
  builder.add(rhs)
  builder.add(";\n")

template addStmt(builder: var Builder, stmtBody: typed) =
  ## makes an expression built by `stmtBody` into a statement
  stmtBody
  builder.add(";\n")

proc addCallStmt(builder: var Builder, callee: Snippet, args: varargs[Snippet]) =
  builder.addStmt():
    builder.addCall(callee, args)

# XXX blocks need indent tracker in `Builder` object

template addSingleIfStmt(builder: var Builder, cond: Snippet, body: typed) =
  builder.add("if (")
  builder.add(cond)
  builder.add(") {\n")
  body
  builder.add("}\n")

template addSingleIfStmtWithCond(builder: var Builder, condBody: typed, body: typed) =
  builder.add("if (")
  condBody
  builder.add(") {\n")
  body
  builder.add("}\n")

proc initIfStmt(builder: var Builder): IfBuilder =
  IfBuilder(state: WaitingIf)

proc finishIfStmt(builder: var Builder, stmt: IfBuilder) =
  assert stmt.state != InBlock
  builder.add("\n")

template addIfStmt(builder: var Builder, stmt: out IfBuilder, body: typed) =
  stmt = initIfStmt(builder)
  body
  finishIfStmt(builder, stmt)

proc initElifBranch(builder: var Builder, stmt: var IfBuilder, cond: Snippet) =
  case stmt.state
  of WaitingIf:
    builder.add("if (")
  of WaitingElseIf:
    builder.add(" else if (")
  else: assert false, $stmt.state
  builder.add(cond)
  builder.add(") {\n")
  stmt.state = InBlock

proc initElseBranch(builder: var Builder, stmt: var IfBuilder) =
  assert stmt.state == WaitingElseIf, $stmt.state
  builder.add(" else {\n")
  stmt.state = InBlock

proc finishBranch(builder: var Builder, stmt: var IfBuilder) =
  builder.add("}")
  stmt.state = WaitingElseIf

template addElifBranch(builder: var Builder, stmt: var IfBuilder, cond: Snippet, body: typed) =
  initElifBranch(builder, stmt, cond)
  body
  finishBranch(builder, stmt)

template addElseBranch(builder: var Builder, stmt: var IfBuilder, body: typed) =
  initElseBranch(builder, stmt)
  body
  finishBranch(builder, stmt)

proc initForRange(builder: var Builder, i, start, bound: Snippet, inclusive: bool = false) =
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
  builder.add("++) {\n")

proc initForStep(builder: var Builder, i, start, bound, step: Snippet, inclusive: bool = false) =
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
  builder.add(") {\n")

proc finishFor(builder: var Builder) {.inline.} =
  builder.add("}\n")

template addForRangeExclusive(builder: var Builder, i, start, bound: Snippet, body: typed) =
  initForRange(builder, i, start, bound, false)
  body
  finishFor(builder)

template addForRangeInclusive(builder: var Builder, i, start, bound: Snippet, body: typed) =
  initForRange(builder, i, start, bound, true)
  body
  finishFor(builder)

template addSwitchStmt(builder: var Builder, val: Snippet, body: typed) =
  builder.add("switch (")
  builder.add(val)
  builder.add(") {\n")
  body
  builder.add("}\n")

template addSingleSwitchCase(builder: var Builder, val: Snippet, body: typed) =
  builder.add("case ")
  builder.add(val)
  builder.add(":\n")
  body

type
  SwitchCaseState = enum
    None, Of, Else, Finished
  SwitchCaseBuilder = object
    state: SwitchCaseState

proc addCase(builder: var Builder, info: var SwitchCaseBuilder, val: Snippet) =
  if info.state != Of:
    assert info.state == None
    info.state = Of
  builder.add("case ")
  builder.add(val)
  builder.add(":\n")

proc addCaseRange(builder: var Builder, info: var SwitchCaseBuilder, first, last: Snippet) =
  if info.state != Of:
    assert info.state == None
    info.state = Of
  builder.add("case ")
  builder.add(first)
  builder.add(" ... ")
  builder.add(last)
  builder.add(":\n")

proc addCaseElse(builder: var Builder, info: var SwitchCaseBuilder) =
  assert info.state == None
  info.state = Else
  builder.add("default:\n")

template addSwitchCase(builder: var Builder, info: out SwitchCaseBuilder, caseBody, body: typed) =
  info = SwitchCaseBuilder(state: None)
  caseBody
  info.state = Finished
  body

template addSwitchElse(builder: var Builder, body: typed) =
  builder.add("default:\n")
  body

proc addBreak(builder: var Builder) =
  builder.add("break;\n")

type ScopeBuilder = object
  inside: bool

proc initScope(builder: var Builder): ScopeBuilder =
  builder.add("{\n")
  result = ScopeBuilder(inside: true)

proc finishScope(builder: var Builder, scope: var ScopeBuilder) =
  assert scope.inside, "scope not inited"
  builder.add("}\n")
  scope.inside = false

template addScope(builder: var Builder, body: typed) =
  builder.add("{\n")
  body
  builder.add("}\n")

type WhileBuilder = object
  inside: bool

proc initWhileStmt(builder: var Builder, cond: Snippet): WhileBuilder =
  builder.add("while (")
  builder.add(cond)
  builder.add(") {\n")
  result = WhileBuilder(inside: true)

proc finishWhileStmt(builder: var Builder, stmt: var WhileBuilder) =
  assert stmt.inside, "while stmt not inited"
  builder.add("}\n")
  stmt.inside = false

template addWhileStmt(builder: var Builder, cond: Snippet, body: typed) =
  builder.add("while (")
  builder.add(cond)
  builder.add(") {\n")
  body
  builder.add("}\n")

proc addLabel(builder: var Builder, name: TLabel) =
  builder.add(name)
  builder.add(": ;\n")

proc addReturn(builder: var Builder) =
  builder.add("return;\n")

proc addReturn(builder: var Builder, value: Snippet) =
  builder.add("return ")
  builder.add(value)
  builder.add(";\n")

proc addGoto(builder: var Builder, label: TLabel) =
  builder.add("goto ")
  builder.add(label)
  builder.add(";\n")

proc addComputedGoto(builder: var Builder, value: Snippet) =
  builder.add("goto *")
  builder.add(value)
  builder.add(";\n")

proc addIncr(builder: var Builder, val: Snippet) =
  builder.add(val)
  builder.add("++;\n")

proc addDecr(builder: var Builder, val: Snippet) =
  builder.add(val)
  builder.add("--;\n")

proc addInPlaceOp(builder: var Builder, binOp: TypedBinaryOp, t: Snippet, a, b: Snippet) =
  builder.add(a)
  builder.add(' ')
  builder.add(typedBinaryOperators[binOp])
  builder.add("= ")
  builder.add(b)
  builder.add(";\n")

proc addInPlaceOp(builder: var Builder, binOp: UntypedBinaryOp, a, b: Snippet) =
  builder.add(a)
  builder.add(' ')
  builder.add(untypedBinaryOperators[binOp])
  builder.add("= ")
  builder.add(b)
  builder.add(";\n")

proc cInPlaceOp(binOp: TypedBinaryOp, t: Snippet, a, b: Snippet): Snippet =
  result = ""
  result.add(a)
  result.add(' ')
  result.add(typedBinaryOperators[binOp])
  result.add("= ")
  result.add(b)
  result.add(";\n")

proc cInPlaceOp(binOp: UntypedBinaryOp, a, b: Snippet): Snippet =
  result = ""
  result.add(a)
  result.add(' ')
  result.add(untypedBinaryOperators[binOp])
  result.add("= ")
  result.add(b)
  result.add(";\n")

template addCPragma(builder: var Builder, val: Snippet) =
  builder.add("\n#pragma ")
  builder.add(val)
  builder.add("\n")

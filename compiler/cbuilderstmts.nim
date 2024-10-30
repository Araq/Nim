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

type IfStmt = object
  needsElse: bool

template addIfStmt(builder: var Builder, stmt: out IfStmt, body: typed) =
  stmt = IfStmt(needsElse: false)
  body
  builder.add("\n")

template addElifBranch(builder: var Builder, stmt: var IfStmt, cond: Snippet, body: typed) =
  if stmt.needsElse:
    builder.add(" else ")
  else:
    stmt.needsElse = true
  builder.add("if (")
  builder.add(cond)
  builder.add(") {\n")
  body
  builder.add("}")

template addElseBranch(builder: var Builder, stmt: var IfStmt, body: typed) =
  assert stmt.needsElse
  builder.add(" else {\n")
  body
  builder.add("}")

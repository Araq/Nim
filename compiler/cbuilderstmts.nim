template addAssignment(builder: var Builder, lhs: Snippet, valueBody: typed) =
  builder.add(lhs)
  builder.add(" = ")
  valueBody
  builder.add(";\n")

template addFieldAssignment(builder: var Builder, lhs: Snippet, name: string, valueBody: typed) =
  builder.add(lhs)
  builder.add("." & name & " = ")
  valueBody
  builder.add(";\n")

template addDerefFieldAssignment(builder: var Builder, lhs: Snippet, name: string, valueBody: typed) =
  builder.add(lhs)
  builder.add("->" & name & " = ")
  valueBody
  builder.add(";\n")

template addSubscriptAssignment(builder: var Builder, lhs: Snippet, index: Snippet, valueBody: typed) =
  builder.add(lhs)
  builder.add("[" & index & "] = ")
  valueBody
  builder.add(";\n")

template addStmt(builder: var Builder, stmtBody: typed) =
  ## makes an expression built by `stmtBody` into a statement
  stmtBody
  builder.add(";\n")

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

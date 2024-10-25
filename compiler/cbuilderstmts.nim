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

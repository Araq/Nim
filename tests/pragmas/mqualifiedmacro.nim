template t*(x:untyped): untyped = 
  echo "template t"

import macros
macro m*(name: static string, x: untyped): untyped =
  let newName = ident(name)
  result = quote do:
    type `newName` = object
  if result.kind == nnkStmtList:
    result = result[^1]

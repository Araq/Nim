# Dump the contents of a NimNode

import macros

proc dumpit(n: NimNode): string {.compileTime.} =
  if n == nil: return "nil"
  result = $n.kind
  add(result, "(")
  case n.kind
  of nnkEmpty: discard # same as nil node in this representation
  of nnkNilLit:                  add(result, "nil")
  of nnkCharLit..nnkInt64Lit:    add(result, $n.intVal)
  of nnkFloatLit..nnkFloat64Lit: add(result, $n.floatVal)
  of nnkStrLit..nnkTripleStrLit, nnkIdent: add(result, $n.strVal)
  of nnkSym, nnkNone:            assert false
  else:
    add(result, dumpit(n[0]))
    for j in 1..n.len-1:
      add(result, ", ")
      add(result, dumpit(n[j]))
  add(result, ")")

macro dumpAST(n): untyped =
  # dump AST as a side-effect and return the inner node
  let n = callsite()
  echo dumpit(n)
  result = n[1]

dumpAST:
  proc add(x, y: int): int =
    return x + y

  proc sub(x, y: int): int = return x - y



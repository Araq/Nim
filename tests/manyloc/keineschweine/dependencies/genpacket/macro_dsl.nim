import macros

#Inline macro.add() to allow for easier nesting
proc und*(a: NimNode; b: NimNode): NimNode {.compileTime.} =
  a.add(b)
  result = a
proc und*(a: NimNode; b: varargs[NimNode]): NimNode {.compileTime.} =
  a.add(b)
  result = a

proc `^`*(a: string): NimNode {.compileTime.} =
  ## new ident node
  result = newIdentNode(a)
proc `[]`*(a, b: NimNode): NimNode {.compileTime.} =
  ## new bracket expression: node[node] not to be confused with node[indx]
  result = newNimNode(nnkBracketExpr).und(a, b)
proc `:=`*(left, right: NimNode): NimNode {.compileTime.} =
  ## new Asgn node:  left = right
  result = newNimNode(nnkAsgn).und(left, right)

proc lit*(a: string): NimNode {.compileTime.} =
  result = newStrLitNode(a)
proc lit*(a: int): NimNode {.compileTime.} =
  result = newIntLitNode(a)
proc lit*(a: float): NimNode {.compileTime.} =
  result = newFloatLitNode(a)
proc lit*(a: char): NimNode {.compileTime.} =
  result = newNimNode(nnkCharLit)
  result.intval = a.ord

proc emptyNode*(): NimNode {.compileTime.} =
  result = newNimNode(nnkEmpty)

proc dot*(left, right: NimNode): NimNode {.compileTime.} =
  result = newNimNode(nnkDotExpr).und(left, right)
proc prefix*(a: string, b: NimNode): NimNode {.compileTime.} =
  result = newNimNode(nnkPrefix).und(newIdentNode(a), b)

proc quoted2ident*(a: NimNode): NimNode {.compileTime.} =
  if a.kind != nnkAccQuoted:
    return a
  var pname = ""
  for piece in 0..a.len - 1:
    pname.add($a[piece].strVal)
  result = ^pname


macro `?`(a: untyped): untyped =
  ## Character literal ?A #=> 'A'
  result = ($a[1].strVal)[0].lit
## echo(?F,?a,?t,?t,?y)

when false:
  macro foo(x: untyped) =
    result = newNimNode(nnkStmtList)
    result.add(newNimNode(nnkCall).und(!!"echo", "Hello thar".lit))
    result.add(newCall("echo", lit("3 * 45 = "), (3.lit.infix("*", 45.lit))))
    let stmtlist = x[1]
    for i in countdown(len(stmtlist)-1, 0):
      result.add(stmtlist[i])
  foo:
    echo y, " * 2 = ", y * 2
    let y = 320


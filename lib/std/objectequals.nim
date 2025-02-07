## This module implements a generic `==` operator for any given object type
## based on the given fields. `-d:nimPreviewSlimSystem` is recommended to use,
## the original version in `system` did not support object variants.

import std/macros

proc build(val1, val2, body, rl: NimNode, name1, name2: string): NimNode =
  template useField(f): untyped =
    newBlockStmt(
      newStmtList(
        newLetStmt(ident name1, newDotExpr(val1, f)),
        newLetStmt(ident name2, newDotExpr(val2, f)),
        copy body))
  result = newStmtList()
  for r in rl:
    case r.kind
    of nnkIdentDefs:
      for f in r[0..^3]:
        result.add(useField(f))
    of nnkRecCase:
      let kind = r[0][0]
      result.add(useField(kind))
      result.add quote do:
        assert `val1`.`kind` == `val2`.`kind`, "case discriminators must be equal for zipFields"
      var cs = newTree(nnkCaseStmt, newDotExpr(val1, kind))
      for b in r[1..^1]:
        var nb = copy(b)
        nb[^1] = build(val1, val2, body, nb[^1], name1, name2)
        cs.add(nb)
      result.add(cs)
    of nnkRecWhen:
      var ws = newTree(nnkWhenStmt)
      for b in r[1..^1]:
        var nb = copy(b)
        nb[^1] = build(val1, val2, body, nb[^1], name1, name2)
        ws.add(nb)
      result.add(ws)
    else: error("unexpected record node " & $r.kind, r)

macro zipFields(val1, val2: object, name1, name2, body: untyped): untyped =
  # requires that `val1` and `val2` have the same case branches!
  var t = val1.getTypeImpl()
  t.expectKind nnkObjectTy
  result = build(val1, val2, body, t[^1], $name1, $name2)

proc `==`*[T: object](x, y: T): bool =
  ## Generic `==` operator for objects that is lifted from the fields
  ## of `x` and `y`. Works with object variants.
  mixin `==`
  zipFields(x, y, xf, yf):
    if xf != yf:
      return false
  true

#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements experimental features which may soon be moved to
## the system module (or other more appropriate modules).

import macros

proc createProcType(p, b: NimNode): NimNode {.compileTime.} =
  #echo treeRepr(p)
  #echo treeRepr(b)
  result = newNimNode(nnkProcTy)
  var formalParams = newNimNode(nnkFormalParams)

  formalParams.add b

  case p.kind
  of nnkPar:
    for i in 0 ..< p.len:
      let ident = p[i]
      var identDefs = newNimNode(nnkIdentDefs)
      case ident.kind
      of nnkExprColonExpr:
        identDefs.add ident[0]
        identDefs.add ident[1]
      else:
        identDefs.add newIdentNode("i" & $i)
        identDefs.add(ident)
      identDefs.add newEmptyNode()
      formalParams.add identDefs
  else:
    var identDefs = newNimNode(nnkIdentDefs)
    identDefs.add newIdentNode("i0")
    identDefs.add(p)
    identDefs.add newEmptyNode()
    formalParams.add identDefs

  result.add formalParams
  result.add newEmptyNode()
  #echo(treeRepr(result))
  #echo(result.toStrLit())

macro `=>`*(p, b: untyped): untyped =
  ## Syntax sugar for anonymous procedures.
  ##
  ## .. code-block:: nim
  ##
  ##   proc passTwoAndTwo(f: (int, int) -> int): int =
  ##     f(2, 2)
  ##
  ##   passTwoAndTwo((x, y) => x + y) # 4

  #echo treeRepr(p)
  #echo(treeRepr(b))
  var params: seq[NimNode] = @[newIdentNode("auto")]

  case p.kind
  of nnkPar:
    for c in children(p):
      var identDefs = newNimNode(nnkIdentDefs)
      case c.kind
      of nnkExprColonExpr:
        identDefs.add(c[0])
        identDefs.add(c[1])
        identDefs.add(newEmptyNode())
      of nnkIdent:
        identDefs.add(c)
        identDefs.add(newIdentNode("auto"))
        identDefs.add(newEmptyNode())
      of nnkInfix:
        if c[0].kind == nnkIdent and c[0].ident == !"->":
          var procTy = createProcType(c[1], c[2])
          params[0] = procTy[0][0]
          for i in 1 ..< procTy[0].len:
            params.add(procTy[0][i])
        else:
          error("Expected proc type (->) got (" & $c[0].ident & ").")
        break
      else:
        echo treeRepr c
        error("Incorrect procedure parameter list.")
      params.add(identDefs)
  of nnkIdent:
    var identDefs = newNimNode(nnkIdentDefs)
    identDefs.add(p)
    identDefs.add(newIdentNode("auto"))
    identDefs.add(newEmptyNode())
    params.add(identDefs)
  of nnkInfix:
    if p[0].kind == nnkIdent and p[0].ident == !"->":
      var procTy = createProcType(p[1], p[2])
      params[0] = procTy[0][0]
      for i in 1 ..< procTy[0].len:
        params.add(procTy[0][i])
    else:
      error("Expected proc type (->) got (" & $p[0].ident & ").")
  else:
    error("Incorrect procedure parameter list.")
  result = newProc(params = params, body = b, procType = nnkLambda)
  #echo(result.treeRepr)
  #echo(result.toStrLit())
  #return result # TODO: Bug?

macro `->`*(p, b: untyped): untyped =
  ## Syntax sugar for procedure types.
  ##
  ## .. code-block:: nim
  ##
  ##   proc pass2(f: (float, float) -> float): float =
  ##     f(2, 2)
  ##
  ##   # is the same as:
  ##
  ##   proc pass2(f: proc (x, y: float): float): float =
  ##     f(2, 2)

  result = createProcType(p, b)

macro dump*(x: typed): untyped =
  ## Dumps the content of an expression, useful for debugging.
  ## It accepts any expression and prints a textual representation
  ## of the tree representing the expression - as it would appear in
  ## source code - together with the value of the expression.
  ##
  ## As an example,
  ##
  ## .. code-block:: nim
  ##   let
  ##     x = 10
  ##     y = 20
  ##   dump(x + y)
  ##
  ## will print ``x + y = 30``.
  let s = x.toStrLit
  let r = quote do:
    debugEcho `s`, " = ", `x`
  return r

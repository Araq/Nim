#
#
#           The Nim Compiler
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# tree helper routines

import
  ast, wordrecg, idents

proc cyclicTreeAux(n: PNode, visited: var seq[PNode]): bool =
  if n == nil: return
  for v in visited:
    if v == n: return true
  if not (n.kind in {nkEmpty..nkNilLit}):
    visited.add(n)
    for nSon in n.sons:
      if cyclicTreeAux(nSon, visited): return true
    discard visited.pop()

proc cyclicTree*(n: PNode): bool =
  var visited: seq[PNode] = @[]
  cyclicTreeAux(n, visited)

proc exprStructuralEquivalent*(a, b: PNode; strictSymEquality=false): bool =
  if a == b:
    result = true
  elif (a != nil) and (b != nil) and (a.kind == b.kind):
    case a.kind
    of nkSym:
      if strictSymEquality:
        result = a.sym == b.sym
      else:
        # don't go nuts here: same symbol as string is enough:
        result = a.sym.name.id == b.sym.name.id
    of nkIdent: result = a.ident.id == b.ident.id
    of nkCharLit..nkUInt64Lit: result = a.intVal == b.intVal
    of nkFloatLit..nkFloat64Lit: result = a.floatVal == b.floatVal
    of nkStrLit..nkTripleStrLit: result = a.strVal == b.strVal
    of nkCommentStmt: result = a.comment == b.comment
    of nkEmpty, nkNilLit, nkType: result = true
    else:
      if a.len == b.len:
        for i in 0..<a.len:
          if not exprStructuralEquivalent(a[i], b[i],
                                          strictSymEquality): return
        result = true

proc sameTree*(a, b: PNode): bool =
  if a == b:
    result = true
  elif a != nil and b != nil and a.kind == b.kind:
    if a.flags != b.flags: return
    if a.info.line != b.info.line: return
    if a.info.col != b.info.col:
      return                  #if a.info.fileIndex <> b.info.fileIndex then exit;
    case a.kind
    of nkSym:
      # don't go nuts here: same symbol as string is enough:
      result = a.sym.name.id == b.sym.name.id
    of nkIdent: result = a.ident.id == b.ident.id
    of nkCharLit..nkUInt64Lit: result = a.intVal == b.intVal
    of nkFloatLit..nkFloat64Lit: result = a.floatVal == b.floatVal
    of nkStrLit..nkTripleStrLit: result = a.strVal == b.strVal
    of nkEmpty, nkNilLit, nkType: result = true
    else:
      if a.len == b.len:
        for i in 0..<a.len:
          if not sameTree(a[i], b[i]): return
        result = true

proc getMagic*(op: PNode): TMagic =
  case op.kind
  of nkCallKinds:
    case op[0].kind
    of nkSym: result = op[0].sym.magic
    else: result = mNone
  else: result = mNone

proc isConstExpr*(n: PNode): bool =
  const atomKinds = {nkCharLit..nkNilLit} # Char, Int, UInt, Str, Float and Nil literals
  n.kind in atomKinds or nfAllConst in n.flags

proc isCaseObj*(n: PNode): bool =
  if n.kind == nkRecCase: return true
  for i in 0..<n.safeLen:
    if n[i].isCaseObj: return true

proc isDeepConstExpr*(n: PNode; preventInheritance = false): bool =
  case n.kind
  of nkCharLit..nkNilLit:
    result = true
  of nkExprEqExpr, nkExprColonExpr, nkHiddenStdConv, nkHiddenSubConv:
    result = isDeepConstExpr(n[1], preventInheritance)
  of nkCurly, nkBracket, nkPar, nkTupleConstr, nkObjConstr, nkClosure, nkRange:
    for i in ord(n.kind == nkObjConstr)..<n.len:
      if not isDeepConstExpr(n[i], preventInheritance): return false
    if n.typ.isNil: result = true
    else:
      let t = n.typ.skipTypes({tyGenericInst, tyDistinct, tyAlias, tySink, tyOwned})
      if t.kind in {tyRef, tyPtr} or tfUnion in t.flags: return false
      if t.kind == tyObject:
        if preventInheritance and t[0] != nil:
          result = false
        elif isCaseObj(t.n):
          result = false
        else:
          result = true
      else:
        result = true
  else: discard

proc isRange*(n: PNode): bool {.inline.} =
  if n.kind in nkCallKinds:
    let callee = n[0]
    if (callee.kind == nkIdent and callee.ident.id == ord(wDotDot)) or
       (callee.kind == nkSym and callee.sym.name.id == ord(wDotDot)) or
       (callee.kind in {nkClosedSymChoice, nkOpenSymChoice} and
        callee[1].sym.name.id == ord(wDotDot)):
      result = true

proc whichPragma*(n: PNode): TSpecialWord =
  # echo "whichPragma"
  let key = if n.kind in nkPragmaCallKinds and n.len > 0: n[0] else: n
  # echo "key"
  # echo key.kind
  if key.kind == nkIdent: 
    let ident = key.ident
    # echo "ident: " & ident.s
    let keyword = whichKeyword(ident)
    # echo keyword
    result = keyword

proc findPragma*(n: PNode, which: TSpecialWord): PNode =
  if n.kind == nkPragma:
    for son in n:
      if whichPragma(son) == which:
        return son

proc effectSpec*(n: PNode, effectType: TSpecialWord): PNode =
  for i in 0..<n.len:
    var it = n[i]
    if it.kind == nkExprColonExpr and whichPragma(it) == effectType:
      result = it[1]
      if result.kind notin {nkCurly, nkBracket}:
        result = newNodeI(nkCurly, result.info)
        result.add(it[1])
      return

proc unnestStmts(n, result: PNode) =
  if n.kind == nkStmtList:
    for x in items(n): unnestStmts(x, result)
  elif n.kind notin {nkCommentStmt, nkNilLit}:
    result.add(n)

proc flattenStmts*(n: PNode): PNode =
  result = newNodeI(nkStmtList, n.info)
  unnestStmts(n, result)
  if result.len == 1:
    result = result[0]

proc extractRange*(k: TNodeKind, n: PNode, a, b: int): PNode =
  result = newNodeI(k, n.info, b-a+1)
  for i in 0..b-a: result[i] = n[i+a]

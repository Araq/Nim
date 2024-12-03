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
  result = false
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

proc sameFloatIgnoreNan(a, b: BiggestFloat): bool {.inline.} =
  ## ignores NaN semantics, but ensures 0.0 == -0.0, see #13730
  cast[uint64](a) == cast[uint64](b) or a == b

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
    of nkFloatLit..nkFloat64Lit: result = sameFloatIgnoreNan(a.floatVal, b.floatVal)
    of nkStrLit..nkTripleStrLit: result = a.strVal == b.strVal
    of nkCommentStmt: result = a.comment == b.comment
    of nkEmpty, nkNilLit, nkType: result = true
    else:
      if a.len == b.len:
        for i in 0..<a.len:
          if not exprStructuralEquivalent(a[i], b[i],
                                          strictSymEquality): return
        result = true
      else:
        result = false
  else:
    result = false

proc sameTree*(a, b: PNode): bool =
  result = false
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
    of nkFloatLit..nkFloat64Lit: result = sameFloatIgnoreNan(a.floatVal, b.floatVal)
    of nkStrLit..nkTripleStrLit: result = a.strVal == b.strVal
    of nkEmpty, nkNilLit, nkType: result = true
    else:
      if a.len == b.len:
        for i in 0..<a.len:
          if not sameTree(a[i], b[i]): return
        result = true

proc getMagic*(op: PNode): TMagic =
  if op == nil: return mNone
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
  result = false
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
        if preventInheritance and t.baseClass != nil:
          result = false
        elif isCaseObj(t.n):
          result = false
        else:
          result = true
      else:
        result = true
  else: result = false

proc isRange*(n: PNode): bool {.inline.} =
  if n.kind in nkCallKinds:
    let callee = n[0]
    if (callee.kind == nkIdent and callee.ident.id == ord(wDotDot)) or
       (callee.kind == nkSym and callee.sym.name.id == ord(wDotDot)) or
       (callee.kind in {nkClosedSymChoice, nkOpenSymChoice} and
        callee[1].sym.name.id == ord(wDotDot)):
      result = true
    else:
      result = false
  else:
    result = false

proc whichPragma*(n: PNode): TSpecialWord =
  let key = if n.kind in nkPragmaCallKinds and n.len > 0: n[0] else: n
  case key.kind
  of nkIdent: result = whichKeyword(key.ident)
  of nkSym: result = whichKeyword(key.sym.name)
  of nkCast: return wCast
  of nkClosedSymChoice, nkOpenSymChoice:
    return whichPragma(key[0])
  of nkBracketExpr:
    if n.kind notin nkPragmaCallKinds: return wInvalid
    result = whichPragma(key[0])
    if result notin {wHint, wHintAsError, wWarning, wWarningAsError}:
      # note bracket pragmas, see processNote
      result = wInvalid
    return
  else: return wInvalid
  if result in nonPragmaWordsLow..nonPragmaWordsHigh:
    result = wInvalid

proc isNoSideEffectPragma*(n: PNode): bool =
  var k = whichPragma(n)
  if k == wCast:
    k = whichPragma(n[1])
  result = k == wNoSideEffect

proc findPragma*(n: PNode, which: TSpecialWord): PNode =
  result = nil
  if n.kind == nkPragma:
    for son in n:
      if whichPragma(son) == which:
        return son

proc effectSpec*(n: PNode, effectType: TSpecialWord): PNode =
  result = nil
  for i in 0..<n.len:
    var it = n[i]
    if it.kind == nkExprColonExpr and whichPragma(it) == effectType:
      result = it[1]
      if result.kind notin {nkCurly, nkBracket}:
        result = newNodeI(nkCurly, result.info)
        result.add(it[1])
      return

proc propSpec*(n: PNode, effectType: TSpecialWord): PNode =
  result = nil
  for i in 0..<n.len:
    var it = n[i]
    if it.kind == nkExprColonExpr and whichPragma(it) == effectType:
      return it[1]

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

proc getRoot*(n: PNode): PSym =
  ## ``getRoot`` takes a *path* ``n``. A path is an lvalue expression
  ## like ``obj.x[i].y``. The *root* of a path is the symbol that can be
  ## determined as the owner; ``obj`` in the example.
  case n.kind
  of nkSym:
    if n.sym.kind in {skVar, skResult, skTemp, skLet, skForVar, skParam}:
      result = n.sym
    else:
      result = nil
  of nkDotExpr, nkBracketExpr, nkHiddenDeref, nkDerefExpr,
      nkObjUpConv, nkObjDownConv, nkCheckedFieldExpr, nkHiddenAddr, nkAddr:
    result = getRoot(n[0])
  of nkHiddenStdConv, nkHiddenSubConv, nkConv:
    result = getRoot(n[1])
  of nkCallKinds:
    if getMagic(n) == mSlice: result = getRoot(n[1])
    else: result = nil
  else: result = nil

proc stupidStmtListExpr*(n: PNode): bool =
  for i in 0..<n.len-1:
    if n[i].kind notin {nkEmpty, nkCommentStmt}: return false
  result = true

proc dontInlineConstant*(orig, cnst: PNode): bool {.inline.} =
  # symbols that expand to a complex constant (array, etc.) should not be
  # inlined, unless it's the empty array:
  result = cnst.kind in {nkCurly, nkPar, nkTupleConstr, nkBracket, nkObjConstr} and
           cnst.len > ord(cnst.kind == nkObjConstr)

proc isRunnableExamples*(n: PNode): bool =
  # Templates and generics don't perform symbol lookups.
  result = n.kind == nkSym and n.sym.magic == mRunnableExamples or
    n.kind == nkIdent and n.ident.id == ord(wRunnableExamples)

proc skipAddr*(n: PNode): PNode {.inline.} =
  result = if n.kind in {nkAddr, nkHiddenAddr}: n[0] else: n

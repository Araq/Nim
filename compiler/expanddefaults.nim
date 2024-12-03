#
#
#           The Nim Compiler
#        (c) Copyright 2023 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import lineinfos, ast, types

proc caseObjDefaultBranch*(obj: PNode; branch: Int128): int =
  result = 0
  for i in 1 ..< obj.len:
    for j in 0 .. obj[i].len - 2:
      if obj[i][j].kind == nkRange:
        let x = getOrdValue(obj[i][j][0])
        let y = getOrdValue(obj[i][j][1])
        if branch >= x and branch <= y:
          return i
      elif getOrdValue(obj[i][j]) == branch:
        return i
    if obj[i].len == 1:
      # else branch
      return i
  return 1

template newZero(t: PType; info: TLineInfo; k = nkIntLit): PNode = newNodeIT(k, info, t)

proc expandDefault*(t: PType; info: TLineInfo): PNode

proc expandField(s: PSym; info: TLineInfo): PNode =
  result = newNodeIT(nkExprColonExpr, info, s.typ)
  result.add newSymNode(s)
  result.add expandDefault(s.typ, info)

proc expandDefaultN(n: PNode; info: TLineInfo; res: PNode) =
  case n.kind
  of nkRecList:
    for i in 0..<n.len:
      expandDefaultN(n[i], info, res)
  of nkRecCase:
    res.add expandField(n[0].sym, info)
    var branch = Zero
    let constOrNil = n[0].sym.astdef
    if constOrNil != nil:
      branch = getOrdValue(constOrNil)

    let selectedBranch = caseObjDefaultBranch(n, branch)
    let b = lastSon(n[selectedBranch])
    expandDefaultN b, info, res
  of nkSym:
    res.add expandField(n.sym, info)
  else:
    discard

proc expandDefaultObj(t: PType; info: TLineInfo; res: PNode) =
  if t.baseClass != nil:
    expandDefaultObj(t.baseClass, info, res)
  expandDefaultN(t.n, info, res)

proc expandDefault(t: PType; info: TLineInfo): PNode =
  case t.kind
  of tyInt:     result = newZero(t, info, nkIntLit)
  of tyInt8:    result = newZero(t, info, nkInt8Lit)
  of tyInt16:   result = newZero(t, info, nkInt16Lit)
  of tyInt32:   result = newZero(t, info, nkInt32Lit)
  of tyInt64:   result = newZero(t, info, nkInt64Lit)
  of tyUInt:    result = newZero(t, info, nkUIntLit)
  of tyUInt8:   result = newZero(t, info, nkUInt8Lit)
  of tyUInt16:  result = newZero(t, info, nkUInt16Lit)
  of tyUInt32:  result = newZero(t, info, nkUInt32Lit)
  of tyUInt64:  result = newZero(t, info, nkUInt64Lit)
  of tyFloat:   result = newZero(t, info, nkFloatLit)
  of tyFloat32: result = newZero(t, info, nkFloat32Lit)
  of tyFloat64: result = newZero(t, info, nkFloat64Lit)
  of tyFloat128: result = newZero(t, info, nkFloat64Lit)
  of tyChar:    result = newZero(t, info, nkCharLit)
  of tyBool:    result = newZero(t, info, nkIntLit)
  of tyEnum:
    # Could use low(T) here to finally fix old language quirks
    result = newZero(t, info, nkIntLit)
  of tyRange:
    # Could use low(T) here to finally fix old language quirks
    result = expandDefault(skipModifier t, info)
  of tyVoid: result = newZero(t, info, nkEmpty)
  of tySink, tyGenericInst, tyDistinct, tyAlias, tyOwned:
    result = expandDefault(t.skipModifier, info)
  of tyOrdinal, tyGenericBody, tyGenericParam, tyInferred, tyStatic:
    if t.hasElementType:
      result = expandDefault(t.skipModifier, info)
    else:
      result = newZero(t, info, nkEmpty)
  of tyFromExpr:
    if t.n != nil and t.n.typ != nil:
      result = expandDefault(t.n.typ, info)
    else:
      result = newZero(t, info, nkEmpty)
  of tyArray:
    result = newZero(t, info, nkBracket)
    let n = toInt64(lengthOrd(nil, t))
    for i in 0..<n:
      result.add expandDefault(t.elementType, info)
  of tyPtr, tyRef, tyProc, tyPointer, tyCstring:
    result = newZero(t, info, nkNilLit)
  of tyVar, tyLent:
    let e = t.elementType
    if e.skipTypes(abstractInst).kind in {tyOpenArray, tyVarargs}:
      # skip the modifier, `var openArray` is a (ptr, len) pair too:
      result = expandDefault(e, info)
    else:
      result = newZero(e, info, nkNilLit)
  of tySet:
    result = newZero(t, info, nkCurly)
  of tyObject:
    result = newNodeIT(nkObjConstr, info, t)
    result.add newNodeIT(nkType, info, t)
    expandDefaultObj(t, info, result)
  of tyTuple:
    result = newZero(t, info, nkTupleConstr)
    for it in t.kids:
      result.add expandDefault(it, info)
  of tyVarargs, tyOpenArray, tySequence, tyUncheckedArray:
    result = newZero(t, info, nkBracket)
  of tyString:
    result = newZero(t, info, nkStrLit)
  of tyNone, tyEmpty, tyUntyped, tyTyped, tyTypeDesc,
     tyNil, tyGenericInvocation, tyError, tyBuiltInTypeClass,
     tyUserTypeClass, tyUserTypeClassInst, tyCompositeTypeClass,
     tyAnd, tyOr, tyNot, tyAnything, tyConcept, tyIterable, tyForward:
    result = newZero(t, info, nkEmpty) # bug indicator

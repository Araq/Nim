#
#
#           The Nim Compiler
#        (c) Copyright 2020 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Implementation of the check that `recover` needs, see
## https://github.com/nim-lang/RFCs/issues/244 for more details.

import
  ast, types, renderer, intsets

proc canAlias(arg, ret: PType; marker: var IntSet): bool

proc canAliasN(arg: PType; n: PNode; marker: var IntSet): bool =
  case n.kind
  of nkRecList:
    for i in 0..<n.len:
      result = canAliasN(arg, n[i], marker)
      if result: return
  of nkRecCase:
    assert(n[0].kind == nkSym)
    result = canAliasN(arg, n[0], marker)
    if result: return
    for i in 1..<n.len:
      case n[i].kind
      of nkOfBranch, nkElse:
        result = canAliasN(arg, lastSon(n[i]), marker)
        if result: return
      else: discard
  of nkSym:
    result = canAlias(arg, n.sym.typ, marker)
  else: discard

proc canAlias(arg, ret: PType; marker: var IntSet): bool =
  if containsOrIncl(marker, ret.id):
    return false

  if ret.kind in {tyPtr, tyPointer}:
    # unsafe so we don't care:
    return false
  if compareTypes(arg, ret, dcEqIgnoreDistinct):
    return true
  case ret.kind
  of tyObject:
    if isFinal(ret):
      result = canAliasN(arg, ret.n, marker)
      if not result and ret.len > 0 and ret[0] != nil:
        result = canAlias(arg, ret[0], marker)
    else:
      result = true
  of tyTuple:
    for i in 0..<ret.len:
      result = canAlias(arg, ret[i], marker)
      if result: break
  of tyArray, tySequence, tyDistinct, tyGenericInst,
     tyAlias, tyInferred, tySink, tyLent, tyOwned, tyRef:
    result = canAlias(arg, ret.lastSon, marker)
  of tyProc:
    result = ret.callConv == ccClosure
  else:
    result = false

proc canAlias*(arg, ret: PType): bool =
  var marker = initIntSet()
  result = canAlias(arg, ret, marker)

proc checkIsolate*(n: PNode): bool =
  if types.containsTyRef(n.typ):
    # XXX Maybe require that 'n.typ' is acyclic. This is not much
    # worse than the already exisiting inheritance and closure restrictions.
    case n.kind
    of nkCharLit..nkNilLit:
      result = true
    of nkCallKinds:
      if n[0].typ.flags * {tfGcSafe, tfNoSideEffect} == {}:
        return false
      for i in 1..<n.len:
        if checkIsolate(n[i]):
          discard "fine, it is isolated already"
        else:
          let argType = n[i].typ
          if argType != nil and not isCompileTimeOnly(argType) and containsTyRef(argType):
            if argType.canAlias(n.typ):
              return false
      result = true
    of nkIfStmt, nkIfExpr:
      for it in n:
        result = checkIsolate(it.lastSon)
        if not result: break
    of nkCaseStmt, nkObjConstr:
      for i in 1..<n.len:
        result = checkIsolate(n[i].lastSon)
        if not result: break
    of nkBracket, nkTupleConstr, nkPar:
      for it in n:
        result = checkIsolate(it)
        if not result: break
    of nkHiddenStdConv, nkHiddenSubConv, nkCast, nkConv:
      result = checkIsolate(n[1])
    of nkObjUpConv, nkObjDownConv, nkDotExpr:
      result = checkIsolate(n[0])
    of nkStmtList, nkStmtListExpr:
      if n.len > 0:
        result = checkIsolate(n[^1])
      else:
        result = false
    else:
      # unanalysable expression:
      result = false
  else:
    # no ref, no cry:
    result = true


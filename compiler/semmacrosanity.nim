#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Implements type sanity checking for ASTs resulting from macros. Lots of
## room for improvement here.

import ast, msgs, types, options

proc ithField(n: PNode, field: var int): PSym =
  result = nil
  case n.kind
  of nkRecList:
    for i in 0..<n.len:
      result = ithField(n[i], field)
      if result != nil: return
  of nkRecCase:
    if n[0].kind != nkSym: return
    result = ithField(n[0], field)
    if result != nil: return
    for i in 1..<n.len:
      case n[i].kind
      of nkOfBranch, nkElse:
        result = ithField(lastSon(n[i]), field)
        if result != nil: return
      else: discard
  of nkSym:
    if field == 0: result = n.sym
    else: dec(field)
  else: discard

proc ithField(t: PType, field: var int): PSym =
  var base = t.baseClass
  while base != nil:
    let b = skipTypes(base, skipPtrs)
    result = ithField(b.n, field)
    if result != nil: return result
    base = b.baseClass
  result = ithField(t.n, field)

proc annotateType*(n: PNode, t: PType; conf: ConfigRef) =
  let x = t.skipTypes(abstractInst+{tyRange})
  # Note: x can be unequal to t and we need to be careful to use 't'
  # to not to skip tyGenericInst
  case n.kind
  of nkObjConstr:
    let x = t.skipTypes(abstractPtrs)
    n.typ() = t
    n[0].typ() = t
    for i in 1..<n.len:
      var j = i-1
      let field = x.ithField(j)
      if field.isNil:
        globalError conf, n.info, "invalid field at index " & $i
      else:
        internalAssert(conf, n[i].kind == nkExprColonExpr)
        annotateType(n[i][1], field.typ, conf)
  of nkPar, nkTupleConstr:
    if x.kind == tyTuple:
      n.typ() = t
      for i in 0..<n.len:
        if i >= x.kidsLen: globalError conf, n.info, "invalid field at index " & $i
        else: annotateType(n[i], x[i], conf)
    elif x.kind == tyProc and x.callConv == ccClosure:
      n.typ() = t
    elif x.kind == tyOpenArray: # `opcSlice` transforms slices into tuples
      if n.kind == nkTupleConstr:
        let
          bracketExpr = newNodeI(nkBracket, n.info)
          left = int n[1].intVal
          right = int n[2].intVal
        bracketExpr.flags = n.flags
        case n[0].kind # is this a string slice or a array slice
        of nkStrKinds:
          for i in left..right:
            bracketExpr.add newIntNode(nkCharLit, BiggestInt n[0].strVal[i])
            annotateType(bracketExpr[^1], x.elementType, conf)
        of nkBracket:
          for i in left..right:
            bracketExpr.add n[0][i]
            annotateType(bracketExpr[^1], x.elementType, conf)
        else:
          globalError(conf, n.info, "Incorrectly generated tuple constr")
        n[] = bracketExpr[]

      n.typ() = t
    else:
      globalError(conf, n.info, "() must have a tuple type")
  of nkBracket:
    if x.kind in {tyArray, tySequence, tyOpenArray}:
      n.typ() = t
      for m in n: annotateType(m, x.elemType, conf)
    else:
      globalError(conf, n.info, "[] must have some form of array type")
  of nkCurly:
    if x.kind in {tySet}:
      n.typ() = t
      for m in n: annotateType(m, x.elemType, conf)
    else:
      globalError(conf, n.info, "{} must have the set type")
  of nkFloatLit..nkFloat128Lit:
    if x.kind in {tyFloat..tyFloat128}:
      n.typ() = t
    else:
      globalError(conf, n.info, "float literal must have some float type")
  of nkCharLit..nkUInt64Lit:
    if x.kind in {tyInt..tyUInt64, tyBool, tyChar, tyEnum}:
      n.typ() = t
    else:
      globalError(conf, n.info, "integer literal must have some int type")
  of nkStrLit..nkTripleStrLit:
    if x.kind in {tyString, tyCstring}:
      n.typ() = t
    else:
      globalError(conf, n.info, "string literal must be of some string type")
  of nkNilLit:
    if x.kind in NilableTypes+{tyString, tySequence}:
      n.typ() = t
    else:
      globalError(conf, n.info, "nil literal must be of some pointer type")
  else: discard

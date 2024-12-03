#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module does the semantic transformation of the fields* iterators.
#  included from semstmts.nim

type
  TFieldInstCtx = object  # either 'tup[i]' or 'field' is valid
    tupleType: PType      # if != nil we're traversing a tuple
    tupleIndex: int
    field: PSym
    replaceByFieldName: bool
    c: PContext

proc wrapNewScope(c: PContext, n: PNode): PNode {.inline.} =
  # use `if true` to not interfere with `break`
  # just opening scope via `openScope(c)` isn't enough,
  # a scope has to be opened in the codegen as well for reused
  # template instantiations
  let trueLit = newIntLit(c.graph, n.info, 1)
  trueLit.typ() = getSysType(c.graph, n.info, tyBool)
  result = newTreeI(nkIfStmt, n.info, newTreeI(nkElifBranch, n.info, trueLit, n))

proc instFieldLoopBody(c: TFieldInstCtx, n: PNode, forLoop: PNode): PNode =
  if c.field != nil and isEmptyType(c.field.typ):
    result = newNode(nkEmpty)
    return
  case n.kind
  of nkEmpty..pred(nkIdent), succ(nkSym)..nkNilLit: result = copyNode(n)
  of nkIdent, nkSym:
    result = n
    let ident = considerQuotedIdent(c.c, n)
    if c.replaceByFieldName:
      if ident.id == considerQuotedIdent(c.c, forLoop[0]).id:
        let fieldName = if c.tupleType.isNil: c.field.name.s
                        elif c.tupleType.n.isNil: "Field" & $c.tupleIndex
                        else: c.tupleType.n[c.tupleIndex].sym.name.s
        result = newStrNode(nkStrLit, fieldName)
        return
    # other fields:
    for i in ord(c.replaceByFieldName)..<forLoop.len-2:
      if ident.id == considerQuotedIdent(c.c, forLoop[i]).id:
        var call = forLoop[^2]
        var tupl = call[i+1-ord(c.replaceByFieldName)]
        if c.field.isNil:
          result = newNodeI(nkBracketExpr, n.info)
          result.add(tupl)
          result.add(newIntNode(nkIntLit, c.tupleIndex))
        else:
          result = newNodeI(nkDotExpr, n.info)
          result.add(tupl)
          result.add(newSymNode(c.field, n.info))
        break
  else:
    if n.kind == nkContinueStmt:
      localError(c.c.config, n.info,
                 "'continue' not supported in a 'fields' loop")
    result = shallowCopy(n)
    for i in 0..<n.len:
      result[i] = instFieldLoopBody(c, n[i], forLoop)

type
  TFieldsCtx = object
    c: PContext
    m: TMagic

proc semForObjectFields(c: TFieldsCtx, typ, forLoop, father: PNode) =
  case typ.kind
  of nkSym:
    # either 'tup[i]' or 'field' is valid
    var fc = TFieldInstCtx(
      c: c.c,
      field: typ.sym,
      replaceByFieldName: c.m == mFieldPairs
    )
    openScope(c.c)
    inc c.c.inUnrolledContext
    var body = instFieldLoopBody(fc, lastSon(forLoop), forLoop)
    # new scope for each field that codegen should know about:
    body = wrapNewScope(c.c, body)
    father.add(semStmt(c.c, body, {}))
    dec c.c.inUnrolledContext
    closeScope(c.c)
  of nkNilLit: discard
  of nkRecCase:
    let call = forLoop[^2]
    if call.len > 2:
      localError(c.c.config, forLoop.info,
                 "parallel 'fields' iterator does not work for 'case' objects")
      return
    # iterate over the selector:
    semForObjectFields(c, typ[0], forLoop, father)
    # we need to generate a case statement:
    var caseStmt = newNodeI(nkCaseStmt, forLoop.info)
    # generate selector:
    var access = newNodeI(nkDotExpr, forLoop.info, 2)
    access[0] = call[1]
    access[1] = newSymNode(typ[0].sym, forLoop.info)
    caseStmt.add(semExprWithType(c.c, access))
    # copy the branches over, but replace the fields with the for loop body:
    for i in 1..<typ.len:
      var branch = copyTree(typ[i])
      branch[^1] = newNodeI(nkStmtList, forLoop.info)
      semForObjectFields(c, typ[i].lastSon, forLoop, branch[^1])
      caseStmt.add(branch)
    father.add(caseStmt)
  of nkRecList:
    for t in items(typ): semForObjectFields(c, t, forLoop, father)
  else:
    illFormedAstLocal(typ, c.c.config)

proc semForFields(c: PContext, n: PNode, m: TMagic): PNode =
  # so that 'break' etc. work as expected, we produce
  # a 'while true: stmt; break' loop ...
  result = newNodeI(nkWhileStmt, n.info, 2)
  var trueSymbol = systemModuleSym(c.graph, getIdent(c.cache, "true"))
  if trueSymbol == nil:
    localError(c.config, n.info, "system needs: 'true'")
    trueSymbol = newSym(skUnknown, getIdent(c.cache, "true"), c.idgen, getCurrOwner(c), n.info)
    trueSymbol.typ = getSysType(c.graph, n.info, tyBool)

  result[0] = newSymNode(trueSymbol, n.info)
  var stmts = newNodeI(nkStmtList, n.info)
  result[1] = stmts

  var call = n[^2]
  if n.len-2 != call.len-1 + ord(m==mFieldPairs):
    localError(c.config, n.info, errWrongNumberOfVariables)
    return result

  const skippedTypesForFields = abstractVar - {tyTypeDesc} + tyUserTypeClasses
  var tupleTypeA = skipTypes(call[1].typ, skippedTypesForFields)
  if tupleTypeA.kind notin {tyTuple, tyObject}:
    localError(c.config, n.info, errGenerated, "no object or tuple type")
    return result
  for i in 1..<call.len:
    let calli = call[i]
    var tupleTypeB = skipTypes(calli.typ, skippedTypesForFields)
    if not sameType(tupleTypeA, tupleTypeB):
      typeMismatch(c.config, calli.info, tupleTypeA, tupleTypeB, calli)

  inc(c.p.nestedLoopCounter)
  let oldBreakInLoop = c.p.breakInLoop
  c.p.breakInLoop = true
  if tupleTypeA.kind == tyTuple:
    var loopBody = n[^1]
    for i in 0..<tupleTypeA.len:
      openScope(c)
      var fc = TFieldInstCtx(
          tupleType: tupleTypeA,
          tupleIndex: i,
          c: c,
          replaceByFieldName: m == mFieldPairs
      )
      var body = instFieldLoopBody(fc, loopBody, n)
      # new scope for each field that codegen should know about:
      body = wrapNewScope(c, body)
      inc c.inUnrolledContext
      stmts.add(semStmt(c, body, {}))
      dec c.inUnrolledContext
      closeScope(c)
  else:
    var fc = TFieldsCtx(m: m, c: c)
    var t = tupleTypeA
    while t.kind == tyObject:
      semForObjectFields(fc, t.n, n, stmts)
      if t.baseClass == nil: break
      t = skipTypes(t.baseClass, skipPtrs)
  c.p.breakInLoop = oldBreakInLoop
  dec(c.p.nestedLoopCounter)
  # for TR macros this 'while true: ...; break' loop is pretty bad, so
  # we avoid it now if we can:
  if containsNode(stmts, {nkBreakStmt}):
    var b = newNodeI(nkBreakStmt, n.info)
    b.add(newNodeI(nkEmpty, n.info))
    stmts.add(b)
  else:
    result = stmts

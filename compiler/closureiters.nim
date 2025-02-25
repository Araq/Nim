#
#
#           The Nim Compiler
#        (c) Copyright 2018 Nim Contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# This file implements closure iterator transformations.
# The main idea is to split the closure iterator body to top level statements.
# The body is split by yield statement.
#
# Example:
#  while a > 0:
#    echo "hi"
#    yield a
#    dec a
#
# Should be transformed to:
#  case :state
#  of 0:
#    if a > 0:
#      echo "hi"
#      :state = 1 # Next state
#      return a # yield
#    else:
#      :state = 2 # Next state
#      break :stateLoop # Proceed to the next state
#  of 1:
#    dec a
#    :state = 0 # Next state
#    break :stateLoop # Proceed to the next state
#  of 2:
#    :state = -1 # End of execution
#  else:
#    return

# Lambdalifting treats :state variable specially, it should always end up
# as the first field in env. Currently C codegen depends on this behavior.

# One special subtransformation is nkStmtListExpr lowering.
# Example:
#   template foo(): int =
#     yield 1
#     2
#
#   iterator it(): int {.closure.} =
#     if foo() == 2:
#       yield 3
#
# If a nkStmtListExpr has yield inside, it has first to be lowered to:
#   yield 1
#   :tmpSlLower = 2
#   if :tmpSlLower == 2:
#     yield 3

# nkTryStmt Transformations:
# If the iter has an nkTryStmt with a yield inside
#  - the closure iter is promoted to have exceptions (ctx.hasExceptions = true)
#  - exception table is created. This is a const array, where
#    `abs(exceptionTable[i])` is a state idx to which we should jump from state
#    `i` should exception be raised in state `i`. For all states in `try` block
#    the target state is `except` block. For all states in `except` block
#    the target state is `finally` block. For all other states there is no
#    target state (0, as the first block can never be neither except nor finally).
#    `exceptionTable[i]` is < 0 if `abs(exceptionTable[i])` is except block,
#    and > 0, for finally block.
#  - local variable :curExc is created
#  - the iter body is wrapped into a
#      try:
#       closureIterSetupExc(:curExc)
#       ...body...
#      catch:
#        :state = exceptionTable[:state]
#        if :state == 0: raise # No state that could handle exception
#        :unrollFinally = :state > 0 # Target state is finally
#        if :state < 0:
#           :state = -:state
#        :curExc = getCurrentException()
#
# nkReturnStmt within a try/except/finally now has to behave differently as we
# want the nearest finally block to be executed before the return, thus it is
# transformed to:
#  :tmpResult = returnValue (if return doesn't have a value, this is skipped)
#  :unrollFinally = true
#  goto nearestFinally (or -1 if not exists)
#
# Example:
#
# try:
#  yield 0
#  raise ...
# except:
#  yield 1
#  return 3
# finally:
#  yield 2
#
# Is transformed to (yields are left in place for example simplicity,
#    in reality the code is subdivided even more, as described above):
#
# case :state
# of 0: # Try
#   yield 0
#   raise ...
#   :state = 2 # What would happen should we not raise
#   break :stateLoop
# of 1: # Except
#   yield 1
#   :tmpResult = 3           # Return
#   :unrollFinally = true # Return
#   :state = 2 # Goto Finally
#   break :stateLoop
#   :state = 2 # What would happen should we not return
#   break :stateLoop
# of 2: # Finally
#   yield 2
#   if :unrollFinally: # This node is created by `newEndFinallyNode`
#     if :curExc.isNil:
#       if nearestFinally == 0:
#         return :tmpResult
#       else:
#         :state = nearestFinally # bubble up
#     else:
#       closureIterSetupExc(nil)
#       raise
#   state = -1 # Goto next state. In this case we just exit
#   break :stateLoop
# else:
#   return

import
  ast, msgs, idents,
  renderer, magicsys, lowerings, lambdalifting, modulegraphs, lineinfos,
  options

import std/tables

when defined(nimPreviewSlimSystem):
  import std/assertions

type
  Ctx = object
    g: ModuleGraph
    fn: PSym
    tmpResultSym: PSym # Used when we return, but finally has to interfere
    unrollFinallySym: PSym # Indicates that we're unrolling finally states (either exception happened or premature return)
    curExcSym: PSym # Current exception

    states: seq[tuple[label: int, body: PNode]] # The resulting states.
    blockLevel: int # Temp used to transform break and continue stmts
    stateLoopLabel: PSym # Label to break on, when jumping between states.
    exitStateIdx: int # index of the last state
    tempVarId: int # unique name counter
    tempVars: PNode # Temp var decls, nkVarSection
    exceptionTable: seq[int] # For state `i` jump to state `exceptionTable[i]` if exception is raised
    hasExceptions: bool # Does closure have yield in try?
    curExcHandlingState: int # Negative for except, positive for finally
    nearestFinally: int # Index of the nearest finally block. For try/except it
                    # is their finally. For finally it is parent finally. Otherwise -1
    idgen: IdGenerator
    varStates: Table[ItemId, int] # Used to detect if local variable belongs to multiple states

const
  nkSkip = {nkEmpty..nkNilLit, nkTemplateDef, nkTypeSection, nkStaticStmt,
            nkCommentStmt, nkMixinStmt, nkBindStmt} + procDefs
  emptyStateLabel = -1
  localNotSeen = -1
  localRequiresLifting = -2

proc newStateAccess(ctx: var Ctx): PNode =
  result = rawIndirectAccess(newSymNode(getEnvParam(ctx.fn)),
      getStateField(ctx.g, ctx.fn), ctx.fn.info)

proc newStateAssgn(ctx: var Ctx, toValue: PNode): PNode =
  # Creates state assignment:
  #   :state = toValue
  newTree(nkAsgn, ctx.newStateAccess(), toValue)

proc newStateAssgn(ctx: var Ctx, stateNo: int = -2): PNode =
  # Creates state assignment:
  #   :state = stateNo
  ctx.newStateAssgn(newIntTypeNode(stateNo, ctx.g.getSysType(TLineInfo(), tyInt)))

proc newEnvVar(ctx: var Ctx, name: string, typ: PType): PSym =
  result = newSym(skVar, getIdent(ctx.g.cache, name), ctx.idgen, ctx.fn, ctx.fn.info)
  result.typ = typ
  result.flags.incl sfNoInit
  assert(not typ.isNil, "Env var needs a type")

  let envParam = getEnvParam(ctx.fn)
  # let obj = envParam.typ.lastSon
  result = addUniqueField(envParam.typ.elementType, result, ctx.g.cache, ctx.idgen)

proc newEnvVarAccess(ctx: Ctx, s: PSym): PNode =
  result = rawIndirectAccess(newSymNode(getEnvParam(ctx.fn)), s, ctx.fn.info)

proc newTempVarAccess(ctx: Ctx, s: PSym): PNode =
  result = newSymNode(s, ctx.fn.info)

proc newTmpResultAccess(ctx: var Ctx): PNode =
  if ctx.tmpResultSym.isNil:
    ctx.tmpResultSym = ctx.newEnvVar(":tmpResult", ctx.fn.typ.returnType)
  ctx.newEnvVarAccess(ctx.tmpResultSym)

proc newUnrollFinallyAccess(ctx: var Ctx, info: TLineInfo): PNode =
  if ctx.unrollFinallySym.isNil:
    ctx.unrollFinallySym = ctx.newEnvVar(":unrollFinally", ctx.g.getSysType(info, tyBool))
  ctx.newEnvVarAccess(ctx.unrollFinallySym)

proc newCurExcAccess(ctx: var Ctx): PNode =
  if ctx.curExcSym.isNil:
    ctx.curExcSym = ctx.newEnvVar(":curExc", ctx.g.callCodegenProc("getCurrentException").typ)
  ctx.newEnvVarAccess(ctx.curExcSym)

proc newState(ctx: var Ctx, n, gotoOut: PNode): int =
  # Creates a new state, adds it to the context fills out `gotoOut` so that it
  # will goto this state.
  # Returns index of the newly created state

  result = ctx.states.len
  let resLit = ctx.g.newIntLit(n.info, result)
  ctx.states.add((result, n))
  ctx.exceptionTable.add(ctx.curExcHandlingState)

  if not gotoOut.isNil:
    assert(gotoOut.len == 0)
    gotoOut.add(ctx.g.newIntLit(gotoOut.info, result))

proc toStmtList(n: PNode): PNode =
  result = n
  if result.kind notin {nkStmtList, nkStmtListExpr}:
    result = newNodeI(nkStmtList, n.info)
    result.add(n)

proc addGotoOut(n: PNode, gotoOut: PNode): PNode =
  # Make sure `n` is a stmtlist, and ends with `gotoOut`
  result = toStmtList(n)
  if result.len == 0 or result[^1].kind != nkGotoState:
    result.add(gotoOut)

proc newTempVarDef(ctx: Ctx, s: PSym, initialValue: PNode): PNode =
  var v = initialValue
  if v == nil:
    v = ctx.g.emptyNode
  newTree(nkVarSection, newTree(nkIdentDefs, newSymNode(s), ctx.g.emptyNode, v))

proc newTempVar(ctx: var Ctx, typ: PType, parent: PNode, initialValue: PNode = nil): PSym =
  result = newSym(skVar, getIdent(ctx.g.cache, ":tmpSlLower" & $ctx.tempVarId), ctx.idgen, ctx.fn, ctx.fn.info)
  inc ctx.tempVarId
  result.typ = typ
  assert(not typ.isNil, "Temp var needs a type")
  parent.add(ctx.newTempVarDef(result, initialValue))

proc hasYields(n: PNode): bool =
  # TODO: This is very inefficient. It traverses the node, looking for nkYieldStmt.
  case n.kind
  of nkYieldStmt:
    result = true
  of nkSkip:
    result = false
  else:
    result = false
    for i in ord(n.kind == nkCast)..<n.len:
      if n[i].hasYields:
        result = true
        break

proc transformBreaksAndContinuesInWhile(ctx: var Ctx, n: PNode, before, after: PNode): PNode =
  result = n
  case n.kind
  of nkSkip:
    discard
  of nkWhileStmt: discard # Do not recurse into nested whiles
  of nkContinueStmt:
    result = before
  of nkBlockStmt:
    inc ctx.blockLevel
    result[1] = ctx.transformBreaksAndContinuesInWhile(result[1], before, after)
    dec ctx.blockLevel
  of nkBreakStmt:
    if ctx.blockLevel == 0:
      result = after
  else:
    for i in 0..<n.len:
      n[i] = ctx.transformBreaksAndContinuesInWhile(n[i], before, after)

proc transformBreaksInBlock(ctx: var Ctx, n: PNode, label, after: PNode): PNode =
  result = n
  case n.kind
  of nkSkip:
    discard
  of nkBlockStmt, nkWhileStmt:
    inc ctx.blockLevel
    result[1] = ctx.transformBreaksInBlock(result[1], label, after)
    dec ctx.blockLevel
  of nkBreakStmt:
    if n[0].kind == nkEmpty:
      if ctx.blockLevel == 0:
        result = after
    else:
      if label.kind == nkSym and n[0].sym == label.sym:
        result = after
  else:
    for i in 0..<n.len:
      n[i] = ctx.transformBreaksInBlock(n[i], label, after)

proc newNullifyCurExc(ctx: var Ctx, info: TLineInfo): PNode =
  # :curEcx = nil
  let curExc = ctx.newCurExcAccess()
  curExc.info = info
  let nilnode = newNode(nkNilLit)
  nilnode.typ() = curExc.typ
  result = newTree(nkAsgn, curExc, nilnode)

proc newOr(g: ModuleGraph, a, b: PNode): PNode {.inline.} =
  result = newTree(nkCall, newSymNode(g.getSysMagic(a.info, "or", mOr)), a, b)
  result.typ() = g.getSysType(a.info, tyBool)
  result.info = a.info

proc collectExceptState(ctx: var Ctx, n: PNode): PNode {.inline.} =
  var ifStmt = newNodeI(nkIfStmt, n.info)
  let g = ctx.g
  for c in n:
    if c.kind == nkExceptBranch:
      var ifBranch: PNode

      if c.len > 1:
        var cond: PNode = nil
        for i in 0..<c.len - 1:
          assert(c[i].kind == nkType)
          let nextCond = newTree(nkCall,
            newSymNode(g.getSysMagic(c.info, "of", mOf)),
            g.callCodegenProc("getCurrentException"),
            c[i])
          nextCond.typ() = ctx.g.getSysType(c.info, tyBool)
          nextCond.info = c.info

          if cond.isNil:
            cond = nextCond
          else:
            cond = g.newOr(cond, nextCond)

        ifBranch = newNodeI(nkElifBranch, c.info)
        ifBranch.add(cond)
      else:
        if ifStmt.len == 0:
          ifStmt = newNodeI(nkStmtList, c.info)
          ifBranch = newNodeI(nkStmtList, c.info)
        else:
          ifBranch = newNodeI(nkElse, c.info)

      ifBranch.add(c[^1])
      ifStmt.add(ifBranch)

  if ifStmt.len != 0:
    result = newTree(nkStmtList, ctx.newNullifyCurExc(n.info), ifStmt)
  else:
    result = ctx.g.emptyNode

proc addElseToExcept(ctx: var Ctx, n: PNode) =
  if n.kind == nkStmtList and n[1].kind == nkIfStmt and n[1][^1].kind != nkElse:
    # Not all cases are covered
    let branchBody = newNodeI(nkStmtList, n.info)

    block: # :unrollFinally = true
      branchBody.add(newTree(nkAsgn,
        ctx.newUnrollFinallyAccess(n.info),
        newIntTypeNode(1, ctx.g.getSysType(n.info, tyBool))))

    block: # :curExc = getCurrentException()
      branchBody.add(newTree(nkAsgn,
        ctx.newCurExcAccess(),
        ctx.g.callCodegenProc("getCurrentException")))

    block: # goto nearestFinally
      branchBody.add(newTree(nkGotoState, ctx.g.newIntLit(n.info, ctx.nearestFinally)))

    let elseBranch = newTree(nkElse, branchBody)
    n[1].add(elseBranch)

proc getFinallyNode(ctx: var Ctx, n: PNode): PNode =
  result = n[^1]
  if result.kind == nkFinally:
    result = result[0]
  else:
    result = ctx.g.emptyNode

proc hasYieldsInExpressions(n: PNode): bool =
  case n.kind
  of nkSkip:
    result = false
  of nkStmtListExpr:
    if isEmptyType(n.typ):
      result = false
      for c in n:
        if c.hasYieldsInExpressions:
          return true
    else:
      result = n.hasYields
  of nkCast:
    result = false
    for i in 1..<n.len:
      if n[i].hasYieldsInExpressions:
        return true
  else:
    result = false
    for c in n:
      if c.hasYieldsInExpressions:
        return true

proc exprToStmtList(n: PNode): tuple[s, res: PNode] =
  assert(n.kind == nkStmtListExpr)
  result = (newNodeI(nkStmtList, n.info), nil)
  result.s.sons = @[]

  var n = n
  while n.kind == nkStmtListExpr:
    result.s.sons.add(n.sons)
    result.s.sons.setLen(result.s.len - 1) # delete last son
    n = n[^1]

  result.res = n

proc newTempVarAsgn(ctx: Ctx, s: PSym, v: PNode): PNode =
  if isEmptyType(v.typ):
    result = v
  else:
    result = newTree(nkFastAsgn, ctx.newTempVarAccess(s), v)
    result.info = v.info

proc addExprAssgn(ctx: Ctx, output, input: PNode, sym: PSym) =
  if input.kind == nkStmtListExpr:
    let (st, res) = exprToStmtList(input)
    output.add(st)
    output.add(ctx.newTempVarAsgn(sym, res))
  else:
    output.add(ctx.newTempVarAsgn(sym, input))

proc convertExprBodyToAsgn(ctx: Ctx, exprBody: PNode, res: PSym): PNode =
  result = newNodeI(nkStmtList, exprBody.info)
  ctx.addExprAssgn(result, exprBody, res)

proc newNotCall(g: ModuleGraph; e: PNode): PNode =
  result = newTree(nkCall, newSymNode(g.getSysMagic(e.info, "not", mNot), e.info), e)
  result.typ() = g.getSysType(e.info, tyBool)

proc boolLit(g: ModuleGraph; info: TLineInfo; value: bool): PNode =
  result = newIntLit(g, info, ord value)
  result.typ() = getSysType(g, info, tyBool)

proc captureVar(c: var Ctx, s: PSym) =
  if c.varStates.getOrDefault(s.itemId) != localRequiresLifting:
    c.varStates[s.itemId] = localRequiresLifting # Mark this variable for lifting
    let e = getEnvParam(c.fn)
    discard addField(e.typ.elementType, s, c.g.cache, c.idgen)

proc lowerStmtListExprs(ctx: var Ctx, n: PNode, needsSplit: var bool): PNode =
  result = n
  case n.kind
  of nkSkip:
    discard

  of nkYieldStmt:
    var ns = false
    for i in 0..<n.len:
      n[i] = ctx.lowerStmtListExprs(n[i], ns)

    if ns:
      result = newNodeI(nkStmtList, n.info)
      let (st, ex) = exprToStmtList(n[0])
      result.add(st)
      n[0] = ex
      result.add(n)

    needsSplit = true

  of nkPar, nkObjConstr, nkTupleConstr, nkBracket:
    var ns = false
    for i in 0..<n.len:
      n[i] = ctx.lowerStmtListExprs(n[i], ns)

    if ns:
      needsSplit = true

      result = newNodeI(nkStmtListExpr, n.info)
      if n.typ.isNil: internalError(ctx.g.config, "lowerStmtListExprs: constr typ.isNil")
      result.typ() = n.typ

      for i in 0..<n.len:
        case n[i].kind
        of nkExprColonExpr:
          if n[i][1].kind == nkStmtListExpr:
            let (st, ex) = exprToStmtList(n[i][1])
            result.add(st)
            n[i][1] = ex
        of nkStmtListExpr:
          let (st, ex) = exprToStmtList(n[i])
          result.add(st)
          n[i] = ex
        else: discard
      result.add(n)

  of nkIfStmt, nkIfExpr:
    var ns = false
    for i in 0..<n.len:
      n[i] = ctx.lowerStmtListExprs(n[i], ns)

    if ns:
      needsSplit = true
      var tmp: PSym = nil
      let isExpr = not isEmptyType(n.typ)
      if isExpr:
        result = newNodeI(nkStmtListExpr, n.info)
        result.typ() = n.typ
        tmp = ctx.newTempVar(n.typ, result)
      else:
        result = newNodeI(nkStmtList, n.info)

      var curS = result

      for branch in n:
        case branch.kind
        of nkElseExpr, nkElse:
          if isExpr:
            let branchBody = newNodeI(nkStmtList, branch.info)
            ctx.addExprAssgn(branchBody, branch[0], tmp)
            let newBranch = newTree(nkElse, branchBody)
            curS.add(newBranch)
          else:
            curS.add(branch)

        of nkElifExpr, nkElifBranch:
          var newBranch: PNode
          if branch[0].kind == nkStmtListExpr:
            let (st, res) = exprToStmtList(branch[0])
            let elseBody = newTree(nkStmtList, st)

            newBranch = newTree(nkElifBranch, res, branch[1])

            let newIf = newTree(nkIfStmt, newBranch)
            elseBody.add(newIf)
            if curS.kind == nkIfStmt:
              let newElse = newNodeI(nkElse, branch.info)
              newElse.add(elseBody)
              curS.add(newElse)
            else:
              curS.add(elseBody)
            curS = newIf
          else:
            newBranch = branch
            if curS.kind == nkIfStmt:
              curS.add(newBranch)
            else:
              let newIf = newTree(nkIfStmt, newBranch)
              curS.add(newIf)
              curS = newIf

          if isExpr:
            let branchBody = newNodeI(nkStmtList, branch[1].info)
            ctx.addExprAssgn(branchBody, branch[1], tmp)
            newBranch[1] = branchBody

        else:
          internalError(ctx.g.config, "lowerStmtListExpr(nkIf): " & $branch.kind)

      if isExpr: result.add(ctx.newTempVarAccess(tmp))

  of nkTryStmt, nkHiddenTryStmt:
    var ns = false
    for i in 0..<n.len:
      n[i] = ctx.lowerStmtListExprs(n[i], ns)

    if ns:
      needsSplit = true
      let isExpr = not isEmptyType(n.typ)

      if isExpr:
        result = newNodeI(nkStmtListExpr, n.info)
        result.typ() = n.typ
        let tmp = ctx.newTempVar(n.typ, result)

        n[0] = ctx.convertExprBodyToAsgn(n[0], tmp)
        for i in 1..<n.len:
          let branch = n[i]
          case branch.kind
          of nkExceptBranch:
            if branch[0].kind == nkType:
              branch[1] = ctx.convertExprBodyToAsgn(branch[1], tmp)
            else:
              branch[0] = ctx.convertExprBodyToAsgn(branch[0], tmp)
          of nkFinally:
            discard
          else:
            internalError(ctx.g.config, "lowerStmtListExpr(nkTryStmt): " & $branch.kind)
        result.add(n)
        result.add(ctx.newTempVarAccess(tmp))

  of nkCaseStmt:
    var ns = false
    for i in 0..<n.len:
      n[i] = ctx.lowerStmtListExprs(n[i], ns)

    if ns:
      needsSplit = true

      let isExpr = not isEmptyType(n.typ)

      if isExpr:
        result = newNodeI(nkStmtListExpr, n.info)
        result.typ() = n.typ
        let tmp = ctx.newTempVar(n.typ, result)

        if n[0].kind == nkStmtListExpr:
          let (st, ex) = exprToStmtList(n[0])
          result.add(st)
          n[0] = ex

        for i in 1..<n.len:
          let branch = n[i]
          case branch.kind
          of nkOfBranch:
            branch[^1] = ctx.convertExprBodyToAsgn(branch[^1], tmp)
          of nkElse:
            branch[0] = ctx.convertExprBodyToAsgn(branch[0], tmp)
          else:
            internalError(ctx.g.config, "lowerStmtListExpr(nkCaseStmt): " & $branch.kind)
        result.add(n)
        result.add(ctx.newTempVarAccess(tmp))
      elif n[0].kind == nkStmtListExpr:
        result = newNodeI(nkStmtList, n.info)
        let (st, ex) = exprToStmtList(n[0])
        result.add(st)
        n[0] = ex
        result.add(n)

  of nkCallKinds, nkChckRange, nkChckRangeF, nkChckRange64:
    var ns = false
    for i in 0..<n.len:
      n[i] = ctx.lowerStmtListExprs(n[i], ns)

    if ns:
      needsSplit = true
      let isExpr = not isEmptyType(n.typ)

      if isExpr:
        result = newNodeI(nkStmtListExpr, n.info)
        result.typ() = n.typ
      else:
        result = newNodeI(nkStmtList, n.info)

      if n[0].kind == nkSym and n[0].sym.magic in {mAnd, mOr}: # `and`/`or` short cirquiting
        var cond = n[1]
        if cond.kind == nkStmtListExpr:
          let (st, ex) = exprToStmtList(cond)
          result.add(st)
          cond = ex

        let tmp = ctx.newTempVar(cond.typ, result, cond)
        # result.add(ctx.newTempVarAsgn(tmp, cond))

        var check = ctx.newTempVarAccess(tmp)
        if n[0].sym.magic == mOr:
          check = ctx.g.newNotCall(check)

        cond = n[2]
        let ifBody = newNodeI(nkStmtList, cond.info)
        if cond.kind == nkStmtListExpr:
          let (st, ex) = exprToStmtList(cond)
          ifBody.add(st)
          cond = ex
        ifBody.add(ctx.newTempVarAsgn(tmp, cond))

        let ifBranch = newTree(nkElifBranch, check, ifBody)
        let ifNode = newTree(nkIfStmt, ifBranch)
        result.add(ifNode)
        result.add(ctx.newTempVarAccess(tmp))
      else:
        for i in 0..<n.len:
          if n[i].kind == nkStmtListExpr:
            let (st, ex) = exprToStmtList(n[i])
            result.add(st)
            n[i] = ex

          if n[i].kind in nkCallKinds: # XXX: This should better be some sort of side effect tracking
            let tmp = ctx.newTempVar(n[i].typ, result, n[i])
            # result.add(ctx.newTempVarAsgn(tmp, n[i]))
            n[i] = ctx.newTempVarAccess(tmp)

        result.add(n)

  of nkVarSection, nkLetSection:
    result = newNodeI(nkStmtList, n.info)
    for c in n:
      let varSect = newNodeI(n.kind, n.info)
      varSect.add(c)
      var ns = false
      c[^1] = ctx.lowerStmtListExprs(c[^1], ns)
      if ns:
        needsSplit = true
        let (st, ex) = exprToStmtList(c[^1])
        result.add(st)
        c[^1] = ex
      for i in 0 .. c.len - 3:
        if c[i].kind == nkSym:
          let s = c[i].sym
          if sfForceLift in s.flags:
            ctx.captureVar(s)

      result.add(varSect)

  of nkDiscardStmt, nkReturnStmt, nkRaiseStmt:
    var ns = false
    for i in 0..<n.len:
      n[i] = ctx.lowerStmtListExprs(n[i], ns)

    if ns:
      needsSplit = true
      result = newNodeI(nkStmtList, n.info)
      let (st, ex) = exprToStmtList(n[0])
      result.add(st)
      n[0] = ex
      result.add(n)

  of nkCast, nkHiddenStdConv, nkHiddenSubConv, nkConv, nkObjDownConv,
      nkDerefExpr, nkHiddenDeref:
    var ns = false
    for i in ord(n.kind == nkCast)..<n.len:
      n[i] = ctx.lowerStmtListExprs(n[i], ns)

    if ns:
      needsSplit = true
      result = newNodeI(nkStmtListExpr, n.info)
      result.typ() = n.typ
      let (st, ex) = exprToStmtList(n[^1])
      result.add(st)
      n[^1] = ex
      result.add(n)

  of nkAsgn, nkFastAsgn, nkSinkAsgn:
    var ns = false
    for i in 0..<n.len:
      n[i] = ctx.lowerStmtListExprs(n[i], ns)

    if ns:
      needsSplit = true
      result = newNodeI(nkStmtList, n.info)
      if n[0].kind == nkStmtListExpr:
        let (st, ex) = exprToStmtList(n[0])
        result.add(st)
        n[0] = ex

      if n[1].kind == nkStmtListExpr:
        let (st, ex) = exprToStmtList(n[1])
        result.add(st)
        n[1] = ex

      result.add(n)

  of nkBracketExpr:
    var lhsNeedsSplit = false
    var rhsNeedsSplit = false
    n[0] = ctx.lowerStmtListExprs(n[0], lhsNeedsSplit)
    n[1] = ctx.lowerStmtListExprs(n[1], rhsNeedsSplit)
    if lhsNeedsSplit or rhsNeedsSplit:
      needsSplit = true
      result = newNodeI(nkStmtListExpr, n.info)
      if lhsNeedsSplit:
        let (st, ex) = exprToStmtList(n[0])
        result.add(st)
        n[0] = ex

      if rhsNeedsSplit:
        let (st, ex) = exprToStmtList(n[1])
        result.add(st)
        n[1] = ex
      result.add(n)

  of nkWhileStmt:
    var condNeedsSplit = false
    n[0] = ctx.lowerStmtListExprs(n[0], condNeedsSplit)
    var bodyNeedsSplit = false
    n[1] = ctx.lowerStmtListExprs(n[1], bodyNeedsSplit)

    if condNeedsSplit or bodyNeedsSplit:
      needsSplit = true

      if condNeedsSplit:
        let (st, ex) = exprToStmtList(n[0])
        let brk = newTree(nkBreakStmt, ctx.g.emptyNode)
        let branch = newTree(nkElifBranch, ctx.g.newNotCall(ex), brk)
        let check = newTree(nkIfStmt, branch)
        let newBody = newTree(nkStmtList, st, check, n[1])

        n[0] = ctx.g.boolLit(n[0].info, true)
        n[1] = newBody

  of nkDotExpr, nkCheckedFieldExpr:
    var ns = false
    n[0] = ctx.lowerStmtListExprs(n[0], ns)
    if ns:
      needsSplit = true
      result = newNodeI(nkStmtListExpr, n.info)
      result.typ() = n.typ
      let (st, ex) = exprToStmtList(n[0])
      result.add(st)
      n[0] = ex
      result.add(n)

  of nkBlockExpr:
    var ns = false
    n[1] = ctx.lowerStmtListExprs(n[1], ns)
    if ns:
      needsSplit = true
      result = newNodeI(nkStmtListExpr, n.info)
      result.typ() = n.typ
      let (st, ex) = exprToStmtList(n[1])
      n.transitionSonsKind(nkBlockStmt)
      n.typ() = nil
      n[1] = st
      result.add(n)
      result.add(ex)

  else:
    for i in 0..<n.len:
      n[i] = ctx.lowerStmtListExprs(n[i], needsSplit)

proc newEndFinallyNode(ctx: var Ctx, info: TLineInfo): PNode =
  # Generate the following code:
  #   if :unrollFinally:
  #       if :curExc.isNil:
  #         if nearestFinally == 0:
  #           return :tmpResult
  #         else:
  #           :state = nearestFinally # bubble up
  #       else:
  #         raise
  let curExc = ctx.newCurExcAccess()
  let nilnode = newNode(nkNilLit)
  nilnode.typ() = curExc.typ
  let cmp = newTree(nkCall, newSymNode(ctx.g.getSysMagic(info, "==", mEqRef), info), curExc, nilnode)
  cmp.typ() = ctx.g.getSysType(info, tyBool)

  let retStmt =
    if ctx.nearestFinally == 0:
      # last finally, we can return
      let retValue = if ctx.fn.typ.returnType.isNil:
                   ctx.g.emptyNode
                 else:
                   newTree(nkFastAsgn,
                           newSymNode(getClosureIterResult(ctx.g, ctx.fn, ctx.idgen), info),
                           ctx.newTmpResultAccess())
      newTree(nkReturnStmt, retValue)
    else:
      # bubble up to next finally
      newTree(nkGotoState, ctx.g.newIntLit(info, ctx.nearestFinally))

  let branch = newTree(nkElifBranch, cmp, retStmt)

  let nullifyExc = newTree(nkCall, newSymNode(ctx.g.getCompilerProc("closureIterSetupExc")), nilnode)
  nullifyExc.info = info
  let raiseStmt = newTree(nkRaiseStmt, curExc)
  raiseStmt.info = info
  let elseBranch = newTree(nkElse, newTree(nkStmtList, nullifyExc, raiseStmt))

  let ifBody = newTree(nkIfStmt, branch, elseBranch)
  let elifBranch = newTree(nkElifBranch, ctx.newUnrollFinallyAccess(info), ifBody)
  elifBranch.info = info
  result = newTree(nkIfStmt, elifBranch)

proc transformReturnsInTry(ctx: var Ctx, n: PNode): PNode =
  result = n
  # TODO: This is very inefficient. It traverses the node, looking for nkYieldStmt.
  case n.kind
  of nkReturnStmt:
    # We're somewhere in try, transform to finally unrolling
    if ctx.nearestFinally == 0:
      # return is within the finally
      return

    result = newNodeI(nkStmtList, n.info)

    block: # :unrollFinally = true
      let asgn = newNodeI(nkAsgn, n.info)
      asgn.add(ctx.newUnrollFinallyAccess(n.info))
      asgn.add(newIntTypeNode(1, ctx.g.getSysType(n.info, tyBool)))
      result.add(asgn)

    if n[0].kind != nkEmpty:
      let asgnTmpResult = newNodeI(nkAsgn, n.info)
      asgnTmpResult.add(ctx.newTmpResultAccess())
      let x = if n[0].kind in {nkAsgn, nkFastAsgn, nkSinkAsgn}: n[0][1] else: n[0]
      asgnTmpResult.add(x)
      result.add(asgnTmpResult)

    result.add(ctx.newNullifyCurExc(n.info))

    let goto = newTree(nkGotoState, ctx.g.newIntLit(n.info, ctx.nearestFinally))
    result.add(goto)

  of nkSkip:
    discard
  of nkTryStmt:
    if n.hasYields:
      # the inner try will handle these transformations
      discard
    else:
      for i in 0..<n.len:
        n[i] = ctx.transformReturnsInTry(n[i])
  else:
    for i in 0..<n.len:
      n[i] = ctx.transformReturnsInTry(n[i])

proc transformClosureIteratorBody(ctx: var Ctx, n: PNode, gotoOut: PNode): PNode =
  result = n
  case n.kind
  of nkSkip: discard

  of nkStmtList, nkStmtListExpr:
    result = addGotoOut(result, gotoOut)
    for i in 0..<n.len:
      if n[i].hasYields:
        # Create a new split
        let go = newNodeI(nkGotoState, n[i].info)
        n[i] = ctx.transformClosureIteratorBody(n[i], go)

        let s = newNodeI(nkStmtList, n[i + 1].info)
        for j in i + 1..<n.len:
          s.add(n[j])

        n.sons.setLen(i + 1)
        discard ctx.newState(s, go)
        if ctx.transformClosureIteratorBody(s, gotoOut) != s:
          internalError(ctx.g.config, "transformClosureIteratorBody != s")
        break

  of nkYieldStmt:
    result = newNodeI(nkStmtList, n.info)
    result.add(n)
    result.add(gotoOut)

  of nkElse, nkElseExpr:
    result[0] = addGotoOut(result[0], gotoOut)
    result[0] = ctx.transformClosureIteratorBody(result[0], gotoOut)

  of nkElifBranch, nkElifExpr, nkOfBranch:
    result[^1] = addGotoOut(result[^1], gotoOut)
    result[^1] = ctx.transformClosureIteratorBody(result[^1], gotoOut)

  of nkIfStmt, nkCaseStmt:
    for i in 0..<n.len:
      n[i] = ctx.transformClosureIteratorBody(n[i], gotoOut)
    if n[^1].kind != nkElse:
      # We don't have an else branch, but every possible branch has to end with
      # gotoOut, so add else here.
      let elseBranch = newTree(nkElse, gotoOut)
      n.add(elseBranch)

  of nkWhileStmt:
    # while e:
    #   s
    # ->
    # BEGIN_STATE:
    #   if e:
    #     s
    #     goto BEGIN_STATE
    #   else:
    #     goto OUT

    result = newNodeI(nkGotoState, n.info)

    let s = newNodeI(nkStmtList, n.info)
    discard ctx.newState(s, result)
    let ifNode = newNodeI(nkIfStmt, n.info)
    let elifBranch = newNodeI(nkElifBranch, n.info)
    elifBranch.add(n[0])

    var body = addGotoOut(n[1], result)

    body = ctx.transformBreaksAndContinuesInWhile(body, result, gotoOut)
    body = ctx.transformClosureIteratorBody(body, result)

    elifBranch.add(body)
    ifNode.add(elifBranch)

    let elseBranch = newTree(nkElse, gotoOut)
    ifNode.add(elseBranch)
    s.add(ifNode)

  of nkBlockStmt:
    result[1] = addGotoOut(result[1], gotoOut)
    result[1] = ctx.transformBreaksInBlock(result[1], result[0], gotoOut)
    result[1] = ctx.transformClosureIteratorBody(result[1], gotoOut)

  of nkTryStmt, nkHiddenTryStmt:
    # See explanation above about how this works
    ctx.hasExceptions = true

    result = newNodeI(nkGotoState, n.info)
    var tryBody = toStmtList(n[0])
    var exceptBody = ctx.collectExceptState(n)
    var finallyBody = newTree(nkStmtList, getFinallyNode(ctx, n))
    finallyBody = ctx.transformReturnsInTry(finallyBody)
    finallyBody.add(ctx.newEndFinallyNode(finallyBody.info))

    # The following index calculation is based on the knowledge how state
    # indexes are assigned
    let tryIdx = ctx.states.len
    var exceptIdx, finallyIdx: int
    if exceptBody.kind != nkEmpty:
      exceptIdx = -(tryIdx + 1)
      finallyIdx = tryIdx + 2
    else:
      exceptIdx = tryIdx + 1
      finallyIdx = tryIdx + 1

    let outToFinally = newNodeI(nkGotoState, finallyBody.info)

    block: # Create initial states.
      let oldExcHandlingState = ctx.curExcHandlingState
      ctx.curExcHandlingState = exceptIdx
      let realTryIdx = ctx.newState(tryBody, result)
      assert(realTryIdx == tryIdx)

      if exceptBody.kind != nkEmpty:
        ctx.curExcHandlingState = finallyIdx
        let realExceptIdx = ctx.newState(exceptBody, nil)
        assert(realExceptIdx == -exceptIdx)

      ctx.curExcHandlingState = oldExcHandlingState
      let realFinallyIdx = ctx.newState(finallyBody, outToFinally)
      assert(realFinallyIdx == finallyIdx)

    block: # Subdivide the states
      let oldNearestFinally = ctx.nearestFinally
      ctx.nearestFinally = finallyIdx

      let oldExcHandlingState = ctx.curExcHandlingState

      ctx.curExcHandlingState = exceptIdx

      if ctx.transformReturnsInTry(tryBody) != tryBody:
        internalError(ctx.g.config, "transformReturnsInTry != tryBody")
      if ctx.transformClosureIteratorBody(tryBody, outToFinally) != tryBody:
        internalError(ctx.g.config, "transformClosureIteratorBody != tryBody")

      ctx.curExcHandlingState = finallyIdx
      ctx.addElseToExcept(exceptBody)
      if ctx.transformReturnsInTry(exceptBody) != exceptBody:
        internalError(ctx.g.config, "transformReturnsInTry != exceptBody")
      if ctx.transformClosureIteratorBody(exceptBody, outToFinally) != exceptBody:
        internalError(ctx.g.config, "transformClosureIteratorBody != exceptBody")

      ctx.curExcHandlingState = oldExcHandlingState
      ctx.nearestFinally = oldNearestFinally
      if ctx.transformClosureIteratorBody(finallyBody, gotoOut) != finallyBody:
        internalError(ctx.g.config, "transformClosureIteratorBody != finallyBody")

  of nkGotoState, nkForStmt:
    internalError(ctx.g.config, "closure iter " & $n.kind)

  else:
    for i in 0..<n.len:
      n[i] = ctx.transformClosureIteratorBody(n[i], gotoOut)

proc stateFromGotoState(n: PNode): int =
  assert(n.kind == nkGotoState)
  result = n[0].intVal.int

proc transformStateAssignments(ctx: var Ctx, n: PNode): PNode =
  # This transforms 3 patterns:
  ########################## 1
  # yield e
  # goto STATE
  # ->
  # :state = STATE
  # return e
  ########################## 2
  # goto STATE
  # ->
  # :state = STATE
  # break :stateLoop
  ########################## 3
  # return e
  # ->
  # :state = -1
  # return e
  #
  result = n
  case n.kind
  of nkStmtList, nkStmtListExpr:
    if n.len != 0 and n[0].kind == nkYieldStmt:
      assert(n.len == 2)
      assert(n[1].kind == nkGotoState)

      result = newNodeI(nkStmtList, n.info)
      result.add(ctx.newStateAssgn(stateFromGotoState(n[1])))

      var retStmt = newNodeI(nkReturnStmt, n.info)
      if n[0][0].kind != nkEmpty:
        var a = newNodeI(nkAsgn, n[0][0].info)
        var retVal = n[0][0] #liftCapturedVars(n[0], owner, d, c)
        a.add newSymNode(getClosureIterResult(ctx.g, ctx.fn, ctx.idgen))
        a.add retVal
        retStmt.add(a)
      else:
        retStmt.add(ctx.g.emptyNode)

      result.add(retStmt)
    else:
      for i in 0..<n.len:
        n[i] = ctx.transformStateAssignments(n[i])

  of nkSkip:
    discard

  of nkReturnStmt:
    result = newNodeI(nkStmtList, n.info)
    result.add(ctx.newStateAssgn(-1))
    result.add(n)

  of nkGotoState:
    result = newNodeI(nkStmtList, n.info)
    result.add(ctx.newStateAssgn(stateFromGotoState(n)))

    let breakState = newNodeI(nkBreakStmt, n.info)
    breakState.add(newSymNode(ctx.stateLoopLabel))
    result.add(breakState)

  else:
    for i in 0..<n.len:
      n[i] = ctx.transformStateAssignments(n[i])

proc skipStmtList(ctx: Ctx; n: PNode): PNode =
  result = n
  while result.kind in {nkStmtList}:
    if result.len == 0: return ctx.g.emptyNode
    result = result[0]

proc skipEmptyStates(ctx: Ctx, stateIdx: int): int =
  # Returns first non-empty state idx for `stateIdx`. Returns `stateIdx` if
  # it is not empty
  var maxJumps = ctx.states.len # maxJumps used only for debugging purposes.
  var stateIdx = stateIdx
  while true:
    let label = stateIdx
    if label == ctx.exitStateIdx: break
    var newLabel = label
    if label == emptyStateLabel:
      newLabel = ctx.exitStateIdx
    else:
      let fs = skipStmtList(ctx, ctx.states[label].body)
      if fs.kind == nkGotoState:
        newLabel = fs[0].intVal.int
    if label == newLabel: break
    stateIdx = newLabel
    dec maxJumps
    if maxJumps == 0:
      assert(false, "Internal error")

  result = ctx.states[stateIdx].label

proc skipThroughEmptyStates(ctx: var Ctx, n: PNode): PNode=
  result = n
  case n.kind
  of nkSkip:
    discard
  of nkGotoState:
    result = copyTree(n)
    result[0].intVal = ctx.skipEmptyStates(result[0].intVal.int)
  else:
    for i in 0..<n.len:
      n[i] = ctx.skipThroughEmptyStates(n[i])

proc newArrayType(g: ModuleGraph; n: int, t: PType; idgen: IdGenerator; owner: PSym): PType =
  result = newType(tyArray, idgen, owner)

  let rng = newType(tyRange, idgen, owner)
  rng.n = newTree(nkRange, g.newIntLit(owner.info, 0), g.newIntLit(owner.info, n - 1))
  rng.rawAddSon(t)

  result.rawAddSon(rng)
  result.rawAddSon(t)

proc createExceptionTable(ctx: var Ctx): PNode {.inline.} =
  result = newNodeI(nkBracket, ctx.fn.info)
  result.typ() = ctx.g.newArrayType(ctx.exceptionTable.len, ctx.g.getSysType(ctx.fn.info, tyInt16), ctx.idgen, ctx.fn)

  for i in ctx.exceptionTable:
    let elem = newIntNode(nkIntLit, i)
    elem.typ() = ctx.g.getSysType(ctx.fn.info, tyInt16)
    result.add(elem)

proc newCatchBody(ctx: var Ctx, info: TLineInfo): PNode {.inline.} =
  # Generates the code:
  # :state = exceptionTable[:state]
  # if :state == 0: raise
  # :unrollFinally = :state > 0
  # if :state < 0:
  #   :state = -:state
  # :curExc = getCurrentException()

  result = newNodeI(nkStmtList, info)

  let intTyp = ctx.g.getSysType(info, tyInt)
  let boolTyp = ctx.g.getSysType(info, tyBool)

  # :state = exceptionTable[:state]
  block:
    # exceptionTable[:state]
    let getNextState = newTree(nkBracketExpr,
      ctx.createExceptionTable(),
      ctx.newStateAccess())
    getNextState.typ() = intTyp

    # :state = exceptionTable[:state]
    result.add(ctx.newStateAssgn(getNextState))

  # if :state == 0: raise
  block:
    let cond = newTree(nkCall,
      ctx.g.getSysMagic(info, "==", mEqI).newSymNode(),
      ctx.newStateAccess(),
      newIntTypeNode(0, intTyp))
    cond.typ() = boolTyp

    let raiseStmt = newTree(nkRaiseStmt, ctx.g.emptyNode)
    let ifBranch = newTree(nkElifBranch, cond, raiseStmt)
    let ifStmt = newTree(nkIfStmt, ifBranch)
    result.add(ifStmt)

  # :unrollFinally = :state > 0
  block:
    let cond = newTree(nkCall,
      ctx.g.getSysMagic(info, "<", mLtI).newSymNode,
      newIntTypeNode(0, intTyp),
      ctx.newStateAccess())
    cond.typ() = boolTyp

    let asgn = newTree(nkAsgn, ctx.newUnrollFinallyAccess(info), cond)
    result.add(asgn)

  # if :state < 0: :state = -:state
  block:
    let cond = newTree(nkCall,
      ctx.g.getSysMagic(info, "<", mLtI).newSymNode,
      ctx.newStateAccess(),
      newIntTypeNode(0, intTyp))
    cond.typ() = boolTyp

    let negateState = newTree(nkCall,
      ctx.g.getSysMagic(info, "-", mUnaryMinusI).newSymNode,
      ctx.newStateAccess())
    negateState.typ() = intTyp

    let ifBranch = newTree(nkElifBranch, cond, ctx.newStateAssgn(negateState))
    let ifStmt = newTree(nkIfStmt, ifBranch)
    result.add(ifStmt)

  # :curExc = getCurrentException()
  block:
    result.add(newTree(nkAsgn,
      ctx.newCurExcAccess(),
      ctx.g.callCodegenProc("getCurrentException")))

proc wrapIntoTryExcept(ctx: var Ctx, n: PNode): PNode {.inline.} =
  let setupExc = newTree(nkCall,
    newSymNode(ctx.g.getCompilerProc("closureIterSetupExc")),
    ctx.newCurExcAccess())

  let tryBody = newTree(nkStmtList, setupExc, n)
  let exceptBranch = newTree(nkExceptBranch, ctx.newCatchBody(ctx.fn.info))

  result = newTree(nkTryStmt, tryBody, exceptBranch)

proc wrapIntoStateLoop(ctx: var Ctx, n: PNode): PNode =
  # while true:
  #   block :stateLoop:
  #     local vars decl (if needed)
  #     body # Might get wrapped in try-except
  let loopBody = newNodeI(nkStmtList, n.info)
  result = newTree(nkWhileStmt, ctx.g.boolLit(n.info, true), loopBody)
  result.info = n.info

  let localVars = newNodeI(nkStmtList, n.info)

  let blockStmt = newNodeI(nkBlockStmt, n.info)
  blockStmt.add(newSymNode(ctx.stateLoopLabel))

  var blockBody = newTree(nkStmtList, localVars, n)
  if ctx.hasExceptions:
    blockBody = ctx.wrapIntoTryExcept(blockBody)

  blockStmt.add(blockBody)
  loopBody.add(blockStmt)

proc deleteEmptyStates(ctx: var Ctx) =
  let goOut = newTree(nkGotoState, ctx.g.newIntLit(TLineInfo(), -1))
  ctx.exitStateIdx = ctx.newState(goOut, nil)

  # Apply new state indexes and mark unused states with -1
  var iValid = 0
  for i, s in ctx.states.mpairs:
    let body = skipStmtList(ctx, s.body)
    if body.kind == nkGotoState and i != ctx.states.len - 1 and i != 0:
      # This is an empty state. Mark with -1.
      s.label = emptyStateLabel
    else:
      s.label = iValid
      inc iValid

  for i, s in ctx.states:
    let body = skipStmtList(ctx, s.body)
    if body.kind != nkGotoState or i == 0:
      discard ctx.skipThroughEmptyStates(s.body)
      let excHandlState = ctx.exceptionTable[i]
      if excHandlState < 0:
        ctx.exceptionTable[i] = -ctx.skipEmptyStates(-excHandlState)
      elif excHandlState != 0:
        ctx.exceptionTable[i] = ctx.skipEmptyStates(excHandlState)

  var i = 1 # ignore the entry and the exit
  while i < ctx.states.len - 1:
    if ctx.states[i].label == emptyStateLabel:
      ctx.states.delete(i)
      ctx.exceptionTable.delete(i)
    else:
      inc i

type
  PreprocessContext = object
    finallys: seq[PNode]
    config: ConfigRef
    blocks: seq[(PNode, int)]
    idgen: IdGenerator
  FreshVarsContext = object
    tab: Table[int, PSym]
    config: ConfigRef
    info: TLineInfo
    idgen: IdGenerator

proc freshVars(n: PNode; c: var FreshVarsContext): PNode =
  case n.kind
  of nkSym:
    let x = c.tab.getOrDefault(n.sym.id)
    if x == nil:
      result = n
    else:
      result = newSymNode(x, n.info)
  of nkSkip - {nkSym}:
    result = n
  of nkLetSection, nkVarSection:
    result = copyNode(n)
    for it in n:
      if it.kind in {nkIdentDefs, nkVarTuple}:
        let idefs = copyNode(it)
        for v in 0..it.len-3:
          if it[v].kind == nkSym:
            let x = copySym(it[v].sym, c.idgen)
            c.tab[it[v].sym.id] = x
            idefs.add newSymNode(x)
          else:
            idefs.add it[v]

        for rest in it.len-2 ..< it.len: idefs.add it[rest]
        result.add idefs
      else:
        result.add it
  of nkRaiseStmt:
    result = nil
    localError(c.config, c.info, "unsupported control flow: 'finally: ... raise' duplicated because of 'break'")
  else:
    result = n
    for i in 0..<n.safeLen:
      result[i] = freshVars(n[i], c)

proc preprocess(c: var PreprocessContext; n: PNode): PNode =
  # in order to fix bug #15243 without risking regressions, we preprocess
  # the AST so that 'break' statements inside a 'try finally' also have the
  # finally section. We need to duplicate local variables here and also
  # detect: 'finally: raises X' which is currently not supported. We produce
  # an error for this case for now. All this will be done properly with Yuriy's
  # patch.

  result = n
  case n.kind
  of nkTryStmt:
    let f = n.lastSon
    var didAddSomething = false
    if f.kind == nkFinally:
      c.finallys.add f.lastSon
      didAddSomething = true

    for i in 0 ..< n.len:
      result[i] = preprocess(c, n[i])

    if didAddSomething:
      discard c.finallys.pop()

  of nkWhileStmt, nkBlockStmt:
    if not n.hasYields: return n
    c.blocks.add((n, c.finallys.len))
    for i in 0 ..< n.len:
      result[i] = preprocess(c, n[i])
    discard c.blocks.pop()

  of nkBreakStmt:
    if c.blocks.len == 0:
      discard
    else:
      var fin = -1
      if n[0].kind == nkEmpty:
        fin = c.blocks[^1][1]
      elif n[0].kind == nkSym:
        for i in countdown(c.blocks.high, 0):
          if c.blocks[i][0].kind == nkBlockStmt and c.blocks[i][0][0].kind == nkSym and
              c.blocks[i][0][0].sym == n[0].sym:
            fin = c.blocks[i][1]
            break

      if fin >= 0:
        result = newNodeI(nkStmtList, n.info)
        for i in countdown(c.finallys.high, fin):
          var vars = FreshVarsContext(tab: initTable[int, PSym](), config: c.config, info: n.info, idgen: c.idgen)
          result.add freshVars(copyTree(c.finallys[i]), vars)
          c.idgen = vars.idgen
        result.add n
  of nkSkip: discard
  else:
    for i in 0 ..< n.len:
      result[i] = preprocess(c, n[i])

proc detectCapturedVars(c: var Ctx, n: PNode, stateIdx: int) =
  case n.kind
  of nkSym:
    let s = n.sym
    if s.kind in {skResult, skVar, skLet, skForVar, skTemp} and sfGlobal notin s.flags and s.owner == c.fn:
      let vs = c.varStates.getOrDefault(s.itemId, localNotSeen)
      if vs == localNotSeen: # First seing this variable
        c.varStates[s.itemId] = stateIdx
      elif vs == localRequiresLifting:
        discard # Sym already marked
      elif vs != stateIdx:
        c.captureVar(s)
  of nkReturnStmt:
    if n[0].kind in {nkAsgn, nkFastAsgn, nkSinkAsgn}:
      # we have a `result = result` expression produced by the closure
      # transform, let's not touch the LHS in order to make the lifting pass
      # correct when `result` is lifted
      detectCapturedVars(c, n[0][1], stateIdx)
    else:
      detectCapturedVars(c, n[0], stateIdx)
  else:
    for i in 0 ..< n.safeLen:
      detectCapturedVars(c, n[i], stateIdx)

proc detectCapturedVars(c: var Ctx) =
  for i, s in c.states:
    detectCapturedVars(c, s.body, i)

proc liftLocals(c: var Ctx, n: PNode): PNode =
  result = n
  case n.kind
  of nkSym:
    let s = n.sym
    if c.varStates.getOrDefault(s.itemId) == localRequiresLifting:
      # lift
      let e = getEnvParam(c.fn)
      let field = getFieldFromObj(e.typ.elementType, s)
      assert(field != nil)
      result = rawIndirectAccess(newSymNode(e), field, n.info)
    # elif c.varStates.getOrDefault(s.itemId, localNotSeen) != localNotSeen:
    #   echo "Not lifting ", s.name.s

  of nkReturnStmt:
    if n[0].kind in {nkAsgn, nkFastAsgn, nkSinkAsgn}:
      # we have a `result = result` expression produced by the closure
      # transform, let's not touch the LHS in order to make the lifting pass
      # correct when `result` is lifted
      n[0][1] = liftLocals(c, n[0][1])
    else:
      n[0] = liftLocals(c, n[0])
  else:
    for i in 0 ..< n.safeLen:
      n[i] = liftLocals(c, n[i])

proc transformClosureIterator*(g: ModuleGraph; idgen: IdGenerator; fn: PSym, n: PNode): PNode =
  var ctx = Ctx(g: g, fn: fn, idgen: idgen)

  # The transformation should always happen after at least partial lambdalifting
  # is performed, so that the closure iter environment is always created upfront.
  doAssert(getEnvParam(fn) != nil, "Env param not created before iter transformation")

  ctx.stateLoopLabel = newSym(skLabel, getIdent(ctx.g.cache, ":stateLoop"), idgen, fn, fn.info)
  var pc = PreprocessContext(finallys: @[], config: g.config, idgen: idgen)
  var n = preprocess(pc, n.toStmtList)
  #echo "transformed into ", n
  #var n = n.toStmtList

  discard ctx.newState(n, nil)
  let gotoOut = newTree(nkGotoState, g.newIntLit(n.info, -1))

  var ns = false
  n = ctx.lowerStmtListExprs(n, ns)

  if n.hasYieldsInExpressions():
    internalError(ctx.g.config, "yield in expr not lowered")

  # Splitting transformation
  discard ctx.transformClosureIteratorBody(n, gotoOut)

  # Optimize empty states away
  ctx.deleteEmptyStates()

  let caseDispatcher = newTreeI(nkCaseStmt, n.info,
      ctx.newStateAccess())

  # Lamdalifting will not touch our locals, it is our responsibility to lift those that
  # need it.
  detectCapturedVars(ctx)

  for s in ctx.states:
    let body = ctx.transformStateAssignments(s.body)
    caseDispatcher.add newTreeI(nkOfBranch, body.info, g.newIntLit(body.info, s.label), body)

  caseDispatcher.add newTreeI(nkElse, n.info, newTreeI(nkReturnStmt, n.info, g.emptyNode))

  result = wrapIntoStateLoop(ctx, caseDispatcher)
  result = liftLocals(ctx, result)

  when false:
    echo "TRANSFORM TO STATES: "
    echo renderTree(result)

    echo "exception table:"
    for i, e in ctx.exceptionTable:
      echo i, " -> ", e

    echo "ENV: ", renderTree(getEnvParam(fn).typ.elementType.n)

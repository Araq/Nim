#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Implements the `async` and `multisync` macros for `asyncdispatch`.

import std/[macros, strutils, asyncfutures]

type
  Context = ref object
    inTry: int
    hasRet: bool

# TODO: Ref https://github.com/nim-lang/Nim/issues/5617
# TODO: Add more line infos
proc newCallWithLineInfo(fromNode: NimNode; theProc: NimNode, args: varargs[NimNode]): NimNode =
  result = newCall(theProc, args)
  result.copyLineInfo(fromNode)

template createCb(retFutureSym, iteratorNameSym,
                  strName, identName, futureVarCompletions: untyped) =
  bind finished
  var nameIterVar = iteratorNameSym
  proc identName {.closure, stackTrace: off.} =
    try:
      if not nameIterVar.finished:
        var next = nameIterVar()
        # Continue while the yielded future is already finished.
        while (not next.isNil) and next.finished:
          next = nameIterVar()
          if nameIterVar.finished:
            break

        if next == nil:
          if not retFutureSym.finished:
            let msg = "Async procedure ($1) yielded `nil`, are you await'ing a `nil` Future?"
            raise newException(AssertionDefect, msg % strName)
        else:
          {.gcsafe.}:
            next.addCallback cast[proc() {.closure, gcsafe.}](identName)
    except:
      futureVarCompletions
      if retFutureSym.finished:
        # Take a look at tasyncexceptions for the bug which this fixes.
        # That test explains it better than I can here.
        raise
      else:
        retFutureSym.fail(getCurrentException())
  identName()

proc createFutureVarCompletions(futureVarIdents: seq[NimNode], fromNode: NimNode): NimNode =
  result = newNimNode(nnkStmtList, fromNode)
  # Add calls to complete each FutureVar parameter.
  for ident in futureVarIdents:
    # Only complete them if they have not been completed already by the user.
    # In the meantime, this was really useful for debugging :)
    #result.add(newCall(newIdentNode("echo"), newStrLitNode(fromNode.lineinfo)))
    result.add newIfStmt(
      (
        newCall(newIdentNode("not"),
                newDotExpr(ident, newIdentNode("finished"))),
        newCallWithLineInfo(fromNode, newIdentNode("complete"), ident)
      )
    )

proc processBody(ctx: Context; node, needsCompletionSym, retFutureSym: NimNode, futureVarIdents: seq[NimNode]): NimNode =
  result = node
  case node.kind
  of nnkReturnStmt:
    result = newNimNode(nnkStmtList, node)

    # As I've painfully found out, the order here really DOES matter.
    result.add createFutureVarCompletions(futureVarIdents, node)

    ctx.hasRet = true
    if node[0].kind == nnkEmpty:
      if ctx.inTry == 0:
        result.add newCallWithLineInfo(node, newIdentNode("complete"), retFutureSym, newIdentNode("result"))
      else:
        result.add newAssignment(needsCompletionSym, newLit(true))
    else:
      let x = processBody(ctx, node[0], needsCompletionSym, retFutureSym, futureVarIdents)
      if x.kind == nnkYieldStmt: result.add x
      elif ctx.inTry == 0:
        result.add newCallWithLineInfo(node, newIdentNode("complete"), retFutureSym, x)
      else:
        result.add newAssignment(newIdentNode("result"), x)
        result.add newAssignment(needsCompletionSym, newLit(true))

    result.add newNimNode(nnkReturnStmt, node).add(newNilLit())
    return # Don't process the children of this return stmt
  of RoutineNodes-{nnkTemplateDef}:
    # skip all the nested procedure definitions
    return
  of nnkTryStmt:
    if result[^1].kind == nnkFinally:
      inc ctx.inTry
      result[0] = processBody(ctx, result[0], needsCompletionSym, retFutureSym, futureVarIdents)
      dec ctx.inTry
      for i in 1 ..< result.len:
        result[i] = processBody(ctx, result[i], needsCompletionSym, retFutureSym, futureVarIdents)
      if ctx.inTry == 0 and ctx.hasRet:
        let finallyNode = copyNimNode(result[^1])
        let stmtNode = newNimNode(nnkStmtList)
        for child in result[^1]:
          stmtNode.add child
        stmtNode.add newIfStmt(
          ( needsCompletionSym,
            newCallWithLineInfo(node, newIdentNode("complete"), retFutureSym,
            newIdentNode("result")
            )
          )
        )
        finallyNode.add stmtNode
        result[^1] = finallyNode
    else:
      for i in 0 ..< result.len:
        result[i] = processBody(ctx, result[i], needsCompletionSym, retFutureSym, futureVarIdents)
  else:
    for i in 0 ..< result.len:
      result[i] = processBody(ctx, result[i], needsCompletionSym, retFutureSym, futureVarIdents)

  # echo result.repr

proc getName(node: NimNode): string =
  case node.kind
  of nnkPostfix:
    return node[1].strVal
  of nnkIdent, nnkSym:
    return node.strVal
  of nnkEmpty:
    return "anonymous"
  else:
    error("Unknown name.", node)

proc getFutureVarIdents(params: NimNode): seq[NimNode] =
  result = @[]
  for i in 1 ..< len(params):
    expectKind(params[i], nnkIdentDefs)
    if params[i][1].kind == nnkBracketExpr and
       params[i][1][0].eqIdent(FutureVar.astToStr):
      ## eqIdent: first char is case sensitive!!!
      result.add(params[i][0])

proc isInvalidReturnType(typeName: string): bool =
  return typeName notin ["Future"] #, "FutureStream"]

proc verifyReturnType(typeName: string, node: NimNode = nil) =
  if typeName.isInvalidReturnType:
    error("Expected return type of 'Future' got '$1'" %
          typeName, node)

template await*(f: typed): untyped {.used.} =
  static:
    error "await expects Future[T], got " & $typeof(f)

template await*[T](f: Future[T]): auto {.used.} =
  when not defined(nimHasTemplateRedefinitionPragma):
    {.pragma: redefine.}
  template yieldFuture {.redefine.} = yield FutureBase()

  when compiles(yieldFuture):
    var internalTmpFuture: FutureBase = f
    yield internalTmpFuture
    (cast[typeof(f)](internalTmpFuture)).read()
  else:
    macro errorAsync(futureError: Future[T]) =
      error(
        "Can only 'await' inside a proc marked as 'async'. Use " &
        "'waitFor' when calling an 'async' proc in a non-async scope instead",
        futureError)
    errorAsync(f)

proc asyncSingleProc(prc: NimNode): NimNode =
  ## This macro transforms a single procedure into a closure iterator.
  ## The `async` macro supports a stmtList holding multiple async procedures.
  if prc.kind == nnkProcTy:
    result = prc
    if prc[0][0].kind == nnkEmpty:
      result[0][0] = quote do: Future[void]
    return result

  if prc.kind in RoutineNodes and prc.name.kind != nnkEmpty:
    # Only non anonymous functions need/can have stack trace disabled
    prc.addPragma(nnkExprColonExpr.newTree(ident"stackTrace", ident"off"))

  if prc.kind notin {nnkProcDef, nnkLambda, nnkMethodDef, nnkDo}:
    error("Cannot transform this node kind into an async proc." &
          " proc/method definition or lambda node expected.", prc)

  if prc[4].kind != nnkEmpty:
    for prag in prc[4]:
      if prag.eqIdent("discardable"):
        error("Cannot make async proc discardable. Futures have to be " &
          "checked with `asyncCheck` instead of discarded", prag)

  let prcName = prc.name.getName

  var returnType = prc.params[0]
  var baseType: NimNode
  if returnType.kind in nnkCallKinds and returnType[0].eqIdent("owned") and
      returnType.len == 2:
    returnType = returnType[1]
  # Verify that the return type is a Future[T]
  if returnType.kind == nnkBracketExpr:
    let fut = repr(returnType[0])
    verifyReturnType(fut, returnType[0])
    baseType = returnType[1]
  elif returnType.kind in nnkCallKinds and returnType[0].eqIdent("[]"):
    let fut = repr(returnType[1])
    verifyReturnType(fut, returnType[0])
    baseType = returnType[2]
  elif returnType.kind == nnkEmpty:
    baseType = returnType
  else:
    baseType = nil
    verifyReturnType(repr(returnType), returnType)

  let futureVarIdents = getFutureVarIdents(prc.params)
  var outerProcBody = newNimNode(nnkStmtList, prc.body)

  # Extract the documentation comment from the original procedure declaration.
  # Note that we're not removing it from the body in order not to make this
  # transformation even more complex.
  let body2 = extractDocCommentsAndRunnables(prc.body)

  # -> var retFuture = newFuture[T]()
  var retFutureSym = genSym(nskVar, "retFuture")
  var subRetType =
    if returnType.kind == nnkEmpty: newIdentNode("void")
    else: baseType
  outerProcBody.add(
    newVarStmt(retFutureSym,
      newCall(
        newNimNode(nnkBracketExpr, prc.body).add(
          newIdentNode("newFuture"),
          subRetType),
      newLit(prcName)))) # Get type from return type of this proc

  # -> iterator nameIter(): FutureBase {.closure.} =
  # ->   {.push warning[resultshadowed]: off.}
  # ->   var result: T
  # ->   {.pop.}
  # ->   <proc_body>
  # ->   complete(retFuture, result)
  var iteratorNameSym = genSym(nskIterator, $prcName & " (Async)")
  var needsCompletionSym = genSym(nskVar, "needsCompletion")
  var ctx = Context()
  var procBody = processBody(ctx, prc.body, needsCompletionSym, retFutureSym, futureVarIdents)
  # don't do anything with forward bodies (empty)
  if procBody.kind != nnkEmpty:
    # fix #13899, defer should not escape its original scope
    let blockStmt = newStmtList(newTree(nnkBlockStmt, newEmptyNode(), procBody))
    procBody = newStmtList()
    let resultIdent = ident"result"
    procBody.add quote do:
      # Check whether there is an implicit return
      when typeof(`blockStmt`) is void:
        `blockStmt`
      else:
        `resultIdent` = `blockStmt`
    procBody.add(createFutureVarCompletions(futureVarIdents, nil))
    procBody.insert(0): quote do:
      {.push warning[resultshadowed]: off.}
      when `subRetType` isnot void:
        var `resultIdent`: `subRetType` = default(`subRetType`)
      else:
        var `resultIdent`: Future[void] = nil
      {.pop.}

      var `needsCompletionSym` = false
    procBody.add quote do:
      complete(`retFutureSym`, `resultIdent`)

    var closureIterator = newProc(iteratorNameSym, [quote do: owned(FutureBase)],
                                  procBody, nnkIteratorDef)
    closureIterator.pragma = newNimNode(nnkPragma, lineInfoFrom = prc.body)
    closureIterator.addPragma(newIdentNode("closure"))

    # If proc has an explicit gcsafe pragma, we add it to iterator as well.
    if prc.pragma.findChild(it.kind in {nnkSym, nnkIdent} and $it == "gcsafe") != nil:
      closureIterator.addPragma(newIdentNode("gcsafe"))
    outerProcBody.add(closureIterator)

    # -> createCb(retFuture)
    # NOTE: The NimAsyncContinueSuffix is checked for in asyncfutures.nim to produce
    # friendlier stack traces:
    var cbName = genSym(nskProc, prcName & NimAsyncContinueSuffix)
    var procCb = getAst createCb(retFutureSym, iteratorNameSym,
                          newStrLitNode(prcName),
                          cbName,
                          createFutureVarCompletions(futureVarIdents, nil)
                        )
    outerProcBody.add procCb

    # -> return retFuture
    outerProcBody.add newNimNode(nnkReturnStmt, prc.body[^1]).add(retFutureSym)

  result = prc
  # Add discardable pragma.
  if returnType.kind == nnkEmpty:
    # xxx consider removing `owned`? it's inconsistent with non-void case
    result.params[0] = quote do: owned(Future[void])

  # based on the yglukhov's patch to chronos: https://github.com/status-im/nim-chronos/pull/47
  if procBody.kind != nnkEmpty:
    body2.add quote do:
      `outerProcBody`
    result.body = body2

macro async*(prc: untyped): untyped =
  ## Macro which processes async procedures into the appropriate
  ## iterators and yield statements.
  if prc.kind == nnkStmtList:
    result = newStmtList()
    for oneProc in prc:
      result.add asyncSingleProc(oneProc)
  else:
    result = asyncSingleProc(prc)
  when defined(nimDumpAsync):
    echo repr result

proc splitParamType(paramType: NimNode, async: bool): NimNode =
  result = paramType
  if paramType.kind == nnkInfix and paramType[0].strVal in ["|", "or"]:
    let firstAsync = "async" in paramType[1].toStrLit().strVal.normalize
    let secondAsync = "async" in paramType[2].toStrLit().strVal.normalize

    if firstAsync:
      result = paramType[if async: 1 else: 2]
    elif secondAsync:
      result = paramType[if async: 2 else: 1]

proc stripReturnType(returnType: NimNode): NimNode =
  # Strip out the 'Future' from 'Future[T]'.
  result = returnType
  if returnType.kind == nnkBracketExpr:
    let fut = repr(returnType[0])
    verifyReturnType(fut, returnType)
    result = returnType[1]

proc splitProc(prc: NimNode): (NimNode, NimNode) =
  ## Takes a procedure definition which takes a generic union of arguments,
  ## for example: proc (socket: Socket | AsyncSocket).
  ## It transforms them so that `proc (socket: Socket)` and
  ## `proc (socket: AsyncSocket)` are returned.

  result[0] = prc.copyNimTree()
  # Retrieve the `T` inside `Future[T]`.
  let returnType = stripReturnType(result[0][3][0])
  result[0][3][0] = splitParamType(returnType, async = false)
  for i in 1 ..< result[0][3].len:
    # Sync proc (0) -> FormalParams (3) -> IdentDefs, the parameter (i) ->
    # parameter type (1).
    result[0][3][i][1] = splitParamType(result[0][3][i][1], async=false)
  var multisyncAwait = quote:
    template await(value: typed): untyped =
      value

  result[0][^1] = nnkStmtList.newTree(multisyncAwait, result[0][^1])

  result[1] = prc.copyNimTree()
  if result[1][3][0].kind == nnkBracketExpr:
    result[1][3][0][1] = splitParamType(result[1][3][0][1], async = true)
  for i in 1 ..< result[1][3].len:
    # Async proc (1) -> FormalParams (3) -> IdentDefs, the parameter (i) ->
    # parameter type (1).
    result[1][3][i][1] = splitParamType(result[1][3][i][1], async = true)

macro multisync*(prc: untyped): untyped =
  ## Macro which processes async procedures into both asynchronous and
  ## synchronous procedures.
  ##
  ## The generated async procedures use the `async` macro, whereas the
  ## generated synchronous procedures simply strip off the `await` calls.
  let (sync, asyncPrc) = splitProc(prc)
  result = newStmtList()
  result.add(asyncSingleProc(asyncPrc))
  result.add(sync)

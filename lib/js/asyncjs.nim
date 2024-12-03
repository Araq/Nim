#
#
#            Nim's Runtime Library
#        (c) Copyright 2017 Nim Authors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.

## This module implements types and macros for writing asynchronous code
## for the JS backend. It provides tools for interaction with JavaScript async API-s
## and libraries, writing async procedures in Nim and converting callback-based code
## to promises.
##
## A Nim procedure is asynchronous when it includes the `{.async.}` pragma. It
## should always have a `Future[T]` return type or not have a return type at all.
## A `Future[void]` return type is assumed by default.
##
## This is roughly equivalent to the `async` keyword in JavaScript code.
##
##   ```nim
##   proc loadGame(name: string): Future[Game] {.async.} =
##     # code
##   ```
##
## should be equivalent to
##
##   ```javascript
##   async function loadGame(name) {
##     // code
##   }
##   ```
##
## A call to an asynchronous procedure usually needs `await` to wait for
## the completion of the `Future`.
##
##   ```nim
##   var game = await loadGame(name)
##   ```
##
## Often, you might work with callback-based API-s. You can wrap them with
## asynchronous procedures using promises and `newPromise`:
##
##   ```nim
##   proc loadGame(name: string): Future[Game] =
##     var promise = newPromise() do (resolve: proc(response: Game)):
##       cbBasedLoadGame(name) do (game: Game):
##         resolve(game)
##     return promise
##   ```
##
## Forward definitions work properly, you just need to always add the `{.async.}` pragma:
##
##   ```nim
##   proc loadGame(name: string): Future[Game] {.async.}
##   ```
##
## JavaScript compatibility
## ========================
##
## Nim currently generates `async/await` JavaScript code which is supported in modern
## EcmaScript and most modern versions of browsers, Node.js and Electron.
## If you need to use this module with older versions of JavaScript, you can
## use a tool that backports the resulting JavaScript code, as babel.

# xxx code: javascript above gives `LanguageXNotSupported` warning.

when not defined(js) and not defined(nimsuggest):
  {.fatal: "Module asyncjs is designed to be used with the JavaScript backend.".}

import std/jsffi
import std/macros
import std/private/since

type
  Future*[T] = ref object
    future*: T
  ## Wraps the return type of an asynchronous procedure.

  PromiseJs* {.importjs: "Promise".} = ref object
  ## A JavaScript Promise.


proc replaceReturn(node: var NimNode) =
  var z = 0
  for s in node:
    var son = node[z]
    let jsResolve = ident("jsResolve")
    if son.kind == nnkReturnStmt:
      let value = if son[0].kind != nnkEmpty: nnkCall.newTree(jsResolve, son[0]) else: jsResolve
      node[z] = nnkReturnStmt.newTree(value)
    elif son.kind == nnkAsgn and son[0].kind == nnkIdent and $son[0] == "result":
      node[z] = nnkAsgn.newTree(son[0], nnkCall.newTree(jsResolve, son[1]))
    elif son.kind in RoutineNodes:
      discard
    else:
      replaceReturn(son)
    inc z

proc isFutureVoid(node: NimNode): bool =
  result = node.kind == nnkBracketExpr and
           node[0].kind == nnkIdent and $node[0] == "Future" and
           node[1].kind == nnkIdent and $node[1] == "void"

proc generateJsasync(arg: NimNode): NimNode =
  if arg.kind notin {nnkProcDef, nnkLambda, nnkMethodDef, nnkDo, nnkProcTy}:
      error("Cannot transform this node kind into an async proc." &
            " proc/method definition or lambda node expected.")

  # Transform type X = proc (): something {.async.}
  # into      type X = proc (): Future[something]
  if arg.kind == nnkProcTy:
    result = arg
    if arg[0][0].kind == nnkEmpty:
      result[0][0] = quote do: Future[void]
    return result

  result = arg
  var isVoid = false
  let jsResolve = ident("jsResolve")
  if arg.params[0].kind == nnkEmpty:
    result.params[0] = nnkBracketExpr.newTree(ident("Future"), ident("void"))
    isVoid = true
  elif isFutureVoid(arg.params[0]):
    isVoid = true

  var code = result.body
  replaceReturn(code)
  result.body = nnkStmtList.newTree()

  if len(code) > 0:
    var awaitFunction = quote:
      proc await[T](f: Future[T]): T {.importjs: "(await #)", used.}
    result.body.add(awaitFunction)

    var resolve: NimNode
    if isVoid:
      resolve = quote:
        var `jsResolve` {.importjs: "undefined".}: Future[void]
    else:
      resolve = quote:
        proc jsResolve[T](a: T): Future[T] {.importjs: "#", used.}
        proc jsResolve[T](a: Future[T]): Future[T] {.importjs: "#", used.}
    result.body.add(resolve)
  else:
    result.body = newEmptyNode()
  for child in code:
    result.body.add(child)

  if len(code) > 0 and isVoid:
    var voidFix = quote:
      return `jsResolve`
    result.body.add(voidFix)

  let asyncPragma = quote:
    {.codegenDecl: "async function $2($3)".}

  result.addPragma(asyncPragma[0])

macro async*(arg: untyped): untyped =
  ## Macro which converts normal procedures into
  ## javascript-compatible async procedures.
  if arg.kind == nnkStmtList:
    result = newStmtList()
    for oneProc in arg:
      result.add generateJsasync(oneProc)
  else:
    result = generateJsasync(arg)

proc newPromise*[T](handler: proc(resolve: proc(response: T))): Future[T] {.importjs: "(new Promise(#))".}
  ## A helper for wrapping callback-based functions
  ## into promises and async procedures.

proc newPromise*(handler: proc(resolve: proc())): Future[void] {.importjs: "(new Promise(#))".}
  ## A helper for wrapping callback-based functions
  ## into promises and async procedures.

template maybeFuture(T): untyped =
  # avoids `Future[Future[T]]`
  when T is Future: T
  else: Future[T]


since (1, 5, 1):
  #[
  TODO:
  * map `Promise.all()`
  * proc toString*(a: Error): cstring {.importjs: "#.toString()".}

  Note:
  We probably can't have a `waitFor` in js in browser (single threaded), but maybe it would be possible
  in in nodejs, see https://nodejs.org/api/child_process.html#child_process_child_process_execsync_command_options
  and https://stackoverflow.com/questions/61377358/javascript-wait-for-async-call-to-finish-before-returning-from-function-witho
  ]#

  type Error*  {.importjs: "Error".} = ref object of JsRoot
    ## https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Error
    message*: cstring
    name*: cstring

  type OnReject* = proc(reason: Error)

  proc then*[T](future: Future[T], onSuccess: proc, onReject: OnReject = nil): auto =
    ## See https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise/then
    ## Returns a `Future` from the return type of `onSuccess(T.default)`.
    runnableExamples("-r:off"):
      from std/sugar import `=>`

      proc fn(n: int): Future[int] {.async.} =
        if n >= 7: raise newException(ValueError, "foobar: " & $n)
        else: result = n * 2

      proc asyncFact(n: int): Future[int] {.async.} =
        if n > 0: result = n * await asyncFact(n-1)
        else: result = 1

      proc main() {.async.} =
        block: # then
          assert asyncFact(3).await == 3*2
          assert asyncFact(3).then(asyncFact).await == 6*5*4*3*2
          let x1 = await fn(3)
          assert x1 == 3 * 2
          let x2 = await fn(4)
            .then((a: int) => a.float)
            .then((a: float) => $a)
          assert x2 == "8.0"

        block: # then with `onReject` callback
          var witness = 1
          await fn(6).then((a: int) => (witness = 2), (r: Error) => (witness = 3))
          assert witness == 2
          await fn(7).then((a: int) => (witness = 2), (r: Error) => (witness = 3))
          assert witness == 3

    template impl(call): untyped =
      # see D20210421T014713
      when typeof(block: call) is void:
        var ret: Future[void]
      else:
        var ret = default(maybeFuture(typeof(call)))
      typeof(ret)
    when T is void:
      type A = impl(onSuccess())
    else:
      type A = impl(onSuccess(default(T)))
    var ret: A
    {.emit: "`ret` = `future`.then(`onSuccess`, `onReject`);".}
    return ret

  proc catch*[T](future: Future[T], onReject: OnReject): Future[void] =
    ## See https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise/catch
    runnableExamples("-r:off"):
      from std/sugar import `=>`
      from std/strutils import contains

      proc fn(n: int): Future[int] {.async.} =
        if n >= 7: raise newException(ValueError, "foobar: " & $n)
        else: result = n * 2

      proc main() {.async.} =
        var reason: Error
        await fn(6).catch((r: Error) => (reason = r)) # note: `()` are needed, `=> reason = r` would not work
        assert reason == nil
        await fn(7).catch((r: Error) => (reason = r))
        assert reason != nil
        assert  "foobar: 7" in $reason.message

      discard main()

    {.emit: "`result` = `future`.catch(`onReject`);".}

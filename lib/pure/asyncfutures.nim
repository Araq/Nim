#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import std/[os, sets, tables, strutils, times, heapqueue, options, deques, cstrutils, typetraits]

import system/stacktraces

when defined(nimPreviewSlimSystem):
  import std/objectdollar # for StackTraceEntry
  import std/assertions

# TODO: This shouldn't need to be included, but should ideally be exported.
type
  CallbackFunc = proc () {.closure, gcsafe.}

  CallbackList = object
    function: CallbackFunc
    next: owned(ref CallbackList)

  FutureBase* = ref object of RootObj  ## Untyped future.
    callbacks: CallbackList

    finished: bool
    error*: ref Exception              ## Stored exception
    errorStackTrace*: string
    when not defined(release) or defined(futureLogging):
      stackTrace: seq[StackTraceEntry] ## For debugging purposes only.
      id: int
      fromProc: string

  Future*[T] = ref object of FutureBase ## Typed future.
    value: T                            ## Stored value

  FutureVar*[T] = distinct Future[T]

  FutureError* = object of Defect
    cause*: FutureBase

when not defined(release):
  var currentID = 0

const isFutureLoggingEnabled* = defined(futureLogging)

const
  NimAsyncContinueSuffix* = "NimAsyncContinue" ## For internal usage. Do not use.

when isFutureLoggingEnabled:
  import std/hashes
  type
    FutureInfo* = object
      stackTrace*: seq[StackTraceEntry]
      fromProc*: string

  var futuresInProgress {.threadvar.}: Table[FutureInfo, int]

  proc getFuturesInProgress*(): var Table[FutureInfo, int] =
    return futuresInProgress

  proc hash(s: StackTraceEntry): Hash =
    result = hash(s.procname) !& hash(s.line) !&
      hash(s.filename)
    result = !$result

  proc hash(fi: FutureInfo): Hash =
    result = hash(fi.stackTrace) !& hash(fi.fromProc)
    result = !$result

  proc getFutureInfo(fut: FutureBase): FutureInfo =
    let info = FutureInfo(
      stackTrace: fut.stackTrace,
      fromProc: fut.fromProc
    )
    return info

  proc logFutureStart(fut: FutureBase) =
    let info = getFutureInfo(fut)
    if info notin getFuturesInProgress():
      getFuturesInProgress()[info] = 0
    getFuturesInProgress()[info].inc()

  proc logFutureFinish(fut: FutureBase) =
    getFuturesInProgress()[getFutureInfo(fut)].dec()

var callSoonProc {.threadvar.}: proc (cbproc: proc ()) {.gcsafe.}

proc getCallSoonProc*(): (proc(cbproc: proc ()) {.gcsafe.}) =
  ## Get current implementation of `callSoon`.
  return callSoonProc

proc setCallSoonProc*(p: (proc(cbproc: proc ()) {.gcsafe.})) =
  ## Change current implementation of `callSoon`. This is normally called when dispatcher from `asyncdispatcher` is initialized.
  callSoonProc = p

proc callSoon*(cbproc: proc () {.gcsafe.}) =
  ## Call `cbproc` "soon".
  ##
  ## If async dispatcher is running, `cbproc` will be executed during next dispatcher tick.
  ##
  ## If async dispatcher is not running, `cbproc` will be executed immediately.
  if callSoonProc.isNil:
    # Loop not initialized yet. Call the function directly to allow setup code to use futures.
    cbproc()
  else:
    callSoonProc(cbproc)

template setupFutureBase(fromProc: string) =
  new(result)
  result.finished = false
  when not defined(release):
    result.stackTrace = getStackTraceEntries()
    result.id = currentID
    result.fromProc = fromProc
    currentID.inc()

proc newFuture*[T](fromProc: string = "unspecified"): owned(Future[T]) =
  ## Creates a new future.
  ##
  ## Specifying `fromProc`, which is a string specifying the name of the proc
  ## that this future belongs to, is a good habit as it helps with debugging.
  setupFutureBase(fromProc)
  when isFutureLoggingEnabled: logFutureStart(result)

proc newFutureVar*[T](fromProc = "unspecified"): owned(FutureVar[T]) =
  ## Create a new `FutureVar`. This Future type is ideally suited for
  ## situations where you want to avoid unnecessary allocations of Futures.
  ##
  ## Specifying `fromProc`, which is a string specifying the name of the proc
  ## that this future belongs to, is a good habit as it helps with debugging.
  let fo = newFuture[T](fromProc)
  result = typeof(result)(fo)
  when isFutureLoggingEnabled: logFutureStart(Future[T](result))

proc clean*[T](future: FutureVar[T]) =
  ## Resets the `finished` status of `future`.
  Future[T](future).finished = false
  Future[T](future).error = nil

proc checkFinished[T](future: Future[T]) =
  ## Checks whether `future` is finished. If it is then raises a
  ## `FutureError`.
  when not defined(release):
    if future.finished:
      var msg = ""
      msg.add("An attempt was made to complete a Future more than once. ")
      msg.add("Details:")
      msg.add("\n  Future ID: " & $future.id)
      msg.add("\n  Created in proc: " & future.fromProc)
      msg.add("\n  Stack trace to moment of creation:")
      msg.add("\n" & indent(($future.stackTrace).strip(), 4))
      when T is string:
        msg.add("\n  Contents (string): ")
        msg.add("\n" & indent($future.value, 4))
      msg.add("\n  Stack trace to moment of secondary completion:")
      msg.add("\n" & indent(getStackTrace().strip(), 4))
      var err = newException(FutureError, msg)
      err.cause = future
      raise err

proc call(callbacks: var CallbackList) =
  var current = callbacks
  while true:
    if not current.function.isNil:
      callSoon(current.function)

    if current.next.isNil:
      break
    else:
      current = current.next[]
  # callback will be called only once, let GC collect them now
  callbacks.next = nil
  callbacks.function = nil

proc add(callbacks: var CallbackList, function: CallbackFunc) =
  if callbacks.function.isNil:
    callbacks.function = function
    assert callbacks.next == nil
  else:
    let newCallback = new(ref CallbackList)
    newCallback.function = function
    newCallback.next = nil

    if callbacks.next == nil:
      callbacks.next = newCallback
    else:
      var last = callbacks.next
      while last.next != nil:
        last = last.next
      last.next = newCallback

proc completeImpl[T, U](future: Future[T], val: sink U, isVoid: static bool) =
  #assert(not future.finished, "Future already finished, cannot finish twice.")
  checkFinished(future)
  assert(future.error == nil)
  when not isVoid:
    future.value = val
  future.finished = true
  future.callbacks.call()
  when isFutureLoggingEnabled: logFutureFinish(future)

proc complete*[T](future: Future[T], val: sink T) =
  ## Completes `future` with value `val`.
  completeImpl(future, val, false)

proc complete*(future: Future[void], val = Future[void].default) =
  completeImpl(future, (), true)

proc complete*[T](future: FutureVar[T]) =
  ## Completes a `FutureVar`.
  template fut: untyped = Future[T](future)
  checkFinished(fut)
  assert(fut.error == nil)
  fut.finished = true
  fut.callbacks.call()
  when isFutureLoggingEnabled: logFutureFinish(Future[T](future))

proc complete*[T](future: FutureVar[T], val: sink T) =
  ## Completes a `FutureVar` with value `val`.
  ##
  ## Any previously stored value will be overwritten.
  template fut: untyped = Future[T](future)
  checkFinished(fut)
  assert(fut.error.isNil())
  fut.finished = true
  fut.value = val
  fut.callbacks.call()
  when isFutureLoggingEnabled: logFutureFinish(fut)

proc fail*[T](future: Future[T], error: ref Exception) =
  ## Completes `future` with `error`.
  #assert(not future.finished, "Future already finished, cannot finish twice.")
  checkFinished(future)
  future.finished = true
  future.error = error
  future.errorStackTrace =
    if getStackTrace(error) == "": getStackTrace() else: getStackTrace(error)
  future.callbacks.call()
  when isFutureLoggingEnabled: logFutureFinish(future)

proc clearCallbacks*(future: FutureBase) =
  future.callbacks.function = nil
  future.callbacks.next = nil

proc addCallback*(future: FutureBase, cb: proc() {.closure, gcsafe.}) =
  ## Adds the callbacks proc to be called when the future completes.
  ##
  ## If future has already completed then `cb` will be called immediately.
  assert cb != nil
  if future.finished:
    callSoon(cb)
  else:
    future.callbacks.add cb

proc addCallback*[T](future: Future[T],
                     cb: proc (future: Future[T]) {.closure, gcsafe.}) =
  ## Adds the callbacks proc to be called when the future completes.
  ##
  ## If future has already completed then `cb` will be called immediately.
  future.addCallback(
    proc() =
    cb(future)
  )

proc `callback=`*(future: FutureBase, cb: proc () {.closure, gcsafe.}) =
  ## Clears the list of callbacks and sets the callback proc to be called when the future completes.
  ##
  ## If future has already completed then `cb` will be called immediately.
  ##
  ## It's recommended to use `addCallback` or `then` instead.
  future.clearCallbacks
  future.addCallback cb

proc `callback=`*[T](future: Future[T],
    cb: proc (future: Future[T]) {.closure, gcsafe.}) =
  ## Sets the callback proc to be called when the future completes.
  ##
  ## If future has already completed then `cb` will be called immediately.
  future.callback = proc () = cb(future)

template getFilenameProcname(entry: StackTraceEntry): (string, string) =
  when compiles(entry.filenameStr) and compiles(entry.procnameStr):
    # We can't rely on "entry.filename" and "entry.procname" still being valid
    # cstring pointers, because the "string.data" buffers they pointed to might
    # be already garbage collected (this entry being a non-shallow copy,
    # "entry.filename" no longer points to "entry.filenameStr.data", but to the
    # buffer of the original object).
    (entry.filenameStr, entry.procnameStr)
  else:
    ($entry.filename, $entry.procname)

proc format(entry: StackTraceEntry): string =
  let (filename, procname) = getFilenameProcname(entry)
  let left = "$#($#)" % [filename, $entry.line]
  result = spaces(2) & "$# $#\n" % [left, procname]

proc isInternal(entry: StackTraceEntry): bool =
  # --excessiveStackTrace:off
  const internals = [
    "asyncdispatch.nim",
    "asyncfutures.nim",
    "threadimpl.nim",  # XXX ?
  ]
  let (filename, procname) = getFilenameProcname(entry)
  for line in internals:
    if filename.endsWith line:
      return true
  return false

proc `$`*(stackTraceEntries: seq[StackTraceEntry]): string =
  result = ""
  when defined(nimStackTraceOverride):
    let entries = addDebuggingInfo(stackTraceEntries)
  else:
    let entries = stackTraceEntries
  var seenEntries = initHashSet[StackTraceEntry]()
  let L = entries.len-1
  var i = L
  var j = 0
  while i >= 0:
    if entries[i].line == reraisedFromBegin or i == 0:
      j = i + int(i != 0)
      while j < L:
        if entries[j].line == reraisedFromBegin:
          break
        if entries[j].line >= 0 and not isInternal(entries[j]):
          # this skips recursive calls sadly
          if entries[j] notin seenEntries:
            result.add format(entries[j])
            seenEntries.incl entries[j]
        inc j
    dec i

proc injectStacktrace[T](future: Future[T]) =
  when not defined(release):
    const header = "\nAsync traceback:\n"

    var exceptionMsg = future.error.msg
    if header in exceptionMsg:
      # This is messy: extract the original exception message from the msg
      # containing the async traceback.
      let start = exceptionMsg.find(header)
      exceptionMsg = exceptionMsg[0..<start]

    var newMsg = exceptionMsg & header

    let entries = getStackTraceEntries(future.error)
    newMsg.add($entries)

    newMsg.add("Exception message: " & exceptionMsg & "\n")

    # # For debugging purposes
    # newMsg.add("Exception type:")
    # for entry in getStackTraceEntries(future.error):
    #   newMsg.add "\n" & $entry
    future.error.msg = newMsg

template readImpl(future, T) =
  when future is Future[T]:
    let fut {.cursor.} = future
  else:
    let fut {.cursor.} = Future[T](future)
  if fut.finished:
    if fut.error != nil:
      injectStacktrace(fut)
      raise fut.error
    when T isnot void:
      result = distinctBase(future).value
  else:
    # TODO: Make a custom exception type for this?
    raise newException(ValueError, "Future still in progress.")

proc read*[T](future: Future[T] | FutureVar[T]): lent T =
  ## Retrieves the value of `future`. Future must be finished otherwise
  ## this function will fail with a `ValueError` exception.
  ##
  ## If the result of the future is an error then that error will be raised.
  readImpl(future, T)

proc read*(future: Future[void] | FutureVar[void]) =
  readImpl(future, void)

proc readError*[T](future: Future[T]): ref Exception =
  ## Retrieves the exception stored in `future`.
  ##
  ## An `ValueError` exception will be thrown if no exception exists
  ## in the specified Future.
  if future.error != nil: return future.error
  else:
    raise newException(ValueError, "No error in future.")

proc mget*[T](future: FutureVar[T]): var T =
  ## Returns a mutable value stored in `future`.
  ##
  ## Unlike `read`, this function will not raise an exception if the
  ## Future has not been finished.
  result = Future[T](future).value

proc finished*(future: FutureBase | FutureVar): bool =
  ## Determines whether `future` has completed.
  ##
  ## `True` may indicate an error or a value. Use `failed` to distinguish.
  when future is FutureVar:
    result = (FutureBase(future)).finished
  else:
    result = future.finished

proc failed*(future: FutureBase): bool =
  ## Determines whether `future` completed with an error.
  return future.error != nil

proc asyncCheck*[T](future: Future[T]) =
  ## Sets a callback on `future` which raises an exception if the future
  ## finished with an error.
  ##
  ## This should be used instead of `discard` to discard void futures,
  ## or use `waitFor` if you need to wait for the future's completion.
  assert(not future.isNil, "Future is nil")
  # TODO: We can likely look at the stack trace here and inject the location
  # where the `asyncCheck` was called to give a better error stack message.
  proc asyncCheckCallback() =
    if future.failed:
      injectStacktrace(future)
      raise future.error
  future.callback = asyncCheckCallback

proc `and`*[T, Y](fut1: Future[T], fut2: Future[Y]): Future[void] =
  ## Returns a future which will complete once both `fut1` and `fut2`
  ## complete.
  var retFuture = newFuture[void]("asyncdispatch.`and`")
  fut1.callback =
    proc () =
      if not retFuture.finished:
        if fut1.failed: retFuture.fail(fut1.error)
        elif fut2.finished: retFuture.complete()
  fut2.callback =
    proc () =
      if not retFuture.finished:
        if fut2.failed: retFuture.fail(fut2.error)
        elif fut1.finished: retFuture.complete()
  return retFuture

proc `or`*[T, Y](fut1: Future[T], fut2: Future[Y]): Future[void] =
  ## Returns a future which will complete once either `fut1` or `fut2`
  ## complete.
  var retFuture = newFuture[void]("asyncdispatch.`or`")
  proc cb[X](fut: Future[X]) =
    if not retFuture.finished:
      if fut.failed: retFuture.fail(fut.error)
      else: retFuture.complete()
  fut1.callback = cb[T]
  fut2.callback = cb[Y]
  return retFuture

proc all*[T](futs: varargs[Future[T]]): auto =
  ## Returns a future which will complete once
  ## all futures in `futs` complete.
  ## If the argument is empty, the returned future completes immediately.
  ##
  ## If the awaited futures are not `Future[void]`, the returned future
  ## will hold the values of all awaited futures in a sequence.
  ##
  ## If the awaited futures *are* `Future[void]`,
  ## this proc returns `Future[void]`.

  when T is void:
    var
      retFuture = newFuture[void]("asyncdispatch.all")
      completedFutures = 0

    let totalFutures = len(futs)

    for fut in futs:
      fut.addCallback proc (f: Future[T]) =
        inc(completedFutures)
        if not retFuture.finished:
          if f.failed:
            retFuture.fail(f.error)
          else:
            if completedFutures == totalFutures:
              retFuture.complete()

    if totalFutures == 0:
      retFuture.complete()

    return retFuture

  else:
    var
      retFuture = newFuture[seq[T]]("asyncdispatch.all")
      retValues = newSeq[T](len(futs))
      completedFutures = 0

    for i, fut in futs:
      proc setCallback(i: int) =
        fut.addCallback proc (f: Future[T]) =
          inc(completedFutures)
          if not retFuture.finished:
            if f.failed:
              retFuture.fail(f.error)
            else:
              retValues[i] = f.read()

              if completedFutures == len(retValues):
                retFuture.complete(retValues)

      setCallback(i)

    if retValues.len == 0:
      retFuture.complete(retValues)

    return retFuture

#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

{.deprecated: "use the nimble packages `malebolgia`, `taskpools` or `weave` instead".}

## Implements Nim's `parallel & spawn statements <manual_experimental.html#parallel-amp-spawn>`_.
##
## Unstable API.
##
## See also
## ========
## * `threads module <typedthreads.html>`_ for basic thread support
## * `locks module <locks.html>`_ for locks and condition variables
## * `asyncdispatch module <asyncdispatch.html>`_ for asynchronous IO

when not compileOption("threads"):
  {.error: "Threadpool requires --threads:on option.".}

import std/[cpuinfo, cpuload, locks, os]

when defined(nimPreviewSlimSystem):
  import std/[assertions, typedthreads, sysatomics]

{.push stackTrace:off.}

type
  Semaphore = object
    c: Cond
    L: Lock
    counter: int

proc initSemaphore(cv: var Semaphore) =
  initCond(cv.c)
  initLock(cv.L)

proc destroySemaphore(cv: var Semaphore) {.inline.} =
  deinitCond(cv.c)
  deinitLock(cv.L)

proc blockUntil(cv: var Semaphore) =
  acquire(cv.L)
  while cv.counter <= 0:
    wait(cv.c, cv.L)
  dec cv.counter
  release(cv.L)

proc signal(cv: var Semaphore) =
  acquire(cv.L)
  inc cv.counter
  release(cv.L)
  signal(cv.c)

const CacheLineSize = 64 # true for most archs

type
  Barrier {.compilerproc.} = object
    entered: int
    cv: Semaphore # Semaphore takes 3 words at least
    left {.align(CacheLineSize).}: int
    interest {.align(CacheLineSize).} : bool # whether the master is interested in the "all done" event

proc barrierEnter(b: ptr Barrier) {.compilerproc, inline.} =
  # due to the signaling between threads, it is ensured we are the only
  # one with access to 'entered' so we don't need 'atomicInc' here:
  inc b.entered
  # also we need no 'fence' instructions here as soon 'nimArgsPassingDone'
  # will be called which already will perform a fence for us.

proc barrierLeave(b: ptr Barrier) {.compilerproc, inline.} =
  atomicInc b.left
  when not defined(x86): fence()
  # We may not have seen the final value of b.entered yet,
  # so we need to check for >= instead of ==.
  if b.interest and b.left >= b.entered: signal(b.cv)

proc openBarrier(b: ptr Barrier) {.compilerproc, inline.} =
  b.entered = 0
  b.left = 0
  b.interest = false

proc closeBarrier(b: ptr Barrier) {.compilerproc.} =
  fence()
  if b.left != b.entered:
    b.cv.initSemaphore()
    fence()
    b.interest = true
    fence()
    while b.left != b.entered: blockUntil(b.cv)
    destroySemaphore(b.cv)

{.pop.}

# ----------------------------------------------------------------------------

type
  AwaitInfo = object
    cv: Semaphore
    idx: int

  FlowVarBase* = ref FlowVarBaseObj ## Untyped base class for `FlowVar[T] <#FlowVar>`_.
  FlowVarBaseObj {.acyclic.} = object of RootObj
    ready, usesSemaphore, awaited: bool
    cv: Semaphore  # for 'blockUntilAny' support
    ai: ptr AwaitInfo
    idx: int
    data: pointer  # we incRef and unref it to keep it alive; note this MUST NOT
                   # be RootRef here otherwise the wrong GC keeps track of it!
    owner: pointer # ptr Worker

  FlowVarObj[T] {.acyclic.} = object of FlowVarBaseObj
    blob: T

  FlowVar*[T] {.compilerproc.} = ref FlowVarObj[T] ## A data flow variable.

  ToFreeQueue = object
    len: int
    lock: Lock
    empty: Semaphore
    data: array[128, pointer]

  WorkerProc = proc (thread, args: pointer) {.nimcall, gcsafe.}
  Worker = object
    taskArrived: Semaphore
    taskStarted: Semaphore #\
    # task data:
    f: WorkerProc
    data: pointer
    ready: bool # put it here for correct alignment!
    initialized: bool # whether it has even been initialized
    shutdown: bool # the pool requests to shut down this worker thread
    q: ToFreeQueue
    readyForTask: Semaphore

const threadpoolWaitMs {.intdefine.}: int = 100

proc blockUntil*(fv: var FlowVarBaseObj) =
  ## Waits until the value for `fv` arrives.
  ##
  ## Usually it is not necessary to call this explicitly.
  if fv.usesSemaphore and not fv.awaited:
    fv.awaited = true
    blockUntil(fv.cv)
    destroySemaphore(fv.cv)

proc selectWorker(w: ptr Worker; fn: WorkerProc; data: pointer): bool =
  if cas(addr w.ready, true, false):
    w.data = data
    w.f = fn
    signal(w.taskArrived)
    blockUntil(w.taskStarted)
    result = true
  else:
    result = false

proc cleanFlowVars(w: ptr Worker) =
  let q = addr(w.q)
  acquire(q.lock)
  for i in 0 ..< q.len:
    GC_unref(cast[RootRef](q.data[i]))
    #echo "GC_unref"
  q.len = 0
  release(q.lock)

proc wakeupWorkerToProcessQueue(w: ptr Worker) =
  # we have to ensure it's us who wakes up the owning thread.
  # This is quite horrible code, but it runs so rarely that it doesn't matter:
  while not cas(addr w.ready, true, false):
    cpuRelax()
    discard
  w.data = nil
  w.f = proc (w, a: pointer) {.nimcall.} =
    let w = cast[ptr Worker](w)
    cleanFlowVars(w)
    signal(w.q.empty)
  signal(w.taskArrived)

proc attach(fv: FlowVarBase; i: int): bool =
  acquire(fv.cv.L)
  if fv.cv.counter <= 0:
    fv.idx = i
    result = true
  else:
    result = false
  release(fv.cv.L)

proc finished(fv: var FlowVarBaseObj) =
  doAssert fv.ai.isNil, "flowVar is still attached to an 'blockUntilAny'"
  # we have to protect against the rare cases where the owner of the flowVar
  # simply disregards the flowVar and yet the "flowVar" has not yet written
  # anything to it:
  blockUntil(fv)
  if fv.data.isNil: return
  let owner = cast[ptr Worker](fv.owner)
  let q = addr(owner.q)
  acquire(q.lock)
  while not (q.len < q.data.len):
    #echo "EXHAUSTED!"
    release(q.lock)
    wakeupWorkerToProcessQueue(owner)
    blockUntil(q.empty)
    acquire(q.lock)
  q.data[q.len] = cast[pointer](fv.data)
  inc q.len
  release(q.lock)
  fv.data = nil
  # the worker thread waits for "data" to be set to nil before shutting down
  owner.data = nil

proc `=destroy`[T](fv: var FlowVarObj[T]) =
  finished(fv)
  `=destroy`(fv.blob)

proc nimCreateFlowVar[T](): FlowVar[T] {.compilerproc.} =
  new(result)

proc nimFlowVarCreateSemaphore(fv: FlowVarBase) {.compilerproc.} =
  fv.cv.initSemaphore()
  fv.usesSemaphore = true

proc nimFlowVarSignal(fv: FlowVarBase) {.compilerproc.} =
  if fv.ai != nil:
    acquire(fv.ai.cv.L)
    fv.ai.idx = fv.idx
    inc fv.ai.cv.counter
    release(fv.ai.cv.L)
    signal(fv.ai.cv.c)
  if fv.usesSemaphore:
    signal(fv.cv)

proc awaitAndThen*[T](fv: FlowVar[T]; action: proc (x: T) {.closure.}) =
  ## Blocks until `fv` is available and then passes its value
  ## to `action`.
  ##
  ## Note that due to Nim's parameter passing semantics, this
  ## means that `T` doesn't need to be copied, so `awaitAndThen` can
  ## sometimes be more efficient than the `^ proc <#^,FlowVar[T]>`_.
  blockUntil(fv[])
  when defined(nimV2):
    action(fv.blob)
  elif T is string or T is seq:
    action(cast[T](fv.data))
  elif T is ref:
    {.error: "'awaitAndThen' not available for FlowVar[ref]".}
  else:
    action(fv.blob)
  finished(fv[])

proc unsafeRead*[T](fv: FlowVar[ref T]): ptr T =
  ## Blocks until the value is available and then returns this value.
  blockUntil(fv[])
  when defined(nimV2):
    result = cast[ptr T](fv.blob)
  else:
    result = cast[ptr T](fv.data)
  finished(fv[])

proc `^`*[T](fv: FlowVar[T]): T =
  ## Blocks until the value is available and then returns this value.
  blockUntil(fv[])
  when not defined(nimV2) and (T is string or T is seq or T is ref):
    deepCopy result, cast[T](fv.data)
  else:
    result = fv.blob
  finished(fv[])

proc blockUntilAny*(flowVars: openArray[FlowVarBase]): int =
  ## Awaits any of the given `flowVars`. Returns the index of one `flowVar`
  ## for which a value arrived.
  ##
  ## A `flowVar` only supports one call to `blockUntilAny` at the same time.
  ## That means if you `blockUntilAny([a,b])` and `blockUntilAny([b,c])`
  ## the second call will only block until `c`. If there is no `flowVar` left
  ## to be able to wait on, -1 is returned.
  ##
  ## **Note:** This results in non-deterministic behaviour and should be avoided.
  var ai: AwaitInfo = AwaitInfo()
  ai.cv.initSemaphore()
  var conflicts = 0
  result = -1
  for i in 0 .. flowVars.high:
    if cas(addr flowVars[i].ai, nil, addr ai):
      if not attach(flowVars[i], i):
        result = i
        break
    else:
      inc conflicts
  if conflicts < flowVars.len:
    if result < 0:
      blockUntil(ai.cv)
      result = ai.idx
    for i in 0 .. flowVars.high:
      discard cas(addr flowVars[i].ai, addr ai, nil)
  destroySemaphore(ai.cv)

proc isReady*(fv: FlowVarBase): bool =
  ## Determines whether the specified `FlowVarBase`'s value is available.
  ##
  ## If `true`, awaiting `fv` will not block.
  if fv.usesSemaphore and not fv.awaited:
    acquire(fv.cv.L)
    result = fv.cv.counter > 0
    release(fv.cv.L)
  else:
    result = true

proc nimArgsPassingDone(p: pointer) {.compilerproc.} =
  let w = cast[ptr Worker](p)
  signal(w.taskStarted)

const
  MaxThreadPoolSize* {.intdefine.} = 256 ## Maximum size of the thread pool. 256 threads
                                         ## should be good enough for anybody ;-)
  MaxDistinguishedThread* {.intdefine.} = 32 ## Maximum number of "distinguished" threads.

type
  ThreadId* = range[0..MaxDistinguishedThread-1] ## A thread identifier.

var
  currentPoolSize: int
  maxPoolSize = MaxThreadPoolSize
  minPoolSize = 4
  gSomeReady: Semaphore
  readyWorker: ptr Worker

# A workaround for recursion deadlock issue
# https://github.com/nim-lang/Nim/issues/4597
var
  numSlavesLock: Lock
  numSlavesRunning {.guard: numSlavesLock.}: int
  numSlavesWaiting {.guard: numSlavesLock.}: int
  isSlave {.threadvar.}: bool

numSlavesLock.initLock

gSomeReady.initSemaphore()

proc slave(w: ptr Worker) {.thread.} =
  isSlave = true
  while true:
    if w.shutdown:
      w.shutdown = false
      atomicDec currentPoolSize
      while true:
        if w.data != nil:
          sleep(threadpoolWaitMs)
        else:
          # The flowvar finalizer ("finished()") set w.data to nil, so we can
          # safely terminate the thread.
          #
          # TODO: look for scenarios in which the flowvar is never finalized, so
          # a shut down thread gets stuck in this loop until the main thread exits.
          break
      break
    when declared(atomicStoreN):
      atomicStoreN(addr(w.ready), true, ATOMIC_SEQ_CST)
    else:
      w.ready = true
    readyWorker = w
    signal(gSomeReady)
    blockUntil(w.taskArrived)
    # XXX Somebody needs to look into this (why does this assertion fail
    # in Visual Studio?)
    when not defined(vcc) and not defined(tcc): assert(not w.ready)

    withLock numSlavesLock:
      inc numSlavesRunning

    w.f(w, w.data)

    withLock numSlavesLock:
      dec numSlavesRunning

    if w.q.len != 0: w.cleanFlowVars

proc distinguishedSlave(w: ptr Worker) {.thread.} =
  while true:
    when declared(atomicStoreN):
      atomicStoreN(addr(w.ready), true, ATOMIC_SEQ_CST)
    else:
      w.ready = true
    signal(w.readyForTask)
    blockUntil(w.taskArrived)
    assert(not w.ready)
    w.f(w, w.data)
    if w.q.len != 0: w.cleanFlowVars

var
  workers: array[MaxThreadPoolSize, Thread[ptr Worker]]
  workersData: array[MaxThreadPoolSize, Worker]

  distinguished: array[MaxDistinguishedThread, Thread[ptr Worker]]
  distinguishedData: array[MaxDistinguishedThread, Worker]

when defined(nimPinToCpu):
  var gCpus: Natural

proc setMinPoolSize*(size: range[1..MaxThreadPoolSize]) =
  ## Sets the minimum thread pool size. The default value of this is 4.
  minPoolSize = size

proc setMaxPoolSize*(size: range[1..MaxThreadPoolSize]) =
  ## Sets the maximum thread pool size. The default value of this
  ## is `MaxThreadPoolSize <#MaxThreadPoolSize>`_.
  maxPoolSize = size
  if currentPoolSize > maxPoolSize:
    for i in maxPoolSize..currentPoolSize-1:
      let w = addr(workersData[i])
      w.shutdown = true

when defined(nimRecursiveSpawn):
  var localThreadId {.threadvar.}: int

proc activateWorkerThread(i: int) {.noinline.} =
  workersData[i].taskArrived.initSemaphore()
  workersData[i].taskStarted.initSemaphore()
  workersData[i].initialized = true
  workersData[i].q.empty.initSemaphore()
  initLock(workersData[i].q.lock)
  createThread(workers[i], slave, addr(workersData[i]))
  when defined(nimRecursiveSpawn):
    localThreadId = i+1
  when defined(nimPinToCpu):
    if gCpus > 0: pinToCpu(workers[i], i mod gCpus)

proc activateDistinguishedThread(i: int) {.noinline.} =
  distinguishedData[i].taskArrived.initSemaphore()
  distinguishedData[i].taskStarted.initSemaphore()
  distinguishedData[i].initialized = true
  distinguishedData[i].q.empty.initSemaphore()
  initLock(distinguishedData[i].q.lock)
  distinguishedData[i].readyForTask.initSemaphore()
  createThread(distinguished[i], distinguishedSlave, addr(distinguishedData[i]))

proc setup() =
  let p = countProcessors()
  when defined(nimPinToCpu):
    gCpus = p
  currentPoolSize = min(p, MaxThreadPoolSize)
  readyWorker = addr(workersData[0])
  for i in 0..<currentPoolSize: activateWorkerThread(i)

proc preferSpawn*(): bool =
  ## Use this proc to determine quickly if a `spawn` or a direct call is
  ## preferable.
  ##
  ## If it returns `true`, a `spawn` may make sense. In general
  ## it is not necessary to call this directly; use the `spawnX template
  ## <#spawnX.t>`_ instead.
  result = gSomeReady.counter > 0

proc spawn*(call: sink typed) {.magic: "Spawn".} =
  ## Always spawns a new task, so that the `call` is never executed on
  ## the calling thread.
  ##
  ## `call` has to be a proc call `p(...)` where `p` is gcsafe and has a
  ## return type that is either `void` or compatible with `FlowVar[T]`.
  discard "It uses `nimSpawn3` internally"

proc pinnedSpawn*(id: ThreadId; call: sink typed) {.magic: "Spawn".} =
  ## Always spawns a new task on the worker thread with `id`, so that
  ## the `call` is **always** executed on the thread.
  ##
  ## `call` has to be a proc call `p(...)` where `p` is gcsafe and has a
  ## return type that is either `void` or compatible with `FlowVar[T]`.
  discard "It uses `nimSpawn4` internally"

template spawnX*(call) =
  ## Spawns a new task if a CPU core is ready, otherwise executes the
  ## call in the calling thread.
  ##
  ## Usually, it is advised to use the `spawn proc <#spawn,sinktyped>`_
  ## in order to not block the producer for an unknown amount of time.
  ##
  ## `call` has to be a proc call `p(...)` where `p` is gcsafe and has a
  ## return type that is either 'void' or compatible with `FlowVar[T]`.
  (if preferSpawn(): spawn call else: call)

proc parallel*(body: untyped) {.magic: "Parallel".}
  ## A parallel section can be used to execute a block in parallel.
  ##
  ## `body` has to be in a DSL that is a particular subset of the language.
  ##
  ## Please refer to `the manual <manual_experimental.html#parallel-amp-spawn>`_
  ## for further information.

var
  state: ThreadPoolState
  stateLock: Lock

initLock stateLock

proc nimSpawn3(fn: WorkerProc; data: pointer) {.compilerproc.} =
  # implementation of 'spawn' that is used by the code generator.
  while true:
    if selectWorker(readyWorker, fn, data): return
    for i in 0..<currentPoolSize:
      if selectWorker(addr(workersData[i]), fn, data): return

    # determine what to do, but keep in mind this is expensive too:
    # state.calls < maxPoolSize: warmup phase
    # (state.calls and 127) == 0: periodic check
    if state.calls < maxPoolSize or (state.calls and 127) == 0:
      # ensure the call to 'advice' is atomic:
      if tryAcquire(stateLock):
        if currentPoolSize < minPoolSize:
          if not workersData[currentPoolSize].initialized:
            activateWorkerThread(currentPoolSize)
          let w = addr(workersData[currentPoolSize])
          atomicInc currentPoolSize
          if selectWorker(w, fn, data):
            release(stateLock)
            return

        case advice(state)
        of doNothing: discard
        of doCreateThread:
          if currentPoolSize < maxPoolSize:
            if not workersData[currentPoolSize].initialized:
              activateWorkerThread(currentPoolSize)
            let w = addr(workersData[currentPoolSize])
            atomicInc currentPoolSize
            if selectWorker(w, fn, data):
              release(stateLock)
              return
            # else we didn't succeed but some other thread, so do nothing.
        of doShutdownThread:
          if currentPoolSize > minPoolSize:
            let w = addr(workersData[currentPoolSize-1])
            w.shutdown = true
          # we don't free anything here. Too dangerous.
        release(stateLock)
      # else the acquire failed, but this means some
      # other thread succeeded, so we don't need to do anything here.
    when defined(nimRecursiveSpawn):
      if localThreadId > 0:
        # we are a worker thread, so instead of waiting for something which
        # might as well never happen (see tparallel_quicksort), we run the task
        # on the current thread instead.
        var self = addr(workersData[localThreadId-1])
        fn(self, data)
        blockUntil(self.taskStarted)
        return

    if isSlave:
      # Run under lock until `numSlavesWaiting` increment to avoid a
      # race (otherwise two last threads might start waiting together)
      withLock numSlavesLock:
        if numSlavesRunning <= numSlavesWaiting + 1:
          # All the other slaves are waiting
          # If we wait now, we-re deadlocked until
          # an external spawn happens !
          if currentPoolSize < maxPoolSize:
            if not workersData[currentPoolSize].initialized:
              activateWorkerThread(currentPoolSize)
            let w = addr(workersData[currentPoolSize])
            atomicInc currentPoolSize
            if selectWorker(w, fn, data):
              return
          else:
            # There is no place in the pool. We're deadlocked.
            # echo "Deadlock!"
            discard

        inc numSlavesWaiting

    blockUntil(gSomeReady)

    if isSlave:
      withLock numSlavesLock:
        dec numSlavesWaiting

var
  distinguishedLock: Lock

initLock distinguishedLock

proc nimSpawn4(fn: WorkerProc; data: pointer; id: ThreadId) {.compilerproc.} =
  acquire(distinguishedLock)
  if not distinguishedData[id].initialized:
    activateDistinguishedThread(id)
  release(distinguishedLock)
  while true:
    if selectWorker(addr(distinguishedData[id]), fn, data): break
    blockUntil(distinguishedData[id].readyForTask)


proc sync*() =
  ## A simple barrier to wait for all `spawn`ed tasks.
  ##
  ## If you need more elaborate waiting, you have to use an explicit barrier.
  while true:
    var allReady = true
    for i in 0 ..< currentPoolSize:
      if not allReady: break
      allReady = allReady and workersData[i].ready
    if allReady: break
    sleep(threadpoolWaitMs)
    # We cannot "blockUntil(gSomeReady)" because workers may be shut down between
    # the time we establish that some are not "ready" and the time we wait for a
    # "signal(gSomeReady)" from inside "slave()" that can never come.

setup()

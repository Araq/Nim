#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

##[
Thread support for Nim. Threads allow multiple functions to execute concurrently.
 
In Nim, threads are a low-level construct and using a library like `malebolgia`, `taskpools` or `weave` is recommended.
 
When creating a thread, you can pass arguments to it. As Nim's garbage collector does not use atomic references, sharing
`ref` and other variables managed by the garbage collector between threads is not supported.
Use global variables to do so, or pointers.
 
Memory allocated using [`sharedAlloc`](./system.html#allocShared.t%2CNatural) can be used and shared between threads.

To communicate between threads, consider using [channels](./system.html#Channel)

Examples
========

```Nim
import std/locks

var
  thr: array[0..4, Thread[tuple[a,b: int]]]
  L: Lock

proc threadFunc(interval: tuple[a,b: int]) {.thread.} =
  for i in interval.a..interval.b:
    acquire(L) # lock stdout
    echo i
    release(L)

initLock(L)

for i in 0..high(thr):
  createThread(thr[i], threadFunc, (i*10, i*10+5))
joinThreads(thr)

deinitLock(L)
```
 
When using a memory management strategy that supports shared heaps like `arc` or `boehm`,
you can pass pointer to threads and share memory between them, but the memory must outlive the thread.
The default memory management strategy, `orc`, supports this.
The example below is **not valid** for memory management strategies that use local heaps like `refc`!

```Nim
import locks
 
var l: Lock
 
proc threadFunc(obj: ptr seq[int]) {.thread.} =
  withLock l:
    for i in 0..<100:
      obj[].add(obj[].len * obj[].len)
 
proc threadHandler() =
  var thr: array[0..4, Thread[ptr seq[int]]]
  var s = newSeq[int]()

  for i in 0..high(thr):
    createThread(thr[i], threadFunc, s.addr)
  joinThreads(thr)
  echo s
 
initLock(l)
threadHandler()
deinitLock(l)
```
]##


import std/private/[threadtypes]
export Thread

import system/ansi_c

when defined(nimPreviewSlimSystem):
  import std/assertions

when defined(genode):
  import genode/env

when hostOS == "any":
  {.error: "Threads not implemented for os:any. Please compile with --threads:off.".}

when hasAllocStack or defined(zephyr) or defined(freertos) or defined(nuttx) or
    defined(cpu16) or defined(cpu8):
  const
    nimThreadStackSize {.intdefine.} = 8192
    nimThreadStackGuard {.intdefine.} = 128

    StackGuardSize = nimThreadStackGuard
    ThreadStackSize = nimThreadStackSize - nimThreadStackGuard
else:
  const
    StackGuardSize = 4096
    ThreadStackMask =
      when defined(genode):
        1024*64*sizeof(int)-1
      else:
        1024*256*sizeof(int)-1

    ThreadStackSize = ThreadStackMask+1 - StackGuardSize


when defined(gcDestructors):
  proc allocThreadStorage(size: int): pointer =
    result = c_malloc(csize_t size)
    zeroMem(result, size)
else:
  template allocThreadStorage(size: untyped): untyped = allocShared0(size)

#const globalsSlot = ThreadVarSlot(0)
#sysAssert checkSlot.int == globalsSlot.int

# Zephyr doesn't include this properly without some help
when defined(zephyr):
  {.emit: """/*INCLUDESECTION*/
  #include <pthread.h>
  """.}


# We jump through some hops here to ensure that Nim thread procs can have
# the Nim calling convention. This is needed because thread procs are
# ``stdcall`` on Windows and ``noconv`` on UNIX. Alternative would be to just
# use ``stdcall`` since it is mapped to ``noconv`` on UNIX anyway.



{.push stack_trace:off.}
when defined(windows):
  proc threadProcWrapper[TArg](closure: pointer): int32 {.stdcall.} =
    result = 0'i32
    nimThreadProcWrapperBody(closure)
    # implicitly return 0
elif defined(genode):
  proc threadProcWrapper[TArg](closure: pointer) {.noconv.} =
    nimThreadProcWrapperBody(closure)
else:
  proc threadProcWrapper[TArg](closure: pointer): pointer {.noconv.} =
    result = nil
    nimThreadProcWrapperBody(closure)
{.pop.}

proc running*[TArg](t: Thread[TArg]): bool {.inline.} =
  ## Returns true if `t` is running.
  result = t.dataFn != nil

proc handle*[TArg](t: Thread[TArg]): SysThread {.inline.} =
  ## Returns the thread handle of `t`.
  result = t.sys

when hostOS == "windows":
  const MAXIMUM_WAIT_OBJECTS = 64

  proc joinThread*[TArg](t: Thread[TArg]) {.inline.} =
    ## Waits for the thread `t` to finish.
    discard waitForSingleObject(t.sys, -1'i32)

  proc joinThreads*[TArg](t: varargs[Thread[TArg]]) =
    ## Waits for every thread in `t` to finish.
    var a: array[MAXIMUM_WAIT_OBJECTS, SysThread] = default(array[MAXIMUM_WAIT_OBJECTS, SysThread])
    var k = 0
    while k < len(t):
      var count = min(len(t) - k, MAXIMUM_WAIT_OBJECTS)
      for i in 0..(count - 1): a[i] = t[i + k].sys
      discard waitForMultipleObjects(int32(count),
                                     cast[ptr SysThread](addr(a)), 1, -1)
      inc(k, MAXIMUM_WAIT_OBJECTS)

elif defined(genode):
  proc joinThread*[TArg](t: Thread[TArg]) {.importcpp.}
    ## Waits for the thread `t` to finish.

  proc joinThreads*[TArg](t: varargs[Thread[TArg]]) =
    ## Waits for every thread in `t` to finish.
    for i in 0..t.high: joinThread(t[i])

else:
  proc joinThread*[TArg](t: Thread[TArg]) {.inline.} =
    ## Waits for the thread `t` to finish.
    discard pthread_join(t.sys, nil)

  proc joinThreads*[TArg](t: varargs[Thread[TArg]]) =
    ## Waits for every thread in `t` to finish.
    for i in 0..t.high: joinThread(t[i])

when false:
  # XXX a thread should really release its heap here somehow:
  proc destroyThread*[TArg](t: var Thread[TArg]) =
    ## Forces the thread `t` to terminate. This is potentially dangerous if
    ## you don't have full control over `t` and its acquired resources.
    when hostOS == "windows":
      discard TerminateThread(t.sys, 1'i32)
    else:
      discard pthread_cancel(t.sys)
    when declared(registerThread): unregisterThread(addr(t))
    t.dataFn = nil
    ## if thread `t` already exited, `t.core` will be `null`.
    if not isNil(t.core):
      deallocThreadStorage(t.core)
      t.core = nil

when hostOS == "windows":
  proc createThread*[TArg](t: var Thread[TArg],
                           tp: proc (arg: TArg) {.thread, nimcall.},
                           param: TArg) =
    ## Creates a new thread `t` and starts its execution.
    ##
    ## Entry point is the proc `tp`.
    ## `param` is passed to `tp`. `TArg` can be `void` if you
    ## don't need to pass any data to the thread.
    t.core = cast[PGcThread](allocThreadStorage(sizeof(GcThread)))

    when TArg isnot void: t.data = param
    t.dataFn = tp
    when hasSharedHeap: t.core.stackSize = ThreadStackSize
    var dummyThreadId: int32 = 0'i32
    t.sys = createThread(nil, ThreadStackSize, threadProcWrapper[TArg],
                         addr(t), 0'i32, dummyThreadId)
    if t.sys <= 0:
      raise newException(ResourceExhaustedError, "cannot create thread")

  proc pinToCpu*[Arg](t: var Thread[Arg]; cpu: Natural) =
    ## Pins a thread to a `CPU`:idx:.
    ##
    ## In other words sets a thread's `affinity`:idx:.
    ## If you don't know what this means, you shouldn't use this proc.
    setThreadAffinityMask(t.sys, uint(1 shl cpu))

elif defined(genode):
  var affinityOffset: cuint = 1
    ## CPU affinity offset for next thread, safe to roll-over.

  proc createThread*[TArg](t: var Thread[TArg],
                           tp: proc (arg: TArg) {.thread, nimcall.},
                           param: TArg) =
    t.core = cast[PGcThread](allocThreadStorage(sizeof(GcThread)))

    when TArg isnot void: t.data = param
    t.dataFn = tp
    when hasSharedHeap: t.stackSize = ThreadStackSize
    t.sys.initThread(
      runtimeEnv,
      ThreadStackSize.culonglong,
      threadProcWrapper[TArg], addr(t), affinityOffset)
    inc affinityOffset

  proc pinToCpu*[Arg](t: var Thread[Arg]; cpu: Natural) =
    {.hint: "cannot change Genode thread CPU affinity after initialization".}
    discard

else:
  proc createThread*[TArg](t: var Thread[TArg],
                           tp: proc (arg: TArg) {.thread, nimcall.},
                           param: TArg) =
    ## Creates a new thread `t` and starts its execution.
    ##
    ## Entry point is the proc `tp`. `param` is passed to `tp`.
    ## `TArg` can be `void` if you
    ## don't need to pass any data to the thread.
    t.core = cast[PGcThread](allocThreadStorage(sizeof(GcThread)))

    when TArg isnot void: t.data = param
    t.dataFn = tp
    when hasSharedHeap: t.core.stackSize = ThreadStackSize
    var a {.noinit.}: Pthread_attr
    doAssert pthread_attr_init(a) == 0
    when hasAllocStack:
      var
        rawstk = allocThreadStorage(ThreadStackSize + StackGuardSize)
        stk = cast[pointer](cast[uint](rawstk) + StackGuardSize)
      let setstacksizeResult = pthread_attr_setstack(addr a, stk, ThreadStackSize)
      t.rawStack = rawstk
    else:
      let setstacksizeResult = pthread_attr_setstacksize(a, ThreadStackSize)

    when not defined(ios):
      # This fails on iOS
      doAssert(setstacksizeResult == 0)
    if pthread_create(t.sys, a, threadProcWrapper[TArg], addr(t)) != 0:
      raise newException(ResourceExhaustedError, "cannot create thread")
    doAssert pthread_attr_destroy(a) == 0

  proc pinToCpu*[Arg](t: var Thread[Arg]; cpu: Natural) =
    ## Pins a thread to a `CPU`:idx:.
    ##
    ## In other words sets a thread's `affinity`:idx:.
    ## If you don't know what this means, you shouldn't use this proc.
    when not defined(macosx):
      var s {.noinit.}: CpuSet
      cpusetZero(s)
      cpusetIncl(cpu.cint, s)
      setAffinity(t.sys, csize_t(sizeof(s)), s)

proc createThread*(t: var Thread[void], tp: proc () {.thread, nimcall.}) =
  createThread[void](t, tp)

when not defined(gcOrc):
  include system/threadids

include system/inclrtl
import std/atomics

const hasSharedHeap* = defined(boehmgc) or defined(gogc) # don't share heaps; every thread has its own

when defined(windows):
  type
    Handle* = int
    SysThread* = Handle
    WinThreadProc* = proc (x: pointer): int32 {.stdcall.}

  proc createThread*(lpThreadAttributes: pointer, dwStackSize: int32,
                     lpStartAddress: WinThreadProc,
                     lpParameter: pointer,
                     dwCreationFlags: int32,
                     lpThreadId: var int32): SysThread {.
    stdcall, dynlib: "kernel32", importc: "CreateThread".}

  proc winSuspendThread*(hThread: SysThread): int32 {.
    stdcall, dynlib: "kernel32", importc: "SuspendThread".}

  proc winResumeThread*(hThread: SysThread): int32 {.
    stdcall, dynlib: "kernel32", importc: "ResumeThread".}

  proc waitForSingleObject*(hHandle: SysThread, dwMilliseconds: int32): int32 {.
    stdcall, dynlib: "kernel32", importc: "WaitForSingleObject".}

  proc waitForMultipleObjects*(nCount: int32,
                              lpHandles: ptr SysThread,
                              bWaitAll: int32,
                              dwMilliseconds: int32): int32 {.
    stdcall, dynlib: "kernel32", importc: "WaitForMultipleObjects".}

  proc terminateThread*(hThread: SysThread, dwExitCode: int32): int32 {.
    stdcall, dynlib: "kernel32", importc: "TerminateThread".}

  proc setThreadAffinityMask*(hThread: SysThread, dwThreadAffinityMask: uint) {.
    importc: "SetThreadAffinityMask", stdcall, header: "<windows.h>".}

elif defined(genode):
  const
    GenodeHeader* = "genode_cpp/threads.h"
  type
    SysThread* {.importcpp: "Nim::SysThread",
                 header: GenodeHeader, final, pure.} = object
    GenodeThreadProc* = proc (x: pointer) {.noconv.}

  proc initThread*(s: var SysThread,
                  env: GenodeEnv,
                  stackSize: culonglong,
                  entry: GenodeThreadProc,
                  arg: pointer,
                  affinity: cuint) {.
    importcpp: "#.initThread(@)".}


else:
  when not (defined(macosx) or defined(haiku)):
    {.passl: "-pthread".}

  when not defined(haiku):
    {.passc: "-pthread".}

  const
    schedh = "#define _GNU_SOURCE\n#include <sched.h>"
    pthreadh* = "#define _GNU_SOURCE\n#include <pthread.h>"

  when not declared(Time):
    when defined(linux):
      type Time = clong
    else:
      type Time = int

  when (defined(linux) or defined(nintendoswitch)) and defined(amd64):
    type
      SysThread* {.importc: "pthread_t",
                  header: "<sys/types.h>" .} = distinct culong
      Pthread_attr* {.importc: "pthread_attr_t",
                    header: "<sys/types.h>".} = object
        abi: array[56 div sizeof(clong), clong]
  elif defined(openbsd) and defined(amd64):
    type
      SysThread* {.importc: "pthread_t", header: "<pthread.h>".} = object
      Pthread_attr* {.importc: "pthread_attr_t",
                       header: "<pthread.h>".} = object
  else:
    type
      SysThread* {.importc: "pthread_t", header: "<sys/types.h>".} = int
      Pthread_attr* {.importc: "pthread_attr_t",
                       header: "<sys/types.h>".} = object
  type
    Timespec* {.importc: "struct timespec", header: "<time.h>".} = object
      tv_sec*: Time
      tv_nsec*: clong

  proc pthread_attr_init*(a1: var Pthread_attr): cint {.
    importc, header: pthreadh.}
  proc pthread_attr_setstack*(a1: ptr Pthread_attr, a2: pointer, a3: int): cint {.
    importc, header: pthreadh.}
  proc pthread_attr_setstacksize*(a1: var Pthread_attr, a2: int): cint {.
    importc, header: pthreadh.}
  proc pthread_attr_destroy*(a1: var Pthread_attr): cint {.
    importc, header: pthreadh.}

  proc pthread_create*(a1: var SysThread, a2: var Pthread_attr,
            a3: proc (x: pointer): pointer {.noconv.},
            a4: pointer): cint {.importc: "pthread_create",
            header: pthreadh.}
  proc pthread_join*(a1: SysThread, a2: ptr pointer): cint {.
    importc, header: pthreadh.}

  proc pthread_cancel*(a1: SysThread): cint {.
    importc: "pthread_cancel", header: pthreadh.}

  type CpuSet* {.importc: "cpu_set_t", header: schedh.} = object
     when defined(linux) and defined(amd64):
       abi: array[1024 div (8 * sizeof(culong)), culong]

  proc cpusetZero*(s: var CpuSet) {.importc: "CPU_ZERO", header: schedh.}
  proc cpusetIncl*(cpu: cint; s: var CpuSet) {.
    importc: "CPU_SET", header: schedh.}

  when defined(android):
    # libc of android doesn't implement pthread_setaffinity_np,
    # it exposes pthread_gettid_np though, so we can use that in combination
    # with sched_setaffinity to set the thread affinity.
    type Pid* {.importc: "pid_t", header: "<sys/types.h>".} = int32 # From posix_other.nim

    proc setAffinityTID*(tid: Pid; setsize: csize_t; s: var CpuSet) {.
      importc: "sched_setaffinity", header: schedh.}

    proc pthread_gettid_np*(thread: SysThread): Pid {.
      importc: "pthread_gettid_np", header: pthreadh.}

    proc setAffinity*(thread: SysThread; setsize: csize_t; s: var CpuSet) =
      setAffinityTID(pthread_gettid_np(thread), setsize, s)
  else:
    proc setAffinity*(thread: SysThread; setsize: csize_t; s: var CpuSet) {.
      importc: "pthread_setaffinity_np", header: pthreadh.}


const
  emulatedThreadVars* = compileOption("tlsEmulation")
# we preallocate a fixed size for thread local storage, so that no heap
# allocations are needed. Currently less than 16K are used on a 64bit machine.
# We use `float` for proper alignment:
const nimTlsSize {.intdefine.} = 16000
type
  ThreadLocalStorage* = array[0..(nimTlsSize div sizeof(float)), float]
  PGcThread* = ptr GcThread
  GcThread* {.pure, inheritable.} = object
    when emulatedThreadVars:
      tls*: ThreadLocalStorage
    else:
      nil
    when hasSharedHeap:
      next*, prev*: PGcThread
      stackBottom*, stackTop*: pointer
      stackSize*: int
    else:
      nil

const hasAllocStack* = defined(zephyr) # maybe freertos too?

type
  Thread*[TArg] = object
    core*: Atomic[PGcThread]
    sys*: SysThread
    when TArg is void:
      dataFn*: Atomic[proc () {.nimcall, gcsafe.}]
    else:
      dataFn*: Atomic[proc (m: TArg) {.nimcall, gcsafe.}]
      data*: Atomic[TArg]
    when hasAllocStack:
      rawStack*: pointer

proc `=copy`*[TArg](x: var Thread[TArg], y: Thread[TArg]) {.error.}

import std/private/threadtypes

when defined(windows):
  type
    ThreadVarSlot = distinct int32

  proc threadVarAlloc(): ThreadVarSlot {.
    importc: "TlsAlloc", stdcall, header: "<windows.h>".}
  proc threadVarSetValue(dwTlsIndex: ThreadVarSlot, lpTlsValue: pointer) {.
    importc: "TlsSetValue", stdcall, header: "<windows.h>".}
  proc tlsGetValue(dwTlsIndex: ThreadVarSlot): pointer {.
    importc: "TlsGetValue", stdcall, header: "<windows.h>".}

  proc getLastError(): uint32 {.
    importc: "GetLastError", stdcall, header: "<windows.h>".}
  proc setLastError(x: uint32) {.
    importc: "SetLastError", stdcall, header: "<windows.h>".}

  proc threadVarGetValue(dwTlsIndex: ThreadVarSlot): pointer =
    let realLastError = getLastError()
    result = tlsGetValue(dwTlsIndex)
    setLastError(realLastError)

elif defined(genode):
  const
    GenodeHeader = "genode_cpp/threads.h"

  type
    ThreadVarSlot = int

  proc threadVarAlloc(): ThreadVarSlot = 0

  proc offMainThread(): bool {.
    importcpp: "Nim::SysThread::offMainThread",
    header: GenodeHeader.}

  proc threadVarSetValue(value: pointer) {.
    importcpp: "Nim::SysThread::threadVarSetValue(@)",
    header: GenodeHeader.}

  proc threadVarGetValue(): pointer {.
    importcpp: "Nim::SysThread::threadVarGetValue()",
    header: GenodeHeader.}

  var mainTls: pointer

  proc threadVarSetValue(s: ThreadVarSlot, value: pointer) {.inline.} =
    if offMainThread():
      threadVarSetValue(value);
    else:
      mainTls = value

  proc threadVarGetValue(s: ThreadVarSlot): pointer {.inline.} =
    if offMainThread():
      threadVarGetValue();
    else:
      mainTls

else:
  when not (defined(macosx) or defined(haiku)):
    {.passl: "-pthread".}

  when not defined(haiku):
    {.passc: "-pthread".}

  when (defined(linux) or defined(nintendoswitch)) and defined(amd64):
    type
      ThreadVarSlot {.importc: "pthread_key_t",
                    header: "<sys/types.h>".} = distinct cuint
  elif defined(openbsd) and defined(amd64):
    type
      ThreadVarSlot {.importc: "pthread_key_t",
                     header: "<pthread.h>".} = cint
  else:
    type
      ThreadVarSlot {.importc: "pthread_key_t",
                     header: "<sys/types.h>".} = object

  proc pthread_getspecific(a1: ThreadVarSlot): pointer {.
    importc: "pthread_getspecific", header: pthreadh.}
  proc pthread_key_create(a1: ptr ThreadVarSlot,
                          destruct: proc (x: pointer) {.noconv.}): int32 {.
    importc: "pthread_key_create", header: pthreadh.}
  proc pthread_key_delete(a1: ThreadVarSlot): int32 {.
    importc: "pthread_key_delete", header: pthreadh.}

  proc pthread_setspecific(a1: ThreadVarSlot, a2: pointer): int32 {.
    importc: "pthread_setspecific", header: pthreadh.}

  proc threadVarAlloc(): ThreadVarSlot {.inline.} =
    result = default(ThreadVarSlot)
    discard pthread_key_create(addr(result), nil)
  proc threadVarSetValue(s: ThreadVarSlot, value: pointer) {.inline.} =
    discard pthread_setspecific(s, value)
  proc threadVarGetValue(s: ThreadVarSlot): pointer {.inline.} =
    result = pthread_getspecific(s)


when emulatedThreadVars:
  # the compiler generates this proc for us, so that we can get the size of
  # the thread local var block; we use this only for sanity checking though
  proc nimThreadVarsSize(): int {.noconv, importc: "NimThreadVarsSize".}



when emulatedThreadVars:
  var globalsSlot: ThreadVarSlot

  when not defined(useNimRtl):
    var mainThread: GcThread

  proc GetThreadLocalVars(): pointer {.compilerRtl, inl.} =
    result = addr(cast[PGcThread](threadVarGetValue(globalsSlot)).tls)

  proc initThreadVarsEmulation() {.compilerproc, inline.} =
    when not defined(useNimRtl):
      globalsSlot = threadVarAlloc()
      when declared(mainThread):
        threadVarSetValue(globalsSlot, addr(mainThread))

when not defined(useNimRtl):
  when emulatedThreadVars:
    if nimThreadVarsSize() > sizeof(ThreadLocalStorage):
      c_fprintf(cstderr, """too large thread local storage size requested,
use -d:\"nimTlsSize=X\" to setup even more or stop using unittest.nim""")
      rawQuit 1

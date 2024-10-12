discard """
  output: '''
Hello from thread
Hello from thread
Hello from thread
Hello from thread
'''
  cmd: "nim $target --hints:on --threads:on --tlsEmulation:off $options $file"
  retries: 2
"""
# Copied from stdlib
import strutils

const
  StackGuardSize = 4096
  ThreadStackMask = 1024*256*sizeof(int)-1
  ThreadStackSize = ThreadStackMask+1 - StackGuardSize

type ThreadFunc = proc() {.thread.}

when defined(posix):
  import posix

  proc runInForeignThread(f: ThreadFunc) =
    proc wrapper(p: pointer): pointer {.noconv.} =
      let thr = cast[ThreadFunc](p)
      setupForeignThreadGc()
      thr()
      tearDownForeignThreadGc()
      setupForeignThreadGc()
      thr()
      tearDownForeignThreadGc()
      result = nil

    var attrs {.noinit.}: PthreadAttr
    doAssert pthread_attr_init(addr attrs) == 0
    doAssert pthread_attr_setstacksize(addr attrs, ThreadStackSize) == 0
    var tid: Pthread
    doAssert pthread_create(addr tid, addr attrs, wrapper, f) == 0
    doAssert pthread_join(tid, nil) == 0

elif defined(windows):
  import winlean
  type
    WinThreadProc = proc (x: pointer): int32 {.stdcall.}

  proc createThread(lpThreadAttributes: pointer, dwStackSize: DWORD,
                     lpStartAddress: WinThreadProc,
                     lpParameter: pointer,
                     dwCreationFlags: DWORD,
                     lpThreadId: var DWORD): Handle {.
    stdcall, dynlib: "kernel32", importc: "CreateThread".}

  proc wrapper(p: pointer): int32 {.stdcall.} =
    let thr = cast[ThreadFunc](p)
    setupForeignThreadGc()
    thr()
    tearDownForeignThreadGc()
    setupForeignThreadGc()
    thr()
    tearDownForeignThreadGc()
    result = 0'i32

  proc runInForeignThread(f: ThreadFunc) =
    var dummyThreadId: DWORD
    var h = createThread(nil, ThreadStackSize.int32, wrapper.WinThreadProc, cast[pointer](f), 0, dummyThreadId)
    doAssert h != 0.Handle
    doAssert waitForSingleObject(h, -1'i32) == 0.DWORD

else:
  {.fatal: "Unknown system".}

proc runInNativeThread(f: ThreadFunc) =
  proc wrapper(f: ThreadFunc) {.thread.} =
    # These operations must be NOP
    setupForeignThreadGc()
    tearDownForeignThreadGc()
    f()
    f()
  var thr: Thread[ThreadFunc]
  createThread(thr, wrapper, f)
  joinThread(thr)

proc f {.thread.} =
  var msg = "Hello " & "from thread"
  echo msg

runInForeignThread(f)
runInNativeThread(f)

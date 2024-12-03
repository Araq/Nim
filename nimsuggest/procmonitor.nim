# Monitor a client process and shutdown the current process, if the client
# process is found to be dead

import os

when defined(posix):
  import posix_utils
  import posix

when defined(windows):
  import winlean

when defined(posix):
  proc monitorClientProcessIdThreadProc(pid: int) {.thread.} =
    while true:
      sleep(1000)
      try:
        sendSignal(Pid(pid), 0)
      except:
        discard kill(Pid(getCurrentProcessId()), cint(SIGTERM))

when defined(windows):
  proc monitorClientProcessIdThreadProc(pid: int) {.thread.} =
    var process = openProcess(SYNCHRONIZE, 0, DWORD(pid))
    if process != 0:
      discard waitForSingleObject(process, INFINITE)
      discard closeHandle(process)
    quit(0)

var tid: Thread[int]

proc hookProcMonitor*(pid: int) =
  when defined(posix) or defined(windows):
    createThread(tid, monitorClientProcessIdThreadProc, pid)

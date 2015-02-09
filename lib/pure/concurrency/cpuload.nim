#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements a helper for a thread pool to determine whether
## creating a thread is a good idea.

when defined(windows):
  import winlean, os, strutils, math

  proc `-`(a, b: TFILETIME): int64 = a.rdFileTime - b.rdFileTime
elif defined(linux):
  from cpuinfo import countProcessors

type
  ThreadPoolAdvice* = enum
    doNothing,
    doCreateThread,  # create additional thread for throughput
    doShutdownThread # too many threads are busy, shutdown one

  ThreadPoolState* = object
    when defined(windows):
      prevSysKernel, prevSysUser, prevProcKernel, prevProcUser: TFILETIME
    calls*: int

proc advice*(s: var ThreadPoolState): ThreadPoolAdvice =
  when defined(windows):
    var
      sysIdle, sysKernel, sysUser,
        procCreation, procExit, procKernel, procUser: TFILETIME
    if getSystemTimes(sysIdle, sysKernel, sysUser) == 0 or
        getProcessTimes(THandle(-1), procCreation, procExit, 
                        procKernel, procUser) == 0:
      return doNothing
    if s.calls > 0:
      let
        sysKernelDiff = sysKernel - s.prevSysKernel
        sysUserDiff = sysUser - s.prevSysUser

        procKernelDiff = procKernel - s.prevProcKernel
        procUserDiff = procUser - s.prevProcUser

        sysTotal = int(sysKernelDiff + sysUserDiff)
        procTotal = int(procKernelDiff + procUserDiff)
      # total CPU usage < 85% --> create a new worker thread.
      # Measurements show that 100% and often even 90% is not reached even
      # if all my cores are busy.
      if sysTotal == 0 or procTotal / sysTotal < 0.85:
        result = doCreateThread
    s.prevSysKernel = sysKernel
    s.prevSysUser = sysUser
    s.prevProcKernel = procKernel
    s.prevProcUser = procUser
  elif defined(linux):
    proc fscanf(c: File, frmt: cstring) {.varargs, importc, 
      header: "<stdio.h>".}

    var f = open("/proc/loadavg")
    var b: float
    var busy, total: int
    fscanf(f,"%lf %lf %lf %ld/%ld",
           addr b, addr b, addr b, addr busy, addr total)
    f.close()
    let cpus = countProcessors()
    if busy-1 < cpus:
      result = doCreateThread
    elif busy-1 >= cpus*2:
      result = doShutdownThread
    else:
      result = doNothing
  else:
    # XXX implement this for other OSes
    result = doNothing
  inc s.calls

when isMainModule:
  import math, os, threadpool
  proc busyLoop() =
    while true:
      discard random(80)
      os.sleep(100)

  spawn busyLoop()
  spawn busyLoop()
  spawn busyLoop()
  spawn busyLoop()

  var s: ThreadPoolState

  for i in 1 .. 70:
    echo advice(s)
    os.sleep(1000)

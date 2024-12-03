#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements a proc to determine the number of CPUs / cores.

runnableExamples:
  doAssert countProcessors() > 0


include "system/inclrtl"

when defined(js):
  import std/jsffi
  proc countProcessorsImpl(): int =
    when defined(nodejs):
      let jsOs = require("os")
      let jsObj = jsOs.cpus().length
    else:
      # `navigator.hardwareConcurrency`
      # works on browser as well as deno.
      let navigator{.importcpp.}: JsObject
      let jsObj = navigator.hardwareConcurrency
    result = jsObj.to int
else:
  when defined(posix) and not (defined(macosx) or defined(bsd)):
    import std/posix

  when defined(windows):
    import std/private/win_getsysteminfo

  when defined(freebsd) or defined(macosx):
    {.emit: "#include <sys/types.h>".}

  when defined(openbsd) or defined(netbsd):
    {.emit: "#include <sys/param.h>".}

  when defined(macosx) or defined(bsd):
    # we HAVE to emit param.h before sysctl.h so we cannot use .header here
    # either. The amount of archaic bullshit in Poonix based OSes is just insane.
    {.emit: "#include <sys/sysctl.h>".}
    {.push nodecl.}
    when defined(macosx):
      proc sysctlbyname(name: cstring,
        oldp: pointer, oldlenp: var csize_t,
        newp: pointer, newlen: csize_t): cint {.importc.}
    let
      CTL_HW{.importc.}: cint
      HW_NCPU{.importc.}: cint
    proc sysctl[I: static[int]](name: var array[I, cint], namelen: cuint,
      oldp: pointer, oldlenp: var csize_t,
      newp: pointer, newlen: csize_t): cint {.importc.}
    {.pop.}

  when defined(genode):
    import genode/env

    proc affinitySpaceTotal(env: GenodeEnvPtr): cuint {.
      importcpp: "@->cpu().affinity_space().total()".}

  when defined(haiku):
    type
      SystemInfo {.importc: "system_info", header: "<OS.h>".} = object
        cpuCount {.importc: "cpu_count".}: uint32

    proc getSystemInfo(info: ptr SystemInfo): int32 {.importc: "get_system_info",
                                                      header: "<OS.h>".}

  proc countProcessorsImpl(): int {.inline.} =
    when defined(windows):
      var
        si: SystemInfo
      getSystemInfo(addr si)
      result = int(si.dwNumberOfProcessors)
    elif defined(macosx) or defined(bsd):
      let dest = addr result
      var len = sizeof(result).csize_t
      when defined(macosx):
        # alias of "hw.activecpu"
        if sysctlbyname("hw.logicalcpu", dest, len, nil, 0) == 0:
          return
      var mib = [CTL_HW, HW_NCPU]
      if sysctl(mib, 2, dest, len, nil, 0) == 0:
        return
    elif defined(hpux):
      result = mpctl(MPC_GETNUMSPUS, nil, nil)
    elif defined(irix):
      var SC_NPROC_ONLN {.importc: "_SC_NPROC_ONLN", header: "<unistd.h>".}: cint
      result = sysconf(SC_NPROC_ONLN)
    elif defined(genode):
      result = runtimeEnv.affinitySpaceTotal().int
    elif defined(haiku):
      var sysinfo: SystemInfo
      if getSystemInfo(addr sysinfo) == 0:
        result = sysinfo.cpuCount.int
    else:
      result = sysconf(SC_NPROCESSORS_ONLN)
    if result < 0: result = 0



proc countProcessors*(): int {.rtl, extern: "ncpi$1".} =
  ## Returns the number of the processors/cores the machine has.
  ## Returns 0 if it cannot be detected.
  countProcessorsImpl()

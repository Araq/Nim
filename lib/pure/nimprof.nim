#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Profiling support for Nim. This is an embedded profiler that requires
## `--profiler:on`. You only need to import this module to get a profiling
## report at program exit. See `Embedded Stack Trace Profiler <estp.html>`_
## for usage.

when not defined(profiler) and not defined(memProfiler):
  {.error: "Profiling support is turned off! Enable profiling by passing `--profiler:on --stackTrace:on` to the compiler (see the Nim Compiler User Guide for more options).".}

{.used.}

# We don't want to profile the profiling code ...
{.push profiler: off.}

import std/[hashes, algorithm, strutils, tables, sets]

when defined(nimPreviewSlimSystem):
  import std/[syncio, sysatomics]

when not defined(memProfiler):
  include "system/timers"

const
  withThreads = compileOption("threads")
  tickCountCorrection = 50_000

when not declared(system.StackTrace):
  type StackTrace = object
    lines: array[0..20, cstring]
    files: array[0..20, cstring]
  proc `[]`*(st: StackTrace, i: int): cstring = st.lines[i]

# We use a simple hash table of bounded size to keep track of the stack traces:
type
  ProfileEntry = object
    total: int
    st: StackTrace
  ProfileData = array[0..64*1024-1, ptr ProfileEntry]

proc `==`(a, b: StackTrace): bool =
  for i in 0 .. high(a.lines):
    if a[i] != b[i]: return false
  result = true

# XXX extract this data structure; it is generally useful ;-)
# However a chain length of over 3000 is suspicious...
var
  profileData: ProfileData
  emptySlots = profileData.len div 2 + profileData.len
  maxChainLen = 0
  totalCalls = 0

when not defined(memProfiler):
  var interval: Nanos = 5_000_000 - tickCountCorrection # 5ms

  proc setSamplingFrequency*(intervalInUs: int) =
    ## set this to change the sampling frequency. Default value is 5ms.
    ## Set it to 0 to disable time based profiling; it uses an imprecise
    ## instruction count measure instead then.
    if intervalInUs <= 0: interval = 0
    else: interval = intervalInUs * 1000 - tickCountCorrection

when withThreads:
  import std/locks
  var
    profilingLock: Lock

  initLock profilingLock

proc hookAux(st: StackTrace, costs: int) =
  # this is quite performance sensitive!
  when withThreads: acquire profilingLock
  inc totalCalls
  var last = high(st.lines)
  while last > 0 and isNil(st[last]): dec last
  var h = hash(pointer(st[last])) and high(profileData)

  # we use probing for maxChainLen entries and replace the encountered entry
  # with the minimal 'total' value:
  if emptySlots == 0:
    var minIdx = h
    var probes = maxChainLen
    while probes >= 0:
      if profileData[h].st == st:
        # wow, same entry found:
        inc profileData[h].total, costs
        return
      if profileData[minIdx].total < profileData[h].total:
        minIdx = h
      h = ((5 * h) + 1) and high(profileData)
      dec probes
    profileData[minIdx].total = costs
    profileData[minIdx].st = st
  else:
    var chain = 0
    while true:
      if profileData[h] == nil:
        profileData[h] = cast[ptr ProfileEntry](
                             allocShared0(sizeof(ProfileEntry)))
        profileData[h].total = costs
        profileData[h].st = st
        dec emptySlots
        break
      if profileData[h].st == st:
        # wow, same entry found:
        inc profileData[h].total, costs
        break
      h = ((5 * h) + 1) and high(profileData)
      inc chain
    maxChainLen = max(maxChainLen, chain)
  when withThreads: release profilingLock

when defined(memProfiler):
  const
    SamplingInterval = 50_000
  var
    gTicker {.threadvar.}: int

  proc requestedHook(): bool {.nimcall.} =
    if gTicker == 0:
      gTicker = SamplingInterval
      result = true
    dec gTicker

  proc hook(st: StackTrace, size: int) {.nimcall.} =
    when defined(ignoreAllocationSize):
      hookAux(st, 1)
    else:
      hookAux(st, size)

else:
  var
    t0 {.threadvar.}: Ticks
    gTicker: int # we use an additional counter to
                 # avoid calling 'getTicks' too frequently

  proc requestedHook(): bool {.nimcall.} =
    result = false
    if interval == 0: result = true
    elif gTicker == 0:
      gTicker = 500
      if getTicks() - t0 > interval:
        result = true
    else:
      dec gTicker

  proc hook(st: StackTrace) {.nimcall.} =
    #echo "profiling! ", interval
    if interval == 0:
      hookAux(st, 1)
    else:
      hookAux(st, 1)
      t0 = getTicks()

proc getTotal(x: ptr ProfileEntry): int =
  result = if isNil(x): 0 else: x.total

proc cmpEntries(a, b: ptr ProfileEntry): int =
  result = b.getTotal - a.getTotal

proc `//`(a, b: int): string =
  result = format("$1/$2 = $3%", a, b, formatFloat(a / b * 100.0, ffDecimal, 2))

proc writeProfile() {.noconv.} =
  system.profilingRequestedHook = nil
  when declared(system.StackTrace):
    system.profilerHook = nil
  const filename = "profile_results.txt"
  echo "writing " & filename & "..."
  var f: File = default(File)
  if open(f, filename, fmWrite):
    sort(profileData, cmpEntries)
    writeLine(f, "total executions of each stack trace:")
    var entries = 0
    for i in 0..high(profileData):
      if profileData[i] != nil: inc entries

    var perProc = initCountTable[string]()
    for i in 0..entries-1:
      var dups = initHashSet[string]()
      for ii in 0..high(StackTrace.lines):
        let procname = profileData[i].st[ii]
        if isNil(procname): break
        let p = $procname
        if not containsOrIncl(dups, p):
          perProc.inc(p, profileData[i].total)

    var sum = 0
    # only write the first 100 entries:
    for i in 0..min(100, entries-1):
      if profileData[i].total > 1:
        inc sum, profileData[i].total
        writeLine(f, "Entry: ", i+1, "/", entries, " Calls: ",
          profileData[i].total // totalCalls, " [sum: ", sum, "; ",
          sum // totalCalls, "]")
        for ii in 0..high(StackTrace.lines):
          let procname = profileData[i].st[ii]
          let filename = profileData[i].st.files[ii]
          if isNil(procname): break
          writeLine(f, "  ", $filename & ": " & $procname, " ",
                    perProc[$procname] // totalCalls)
    close(f)
    echo "... done"
  else:
    echo "... failed"

var
  disabled: int

proc disableProfiling*() =
  when declared(system.StackTrace):
    atomicDec disabled
    system.profilingRequestedHook = nil

proc enableProfiling*() =
  when declared(system.StackTrace):
    if atomicInc(disabled) >= 0:
      system.profilingRequestedHook = requestedHook

when declared(system.StackTrace):
  import std/exitprocs
  system.profilingRequestedHook = requestedHook
  system.profilerHook = hook
  addExitProc(writeProfile)

{.pop.}

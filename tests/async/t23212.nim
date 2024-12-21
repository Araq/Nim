discard """
  valgrind: true
  cmd: '''nim c --mm:arc -d:nimAllocStats -d:useMalloc $file'''
  output: '''1000'''
"""

import std/asyncdispatch

var count: int

proc stuff() {.async.} =
  #echo count, 1
  await sleepAsync(1)
  #echo count, 2
  count.inc

for _ in 0..<1000:
  asyncCheck stuff()

while hasPendingOperations(): poll()

echo count

setGlobalDispatcher(nil)

import std/importutils
privateAccess(AllocStats)
doAssert getAllocStats().allocCount - getAllocStats().deallocCount < 10

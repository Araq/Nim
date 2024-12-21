discard """
  cmd: '''nim c --mm:arc -d:nimAllocStats $file'''
  output: '''1000
(allocCount: 9010, deallocCount: 9004)'''
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
echo getAllocStats()

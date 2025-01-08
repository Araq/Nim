discard """
  outputsub: "(allocCount: 4011, deallocCount: 4009)"
  cmd: "nim c --gc:orc -d:nimAllocStats $file"
"""

import asyncdispatch
# bug #15076
const
  # Just to occupy some RAM
  BigData = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

proc doNothing(): Future[void] {.async.} =
  discard

proc main(): Future[void] {.async.} =
  for x in 0 .. 1_000:
    await doNothing()

waitFor main()
GC_fullCollect()
echo getAllocStats()

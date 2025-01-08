discard """
  joinable: false
  retries: 2
"""

import std/asyncdispatch

# bug #22256
GC_disableMarkAndSweep()
waitFor sleepAsync(1000)

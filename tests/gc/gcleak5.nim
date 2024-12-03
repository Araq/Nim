discard """
  output: "success"
  retries: 2
"""

import os, times

proc main =
  var i = 0
  for ii in 0..50_000:
    #while true:
    var t = getTime()
    var g = t.utc()
    #echo isOnStack(addr g)

    if i mod 100 == 0:
      let om = getOccupiedMem()
      #echo "memory: ", om
      if om > 100_000: quit "leak"

    inc(i)
    sleep(1)

  echo "success"

main()

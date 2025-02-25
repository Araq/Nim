discard """
    output: '''Success'''
    retries: 2
"""

# bug #3793

import os
import math
import lists
import strutils

proc mkleak() =
    # allocate 1 MB via linked lists
    let numberOfLists = 100
    for i in countUp(1, numberOfLists):
        var leakList = initDoublyLinkedList[string]()
        let numberOfLeaks = 5000
        for j in countUp(1, numberOfLeaks):
            leakList.append(newString(200))

proc mkManyLeaks() =
    for i in 0..0:
        when false: echo getOccupiedMem()
        mkleak()
        when false: echo getOccupiedMem()
        # Force a full collection. This should free all of the
        # lists and bring the memory usage down to a few MB's.
        GC_fullCollect()
        when false: echo getOccupiedMem()
        if getOccupiedMem() > 8 * 200 * 5000 * 2:
          echo GC_getStatistics()
          quit "leaking"
    echo "Success"

mkManyLeaks()

discard """
  cmd: "nim c --hints:off -d:testsConciseTypeMismatch $file"
  errormsg: "type mismatch"
  nimout: '''
tconcisetypemismatch.nim(23, 47) Error: type mismatch
Expression: int(inNanoseconds(t2 - t1)) / 100.5
  [1] int(inNanoseconds(t2 - t1)): int
  [2] 100.5: float64

Expected one of (first mismatch at [position]):
[1] proc `/`(x, y: float): float
[1] proc `/`(x, y: float32): float32
[2] proc `/`(x, y: int): float
'''
"""

import std/monotimes
from times import inNanoseconds

let t1 = getMonotime()
let result = 1 + 2
let t2 = getMonotime()
echo "Elapsed: ", (t2 - t1).inNanoseconds.int / 100.5

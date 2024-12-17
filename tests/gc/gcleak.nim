discard """
  outputsub: "no leak: "
  retries: 2
"""

when defined(GC_setMaxPause):
  GC_setMaxPause 2_000

type
  TTestObj = object of RootObj
    x: string

proc makeObj(): TTestObj =
  result.x = "Hello"

const numIter =
  # see tests/gc/gcleak2.nim
  when defined(boehmgc):
    1_000
  elif defined(gcMarkAndSweep): 10_000
  else: 100_000

for i in 1 .. numIter:
  when defined(gcMarkAndSweep) or defined(boehmgc):
    GC_fullcollect()
  var obj = makeObj()
  if getOccupiedMem() > 300_000: quit("still a leak!")
#  echo GC_getstatistics()

echo "no leak: ", getOccupiedMem()

discard """
  outputsub: "no leak: "
  retries: 2
"""

when defined(GC_setMaxPause):
  GC_setMaxPause 2_000

type
  TTestObj = object of RootObj
    x: string
    s: seq[int]

proc makeObj(): TTestObj =
  result.x = "Hello"
  result.s = @[1,2,3]

const numIter =
  when defined(boehmgc):
    # super slow because GC_fullcollect() at each iteration; especially
    # on OSX 10.15 where it takes ~170s
    # `getOccupiedMem` should be constant after each iteration for i >= 3
    1_000
  elif defined(gcMarkAndSweep):
    # likewise, somewhat slow, 1_000_000 would run for 8s
    # and same remark as above
    100_000
  else: 1_000_000

proc inProc() =
  for i in 1 .. numIter:
    when defined(gcMarkAndSweep) or defined(boehmgc):
      GC_fullcollect()
    var obj: TTestObj
    obj = makeObj()
    if getOccupiedMem() > 300_000: quit("still a leak!")

inProc()
echo "no leak: ", getOccupiedMem()

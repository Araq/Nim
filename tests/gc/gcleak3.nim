discard """
  outputsub: "no leak: "
  retries: 2
"""

when defined(GC_setMaxPause):
  GC_setMaxPause 2_000

type
  TSomething = object
    s: string
    s1: string
var s: seq[TSomething] = @[]
for i in 0..1024:
  var obj: TSomething
  obj.s = "blah"
  obj.s1 = "asd"
  s.add(obj)

proc limit*[t](a: var seq[t]) =
  while s.len > 0:
    if getOccupiedMem() > 3000_000: quit("still a leak!")
    s.delete(0)

s.limit()
echo "no leak: ", getOccupiedMem()


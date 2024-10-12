discard """
  outputsub: "no leak: "
  retries: 2
"""

type
  Cyclic = object
    sibling: PCyclic
    data: array[0..200, char]

  PCyclic = ref Cyclic

proc makePair: PCyclic =
  new(result)
  new(result.sibling)
  when not defined(gcDestructors):
    result.sibling.sibling = result

proc loop =
  for i in 0..10000:
    var x = makePair()
    GC_fullCollect()
    x = nil
    GC_fullCollect()

  if getOccupiedMem() > 300_000:
    echo "still a leak! ", getOccupiedMem()
    quit(1)
  else:
    echo "no leak: ", getOccupiedMem()

loop()


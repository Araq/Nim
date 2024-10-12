discard """
  outputsub: "no leak: "
  retries: 2
"""

type
  TNode = object
    data: array[0..300, char]

  PNode = ref TNode

  TNodeArray = array[0..10, PNode]

  TArrayHolder = object
    sons: TNodeArray

proc nullify(a: var TNodeArray) =
  for i in 0..high(a):
    a[i] = nil

proc newArrayHolder: ref TArrayHolder =
  new result

  for i in 0..high(result.sons):
    new result.sons[i]

  nullify result.sons

proc loop =
  for i in 0..10000:
    discard newArrayHolder()

  if getOccupiedMem() > 300_000:
    echo "still a leak! ", getOccupiedMem()
    quit 1
  else:
    echo "no leak: ", getOccupiedMem()

loop()


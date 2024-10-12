discard """
  outputsub: "no leak: "
  retries: 2
"""

type
  Module = object
    nodes*: seq[PNode]
    id: int

  PModule = ref Module

  Node = object
    owner* {.cursor.}: PModule
    data*: array[0..200, char] # some fat to drain memory faster
    id: int

  PNode = ref Node

var
  gid: int

when false:
  proc finalizeNode(x: PNode) =
    echo "node id: ", x.id
  proc finalizeModule(x: PModule) =
    echo "module id: ", x.id

proc newNode(owner: PModule): PNode =
  new(result)
  result.owner = owner
  inc gid
  result.id = gid

proc compileModule: PModule =
  new(result)
  result.nodes = @[]
  for i in 0..100:
    result.nodes.add newNode(result)
  inc gid
  result.id = gid

var gModuleCache: PModule

proc loop =
  for i in 0..1000:
    gModuleCache = compileModule()
    gModuleCache = nil
    GC_fullCollect()

    if getOccupiedMem() > 9_000_000:
      echo "still a leak! ", getOccupiedMem()
      quit(1)
  echo "no leak: ", getOccupiedMem()

loop()


# issue #16128

import std/[tables, hashes]

type
  NodeId*[L] = object
    isSource: bool
    index: Table[NodeId[L], seq[NodeId[L]]]

func hash*[L](id: NodeId[L]): Hash = discard
func `==`[L](a, b: NodeId[L]): bool = discard

proc makeIndex*[T, L](tree: T) =
  var parent = NodeId[L]()
  var tmp: Table[NodeId[L], seq[NodeId[L]]]
  tmp[parent] = @[parent]

proc simpleTreeDiff*[T, L](source, target: T) =
  # Swapping these two lines makes error disappear
  var m: Table[NodeId[L], NodeId[L]]
  makeIndex[T, L](target)

var tmp: Table[string, seq[string]] # removing this forward declaration also removes error

proc diff(x1, x2: string): auto =
  simpleTreeDiff[int, string](12, 12)

# issue #23596

import std/heapqueue
type Algo = enum heapqueue, quick
when false:
  let x = heapqueue
let y: Algo = heapqueue
proc bar*(algo=quick) =
  var x: HeapQueue[int]
  case algo
  of heapqueue: echo 1 # `Algo.heapqueue` works on devel
  of quick: echo 2
  echo x.len

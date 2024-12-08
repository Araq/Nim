# issue #22820

{.push raises: [].}

import
  "."/[msugarcrash1]

import
  std/[options, sugar]

var closestNodes: seq[Node]
for cn in closestNodes:
  discard cn.address.map(a => a.port)

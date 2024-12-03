discard """
  errormsg: "type mismatch: got <openArray[int], proc (x: GenericParam, y: GenericParam): auto, SortOrder>"
  line: 12
"""

import sugar
from algorithm import sorted, SortOrder

let a = 5

proc sorted*[T](a: openArray[T], key: proc(v: T): int, order = SortOrder.Ascending): seq[T] =
  sorted(a, (x, y) => key(x) < key(y), order)

echo sorted(@[9, 1, 8, 2, 6, 4, 5, 0], (x) => (a - x).abs)

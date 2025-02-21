# issue #24698

type Point = tuple[x, y: int]

const Origin: Point = (0, 0)

import macros

template next(point: Point): Point =
  (point.x + 1, point.y + 1)

discard Origin.x      # OK: the field is visible.
discard next(Origin)  # Compilation error: the field is not visible.

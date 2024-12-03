discard """
  matrix: "--mm:arc --multimethods:on -d:nimInternalNonVtablesTesting; --mm:refc --multimethods:on -d:nimInternalNonVtablesTesting"
  output: '''wow2
X 1
X 3'''
"""
type
  First[T] = ref object of RootObj
    value: T

  Second[T] = ref object of First[T]
    value2: T

method wow[T](y: int; x: First[T]) {.base.} =
  echo "wow1"

method wow[T](y: int; x: Second[T]) =
  echo "wow2"

var
  x: Second[int]
new(x)

proc takeFirst(x: First[int]) =
  wow(2, x)

takeFirst(x)


# bug #5479
type
  Base[T: static[int]] = ref object of RootObj

method test[T](t: Base[T]) {.base.} =
  echo "X ", t.T

let ab = Base[1]()

ab.test()

let ac = Base[3]()
ac.test()

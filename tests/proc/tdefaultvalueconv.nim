# issue #22126

func foo[T](arr: openArray[T], idx: Natural = arr.high): int = # missed conversion: `Natural(arr.high)`
  if idx == 0:
    return 0
  foo(arr, idx - 1)

let arr = [0, 1, 2]

doAssert foo(arr) == 0

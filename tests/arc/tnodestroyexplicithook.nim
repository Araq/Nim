discard """
  ccodecheck: "'Result[(i - 0)] = eqdup'"
"""

# issue #24626

proc arrayWith2[T](y: T, size: static int): array[size, T] {.noinit, nodestroy, raises: [].} =
  ## Creates a new array filled with `y`.
  for i in 0..size-1:
    when defined(nimHasDup):
      result[i] = `=dup`(y)
    else:
      wasMoved(result[i])
      `=copy`(result[i], y)

proc useArray(x: seq[int]) =
  var a = arrayWith2(x, 2)

proc main =
  let x = newSeq[int](100)
  for i in 0..5:
    useArray(x)

main()

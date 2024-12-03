discard """
  cmd: "nim check $options $file"
  errormsg: "tuple expected for tuple unpacking, but got 'array[0..2, int]'"
"""

iterator xclusters*[T](a: openArray[T]; s: static[int]): array[s, T] {.inline.} =
  var result: array[s, T] # iterators have no default result variable
  var i = 0
  while i < len(a):
    for j, x in mpairs(result):
      x = a[(i + j) mod len(a)]
    yield result
    inc(i)

proc m =
  for (i, j, k) in xclusters([1, 2, 3, 4, 5], 3):
    echo i, j, k

m()

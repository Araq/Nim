discard """
  output: "123"
  targets: "c cpp"
"""
# Try to break the transformation pass:
iterator iterAndZero(a: var openArray[int]): int =
  for i in 0..len(a)-1:
    yield a[i]
    a[i] = 0

var x = [[1, 2, 3], [4, 5, 6]]
for y in iterAndZero(x[0]): write(stdout, $y)
#OUT 123

write stdout, "\n"

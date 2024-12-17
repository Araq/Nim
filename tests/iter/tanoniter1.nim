discard """
  targets: "c js"
  output: '''1
2
3
4
1
2'''
"""

proc factory(a, b: int): iterator (): int =
  iterator foo(): int {.closure.} =
    var x = a
    while x <= b:
      yield x
      inc x
  return foo

proc factory2(a, b: int): iterator (): int =
  return iterator (): int =
    var x = a
    while x <= b:
      yield x
      inc x

let foo = factory(1, 4)

for f in foo():
  echo f

let foo2 = factory2(1,2)

for f in foo2(): echo f

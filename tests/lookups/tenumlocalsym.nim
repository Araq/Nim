block:
  type Enum = enum a, b

  block:
    let a = b
    let x: Enum = a
    doAssert x == b
  
block:
  type
    Enum = enum
      a = 2
      b = 10

  iterator items2(): Enum =
    for a in [a, b]:
      yield a

  var s = newSeq[Enum]()
  for i in items2():
    s.add i
  doAssert s == @[a, b]

discard """
  matrix: ";--d:danger"
"""

block:
  proc foo() =
    var name = int64(12)
    var x = uint32(name)
    var m = x + 12

    var y = int32(name)
    var n = y + 1

    doAssert m == uint32(n + 11)


  foo()

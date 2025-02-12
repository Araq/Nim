discard """
  matrix: "--mm:refc; --mm:orc"
  targets: "c cpp js"
"""

import std/assertions

# bug #20227
type
  Data = object
    id: int

  Test = distinct Data

  Object = object
    data: Test


var x: Object = Object(data: Test(Data(id: 12)))
doAssert Data(x.data).id == 12

block: # bug #16771
  type A = object
    n: int

  proc foo(a, b: var A) =
    swap a, b

  var a, b: A
  a.n = 42
  b.n = 1
  doAssert a.n == 42
  doAssert b.n == 1
  a.swap b
  doAssert a.n == 1
  doAssert b.n == 42
  a.foo b
  doAssert a.n == 42
  doAssert b.n == 1

block: # bug #24683
  block:
    var v = newSeq[int](100)
    v[99]= 444
    v.setLen(5)
    v.setLen(100)
    doAssert v[99] == 0

  when not defined(js):
    block:
      var 
        x = @[1, 2, 3, 4, 45, 56, 67, 999, 88, 777]

      x.setLen(0) # zero-fills 1mb of released data

      type
        TGenericSeq = object
          len, reserved: int
        PGenericSeq = ptr TGenericSeq

      when defined(gcRefc):
        cast[PGenericSeq](x).len = 10
      else:
        cast[ptr int](addr x)[] = 10

      doAssert x == @[1, 2, 3, 4, 45, 56, 67, 999, 88, 777]

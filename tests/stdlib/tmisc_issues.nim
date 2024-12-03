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

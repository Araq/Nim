discard """
  targets: "c cpp"
"""

block:
  var called = 0

  proc bar(a: var int): var int =
    inc called
    result = a

  proc foo =
    var a = 2
    var s = move bar(a)
    doAssert called == 1
    doAssert s == 2

  foo()

import std/deques

block: # bug #24319
  var queue = initDeque[array[32, byte]]()
  for i in 0 ..< 5:
    let element: array[32, byte] = [
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 1,
          ]
    queue.addLast(element)

  doAssert queue.popLast[^1] == byte(1)

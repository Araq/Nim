discard """
  matrix: "-d:nimPreviewSlimSystem"
  targets: "c cpp js"
"""

import std/[assertions, objectequals]

type Foo = object
  a: int
  case b: bool
  of false:
    c: string
  else:
    d: float

doAssert Foo(a: 1, b: false, c: "abc") == Foo(a: 1, b: false, c: "abc")
doAssert Foo(a: 1, b: false, c: "abc") != Foo(a: 2, b: false, c: "abc")
doAssert Foo(a: 1, b: false, c: "abc") != Foo(a: 1, b: true, d: 3.14)
doAssert Foo(a: 1, b: false, c: "abc") != Foo(a: 1, b: false, c: "def")

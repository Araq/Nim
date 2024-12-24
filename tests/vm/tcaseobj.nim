# issue #17571

import std/[macros, objectdollar]

type
  MyEnum = enum
    F, S, T
  Foo = object
    case o: MyEnum
    of F:
      f: string
    of S:
      s: string
    of T:
      t: string

let val = static(Foo(o: F, f: "foo")).f
doAssert val == "foo"
doAssert $static(Foo(o: F, f: "foo")) == $Foo(o: F, f: "foo")

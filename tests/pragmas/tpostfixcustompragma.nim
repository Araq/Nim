# issue #24526

import std/macros

template prag {.pragma.}

type
  Foo1* = ref object of RootObj
    name*: string
  Foo2* {.used.} = ref object of RootObj
    name*: string
  Foo3* {.prag.} = ref object of RootObj
    name*: string
  Foo4* {.used, prag.} = ref object of RootObj
    name*: string

# needs to have `typedesc` type
proc foo(T: typedesc): bool =
  T.hasCustomPragma(prag)

doAssert not foo(typeof(Foo1()[]))
doAssert not foo(typeof(Foo2()[]))
doAssert foo(typeof(Foo3()[]))
doAssert foo(typeof(Foo4()[]))

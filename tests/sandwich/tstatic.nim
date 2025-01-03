from mstatic import Foo

doAssert $Foo(x: 1, y: 2) == "static Foo(1, 2)"
let foo = Foo(x: 3, y: 4)
doAssert $foo == "runtime Foo(3, 4)"

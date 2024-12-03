import macros

var destroyCalled = false
macro bar() =
  let s = newTree(nnkAccQuoted, ident"=destroy")
  # let s = ident"`=destroy`" # this would not work
  result = quote do:
    type Foo = object
    # proc `=destroy`(a: var Foo) = destroyCalled = true # this would not work
    proc `s`(a: var Foo) = destroyCalled = true
    block:
      let a = Foo()
bar()
doAssert destroyCalled

# custom `op`
var destroyCalled2 = false
macro bar(ident) =
  var x = 1.5
  result = quote("@") do:
    type Foo = object
    let `@ident` = 0 # custom op interpolated symbols need quoted (``)
    proc `=destroy`(a: var Foo) =
      doAssert @x == 1.5
      doAssert compiles(@x == 1.5)
      let b1 = @[1,2]
      let b2 = @@[1,2]
      doAssert $b1 == "[1, 2]"
      doAssert $b2 == "@[1, 2]"
      destroyCalled2 = true
    block:
      let a = Foo()
bar(someident)
doAssert destroyCalled2

proc `&%`(x: int): int = 1
proc `&%`(x, y: int): int = 2

macro bar2() =
  var x = 3
  result = quote("&%") do:
    var y = &%x # quoting operator
    doAssert &%&%y == 1 # unary operator => need to escape
    doAssert y &% y == 2 # binary operator => no need to escape
    doAssert y == 3
bar2()

block:
  macro foo(a: openArray[string] = []): string =
    echo a # Segfault doesn't happen if this is removed
    newLit ""

  proc bar(a: static[openArray[string]] = []) =
    const tmp = foo(a)

  # bug #22909
  doAssert not compiles(bar())

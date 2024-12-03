import std/[volatile, assertions]

var st: int
var foo: ptr int = addr st
volatileStore(foo, 12)
doAssert volatileLoad(foo) == 12

# bug #14623
proc bar =
  var st: int
  var foo: ptr int = addr st
  volatileStore(foo, 12)
  doAssert volatileLoad(foo) == 12

bar()

import issue_23172/m23172

type FooX = distinct Foo

func `$`*(x: FooX): string =
  $m23172.Foo(x)

var a: FooX
doAssert $a == "X"

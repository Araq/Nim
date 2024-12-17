# issue #23977

type Foo[T] = int

proc foo(T: typedesc) =
  var a: T

foo(int)

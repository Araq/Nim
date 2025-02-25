proc doSomething*(x, y: int): int =
  ## do something
  x + y

const
  a* = 1 ## echo 1234
  b* = "test"

type
  MyEnum* = enum
    foo, bar

proc foo2*[T: int, M: string, U](x: T, y: U, z: M) =
  echo 1

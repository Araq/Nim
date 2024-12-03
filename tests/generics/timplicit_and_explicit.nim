
block: # basic test
  proc doStuff[T](a: SomeInteger): T = discard
  proc doStuff[T;Y](a: SomeInteger, b: Y): Y = discard
  assert typeof(doStuff[int](100)) is int
  assert typeof(doStuff[int, float](100, 1.0)) is float
  assert typeof(doStuff[int, string](100, "Hello")) is string

  proc t[T](x: T; z: int | float): seq[T] = result.add(x & $z)

  assert t[string]("Hallo", 2.0) == @["Hallo" & $2.0]

  proc t2[T](z: int | float): seq[T] = result.add($z)

  assert t2[string](2.0) == @[$2.0]

block: # template test
  template someThing[T;Y](a: SomeFloat, b: SomeOrdinal): (T, Y) = (a, b)
  assert typeof(someThing[float64, int](1.0, 100)) is (float64, int)

block: # static test
  proc t[T](s: static bool) = discard
  proc t2[T](s: static string) = discard
  t[string](true)
  t2[int]("hello")
  t2[string]("world")
  t2[float]("test222222")

block: #11152
  proc f[T](X: typedesc) = discard
  f[int](string)

block: #15622
  proc test1[T](a: T, b: static[string] = "") = discard
  test1[int64](123)
  proc test2[T](a: T, b: static[string] = "") = discard
  doAssert not (compiles do:
    test2[int64, static[string]](123))

block: #4688
  proc convertTo[T](v: int or float): T = (T)(v)
  discard convertTo[float](1)

block: #4164
  proc printStr[T](s: static[string]): T = discard
  discard printStr[int]("hello static")

import macros

block: # issue #9040, statics with template, macro, symchoice explicit generics
  block: # macro
    macro fun[N: static int](): untyped =
      newLit 1
    const a = fun[2]()
    doAssert a == 1
  block: # template
    template fun[N: static int](): untyped =
      1
    const a = fun[2]()
    doAssert a == 1
  block: # symchoice
    proc newSeq[x: static int](): int = 1
    template foo: int =
      newSeq[2]()
    doAssert foo() == 1

block:
  template foo(a: untyped, b: untyped = a(0)): untyped =
    let x = a(0)
    let y = b
    (x, y)
  proc bar(x: int): int = x + 1
  doAssert foo(bar, b = bar(0)) == (1, 1)
  doAssert foo(bar) == (1, 1)

block: # issue #23506
  var a: string
  template foo(x: int; y = x) =
    a = $($x, $y)
  foo(1)
  doAssert a == "(\"1\", \"1\")"

block: # untyped params with default value
  macro foo(x: typed): untyped =
    result = x
  template test(body: untyped, alt: untyped = (;), maxTries = 3): untyped {.foo.} =
    body
    alt
  var s = "a"
  test:
    s.add "b"
  do:
    s.add "c"
  doAssert s == "abc"
  template test2(body: untyped, alt: untyped = s.add("e"), maxTries = 3): untyped =
    body
    alt
  test2:
    s.add "d"
  doAssert s == "abcde"
  template test3(body: untyped = willNotCompile) =
    discard
  test3()

block: # typed params with `void` default value
  macro foo(x: typed): untyped =
    result = x
  template test(body: untyped, alt: typed = (;), maxTries = 3): untyped {.foo.} =
    body
    alt
  var s = "a"
  test:
    s.add "b"
  do:
    s.add "c"
  doAssert s == "abc"
  template test2(body: untyped, alt: typed = s.add("e"), maxTries = 3): untyped =
    body
    alt
  test2:
    s.add "d"
  doAssert s == "abcde"

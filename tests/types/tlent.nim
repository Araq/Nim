discard """
  targets: "c cpp js"
"""

#[
xxx move at least some of those tests to here:
tests/lent/tbasic_lent_check.nim
tests/lent/tlent_from_var.nim
tests/lent/tnot_allowed_lent.nim
tests/lent/tnot_allowed_lent2.nim
tests/types/tlent.nim
tests/types/tlent_var.nim
]#

type Foo = object
  f0: int
  f1: int

proc fn1(a: auto): lent int = a[0]
proc fn2(a: Foo): lent int = a.f0

iterator it3(a: Foo): lent int =
  yield a.f0

template sameAddr(a, b): bool = 
  when defined(js):
    # we could probably do something smarter here
    a == b
  else:
    let pa = cast[int](a.unsafeAddr)
    let pb = cast[int](b.unsafeAddr)
    pa == pb

template main() = 
  block:
    let a = @[10,11,12]
    doAssert sameAddr(a[0], fn1(a))
  block:
    let a = [10,11,12]
    doAssert sameAddr(a[0], fn1(a))
  block:
    let a = Foo(f0: 10)
    doAssert sameAddr(a.f0, fn2(a))

  block:
    let a = @[10,11,12]
    for ai in items(a):
      doAssert sameAddr(a[0], ai)
      break
  block:
    let a = [10,11,12]
    for ai in items(a):
      doAssert sameAddr(a[0], ai)
      break
  block:
    let a = [[1,2],[1,2],[1,2]]
    for ai in items(a):
      doAssert sameAddr(a[0][0], ai[0])
      break
  block:
    let a = Foo(f0: 10)
    for ai in it3(a):
      doAssert sameAddr(a.f0, ai)
      break

static: main()
main()

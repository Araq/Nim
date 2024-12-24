block: # issue #13302
  proc foo(x: object): int = x.i*2
  proc foo(x: var object) = x.i*=2
  type Foo = object
    i: int
  let x = Foo(i: 3)
  var y = Foo(i: 4)
  doAssert foo(x) == 6
  foo(y)
  doAssert y.i == 8

block: # issue #24449
  proc p(x: var seq)= discard
  proc p(x: seq)= discard
  var s : seq[int]
  p(s)

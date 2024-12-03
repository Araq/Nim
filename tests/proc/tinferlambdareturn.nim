import std/[sugar, sequtils]

block: # issue #23200
  proc dosomething(iter: int -> (iterator: int)) =
    discard
  proc dosomething(iter: int -> seq[int]) =
    discard
  proc makeSeq(x: int): seq[int] =
    @[x]
  # Works fine with 1.6.12 and 1.6.14
  dosomething(makeSeq)
  # Works with 1.6.12, fails with 1.6.14
  dosomething((y) => makeSeq(y))
  dosomething(proc (y: auto): auto = makeSeq(y))
  proc foo(y: auto): auto = makeSeq(y)
  dosomething(foo)

block: # issue #18866
  proc somefn[T](list: openarray[T], op: proc (v: T): float) =
    discard op(list[0])

  type TimeD = object
    year:  Natural
    month: 1..12
    day:   1..31

  doAssert not compiles(@[TimeD()].somefn(proc (v: auto): auto =
    v
  ))
  @[TimeD()].somefn(proc (v: auto): auto =
    v.year.float
  )
  proc foo(v: auto): auto = v
  doAssert not compiles(@[TimeD()].somefn(foo))
  proc bar(v: auto): auto = v.year.float
  @[TimeD()].somefn(bar)

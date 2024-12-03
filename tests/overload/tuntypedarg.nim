import macros

block: # issue #7385
  type CustomSeq[T] = object
    data: seq[T]
  macro `[]`[T](s: CustomSeq[T], args: varargs[untyped]): untyped =
    ## The end goal is to replace the joker "_" by something else
    result = newIntLitNode(10)
  proc foo1(): CustomSeq[int] =
    result.data.newSeq(10)
    # works since no overload matches first argument with type `CustomSeq`
    # except magic `[]`, which always matches without checking arguments
    doAssert result[_] == 10
  doAssert foo1() == CustomSeq[int](data: newSeq[int](10))
  proc foo2[T](): CustomSeq[T] =
    result.data.newSeq(10)
    # works fine with generic return type
    doAssert result[_] == 10
  doAssert foo2[int]() == CustomSeq[int](data: newSeq[int](10))

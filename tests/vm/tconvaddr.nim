block: # issue #24097
  type Foo = distinct int
  proc foo(x: var Foo) =
    int(x) += 1
  proc bar(x: var int) =
    x += 1
  static:
    var x = Foo(1)
    int(x) = int(x) + 1
    doAssert x.int == 2
    int(x) += 1
    doAssert x.int == 3
    foo(x)
    doAssert x.int == 4
    bar(int(x)) # need vmgen flags propagated for this
    doAssert x.int == 5
  type Bar = object
    x: Foo
  static:
    var obj = Bar(x: Foo(1))
    int(obj.x) = int(obj.x) + 1
    doAssert obj.x.int == 2
    int(obj.x) += 1
    doAssert obj.x.int == 3
    foo(obj.x)
    doAssert obj.x.int == 4
    bar(int(obj.x)) # need vmgen flags propagated for this
    doAssert obj.x.int == 5
  static:
    var arr = @[Foo(1)]
    int(arr[0]) = int(arr[0]) + 1
    doAssert arr[0].int == 2
    int(arr[0]) += 1
    doAssert arr[0].int == 3
    foo(arr[0])
    doAssert arr[0].int == 4
    bar(int(arr[0])) # need vmgen flags propagated for this
    doAssert arr[0].int == 5
  proc testResult(): Foo =
    result = Foo(1)
    int(result) = int(result) + 1
    doAssert result.int == 2
    int(result) += 1
    doAssert result.int == 3
    foo(result)
    doAssert result.int == 4
    bar(int(result)) # need vmgen flags propagated for this
    doAssert result.int == 5
  doAssert testResult().int == 5

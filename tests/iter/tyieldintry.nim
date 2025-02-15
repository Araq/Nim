discard """
  matrix: "; --experimental:strictdefs"
  targets: "c cpp"
"""

var closureIterResult = newSeq[int]()

proc checkpoint(arg: int) =
  closureIterResult.add(arg)

type
  TestError = object of CatchableError
  AnotherError = object of CatchableError

proc testClosureIterAux(it: iterator(): int, exceptionExpected: bool, expectedResults: varargs[int]) =
  closureIterResult.setLen(0)

  var exceptionCaught = false

  try:
    for i in it():
      closureIterResult.add(i)
  except TestError:
    exceptionCaught = true

  if closureIterResult != @expectedResults or exceptionCaught != exceptionExpected:
    if closureIterResult != @expectedResults:
      echo "Expected: ", @expectedResults
      echo "Actual: ", closureIterResult
    if exceptionCaught != exceptionExpected:
      echo "Expected exception: ", exceptionExpected
      echo "Got exception: ", exceptionCaught
    doAssert(false)

proc test(it: iterator(): int, expectedResults: varargs[int]) =
  testClosureIterAux(it, false, expectedResults)

proc testExc(it: iterator(): int, expectedResults: varargs[int]) =
  testClosureIterAux(it, true, expectedResults)

proc raiseTestError() =
  raise newException(TestError, "Test exception!")

block:
  iterator it(): int {.closure.} =
    var i = 5
    while i != 0:
      yield i
      if i == 3:
        yield 123
      dec i

  test(it, 5, 4, 3, 123, 2, 1)

block:
  iterator it(): int {.closure.} =
    yield 0
    try:
      checkpoint(1)
      raiseTestError()
    except TestError:
      checkpoint(2)
      yield 3
      checkpoint(4)
    finally:
      checkpoint(5)

    checkpoint(6)

  test(it, 0, 1, 2, 3, 4, 5, 6)

block:
  iterator it(): int {.closure.} =
    yield 0
    try:
      yield 1
      checkpoint(2)
    finally:
      checkpoint(3)
      yield 4
      checkpoint(5)
      yield 6

  test(it, 0, 1, 2, 3, 4, 5, 6)

block:
  iterator it(): int {.closure.} =
    yield 0
    try:
      yield 1
      raiseTestError()
      yield 2
    finally:
      checkpoint(3)
      yield 4
      checkpoint(5)
      yield 6

  testExc(it, 0, 1, 3, 4, 5, 6)

block:
  iterator it(): int {.closure.} =
    try:
      try:
        raiseTestError()
      except AnotherError:
        yield 123
      finally:
        checkpoint(3)
    finally:
      checkpoint(4)

  testExc(it, 3, 4)

block:
  iterator it(): int {.closure.} =
    try:
      yield 1
      raiseTestError()
    except AnotherError:
      checkpoint(123)
    finally:
      checkpoint(2)
    checkpoint(3)

  testExc(it, 1, 2)

block:
  iterator it(): int {.closure.} =
    try:
      yield 0
      try:
        yield 1
        try:
          yield 2
          raiseTestError()
        except AnotherError:
          yield 123
        finally:
          yield 3
      except AnotherError:
        yield 124
      finally:
        yield 4
      checkpoint(1234)
    except:
      yield 5
      checkpoint(6)
    finally:
      checkpoint(7)
      yield 8
    checkpoint(9)

  test(it, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9)

block:
  iterator it(): int {.closure.} =
    try:
      yield 0
      return 2
    finally:
      checkpoint(1)
    checkpoint(123)

  test(it, 0, 1)

block:
  iterator it(): int {.closure.} =
    try:
      try:
        yield 0
        raiseTestError()
      finally:
        checkpoint(1)
    except TestError:
      yield 2
      return
    finally:
      yield 3

    checkpoint(123)

  test(it, 0, 1, 2, 3)

block:
  iterator it(): int {.closure.} =
    try:
      try:
        yield 0
        raiseTestError()
      finally:
        return # Return in finally should stop exception propagation
    except AnotherError:
      yield 2
      return
    finally:
      yield 3
    checkpoint(123)

  test(it, 0, 3)

block: # Yield in yield
  iterator it(): int {.closure.} =
    template foo(): int =
      yield 1
      2

    for i in 0 .. 2:
      checkpoint(0)
      yield foo()

  test(it, 0, 1, 2, 0, 1, 2, 0, 1, 2)

block:
  iterator it(): int {.closure.} =
    let i = if true:
        yield 0
        1
      else:
        2
    yield i

  test(it, 0, 1)

block:
  iterator it(): int {.closure.} =
    var foo = 123
    let i = try:
        yield 0
        raiseTestError()
        1
      except TestError as e:
        assert(e.msg == "Test exception!")
        case foo
        of 1:
          yield 123
          2
        of 123:
          yield 5
          6
        else:
          7
    yield i

  test(it, 0, 5, 6)

block:
  iterator it(): int {.closure.} =
    proc voidFoo(i1, i2, i3: int) =
      checkpoint(i1)
      checkpoint(i2)
      checkpoint(i3)

    proc foo(i1, i2, i3: int): int =
      voidFoo(i1, i2, i3)
      i3

    proc bar(i1: int): int =
      checkpoint(i1)

    template tryexcept: int =
      try:
        yield 1
        raiseTestError()
        123
      except TestError:
        yield 2
        checkpoint(3)
        4

    let e1 = true

    template ifelse1: int =
      if e1:
        yield 10
        11
      else:
        12

    template ifelse2: int =
      if ifelse1() == 12:
        yield 20
        21
      else:
        yield 22
        23

    let i = foo(bar(0), tryexcept, ifelse2)
    discard foo(bar(0), tryexcept, ifelse2)
    voidFoo(bar(0), tryexcept, ifelse2)
    yield i

  test(it,

    # let i = foo(bar(0), tryexcept, ifelse2)
    0, # bar(0)
    1, 2, 3, # tryexcept
    10, # ifelse1
    22, # ifelse22
    0, 4, 23, # foo

    # discard foo(bar(0), tryexcept, ifelse2)
    0, # bar(0)
    1, 2, 3, # tryexcept
    10, # ifelse1
    22, # ifelse22
    0, 4, 23, # foo

    # voidFoo(bar(0), tryexcept, ifelse2)
    0, # bar(0)
    1, 2, 3, # tryexcept
    10, # ifelse1
    22, # ifelse22
    0, 4, 23, # foo

    23 # i
  )

block:
  iterator it(): int {.closure.} =
    checkpoint(0)
    for i in 0 .. 1:
      try:
        yield 1
        raiseTestError()
      except TestError as e:
        doAssert(e.msg == "Test exception!")
        yield 2
      except AnotherError:
        yield 123
      except:
        yield 1234
      finally:
        yield 3
        checkpoint(4)
        yield 5

  test(it, 0, 1, 2, 3, 4, 5, 1, 2, 3, 4, 5)

block:
  iterator it(): int {.closure.} =
    var i = 5
    template foo(): bool =
      yield i
      true

    while foo():
      dec i
      if i == 0:
        break

  test(it, 5, 4, 3, 2, 1)

block: # Short cirquits
  iterator it(): int {.closure.} =
    template trueYield: bool =
      yield 1
      true

    template falseYield: bool =
      yield 0
      false

    if trueYield or falseYield:
      discard falseYield and trueYield

    if falseYield and trueYield:
      checkpoint(123)

  test(it, 1, 0, 0)

block: #7969
  type
    SomeObj = object
      id: int

  iterator it(): int {.closure.} =
    template yieldAndSomeObj: SomeObj =
      var s: SomeObj
      s.id = 2
      yield 1
      s

    checkpoint(yieldAndSomeObj().id)

    var i = 5
    case i
    of 0:
      checkpoint(123)
    of 1, 2, 5:
      checkpoint(3)
    else:
      checkpoint(123)

  test(it, 1, 2, 3)

block: # yield in blockexpr
  iterator it(): int {.closure.} =
    yield(block:
      checkpoint(1)
      yield 2
      3
    )

  test(it, 1, 2, 3)

block: #8851
  type
    Foo = ref object of RootObj
  template someFoo(): Foo =
    var f: Foo
    yield 1
    f
  iterator it(): int {.closure.} =
    var o: RootRef
    o = someFoo()

  test(it, 1)

block: # 8243
  iterator it(): int {.closure.} =
    template yieldAndSeq: seq[int] =
      yield 1
      @[123, 5, 123]

    checkpoint(yieldAndSeq[1])

  test(it, 1, 5)

block:
  iterator it(): int {.closure.} =
    template yieldAndSeq: seq[int] =
      yield 1
      @[123, 5, 123]

    template yieldAndNum: int =
      yield 2
      1

    checkpoint(yieldAndSeq[yieldAndNum])

  test(it, 1, 2, 5)

block: #9694 - yield in ObjConstr
  type Foo = object
    a, b: int

  template yieldAndNum: int =
    yield 1
    2

  iterator it(): int {.closure.} =
    let a = Foo(a: 5, b: yieldAndNum())
    checkpoint(a.b)

  test(it, 1, 2)

block: #9716
  iterator it(): int {.closure.} =
    var a = 0
    for i in 1 .. 3:
      var a: int # Make sure the "local" var is reset
      var b: string # ditto
      yield 1
      a += 5
      b &= "hello"
      doAssert(a == 5)
      doAssert(b == "hello")
  test(it, 1, 1, 1)

block: # nnkChckRange
  type Foo = distinct uint64
  template yieldDistinct: Foo =
    yield 2
    Foo(0)

  iterator it(): int {.closure.} =
    yield 1
    var a: int
    a = int(yieldDistinct())
    yield 3

  test(it, 1, 2, 3)

block: #17849 - yield in case subject
  template yieldInCase: int =
    yield 2
    3

  iterator it(): int {.closure.} =
    yield 1
    case yieldInCase()
    of 1: checkpoint(11)
    of 3: checkpoint(13)
    else: checkpoint(14)
    yield 5

  test(it, 1, 2, 13, 5)

block: # void iterator
  iterator it() {.closure.} =
    try:
      yield
    except:
      discard
  var a = it

block: # Locals present in only 1 state should be on the stack
  proc checkOnStack(a: pointer, shouldBeOnStack: bool) =
    # Quick and dirty way to check if a points to stack
    var dummy = 0
    let dummyAddr = addr dummy
    let distance = abs(cast[int](dummyAddr) - cast[int](a))
    const requiredDistance = 300
    if shouldBeOnStack:
      doAssert(distance <= requiredDistance, "a is not on stack, but should")
    else:
      doAssert(distance > requiredDistance, "a is on stack, but should not")

  iterator it(): int {.closure.} =
    var a = 1
    var b = 2
    var c {.liftLocals.} = 3
    checkOnStack(addr a, true)
    checkOnStack(addr b, false)
    checkOnStack(addr c, false)
    yield a
    yield b
  test(it, 1, 2)

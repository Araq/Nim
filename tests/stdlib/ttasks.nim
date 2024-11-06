discard """
  targets: "c cpp"
  matrix: "--gc:orc --threads:off"
"""

import std/[tasks, strformat]
import std/assertions

block:
  var s = ""
  proc `+`(x: int, y: string) =
    s.add $x & y

  let literal = "Nim"
  let t = toTask(521 + literal)
  t.invoke()

  doAssert s == "521Nim"

block:
  var s = ""
  proc `!`(x: int) =
    s.add $x

  let t = toTask !12
  t.invoke()

  doAssert s == "12"


block:
  block:
    var called = 0
    proc hello(x: static range[1 .. 5]) =
      called += x

    let b = toTask hello(3)
    b.invoke()
    doAssert called == 3
    b.invoke()
    doAssert called == 6

  block:
    var called = 0
    proc hello(x: range[1 .. 5]) =
      called += x

    let b = toTask hello(3)
    b.invoke()
    doAssert called == 3
    b.invoke()
    doAssert called == 6

  block:
    var called = 0
    proc hello(x: 1 .. 5) =
      called += x

    let b = toTask hello(3)
    b.invoke()
    doAssert called == 3
    b.invoke()
    doAssert called == 6

  block:
    var temp = ""
    proc hello(a: int or seq[string]) =
      when a is seq[string]:
        for s in a:
          temp.add s
      else:
        temp.addInt a

    let x = @["1", "2", "3", "4"]
    let b = toTask hello(x)
    b.invoke()
    doAssert temp == "1234"
    b.invoke()
    doAssert temp == "12341234"


  block:
    var temp = ""

    proc hello(a: int or string) =
      when a is string:
        temp.add a

    let x = "!2"

    let b = toTask hello(x)
    b.invoke()
    doAssert temp == x

  block:
    var temp = ""
    proc hello(a: int or string) =
      when a is string:
        temp.add a

    let x = "!2"
    let b = toTask hello(x)
    b.invoke()
    doAssert temp == x

  block:
    var x = 0
    proc hello(typ: typedesc) =
      x += typ(12)

    let b = toTask hello(int)
    b.invoke()
    doAssert x == 12

  block:
    var temp = ""
    proc hello(a: int or seq[string]) =
      when a is seq[string]:
        for s in a:
          temp.add s

    let x = @["1", "2", "3", "4"]
    let b = toTask hello(x)
    b.invoke()
    doAssert temp == "1234"

  block:
    var temp = ""
    proc hello(a: int | string) =
      when a is string:
        temp.add a

    let x = "!2"
    let b = toTask hello(x)
    b.invoke()
    doAssert temp == x

  block:
    var x = 0
    proc hello(a: int | string) =
      when a is int:
        x = a

    let b = toTask hello(12)
    b.invoke()
    doAssert x == 12

  block:
    var a1: seq[int]
    var a2 = 0
    proc hello(c: seq[int], a: int) =
      a1 = c
      a2 = a

    let x = 12
    var y = @[1, 3, 1, 4, 5, x, 1]
    let b = toTask hello(y, 12)
    b.invoke()

    doAssert a1 == y
    doAssert a2 == x

  block:
    var a1: seq[int]
    var a2 = 0
    proc hello(c: seq[int], a: int) =
      a1 = c
      a2 = a
    var x = 2
    let b = toTask hello(@[1, 3, 1, 4, 5, x, 1], 12)
    b.invoke()

    doAssert a1 == @[1, 3, 1, 4, 5, x, 1]
    doAssert a2 == 12

  block:
    var a1: array[7, int]
    var a2 = 0
    proc hello(c: array[7, int], a: int) =
      a1 = c
      a2 = a

    let b = toTask hello([1, 3, 1, 4, 5, 2, 1], 12)
    b.invoke()

    doAssert a1 == [1, 3, 1, 4, 5, 2, 1]
    doAssert a2 == 12

  block:
    var a1: seq[int]
    var a2 = 0
    proc hello(c: seq[int], a: int) =
      a1 = c
      a2 = a

    let b = toTask hello(@[1, 3, 1, 4, 5, 2, 1], 12)
    b.invoke()

    doAssert a1 == @[1, 3, 1, 4, 5, 2, 1]
    doAssert a2 == 12

  block:
    var a1: seq[int]
    var a2 = 0
    proc hello(a: int, c: seq[int]) =
      a1 = c
      a2 = a

    let b = toTask hello(8, @[1, 3, 1, 4, 5, 2, 1])
    b.invoke()

    doAssert a1 == @[1, 3, 1, 4, 5, 2, 1]
    doAssert a2 == 8

    let c = toTask 8.hello(@[1, 3, 1, 4, 5, 2, 1])
    c.invoke()

    doAssert a1 == @[1, 3, 1, 4, 5, 2, 1]
    doAssert a2 == 8

  block:
    var a1: seq[seq[int]]
    var a2: int
    proc hello(a: int, c: openArray[seq[int]]) =
      a1 = @c
      a2 = a

    let b = toTask hello(8, @[@[3], @[4], @[5], @[6], @[12], @[7]])
    b.invoke()

    doAssert a1 ==  @[@[3], @[4], @[5], @[6], @[12], @[7]]
    doAssert a2 == 8

  block:
    var a1: seq[int]
    var a2: int
    proc hello(a: int, c: openArray[int]) =
      a1 = @c
      a2 = a

    let b = toTask hello(8, @[3, 4, 5, 6, 12, 7])
    b.invoke()

    doAssert a1 == @[3, 4, 5, 6, 12, 7]
    doAssert a2 == 8

  block:
    var a1: seq[int]
    var a2: int
    proc hello(a: int, c: static varargs[int]) =
      a1 = @c
      a2 = a

    let b = toTask hello(8, @[3, 4, 5, 6, 12, 7])
    b.invoke()

    doAssert a1 == @[3, 4, 5, 6, 12, 7]
    doAssert a2 == 8

  block:
    var a1: seq[int]
    var a2: int
    proc hello(a: int, c: static varargs[int]) =
      a1 = @c
      a2 = a

    let b = toTask hello(8, [3, 4, 5, 6, 12, 7])
    b.invoke()

    doAssert a1 == @[3, 4, 5, 6, 12, 7]
    doAssert a2 == 8

  block:
    var a1: seq[int]
    var a2: int
    proc hello(a: int, c: varargs[int]) =
      a1 = @c
      a2 = a

    let x = 12
    let b = toTask hello(8, 3, 4, 5, 6, x, 7)
    b.invoke()

    doAssert a1 == @[3, 4, 5, 6, 12, 7]
    doAssert a2 == 8

  block:
    var x = 12

    proc hello(x: ptr int) =
      x[] += 12

    let b = toTask hello(addr x)
    b.invoke()

    doAssert x == 24

    let c = toTask x.addr.hello
    invoke(c)

    doAssert x == 36
  block:
    type
      Test = ref object
        id: int

    var x = 0
    proc hello(a: int, c: static Test) =
      x += a
      x += c.id

    let b = toTask hello(8, Test(id: 12))
    b.invoke()

    doAssert x == 20

  block:
    type
      Test = object
        id: int

    var x = 0
    proc hello(a: int, c: static Test) =
      x += a
      x += c.id

    let b = toTask hello(8, Test(id: 12))
    b.invoke()
    doAssert x == 20

  block:
    var x = 0
    proc hello(a: int, c: static seq[int]) =
      x += a
      for i in c:
        x += i

    let b = toTask hello(8, @[3, 4, 5, 6, 12, 7])
    b.invoke()
    doAssert x == 45

  block:
    var x = 0
    proc hello(a: int, c: static array[5, int]) =
      x += a
      for i in c:
        x += i

    let b = toTask hello(8, [3, 4, 5, 6, 12])
    b.invoke()
    doAssert x == 38

  block:
    var aVal = 0
    var cVal = ""

    proc hello(a: int, c: static string) =
      aVal += a
      cVal.add c

    var x = 1314
    let b = toTask hello(x, "hello")
    b.invoke()

    doAssert aVal == x
    doAssert cVal == "hello"

  block:
    var aVal = ""

    proc hello(a: static string) =
      aVal.add a
    let b = toTask hello("hello")
    b.invoke()

    doAssert aVal == "hello"

  block:
    var aVal = 0
    var cVal = ""

    proc hello(a: static int, c: static string) =
      aVal += a
      cVal.add c
    let b = toTask hello(8, "hello")
    b.invoke()

    doAssert aVal == 8
    doAssert cVal == "hello"

  block:
    var aVal = 0
    var cVal = 0

    proc hello(a: static int, c: int) =
      aVal += a
      cVal += c

    let b = toTask hello(c = 0, a = 8)
    b.invoke()

    doAssert aVal == 8
    doAssert cVal == 0

  block:
    var aVal = 0
    var cVal = 0

    proc hello(a: int, c: static int) =
      aVal += a
      cVal += c

    let b = toTask hello(c = 0, a = 8)
    b.invoke()

    doAssert aVal == 8
    doAssert cVal == 0

  block:
    var aVal = 0
    var cVal = 0

    proc hello(a: static int, c: static int) =
      aVal += a
      cVal += c

    let b = toTask hello(0, 8)
    b.invoke()

    doAssert aVal == 0
    doAssert cVal == 8

  block:
    var temp = ""
    proc hello(x: int, y: seq[string], d = 134) =
      temp = fmt"{x=} {y=} {d=}"


    proc main() =
      var x = @["23456"]
      let t = toTask hello(2233, x)
      t.invoke()

      doAssert temp == """x=2233 y=@["23456"] d=134"""

    main()


  block:
    var temp = ""
    proc hello(x: int, y: seq[string], d = 134) =
      temp.add fmt"{x=} {y=} {d=}"

    proc ok() =
      temp = "ok"

    proc main() =
      var x = @["23456"]
      let t = toTask hello(2233, x)
      t.invoke()
      t.invoke()

      doAssert temp == """x=2233 y=@["23456"] d=134x=2233 y=@["23456"] d=134"""

    main()

    var x = @["4"]
    let m = toTask hello(2233, x, 7)
    m.invoke()

    doAssert temp == """x=2233 y=@["23456"] d=134x=2233 y=@["23456"] d=134x=2233 y=@["4"] d=7"""

    let n = toTask ok()
    n.invoke()

    doAssert temp == "ok"

  block:
    var called = 0
    block:
      proc hello() =
        inc called

      let a = toTask hello()
      invoke(a)

    doAssert called == 1

    block:
      proc hello(a: int) =
        inc called, a

      let b = toTask hello(13)
      let c = toTask hello(a = 14)
      b.invoke()
      c.invoke()

    doAssert called == 28

    block:
      proc hello(a: int, c: int) =
        inc called, a

      let b = toTask hello(c = 0, a = 8)
      b.invoke()

    doAssert called == 36

  block:
    proc returnsSomething(a, b: int): int = a + b

    proc noArgsButReturnsSomething(): string = "abcdef"

    proc testReturnValues() =
      let t = toTask returnsSomething(2233, 11)
      var res: int = 0
      t.invoke(addr res)
      doAssert res == 2233+11

      let tb = toTask noArgsButReturnsSomething()
      var resB: string = ""
      tb.invoke(addr resB)
      doAssert resB == "abcdef"

    testReturnValues()


block: # bug #23635
  block:
    type
      Store = object
        run: proc (a: int) {.nimcall, gcsafe.}

    block:
      var count = 0
      proc hello(a: int) =
        inc count, a

      var store = Store()
      store.run = hello

      let b = toTask store.run(13)
      b.invoke()
      doAssert count == 13

  block:
    type
      Store = object
        run: proc () {.nimcall, gcsafe.}

    block:
      var count = 0
      proc hello() =
        inc count, 1

      var store = Store()
      store.run = hello

      let b = toTask store.run()
      b.invoke()
      doAssert count == 1

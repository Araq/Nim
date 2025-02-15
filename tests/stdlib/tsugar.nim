discard """
  targets: "c js"
  matrix: "--mm:refc; --mm:orc"
  output: '''
x + y = 30
'''
"""
import std/[sugar, algorithm, random, sets, tables, strutils, sequtils]
import std/[syncio, assertions]

type # for capture test, ref #20679
  FooCapture = ref object
    x: int

proc mainProc() =
  block: # bug #16967
    var s = newSeq[proc (): int](5)
    {.push exportc.}
    proc bar() =
      for i in 0 ..< s.len:
        let foo = i + 1
        capture foo:
          s[i] = proc(): int = foo
    {.pop.}

    bar()

    for i, p in s.pairs:
      let foo = i + 1
      doAssert p() == foo

template main() =
  block: # `=>`
    block:
      let f1 = () => 42
      doAssert f1() == 42

      let f2 = (x: int) => x + 1
      doAssert f2(42) == 43

      let f3 = (x, y: int) => x + y
      doAssert f3(1, 2) == 3

      var x = 0
      let f4 = () => (x = 12)
      f4()
      doAssert x == 12

      let f5 = () => (discard) # simplest proc that returns void
      f5()

    block:
      proc call1(f: () -> int): int = f()
      doAssert call1(() => 12) == 12

      proc call2(f: int -> int): int = f(42)
      doAssert call2(x => x) == 42
      doAssert call2((x) => x) == 42
      doAssert call2((x: int) => x) == 42

      proc call3(f: (int, int) -> int): int = f(1, 2)
      doAssert call3((x, y) => x + y) == 3
      doAssert call3((x, y: int) => x + y) == 3
      doAssert call3((x: int, y: int) => x + y) == 3

      var a = 0
      proc call4(f: int -> void) = f(42)
      call4((x: int) => (a = x))
      doAssert a == 42

      proc call5(f: (int {.noSideEffect.} -> int)): int = f(42)
      doAssert call5(x {.noSideEffect.} => x + 1) == 43

  block: # `->`
    doAssert $(() -> int) == "proc (): int{.closure.}"
    doAssert $(float -> int) == "proc (i0: float): int{.closure.}"
    doAssert $((float) -> int) == "proc (i0: float): int{.closure.}"
    doAssert $((float, bool) -> int) == "proc (i0: float, i1: bool): int{.closure.}"

    doAssert $(() -> void) == "proc (){.closure.}"
    doAssert $(float -> void) == "proc (i0: float){.closure.}"
    doAssert $((float) -> void) == "proc (i0: float){.closure.}"
    doAssert $((float, bool) -> void) == "proc (i0: float, i1: bool){.closure.}"

    doAssert $(() {.inline.} -> int) == "proc (): int{.inline.}"
    doAssert $(float {.inline.} -> int) == "proc (i0: float): int{.inline.}"
    doAssert $((float) {.inline.} -> int) == "proc (i0: float): int{.inline.}"
    doAssert $((float, bool) {.inline.} -> int) == "proc (i0: float, i1: bool): int{.inline.}"

  block: # capture
    var closure1: () -> int
    for i in 0 .. 10:
      if i == 5:
        capture i:
          closure1 = () => i
    doAssert closure1() == 5

    var closure2: () -> (int, int)
    for i in 0 .. 10:
      for j in 0 .. 10:
        if i == 5 and j == 3:
          capture i, j:
            closure2 = () => (i, j)
    doAssert closure2() == (5, 3)

    block: # issue #20679
      # this should compile. Previously was broken as `var int` is an `nnkHiddenDeref`
      # which was not handled correctly

      block:
        var x = 5
        var s1 = newSeq[proc (): int](2)
        proc function(data: var int) =
          for i in 0 ..< 2:
            data = (i+1) * data
            capture data:
              s1[i] = proc(): int = data
        function(x)
        doAssert s1[0]() == 5
        doAssert s1[1]() == 10


      block:
        var y = @[5, 10]
        var s2 = newSeq[proc (): seq[int]](2)
        proc functionS(data: var seq[int]) =
          for i in 0 ..< 2:
            data.add (i+1) * 5
            capture data:
              s2[i] = proc(): seq[int] = data
        functionS(y)
        doAssert s2[0]() == @[5, 10, 5]
        doAssert s2[1]() == @[5, 10, 5, 10]


      template typeT(typ, val: untyped): untyped =
        var x = val
        var s = newSeq[proc (): typ](2)

        proc functionT[T](data: var T) =
          for i in 0 ..< 2:
            if i == 1:
              data = default(T)
            capture data:
              s[i] = proc (): T = data

        functionT(x)
        doAssert s[0]() == val
        doAssert s[1]() == x # == default
        doAssert s[1]() == default(typ)

      block:
        var x = 1.1
        typeT(float, x)
      block:
        var x = "hello"
        typeT(string, x)
      block:
        var f = FooCapture(x: 5)
        typeT(FooCapture, f)

  block: # dup
    block dup_with_field:
      type
        Foo = object
          col, pos: int
          name: string

      proc inc_col(foo: var Foo) = inc(foo.col)
      proc inc_pos(foo: var Foo) = inc(foo.pos)
      proc name_append(foo: var Foo, s: string) = foo.name &= s

      let a = Foo(col: 1, pos: 2, name: "foo")
      block:
        let b = a.dup(inc_col, inc_pos):
          _.pos = 3
          name_append("bar")
          inc_pos

        doAssert(b == Foo(col: 2, pos: 4, name: "foobar"))

      block:
        let b = a.dup(inc_col, pos = 3, name = "bar"):
          name_append("bar")
          inc_pos

        doAssert(b == Foo(col: 2, pos: 4, name: "barbar"))

    block:
      var a = @[1, 2, 3, 4, 5, 6, 7, 8, 9]
      doAssert dup(a, sort(_)) == sorted(a)
      doAssert a.dup(sort) == sorted(a)
      # Chaining:
      var aCopy = a
      aCopy.insert(10)
      doAssert a.dup(insert(10)).dup(sort()) == sorted(aCopy)

    block:
      when nimvm: discard
      else:
        const b = @[0, 1, 2]
        discard b.dup shuffle()
        doAssert b[0] == 0
        doAssert b[1] == 1

  block: # collect
    let data = @["bird", "word"] # if this gets stuck in your head, its not my fault

    doAssert collect(newSeq, for (i, d) in data.pairs: (if i mod 2 == 0: d)) == @["bird"]
    doAssert collect(initTable(2), for (i, d) in data.pairs: {i: d}) ==
      {0: "bird", 1: "word"}.toTable
    doAssert collect(initHashSet(), for d in data.items: {d}) == data.toHashSet

    block:
      let x = collect(newSeqOfCap(4)):
          for (i, d) in data.pairs:
            if i mod 2 == 0: d
      doAssert x == @["bird"]

    block: # bug #12874
      let bug = collect(
          newSeq,
          for (i, d) in data.pairs:(
            block:
              if i mod 2 == 0:
                d
              else:
                d & d
            )
      )
      doAssert bug == @["bird", "wordword"]

    block:
      let y = collect(newSeq):
        for (i, d) in data.pairs:
          try: parseInt(d) except: 0
      doAssert y == @[0, 0]

    block:
      let z = collect(newSeq):
        for (i, d) in data.pairs:
          case d
          of "bird": "word"
          else: d
      doAssert z == @["word", "word"]

    block:
      proc tforum(): seq[int] =
        collect(newSeq):
          for y in 0..10:
            if y mod 5 == 2:
              for x in 0..y:
                x
      doAssert tforum() == @[0, 1, 2, 0, 1, 2, 3, 4, 5, 6, 7]

    block:
      let x = collect:
        for d in data.items:
          when d is int: "word"
          else: d
      doAssert x == @["bird", "word"]

    block:
      doAssert collect(for (i, d) in pairs(data): (i, d)) == @[(0, "bird"), (1, "word")]
      doAssert collect(for d in data.items: (try: parseInt(d) except: 0)) == @[0, 0]
      doAssert collect(for (i, d) in pairs(data): {i: d}) ==
        {1: "word", 0: "bird"}.toTable
      doAssert collect(for d in data.items: {d}) == data.toHashSet

    block: # bug #14332
      template foo =
        discard collect(newSeq, for i in 1..3: i)
      foo()

  block: # dump
    # symbols in templates are gensym'd
    let
      x {.inject.} = 10
      y {.inject.} = 20
    dump(x + y) # x + y = 30

  block: # dumpToString
    template square(x): untyped = x * x
    let x {.inject.} = 10
    doAssert dumpToString(square(x)) == "square(x): x * x = 100"
    let s = dumpToString(doAssert 1+1 == 2)
    doAssert "failedAssertImpl" in s
    let s2 = dumpToString:
      doAssertRaises(AssertionDefect): doAssert false
    doAssert "except AssertionDefect" in s2

  block: # bug #20704
    proc test() =
      var xs, ys: seq[int] = @[]
      for i in 0..5:
        xs.add(i)

      xs.apply(proc (d: auto) = ys.add(d))
      # ^ can be turned into d => ys.add(d) when we can infer void return type, #16906
      doAssert ys == @[0, 1, 2, 3, 4, 5]

    test()

  mainProc()

when not defined(js): # TODO fixme JS VM
  static:
    main()

main()

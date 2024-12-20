{.experimental: "flexibleOptionalParams".}

block: # adapted tests from PR #18618 for RFC 402, covers issue #19556
  template fails(body: untyped) =
    doAssert not compiles(body)
    static: doAssert not compiles(body)
  block: # test basic template overload with untyped
    template t1(x: int, body: untyped) =
      block:
        var v {.inject.} = x
        body

    template t1(body: untyped) = t1(1, body)

    var outputs: seq[string]
    t1: outputs.add($v)
    t1(2): outputs.add($v)
    t1: outputs.add("hello" & $v)
    fails: t1("hello", 10)
    fails: t1()
    fails: t1(1,2,3)
    doAssert outputs == @["1", "2", "hello1"]

  block: # test template with varargs combine untyped
    template t1(x: int, vs: varargs[string], body: untyped) =
      block:
        var v {.inject.} = x + vs.len
        body

    template t1(body: untyped) = t1(1, "hello", body)

    var outputs: seq[string]
    t1: outputs.add($v)
    t1(2, "hello", "hello 2"): outputs.add($v)
    fails:
      t1(2, 3): discard v
    fails:
      t1("hello", "world"): discard v
    doAssert outputs == @["2", "4"]

  block: # test template with named parameter combine untyped
    template t1(x: int, y = 4, body: untyped) =
      block:
        var v {.inject.} = x + y
        body

    template t1(body: untyped) = t1(1, 3, body)

    t1: discard v
    t1(x = 1, 3): discard v
    t1(2): discard v

  block: # multiple overloads, covers issue #14827
    template fun(a: bool, body: untyped): untyped = discard
    template fun(a: int, body: untyped): untyped = discard
    template fun(body: untyped): untyped = discard
    fun(true): nonexistant # ok
    fun(1): nonexistant # ok
    fun: nonexistant # Error: undeclared identifier: 'nonexistant'
    template varargsUntypedRedirection(x: varargs[untyped]) =
      fun(x)
    varargsUntypedRedirection(true): nonexistant
    varargsUntypedRedirection(1): nonexistant
    varargsUntypedRedirection: nonexistant

when false: # issue #20274, pragma macros
  macro a(path: string, fn: untyped): untyped =
    result = fn
  macro a(fn: untyped): untyped =
    result = fn
  proc b() {.a: "abc".} = discard
  proc c() {.a.} = discard

import moverloadedblockparam

block:
  fun2(true): nonexistant # ok
  fun2(1): nonexistant # ok
  fun2: nonexistant # Error: undeclared identifier: 'nonexistant'

block:
  template fun2(body: untyped): int = 123
  fun2(true): nonexistant # ok
  fun2(1): nonexistant # ok
  discard (fun2 do: nonexistant) # Error: undeclared identifier: 'nonexistant'
  template fun2(a: bool, body: untyped): untyped = discard
  template fun2(a: int, body: untyped): untyped = discard
  fun2(true): nonexistant # ok
  fun2(1): nonexistant # ok
  discard (fun2 do: nonexistant)

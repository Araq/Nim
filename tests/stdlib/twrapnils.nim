discard """
  matrix: "--mm:refc; --mm:orc"
"""

import std/wrapnils
from std/options import get, isSome
import std/assertions

proc checkNotZero(x: float): float =
  doAssert x != 0
  x

proc main() =
  var witness = 0
  block:
    type Bar = object
      b1: int
      b2: ptr string

    type Foo = ref object
      x1: float
      x2: Foo
      x3: string
      x4: Bar
      x5: seq[int]
      x6: ptr Bar
      x7: array[2, string]
      x8: seq[int]
      x9: ref Bar

    type Goo = ref object
      foo: Foo

    proc fun(a: Bar): auto = a.b2

    var a: Foo = nil

    var x6: ptr Bar = nil
    when nimvm: discard # pending https://github.com/timotheecour/Nim/issues/568
    else:
      x6 = create(Bar)
      x6.b1 = 42
    var a2 = Foo(x1: 1.0, x5: @[10, 11], x6: x6)
    var a3 = Foo(x1: 1.2, x3: "abc")
    a3.x2 = a3

    var goo = Goo(foo: a)

    proc initFoo(x1: float): auto =
      witness.inc
      result = Foo(x1: x1)

    doAssert ?.a.x2.x2.x1 == 0.0
    doAssert ?.a3.x2.x2.x1 == 1.2
    doAssert ?.a3.x2.x2.x3[1] == 'b'

    doAssert ?.a3.x2.x2.x5.len == 0
    doAssert a3.x2.x2.x3.len == 3

    doAssert ?.a.x2.x2.x3[1] == default(char)
    # here we only apply wrapnil around goo.foo, not goo (and assume goo is not nil)
    doAssert ?.(goo.foo).x2.x2.x1 == 0.0

    when nimvm: discard
    else:
      doAssert ?.a2.x6[] == Bar(b1: 42) # deref for ptr Bar

    doAssert ?.a2.x1.checkNotZero == 1.0
    doAssert a == nil
    # shows that checkNotZero won't be called if a nil is found earlier in chain
    doAssert ?.a.x1.checkNotZero == 0.0

    when nimvm: discard
    else:
      # checks that a chain without nil but with an empty seq still raises
      doAssertRaises(IndexDefect): discard ?.a2.x8[3]

    # make sure no double evaluation bug
    doAssert witness == 0
    doAssert ?.initFoo(1.3).x1 == 1.3
    doAssert witness == 1

    # here, it's used twice, to deref `ref Bar` and then `ptr string`
    doAssert ?.a.x9[].fun[] == ""

    block: # `??.`
      doAssert (??.a3.x2.x2.x3.len).get == 3
      doAssert (??.a2.x4).isSome
      doAssert not (??.a.x4).isSome

  block:
    type
      A = object
        b: B
      B = object
        c: C
      C = object
        d: D
      D = ref object
        e: E
        e2: array[2, E]
        e3: seq[E]
        d3: D
        i4: int
      E = object
        f: int
        d2: D
    proc identity[T](a: T): T = a
    proc identity2[T](a: T, ignore: int): T = a
    var a: A = default(A)
    doAssert ?.a.b.c.d.e.f == 0
    doAssert ?.a.b.c.d.e.d2.d3[].d3.e.d2.e.f == 0
    doAssert ?.a.b.c.d.d3[].e.f == 0
    doAssert ?.a.b.c.d.e2[0].d2.e3[0].f == 0
    doAssert ?.a == A.default
    doAssert ?.a.b.c.d.e == E.default
    doAssert ?.a.b.c.d.e.d2 == nil

    doAssert ?.a.identity.b.c.identity2(12).d.d3.e.f == 0
    doAssert ?.a.b.c.d.d3.e2[0].f == 0
    a.b.c.d = D()
    a.b.c.d.d3 = a.b.c.d
    a.b.c.d.e2[0].f = 5
    doAssert ?.a.b.c.d.d3.e2[0].f == 5

    var d: D = nil
    doAssert ?.d.identity.i4 == 0
    doAssert ?.d.i4.identity == 0

  block: # case objects
    type
      Kind = enum k0, k1, k2
      V = object
        case kind: Kind
        of k0:
          x0: int
        of k1:
          x1: int
        of k2:
          x2: int
      A = object
        v0: V

    block:
      var a = V(kind: k0, x0: 3)
      doAssert ?.a.x0 == 3
      doAssert ?.a.x1 == 0
      a = V(kind: k1, x1: 5)
      doAssert ?.a.x0 == 0
      doAssert ?.a.x1 == 5

    block:
      var a = A(v0: V(kind: k0, x0: 10))
      doAssert ?.a.v0.x0 == 10
      doAssert ?.a.v0.x1 == 0
      a.v0 = V(kind: k2, x2: 8)
      doAssert ?.a.v0.x0 == 0
      doAssert ?.a.v0.x1 == 0
      doAssert ?.a.v0.x2 == 8

  block: # `nnkCall`
    type
      A = object
        a0: int
        d: D
      D = ref object
        i4: int

    proc identity[T](a: T): T = a
    var d: D = nil
    doAssert ?.d.i4.identity == 0
    doAssert ?.identity(?.d.i4) == 0
    doAssert ?.identity(d.i4) == 0
    doAssert ?.identity(d) == nil
    doAssert ?.identity(d[]) == default(typeof(d[]))
    doAssert ?.identity(d[]).i4 == 0
    var a: A = default(A)
    doAssert ?.identity(a) == default(A)
    doAssert ?.identity(a.a0) == 0
    doAssert ?.identity(a.d) == nil
    doAssert ?.identity(a.d.i4) == 0

  block: # lvalue semantic propagation
    type
      A = ref object
        a0: A
        a1: seq[A]
        a2: int

      B = object
        b0: int
        case cond: bool
        of false: discard
        of true:
          b1: float

    block:
      var a: A = default(A)
      doAssert ?.a.a0.a1[0].a2.addr == nil
      a = A(a2: 3)
      doAssert ?.a.a0.a1[0].a2.addr == nil
      a.a0 = a
      a.a1 = @[a]
      let p = ?.a.a0.a1[0].a2.addr
      doAssert p != nil
      p[] = 5
      doAssert a.a2 == 5

    block:
      var b = B(cond: false, b0: 3)
      let p = ?.b.b1.addr
      doAssert p == nil
      b = B(cond: true, b1: 4.5)
      let p2 = ?.b.b1.addr
      doAssert p2 != nil
      p2[] = 4.6
      doAssert b.b1 == 4.6
      # useful pattern, impossible with Options
      if (let p3 = ?.b.b1.addr; p3 != nil):
        p3[] = 4.7
      doAssert b.b1 == 4.7

main()
static: main()

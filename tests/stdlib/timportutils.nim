discard """
  matrix: "--mm:refc; --mm:orc"
"""

import std/[importutils, assertions, objectequals]
import stdtest/testutils
import mimportutils

template main =
  block: # privateAccess
    assertAll:
      var a: A
      var b = initB() # B is private
      compiles(a.a0)
      compiles(b.b0)
      not compiles(a.ha1)
      not compiles(b.hb1)

    block:
      assertAll:
        privateAccess A
        compiles(a.ha1)
        a.ha1 == 0.0
        not compiles(a.hb1)
        privateAccess b.typeof
        b.hb1 = 3
        type B2 = b.typeof
        let b2 = B2(b0: 4, hb1: 5)
        b.hb1 == 3
        b2 == B2(b0: 4, hb1: 5)

    assertAll:
      not compiles(a.ha1)
      not compiles(b.hb1)

    block:
      assertAll:
        not compiles(C(c0: 1, hc1: 2))
        privateAccess C
        let c = C(c0: 1, hc1: 2)
        c.hc1 == 2

    block:
      assertAll:
        not compiles(E[int](he1: 1))
        privateAccess E[int]
        var e = E[int](he1: 1)
        e.he1 == 1
        e.he1 = 2
        e.he1 == 2
        e.he1 += 3
        e.he1 == 5
        # xxx caveat: this currently compiles but in future, we may want
        # to make `privateAccess E[int]` only affect a specific instantiation;
        # note that `privateAccess E` does work to cover all instantiations.
        var e2 = E[float](he1: 1)

    block:
      assertAll:
        not compiles(E[int](he1: 1))
        privateAccess E
        var e = E[int](he1: 1)
        e.he1 == 1

    block:
      assertAll:
        not compiles(F[int, int](h3: 1))
        privateAccess F[int, int]
        var e = F[int, int](h3: 1)
        e.h3 == 1

    block:
      assertAll:
        not compiles(F[int, int](h3: 1))
        privateAccess F[int, int].default[].typeof
        var e = F[int, int](h3: 1)
        e.h3 == 1

    block:
      assertAll:
        var a = G[int]()
        var b = a.addr
        privateAccess b.type
        discard b.he1
        discard b[][].he1

    block:
      assertAll:
        privateAccess H[int]
        var a = H[int](h5: 2)

    block:
      assertAll:
        privateAccess PA
        var pa = PA(a0: 1, ha1: 2)
        pa.ha1 == 2
        pa.ha1 = 3
        pa.ha1 == 3

    block:
      assertAll:
        var b = BAalias()
        not compiles(b.hb1)
        privateAccess BAalias
        discard b.hb1

    block:
      assertAll:
        var a = A(a0: 1)
        var a2 = a.addr
        not compiles(a2.ha1)
        privateAccess PtA
        a2.type is PtA
        a2.ha1 = 2
        a2.ha1 == 2
        a.ha1 = 3
        a2.ha1 == 3

    block:
      disableVm:
        assertAll:
          var a = A.create()
          defer: dealloc(a)
          a is PtA
          a.typeof is PtA
          not compiles(a.ha1)
          privateAccess a.typeof
          a.ha1 = 2
          a.ha1 == 2
          a[].ha1 = 3
          a.ha1 == 3

    block:
      disableVm:
        assertAll:
          var a = A.create()
          defer: dealloc(a)
          privateAccess PtA
          a.ha1 == 0

    block:
      privateAccess PityRef
      let x = PityRef[int](a: 1)  # works
      doAssert x.a == 1

      privateAccess Hope
      let y = Hope[int](a: 1)
      doAssert y.a == 1

static: main()
main()

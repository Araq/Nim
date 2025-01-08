discard """
targets: "c js"
output: '''
foo88
23 24foo 88
foo88
23 24foo 88
11
int: 108
0
11
1
11
2
11
3
11
4
11
5
11
6
11
7
11
8
11
9
11
11
py
py
py
py
px
6
proc (){.closure, noSideEffect, gcsafe.}
'''
"""


block tnestedclosure:
  proc main(param: int) =
    var foo = 23
    proc outer(outerParam: string) =
      var outerVar = 88
      echo outerParam, outerVar
      proc inner() =
        block Test:
          echo foo, " ", param, outerParam, " ", outerVar
      inner()
    outer("foo")

  # test simple closure within dummy 'main':
  proc dummy =
    proc main2(param: int) =
      var fooB = 23
      proc outer(outerParam: string) =
        var outerVar = 88
        echo outerParam, outerVar
        proc inner() =
          block Test:
            echo fooB, " ", param, outerParam, " ", outerVar
        inner()
      outer("foo")
    main2(24)

  dummy()

  main(24)

  # Jester + async triggered this bug:
  proc cbOuter() =
    var response = "hohoho"
    block:
      proc cbIter() =
        block:
          proc fooIter() =
            doAssert response == "hohoho"
          fooIter()
      cbIter()
  cbOuter()


block tnestedproc:
  proc p(x, y: int): int =
    result = x + y

  echo p((proc (): int =
            var x = 7
            return x)(),
         (proc (): int = return 4)())


block deeplynested:
  # bug #4070
  proc id(f: (proc())): auto =
    return f

  proc foo(myinteger: int): (iterator(): int) =
    return iterator(): int {.closure.} =
            proc bar() =
              proc kk() =
                echo "int: ", myinteger
              kk()
            id(bar)()

  discard foo(108)()


block tclosure2:
  when true:
    proc ax =
      for xxxx in 0..9:
        var i = 0
        proc bx =
          if i > 10:
            echo xxxx
            return
          i += 1
          #for j in 0 .. 0: echo i
          bx()

        bx()
        echo i

    ax()

  when true:
    proc accumulator(start: int): (proc(): int {.closure.}) =
      var x = start-1
      #let dummy = proc =
      #  discard start

      result = proc (): int =
        #var x = 9
        for i in 0 .. 0: x = x + 1

        return x

    var a = accumulator(3)
    let b = accumulator(4)
    echo a() + b() + a()


    proc outer =

      proc py() =
        # no closure here:
        for i in 0..3: echo "py"

      py()

    outer()


  when true:
    proc outer2 =
      var errorValue = 3
      proc fac[T](n: T): T =
        if n < 0: result = errorValue
        elif n <= 1: result = 1
        else: result = n * fac(n-1)

      proc px() {.closure.} =
        echo "px"

      proc py() {.closure.} =
        echo "py"

      let
        mapping = {
          "abc": px,
          "xyz": py
        }
      mapping[0][1]()

      echo fac(3)


    outer2()

# bug #5688

import typetraits

block:
  proc myDiscard[T](a: T) = discard

  proc foo() =
    let a = 5
    let f = (proc() =
              myDiscard (proc() = echo a)
            )
    echo name(typeof(f))

  foo()


block:
  iterator foo: int {.closure.} =
    yield 1
    yield 2
    yield 3

  proc pork =
    let call = foo
    for i in call():
      discard i

    let call2 = foo
    while not finished(call2):
      discard call2()

  pork()

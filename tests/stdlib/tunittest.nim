discard """
  output: '''

[Suite] suite with only teardown

[Suite] suite with only setup

[Suite] suite with none

[Suite] suite with both

[Suite] bug #4494

[Suite] bug #5571

[Suite] bug #5784

[Suite] test suite

[Suite] test name filtering
'''
matrix: "--mm:refc; --mm:orc"
targets: "c js"
"""

import std/[unittest, sequtils, assertions, objectequals]
from std/unittest {.all.} import matchFilter

proc doThings(spuds: var int): int =
  spuds = 24
  return 99
test "#964":
  var spuds = 0
  check doThings(spuds) == 99
  check spuds == 24


from std/strutils import toUpperAscii
test "#1384":
  check(@["hello", "world"].map(toUpperAscii) == @["HELLO", "WORLD"])


import std/options
test "unittest typedescs":
  check(none(int) == none(int))
  check(none(int) != some(1))


test "unittest multiple requires":
  require(true)
  require(true)


import std/random
from std/strutils import parseInt
proc defectiveRobot() =
  case rand(1..4)
  of 1: raise newException(OSError, "CANNOT COMPUTE!")
  of 2: discard parseInt("Hello World!")
  of 3: raise newException(IOError, "I can't do that Dave.")
  else: doAssert 2 + 2 == 5
test "unittest expect":
  expect IOError, OSError, ValueError, AssertionDefect:
    defectiveRobot()

var
  a = 1
  b = -1
  c = 1

#unittests are sequential right now
suite "suite with only teardown":
  teardown:
    b = 2

  test "unittest with only teardown 1":
    check a == c

  test "unittest with only teardown 2":
    check b > a

suite "suite with only setup":
  setup:
    var testVar {.used.} = "from setup"

  test "unittest with only setup 1":
    check testVar == "from setup"
    check b > a
    b = -1

  test "unittest with only setup 2":
    check b < a

suite "suite with none":
  test "unittest with none":
    check b < a

suite "suite with both":
  setup:
    a = -2

  teardown:
    c = 2

  test "unittest with both 1":
    check b > a

  test "unittest with both 2":
    check c == 2

suite "bug #4494":
    test "Uniqueness check":
      var tags = @[1, 2, 3, 4, 5]
      check:
        allIt(0..3, tags[it] != tags[it + 1])

suite "bug #5571":
  test "can define gcsafe procs within tests":
    proc doTest {.gcsafe.} =
      let line = "a"
      check: line == "a"
    doTest()

suite "bug #5784":
  test "`or` should short circuit":
    type Obj = ref object
      field: int
    var obj: Obj
    check obj.isNil or obj.field == 0

type
    SomeType = object
        value: int
        children: seq[SomeType]

# bug #5252

proc `==`(a, b: SomeType): bool =
    return a.value == b.value

suite "test suite":
    test "test":
        let a = SomeType(value: 10)
        let b = SomeType(value: 10)

        check(a == b)

suite "test name filtering":
  test "test name":
    check matchFilter("suite1", "foo", "")
    check matchFilter("suite1", "foo", "foo")
    check matchFilter("suite1", "foo", "::")
    check matchFilter("suite1", "foo", "*")
    check matchFilter("suite1", "foo", "::foo")
    check matchFilter("suite1", "::foo", "::foo")

  test "test name - glob":
    check matchFilter("suite1", "foo", "f*")
    check matchFilter("suite1", "foo", "*oo")
    check matchFilter("suite1", "12345", "12*345")
    check matchFilter("suite1", "q*wefoo", "q*wefoo")
    check false == matchFilter("suite1", "foo", "::x")
    check false == matchFilter("suite1", "foo", "::x*")
    check false == matchFilter("suite1", "foo", "::*x")
    #  overlap
    check false == matchFilter("suite1", "12345", "123*345")
    check matchFilter("suite1", "ab*c::d*e::f", "ab*c::d*e::f")

  test "suite name":
    check matchFilter("suite1", "foo", "suite1::")
    check false == matchFilter("suite1", "foo", "suite2::")
    check matchFilter("suite1", "qwe::foo", "qwe::foo")
    check matchFilter("suite1", "qwe::foo", "suite1::qwe::foo")

  test "suite name - glob":
    check matchFilter("suite1", "foo", "::*")
    check matchFilter("suite1", "foo", "*::*")
    check matchFilter("suite1", "foo", "*::foo")
    check false == matchFilter("suite1", "foo", "*ite2::")
    check matchFilter("suite1", "q**we::foo", "q**we::foo")
    check matchFilter("suite1", "a::b*c::d*e", "a::b*c::d*e")


block:
  type MyFoo = object
  var obj = MyFoo()
  let check = 1
  check(obj == obj)

block:
  let check = 123
  var a = 1
  var b = 1
  check(a == b)

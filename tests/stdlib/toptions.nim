discard """
  matrix: "--mm:refc; --mm:orc"
  targets: "c js"
"""

import std/[json, options]

import std/assertions
import std/objectdollar


# RefPerson is used to test that overloaded `==` operator is not called by
# options. It is defined here in the global scope, because otherwise the test
# will not even consider the `==` operator. Different bug?
type RefPerson = ref object
  name: string

proc `==`(a, b: RefPerson): bool =
  assert(not a.isNil and not b.isNil)
  a.name == b.name


template disableJsVm(body) =
  # something doesn't work in JS VM
  when defined(js):
    when nimvm: discard
    else: body
  else:
    body

proc main() =
  type
    Foo = ref object
      test: string
    Test = object
      foo: Option[Foo]

  let js = """{"foo": {"test": "123"}}"""
  let parsed = parseJson(js)
  let a = parsed.to(Test)
  doAssert $(%*a) == """{"foo":{"test":"123"}}"""

  block options:
    # work around a bug in unittest
    let intNone = none(int)
    let stringNone = none(string)

    block example:
      proc find(haystack: string, needle: char): Option[int] =
        result = none(int)
        for i, c in haystack:
          if c == needle:
            return some i

      doAssert("abc".find('c').get() == 2)

      let result = "team".find('i')

      doAssert result == intNone
      doAssert result.isNone

    block some:
      doAssert some(6).get() == 6
      doAssert some("a").unsafeGet() == "a"
      doAssert some(6).isSome
      doAssert some("a").isSome

    block none:
      doAssertRaises UnpackDefect:
        discard none(int).get()
      doAssert(none(int).isNone)
      doAssert(not none(string).isSome)

    block equality:
      doAssert some("a") == some("a")
      doAssert some(7) != some(6)
      doAssert some("a") != stringNone
      doAssert intNone == intNone

      when compiles(some("a") == some(5)):
        doAssert false
      when compiles(none(string) == none(int)):
        doAssert false

    block get_with_a_default_value:
      doAssert(some("Correct").get("Wrong") == "Correct")
      doAssert(stringNone.get("Correct") == "Correct")

    block stringify:
      doAssert($(some("Correct")) == "some(\"Correct\")")
      doAssert($(stringNone) == "none(string)")

    disableJsVm:
      block map_with_a_void_result:
        var procRan = 0
        # TODO closure anonymous functions doesn't work in VM with JS
        # Error: cannot evaluate at compile time: procRan
        some(123).map(proc (v: int) = procRan = v)
        doAssert procRan == 123
        intNone.map(proc (v: int) = doAssert false)

    block map:
      doAssert(some(123).map(proc (v: int): int = v * 2) == some(246))
      doAssert(intNone.map(proc (v: int): int = v * 2).isNone)

    block filter:
      doAssert(some(123).filter(proc (v: int): bool = v == 123) == some(123))
      doAssert(some(456).filter(proc (v: int): bool = v == 123).isNone)
      doAssert(intNone.filter(proc (v: int): bool = raiseAssert "false").isNone)

    block flatMap:
      proc addOneIfNotZero(v: int): Option[int] =
        if v != 0:
          result = some(v + 1)
        else:
          result = none(int)

      doAssert(some(1).flatMap(addOneIfNotZero) == some(2))
      doAssert(some(0).flatMap(addOneIfNotZero) == none(int))
      doAssert(some(1).flatMap(addOneIfNotZero).flatMap(addOneIfNotZero) == some(3))

      proc maybeToString(v: int): Option[string] =
        if v != 0:
          result = some($v)
        else:
          result = none(string)

      doAssert(some(1).flatMap(maybeToString) == some("1"))

      proc maybeExclaim(v: string): Option[string] =
        if v != "":
          result = some v & "!"
        else:
          result = none(string)

      doAssert(some(1).flatMap(maybeToString).flatMap(maybeExclaim) == some("1!"))
      doAssert(some(0).flatMap(maybeToString).flatMap(maybeExclaim) == none(string))

    block SomePointer:
      var intref: ref int = nil
      doAssert(option(intref).isNone)
      intref.new
      doAssert(option(intref).isSome)

      let tmp = option(intref)
      doAssert(sizeof(tmp) == sizeof(ptr int))

      var prc = proc (x: int): int = x + 1
      doAssert(option(prc).isSome)
      prc = nil
      doAssert(option(prc).isNone)

    block:
      doAssert(none[int]().isNone)
      doAssert(none(int) == none[int]())

    # "$ on typed with .name"
    block:
      type Named = object
        name: string

      let nobody = none(Named)
      doAssert($nobody == "none(Named)")

    # "$ on type with name()"
    block:
      type Person = object
        myname: string

      let noperson = none(Person)
      doAssert($noperson == "none(Person)")

    # "Ref type with overloaded `==`"
    block:
      let p = some(RefPerson.new())
      doAssert p.isSome

    block: # test cstring
      block:
        let x = some("".cstring)
        doAssert x.isSome
        doAssert x.get == ""

      block:
        let x = some("12345".cstring)
        doAssert x.isSome
        doAssert x.get == "12345"

      block:
        let x = "12345".cstring
        let y = some(x)
        doAssert y.isSome
        doAssert y.get == "12345"

      block:
        let x = none(cstring)
        doAssert x.isNone
        doAssert $x == "none(cstring)"

static: main()
main()

when not defined(js):
  block: # bug #22932
    var it = iterator: int {.closure.} = discard
    doAssert it.option.isSome # Passes.
    it = nil
    doAssert it.option.isNone # Passes.

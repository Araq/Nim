discard """
  targets: "cpp"
  matrix: "--gc:orc"
"""

import std/options

# bug #18410
type
  O = object of RootObj
   val: pointer

proc p(): Option[O] = none(O)

doAssert $p() == "none(O)"

# bug #17351
type
  Foo = object of RootObj
  Foo2 = object of Foo
  Bar = object
    x: Foo2

var b = Bar()
discard b

# bug #4678
{.emit: """/*TYPESECTION*/
enum class SomeEnum {A,B,C};
""".}
type
  EnumVector[T: enum] {.importcpp: "std::vector", header: "vector".} = object
  SomeEnum {.importcpp, nodecl.} = enum
    A,B,C

proc asVector*[T](t: T): EnumVector[T] =
  discard
# Nim generates this signature here:
# N_NIMCALL(std::vector<> , asvector_106028_3197418230)(SomeEnum t0)

discard asVector(SomeEnum.A)


block: # bug #10219
  type
    Vector[T]  {.importcpp: "std::vector", header: "vector".} = object

  proc initVector[T](n: csize_t): Vector[T] 
      {.importcpp: "std::vector<'*0>(@)", header: "vector".}

  proc unsafeIndex[T](this: var Vector[T], i: csize_t): var T 
      {.importcpp: "#[#]", header: "vector".}

  proc `[]`[T](this: var Vector[T], i: Natural): var T {.inline, noinit.} =
    when compileOption("boundChecks"):
        # this.checkIndex i
        discard
    result = this.unsafeIndex(csize_t(i))

  var v1 = initVector[int](10)
  doAssert v1[0] == 0

block: # bug #12703 bug #19588
  type
    cstringConstImpl {.importc:"const char*".} = cstring
    constChar = distinct cstringConstImpl

  {.emit: """
  const char* foo() {
    return "hello";
  }
  """.}
  proc foo(): constChar {.importcpp.} # change to importcpp for C++ backend
  doAssert $(foo().cstring) == "hello"


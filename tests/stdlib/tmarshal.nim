discard """
  matrix: "--mm:orc; --mm:refc"
"""

import std/marshal
import std/[assertions, objectdollar, streams]

# TODO: add static tests

proc testit[T](x: T): string = $$to[T]($$x)

template check1 =
  let test1: array[0..1, array[0..4, string]] = [
    ["test", "1", "2", "3", "4"], ["test", "1", "2", "3", "4"]]
  doAssert testit(test1) ==
    """[["test", "1", "2", "3", "4"], ["test", "1", "2", "3", "4"]]"""
  let test2: tuple[name: string, s: int] = ("tuple test", 56)
  doAssert testit(test2) == """{"Field0": "tuple test", "Field1": 56}"""

static: check1()
check1()

type
  TE = enum
    blah, blah2

  TestObj = object
    test, asd: int
    case test2: TE
    of blah:
      help: string
    else:
      discard

  PNode = ref TNode
  TNode = object
    next, prev: PNode
    data: string

proc buildList(): PNode =
  new(result)
  new(result.next)
  new(result.prev)
  result.data = "middle"
  result.next.data = "next"
  result.prev.data = "prev"
  result.next.next = result.prev
  result.next.prev = result
  result.prev.next = result
  result.prev.prev = result.next

let test3 = TestObj(test: 42, test2: blah)
doAssert testit(test3) ==
  """{"test": 42, "asd": 0, "test2": "blah", "help": ""}"""

var test4: ref tuple[a, b: string]
new(test4)
test4.a = "ref string test: A"
test4.b = "ref string test: B"
discard testit(test4) # serialization uses the pointer address, which is not consistent

let test5 = @[(0,1),(2,3),(4,5)]
doAssert testit(test5) ==
  """[{"Field0": 0, "Field1": 1}, {"Field0": 2, "Field1": 3}, {"Field0": 4, "Field1": 5}]"""

let test6: set[char] = {'A'..'Z', '_'}
doAssert testit(test6) ==
  """[65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 95]"""

let test7 = buildList()
discard testit(test7) # serialization uses the pointer address, which is not consistent


# bug #1352
block:
  type
    Entity = object of RootObj
      name: string

    Person = object of Entity
      age: int
      bio: string
      blob: string

  let instance1 = Person(name: "Cletus", age: 12,
                         bio: "Я Cletus",
                         blob: "ABC\x80")
  doAssert $$instance1 == """{"age": 12, "bio": "Я Cletus", "blob": [65, 66, 67, 128], "name": "Cletus"}"""
  doAssert to[Person]($$instance1).bio == instance1.bio
  doAssert to[Person]($$instance1).blob == instance1.blob

# bug #5757
block:
  type
    Something = object
      x: string
      y: int

  let data1 = """{"x": "alpha", "y": 100}"""
  let data2 = """{"x": "omega", "y": 200}"""

  var r = to[Something](data1)
  doAssert $r.x & " " & $r.y == "alpha 100"
  r = to[Something](data2)
  doAssert $r.x & " " & $r.y == "omega 200"

block:
  type
    Foo = object
      a1: string
      a2: string
      a3: seq[string]
      a4: seq[int]
      a5: seq[int]
      a6: seq[int]
  var foo = Foo(a2: "", a4: @[], a6: @[1])
  foo.a6.setLen 0
  doAssert $$foo == """{"a1": "", "a2": "", "a3": [], "a4": [], "a5": [], "a6": []}"""
  doAssert testit(foo) == """{"a1": "", "a2": "", "a3": [], "a4": [], "a5": [], "a6": []}"""

import std/[options, json]

# bug #15934
block:
  let
    a1 = some(newJNull())
    a2 = none(JsonNode)
  doAssert $($$a1).to[:Option[JsonNode]] == "some(null)"
  doAssert $($$a2).to[:Option[JsonNode]] == "none(JsonNode)"
  doAssert ($$a1).to[:Option[JsonNode]] == some(newJNull())
  doAssert ($$a2).to[:Option[JsonNode]] == none(JsonNode)

# bug #15620
block:
  let str = """{"numeric": null}"""

  type
    LegacyEntry = object
      numeric: string

  let test = to[LegacyEntry](str)
  doAssert $test == """(numeric: "")"""

block:
  let str = """{"numeric": null}"""

  type
    LegacyEntry = object
      numeric: seq[int]

  var test = to[LegacyEntry](str)
  doAssert $test == """(numeric: @[])"""

# bug #16022
block:
  let p: proc (): string = proc (): string = "hello world"
  let poc = to[typeof(p)]($$p)
  doAssert poc() == "hello world"

block:
  type
    A {.inheritable.} = object
    B = object of A
      f: int

  let a: ref A = new(B)
  doAssert $$a[] == "{}" # not "{f: 0}"

# bug #16496
block:
  type
    A = ref object
      data: seq[int]

    B = ref object
      x: A
  let o = A(data: @[1, 2, 3, 4])
  let s1 = @[B(x: o), B(x: o)]
  let m  = $$ s1
  let s2 = to[seq[B]](m)
  doAssert s2[0].x.data == s2[1].x.data
  doAssert s1[0].x.data == s2[1].x.data


block:
  type
    Obj = ref object
      i: int
      b: bool

  let
    strm = newStringStream()

  var
    o = Obj(i: 1, b: false)
    t1 = @[o, o]
    t2: seq[Obj]

  doAssert t1[0] == t1[1]

  strm.store(t1)
  strm.setPosition(0)
  strm.load(t2)
  strm.close()

  doAssert t2[0] == t2[1]


template checkMarshal(data: typed) =
  let orig = data
  let m = $$orig

  let old = to[typeof(orig)](m)
  doAssert data == old

template main() =
  type
    Book = object
      page: int
      name: string

  let book = Book(page: 12, name: "persona")

  checkMarshal(486)
  checkMarshal(3.14)
  checkMarshal("azure sky")
  checkMarshal(book)
  checkMarshal([1, 2, 3])
  checkMarshal(@[1.5, 2.7, 3.9, 4.2])
  checkMarshal(@["dream", "is", "possible"])

static: main()
main()

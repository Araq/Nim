discard """
  output: ""
  matrix: "--mm:refc; --mm:orc"
  targets: "c js"
"""

import json, strutils, options, tables
import std/[assertions, objectequals]

# The definition of the `%` proc needs to be here, since the `% c` calls below
# can only find our custom `%` proc for `Pix` if defined in global scope.
type
  Pix = tuple[x, y: uint8, ch: uint16]
proc `%`(p: Pix): JsonNode =
  result = %* { "x" : % p.x,
                "y" : % p.y,
                "ch" : % p.ch }

proc testJson() =
  # Tests inspired by own use case (with some additional tests).
  # This should succeed.
  type
    Point[T] = object
      x, y: T

    ReplayEventKind = enum
      FoodAppeared, FoodEaten, DirectionChanged

    ReplayEvent = object
      time*: float
      case kind*: ReplayEventKind
      of FoodAppeared, FoodEaten:
        foodPos*: Point[float]
        case subKind*: bool
        of true:
          it: int
        of false:
          ot: float
      of DirectionChanged:
        playerPos*: float

    Replay = ref object
      events*: seq[ReplayEvent]
      test: int
      test2: string
      test3: bool
      testNil: string

  var x = Replay(
    events: @[
      ReplayEvent(
        time: 1.2345,
        kind: FoodEaten,
        foodPos: Point[float](x: 5.0, y: 1.0),
        subKind: true,
        it: 7
      )
    ],
    test: 18827361,
    test2: "hello world",
    test3: true,
    testNil: "nil"
  )

  let node = %x

  let y = to(node, Replay)
  doAssert y.events[0].time == 1.2345
  doAssert y.events[0].kind == FoodEaten
  doAssert y.events[0].foodPos.x == 5.0
  doAssert y.events[0].foodPos.y == 1.0
  doAssert y.test == 18827361
  doAssert y.test2 == "hello world"
  doAssert y.test3
  doAssert y.testNil == "nil"

  # Test for custom object variants (without an enum) and with an else branch.
  block:
    type
      TestVariant = object
        name: string
        case age: uint8
        of 2:
          preSchool: string
        of 8:
          primarySchool: string
        else:
          other: int

    var node = %{
      "name": %"Nim",
      "age": %8,
      "primarySchool": %"Sandtown"
    }

    var result = to(node, TestVariant)
    doAssert result.age == 8
    doAssert result.name == "Nim"
    doAssert result.primarySchool == "Sandtown"

    node = %{
      "name": %"⚔️Foo☢️",
      "age": %25,
      "other": %98
    }

    result = to(node, TestVariant)
    doAssert result.name == node["name"].getStr()
    doAssert result.age == node["age"].getInt().uint8
    doAssert result.other == node["other"].getBiggestInt()

  # TODO: Test object variant with set in of branch.
  # TODO: Should we support heterogeneous arrays?

  # Tests that verify the error messages for invalid data.
  block:
    type
      Person = object
        name: string
        age: int

    var node = %{
      "name": %"Dominik"
    }

    try:
      discard to(node, Person)
      doAssert false
    except KeyError as exc:
      doAssert("age" in exc.msg)
    except:
      doAssert false

    node["age"] = %false

    try:
      discard to(node, Person)
      doAssert false
    except JsonKindError as exc:
      doAssert("age" in exc.msg)
    except:
      doAssert false

    type
      PersonAge = enum
        Fifteen, Sixteen

      PersonCase = object
        name: string
        case age: PersonAge
        of Fifteen:
          discard
        of Sixteen:
          id: string

    try:
      discard to(node, PersonCase)
      doAssert false
    except JsonKindError as exc:
      doAssert("age" in exc.msg)
    except:
      doAssert false

  # Test the example in json module.
  block:
    let jsonNode = parseJson("""
      {
        "person": {
          "name": "Nimmer",
          "age": 21
        },
        "list": [1, 2, 3, 4]
      }
    """)

    type
      Person = object
        name: string
        age: int

      Data1 = object # TODO: Codegen bug when changed to ``Data``.
        person: Person
        list: seq[int]

    var data = to(jsonNode, Data1)
    doAssert data.person.name == "Nimmer"
    doAssert data.person.age == 21
    doAssert data.list == @[1, 2, 3, 4]

  # Test non-variant enum fields.
  block:
    type
      EnumType = enum
        Foo, Bar

      TestEnum = object
        field: EnumType

    var node = %{
      "field": %"Bar"
    }

    var result = to(node, TestEnum)
    doAssert result.field == Bar

  # Test ref type in field.
  block:
    var jsonNode = parseJson("""
      {
        "person": {
          "name": "Nimmer",
          "age": 21
        },
        "list": [1, 2, 3, 4]
      }
    """)

    type
      Person = ref object
        name: string
        age: int

      Data = object
        person: Person
        list: seq[int]

    var data = to(jsonNode, Data)
    doAssert data.person.name == "Nimmer"
    doAssert data.person.age == 21
    doAssert data.list == @[1, 2, 3, 4]

    jsonNode = parseJson("""
      {
        "person": null,
        "list": [1, 2, 3, 4]
      }
    """)
    data = to(jsonNode, Data)
    doAssert data.person.isNil

  block:
    type
      FooBar = object
        field: float

    let x = parseJson("""{ "field": 5}""")
    let data = to(x, FooBar)
    doAssert data.field == 5.0

  block:
    type
      BirdColor = object
        name: string
        rgb: array[3, float]

    type
      Bird = object
        age: int
        height: float
        name: string
        colors: array[2, BirdColor]

    var red = BirdColor(name: "red", rgb: [1.0, 0.0, 0.0])
    var blue = BirdColor(name: "blue", rgb: [0.0, 0.0, 1.0])
    var b = Bird(age: 3, height: 1.734, name: "bardo", colors: [red, blue])
    let jnode = %b
    let data = jnode.to(Bird)
    doAssert data == b

  block:
    type
      MsgBase = ref object of RootObj
        name*: string

      MsgChallenge = ref object of MsgBase
        challenge*: string

    let data = %*{"name": "foo", "challenge": "bar"}
    let msg = data.to(MsgChallenge)
    doAssert msg.name == "foo"
    doAssert msg.challenge == "bar"

  block:
    type
      Color = enum Red, Brown
      Thing = object
        animal: tuple[fur: bool, legs: int]
        color: Color

    var j = parseJson("""
      {"animal":{"fur":true,"legs":6},"color":"Red"}
    """)

    let parsed = to(j, Thing)
    doAssert parsed.animal.fur
    doAssert parsed.animal.legs == 6
    doAssert parsed.color == Red

  block:
    when not defined(js):
      # disable on js because of #12492
      type
        Car = object
          engine: tuple[name: string, capacity: float]
          model: string

      let j = """
        {"engine": {"name": "V8", "capacity": 5.5}, "model": "Skyline"}
      """

      var i = 0
      proc mulTest(): JsonNode =
        inc i
        return parseJson(j)

      let parsed = mulTest().to(Car)
      doAssert parsed.engine.name == "V8"

      doAssert i == 1

  block:
    # Option[T] support!
    type
      Car1 = object # TODO: Codegen bug when `Car`
        engine: tuple[name: string, capacity: Option[float]]
        model: string
        year: Option[int]

    let noYear = """
      {"engine": {"name": "V8", "capacity": 5.5}, "model": "Skyline"}
    """

    let noYearParsed = parseJson(noYear)
    let noYearDeser = to(noYearParsed, Car1)
    doAssert noYearDeser.engine.capacity == some(5.5)
    doAssert noYearDeser.year.isNone
    doAssert noYearDeser.engine.name == "V8"

    # Issue #7433
    type
      Obj2 = object
        n1: int
        n2: Option[string]
        n3: bool

    var j = %*[ { "n1": 4, "n2": "ABC", "n3": true },
                { "n1": 1, "n3": false },
                { "n1": 1, "n2": "XYZ", "n3": false } ]

    let jDeser = j.to(seq[Obj2])
    doAssert jDeser[0].n2.get() == "ABC"
    doAssert jDeser[1].n2.isNone()

    # Issue #6902
    type
      Obj = object
        n1: int
        n2: Option[int]
        n3: Option[string]
        n4: Option[bool]

    var j0 = parseJson("""{"n1": 1, "n2": null, "n3": null, "n4": null}""")
    let j0Deser = j0.to(Obj)
    doAssert j0Deser.n1 == 1
    doAssert j0Deser.n2.isNone()
    doAssert j0Deser.n3.isNone()
    doAssert j0Deser.n4.isNone()

  # Table[T, Y] support.
  block:
    type
      Friend = object
        name: string
        age: int

      Dynamic = object
        name: string
        friends: Table[string, Friend]

    let data = """
      {"friends": {
                    "John": {"name": "John", "age": 35},
                    "Elizabeth": {"name": "Elizabeth", "age": 23}
                  }, "name": "Dominik"}
    """

    let dataParsed = parseJson(data)
    let dataDeser = to(dataParsed, Dynamic)
    doAssert dataDeser.name == "Dominik"
    doAssert dataDeser.friends["John"].age == 35
    doAssert dataDeser.friends["Elizabeth"].age == 23

  # JsonNode support
  block:
    type
      Test = object
        name: string
        fallback: JsonNode

    let data = """
      {"name": "FooBar", "fallback": 56.42}
    """

    let dataParsed = parseJson(data)
    let dataDeser = to(dataParsed, Test)
    doAssert dataDeser.name == "FooBar"
    doAssert dataDeser.fallback.kind == JFloat
    doAssert dataDeser.fallback.getFloat() == 56.42

  # int64, float64 etc support.
  block:
    type
      Test1 = object
        a: int8
        b: int16
        c: int32
        d: int64
        e: uint8
        f: uint16
        g: uint32
        h: uint64
        i: float32
        j: float64

    let data = """
      {"a": 1, "b": 2, "c": 3, "d": 4, "e": 5, "f": 6, "g": 7,
       "h": 8, "i": 9.9, "j": 10.10}
    """

    let dataParsed = parseJson(data)
    let dataDeser = to(dataParsed, Test1)
    doAssert dataDeser.a == 1
    doAssert dataDeser.f == 6
    doAssert dataDeser.i == 9.9'f32

  # deserialize directly into a table
  block:
    let s = """{"a": 1, "b": 2}"""
    let t = parseJson(s).to(Table[string, int])
    doAssert t["a"] == 1
    doAssert t["b"] == 2

  block:
    # bug #8037
    type
      Apple = distinct string
      String = distinct Apple
      Email = distinct string
      MyList = distinct seq[int]
      MyYear = distinct Option[int]
      MyTable = distinct Table[string, int]
      MyArr = distinct array[3, float]
      MyRef = ref object
        name: string
      MyObj = object
        color: int
      MyDistRef = distinct MyRef
      MyDistObj = distinct MyObj
      Toot = object
        name*: String
        email*: Email
        list: MyList
        year: MyYear
        dict: MyTable
        arr: MyArr
        person: MyDistRef
        distfruit: MyDistObj
        dog: MyRef
        fruit: MyObj
        emails: seq[String]

    var tJson = parseJson("""
      {
        "name":"Bongo",
        "email":"bongo@bingo.com",
        "list": [11,7,15],
        "year": 1975,
        "dict": {"a": 1, "b": 2},
        "arr": [1.0, 2.0, 7.0],
        "person": {"name": "boney"},
        "dog": {"name": "honey"},
        "fruit": {"color": 10},
        "distfruit": {"color": 11},
        "emails": ["abc", "123"]
      }
    """)

    var t = to(tJson, Toot)
    doAssert string(t.name) == "Bongo"
    doAssert string(t.email) == "bongo@bingo.com"
    doAssert seq[int](t.list) == @[11,7,15]
    doAssert Option[int](t.year).get() == 1975
    doAssert Table[string,int](t.dict)["a"] == 1
    doAssert Table[string,int](t.dict)["b"] == 2
    doAssert array[3, float](t.arr) == [1.0,2.0,7.0]

    doAssert MyRef(t.person).name == "boney"
    doAssert MyObj(t.distfruit).color == 11
    doAssert t.dog.name == "honey"
    doAssert t.fruit.color == 10
    doAssert seq[string](t.emails) == @["abc", "123"]

    block test_table:
      var y = parseJson("""{"a": 1, "b": 2, "c": 3}""")
      var u = y.to(MyTable)
      var v = y.to(Table[string, int])
      doAssert Table[string, int](u)["a"] == 1
      doAssert Table[string, int](u)["b"] == 2
      doAssert Table[string, int](u)["c"] == 3
      doAssert v["a"] == 1

    block primitive_string:
      const kApple = "apple"
      var u = newJString(kApple)
      var v = u.to(Email)
      var w = u.to(Apple)
      var x = u.to(String)
      doAssert string(v) == kApple
      doAssert string(w) == kApple
      doAssert string(x) == kApple

    block test_option:
      var u = newJInt(1137)
      var v = u.to(MyYear)
      var w = u.to(Option[int])
      doAssert Option[int](v).get() == 1137
      doAssert w.get() == 1137

    block test_object:
      var u = parseJson("""{"color": 987}""")
      var v = u.to(MyObj)
      var w = u.to(MyDistObj)
      doAssert v.color == 987
      doAssert MyObj(w).color == 987

    block test_ref_object:
      var u = parseJson("""{"name": "smith"}""")
      var v = u.to(MyRef)
      var w = u.to(MyDistRef)
      doAssert v.name == "smith"
      doAssert MyRef(w).name == "smith"

  block:
    # bug #12015
    type
      Cluster = object
        works: tuple[x, y: uint8, ch: uint16] # working
        fails: Pix # previously broken

    let data = (x: 123'u8, y: 53'u8, ch: 1231'u16)
    let c = Cluster(works: data, fails: data)
    let cFromJson = (% c).to(Cluster)
    doAssert c == cFromJson

  block:
    # bug related to #12015
    type
      PixInt = tuple[x, y, ch: int]
      SomePix = Pix | PixInt
      Cluster[T: SomePix] = seq[T]
      ClusterObject[T: SomePix] = object
        data: Cluster[T]
      RecoEvent[T: SomePix] = object
        cluster: seq[ClusterObject[T]]

    let data = @[(x: 123'u8, y: 53'u8, ch: 1231'u16)]
    var c = RecoEvent[Pix](cluster: @[ClusterObject[Pix](data: data)])
    let cFromJson = (% c).to(RecoEvent[Pix])
    doAssert c == cFromJson


  block:
    # ref objects with cycles.
    type
      Misdirection = object
        cycle: Cycle

      Cycle = ref object
        foo: string
        cycle: Misdirection

    let data = """
      {"cycle": null}
    """

    let dataParsed = parseJson(data)
    let dataDeser = to(dataParsed, Misdirection)

  block:
    # ref object from #12316
    type
      Foo = ref Bar
      Bar = object

    discard "null".parseJson.to Foo

  block:
    # named array #12289
    type Vec = array[2, int]
    let arr = "[1,2]".parseJson.to Vec
    doAssert arr == [1,2]

  block:
    # test error message in exception

    type
      MyType = object
        otherMember: string
        member: MySubType

      MySubType = object
        somethingElse: string
        list: seq[MyData]

      MyData = object
        value: int

    let jsonNode = parseJson("""
      {
        "otherMember": "otherValue",
        "member": {
          "somethingElse": "something",
          "list": [{"value": 1}, {"value": 2}, {}]
        }
      }
    """)

    try:
      let tmp = jsonNode.to(MyType)
      doAssert false, "this should be unreachable"
    except KeyError:
      doAssert getCurrentExceptionMsg().contains ".member.list[2].value"

  block:
    # Enum indexed array test
    type Test = enum
      one, two, three, four, five
    let a = [
      one: 300,
      two: 20,
      three: 10,
      four: 0,
      five: -10
    ]
    doAssert (%* a).to(a.typeof) == a


testJson()
static:
  testJson()

discard """
  matrix: "-d:nimPreviewRangeDefault --mm:refc; -d:nimPreviewRangeDefault --warningAsError:ProveInit --mm:orc"
  targets: "c cpp js"
"""

import std/[times, macros, tables]

type
  Guess = object
    poi: DateTime

  GuessDistinct = distinct Guess

block:
  var x: Guess
  discard Guess()

  var y: GuessDistinct

  discard y

  discard GuessDistinct(x)


import mobject_default_value

block:
  let x = Default()
  doAssert x.se == 0'i32

block:
  let x = default(Default)
  doAssert x.se == 0'i32
# echo Default(poi: 12)
# echo Default(poi: 17)

# echo NonDefault(poi: 77)

block:
  var x: Default
  doAssert x.se == 0'i32

type
  ObjectBase = object of RootObj
    value = 12

  ObjectBaseDistinct = distinct ObjectBase

  DinstinctInObject = object
    data: ObjectBaseDistinct

  Object = object of ObjectBase
    time: float = 1.2
    date: int
    scale: range[1..10]

  Object2 = object
    name: Object

  Object3 = object
    obj: Object2

  ObjectTuple = tuple
    base: ObjectBase
    typ: int
    obj: Object

  TupleInObject = object
    size = 777
    data: ObjectTuple

  Ref = ref object of ObjectBase

  RefInt = ref object of Ref
    data = 73

  Ref2 = ref object of ObjectBase

  RefInt2 = ref object of Ref
    data = 73

var t {.threadvar.}: Default
# var m1, m2 {.threadvar.}: Default

block:
  doAssert t.se == 0'i32

block: # ARC/ORC cannot bind destructors twice, so it cannot
      # be moved into main
  block:
    var x: Ref
    new(x)
    doAssert x.value == 12, "Ref.value = " & $x.value

    var y: RefInt
    new(y)
    doAssert y.value == 12
    doAssert y.data == 73

  block:
    var x: Ref2
    new(x, proc (x: Ref2) {.nimcall.} = discard "call Ref")
    doAssert x.value == 12, "Ref.value = " & $x.value

    proc call(x: RefInt2) =
      discard "call RefInt"

    var y: RefInt2
    new(y, call)
    doAssert y.value == 12
    doAssert y.data == 73

template main {.dirty.} =
  block: # bug #16744
    type
      R = range[1..10]
      Obj = object
        r: R

    var
      rVal: R = default(R) # Works fine
      objVal = default(Obj)

    doAssert rVal == 1
    doAssert objVal.r == 1

  block: # bug #16744
    type
      R = range[1..10]
      Obj = object
        r: R

    var
      rVal: R = default(R) # Works fine
      objVal = Obj()

    doAssert rVal == 1 # it should be 1
    doAssert objVal.r == 1

  block: # bug #3608
    type
      abc = ref object
        w: range[2..100]

    proc createABC(): abc =
      new(result)
      result.w = 20

    doAssert createABC().w == 20

  block:
    var x = new ObjectBase
    doAssert x.value == 12

    proc hello(): ref ObjectBase =
      new result

    let z = hello()
    doAssert z.value == 12

  block:
    var base = ObjectBase()
    var x: ObjectBaseDistinct = ObjectBaseDistinct(base)
    doAssert ObjectBase(x).value == 12
    let y = ObjectBaseDistinct(default(ObjectBase))
    doAssert ObjectBase(y).value == 12

    let m = ObjectBaseDistinct(ObjectBase())
    doAssert ObjectBase(m).value == 12

    proc hello(): ObjectBaseDistinct =
      result = ObjectBaseDistinct(default(ObjectBase))

    let z = hello()
    doAssert ObjectBase(z).value == 12

  block:
    var x: DinstinctInObject
    x.data = ObjectBaseDistinct(default(ObjectBase))

    doAssert ObjectBase(x.data).value == 12

  block:
    var x = Object()
    doAssert x.value == 12
    doAssert x.time == 1.2
    doAssert x.scale == 1

    let y = default(Object)
    doAssert y.value == 12
    doAssert y.time == 1.2
    doAssert y.scale == 1

    var x1, x2, x3 = default(Object)
    doAssert x1.value == 12
    doAssert x1.time == 1.2
    doAssert x1.scale == 1
    doAssert x2.value == 12
    doAssert x2.time == 1.2
    doAssert x2.scale == 1
    doAssert x3.value == 12
    doAssert x3.time == 1.2
    doAssert x3.scale == 1

  block:
    var x = new Object
    doAssert x[] == default(Object)

  block:
    var x = default(Object2)
    doAssert x.name.value == 12
    doAssert x.name.time == 1.2
    doAssert x.name.scale == 1

  block:
    let x = Object2()
    doAssert x.name.value == 12
    doAssert x.name.time == 1.2
    doAssert x.name.scale == 1

  block:
    var x: ref Object2
    new x
    doAssert x[] == default(Object2)

  block:
    var x = default(Object3)
    doAssert x.obj.name.value == 12
    doAssert x.obj.name.time == 1.2
    doAssert x.obj.name.scale == 1

  block:
    var x = Object3()
    doAssert x.obj.name.value == 12
    doAssert x.obj.name.time == 1.2
    doAssert x.obj.name.scale == 1

  when nimvm:
    # todo
    discard "fixme"
  else:
    when defined(gcArc) or defined(gcOrc):
      block: #seq
        var x = newSeq[Object](10)
        let y = x[0]
        doAssert y.value == 12
        doAssert y.time == 1.2
        doAssert y.scale == 1

      block:
        var x: seq[Object]
        setLen(x, 5)
        let y = x[^1]
        doAssert y.value == 12
        doAssert y.time == 1.2
        doAssert y.scale == 1

      block:
        var my = @[1, 2, 3, 4, 5]
        my.setLen(0)
        my.setLen(5)
        doAssert my == @[0, 0, 0, 0, 0]

      block:
        var my = "hello"
        my.setLen(0)
        my.setLen(5)
        doAssert $(@my) == """@['\x00', '\x00', '\x00', '\x00', '\x00']"""

  block: # array
    var x: array[10, Object] = default(array[10, Object])
    let y = x[0]
    doAssert y.value == 12
    doAssert y.time == 1.2
    doAssert y.scale == 1

  block: # array
    var x {.noinit.}: array[10, Object]
    discard x

  block: # tuple
    var x = default(ObjectTuple)
    doAssert x.base.value == 12
    doAssert x.typ == 0
    doAssert x.obj.time == 1.2
    doAssert x.obj.date == 0
    doAssert x.obj.scale == 1
    doAssert x.obj.value == 12

  block: # tuple in object
    var x = default(TupleInObject)
    doAssert x.data.base.value == 12
    doAssert x.data.typ == 0
    doAssert x.data.obj.time == 1.2
    doAssert x.data.obj.date == 0
    doAssert x.data.obj.scale == 1
    doAssert x.data.obj.value == 12
    doAssert x.size == 777

  type
    ObjectArray = object
      data: array[10, Object]

  block:
    var x = default(ObjectArray)
    let y = x.data[0]
    doAssert y.value == 12
    doAssert y.time == 1.2
    doAssert y.scale == 1

  block:
    var x: PrellDeque[int]
    doAssert x.pendingTasks == 0

  type
    Color = enum
      Red, Blue, Yellow

    ObjectVarint = object
      case kind: Color
      of Red:
        data: int = 10
      of Blue:
        fill = "123"
      of Yellow:
        time = 1.8'f32

    ObjectVarint1 = object
      case kind: Color = Blue
      of Red:
        data1: int = 10
      of Blue:
        fill2 = "123"
        cry: float
      of Yellow:
        time3 = 1.8'f32
        him: int

  block:
    var x = ObjectVarint(kind: Red)
    doAssert x.kind == Red
    doAssert x.data == 10

  block:
    var x = ObjectVarint(kind: Blue)
    doAssert x.kind == Blue
    doAssert x.fill == "123"

  block:
    var x = ObjectVarint(kind: Yellow)
    doAssert x.kind == Yellow
    doAssert typeof(x.time) is float32

  block:
    var x = default(ObjectVarint1)
    doAssert x.kind == Blue
    doAssert x.fill2 == "123"
    x.cry = 326

  type
    ObjectVarint2 = object
      case kind: Color
      of Red:
        data: int = 10
      of Blue:
        fill = "123"
      of Yellow:
        time = 1.8'f32

  block:
    var x = ObjectVarint2(kind: Blue)
    doAssert x.fill == "123"

  block:
    type
      Color = enum
        Red, Blue, Yellow
  
    type
      ObjectVarint3 = object
        case kind: Color = Blue
        of Red:
          data1: int = 10
        of Blue:
          case name: Color = Blue
          of Blue:
            go = 12
          else:
            temp = 66
          fill2 = "123"
          cry: float
        of Yellow:
          time3 = 1.8'f32
          him: int

    block:
      var x = default(ObjectVarint3)
      doAssert x.kind == Blue
      doAssert x.name == Blue
      doAssert x.go == 12

    block:
      var x = ObjectVarint3(kind: Blue, name: Red, temp: 99)
      doAssert x.kind == Blue
      doAssert x.name == Red
      doAssert x.temp == 99

  block:
    type
      Default = tuple
        id: int = 1
        obj: ObjectBase
        name: string

      Class = object
        def: Default

      Member = object
        def: Default = (id: 777, obj: ObjectBase(), name: "fine")

    block:
      var x = default(Default)
      doAssert x.id == 1
      doAssert x.obj == default(ObjectBase)
      doAssert x.name == ""

    block:
      var x = default(Class)
      doAssert x.def == default(Default)
      doAssert x.def.id == 1
      doAssert x.def.obj == default(ObjectBase)
      doAssert x.def.name == ""

    block:
      var x = default(Member)
      doAssert x.def.id == 777
      doAssert x.def.obj == default(ObjectBase)
      doAssert x.def.name == "fine"

  block:
    var x {.noinit.} = 12
    doAssert x == 12

    type
      Pure = object
        id: int = 12

    var y {.noinit.}: Pure
    doAssert y.id == 0

    var z {.noinit.}: Pure = Pure(id: 77)
    doAssert z.id == 77

  block: # bug #20681
    type A = object
      d: DateTime = DateTime()

    let x = default(A)
    doAssert $x == "(d: Uninitialized DateTime)"

  block: # bug #20715
    block:
      type
        Foo = enum
          A
          B

        Bar = object
          case foo: Foo
          of A:
            t: range[-1..2]
          else: discard

      var d = default(Bar)
      doAssert d.t == -1

    block:
      type
        Foo = enum
          A
          B

        Bar = object
          case foo: Foo
          of A:
            t: range[0..2]
          else: discard

      var d = default(Bar)
      doAssert d.t == 0

    block: # bug #20740
      block:
        proc foo(x: static DateTime = Datetime()) =
          discard

        foo()

      block:
        macro foo(x: static DateTime) =
          discard x

        macro foo2: untyped =
          var x = DateTime()

          result = quote do:
            foo(`x`)

        foo2()


  block: # issue #20699
    type
      Either[A,B] = object
        case kind:bool
        of false:
          b: B
        of true:
            a: A
      O = object of RootRef

    proc oToEither(o:O):Either[O,void] =
      Either[O,void](kind:true,a: o)

    discard oToEither(O())

  block: # bug #20695
    type
      Default = object
        tabs: Table[string, int] = initTable[string, int]()

    let d = default(Default)
    doAssert d.tabs.len == 0

  block:
    type
      Default = object
        tabs: Table[string, int] = Table[string, int]()

    let d = default(Default)
    doAssert d.tabs.len == 0


  block:
    type DjangoDateTime = distinct DateTime

    type Default = object
      data: DjangoDateTime = DjangoDateTime(DateTime())

    let x = default(Default)
    doAssert x.data is DjangoDateTime

  block:
    type DjangoDateTime = distinct DateTime

    type Default = object
      data = DjangoDateTime(DateTime())

    let x = default(Default)
    doAssert x.data is DjangoDateTime

  block:
    type
      Result2 = object
        case o: bool
        of false:
          e: float
        of true:
          v {.requiresInit.} : int = 1

    proc startSessionSync(): Result2 =
      return Result2(o: true)

    proc mainSync =
      let ff = startSessionSync()
      doAssert ff.v == 1

    mainSync()

  block:
    type
      Result2 = object
        v {.requiresInit.} : int = 1

    proc startSessionSync(): Result2 =
      return Result2()

    proc mainSync =
      let ff = startSessionSync()
      doAssert ff.v == 1

    mainSync()

  block: # bug #21801
    func evaluate(i: int): float =
      0.0

    func evaluate(): float =
      0.0

    type SearchOptions = object
        evaluation: proc(): float = evaluate

  block:
    func evaluate(): float =
      0.0

    type SearchOptions = object
        evaluation: proc(): float = evaluate

  block:
    func evaluate(i: int): float =
      0.0

    type SearchOptions = object
        evaluation = evaluate
  block:
    type
      Result[T, E] = object
        when T is void:
          when E is void:
            oResultPrivate: bool
          else:
            case oResultPrivate: bool
            of false:
              eResultPrivate: E
            of true:
              discard
        else:
          when E is void:
            case oResultPrivate: bool
            of false:
              discard
            of true:
              vResultPrivate: T
          else:
            case oResultPrivate: bool
            of false:
              eResultPrivate: E
            of true:
              vResultPrivate: T


    template `?`[T, E](self: Result[T, E]): auto =
      let v = (self)
      if not v.oResultPrivate:
        when compiles(`assignResult?`(default(typeof(result)))):
          when typeof(result) is typeof(v):
            `assignResult?`(v)
          elif E is void:
            `assignResult?`(err(typeof(result)))
          else:
            `assignResult?`(err(typeof(result), v.eResultPrivate))
          return
        else:
          return
            when typeof(result) is typeof(v):
              v
            elif E is void:
              err(typeof(result))
            else:
              err(typeof(result), v.eResultPrivate)

      when not(T is void):
        v.vResultPrivate
        
    type R = Result[int, string]

    proc testAssignResult() =
      var assigned: bool
      template `assignResult?`(v: Result) =
        assigned = true
        result = v

      proc failed(): Result[int, string] =
        discard

      proc calling(): Result[int, string] =
        let _ = ? failed()
        doAssert false

      let r = calling()
      doAssert assigned

    when nimvm:
      when not defined(js):
        testAssignResult()
    else:
      testAssignResult()

  block: # bug #22123
    type Thing = object
      x: float32 = 1

    type ThingWithArray = object
        arr: array[256, float32]
        n: float32 = 1

    type Container = ref object
        thing: array[5, Thing]
        thing_with_array: array[5, ThingWithArray]

    var foo = new Container
    doAssert int(foo.thing[0].x) == 1

  block: # bug #22613
    type
      K = enum
        A = "a"
        B = "b"
      T = object
        case kind: K = B
        of A:
          a: int
        of B:
          b: float

    doAssert T().kind == B

  block: # bug #22926
    type
      Direction = enum
        North
        South
        East
        West

      ArrayObj1 = object
        list: array[Direction, int]

      ArrayObj2 = object
        list: array[Direction, int] = [1, 2, 3, 4]

    block:
      var a: ArrayObj1
      doAssert a.list[West] == 0
      var b = default ArrayObj1
      doAssert b.list[North] == 0


    block:
      var a: ArrayObj2
      doAssert a.list[West] == 0
      var b = default ArrayObj2
      doAssert b.list[North] == 1

  block:
    type limited_float = range[1.2..20.0]
    doAssert default(limited_float) == 1.2


  block:
    type
      range1 = range[1..10]
      range2 = range[-1..10]

    proc foo =
      doAssert default(range1) == 1
      doAssert default(range2) == -1

      let s = default(array[5, range1])
      doAssert s == [range1 1, 1, 1, 1, 1]

    foo()

  block:
    type
      Object = object
        id: range[1.2..29.3]

    var s = default(Object)
    doAssert s.id == 1.2

  block: # bug #23943
    type limited_int = range[1..20]
    var d: limited_int;
    doAssert d == 1

  block: # bug #23545
    proc evaluate(params: int) =
        discard

    proc evaluate() =
        discard

    type SearchInfo = object
      evaluation: proc() = evaluate

    var a = SearchInfo()
    a.evaluation()

static: main()
main()

discard """
  matrix: "--mm:refc"
  output: '''Sortable
Sortable
Container
oof
111 111
(id: @[1, 2, 3], name: @["Vas", "Pas", "NafNaf"], age: @[10, 16, 18])
'''
"""

# todo wait for https://github.com/nim-lang/Nim/pull/20380

import typetraits

template reject(expr) = assert(not compiles(x))

type
  TObj = object
    x: int

  JSonValue = object
    val: string

  Sortable = concept x, y
    (x < y) is bool

  ObjectContainer = concept C
    C.len is Ordinal
    for v in items(C):
      v.type is tuple|object

proc foo(c: ObjectContainer) =
  echo "Container"

proc foo(x: Sortable) =
  echo "Sortable"

foo 10
foo "test"
foo(@[TObj(x: 10), TObj(x: 20)])

proc intval(x: int): int = 10

type
  TFoo = concept o, type T, ref r, var v, ptr p, static s
    o.x
    y(o) is int

    var str: string
    var intref: ref int

    refproc(ref T, ref int)
    varproc(var T)
    ptrproc(ptr T, str)

    staticproc(static[T])

    typeproc T
    T.typeproc
    typeproc o.type
    o.type.typeproc

    o.to(type string)
    o.to(type JsonValue)

    refproc(r, intref)
    varproc(v)
    p.ptrproc(string)
    staticproc s
    typeproc(T)

    const TypeName = T.name
    type MappedType = type(o.y)

    intval y(o)
    let z = intval(o.y)

    static:
      assert T.name.len == 4
      reject o.name
      reject o.typeproc
      reject staticproc(o)
      reject o.varproc
      reject T.staticproc
      reject p.staticproc

proc y(x: TObj): int = 10

proc varproc(x: var TObj) = discard
proc refproc(x: ref TObj, y: ref int) = discard
proc ptrproc(x: ptr TObj, y: string) = discard
proc staticproc(x: static[TObj]) = discard
proc typeproc(t: type TObj) = discard
proc to(x: TObj, t: type string) = discard
proc to(x: TObj, t: type JSonValue) = discard

proc testFoo(x: TFoo) =
  echo "oof"

testFoo(TObj(x: 10))

# bug #7092

type stringTest = concept x
  x is string

let usedToFail: stringTest = "111"
let working: string = "111"

echo usedToFail, " ", working

# bug #5868

type TaggedType[T; Key: static[string]] = T

proc setKey*[DT](dt: DT, key: static[string]): TaggedType[DT, key] =
  result = cast[type(result)](dt)

type Students = object
   id : seq[int]
   name : seq[string]
   age: seq[int]

let
  stud = Students(id : @[1,2,3], name : @["Vas", "Pas", "NafNaf"], age : @[10,16,18])
  stud2 = stud.setkey("id")

echo stud2

{.experimental: "notnil".}

import macros, asyncmacro, asyncfutures

block:
  template myAttr() {.pragma.}

  proc myProc():int {.myAttr.} = 2
  const hasMyAttr = myProc.hasCustomPragma(myAttr)
  static:
    doAssert(hasMyAttr)

block:
  template myAttr(a: string) {.pragma.}

  type
    MyObj = object
      myField1, myField2 {.myAttr: "hi".}: int

    MyGenericObj[T] = object
      myField1, myField2 {.myAttr: "hi".}: int

    MyOtherObj = MyObj


  var o: MyObj
  static:
    doAssert o.myField2.hasCustomPragma(myAttr)
    doAssert(not o.myField1.hasCustomPragma(myAttr))
    doAssert(not o.myField1.hasCustomPragma(MyObj))
    doAssert(not o.myField1.hasCustomPragma(MyOtherObj))

  var ogen: MyGenericObj[int]
  static:
    doAssert ogen.myField2.hasCustomPragma(myAttr)
    doAssert(not ogen.myField1.hasCustomPragma(myAttr))
    doAssert(not ogen.myField1.hasCustomPragma(MyGenericObj))
    doAssert(not ogen.myField1.hasCustomPragma(MyGenericObj))


import custom_pragma
block: # A bit more advanced case
  type
    Subfield {.defaultValue: "catman".} = object
      `c`* {.serializationKey: "cc".}: float

    MySerializable = object
      a {.serializationKey"asdf", defaultValue: 5.} : int
      b {.custom_pragma.defaultValue"hello".} : int
      field: Subfield
      d {.alternativeKey("df", 5).}: float
      e {.alternativeKey(V = 5).}: seq[bool]

  proc myproc(x: int, s: string) {.alternativeKey(V = 5), serializationKey"myprocSS".} =
    echo x, s


  var s: MySerializable

  const aDefVal = s.a.getCustomPragmaVal(defaultValue)
  static: doAssert(aDefVal == 5)

  const aSerKey = s.a.getCustomPragmaVal(serializationKey)
  static: doAssert(aSerKey == "asdf")

  const cSerKey = getCustomPragmaVal(s.field.c, serializationKey)
  static: doAssert(cSerKey == "cc")

  const procSerKey = getCustomPragmaVal(myproc, serializationKey)
  static: doAssert(procSerKey == "myprocSS")

  static: doAssert(hasCustomPragma(myproc, alternativeKey))

  const hasFieldCustomPragma = s.field.hasCustomPragma(defaultValue)
  static: doAssert(hasFieldCustomPragma == false)

  # pragma on an object
  static:
    doAssert Subfield.hasCustomPragma(defaultValue)
    doAssert(Subfield.getCustomPragmaVal(defaultValue) == "catman")

    doAssert hasCustomPragma(type(s.field), defaultValue)

  proc foo(s: var MySerializable) =
    static: doAssert(s.a.getCustomPragmaVal(defaultValue) == 5)

  foo(s)

block: # ref types
  type
    Node = object of RootObj
      left {.serializationKey:"l".}, right {.serializationKey:"r".}: NodeRef
    NodeRef = ref Node
    NodePtr = ptr Node

    SpecialNodeRef = ref object of NodeRef
      data {.defaultValue"none".}: string

    MyFile {.defaultValue: "closed".} = ref object
      path {.defaultValue: "invalid".}: string

    TypeWithoutPragma = object

  var s = NodeRef()

  const
    leftSerKey = getCustomPragmaVal(s.left, serializationKey)
    rightSerKey = getCustomPragmaVal(s.right, serializationKey)
  static:
    doAssert leftSerKey == "l"
    doAssert rightSerKey == "r"

  var specS = SpecialNodeRef()

  const
    dataDefVal = hasCustomPragma(specS.data, defaultValue)
    specLeftSerKey = hasCustomPragma(specS.left, serializationKey)
  static:
    doAssert dataDefVal == true
    doAssert specLeftSerKey == true

  var ptrS = NodePtr(nil)
  const
    ptrRightSerKey = getCustomPragmaVal(ptrS.right, serializationKey)
  static:
    doAssert ptrRightSerKey == "r"

  var f = MyFile()
  const
    fileDefVal = f.getCustomPragmaVal(defaultValue)
    filePathDefVal = f.path.getCustomPragmaVal(defaultValue)
  static:
    doAssert fileDefVal == "closed"
    doAssert filePathDefVal == "invalid"

  static:
    doAssert TypeWithoutPragma.hasCustomPragma(defaultValue) == false

block:
  type
    VariantKind = enum
      variInt,
      variFloat
      variString
      variNestedCase
    Variant = object
      case kind: VariantKind
      of variInt: integer {.serializationKey: "int".}: BiggestInt
      of variFloat: floatp: BiggestFloat
      of variString: str {.serializationKey: "string".}: string
      of variNestedCase:
        case nestedKind: VariantKind
        of variInt..variNestedCase: nestedItem {.defaultValue: "Nimmers of the world, unite!".}: int

  let vari = Variant(kind: variInt)

  const
    hasIntSerKey = vari.integer.hasCustomPragma(serializationKey)
    strSerKey = vari.str.getCustomPragmaVal(serializationKey)
    nestedItemDefVal = vari.nestedItem.getCustomPragmaVal(defaultValue)

  static:
    doAssert hasIntSerKey
    doAssert strSerKey == "string"
    doAssert nestedItemDefVal == "Nimmers of the world, unite!"

block:
  template simpleAttr {.pragma.}

  type Annotated {.simpleAttr.} = object

  proc generic_proc[T]() =
    doAssert Annotated.hasCustomPragma(simpleAttr)

#--------------------------------------------------------------------------
# Pragma on proc type

type
  MyAnnotatedProcType {.defaultValue(4).} = proc(x: int)

let a {.defaultValue(4).}: proc(x: int)  = nil
var b: MyAnnotatedProcType = nil
var c: proc(x: int): void {.defaultValue(5).}  = nil
var d {.defaultValue(44).}: MyAnnotatedProcType = nil
static:
  doAssert hasCustomPragma(a, defaultValue)
  doAssert hasCustomPragma(MyAnnotatedProcType, defaultValue)
  doAssert hasCustomPragma(b, defaultValue)
  doAssert hasCustomPragma(typeof(c), defaultValue)
  doAssert getCustomPragmaVal(d, defaultValue) == 44
  doAssert getCustomPragmaVal(typeof(d), defaultValue) == 4

# bug #8371
template thingy {.pragma.}

type
  Cardinal = enum
    north, east, south, west
  Something = object
    a: float32
    case cardinal: Cardinal
    of north:
      b {.thingy.}: int
    of east:
      c: int
    of south: discard
    else: discard

var foo: Something
foo.cardinal = north
doAssert foo.b.hasCustomPragma(thingy) == true

proc myproc(s: string): int =
  {.thingy.}:
    s.len

doAssert myproc("123") == 3

let xx = compiles:
  proc myproc_bad(s: string): int =
    {.not_exist.}:
      s.len
doAssert: xx == false

macro checkSym(s: typed{nkSym}): untyped =
  let body = s.getImpl.body
  doAssert body[1].kind == nnkPragmaBlock
  doAssert body[1][0].kind == nnkPragma
  doAssert body[1][0][0] == bindSym"thingy"

checkSym(myproc)

# var and let pragmas
block:
  template myAttr() {.pragma.}
  template myAttr2(x: int) {.pragma.}
  template myAttr3(x: string) {.pragma.}

  type
    MyObj2 = ref object
    MyObjNotNil = MyObj2 not nil

  let a {.myAttr,myAttr2(2),myAttr3:"test".}: int = 0
  let b {.myAttr,myAttr2(2),myAttr3:"test".} = 0
  var x {.myAttr,myAttr2(2),myAttr3:"test".}: int = 0
  var y {.myAttr,myAttr2(2),myAttr3:"test".}: int
  var z {.myAttr,myAttr2(2),myAttr3:"test".} = 0
  var z2 {.myAttr.}: MyObjNotNil

  template check(s: untyped) =
    doAssert s.hasCustomPragma(myAttr)
    doAssert s.hasCustomPragma(myAttr2)
    doAssert s.getCustomPragmaVal(myAttr2) == 2
    doAssert s.hasCustomPragma(myAttr3)
    doAssert s.getCustomPragmaVal(myAttr3) == "test"

  check(a)
  check(b)
  check(x)
  check(y)
  check(z)

# pragma with multiple fields
block:
  template myAttr(first: string, second: int, third: float) {.pragma.}
  let a {.myAttr("one", 2, 3.0).} = 0
  let ps = a.getCustomPragmaVal(myAttr)
  doAssert ps.first == ps[0] and ps.first == "one"
  doAssert ps.second == ps[1] and ps.second == 2
  doAssert ps.third == ps[2] and ps.third == 3.0

# pragma with implicit&explicit generic types
block:
  template fooBar[T](x: T; c: static[int] = 42; m: char) {.pragma.}
  var e {.fooBar("foo", 123, 'u').}: int
  doAssert(hasCustomPragma(e, fooBar))
  doAssert(getCustomPragmaVal(e, fooBar).c == 123)

block:
  macro expectedAst(expectedRepr: static[string], input: untyped): untyped =
    doAssert input.treeRepr & "\n" == expectedRepr
    return input

  macro expectedAstRepr(expectedRepr: static[string], input: untyped): untyped =
    doAssert input.repr == expectedRepr
    return input

  const procTypeAst = """
ProcTy
  FormalParams
    Empty
    IdentDefs
      Ident "x"
      Ident "int"
      Empty
  Pragma
    Ident "async"
"""

  type
    Foo = proc (x: int) {.expectedAst(procTypeAst), async.}

  static: doAssert Foo is proc(x: int): Future[void]

  const asyncProcTypeAst = """
proc (s: string): Future[void] {..}"""
  # using expectedAst would show `OpenSymChoice` for Future[void], which is fragile.
  type
    Bar = proc (s: string) {.async, expectedAstRepr(asyncProcTypeAst).}

  static: doAssert Bar is proc(x: string): Future[void]

  const typeAst = """
TypeDef
  PragmaExpr
    Ident "Baz"
    Pragma
  Empty
  ObjectTy
    Empty
    Empty
    RecList
      IdentDefs
        Ident "x"
        Ident "string"
        Empty
"""

  type
    Baz {.expectedAst(typeAst).} = object
      x: string

  static: doAssert Baz.x is string

  const procAst = """
ProcDef
  Ident "bar"
  Empty
  Empty
  FormalParams
    Ident "string"
    IdentDefs
      Ident "s"
      Ident "string"
      Empty
  Empty
  Empty
  StmtList
    ReturnStmt
      Ident "s"
"""

  proc bar(s: string): string {.expectedAst(procAst).} =
    return s

  static: doAssert bar("x") == "x"

#------------------------------------------------------
# bug #13909

template dependency*(id: string, weight = 0.0) {.pragma.}

type
  MyObject* = object
    provider*: proc(obj: string): pointer {.dependency("Data/" & obj, 16.1), noSideEffect.}

proc myproc(obj: string): string {.dependency("Data/" & obj, 16.1).} =
  result = obj

# bug 12523
template myCustomPragma {.pragma.}

type
  RefType = ref object
    field {.myCustomPragma.}: int

  ObjType = object
    field {.myCustomPragma.}: int
  RefType2 = ref ObjType

block:
  let x = RefType()
  for fieldName, fieldSym in fieldPairs(x[]):
    doAssert hasCustomPragma(fieldSym, myCustomPragma)

block:
  let x = RefType2()
  for fieldName, fieldSym in fieldPairs(x[]):
    doAssert hasCustomPragma(fieldSym, myCustomPragma)

# bug 8457
block:
  template world {.pragma.}

  type
    Hello = ref object
      a: float32
      b {.world.}: int

  discard Hello(a: 1.0, b: 12)

# test routines
block:
  template prag {.pragma.}
  proc hello {.prag.} = discard
  iterator hello2: int {.prag.} = discard
  template hello3(x: int): int {.prag.} = x
  macro hello4(x: int): int {.prag.} = x
  func hello5(x: int): int {.prag.} = x
  doAssert hello.hasCustomPragma(prag)
  doAssert hello2.hasCustomPragma(prag)
  doAssert hello3.hasCustomPragma(prag)
  doAssert hello4.hasCustomPragma(prag)
  doAssert hello5.hasCustomPragma(prag)

# test push doesn't break
block:
  template prag {.pragma.}
  {.push prag.}
  proc hello = discard
  iterator hello2: int = discard
  template hello3(x: int): int = x
  macro hello4(x: int): int = x
  func hello5(x: int): int = x
  type
    Foo = enum a
    Bar[T] = ref object of RootObj
      x: T
      case y: bool
      of false: discard
      else:
        when true: discard
  for a in [1]: discard a
  {.pop.}

# issue #11511
when false:
  template myAttr {.pragma.}

  type TObj = object
      a {.myAttr.}: int

  macro hasMyAttr(t: typedesc): untyped =
    let objTy = t.getType[1].getType
    let recList = objTy[2]
    let sym = recList[0]
    assert sym.kind == nnkSym and sym.eqIdent("a")
    let hasAttr = sym.hasCustomPragma(myAttr)
    newLit(hasAttr)

  doAssert hasMyAttr(TObj)


# bug #11415
template noserialize() {.pragma.}

type
  Point[T] = object
    x, y: T

  ReplayEventKind = enum
    FoodAppeared, FoodEaten, DirectionChanged

  ReplayEvent = object
    case kind: ReplayEventKind
    of FoodEaten, FoodAppeared: # foodPos is in multiple branches
      foodPos {.noserialize.}: Point[float]
    of DirectionChanged:
      playerPos: float
let ev = ReplayEvent(
    kind: FoodEaten,
    foodPos: Point[float](x: 5.0, y: 1.0)
  )

doAssert ev.foodPos.hasCustomPragma(noserialize)


when false:
  # misc
  {.pragma: haha.}
  {.pragma: hoho.}
  template hehe(key, val: string, haha) {.pragma.}

  type A {.haha, hoho, haha, hehe("hi", "hu", "he").} = int

  assert A.getCustomPragmaVal(hehe) == (key: "hi", val: "hu", haha: "he")

  template hehe(key, val: int) {.pragma.}

  var bb {.haha, hoho, hehe(1, 2), haha, hehe("hi", "hu", "he").} = 3

  # left-to-right priority/override order for getCustomPragmaVal
  assert bb.getCustomPragmaVal(hehe) == (key: "hi", val: "hu", haha: "he")

{.experimental: "dynamicBindSym".}

# const
block:
  template myAttr() {.pragma.}
  template myAttr2(x: int) {.pragma.}
  template myAttr3(x: string) {.pragma.}

  type
    MyObj2 = ref object

  const a {.myAttr,myAttr2(2),myAttr3:"test".}: int = 0
  const b {.myAttr,myAttr2(2),myAttr3:"test".} = 0

  macro forceHasCustomPragma(x: untyped, y: typed): untyped =
    var x = bindSym(x.repr)
    for c in x:
      if c.symKind == nskConst:
        x = c
        break
    result = getAst(hasCustomPragma(x, y))

  macro forceGetCustomPragmaVal(x: untyped, y: typed): untyped =
    var x = bindSym(x.repr)
    for c in x:
      if c.symKind == nskConst:
        x = c
        break
    result = getAst(getCustomPragmaVal(x, y))

  template check(s: untyped) =
    doAssert forceHasCustomPragma(s, myAttr)
    doAssert forceHasCustomPragma(s, myAttr2)
    doAssert forceGetCustomPragmaVal(s, myAttr2) == 2
    doAssert forceHasCustomPragma(s, myAttr3)
    doAssert forceGetCustomPragmaVal(s, myAttr3) == "test"

  check(a)
  check(b)

block: # https://forum.nim-lang.org/t/12522, backticks
  template `mypragma`() {.pragma.}
  # Error: invalid pragma: `mypragma`
  type Test = object
    field {.`mypragma`.}: int
  doAssert Test().field.hasCustomPragma(mypragma)

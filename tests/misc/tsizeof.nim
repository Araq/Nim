discard """
  targets: "c cpp"
  output: '''
body executed
body executed
OK
macros api OK
'''
"""

# This is for Azure. The keyword ``alignof`` only exists in ``c++11``
# and newer. On Azure gcc does not default to c++11 yet.
when defined(cpp) and not defined(windows):
  {.passC: "-std=c++11".}

# Object offsets are different for inheritance objects when compiling
# to c++.

type
  TMyEnum = enum
    tmOne, tmTwo, tmThree, tmFour

  TMyArray1 = array[3, uint8]
  TMyArray2 = array[1..3, int32]
  TMyArray3 = array[TMyEnum, float64]

var failed = false

const
  mysize1 = sizeof(TMyArray1)
  mysize2 = sizeof(TMyArray2)
  mysize3 = sizeof(TMyArray3)

doAssert mysize1 == 3
doAssert mysize2 == 12
doAssert mysize3 == 32

import macros, typetraits

macro testSizeAlignOf(args: varargs[untyped]): untyped =
  result = newStmtList()
  for arg in args:
    result.add quote do:
      let
        c_size = c_sizeof(`arg`)
        nim_size = sizeof(`arg`)
        c_align = c_alignof(type(`arg`))
        nim_align = alignof(`arg`)

      if nim_size != c_size or nim_align != c_align:
        var msg = strAlign(`arg`.type.name & ": ")
        if nim_size != c_size:
          msg.add  " size(got, expected):  " & $nim_size & " != " & $c_size
        if nim_align != c_align:
          msg.add  " align(get, expected): " & $nim_align & " != " & $c_align
        echo msg
        failed = true


macro testOffsetOf(a, b: untyped): untyped =
  let typeName = newLit(a.repr)
  let member   = newLit(b.repr)
  result = quote do:
    let
      c_offset   = c_offsetof(`a`,`b`)
      nim_offset = offsetof(`a`,`b`)
    if c_offset != nim_offset:
      echo `typeName`, ".", `member`, " offsetError, C: ", c_offset, " nim: ", nim_offset
      failed = true

proc strAlign(arg: string): string =
  const minLen = 22
  result = arg
  for i in 0 ..< minLen - arg.len:
    result &= ' '

macro c_offsetof(fieldAccess: typed): int32 =
  ## Bullet proof implementation that works on actual offsetof operator
  ## in the c backend. Assuming of course this implementation is
  ## correct.
  let s = if fieldAccess.kind == nnkCheckedFieldExpr: fieldAccess[0]
          else: fieldAccess
  let a = s[0].getTypeInst
  let b = s[1]
  result = quote do:
    var res: int32
    {.emit: [res, " = offsetof(", `a`, ", ", `b`, ");"] .}
    res

template c_offsetof(t: typedesc, a: untyped): int32 =
  var x: ptr t
  c_offsetof(x[].a)

macro c_sizeof(a: typed): int32 =
  ## Bullet proof implementation that works using the sizeof operator
  ## in the c backend. Assuming of course this implementation is
  ## correct.
  result = quote do:
    var res: int32
    {.emit: [res, " = sizeof(", `a`, ");"] .}
    res

macro c_alignof(arg: untyped): untyped =
  ## Bullet proof implementation that works on actual alignment
  ## behavior measured at runtime.
  let typeSym = genSym(nskType, "AlignTestType"&arg.repr)
  result = quote do:
    type
      `typeSym` = object
        causeAlign: byte
        member: `arg`
    c_offsetof(`typeSym`, member)

macro testAlign(arg:untyped):untyped =
  let prefix = newLit(arg.lineinfo & "  alignof " & arg.repr & " ")
  result = quote do:
    let cAlign = c_alignof(`arg`)
    let nimAlign = alignof(`arg`)
    if cAlign != nimAlign:
      echo `prefix`, cAlign, " != ", nimAlign
      failed = true

macro testSize(arg:untyped):untyped =
  let prefix = newLit(arg.lineinfo & "  sizeof " & arg.repr & " ")
  result = quote do:
    let cSize = c_sizeof(`arg`)
    let nimSize = sizeof(`arg`)
    if cSize != nimSize:
      echo `prefix`, cSize, " != ", nimSize
      failed = true

type
  MyEnum {.pure.} = enum
    ValueA
    ValueB
    ValueC

  OtherEnum {.pure, size: 8.} = enum
    ValueA
    ValueB

  Enum1 {.pure, size: 1.} = enum
    ValueA
    ValueB

  Enum2 {.pure, size: 2.} = enum
    ValueA
    ValueB

  Enum4 {.pure, size: 4.} = enum
    ValueA
    ValueB

  Enum8 {.pure, size: 8.} = enum
    ValueA
    ValueB

  # Must have more than 32 elements so that set[MyEnum33] will become compile to an int64.
  MyEnum33 {.pure.} = enum
    Value1, Value2, Value3, Value4, Value5, Value6,
    Value7, Value8, Value9, Value10, Value11, Value12,
    Value13, Value14, Value15, Value16, Value17, Value18,
    Value19, Value20, Value21, Value22, Value23, Value24,
    Value25, Value26, Value27, Value28, Value29, Value30,
    Value31, Value32, Value33

proc transformObjectconfigPacked(arg: NimNode): NimNode =
  let debug = arg.kind == nnkPragmaExpr

  if arg.eqIdent("objectconfig"):
    result = ident"packed"
  else:
    result = copyNimNode(arg)
    for child in arg:
      result.add transformObjectconfigPacked(child)

proc removeObjectconfig(arg: NimNode): NimNode =
  if arg.kind == nnkPragmaExpr and arg[1][0].eqIdent "objectconfig":
    result = arg[0]
  else:
    result = copyNimNode(arg)
    for child in arg:
      result.add removeObjectconfig(child)

macro testinstance(body: untyped): untyped =
  let bodyPure = removeObjectconfig(body)
  let bodyPacked = transformObjectconfigPacked(body)

  result = quote do:
    proc pureblock(): void =
      const usePacked {.inject.} = false
      `bodyPure`

    pureblock()

    proc packedblock(): void =
      const usePacked {.inject.} = true
      `bodyPacked`

    packedblock()

proc testPrimitiveTypes(): void =
  testAlign(pointer)
  testAlign(int)
  testAlign(uint)
  testAlign(int8)
  testAlign(int16)
  testAlign(int32)
  testAlign(int64)
  testAlign(uint8)
  testAlign(uint16)
  testAlign(uint32)
  testAlign(uint64)
  testAlign(float)
  testAlign(float32)
  testAlign(float64)

  testAlign(MyEnum)
  testAlign(OtherEnum)
  testAlign(Enum1)
  testAlign(Enum2)
  testAlign(Enum4)
  testAlign(Enum8)

testPrimitiveTypes()

testinstance:
  type

    EnumObjectA  {.objectconfig.} = object
      a : Enum1
      b : Enum2
      c : Enum4
      d : Enum8

    EnumObjectB  {.objectconfig.} = object
      a : Enum8
      b : Enum4
      c : Enum2
      d : Enum1

    TrivialType  {.objectconfig.} = object
      x,y,z: int8

    SimpleAlignment {.objectconfig.} = object
      # behaves differently on 32bit Windows and 32bit Linux
      a,b: int8
      c: int64

    AlignAtEnd {.objectconfig.} = object
      a: int64
      b,c: int8

    SimpleBranch {.objectconfig.} = object
      case kind: MyEnum
      of MyEnum.ValueA:
        a: int16
      of MyEnum.ValueB:
        b: int32
      of MyEnum.ValueC:
        c: int64

    PaddingBeforeBranchA {.objectconfig.} = object
      cause: int8
      case kind: MyEnum
      of MyEnum.ValueA:
        a: int16
      of MyEnum.ValueB:
        b: int32
      of MyEnum.ValueC:
        c: int64

    PaddingBeforeBranchB {.objectconfig.} = object
      cause: int8
      case kind: MyEnum
      of MyEnum.ValueA:
        a: int8
      of MyEnum.ValueB:
        b: int16
      of MyEnum.ValueC:
        c: int32

    PaddingAfterBranch {.objectconfig.} = object
      case kind: MyEnum
      of MyEnum.ValueA:
        a: int8
      of MyEnum.ValueB:
        b: int16
      of MyEnum.ValueC:
        c: int32
      cause: int64

    RecursiveStuff {.objectconfig.} = object
      case kind: MyEnum    # packedOffset:    0
      of MyEnum.ValueA:    # packedOffset:
        a: int16           # packedOffset:    1
      of MyEnum.ValueB:    # packedOffset:
        b: int32           # packedOffset:    1
      of MyEnum.ValueC:    # packedOffset:
        case kind2: MyEnum # packedOffset:    1
        of MyEnum.ValueA:  # packedOffset:
          ca1: int8
          ca2: int32
        of MyEnum.ValueB:  # packedOffset:
          cb: int32        # packedOffset:    2
        of MyEnum.ValueC:  # packedOffset:
          cc: int64        # packedOffset:    2
        d1: int8
        d2: int64

    Foobar {.objectconfig.} = object
      case kind: OtherEnum
      of OtherEnum.ValueA:
        a: uint8
      of OtherEnum.ValueB:
        b: int8
      c: int8

    PaddingOfSetEnum33 {.objectconfig.} = object
      cause: int8
      theSet: set[MyEnum33]

    Bazing {.objectconfig.} = object of RootObj
      a: int64
      # TODO test on 32 bit system
      # only there the object header is smaller than the first member

    InheritanceA {.objectconfig.} = object of RootObj
      a: char

    InheritanceB {.objectconfig.} = object of InheritanceA
      b: char

    InheritanceC {.objectconfig.} = object of InheritanceB
      c: char

    # from issue 4763
    GenericObject[T] {.objectconfig.} = object
      a: int32
      b: T

    # this type mixes `packed` with `align`.
    MyCustomAlignPackedObject {.objectconfig.} = object
      a: char
      b {.align: 32.}: int32 # align overrides `packed` for this field.
      c: char
      d: int32  # unaligned

    Kind = enum
      K1, K2
  
    AnotherEnum = enum
      X1, X2, X3

    MyObject = object
      s: string
      case k: Kind
      of K1: nil
      of K2:
          x: float
          y: int32
      z: AnotherEnum

    Stack[N: static int, T: object] = object
      pad: array[128 - sizeof(array[N, ptr T]) - sizeof(int) - sizeof(pointer), byte]
      stack: array[N, ptr T]
      len*: int
      rawMem: ptr array[N, T]

    Stack2[T: object] = object
      pad: array[128 - sizeof(array[sizeof(T), ptr T]), byte]
    

  const trivialSize = sizeof(TrivialType) # needs to be able to evaluate at compile time

  proc main(): void =
    var t : TrivialType
    var a : SimpleAlignment
    var b : AlignAtEnd
    var c : SimpleBranch
    var d : PaddingBeforeBranchA
    var e : PaddingBeforeBranchB
    var f : PaddingAfterBranch
    var g : RecursiveStuff
    var ro : RootObj
    var go : GenericObject[int64]
    var po : PaddingOfSetEnum33
    var capo: MyCustomAlignPackedObject
    var issue15516: MyObject
    var issue12636_1: Stack[5, MyObject]
    var issue12636_2: Stack2[MyObject]

    var
      e1: Enum1
      e2: Enum2
      e4: Enum4
      e8: Enum8
    var
      eoa: EnumObjectA
      eob: EnumObjectB

    testAlign(SimpleAlignment)

    # sanity check to ensure both branches are actually executed
    when usePacked:
      doAssert sizeof(SimpleAlignment) == 10
    else:
      doAssert sizeof(SimpleAlignment) > 10

    testSizeAlignOf(t,a,b,c,d,e,f,g,ro,go,po, e1, e2, e4, e8, eoa, eob, capo, issue15516, issue12636_1, issue12636_2)

    type
      WithBitsize {.objectconfig.} = object
        bitfieldA {.bitsize: 16.}: uint32
        bitfieldB {.bitsize: 16.}: uint32

    var wbs: WithBitsize
    testSize(wbs)

    testOffsetOf(TrivialType, x)
    testOffsetOf(TrivialType, y)
    testOffsetOf(TrivialType, z)

    testOffsetOf(SimpleAlignment, a)
    testOffsetOf(SimpleAlignment, b)
    testOffsetOf(SimpleAlignment, c)

    testOffsetOf(AlignAtEnd, a)
    testOffsetOf(AlignAtEnd, b)
    testOffsetOf(AlignAtEnd, c)

    testOffsetOf(SimpleBranch, a)
    testOffsetOf(SimpleBranch, b)
    testOffsetOf(SimpleBranch, c)

    testOffsetOf(PaddingBeforeBranchA, cause)
    testOffsetOf(PaddingBeforeBranchA, a)
    testOffsetOf(PaddingBeforeBranchB, cause)
    testOffsetOf(PaddingBeforeBranchB, a)

    testOffsetOf(PaddingAfterBranch, a)
    testOffsetOf(PaddingAfterBranch, cause)

    testOffsetOf(Foobar, c)

    testOffsetOf(PaddingOfSetEnum33, cause)
    testOffsetOf(PaddingOfSetEnum33, theSet)

    testOffsetOf(Bazing, a)
    testOffsetOf(InheritanceA, a)
    testOffsetOf(InheritanceB, b)
    testOffsetOf(InheritanceC, c)

    testOffsetOf(EnumObjectA, a)
    testOffsetOf(EnumObjectA, b)
    testOffsetOf(EnumObjectA, c)
    testOffsetOf(EnumObjectA, d)
    testOffsetOf(EnumObjectB, a)
    testOffsetOf(EnumObjectB, b)
    testOffsetOf(EnumObjectB, c)
    testOffsetOf(EnumObjectB, d)

    testOffsetOf(RecursiveStuff, kind)
    testOffsetOf(RecursiveStuff, a)
    testOffsetOf(RecursiveStuff, b)
    testOffsetOf(RecursiveStuff, kind2)
    testOffsetOf(RecursiveStuff, ca1)
    testOffsetOf(RecursiveStuff, ca2)
    testOffsetOf(RecursiveStuff, cb)
    testOffsetOf(RecursiveStuff, cc)
    testOffsetOf(RecursiveStuff, d1)
    testOffsetOf(RecursiveStuff, d2)

    testOffsetOf(MyCustomAlignPackedObject, a)
    testOffsetOf(MyCustomAlignPackedObject, b)
    testOffsetOf(MyCustomAlignPackedObject, c)
    testOffsetOf(MyCustomAlignPackedObject, d)

    echo "body executed" # sanity check to ensure this logic isn't skipped entirely


  main()

{.emit: """/*TYPESECTION*/
typedef struct{
  float a; float b;
} Foo;
""".}

type
  Foo {.importc.} = object

  Bar = object
    b: byte
    foo: Foo

assert sizeof(Bar) == 12

# bug #10082
type
  A = int8        # change to int16 and get sizeof(C)==6
  B = int16
  C {.packed.} = object
    d {.bitsize:  1.}: A
    e {.bitsize:  7.}: A
    f {.bitsize: 16.}: B

assert sizeof(C) == 3


type
  MixedBitsize {.packed.} = object
    a: uint32
    b {.bitsize:  8.}: uint8
    c {.bitsize:  1.}: uint8
    d {.bitsize:  7.}: uint8
    e {.bitsize: 16.}: uint16
    f: uint32

doAssert sizeof(MixedBitsize) == 12


type
  MyUnionType {.union.} = object
    a: int32
    b: float32

  MyCustomAlignUnion {.union.} = object
    c: char
    a {.align: 32.}: int

  MyCustomAlignObject = object
    c: char
    a {.align: 32.}: int

doAssert sizeof(MyUnionType) == 4
doAssert sizeof(MyCustomAlignUnion) == 32
doAssert alignof(MyCustomAlignUnion) == 32
doAssert sizeof(MyCustomAlignObject) == 64
doAssert alignof(MyCustomAlignObject) == 32






##########################################
# bug #9794
##########################################

type
  imported_double {.importc: "double".} = object

  Pod = object
    v* : imported_double
    seed*: int32

  Pod2 = tuple[v: imported_double, seed: int32]

proc foobar() =
  testAlign(Pod)
  testSize(Pod)
  testAlign(Pod2)
  testSize(Pod2)
  doAssert sizeof(Pod) == sizeof(Pod2)
  doAssert alignof(Pod) == alignof(Pod2)
foobar()

if failed:
  quit("FAIL")
else:
  echo "OK"

##########################################
# sizeof macros API
##########################################

import macros

type
  Vec2f = object
    x,y: float32

  Vec4f = object
    x,y,z,w: float32

  # this type is constructed to have no platform depended alignment.
  ParticleDataA = object
    pos, vel: Vec2f
    birthday: float32
    padding: float32
    moreStuff: Vec4f

const expected = [
  # name size align offset
  ("pos", 8, 4, 0),
  ("vel", 8, 4, 8),
  ("birthday", 4, 4, 16),
  ("padding", 4, 4, 20),
  ("moreStuff", 16, 4, 24)
]

macro typeProcessing(arg: typed): untyped =
  let recList = arg.getTypeImpl[2]
  recList.expectKind nnkRecList
  for i, identDefs in recList:
    identDefs.expectKind nnkIdentDefs
    identDefs.expectLen 3
    let sym = identDefs[0]
    sym.expectKind nnkSym
    doAssert expected[i][0] == sym.strVal
    doAssert expected[i][1] == getSize(sym)
    doAssert expected[i][2] == getAlign(sym)
    doAssert expected[i][3] == getOffset(sym)

  result = newCall(bindSym"echo", newLit("macros api OK"))

proc main() =
  var mylocal: ParticleDataA
  typeProcessing(mylocal)

main()

# issue #11320 use UncheckedArray

type
  Payload = object
    something: int8
    vals: UncheckedArray[int32]

proc payloadCheck() =
  doAssert offsetOf(Payload, vals) == 4
  doAssert sizeof(Payload) == 4

payloadCheck()

# offsetof tuple types

type
  MyTupleType = tuple
    a: float64
    b: float64
    c: float64

  MyOtherTupleType = tuple
    a: float64
    b: imported_double
    c: float64

  MyCaseObject = object
    val1: imported_double
    case kind: bool
    of true:
      val2,val3: float32
    else:
      val4,val5: int32

doAssert offsetof(MyTupleType, a) == 0
doAssert offsetof(MyTupleType, b) == 8
doAssert offsetof(MyTupleType, c) == 16

doAssert offsetof(MyOtherTupleType, a) == 0
doAssert offsetof(MyOtherTupleType, b) == 8

# The following expression can only work if the offsetof expression is
# properly forwarded for the C code generator.
doAssert offsetof(MyOtherTupleType, c) == 16
doAssert offsetof(Bar, foo) == 4
doAssert offsetof(MyCaseObject, val1) == 0
doAssert offsetof(MyCaseObject, kind) == 8
doAssert offsetof(MyCaseObject, val2) == 12
doAssert offsetof(MyCaseObject, val3) == 16
doAssert offsetof(MyCaseObject, val4) == 12
doAssert offsetof(MyCaseObject, val5) == 16

template reject(e) =
  static: assert(not compiles(e))

reject:
  const off1 = offsetof(MyOtherTupleType, c)

reject:
  const off2 = offsetof(MyOtherTupleType, b)

reject:
  const off3 = offsetof(MyCaseObject, kind)


type
  MyPackedCaseObject {.packed.} = object
    val1: imported_double
    case kind: bool
    of true:
      val2,val3: float32
    else:
      val4,val5: int32

# packed case object

doAssert offsetof(MyPackedCaseObject, val1) == 0
doAssert offsetof(MyPackedCaseObject, val2) == 9
doAssert offsetof(MyPackedCaseObject, val3) == 13
doAssert offsetof(MyPackedCaseObject, val4) == 9
doAssert offsetof(MyPackedCaseObject, val5) == 13

reject:
  const off5 = offsetof(MyPackedCaseObject, val2)

reject:
  const off6 = offsetof(MyPackedCaseObject, val3)

reject:
  const off7 = offsetof(MyPackedCaseObject, val4)

reject:
  const off8 = offsetof(MyPackedCaseObject, val5)


type
  O0 = object
  T0 = tuple[]

doAssert sizeof(O0) == 1
doAssert sizeof(T0) == 1


type
  # this thing may not have padding bytes at the end
  PackedUnion* {.union, packed.} = object
    a*: array[11, byte]
    b*: int64

doAssert sizeof(PackedUnion) == 11
doAssert alignof(PackedUnion) == 1

# bug #22553
type
  ChunkObj = object
    data: UncheckedArray[byte]

doAssert sizeof(ChunkObj) == 1
doAssert offsetOf(ChunkObj, data) == 1


block: # bug #13945
  template c_sizeof(T: typedesc): int =
    block:
      # proc needed pending https://github.com/nim-lang/Nim/issues/13943 D20200409T215527
      proc fun2(): int =
        {.emit:[result," = sizeof(", T, ");"].}
      fun2()

  macro test(body: untyped): untyped =
    result = newStmtList()
    for T in body:
      result.add quote do:
        let s1 = `T`.sizeof
        let s2 = `T`.c_sizeof
        doAssert s1 == s2

  type FooEmpty = object
  const N = 10
  type FooEmptyArr = array[N, FooEmpty]
  type Bar = object
    x: FooEmpty
    y: cint

  type BarTup = (FooEmpty, cint)
  type BarTup2 = (().type, cint)

  test:
    FooEmpty
    FooEmptyArr
    Bar
    BarTup
    BarTup2



discard """
  output: '''
Destructor for TestTestObj
=destroy called
123xyzabc
destroyed: false
destroyed: false
destroyed2: false
destroyed2: false
destroying variable: 2
destroying variable: 1
whiley ends :(
1
(x: "0")
(x: "1")
(x: "2")
(x: "3")
(x: "4")
(x: "5")
(x: "6")
(x: "7")
(x: "8")
(x: "9")
(x: "10")
0
new line before - @['a']
new line after - @['a']
finalizer
aaaaa
hello
true
copying
123
42
@["", "d", ""]
ok
destroying variable: 20
destroying variable: 10
closed
'''
  cmd: "nim c --mm:arc --deepcopy:on -d:nimAllocPagesViaMalloc $file"
"""

block: # bug #23627
  type
    TestObj = object of RootObj

    Test2 = object of RootObj
      foo: TestObj

    TestTestObj = object of RootObj
      shit: TestObj

  proc `=destroy`(x: TestTestObj) =
    echo "Destructor for TestTestObj"
    let test = Test2(foo: TestObj())

  proc testCaseT() =
    let tt1 {.used.} = TestTestObj(shit: TestObj())


  proc main() =
    testCaseT()

  main()


# bug #9401

type
  MyObj = object
    len: int
    data: ptr UncheckedArray[float]

proc `=destroy`*(m: MyObj) =

  echo "=destroy called"

  if m.data != nil:
    deallocShared(m.data)

type
  MyObjDistinct = distinct MyObj

proc `=copy`*(m: var MyObj, m2: MyObj) =
  if m.data == m2.data: return
  if m.data != nil:
    `=destroy`(m)
  m.len = m2.len
  if m.len > 0:
    m.data = cast[ptr UncheckedArray[float]](allocShared(sizeof(float) * m.len))
    copyMem(m.data, m2.data, sizeof(float) * m.len)


proc `=sink`*(m: var MyObj, m2: MyObj) =
  if m.data != m2.data:
    if m.data != nil:
      `=destroy`(m)
    m.len = m2.len
    m.data = m2.data

proc newMyObj(len: int): MyObj =
  result = MyObj()
  result.len = len
  result.data = cast[ptr UncheckedArray[float]](allocShared(sizeof(float) * len))

proc newMyObjDistinct(len: int): MyObjDistinct =
  MyObjDistinct(newMyObj(len))

proc fooDistinct =
  doAssert newMyObjDistinct(2).MyObj.len == 2

fooDistinct()


proc takeSink(x: sink string): bool = true

proc b(x: sink string): string =
  if takeSink(x):
    return x & "abc"
  else:
    result = ""

proc bbb(inp: string) =
  let y = inp & "xyz"
  echo b(y)

bbb("123")


# bug #13691
type Variable = ref object
  value: int

proc `=destroy`(self: typeof(Variable()[])) =
  echo "destroying variable: ",self.value

proc newVariable(value: int): Variable =
  result = Variable()
  result.value = value
  #echo "creating variable: ",result.value

proc test(count: int) =
  var v {.global.} = newVariable(10)

  var count = count - 1
  if count == 0: return

  test(count)
  echo "destroyed: ", v.isNil

test(3)

proc test2(count: int) =
  block: #XXX: Fails with block currently
    var v {.global.} = newVariable(20)

    var count = count - 1
    if count == 0: return

    test2(count)
    echo "destroyed2: ", v.isNil

test2(3)

proc whiley =
  var a = newVariable(1)
  while true:
    var b = newVariable(2)
    if true: raise newException(CatchableError, "test")

try:
  whiley()
except CatchableError:
  echo "whiley ends :("

#------------------------------------------------------------------------------
# issue #13810

import streams

type
  A = ref AObj
  AObj = object of RootObj
    io: Stream
  B = ref object of A
    x: int

proc `=destroy`(x: AObj) =
  close(x.io)
  echo "closed"

var x = B(io: newStringStream("thestream"))


#------------------------------------------------------------------------------
# issue #14003

proc cryptCTR*(nonce: var openArray[char]) =
  nonce[1] = 'A'

proc main() =
  var nonce1 = "0123456701234567"
  cryptCTR(nonce1)
  doAssert(nonce1 == "0A23456701234567")
  var nonce2 = "01234567"
  cryptCTR(nonce2.toOpenArray(0, nonce2.len-1))
  doAssert(nonce2 == "0A234567")

main()

# bug #14079
import std/algorithm

let
  n = @["c", "b"]
  q = @[("c", "2"), ("b", "1")]

doAssert n.sortedByIt(it) == @["b", "c"], "fine"
doAssert q.sortedByIt(it[0]) == @[("b", "1"), ("c", "2")], "fails under arc"


#------------------------------------------------------------------------------
# issue #14236

type
  MyType = object
    a: seq[int]

proc re(x: static[string]): static MyType =
  MyType()

proc match(inp: string, rg: static MyType) =
  doAssert rg.a.len == 0

match("ac", re"a(b|c)")

#------------------------------------------------------------------------------
# issue #14243

type
  Game* = ref object

proc free*(game: Game) =
  let a = 5

proc newGame*(): Game =
  new(result, free)

var game*: Game


#------------------------------------------------------------------------------
# issue #14333

type
  SimpleLoop = object

  Lsg = object
    loops: seq[ref SimpleLoop]
    root: ref SimpleLoop

var lsg: Lsg
lsg.loops.add lsg.root
echo lsg.loops.len

# bug #14495
type
  Gah = ref object
    x: string

proc bug14495 =
  var owners: seq[Gah] = @[]
  for i in 0..10:
    owners.add Gah(x: $i)

  var x: seq[Gah] = @[]
  for i in 0..10:
    x.add owners[i]

  for i in 0..100:
    setLen(x, 0)
    setLen(x, 10)

  for i in 0..x.len-1:
    if x[i] != nil:
      echo x[i][]

  for o in owners:
    echo o[]

bug14495()

# bug #14396
type
  Spinny = ref object
    t: ref int
    text: string

proc newSpinny*(): Spinny =
  Spinny(t: new(int), text: "hello")

proc spinnyLoop(x: ref int, spinny: sink Spinny) =
  echo x[]

proc start*(spinny: sink Spinny) =
  spinnyLoop(spinny.t, spinny)

var spinner1 = newSpinny()
spinner1.start()

# bug #14345

type
  SimpleLoopB = ref object
    children: seq[SimpleLoopB]
    parent: SimpleLoopB

proc addChildLoop(self: SimpleLoopB, loop: SimpleLoopB) =
  self.children.add loop

proc setParent(self: SimpleLoopB, parent: SimpleLoopB) =
  self.parent = parent
  self.parent.addChildLoop(self)

var l = SimpleLoopB()
l.setParent(l)


# bug #14968
import times
let currentTime = now().utc


# bug #14994
import sequtils
var newLine = @['a']
let indent = newSeq[char]()

echo "new line before - ", newline

newline.insert(indent, 0)

echo "new line after - ", newline

# bug #15044

type
  Test = ref object

proc test: Test =
  # broken
  new(result, proc(x: Test) =
    echo "finalizer"
  )

proc tdirectFinalizer =
  discard test()

tdirectFinalizer()


# bug #14480
proc hello(): int =
  result = 42

var leaves {.global.} = hello()
doAssert leaves == 42

# bug #15052

proc mutstrings =
  var data = "hello"
  for c in data.mitems():
    c = 'a'
  echo data

mutstrings()

# bug #15038

type
  Machine = ref object
    hello: string

var machineTypes: seq[tuple[factory: proc(): Machine]]

proc registerMachine(factory: proc(): Machine) =
  var mCreator = proc(): Machine =
    result = factory()

  machineTypes.add((factory: mCreator))

proc facproc(): Machine =
  result = Machine(hello: "hello")

registerMachine(facproc)

proc createMachine =
  for machine in machineTypes:
    echo machine.factory().hello

createMachine()

# bug #15122

import tables

type
  BENodeKind = enum
    tkBytes,
    tkList,
    tkDict

  BENode = object
    case kind: BENodeKind
    of tkBytes: strVal: string
    of tkList: listVal: seq[BENode]
    of tkDict: dictVal: Table[string, BENode]

var data = {
  "examples": {
    "values": BENode(
      kind: tkList,
      listVal: @[BENode(kind: tkBytes, strVal: "test")]
    )
  }.toTable()
}.toTable()

# For ARC listVal is empty for some reason
doAssert data["examples"]["values"].listVal[0].strVal == "test"




###############################################################################
# bug #15405
import parsexml
const test_xml_str = "<A><B>value</B></A>"
var stream = newStringStream(test_xml_str)
var xml: XmlParser
open(xml, stream, "test")
var xml2 = deepCopy(xml)

proc text_parser(xml: var XmlParser) =
  var test_passed = false
  while true:
    xml.next()
    case xml.kind
    of xmlElementStart:
      if xml.elementName == "B":
        xml.next()
        if xml.kind == xmlCharData and xml.charData == "value":
          test_passed = true

    of xmlEof: break
    else: discard
  xml.close()
  doAssert(test_passed)

text_parser(xml)
text_parser(xml2)

# bug #15599
type
  PixelBuffer = ref object

proc newPixelBuffer(): PixelBuffer =
  new(result) do (buffer: PixelBuffer):
    echo "ok"

discard newPixelBuffer()


# bug #17199

proc passSeq(data: seq[string]) =
  # used the system.& proc initially
  let wat = data & "hello"

proc test2 =
  let name = @["hello", "world"]
  passSeq(name)
  doAssert name == @["hello", "world"]

static: test2() # was buggy
test2()

proc merge(x: sink seq[string], y: sink string): seq[string] =
  newSeq(result, x.len + 1)
  for i in 0..x.len-1:
    result[i] = move(x[i])
  result[x.len] = move(y)

proc passSeq2(data: seq[string]) =
  # used the system.& proc initially
  let wat = merge(data, "hello")

proc test3 =
  let name = @["hello", "world"]
  passSeq2(name)
  doAssert name == @["hello", "world"]

static: test3() # was buggy
test3()

# bug #17712
proc t17712 =
  var ppv = new int
  discard @[ppv]
  var el: ref int
  el = [ppv][0]
  echo el != nil

t17712()

# bug #18030

type
  Foo = object
    n: int

proc `=copy`(dst: var Foo, src: Foo) =
  echo "copying"
  dst.n = src.n

proc `=sink`(dst: var Foo, src: Foo) =
  echo "sinking"
  dst.n = src.n

var a: Foo

proc putValue[T](n: T)

proc useForward =
  putValue(123)

proc putValue[T](n: T) =
  var b = Foo(n:n)
  a = b
  echo b.n

useForward()


# bug #17319
type
  BrokenObject = ref object
    brokenType: seq[int]

proc use(obj: BrokenObject) =
  discard

method testMethod(self: BrokenObject) {.base.} =
  iterator testMethodIter() {.closure.} =
    use(self)

  var nameIterVar = testMethodIter
  nameIterVar()

let mikasa = BrokenObject()
mikasa.testMethod()

# bug #19205
type
  InputSectionBase* = object of RootObj
    relocations*: seq[int]   # traced reference. string has a similar SIGSEGV.
  InputSection* = object of InputSectionBase

proc fooz(sec: var InputSectionBase) =
  if sec of InputSection:  # this line SIGSEGV.
    echo 42

var sec = create(InputSection)
sec[] = InputSection(relocations: newSeq[int]())
fooz sec[]

block:
  type
    Data = ref object
      id: int
  proc main =
    var x = Data(id: 99)
    var y = x
    x[] = Data(id: 778)[]
    doAssert y.id == 778
    doAssert x[].id == 778
  main()

block: # bug #19857
  type
    ValueKind = enum VNull, VFloat, VObject # need 3 elements. Cannot remove VNull or VObject

    Value = object
      case kind: ValueKind
      of VFloat: fnum: float
      of VObject: tab: Table[int, int] # OrderedTable[T, U] also makes it fail.
                                      # "simpler" types also work though
      else: discard # VNull can be like this, but VObject must be filled

    # required. Pure proc works
    FormulaNode = proc(c: OrderedTable[string, int]): Value

  proc toF(v: Value): float =
    doAssert v.kind == VFloat
    case v.kind
    of VFloat: result = v.fnum
    else: result = 0.0


  proc foo() =
    let fuck = initOrderedTable[string, int]()
    proc cb(fuck: OrderedTable[string, int]): Value =
                            # works:
                            #result = Value(kind: VFloat, fnum: fuck["field_that_does_not_exist"].float)
                            # broken:
      result = Value()
      discard "actuall runs!"
      let t = fuck["field_that_does_not_exist"]
      echo "never runs, but we crash after! ", t

    doAssertRaises(KeyError):
      let fn = FormulaNode(cb)
      let v = fn(fuck)
      #echo v
      let res = v.toF()

  foo()

import std/options

# bug #21592
type Event* = object
  code*: string

type App* = ref object of RootObj
  id*: string

method process*(self: App): Option[Event] {.base.} =
  raise Exception.new_exception("not impl")

# bug #21617
type Test2 = ref object of RootObj

method bug(t: Test2): seq[float] {.base.} = result = @[]

block: # bug #22664
  type
    ElementKind = enum String, Number
    Element = object
      case kind: ElementKind
      of String:
        str: string
      of Number:
        num: float
    Calc = ref object
      stack: seq[Element]

  var calc = new Calc

  calc.stack.add Element(kind: Number, num: 200.0)
  doAssert $calc.stack == "@[(kind: Number, num: 200.0)]"
  let calc2 = calc
  calc2.stack = calc.stack # This nulls out the object in the stack
  doAssert $calc.stack == "@[(kind: Number, num: 200.0)]"
  doAssert $calc2.stack == "@[(kind: Number, num: 200.0)]"

block: # bug #19250
  type
    Bar[T] = object
      err: proc(): string

    Foo[T] = object
      run: proc(): Bar[T]

  proc bar[T](err: proc(): string): Bar[T] =
    assert not err.isNil
    Bar[T](err: err)

  proc foo(): Foo[char] = 
    result = Foo[char]()
    result.run = proc(): Bar[char] =
      # works
      # result = Bar[char](err: proc(): string = "x")
      # not work
      result = bar[char](proc(): string = "x")

  proc bug[T](fs: Foo[T]): Foo[T] =
    result = Foo[T]()
    result.run = proc(): Bar[T] =
      let res = fs.run()
      
      # works
      # var errors = @[res.err] 
      
      # not work
      var errors: seq[proc(): string] = @[]
      errors.add res.err
      
      return bar[T] do () -> string:
        result = ""
        for err in errors:
          result.add res.err()

  doAssert bug(foo()).run().err() == "x"

block: # bug #22259
  type
    ProcWrapper = tuple
      p: proc() {.closure.}


  proc f(wrapper: ProcWrapper) =
    let s = @[wrapper.p]
    let a = [wrapper.p]

  proc main =
    # let wrapper: ProcWrapper = ProcWrapper(p: proc {.closure.} = echo 10)
    let wrapper: ProcWrapper = (p: proc {.closure.} = echo 10)
    f(wrapper)

  main()

block:
  block: # bug #22923
    block:
      let
        a: int = 100
        b: int32 = 200'i32

      let
        x = arrayWith(a, 8) # compiles
        y = arrayWith(b, 8) # internal error
        z = arrayWith(14, 8) # integer literal also results in a crash

      doAssert x == [100, 100, 100, 100, 100, 100, 100, 100]
      doAssert $y == "[200, 200, 200, 200, 200, 200, 200, 200]"
      doAssert z == [14, 14, 14, 14, 14, 14, 14, 14]

    block:
      let a: string = "nim"
      doAssert arrayWith(a, 3) == ["nim", "nim", "nim"]

      let b: char = 'c'
      doAssert arrayWith(b, 3) == ['c', 'c', 'c']

      let c: uint = 300'u
      doAssert $arrayWith(c, 3) == "[300, 300, 300]"

block: # bug #23505
  type
    K = object
    C = object
      value: ptr K

  proc init(T: type C): C =
    let tmp = new K
    C(value: addr tmp[])

  discard init(C)

block: # bug #23524
  type MyType = object
    a: int

  proc `=destroy`(typ: MyType) = discard

  var t1 = MyType(a: 100)
  var t2 = t1 # Should be a copy?

  proc main() =
    t2 = t1
    doAssert t1.a == 100
    doAssert t2.a == 100

  main()

block: # bug #23907
  type
    Thingy = object
      value: int

    ExecProc[C] = proc(value: sink C): int {.nimcall.}

  proc `=copy`(a: var Thingy, b: Thingy) {.error.}

  var thingyDestroyCount = 0

  proc `=destroy`(thingy: Thingy) =
    assert(thingyDestroyCount <= 0)
    thingyDestroyCount += 1

  proc store(value: sink Thingy): int =
    result = value.value

  let callback: ExecProc[Thingy] = store

  doAssert callback(Thingy(value: 123)) == 123

import std/strutils

block: # bug #23974
  func g(e: seq[string]): lent seq[string] = result = e
  proc k(f: string): seq[string] = f.split("/")
  proc n() =
    const r = "/d/"
    let t =
      if true:
        k(r).g()
      else:
        k("/" & r).g()
    echo t

  n()

block: # bug #23973
  func g(e: seq[string]): lent seq[string] = result = e
  proc k(f: string): seq[string] = f.split("/")
  proc n() =
    const r = "/test/empty"  # or "/test/empty/1"
    let a = k(r).g()
    let t =
      if true:
        k(r).g()
      else:
        k("/" & r).g()   # or raiseAssert ""
    doAssert t == a

  n()

block: # bug #24141
  func reverse(s: var openArray[char]) =
    s[0] = 'f'

  func rev(s: var string) =
    s.reverse

  proc main =
    var abc = "abc"
    abc.rev
    doAssert abc == "fbc"

  main()

block:
  type
    FooObj = object
      data: int
    Foo = ref FooObj


  proc delete(self: FooObj) =
    discard

  var s = Foo()
  new(s, delete)

block:
  type
    FooObj = object
      data: int
      i1, i2, i3, i4: float
    Foo = ref FooObj


  proc delete(self: FooObj) =
    discard

  var s = Foo()
  new(s, delete)

proc test_18070() = # bug #18070
  try:
    try:
      raise newException(CatchableError, "something")
    except:
      raise newException(CatchableError, "something else")
  except:
    doAssert getCurrentExceptionMsg() == "something else"

  let msg = getCurrentExceptionMsg()
  doAssert msg == "", "expected empty string but got: " & $msg

test_18070()

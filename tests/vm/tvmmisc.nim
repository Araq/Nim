import macros
import os

# bug #4462
block:
  proc foo(t: typedesc) {.compileTime.} =
    assert sameType(getType(t), getType(int))

  static:
    foo(int)

# bug #4412
block:
  proc default[T](t: typedesc[T]): T {.inline.} = discard

  static:
    var x = default(type(0))

# bug #6379
import algorithm

static:
  var numArray = [1, 2, 3, 4, -1]
  numArray.sort(cmp)
  doAssert numArray == [-1, 1, 2, 3, 4]

  var str = "cba"
  str.sort(cmp)
  doAssert str == "abc"

# bug #6086
import math, sequtils, sugar

block:
  proc f: int =
    toSeq(10..<10_000).filter(
      a => a == ($a).map(
        d => (d.ord-'0'.ord).int^4
      ).sum
    ).sum

  var a = f()
  const b = f()

  doAssert a == b

block:
  proc f(): seq[char] =
    result = "hello".map(proc(x: char): char = x)

  var runTime = f()
  const compTime = f()
  doAssert runTime == compTime

# #6083
block:
  proc abc(): seq[int] =
    result = @[0]
    result.setLen(2)
    var tmp: int

    for i in 0 ..< 2:
      inc tmp
      result[i] = tmp

  const fact1000 = abc()
  doAssert fact1000 == @[1, 2]

# Tests for VM ops
block:
  static:
    # for joint test, the project path is different, so I disabled it:
    when false:
      doAssert "vm" in getProjectPath()

    let b = getEnv("UNSETENVVAR")
    doAssert b == ""
    doAssert existsEnv("UNSERENVVAR") == false
    putEnv("UNSETENVVAR", "VALUE")
    doAssert getEnv("UNSETENVVAR") == "VALUE"
    doAssert existsEnv("UNSETENVVAR") == true

    doAssert fileExists("MISSINGFILE") == false
    doAssert dirExists("MISSINGDIR") == false
    doAssert fileExists(currentSourcePath())
    doAssert dirExists(currentSourcePath().parentDir)

# bug #7210
block:
  static:
    proc f(size: int): int =
      var some = newStringOfCap(size)
      result = size
    doAssert f(4) == 4

# bug #6689
block:
  static:
    proc foo(): int = 0
    var f: proc(): int
    doAssert f.isNil
    f = foo
    doAssert(not f.isNil)

block:
  static:
    var x: ref ref int
    new(x)
    doAssert(not x.isNil)

# bug #7871
static:
  type Obj = object
    field: int
  var s = newSeq[Obj](1)
  var o = Obj()
  s[0] = o
  o.field = 2
  doAssert s[0].field == 0

# bug #8125
static:
   let def_iter_var = ident("it")

# bug #8142
static:
  type Obj = object
    names: string

  proc pushName(o: var Obj) =
    var s = ""
    s.add("FOOBAR")
    o.names.add(s)

  var o = Obj()
  o.names = ""
  o.pushName()
  o.pushName()
  doAssert o.names == "FOOBARFOOBAR"

# bug #8154
import parseutils

static:
  type Obj = object
    i: int

  proc foo(): Obj =
    discard parseInt("1", result.i, 0)

  static:
    doAssert foo().i == 1

# bug #10333
block:
  const
    encoding: auto = [
      ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"],
      ["", "X", "XX", "XXX", "XL", "L", "LX", "LXX", "LXXX", "XC"],
      ["", "C", "CC", "CCC", "CD", "D", "DC", "DCC", "DCCC", "CM"],
      ["", "M", "MM", "MMM", "--", "-", "--", "---", "----", "--"],
    ]
  doAssert encoding.len == 4

# bug #10886

proc tor(): bool =
  result = true
  result = false or result

proc tand(): bool =
  result = false
  result = true and result

const
  ctor = tor()
  ctand = not tand()

static:
  doAssert ctor
  doAssert ctand

block: # bug #13081
  type Kind = enum
    k0, k1, k2, k3

  type Foo = object
    x0: float
    case kind: Kind
    of k0: discard
    of k1: x1: int
    of k2: x2: string
    of k3: x3: string

  const j1 = Foo(x0: 1.2, kind: k1, x1: 12)
  const j2 = Foo(x0: 1.3, kind: k2, x2: "abc")
  const j3 = Foo(x0: 1.3, kind: k3, x3: "abc2")
  static:
    doAssert $j1 == "(x0: 1.2, kind: k1, x1: 12)"
    doAssert $j2 == """(x0: 1.3, kind: k2, x2: "abc")"""
    doAssert $j3 == """(x0: 1.3, kind: k3, x3: "abc2")"""
  doAssert $j1 == "(x0: 1.2, kind: k1, x1: 12)"
  doAssert $j2 == """(x0: 1.3, kind: k2, x2: "abc")"""
  doAssert $j3 == """(x0: 1.3, kind: k3, x3: "abc2")"""

  doAssert j1.x1 == 12
  static:
    doAssert j1.x1 == 12

block: # bug #15595
  proc fn0()=echo 0
  proc fn1()=discard
  proc main=
    var local = 0
    proc fn2()=echo local
    var a0 = fn0
    var a1 = fn1
    var a2 = fn2
    var a3: proc()
    var a4: proc()
    doAssert a0 == fn0 # bugfix
    doAssert a1 == fn1 # ditto
    doAssert a2 == fn2 # ditto

    doAssert fn0 != fn1

    doAssert a2 != nil
    doAssert a3 == nil # bugfix

    doAssert a3 == a4 # bugfix
  static: main()
  main()

block: # issue #20543
  type F = proc()
  const myArray = block:
    var r: array[1, F]
    r[0] = nil
    r
  doAssert isNil(myArray[0])

# bug #15363
import sequtils

block:
  func identity(a: bool): bool = a

  var a: seq[bool] = static:
      newSeq[bool](0).mapIt(it) # segfaults
  var b: seq[bool] = static:
      newSeq[bool](0).filterIt(it) # does not segfault
  var c: seq[bool] = static:
      newSeq[bool](0).map(identity) # does not segfault
  var d: seq[bool] = static:
      newSeq[bool](0).map(proc (a: bool): bool = false) # segfaults
  var e: seq[bool] = static:
      newSeq[bool](0).filter(identity) # does not segfault
  var f: seq[bool] = static:
      newSeq[bool](0).filter(proc (a: bool): bool = false) # segfaults

  doAssert a == @[]
  doAssert b == @[]
  doAssert c == @[]
  doAssert d == @[]
  doAssert e == @[]
  doAssert f == @[]


block: # bug #18310
  macro t() : untyped =
    let
      x = nnkTupleConstr.newTree(newLit(1))
      y = nnkTupleConstr.newTree(newLit(2))
    doAssert not (x == y) # not using != intentionally
    doAssert not(cast[int](x) == cast[int](y))
    doAssert not(system.`==`(x, y))
    doAssert system.`==`(x, x)
  t()

block: # bug #10815
  type
    Opcode = enum
      iChar, iSet

    Inst = object
      case code: Opcode
        of iChar:
          c: char
        of iSet:
          cs: set[char]

    Patt = seq[Inst]


  proc `$`(p: Patt): string =
    discard

  proc P(): Patt =
    result.add Inst(code: iSet)

  const a = P()
  doAssert $a == ""

import tables

block: # bug #8007
  type
    CostKind = enum
      Fixed,
      Dynamic

    Cost = object
      case kind*: CostKind
      of Fixed:
        cost*: int
      of Dynamic:
        handler*: proc(value: int): int {.nimcall.}

  proc foo(value: int): int {.nimcall.} =
    sizeof(value)

  const a: array[2, Cost] =[
    Cost(kind: Fixed, cost: 999),
    Cost(kind: Dynamic, handler: foo)
  ]

  # OK with arrays & object variants
  doAssert $a == "[(kind: Fixed, cost: 999), (kind: Dynamic, handler: ...)]"

  const b: Table[int, Cost] = {
    0: Cost(kind: Fixed, cost: 999),
    1: Cost(kind: Dynamic, handler: foo)
  }.toTable

  # KO with Tables & object variants
  # echo b # {0: (kind: Fixed, cost: 0), 1: (kind: Dynamic, handler: ...)} # <----- wrong behaviour
  doAssert $b == "{0: (kind: Fixed, cost: 999), 1: (kind: Dynamic, handler: ...)}"

  const c: Table[int, int] = {
    0: 100,
    1: 999
  }.toTable

  # OK with Tables and primitive int
  doAssert $c == "{0: 100, 1: 999}"

  # For some reason the following gives
  #    Error: invalid type for const: Cost
  const d0 = Cost(kind: Fixed, cost: 999)

  # OK with seq & object variants
  const d = @[Cost(kind: Fixed, cost: 999), Cost(kind: Dynamic, handler: foo)]
  doAssert $d == "@[(kind: Fixed, cost: 999), (kind: Dynamic, handler: ...)]"

block: # bug #14340
  block:
    proc opl3EnvelopeCalcSin0() = discard
    type EnvelopeSinfunc = proc() {.nimcall.} # todo: fixme 
    # const EnvelopeCalcSin0 = opl3EnvelopeCalcSin0 # ok
    const EnvelopeCalcSin0: EnvelopeSinfunc = opl3EnvelopeCalcSin0 # was bug
    const envelopeSin = [EnvelopeCalcSin0]
    var a = 0
    envelopeSin[a]()

  block:
    type Mutator = proc() {.noSideEffect, gcsafe.}
    proc mutator0() = discard
    const mTable = [Mutator(mutator0)]
    var i=0
    mTable[i]()

block: # VM wrong register free causes errors in unrelated code
  block: # bug #15597
    #[
    Error: unhandled exception: 'sym' is not accessible using discriminant 'kind' of type 'TNode' [FieldDefect]
    in /Users/timothee/git_clone/nim/Nim_prs/compiler/vm.nim(1176) rawExecute
    in opcIndCall
    in let prc = if not isClosure: bb.sym else: bb[0].sym
    ]#
    proc bar2(head: string): string = "asdf"
    proc zook(u1: int) = discard

    type PathEntry = object
      kind: int
      path: string

    iterator globOpt(): int =
      var u1: int

      zook(u1)
      zook(u1)
      zook(u1)
      zook(u1)
      zook(u1)
      zook(u1)
      zook(u1)
      zook(u1)
      zook(u1)
      zook(u1)
      zook(u1)
      zook(u1)
      zook(u1)
      zook(u1)

      var entry = PathEntry()
      entry.path = bar2("")
      if false:
        echo "here2"

    proc processAux(a: float) = discard

    template bar(iter: untyped): untyped =
      var ret: float
      for x in iter: break
      ret

    proc main() =
      processAux(bar(globOpt()))
    static: main()

  block: # ditto
    # D20201024T133245
    type Deque = object
    proc initDeque2(initialSize: int = 4): Deque = Deque()
    proc len2(a: Deque): int = 2
    proc baz(dir: string): bool = true
    proc bar2(head: string): string = "asdf"
    proc bar3(path: var string) = path = path

    type PathEntry = object
      kind: int
      path: string

    proc initGlobOpt(dir: string, a1=false,a2=false,a3=false,a4=false): string = dir

    iterator globOpt(dir: string): int =
      var stack = initDeque2()
      doAssert baz("")
      let z = stack.len2
      if stack.len2 >= 0:
        var entry = PathEntry()
        let current = if true: stack.len2 else: stack.len2
        entry.path = bar2("")
        bar3(entry.path)
      if false:
        echo "here2" # comment here => you get same error as https://github.com/nim-lang/Nim/issues/15704

    proc processAux(a: float) = discard

    template bar(iter: untyped): untyped =
      var ret: float
      for x in iter: break
      ret
    proc main() =
      processAux(bar(globOpt(initGlobOpt("."))))
    static: main()

  block: # bug #15704
    #[
    Error: attempt to access a nil address kind: rkFloat
    ]#
    type Deque = object
    proc initDeque2(initialSize: int = 4): Deque = Deque()
    proc len2(a: Deque): int = 2

    proc baz(dir: string): bool = true
    proc bar2(head: string): string = "asdf"
    proc bar3(path: var string) = path = path

    type PathEntry = object
      kind: int
      path: string
      depth: int

    proc initGlobOpt(dir: string, a1=false,a2=false,a3=false,a4=false): string =
      dir

    iterator globOpt(dir: string): int =
      var stack = initDeque2()
      doAssert baz("")
      let z = stack.len2
      var a5: int
      if stack.len2 >= 0:
        var entry = PathEntry()
        if false:
          echo "here"
        let current = if true: stack.len2 else: stack.len2
        entry.depth = 1
        entry.path = bar2("")
        bar3(entry.path)
    proc processAux(a: float) = discard
    template bar(iter: untyped): untyped =
      var ret: float
      for x in iter:
        break
      ret
    const dir = "."
    proc main() =
      processAux(bar(globOpt(initGlobOpt(dir))))
    static: main()

block: # bug #8015
  block:
    type Foo = object
      case b: bool
      of false: v1: int
      of true: v2: int
    const t = [Foo(b: false, v1: 1), Foo(b: true, v2: 2)]
    doAssert $t == "[(b: false, v1: 1), (b: true, v2: 2)]"
    doAssert $t[0] == "(b: false, v1: 1)" # was failing

  block:
    type
      CostKind = enum
        Fixed,
        Dynamic

      Cost = object
        case kind*: CostKind
        of Fixed:
          cost*: int
        of Dynamic:
          handler*: proc(): int {.nimcall.}

    proc foo1(): int {.nimcall.} =
      100

    proc foo2(): int {.nimcall.} =
      200

    # Change to `let` and it doesn't crash
    const costTable = [
      0: Cost(kind: Fixed, cost: 999),
      1: Cost(kind: Dynamic, handler: foo1),
      2: Cost(kind: Dynamic, handler: foo2)
    ]

    doAssert $costTable[0] == "(kind: Fixed, cost: 999)"
    doAssert costTable[1].handler() == 100
    doAssert costTable[2].handler() == 200

    # Now trying to carry the table as an object field
    type
      Wrapper = object
        table: array[3, Cost]

    proc procNewWrapper(): Wrapper =
      result.table = costTable

    # Alternatively, change to `const` and it doesn't crash
    let viaProc = procNewWrapper()

    doAssert viaProc.table[1].handler != nil
    doAssert viaProc.table[2].handler != nil
    doAssert $viaProc.table[0] == "(kind: Fixed, cost: 999)"
    doAssert viaProc.table[1].handler() == 100
    doAssert viaProc.table[2].handler() == 200


# bug #19198

block:
  type
    Foo[n: static int] = int

block:
  static:
    let x = int 1
    doAssert $(x.type) == "int"  # Foo

block:
  static:
    let x = int 1
    let y = x + 1
    # Error: unhandled exception: value out of range: -8 notin 0 .. 65535 [RangeDefect]
    doAssert y == 2


type Atom* = object
  bar: int

proc main() = # bug #12994
  var s: seq[Atom]
  var atom: Atom
  var checked = 0
  for i in 0..<2:
    atom.bar = 5
    s.add atom
    atom.reset
    if i == 0:
      checked += 1
      doAssert $s == "@[(bar: 5)]"
    else:
      checked += 1
      doAssert $s == "@[(bar: 5), (bar: 5)]"
  doAssert checked == 2

static: main()
main()

# bug #19201
proc foo(s: sink string) = doAssert s.len == 3

static:
  foo("abc")


static:
  for i in '1' .. '2': # bug #10938
    var s: set[char]
    doAssert s == {}
    incl(s, i)

  for _ in 0 ..< 3: # bug #13312
    var s: string
    s.add("foo")
    doAssert s == "foo"

  for i in 1 .. 5: # bug #13918
    var arr: array[3, int]
    var val: int
    doAssert arr == [0, 0, 0] and val == 0
    for j in 0 ..< len(arr):
      arr[j] = i
      val = i

# bug #20985
let a = block:
  var groups: seq[seq[int]]
  for i in 0 ..< 3:
    var group: seq[int]
    for j in 0 ..< 3:
      group.add j
    groups.add group
  groups

const b = block:
  var groups: seq[seq[int]]
  for i in 0 ..< 3:
    var group: seq[int]
    for j in 0 ..< 3:
      group.add j
    groups.add group
  groups

doAssert a == @[@[0, 1, 2], @[0, 1, 2], @[0, 1, 2]]
doAssert b == @[@[0, 1, 2], @[0, 1, 2], @[0, 1, 2]]

macro m1(s: string): int =
  var ProcID {.global, compileTime.}: int
  inc(ProcID)
  result = newLit(ProcID)

proc macroGlobal =
  doAssert m1("Macro argument") == 1
  doAssert m1("Macro argument") == 2
  doAssert m1("Macro argument") == 3

static: macroGlobal()
macroGlobal()

block: # bug #10108
  template reject(x) =
    static: doAssert(not compiles(x))

  static:
    let x: int = 2
    proc deliver_x(): int = x
    var y2 = deliver_x()
    discard y2
    reject:
      const c5 = deliver_x()

block: # bug #7590
  proc doInit[T]():auto=
    var a: T
    return a

  proc fun2[T](tup1:T)=
    const tup0=doInit[T]()

    # var tup=tup0 #ok
    const tup=tup0 #causes bug

    doAssert tup is tuple
    doAssert tup[0] is tuple
    for ai in tup.fields:
      doAssert ai is tuple, "BUG2"

  # const c=(foo:(bar1: 0.0))
  const c=(foo:(bar1:"foo1"))
  fun2(c)

block: # bug #21708
  type
    Tup = tuple[name: string]

  const X: array[2, Tup] = [(name: "foo",), (name: "bar",)]

  static:
    let s = X[0]
    doAssert s[0] == "foo"

block:
  proc swap[T](x: var T): T =
    result = x
    x = default(T)

  proc merge[T](a, b: var openArray[T]) =
    a[0] = swap b[0]

  static:
    var x = "abc"
    var y = "356"
    merge(x, y)
    doAssert x == "3bc"

block: # bug #22190
  type
    EVMFork = enum
      Berlin
      Istanbul
      Shanghai

  const
    Vm2OpAllForks =
      {EVMFork.low .. EVMFork.high}

    vm2OpExecBlockData = [(forks: Vm2OpAllForks)]

  proc mkOpTable(selected: EVMFork): bool =
    selected notin vm2OpExecBlockData[0].forks

  const
    tab = mkOpTable(Berlin)

  doAssert not tab

block: # issue #22524
  const cnst = cstring(nil)
  doAssert cnst.isNil
  doAssert cnst == nil
  let b = cnst
  doAssert b.isNil
  doAssert b == nil

  let a = static: cstring(nil)
  doAssert a.isNil

  static:
    var x: cstring
    doAssert x.isNil
    doAssert x == nil
    doAssert x != ""

block: # issue #15730
  const s: cstring = ""
  doAssert s != nil

  static:
    let s: cstring = ""
    doAssert not s.isNil
    doAssert s != nil
    doAssert s == ""

static: # more nil cstring issues
  let x = cstring(nil)
  doAssert x.len == 0

block: # bug #23925
  type Foo = enum A = -1
  proc foo =
    doAssert cast[Foo](-1) == A
    doAssert ord(A) == -1

  static: foo()
  foo()

  type E = enum
    e0 e1 e2 e3 e4 e5 e6 e7 e8 e9 e10 e11 e12 e13 e14 e15 e16 e17 e18 e19 e20
    e21 e22 e23 e24 e25 e26 e27 e28 e29 e30 e31 e32 e33 e34 e35 e36 e37 e38
    e39 e40 e41 e42 e43 e44 e45 e46 e47 e48 e49 e50 e51 e52 e53 e54 e55 e56
    e57 e58 e59 e60 e61 e62 e63 e64 e65 e66 e67 e68 e69 e70 e71 e72 e73 e74
    e75 e76 e77 e78 e79 e80 e81 e82 e83 e84 e85 e86 e87 e88 e89 e90 e91 e92
    e93 e94 e95 e96 e97 e98 e99 e100 e101 e102 e103 e104 e105 e106 e107 e108
    e109 e110 e111 e112 e113 e114 e115 e116 e117 e118 e119 e120 e121 e122
    e123 e124 e125 e126 e127 e128
  proc bar =
    doAssert cast[E](int(e128)) == e128

  static: bar()
  bar()

static: # bug #21353
  var s: proc () = default(proc ())
  doAssert s == nil

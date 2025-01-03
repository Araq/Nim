discard """
  matrix: "--mm:refc; --mm:orc"
  targets: "c js"
"""

# xxx move all tests under `main`

import std/sequtils
import strutils
from algorithm import sorted
import std/assertions

{.experimental: "strictEffects".}
{.push warningAsError[Effect]: on.}
{.experimental: "strictFuncs".}

# helper for testing double substitution side effects which are handled
# by `evalOnceAs`
var counter = 0
proc identity[T](a: T): auto =
  counter.inc
  a

block: # concat test
  let
    s1 = @[1, 2, 3]
    s2 = @[4, 5]
    s3 = @[6, 7]
    total = concat(s1, s2, s3)
  doAssert total == @[1, 2, 3, 4, 5, 6, 7]

block: # count test
  let
    s1 = @[1, 2, 3, 2]
    s2 = @['a', 'b', 'x', 'a']
    a1 = [1, 2, 3, 2]
    a2 = ['a', 'b', 'x', 'a']
    r0 = count(s1, 0)
    r1 = count(s1, 1)
    r2 = count(s1, 2)
    r3 = count(s2, 'y')
    r4 = count(s2, 'x')
    r5 = count(s2, 'a')
    ar0 = count(a1, 0)
    ar1 = count(a1, 1)
    ar2 = count(a1, 2)
    ar3 = count(a2, 'y')
    ar4 = count(a2, 'x')
    ar5 = count(a2, 'a')
  doAssert r0 == 0
  doAssert r1 == 1
  doAssert r2 == 2
  doAssert r3 == 0
  doAssert r4 == 1
  doAssert r5 == 2
  doAssert ar0 == 0
  doAssert ar1 == 1
  doAssert ar2 == 2
  doAssert ar3 == 0
  doAssert ar4 == 1
  doAssert ar5 == 2

block: # cycle tests
  let
    a = @[1, 2, 3]
    b: seq[int] = @[]
    c = [1, 2, 3]

  doAssert a.cycle(3) == @[1, 2, 3, 1, 2, 3, 1, 2, 3]
  doAssert a.cycle(0) == @[]
  #doAssert a.cycle(-1) == @[] # will not compile!
  doAssert b.cycle(3) == @[]
  doAssert c.cycle(3) == @[1, 2, 3, 1, 2, 3, 1, 2, 3]
  doAssert c.cycle(0) == @[]

block: # repeat tests
  doAssert repeat(10, 5) == @[10, 10, 10, 10, 10]
  doAssert repeat(@[1, 2, 3], 2) == @[@[1, 2, 3], @[1, 2, 3]]
  doAssert repeat([1, 2, 3], 2) == @[[1, 2, 3], [1, 2, 3]]

block: # deduplicates test
  let
    dup1 = @[1, 1, 3, 4, 2, 2, 8, 1, 4]
    dup2 = @["a", "a", "c", "d", "d"]
    dup3 = [1, 1, 3, 4, 2, 2, 8, 1, 4]
    dup4 = ["a", "a", "c", "d", "d"]
    unique1 = deduplicate(dup1)
    unique2 = deduplicate(dup2)
    unique3 = deduplicate(dup3)
    unique4 = deduplicate(dup4)
    unique5 = deduplicate(dup1.sorted, true)
    unique6 = deduplicate(dup2, true)
    unique7 = deduplicate(dup3.sorted, true)
    unique8 = deduplicate(dup4, true)
  doAssert unique1 == @[1, 3, 4, 2, 8]
  doAssert unique2 == @["a", "c", "d"]
  doAssert unique3 == @[1, 3, 4, 2, 8]
  doAssert unique4 == @["a", "c", "d"]
  doAssert unique5 == @[1, 2, 3, 4, 8]
  doAssert unique6 == @["a", "c", "d"]
  doAssert unique7 == @[1, 2, 3, 4, 8]
  doAssert unique8 == @["a", "c", "d"]

block: # zip test
  let
    short = @[1, 2, 3]
    long = @[6, 5, 4, 3, 2, 1]
    words = @["one", "two", "three"]
    ashort = [1, 2, 3]
    along = [6, 5, 4, 3, 2, 1]
    awords = ["one", "two", "three"]
    zip1 = zip(short, long)
    zip2 = zip(short, words)
    zip3 = zip(ashort, along)
  doAssert zip1 == @[(1, 6), (2, 5), (3, 4)]
  doAssert zip2 == @[(1, "one"), (2, "two"), (3, "three")]
  doAssert zip3 == @[(1, 6), (2, 5), (3, 4)]
  doAssert zip1[2][1] == 4
  doAssert zip2[2][1] == "three"
  doAssert zip3[2][1] == 4
  when (NimMajor, NimMinor) <= (1, 0):
    let
      # In Nim 1.0.x and older, zip returned a seq of tuple strictly
      # with fields named "a" and "b".
      zipAb = zip(ashort, awords)
    doAssert zipAb == @[(a: 1, b: "one"), (2, "two"), (3, "three")]
    doAssert zipAb[2].b == "three"
  else:
    let
      # As zip returns seq of anonymous tuples, they can be assigned
      # to any variable that's a sequence of named tuples too.
      zipXy: seq[tuple[x: int, y: string]] = zip(ashort, awords)
      zipMn: seq[tuple[m: int, n: string]] = zip(ashort, words)
    doAssert zipXy == @[(x: 1, y: "one"), (2, "two"), (3, "three")]
    doAssert zipMn == @[(m: 1, n: "one"), (2, "two"), (3, "three")]
    doAssert zipXy[2].y == "three"
    doAssert zipMn[2].n == "three"

block: # distribute tests
  let numbers = @[1, 2, 3, 4, 5, 6, 7]
  doAssert numbers.distribute(3) == @[@[1, 2, 3], @[4, 5], @[6, 7]]
  doAssert numbers.distribute(6)[0] == @[1, 2]
  doAssert numbers.distribute(6)[5] == @[7]
  let a = @[1, 2, 3, 4, 5, 6, 7]
  doAssert a.distribute(1, true) == @[@[1, 2, 3, 4, 5, 6, 7]]
  doAssert a.distribute(1, false) == @[@[1, 2, 3, 4, 5, 6, 7]]
  doAssert a.distribute(2, true) == @[@[1, 2, 3, 4], @[5, 6, 7]]
  doAssert a.distribute(2, false) == @[@[1, 2, 3, 4], @[5, 6, 7]]
  doAssert a.distribute(3, true) == @[@[1, 2, 3], @[4, 5], @[6, 7]]
  doAssert a.distribute(3, false) == @[@[1, 2, 3], @[4, 5, 6], @[7]]
  doAssert a.distribute(4, true) == @[@[1, 2], @[3, 4], @[5, 6], @[7]]
  doAssert a.distribute(4, false) == @[@[1, 2], @[3, 4], @[5, 6], @[7]]
  doAssert a.distribute(5, true) == @[@[1, 2], @[3, 4], @[5], @[6], @[7]]
  doAssert a.distribute(5, false) == @[@[1, 2], @[3, 4], @[5, 6], @[7], @[]]
  doAssert a.distribute(6, true) == @[@[1, 2], @[3], @[4], @[5], @[6], @[7]]
  doAssert a.distribute(6, false) == @[
    @[1, 2], @[3, 4], @[5, 6], @[7], @[], @[]]
  doAssert a.distribute(8, false) == a.distribute(8, true)
  doAssert a.distribute(90, false) == a.distribute(90, true)
  var b = @[0]
  for f in 1 .. 25: b.add(f)
  doAssert b.distribute(5, true)[4].len == 5
  doAssert b.distribute(5, false)[4].len == 2

block: # map test
  let
    numbers = @[1, 4, 5, 8, 9, 7, 4]
    anumbers = [1, 4, 5, 8, 9, 7, 4]
    m1 = map(numbers, proc(x: int): int = 2*x)
    m2 = map(anumbers, proc(x: int): int = 2*x)
  doAssert m1 == @[2, 8, 10, 16, 18, 14, 8]
  doAssert m2 == @[2, 8, 10, 16, 18, 14, 8]

block: # apply test
  var a = @["1", "2", "3", "4"]
  apply(a, proc(x: var string) = x &= "42")
  doAssert a == @["142", "242", "342", "442"]

block: # filter proc test
  let
    colors = @["red", "yellow", "black"]
    acolors = ["red", "yellow", "black"]
    f1 = filter(colors, proc(x: string): bool = x.len < 6)
    f2 = filter(colors) do (x: string) -> bool: x.len > 5
    f3 = filter(acolors, proc(x: string): bool = x.len < 6)
    f4 = filter(acolors) do (x: string) -> bool: x.len > 5
  doAssert f1 == @["red", "black"]
  doAssert f2 == @["yellow"]
  doAssert f3 == @["red", "black"]
  doAssert f4 == @["yellow"]

block: # filter iterator test
  let numbers = @[1, 4, 5, 8, 9, 7, 4]
  let anumbers = [1, 4, 5, 8, 9, 7, 4]
  doAssert toSeq(filter(numbers, proc (x: int): bool = x mod 2 == 0)) ==
    @[4, 8, 4]
  doAssert toSeq(filter(anumbers, proc (x: int): bool = x mod 2 == 0)) ==
    @[4, 8, 4]

block: # keepIf test
  var floats = @[13.0, 12.5, 5.8, 2.0, 6.1, 9.9, 10.1]
  keepIf(floats, proc(x: float): bool = x > 10)
  doAssert floats == @[13.0, 12.5, 10.1]

block: # insert tests
  var dest = @[1, 1, 1, 1, 1, 1, 1, 1]
  let
    src = @[2, 2, 2, 2, 2, 2]
    outcome = @[1, 1, 1, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1]
  dest.insert(src, 3)
  doAssert dest == outcome, """\
  Inserting [2,2,2,2,2,2] into [1,1,1,1,1,1,1,1]
  at 3 is [1,1,1,2,2,2,2,2,2,1,1,1,1,1]"""

block: # filterIt test
  let
    temperatures = @[-272.15, -2.0, 24.5, 44.31, 99.9, -113.44]
    acceptable = filterIt(temperatures, it < 50 and it > -10)
    notAcceptable = filterIt(temperatures, it > 50 or it < -10)
  doAssert acceptable == @[-2.0, 24.5, 44.31]
  doAssert notAcceptable == @[-272.15, 99.9, -113.44]

block: # keepItIf test
  var candidates = @["foo", "bar", "baz", "foobar"]
  keepItIf(candidates, it.len == 3 and it[0] == 'b')
  doAssert candidates == @["bar", "baz"]

block: # all
  let
    numbers = @[1, 4, 5, 8, 9, 7, 4]
    anumbers = [1, 4, 5, 8, 9, 7, 4]
    len0seq: seq[int] = @[]
  doAssert all(numbers, proc (x: int): bool = return x < 10) == true
  doAssert all(numbers, proc (x: int): bool = return x < 9) == false
  doAssert all(len0seq, proc (x: int): bool = return false) == true
  doAssert all(anumbers, proc (x: int): bool = return x < 10) == true
  doAssert all(anumbers, proc (x: int): bool = return x < 9) == false

block: # allIt
  let
    numbers = @[1, 4, 5, 8, 9, 7, 4]
    anumbers = [1, 4, 5, 8, 9, 7, 4]
    len0seq: seq[int] = @[]
  doAssert allIt(numbers, it < 10) == true
  doAssert allIt(numbers, it < 9) == false
  doAssert allIt(len0seq, false) == true
  doAssert allIt(anumbers, it < 10) == true
  doAssert allIt(anumbers, it < 9) == false

block: # any
  let
    numbers = @[1, 4, 5, 8, 9, 7, 4]
    anumbers = [1, 4, 5, 8, 9, 7, 4]
    len0seq: seq[int] = @[]
  doAssert any(numbers, proc (x: int): bool = return x > 8) == true
  doAssert any(numbers, proc (x: int): bool = return x > 9) == false
  doAssert any(len0seq, proc (x: int): bool = return true) == false
  doAssert any(anumbers, proc (x: int): bool = return x > 8) == true
  doAssert any(anumbers, proc (x: int): bool = return x > 9) == false

block: # anyIt
  let
    numbers = @[1, 4, 5, 8, 9, 7, 4]
    anumbers = [1, 4, 5, 8, 9, 7, 4]
    len0seq: seq[int] = @[]
  doAssert anyIt(numbers, it > 8) == true
  doAssert anyIt(numbers, it > 9) == false
  doAssert anyIt(len0seq, true) == false
  doAssert anyIt(anumbers, it > 8) == true
  doAssert anyIt(anumbers, it > 9) == false

block: # toSeq test
  block:
    let
      numeric = @[1, 2, 3, 4, 5, 6, 7, 8, 9]
      oddNumbers = toSeq(filter(numeric) do (x: int) -> bool:
        if x mod 2 == 1:
          result = true
        else:
          result = false
      )
    doAssert oddNumbers == @[1, 3, 5, 7, 9]

  block:
    doAssert [1, 2].toSeq == @[1, 2]
    doAssert @[1, 2].toSeq == @[1, 2]

    doAssert @[1, 2].toSeq == @[1, 2]
    doAssert toSeq(@[1, 2]) == @[1, 2]

  block:
    iterator myIter(seed: int): auto =
      for i in 0..<seed:
        yield i
    doAssert toSeq(myIter(2)) == @[0, 1]

  block:
    iterator myIter(): auto {.inline.} =
      yield 1
      yield 2

    doAssert myIter.toSeq == @[1, 2]
    doAssert toSeq(myIter) == @[1, 2]

  when not defined(js):
    # pending #4695
    block:
        iterator myIter(): int {.closure.} =
          yield 1
          yield 2

        doAssert myIter.toSeq == @[1, 2]
        doAssert toSeq(myIter) == @[1, 2]

    block:
      proc myIter(): auto =
        iterator ret(): int {.closure.} =
          yield 1
          yield 2
        result = ret

      doAssert myIter().toSeq == @[1, 2]
      doAssert toSeq(myIter()) == @[1, 2]

    block:
      proc myIter(n: int): auto =
        var counter = 0
        iterator ret(): int {.closure.} =
          while counter < n:
            yield counter
            counter.inc
        result = ret

      block:
        let myIter3 = myIter(3)
        doAssert myIter3.toSeq == @[0, 1, 2]
      block:
        let myIter3 = myIter(3)
        doAssert toSeq(myIter3) == @[0, 1, 2]
      block:
        # makes sure this does not hang forever
        doAssert myIter(3).toSeq == @[0, 1, 2]
        doAssert toSeq(myIter(3)) == @[0, 1, 2]

block:
  # tests https://github.com/nim-lang/Nim/issues/7187
  counter = 0
  let ret = toSeq(@[1, 2, 3].identity().filter(proc (x: int): bool = x < 3))
  doAssert ret == @[1, 2]
  doAssert counter == 1
block: # foldl tests
  let
    numbers = @[5, 9, 11]
    addition = foldl(numbers, a + b)
    subtraction = foldl(numbers, a - b)
    multiplication = foldl(numbers, a * b)
    words = @["nim", "is", "cool"]
    concatenation = foldl(words, a & b)
  doAssert addition == 25, "Addition is (((5)+9)+11)"
  doAssert subtraction == -15, "Subtraction is (((5)-9)-11)"
  doAssert multiplication == 495, "Multiplication is (((5)*9)*11)"
  doAssert concatenation == "nimiscool"

block: # foldr tests
  let
    numbers = @[5, 9, 11]
    addition = foldr(numbers, a + b)
    subtraction = foldr(numbers, a - b)
    multiplication = foldr(numbers, a * b)
    words = @["nim", "is", "cool"]
    concatenation = foldr(words, a & b)
  doAssert addition == 25, "Addition is (5+(9+(11)))"
  doAssert subtraction == 7, "Subtraction is (5-(9-(11)))"
  doAssert multiplication == 495, "Multiplication is (5*(9*(11)))"
  doAssert concatenation == "nimiscool"
  doAssert toSeq(1..3).foldr(a + b) == 6 # issue #14404

block: # mapIt + applyIt test
  counter = 0
  var
    nums = @[1, 2, 3, 4]
    strings = nums.identity.mapIt($(4 * it))
  doAssert counter == 1
  nums.applyIt(it * 3)
  doAssert nums[0] + nums[3] == 15
  doAssert strings[2] == "12"

block: # newSeqWith tests
  var seq2D = newSeqWith(4, newSeq[bool](2))
  seq2D[0][0] = true
  seq2D[1][0] = true
  seq2D[0][1] = true
  doAssert seq2D == @[@[true, true], @[true, false], @[false, false], @[false, false]]

block: # bug #21538
  var x: seq[int] = @[2, 4]
  var y = newSeqWith(x.pop(), true)
  doAssert y == @[true, true, true, true]

block: # mapLiterals tests
  let x = mapLiterals([0.1, 1.2, 2.3, 3.4], int)
  doAssert x is array[4, int]
  doAssert mapLiterals((1, ("abc"), 2), float, nested = false) ==
    (float(1), "abc", float(2))
  doAssert mapLiterals(([1], ("abc"), 2), `$`, nested = true) ==
    (["1"], "abc", "2")

block: # mapIt with openArray
  counter = 0
  proc foo(x: openArray[int]): seq[int] = x.mapIt(it * 10)
  doAssert foo([identity(1), identity(2)]) == @[10, 20]
  doAssert counter == 2

block: # mapIt with direct openArray
  proc foo1(x: openArray[int]): seq[int] = x.mapIt(it * 10)
  counter = 0
  doAssert foo1(openArray[int]([identity(1), identity(2)])) == @[10, 20]
  doAssert counter == 2

  # Corner cases (openArray literals should not be common)
  template foo2(x: openArray[int]): seq[int] = x.mapIt(it * 10)
  counter = 0
  doAssert foo2(openArray[int]([identity(1), identity(2)])) == @[10, 20]
  doAssert counter == 2

  counter = 0
  doAssert openArray[int]([identity(1), identity(2)]).mapIt(it) == @[1, 2]
  doAssert counter == 2

block: # mapIt empty test, see https://github.com/nim-lang/Nim/pull/8584#pullrequestreview-144723468
  # NOTE: `[].mapIt(it)` is illegal, just as `let a = @[]` is (lacks type
  # of elements)
  doAssert: not compiles(mapIt(@[], it))
  doAssert: not compiles(mapIt([], it))
  doAssert newSeq[int](0).mapIt(it) == @[]

block: # mapIt redifinition check, see https://github.com/nim-lang/Nim/issues/8580
  let s2 = [1, 2].mapIt(it)
  doAssert s2 == @[1, 2]

block:
  counter = 0
  doAssert [1, 2].identity().mapIt(it*2).mapIt(it*10) == @[20, 40]
  # https://github.com/nim-lang/Nim/issues/7187 test case
  doAssert counter == 1

block: # mapIt with invalid RHS for `let` (#8566)
  type X = enum
    A, B
  doAssert mapIt(X, $it) == @["A", "B"]

block:
  # bug #9093
  let inp = "a:b,c:d"

  let outp = inp.split(",").mapIt(it.split(":"))
  doAssert outp == @[@["a", "b"], @["c", "d"]]


block:
  proc iter(len: int): auto =
    result = iterator(): int =
      for i in 0..<len:
        yield i

  # xxx: obscure CT error: basic_types.nim(16, 16) Error: internal error: symbol has no generated name: true
  when not defined(js):
    doAssert: iter(3).mapIt(2*it).foldl(a + b) == 6

block: # strictFuncs tests with ref object
  type Foo = ref object

  let foo1 = Foo()
  let foo2 = Foo()
  let foos = @[foo1, foo2]

  # Procedures that are `func`
  discard concat(foos, foos)
  discard count(foos, foo1)
  discard cycle(foos, 3)
  discard deduplicate(foos)
  discard minIndex(foos)
  discard maxIndex(foos)
  discard distribute(foos, 2)
  var mutableFoos = foos
  mutableFoos.delete(0..1)
  mutableFoos.insert(foos)

  # Some procedures that are `proc`, but were reverted from `func`
  discard repeat(foo1, 3)
  discard zip(foos, foos)
  let fooTuples = @[(foo1, 1), (foo2, 2)]
  discard unzip(fooTuples)

template main =
  # xxx move all tests here
  block: # delete tests
    let outcome = @[1, 1, 1, 1, 1, 1, 1, 1]
    var dest = @[1, 1, 1, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1]
    dest.delete(3, 8)
    doAssert outcome == dest, """\
    Deleting range 3-9 from [1,1,1,2,2,2,2,2,2,1,1,1,1,1]
    is [1,1,1,1,1,1,1,1]"""
    var x = @[1, 2, 3]
    x.delete(100, 100)
    doAssert x == @[1, 2, 3]

  block: # delete tests
    var a = @[10, 11, 12, 13, 14]
    doAssertRaises(IndexDefect): a.delete(4..5)
    doAssertRaises(IndexDefect): a.delete(4..<6)
    doAssertRaises(IndexDefect): a.delete(-1..1)
    doAssertRaises(IndexDefect): a.delete(-1 .. -1)
    doAssertRaises(IndexDefect): a.delete(5..5)
    doAssertRaises(IndexDefect): a.delete(5..3)
    doAssertRaises(IndexDefect): a.delete(5..<5) # edge case
    doAssert a == @[10, 11, 12, 13, 14]
    a.delete(4..4)
    doAssert a == @[10, 11, 12, 13]
    a.delete(1..2)
    doAssert a == @[10, 13]
    a.delete(1..<1) # empty slice
    doAssert a == @[10, 13]
    a.delete(0..<0)
    doAssert a == @[10, 13]
    a.delete(0..0)
    doAssert a == @[13]
    a.delete(0..0)
    doAssert a == @[]
    doAssertRaises(IndexDefect): a.delete(0..0)
    doAssertRaises(IndexDefect): a.delete(0..<0) # edge case
    block:
      type A = object
        a0: int
      var a = @[A(a0: 10), A(a0: 11), A(a0: 12)]
      a.delete(0..1)
      doAssert a == @[A(a0: 12)]
    block:
      type A = ref object
      let a0 = A()
      let a1 = A()
      let a2 = A()
      var a = @[a0, a1, a2]
      a.delete(0..1)
      doAssert a == @[a2]

static: main()
main()

{.pop.}

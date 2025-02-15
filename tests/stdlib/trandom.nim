discard """
  joinable: false # to avoid messing with global rand state
  matrix: "--mm:refc; --mm:orc; --backend:js --jsbigint64:off -d:nimStringHash2; --backend:js --jsbigint64:on"
"""
import std/[assertions, formatfloat]
import std/[random, math, stats, sets, tables]
import std/private/jsutils
when not defined(js):
  import std/os

randomize(233)

proc main() =
  var occur: array[1000, int] = default(array[1000, int])

  for i in 0..100_000:
    let x = rand(high(occur))
    inc occur[x]

  doAssert max(occur) <= 140 and min(occur) >= 60 # gives some slack

  var a = [0, 1]
  shuffle(a)
  doAssert a in [[0,1], [1,0]]

  doAssert rand(0) == 0
  when not defined(nimscript):
    doAssert sample("a") == 'a'

  when compileOption("rangeChecks") and not defined(nimscript):
    doAssertRaises(RangeDefect):
      discard rand(-1)

    doAssertRaises(RangeDefect):
      discard rand(-1.0)

  # don't use causes integer overflow
  doAssert compiles(rand[int](low(int) .. high(int)))

main()

block:
  when not defined(js):
    doAssert almostEqual(rand(12.5), 7.355175342026979)
    doAssert almostEqual(rand(2233.3322), 499.342386778917)

  type DiceRoll = range[0..6]
  when not defined(js):
    doAssert rand(DiceRoll).int == 3
  elif compileOption("jsbigint64"):
    doAssert rand(DiceRoll).int == 1
  else:
    doAssert rand(DiceRoll).int == 6

var rs: RunningStat
for j in 1..5:
  for i in 1 .. 100_000:
    rs.push(gauss())
  doAssert abs(rs.mean-0) < 0.08, $rs.mean
  doAssert abs(rs.standardDeviation()-1.0) < 0.1
  let bounds = [3.5, 5.0]
  for a in [rs.max, -rs.min]:
    doAssert a >= bounds[0] and a <= bounds[1]
  rs.clear()

block:
  type DiceRoll = range[3..6]
  var flag = false
  for i in 0..<100:
    if rand(5.DiceRoll) < 3:
      flag = true
  doAssert flag # because of: rand(max: int): int


block: # random int
  block: # there might be some randomness
    var set = initHashSet[int](128)

    for i in 1..1000:
      incl(set, rand(high(int)))
    doAssert len(set) == 1000

  block: # single number bounds work
    var rand: int
    for i in 1..1000:
      rand = rand(1000)
      doAssert rand <= 1000
      doAssert rand >= 0

  block: # slice bounds work
    var rand: int
    for i in 1..1000:
      rand = rand(100..1000)
      doAssert rand <= 1000
      doAssert rand >= 100

  block: # again gives new numbers
    var rand1 = rand(1000000)
    when not (defined(js) or defined(nimscript)):
      os.sleep(200)

    var rand2 = rand(1000000)
    doAssert rand1 != rand2

block: # random float
  block: # there might be some randomness
    var set = initHashSet[float](128)

    for i in 1..100:
      incl(set, rand(1.0))
    doAssert len(set) == 100

  block: # single number bounds work
    var rand: float
    for i in 1..1000:
      rand = rand(1000.0)
      doAssert rand <= 1000.0
      doAssert rand >= 0.0

  block: # slice bounds work
    var rand: float
    for i in 1..1000:
      rand = rand(100.0..1000.0)
      doAssert rand <= 1000.0
      doAssert rand >= 100.0

  block: # again gives new numbers
    var rand1: float = rand(1000000.0)
    when not (defined(js) or defined(nimscript)):
      os.sleep(200)

    var rand2: float = rand(1000000.0)
    doAssert rand1 != rand2

block: # random sample
  block: # "non-uniform array sample unnormalized int CDF
    let values = [10, 20, 30, 40, 50] # values
    let counts = [4, 3, 2, 1, 0]      # weights aka unnormalized probabilities
    var histo = initCountTable[int]()
    let cdf = counts.cumsummed        # unnormalized CDF
    for i in 0 ..< 5000:
      histo.inc(sample(values, cdf))
    doAssert histo.len == 4              # number of non-zero in `counts`
    # Any one bin is a binomial random var for n samples, each with prob p of
    # adding a count to k; E[k]=p*n, Var k=p*(1-p)*n, approximately Normal for
    # big n.  So, P(abs(k - p*n)/sqrt(p*(1-p)*n))>3.0) =~ 0.0027, while
    # P(wholeTestFails) =~ 1 - P(binPasses)^4 =~ 1 - (1-0.0027)^4 =~ 0.01.
    for i, c in counts:
      if c == 0:
        doAssert values[i] notin histo
        continue
      let p = float(c) / float(cdf[^1])
      let n = 5000.0
      let expected = p * n
      let stdDev = sqrt(n * p * (1.0 - p))
      doAssert abs(float(histo[values[i]]) - expected) <= 3.0 * stdDev

  block: # non-uniform array sample normalized float CDF
    let values = [10, 20, 30, 40, 50]     # values
    let counts = [0.4, 0.3, 0.2, 0.1, 0]  # probabilities
    var histo = initCountTable[int]()
    let cdf = counts.cumsummed            # normalized CDF
    for i in 0 ..< 5000:
      histo.inc(sample(values, cdf))
    doAssert histo.len == 4                  # number of non-zero in ``counts``
    for i, c in counts:
      if c == 0:
        doAssert values[i] notin histo
        continue
      let p = float(c) / float(cdf[^1])
      let n = 5000.0
      let expected = p * n
      let stdDev = sqrt(n * p * (1.0 - p))
      # NOTE: like unnormalized int CDF test, P(wholeTestFails) =~ 0.01.
      doAssert abs(float(histo[values[i]]) - expected) <= 3.0 * stdDev

block:
  # 0 is a valid seed
  var r = initRand(0)
  doAssert r.rand(1.0) != r.rand(1.0)
  r = initRand(10)
  doAssert r.rand(1.0) != r.rand(1.0)
  # changing the seed changes the sequence
  var r1 = initRand(123)
  var r2 = initRand(124)
  doAssert r1.rand(1.0) != r2.rand(1.0)

block: # bug #17467
  let n = 1000
  for i in -n .. n:
    var r = initRand(i)
    let x = r.rand(1.0)
    doAssert x > 1e-4, $(x, i)
      # This used to fail for each i in 0..<26844, i.e. the 1st produced value
      # was predictable and < 1e-4, skewing distributions.

block: # bug #16360, Natural overload
  var r = initRand()
  template test(a) =
    let a2 = a
    block:
      let a3 = r.rand(a2)
      doAssert a3 <= a2
      doAssert a3.type is a2.type
    block:
      let a3 = rand(a2)
      doAssert a3 <= a2
      doAssert a3.type is a2.type
  test int.high
  test int.high - 1
  test int.high - 2
  test 0

block: # same as above but use slice overload
  var r = initRand()
  template test[T](a: T) =
    let a2: T = a
    block:
      let a3 = r.rand(T(0) .. a2)
      doAssert a3 <= a2
      doAssert a3.type is a2.type
    block:
      let a3 = rand(T(0) .. a2)
      doAssert a3 <= a2
      doAssert a3.type is a2.type
  test cast[uint](int.high)
  test cast[uint](int.high) + 1
  when hasWorkingInt64 and defined(js):
    # weirdly this has to run only in JS for the final int32.high test
    # to be the same between C/C++ and --jsbigint64:on
    test uint64.high
    test uint64.high - 1
  test uint.high - 2
  test uint.high - 1
  test uint.high
  test int.high
  test int.high - 1
  test int.high - 2
  test 0
  test 0'u
  test 0'u64

block: # bug #16296
  var r = initRand()
  template test(x) =
    let a2 = x
    let a3 = r.rand(a2)
    doAssert a3 <= a2.b
    doAssert a3 >= a2.a
    doAssert a3.type is a2.a.type
  test(-2 .. int.high-1)
  test(int.low .. int.high)
  test(int.low+1 .. int.high)
  test(int.low .. int.high-1)
  test(int.low .. 0)
  test(int.low .. -1)
  test(int.low .. 1)
  test(int64.low .. 1'i64)
  test(10'u64 .. uint64.high)

block: # bug #17670
  type UInt48 = range[0'u64..2'u64^48-1]
  let x = rand(UInt48)
  doAssert x is UInt48

block: # bug #17898
  # Checks whether `initRand()` generates unique states.
  # size should be 2^64, but we don't have time and space.

  # Disable this test for js until js gets proper skipRandomNumbers.
  when not defined(js):
    const size = 1000
    var
      rands: array[size, Rand]
      randSet: HashSet[Rand]
    for i in 0..<size:
      rands[i] = initRand()
      randSet.incl rands[i]

    doAssert randSet.len == size

    # Checks random number sequences overlapping.
    const numRepeat = 100
    for i in 0..<size:
      for j in 0..<numRepeat:
        discard rands[i].next
        doAssert rands[i] notin randSet

block: # bug #22360
  const size = 1000
  var fc = 0
  var tc = 0

  for _ in 1..size:
    let s = rand(bool)

    if s:
      inc tc
    else:
      inc fc

  when defined(js) and not compileOption("jsbigint64"):
    doAssert (tc, fc) == (515, 485), $(tc, fc)
  else:
    doAssert (tc, fc) == (510, 490), $(tc, fc)

block:
  when defined(js) and not compileOption("jsbigint64"):
    doAssert rand(int32.high) == 335507522
  else:
    doAssert rand(int32.high) == 607539621

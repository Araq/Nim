#
#
#            Nim's Runtime Library
#        (c) Copyright 2017 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Nim's standard random number generator (RNG).
##
## Its implementation is based on the `xoroshiro128+`
## (xor/rotate/shift/rotate) library.
## * More information: https://xoroshiro.di.unimi.it
## * C implementation: https://xoroshiro.di.unimi.it/xoroshiro128plus.c
##
## **Do not use this module for cryptographic purposes!**
##
## Basic usage
## ===========
##
runnableExamples:
  # Call randomize() once to initialize the default random number generator.
  # If this is not called, the same results will occur every time these
  # examples are run.
  randomize()

  # Pick a number in 0..100.
  let num = rand(100)
  doAssert num in 0..100

  # Roll a six-sided die.
  let roll = rand(1..6)
  doAssert roll in 1..6

  # Pick a marble from a bag.
  let marbles = ["red", "blue", "green", "yellow", "purple"]
  let pick = sample(marbles)
  doAssert pick in marbles

  # Shuffle some cards.
  var cards = ["Ace", "King", "Queen", "Jack", "Ten"]
  shuffle(cards)
  doAssert cards.len == 5

## These examples all use the default RNG. The
## `Rand type <#Rand>`_ represents the state of an RNG.
## For convenience, this module contains a default Rand state that corresponds
## to the default RNG. Most procs in this module which do
## not take in a Rand parameter, including those called in the above examples,
## use the default generator. Those procs are **not** thread-safe.
##
## Note that the default generator always starts in the same state.
## The `randomize proc <#randomize>`_ can be called to initialize the default
## generator with a seed based on the current time, and it only needs to be
## called once before the first usage of procs from this module. If
## `randomize` is not called, the default generator will always produce
## the same results.
##
## RNGs that are independent of the default one can be created with the
## `initRand proc <#initRand,int64>`_.
##
## Again, it is important to remember that this module must **not** be used for
## cryptographic applications.
##
## See also
## ========
## * `std/sysrand module <sysrand.html>`_ for a cryptographically secure pseudorandom number generator
## * `math module <math.html>`_ for basic math routines
## * `stats module <stats.html>`_ for statistical analysis
## * `list of cryptographic and hashing modules <lib.html#pure-libraries-hashing>`_
##   in the standard library

import std/[algorithm, math]
import std/private/[since, jsutils]

when defined(nimPreviewSlimSystem):
  import std/[assertions]

include system/inclrtl
{.push debugger: off.}


when hasWorkingInt64:
  type Ui = uint64

  const randMax = 18_446_744_073_709_551_615u64
else:
  type Ui = uint32

  const randMax = 4_294_967_295u32


type
  Rand* = object ## State of a random number generator.
                 ##
                 ## Create a new Rand state using the `initRand proc <#initRand,int64>`_.
                 ##
                 ## The module contains a default Rand state for convenience.
                 ## It corresponds to the default RNG's state.
                 ## The default Rand state always starts with the same values, but the
                 ## `randomize proc <#randomize>`_ can be used to seed the default generator
                 ## with a value based on the current time.
                 ##
                 ## Many procs have two variations: one that takes in a Rand parameter and
                 ## another that uses the default generator. The procs that use the default
                 ## generator are **not** thread-safe!
    a0, a1: Ui

when hasWorkingInt64:
  const DefaultRandSeed = Rand(
    a0: 0x69B4C98CB8530805u64,
    a1: 0xFED1DD3004688D67CAu64)

  # racy for multi-threading but good enough for now:
  var state = DefaultRandSeed # global for backwards compatibility
else:
  var state = Rand(
    a0: 0x69B4C98Cu32,
    a1: 0xFED1DD30u32) # global for backwards compatibility

func isValid(r: Rand): bool {.inline.} =
  ## Check whether state of `r` is valid.
  ##
  ## In `xoroshiro128+`, if all bits of `a0` and `a1` are zero,
  ## they are always zero after calling `next(r: var Rand)`.
  not (r.a0 == 0 and r.a1 == 0)

since (1, 5):
  template randState*(): untyped =
    ## Makes the default Rand state accessible from other modules.
    ## Useful for module authors.
    state

proc rotl(x, k: Ui): Ui =
  result = (x shl k) or (x shr (Ui(64) - k))

proc next*(r: var Rand): uint64 =
  ## Computes a random `uint64` number using the given state.
  ##
  ## **See also:**
  ## * `rand proc<#rand,Rand,Natural>`_ that returns an integer between zero and
  ##   a given upper bound
  ## * `rand proc<#rand,Rand,range[]>`_ that returns a float
  ## * `rand proc<#rand,Rand,HSlice[T: Ordinal or float or float32 or float64,T: Ordinal or float or float32 or float64]>`_
  ##   that accepts a slice
  ## * `rand proc<#rand,typedesc[T]>`_ that accepts an integer or range type
  ## * `skipRandomNumbers proc<#skipRandomNumbers,Rand>`_
  runnableExamples("-r:off"):
    var r = initRand(2019)
    assert r.next() == 13223559681708962501'u64 # implementation defined
    assert r.next() == 7229677234260823147'u64 # ditto

  let s0 = r.a0
  var s1 = r.a1
  result = s0 + s1
  s1 = s1 xor s0
  r.a0 = rotl(s0, 55) xor s1 xor (s1 shl 14) # a, b
  r.a1 = rotl(s1, 36) # c

proc skipRandomNumbers*(s: var Rand) =
  ## The jump function for the generator.
  ##
  ## This proc is equivalent to `2^64` calls to `next <#next,Rand>`_, and it can
  ## be used to generate `2^64` non-overlapping subsequences for parallel
  ## computations.
  ##
  ## When multiple threads are generating random numbers, each thread must
  ## own the `Rand <#Rand>`_ state it is using so that the thread can safely
  ## obtain random numbers. However, if each thread creates its own Rand state,
  ## the subsequences of random numbers that each thread generates may overlap,
  ## even if the provided seeds are unique. This is more likely to happen as the
  ## number of threads and amount of random numbers generated increases.
  ##
  ## If many threads will generate random numbers concurrently, it is better to
  ## create a single Rand state and pass it to each thread. After passing the
  ## Rand state to a thread, call this proc before passing it to the next one.
  ## By using the Rand state this way, the subsequences of random numbers
  ## generated in each thread will never overlap as long as no thread generates
  ## more than `2^64` random numbers.
  ##
  ## **See also:**
  ## * `next proc<#next,Rand>`_
  runnableExamples("--threads:on"):
    import std/random

    const numbers = 100000

    var
      thr: array[0..3, Thread[(Rand, int)]]
      vals: array[0..3, int]

    proc randomSum(params: tuple[r: Rand, index: int]) {.thread.} =
      var r = params.r
      var s = 0 # avoid cache thrashing
      for i in 1..numbers:
        s += r.rand(0..10)
      vals[params.index] = s

    var r = initRand(2019)
    for i in 0..<thr.len:
      createThread(thr[i], randomSum, (r, i))
      r.skipRandomNumbers()

    joinThreads(thr)

    for val in vals:
      doAssert abs(val - numbers * 5) / numbers < 0.1

    doAssert vals == [501737, 497901, 500683, 500157]


  when hasWorkingInt64:
    const helper = [0xbeac0467eba5facbu64, 0xd86b048b86aa9922u64]
  else:
    const helper = [0xbeac0467u32, 0xd86b048bu32]
  var
    s0 = Ui 0
    s1 = Ui 0
  for i in 0..high(helper):
    for b in 0 ..< 64:
      if (helper[i] and (Ui(1) shl Ui(b))) != 0:
        s0 = s0 xor s.a0
        s1 = s1 xor s.a1
      discard next(s)
  s.a0 = s0
  s.a1 = s1

proc rand[T: uint | uint64](r: var Rand; max: T): T =
  # xxx export in future work
  result = default(T)
  if max == 0: return
  else:
    let max = uint64(max)
    when T.high.uint64 == uint64.high:
      if max == uint64.high: return T(next(r))
    var iters = 0
    while true:
      let x = next(r)
      # avoid `mod` bias
      if x <= randMax - (randMax mod max) or iters > 20:
        return T(x mod (max + 1))
      else:
        inc iters

proc rand*(r: var Rand; max: Natural): int {.benign.} =
  ## Returns a random integer in the range `0..max` using the given state.
  ##
  ## **See also:**
  ## * `rand proc<#rand,int>`_ that returns an integer using the default RNG
  ## * `rand proc<#rand,Rand,range[]>`_ that returns a float
  ## * `rand proc<#rand,Rand,HSlice[T: Ordinal or float or float32 or float64,T: Ordinal or float or float32 or float64]>`_
  ##   that accepts a slice
  ## * `rand proc<#rand,typedesc[T]>`_ that accepts an integer or range type
  runnableExamples:
    var r = initRand(123)
    if false:
      assert r.rand(100) == 96 # implementation defined
  # bootstrap: can't use `runnableExamples("-r:off")`
  cast[int](rand(r, uint64(max)))
    # xxx toUnsigned pending https://github.com/nim-lang/Nim/pull/18445

proc rand*(max: int): int {.benign.} =
  ## Returns a random integer in the range `0..max`.
  ##
  ## If `randomize <#randomize>`_ has not been called, the sequence of random
  ## numbers returned from this proc will always be the same.
  ##
  ## This proc uses the default RNG. Thus, it is **not** thread-safe.
  ##
  ## **See also:**
  ## * `rand proc<#rand,Rand,Natural>`_ that returns an integer using a
  ##   provided state
  ## * `rand proc<#rand,float>`_ that returns a float
  ## * `rand proc<#rand,HSlice[T: Ordinal or float or float32 or float64,T: Ordinal or float or float32 or float64]>`_
  ##   that accepts a slice
  ## * `rand proc<#rand,typedesc[T]>`_ that accepts an integer or range type
  runnableExamples("-r:off"):
    randomize(123)
    assert [rand(100), rand(100)] == [96, 63] # implementation defined

  rand(state, max)

proc rand*(r: var Rand; max: range[0.0 .. high(float)]): float {.benign.} =
  ## Returns a random floating point number in the range `0.0..max`
  ## using the given state.
  ##
  ## **See also:**
  ## * `rand proc<#rand,float>`_ that returns a float using the default RNG
  ## * `rand proc<#rand,Rand,Natural>`_ that returns an integer
  ## * `rand proc<#rand,Rand,HSlice[T: Ordinal or float or float32 or float64,T: Ordinal or float or float32 or float64]>`_
  ##   that accepts a slice
  ## * `rand proc<#rand,typedesc[T]>`_ that accepts an integer or range type
  runnableExamples:
    var r = initRand(234)
    let f = r.rand(1.0) # 8.717181376738381e-07

  let x = next(r)
  when defined(js):
    when compiles(compileOption("jsbigint64")):
      when compileOption("jsbigint64"):
        result = (float(x) / float(high(uint64))) * max
      else:
        result = (float(x) / float(high(uint32))) * max
    else:
      result = (float(x) / float(high(uint32))) * max
  else:
    let u = (0x3FFu64 shl 52u64) or (x shr 12u64)
    result = (cast[float](u) - 1.0) * max

proc rand*(max: float): float {.benign.} =
  ## Returns a random floating point number in the range `0.0..max`.
  ##
  ## If `randomize <#randomize>`_ has not been called, the sequence of random
  ## numbers returned from this proc will always be the same.
  ##
  ## This proc uses the default RNG. Thus, it is **not** thread-safe.
  ##
  ## **See also:**
  ## * `rand proc<#rand,Rand,range[]>`_ that returns a float using a
  ##   provided state
  ## * `rand proc<#rand,int>`_ that returns an integer
  ## * `rand proc<#rand,HSlice[T: Ordinal or float or float32 or float64,T: Ordinal or float or float32 or float64]>`_
  ##   that accepts a slice
  ## * `rand proc<#rand,typedesc[T]>`_ that accepts an integer or range type
  runnableExamples:
    randomize(234)
    let f = rand(1.0) # 8.717181376738381e-07

  rand(state, max)

proc rand*[T: Ordinal or SomeFloat](r: var Rand; x: HSlice[T, T]): T =
  ## For a slice `a..b`, returns a value in the range `a..b` using the given
  ## state.
  ##
  ## Allowed types for `T` are integers, floats, and enums without holes.
  ##
  ## **See also:**
  ## * `rand proc<#rand,HSlice[T: Ordinal or float or float32 or float64,T: Ordinal or float or float32 or float64]>`_
  ##   that accepts a slice and uses the default RNG
  ## * `rand proc<#rand,Rand,Natural>`_ that returns an integer
  ## * `rand proc<#rand,Rand,range[]>`_ that returns a float
  ## * `rand proc<#rand,typedesc[T]>`_ that accepts an integer or range type
  runnableExamples:
    var r = initRand(345)
    assert r.rand(1..5) <= 5
    assert r.rand(-1.1 .. 1.2) >= -1.1
  assert x.a <= x.b
  when T is SomeFloat:
    result = rand(r, x.b - x.a) + x.a
  else: # Integers and Enum types
    when jsNoBigInt64:
      result = cast[T](rand(r, cast[uint](x.b) - cast[uint](x.a)) + cast[uint](x.a))
    else:
      result = cast[T](rand(r, cast[uint64](x.b) - cast[uint64](x.a)) + cast[uint64](x.a))

proc rand*[T: Ordinal or SomeFloat](x: HSlice[T, T]): T =
  ## For a slice `a..b`, returns a value in the range `a..b`.
  ##
  ## Allowed types for `T` are integers, floats, and enums without holes.
  ##
  ## If `randomize <#randomize>`_ has not been called, the sequence of random
  ## numbers returned from this proc will always be the same.
  ##
  ## This proc uses the default RNG. Thus, it is **not** thread-safe.
  ##
  ## **See also:**
  ## * `rand proc<#rand,Rand,HSlice[T: Ordinal or float or float32 or float64,T: Ordinal or float or float32 or float64]>`_
  ##   that accepts a slice and uses a provided state
  ## * `rand proc<#rand,int>`_ that returns an integer
  ## * `rand proc<#rand,float>`_ that returns a floating point number
  ## * `rand proc<#rand,typedesc[T]>`_ that accepts an integer or range type
  runnableExamples:
    randomize(345)
    assert rand(1..6) <= 6

  result = rand(state, x)

proc rand*[T: Ordinal](r: var Rand; t: typedesc[T]): T {.since: (1, 7, 1).} =
  ## Returns a random Ordinal in the range `low(T)..high(T)`.
  ##
  ## If `randomize <#randomize>`_ has not been called, the sequence of random
  ## numbers returned from this proc will always be the same.
  ##
  ## **See also:**
  ## * `rand proc<#rand,int>`_ that returns an integer
  ## * `rand proc<#rand,float>`_ that returns a floating point number
  ## * `rand proc<#rand,HSlice[T: Ordinal or float or float32 or float64,T: Ordinal or float or float32 or float64]>`_
  ##   that accepts a slice
  when T is range or T is enum:
    result = rand(r, low(T)..high(T))
  elif T is bool:
    result = r.next < randMax div 2
  else:
    when jsNoBigInt64:
      result = cast[T](r.next shr (sizeof(uint)*8 - sizeof(T)*8))
    else:
      result = cast[T](r.next shr (sizeof(uint64)*8 - sizeof(T)*8))

proc rand*[T: Ordinal](t: typedesc[T]): T =
  ## Returns a random Ordinal in the range `low(T)..high(T)`.
  ##
  ## If `randomize <#randomize>`_ has not been called, the sequence of random
  ## numbers returned from this proc will always be the same.
  ##
  ## This proc uses the default RNG. Thus, it is **not** thread-safe.
  ##
  ## **See also:**
  ## * `rand proc<#rand,int>`_ that returns an integer
  ## * `rand proc<#rand,float>`_ that returns a floating point number
  ## * `rand proc<#rand,HSlice[T: Ordinal or float or float32 or float64,T: Ordinal or float or float32 or float64]>`_
  ##   that accepts a slice
  runnableExamples:
    randomize(567)
    type E = enum a, b, c, d

    assert rand(E) in a..d
    assert rand(char) in low(char)..high(char)
    assert rand(int8) in low(int8)..high(int8)
    assert rand(uint32) in low(uint32)..high(uint32)
    assert rand(range[1..16]) in 1..16

  result = rand(state, t)

proc sample*[T](r: var Rand; s: set[T]): T =
  ## Returns a random element from the set `s` using the given state.
  ##
  ## **See also:**
  ## * `sample proc<#sample,set[T]>`_ that uses the default RNG
  ## * `sample proc<#sample,Rand,openArray[T]>`_ for `openArray`s
  ## * `sample proc<#sample,Rand,openArray[T],openArray[U]>`_ that uses a
  ##   cumulative distribution function
  runnableExamples:
    var r = initRand(987)
    let s = {1, 3, 5, 7, 9}
    assert r.sample(s) in s

  assert card(s) != 0
  var i = rand(r, card(s) - 1)
  for e in s:
    if i == 0: return e
    dec(i)

proc sample*[T](s: set[T]): T =
  ## Returns a random element from the set `s`.
  ##
  ## If `randomize <#randomize>`_ has not been called, the order of outcomes
  ## from this proc will always be the same.
  ##
  ## This proc uses the default RNG. Thus, it is **not** thread-safe.
  ##
  ## **See also:**
  ## * `sample proc<#sample,Rand,set[T]>`_ that uses a provided state
  ## * `sample proc<#sample,openArray[T]>`_ for `openArray`s
  ## * `sample proc<#sample,openArray[T],openArray[U]>`_ that uses a
  ##   cumulative distribution function
  runnableExamples:
    randomize(987)
    let s = {1, 3, 5, 7, 9}
    assert sample(s) in s

  sample(state, s)

proc sample*[T](r: var Rand; a: openArray[T]): T =
  ## Returns a random element from `a` using the given state.
  ##
  ## **See also:**
  ## * `sample proc<#sample,openArray[T]>`_ that uses the default RNG
  ## * `sample proc<#sample,Rand,openArray[T],openArray[U]>`_ that uses a
  ##   cumulative distribution function
  ## * `sample proc<#sample,Rand,set[T]>`_ for sets
  runnableExamples:
    let marbles = ["red", "blue", "green", "yellow", "purple"]
    var r = initRand(456)
    assert r.sample(marbles) in marbles

  result = a[r.rand(a.low..a.high)]

proc sample*[T](a: openArray[T]): lent T =
  ## Returns a random element from `a`.
  ##
  ## If `randomize <#randomize>`_ has not been called, the order of outcomes
  ## from this proc will always be the same.
  ##
  ## This proc uses the default RNG. Thus, it is **not** thread-safe.
  ##
  ## **See also:**
  ## * `sample proc<#sample,Rand,openArray[T]>`_ that uses a provided state
  ## * `sample proc<#sample,openArray[T],openArray[U]>`_ that uses a
  ##   cumulative distribution function
  ## * `sample proc<#sample,set[T]>`_ for sets
  runnableExamples:
    let marbles = ["red", "blue", "green", "yellow", "purple"]
    randomize(456)
    assert sample(marbles) in marbles

  result = a[rand(a.low..a.high)]

proc sample*[T, U](r: var Rand; a: openArray[T]; cdf: openArray[U]): T =
  ## Returns an element from `a` using a cumulative distribution function
  ## (CDF) and the given state.
  ##
  ## The `cdf` argument does not have to be normalized, and it could contain
  ## any type of elements that can be converted to a `float`. It must be
  ## the same length as `a`. Each element in `cdf` should be greater than
  ## or equal to the previous element.
  ##
  ## The outcome of the `cumsum<math.html#cumsum,openArray[T]>`_ proc and the
  ## return value of the `cumsummed<math.html#cumsummed,openArray[T]>`_ proc,
  ## which are both in the math module, can be used as the `cdf` argument.
  ##
  ## **See also:**
  ## * `sample proc<#sample,openArray[T],openArray[U]>`_ that also utilizes
  ##   a CDF but uses the default RNG
  ## * `sample proc<#sample,Rand,openArray[T]>`_ that does not use a CDF
  ## * `sample proc<#sample,Rand,set[T]>`_ for sets
  runnableExamples:
    from std/math import cumsummed

    let marbles = ["red", "blue", "green", "yellow", "purple"]
    let count = [1, 6, 8, 3, 4]
    let cdf = count.cumsummed
    var r = initRand(789)
    assert r.sample(marbles, cdf) in marbles

  assert(cdf.len == a.len) # Two basic sanity checks.
  assert(float(cdf[^1]) > 0.0)
  # While we could check cdf[i-1] <= cdf[i] for i in 1..cdf.len, that could get
  # awfully expensive even in debugging modes.
  let u = r.rand(float(cdf[^1]))
  a[cdf.upperBound(U(u))]

proc sample*[T, U](a: openArray[T]; cdf: openArray[U]): T =
  ## Returns an element from `a` using a cumulative distribution function
  ## (CDF).
  ##
  ## This proc works similarly to
  ## `sample <#sample,Rand,openArray[T],openArray[U]>`_.
  ## See that proc's documentation for more details.
  ##
  ## If `randomize <#randomize>`_ has not been called, the order of outcomes
  ## from this proc will always be the same.
  ##
  ## This proc uses the default RNG. Thus, it is **not** thread-safe.
  ##
  ## **See also:**
  ## * `sample proc<#sample,Rand,openArray[T],openArray[U]>`_ that also utilizes
  ##   a CDF but uses a provided state
  ## * `sample proc<#sample,openArray[T]>`_ that does not use a CDF
  ## * `sample proc<#sample,set[T]>`_ for sets
  runnableExamples:
    from std/math import cumsummed

    let marbles = ["red", "blue", "green", "yellow", "purple"]
    let count = [1, 6, 8, 3, 4]
    let cdf = count.cumsummed
    randomize(789)
    assert sample(marbles, cdf) in marbles

  state.sample(a, cdf)

proc gauss*(r: var Rand; mu = 0.0; sigma = 1.0): float {.since: (1, 3).} =
  ## Returns a Gaussian random variate,
  ## with mean `mu` and standard deviation `sigma`
  ## using the given state.
  # Ratio of uniforms method for normal
  # https://www2.econ.osaka-u.ac.jp/~tanizaki/class/2013/econome3/13.pdf
  const K = sqrt(2 / E)
  var
    a = 0.0
    b = 0.0
  while true:
    a = rand(r, 1.0)
    b = (2.0 * rand(r, 1.0) - 1.0) * K
    if  b * b <= -4.0 * a * a * ln(a): break
  result = mu + sigma * (b / a)

proc gauss*(mu = 0.0, sigma = 1.0): float {.since: (1, 3).} =
  ## Returns a Gaussian random variate,
  ## with mean `mu` and standard deviation `sigma`.
  ##
  ## If `randomize <#randomize>`_ has not been called, the order of outcomes
  ## from this proc will always be the same.
  ##
  ## This proc uses the default RNG. Thus, it is **not** thread-safe.
  result = gauss(state, mu, sigma)

proc initRand*(seed: int64): Rand =
  ## Initializes a new `Rand <#Rand>`_ state using the given seed.
  ##
  ## Providing a specific seed will produce the same results for that seed each time.
  ##
  ## The resulting state is independent of the default RNG's state. When `seed == 0`,
  ## we internally set the seed to an implementation defined non-zero value.
  ##
  ## **See also:**
  ## * `initRand proc<#initRand>`_ that uses the current time
  ## * `randomize proc<#randomize,int64>`_ that accepts a seed for the default RNG
  ## * `randomize proc<#randomize>`_ that initializes the default RNG using the current time
  runnableExamples:
    from std/times import getTime, toUnix, nanosecond

    var r1 = initRand(123)
    let now = getTime()
    var r2 = initRand(now.toUnix * 1_000_000_000 + now.nanosecond)
  const seedFallback0 = int32.high # arbitrary
  let seed = if seed != 0: seed else: seedFallback0 # because 0 is a fixed point
  result.a0 = Ui(seed shr 16)
  result.a1 = Ui(seed and 0xffff)
  when not defined(nimLegacyRandomInitRand):
    # calling `discard next(result)` (even a few times) would still produce
    # skewed numbers for the 1st call to `rand()`.
    skipRandomNumbers(result)
  discard next(result)

proc randomize*(seed: int64) {.benign.} =
  ## Initializes the default random number generator with the given seed.
  ##
  ## Providing a specific seed will produce the same results for that seed each time.
  ##
  ## **See also:**
  ## * `initRand proc<#initRand,int64>`_ that initializes a Rand state
  ##   with a given seed
  ## * `randomize proc<#randomize>`_ that uses the current time instead
  ## * `initRand proc<#initRand>`_ that initializes a Rand state using
  ##   the current time
  runnableExamples:
    from std/times import getTime, toUnix, nanosecond

    randomize(123)

    let now = getTime()
    randomize(now.toUnix * 1_000_000_000 + now.nanosecond)

  state = initRand(seed)

proc shuffle*[T](r: var Rand; x: var openArray[T]) =
  ## Shuffles a sequence of elements in-place using the given state.
  ##
  ## **See also:**
  ## * `shuffle proc<#shuffle,openArray[T]>`_ that uses the default RNG
  runnableExamples:
    var cards = ["Ace", "King", "Queen", "Jack", "Ten"]
    var r = initRand(678)
    r.shuffle(cards)
    import std/algorithm
    assert cards.sorted == @["Ace", "Jack", "King", "Queen", "Ten"]

  for i in countdown(x.high, 1):
    let j = r.rand(i)
    swap(x[i], x[j])

proc shuffle*[T](x: var openArray[T]) =
  ## Shuffles a sequence of elements in-place.
  ##
  ## If `randomize <#randomize>`_ has not been called, the order of outcomes
  ## from this proc will always be the same.
  ##
  ## This proc uses the default RNG. Thus, it is **not** thread-safe.
  ##
  ## **See also:**
  ## * `shuffle proc<#shuffle,Rand,openArray[T]>`_ that uses a provided state
  runnableExamples:
    var cards = ["Ace", "King", "Queen", "Jack", "Ten"]
    randomize(678)
    shuffle(cards)
    import std/algorithm
    assert cards.sorted == @["Ace", "Jack", "King", "Queen", "Ten"]

  shuffle(state, x)

when not defined(standalone):
  when defined(js):
    import std/times
  else:
    when defined(nimscript):
      import std/hashes
    else:
      import std/[hashes, os, sysrand, monotimes]

      when compileOption("threads"):
        import std/locks
        var baseSeedLock: Lock
        baseSeedLock.initLock

    var baseState: Rand

  proc initRand(): Rand =
    ## Initializes a new Rand state.
    ##
    ## The resulting state is independent of the default RNG's state.
    ##
    ## **Note:** Does not work for the compile-time VM.
    ##
    ## See also:
    ## * `initRand proc<#initRand,int64>`_ that accepts a seed for a new Rand state
    ## * `randomize proc<#randomize>`_ that initializes the default RNG using the current time
    ## * `randomize proc<#randomize,int64>`_ that accepts a seed for the default RNG
    when defined(js):
      let time = int64(times.epochTime() * 1000) and 0x7fff_ffff
      result = initRand(time)
    else:
      proc getRandomState(): Rand =
        when defined(nimscript):
          result = Rand(
            a0: CompileTime.hash.Ui,
            a1: CompileDate.hash.Ui)
          if not result.isValid:
            result = DefaultRandSeed
        else:
          var urand: array[sizeof(Rand), byte]

          for i in 0 .. 7:
            if sysrand.urandom(urand):
              copyMem(result.addr, urand[0].addr, sizeof(Rand))
              if result.isValid:
                break

          if not result.isValid:
            # Don't try to get alternative random values from other source like time or process/thread id,
            # because such code would be never tested and is a liability for security.
            quit("Failed to initializes baseState in random module as sysrand.urandom doesn't work.")

      when compileOption("threads"):
        baseSeedLock.withLock:
          if not baseState.isValid:
            baseState = getRandomState()
          result = baseState
          baseState.skipRandomNumbers
      else:
        if not baseState.isValid:
          baseState = getRandomState()
        result = baseState
        baseState.skipRandomNumbers

  since (1, 5, 1):
    export initRand

  proc randomize*() {.benign.} =
    ## Initializes the default random number generator with a seed based on
    ## random number source.
    ##
    ## This proc only needs to be called once, and it should be called before
    ## the first usage of procs from this module that use the default RNG.
    ##
    ## **Note:** Does not work for the compile-time VM.
    ##
    ## **See also:**
    ## * `randomize proc<#randomize,int64>`_ that accepts a seed
    ## * `initRand proc<#initRand>`_ that initializes a Rand state using
    ##   the current time
    ## * `initRand proc<#initRand,int64>`_ that initializes a Rand state
    ##   with a given seed
    state = initRand()

{.pop.}

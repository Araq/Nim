discard """
  # test C with -d:nimUseCppAtomics as well to check nothing breaks
  matrix: "--mm:refc; --mm:orc; --mm:refc -d:nimUseCppAtomics; --mm:orc -d:nimUseCppAtomics"
  targets: "c cpp"
"""

# test atomic operations

import std/[atomics, bitops]
import std/assertions


type
  Object = object
    val: int


# Atomic operations for trivial objects


block trivialLoad:
  var location: Atomic[int]
  location.store(1)
  doAssert location.load == 1
  location.store(2)
  doAssert location.load(moRelaxed) == 2
  location.store(3)
  doAssert location.load(moAcquire) == 3


block trivialStore:
  var location: Atomic[int]
  location.store(1)
  doAssert location.load == 1
  location.store(2, moRelaxed)
  doAssert location.load == 2
  location.store(3, moRelease)
  doAssert location.load == 3


block trivialExchange:
  var location: Atomic[int]
  location.store(1)
  doAssert location.exchange(2) == 1
  doAssert location.exchange(3, moRelaxed) == 2
  doAssert location.exchange(4, moAcquire) == 3
  doAssert location.exchange(5, moRelease) == 4
  doAssert location.exchange(6, moAcquireRelease) == 5
  doAssert location.load == 6


block trivialCompareExchangeDoesExchange:
  var location: Atomic[int]
  var expected = 1
  location.store(1)
  doAssert location.compareExchange(expected, 2)
  doAssert expected == 1
  doAssert location.load == 2
  expected = 2
  doAssert location.compareExchange(expected, 3, moRelaxed)
  doAssert expected == 2
  doAssert location.load == 3
  expected = 3
  doAssert location.compareExchange(expected, 4, moAcquire)
  doAssert expected == 3
  doAssert location.load == 4
  expected = 4
  doAssert location.compareExchange(expected, 5, moRelease)
  doAssert expected == 4
  doAssert location.load == 5
  expected = 5
  doAssert location.compareExchange(expected, 6, moAcquireRelease)
  doAssert expected == 5
  doAssert location.load == 6


block trivialCompareExchangeDoesNotExchange:
  var location: Atomic[int]
  var expected = 10
  location.store(1)
  doAssert not location.compareExchange(expected, 2)
  doAssert expected == 1
  doAssert location.load == 1
  expected = 10
  doAssert not location.compareExchange(expected, 3, moRelaxed)
  doAssert expected == 1
  doAssert location.load == 1
  expected = 10
  doAssert not location.compareExchange(expected, 4, moAcquire)
  doAssert expected == 1
  doAssert location.load == 1
  expected = 10
  doAssert not location.compareExchange(expected, 5, moRelease)
  doAssert expected == 1
  doAssert location.load == 1
  expected = 10
  doAssert not location.compareExchange(expected, 6, moAcquireRelease)
  doAssert expected == 1
  doAssert location.load == 1


block trivialCompareExchangeSuccessFailureDoesExchange:
  var location: Atomic[int]
  var expected = 1
  location.store(1)
  doAssert location.compareExchange(expected, 2, moSequentiallyConsistent, moSequentiallyConsistent)
  doAssert expected == 1
  doAssert location.load == 2
  expected = 2
  doAssert location.compareExchange(expected, 3, moRelaxed, moRelaxed)
  doAssert expected == 2
  doAssert location.load == 3
  expected = 3
  doAssert location.compareExchange(expected, 4, moAcquire, moAcquire)
  doAssert expected == 3
  doAssert location.load == 4
  expected = 4
  doAssert location.compareExchange(expected, 5, moRelease, moRelease)
  doAssert expected == 4
  doAssert location.load == 5
  expected = 5
  doAssert location.compareExchange(expected, 6, moAcquireRelease, moAcquireRelease)
  doAssert expected == 5
  doAssert location.load == 6


block trivialCompareExchangeSuccessFailureDoesNotExchange:
  var location: Atomic[int]
  var expected = 10
  location.store(1)
  doAssert not location.compareExchange(expected, 2, moSequentiallyConsistent, moSequentiallyConsistent)
  doAssert expected == 1
  doAssert location.load == 1
  expected = 10
  doAssert not location.compareExchange(expected, 3, moRelaxed, moRelaxed)
  doAssert expected == 1
  doAssert location.load == 1
  expected = 10
  doAssert not location.compareExchange(expected, 4, moAcquire, moAcquire)
  doAssert expected == 1
  doAssert location.load == 1
  expected = 10
  doAssert not location.compareExchange(expected, 5, moRelease, moRelease)
  doAssert expected == 1
  doAssert location.load == 1
  expected = 10
  doAssert not location.compareExchange(expected, 6, moAcquireRelease, moAcquireRelease)
  doAssert expected == 1
  doAssert location.load == 1


block trivialCompareExchangeWeakDoesExchange:
  var location: Atomic[int]
  var expected = 1
  location.store(1)
  doAssert location.compareExchangeWeak(expected, 2)
  doAssert expected == 1
  doAssert location.load == 2
  expected = 2
  doAssert location.compareExchangeWeak(expected, 3, moRelaxed)
  doAssert expected == 2
  doAssert location.load == 3
  expected = 3
  doAssert location.compareExchangeWeak(expected, 4, moAcquire)
  doAssert expected == 3
  doAssert location.load == 4
  expected = 4
  doAssert location.compareExchangeWeak(expected, 5, moRelease)
  doAssert expected == 4
  doAssert location.load == 5
  expected = 5
  doAssert location.compareExchangeWeak(expected, 6, moAcquireRelease)
  doAssert expected == 5
  doAssert location.load == 6


block trivialCompareExchangeWeakDoesNotExchange:
  var location: Atomic[int]
  var expected = 10
  location.store(1)
  doAssert not location.compareExchangeWeak(expected, 2)
  doAssert expected == 1
  doAssert location.load == 1
  expected = 10
  doAssert not location.compareExchangeWeak(expected, 3, moRelaxed)
  doAssert expected == 1
  doAssert location.load == 1
  expected = 10
  doAssert not location.compareExchangeWeak(expected, 4, moAcquire)
  doAssert expected == 1
  doAssert location.load == 1
  expected = 10
  doAssert not location.compareExchangeWeak(expected, 5, moRelease)
  doAssert expected == 1
  doAssert location.load == 1
  expected = 10
  doAssert not location.compareExchangeWeak(expected, 6, moAcquireRelease)
  doAssert expected == 1
  doAssert location.load == 1


block trivialCompareExchangeWeakSuccessFailureDoesExchange:
  var location: Atomic[int]
  var expected = 1
  location.store(1)
  doAssert location.compareExchangeWeak(expected, 2, moSequentiallyConsistent, moSequentiallyConsistent)
  doAssert expected == 1
  doAssert location.load == 2
  expected = 2
  doAssert location.compareExchangeWeak(expected, 3, moRelaxed, moRelaxed)
  doAssert expected == 2
  doAssert location.load == 3
  expected = 3
  doAssert location.compareExchangeWeak(expected, 4, moAcquire, moAcquire)
  doAssert expected == 3
  doAssert location.load == 4
  expected = 4
  doAssert location.compareExchangeWeak(expected, 5, moRelease, moRelease)
  doAssert expected == 4
  doAssert location.load == 5
  expected = 5
  doAssert location.compareExchangeWeak(expected, 6, moAcquireRelease, moAcquireRelease)
  doAssert expected == 5
  doAssert location.load == 6


block trivialCompareExchangeWeakSuccessFailureDoesNotExchange:
  var location: Atomic[int]
  var expected = 10
  location.store(1)
  doAssert not location.compareExchangeWeak(expected, 2, moSequentiallyConsistent, moSequentiallyConsistent)
  doAssert expected == 1
  doAssert location.load == 1
  expected = 10
  doAssert not location.compareExchangeWeak(expected, 3, moRelaxed, moRelaxed)
  doAssert expected == 1
  doAssert location.load == 1
  expected = 10
  doAssert not location.compareExchangeWeak(expected, 4, moAcquire, moAcquire)
  doAssert expected == 1
  doAssert location.load == 1
  expected = 10
  doAssert not location.compareExchangeWeak(expected, 5, moRelease, moRelease)
  doAssert expected == 1
  doAssert location.load == 1
  expected = 10
  doAssert not location.compareExchangeWeak(expected, 6, moAcquireRelease, moAcquireRelease)
  doAssert expected == 1
  doAssert location.load == 1


# Atomic operations for non-trivial objects


block objectLoad:
  var location: Atomic[Object]
  location.store(Object(val: 1))
  doAssert location.load == Object(val: 1)
  location.store(Object(val: 2))
  doAssert location.load(moRelaxed) == Object(val: 2)
  location.store(Object(val: 3))
  doAssert location.load(moAcquire) == Object(val: 3)


block objectStore:
  var location: Atomic[Object]
  location.store(Object(val: 1))
  doAssert location.load == Object(val: 1)
  location.store(Object(val: 2), moRelaxed)
  doAssert location.load == Object(val: 2)
  location.store(Object(val: 3), moRelease)
  doAssert location.load == Object(val: 3)


block objectExchange:
  var location: Atomic[Object]
  location.store(Object(val: 1))
  doAssert location.exchange(Object(val: 2)) == Object(val: 1)
  doAssert location.exchange(Object(val: 3), moRelaxed) == Object(val: 2)
  doAssert location.exchange(Object(val: 4), moAcquire) == Object(val: 3)
  doAssert location.exchange(Object(val: 5), moRelease) == Object(val: 4)
  doAssert location.exchange(Object(val: 6), moAcquireRelease) == Object(val: 5)
  doAssert location.load == Object(val: 6)


block objectCompareExchangeDoesExchange:
  var location: Atomic[Object]
  var expected = Object(val: 1)
  location.store(Object(val: 1))
  doAssert location.compareExchange(expected, Object(val: 2))
  doAssert expected == Object(val: 1)
  doAssert location.load == Object(val: 2)
  expected = Object(val: 2)
  doAssert location.compareExchange(expected, Object(val: 3), moRelaxed)
  doAssert expected == Object(val: 2)
  doAssert location.load == Object(val: 3)
  expected = Object(val: 3)
  doAssert location.compareExchange(expected, Object(val: 4), moAcquire)
  doAssert expected == Object(val: 3)
  doAssert location.load == Object(val: 4)
  expected = Object(val: 4)
  doAssert location.compareExchange(expected, Object(val: 5), moRelease)
  doAssert expected == Object(val: 4)
  doAssert location.load == Object(val: 5)
  expected = Object(val: 5)
  doAssert location.compareExchange(expected, Object(val: 6), moAcquireRelease)
  doAssert expected == Object(val: 5)
  doAssert location.load == Object(val: 6)


block objectCompareExchangeDoesNotExchange:
  var location: Atomic[Object]
  var expected = Object(val: 10)
  location.store(Object(val: 1))
  doAssert not location.compareExchange(expected, Object(val: 2))
  doAssert expected == Object(val: 1)
  doAssert location.load == Object(val: 1)
  expected = Object(val: 10)
  doAssert not location.compareExchange(expected, Object(val: 3), moRelaxed)
  doAssert expected == Object(val: 1)
  doAssert location.load == Object(val: 1)
  expected = Object(val: 10)
  doAssert not location.compareExchange(expected, Object(val: 4), moAcquire)
  doAssert expected == Object(val: 1)
  doAssert location.load == Object(val: 1)
  expected = Object(val: 10)
  doAssert not location.compareExchange(expected, Object(val: 5), moRelease)
  doAssert expected == Object(val: 1)
  doAssert location.load == Object(val: 1)
  expected = Object(val: 10)
  doAssert not location.compareExchange(expected, Object(val: 6), moAcquireRelease)
  doAssert expected == Object(val: 1)
  doAssert location.load == Object(val: 1)


block objectCompareExchangeSuccessFailureDoesExchange:
  var location: Atomic[Object]
  var expected = Object(val: 1)
  location.store(Object(val: 1))
  doAssert location.compareExchange(expected, Object(val: 2), moSequentiallyConsistent, moSequentiallyConsistent)
  doAssert expected == Object(val: 1)
  doAssert location.load == Object(val: 2)
  expected = Object(val: 2)
  doAssert location.compareExchange(expected, Object(val: 3), moRelaxed, moRelaxed)
  doAssert expected == Object(val: 2)
  doAssert location.load == Object(val: 3)
  expected = Object(val: 3)
  doAssert location.compareExchange(expected, Object(val: 4), moAcquire, moAcquire)
  doAssert expected == Object(val: 3)
  doAssert location.load == Object(val: 4)
  expected = Object(val: 4)
  doAssert location.compareExchange(expected, Object(val: 5), moRelease, moRelease)
  doAssert expected == Object(val: 4)
  doAssert location.load == Object(val: 5)
  expected = Object(val: 5)
  doAssert location.compareExchange(expected, Object(val: 6), moAcquireRelease, moAcquireRelease)
  doAssert expected == Object(val: 5)
  doAssert location.load == Object(val: 6)


block objectCompareExchangeSuccessFailureDoesNotExchange:
  var location: Atomic[Object]
  var expected = Object(val: 10)
  location.store(Object(val: 1))
  doAssert not location.compareExchange(expected, Object(val: 2), moSequentiallyConsistent, moSequentiallyConsistent)
  doAssert expected == Object(val: 1)
  doAssert location.load == Object(val: 1)
  expected = Object(val: 10)
  doAssert not location.compareExchange(expected, Object(val: 3), moRelaxed, moRelaxed)
  doAssert expected == Object(val: 1)
  doAssert location.load == Object(val: 1)
  expected = Object(val: 10)
  doAssert not location.compareExchange(expected, Object(val: 4), moAcquire, moAcquire)
  doAssert expected == Object(val: 1)
  doAssert location.load == Object(val: 1)
  expected = Object(val: 10)
  doAssert not location.compareExchange(expected, Object(val: 5), moRelease, moRelease)
  doAssert expected == Object(val: 1)
  doAssert location.load == Object(val: 1)
  expected = Object(val: 10)
  doAssert not location.compareExchange(expected, Object(val: 6), moAcquireRelease, moAcquireRelease)
  doAssert expected == Object(val: 1)
  doAssert location.load == Object(val: 1)


block objectCompareExchangeWeakDoesExchange:
  var location: Atomic[Object]
  var expected = Object(val: 1)
  location.store(Object(val: 1))
  doAssert location.compareExchangeWeak(expected, Object(val: 2))
  doAssert expected == Object(val: 1)
  doAssert location.load == Object(val: 2)
  expected = Object(val: 2)
  doAssert location.compareExchangeWeak(expected, Object(val: 3), moRelaxed)
  doAssert expected == Object(val: 2)
  doAssert location.load == Object(val: 3)
  expected = Object(val: 3)
  doAssert location.compareExchangeWeak(expected, Object(val: 4), moAcquire)
  doAssert expected == Object(val: 3)
  doAssert location.load == Object(val: 4)
  expected = Object(val: 4)
  doAssert location.compareExchangeWeak(expected, Object(val: 5), moRelease)
  doAssert expected == Object(val: 4)
  doAssert location.load == Object(val: 5)
  expected = Object(val: 5)
  doAssert location.compareExchangeWeak(expected, Object(val: 6), moAcquireRelease)
  doAssert expected == Object(val: 5)
  doAssert location.load == Object(val: 6)


block objectCompareExchangeWeakDoesNotExchange:
  var location: Atomic[Object]
  var expected = Object(val: 10)
  location.store(Object(val: 1))
  doAssert not location.compareExchangeWeak(expected, Object(val: 2))
  doAssert expected == Object(val: 1)
  doAssert location.load == Object(val: 1)
  expected = Object(val: 10)
  doAssert not location.compareExchangeWeak(expected, Object(val: 3), moRelaxed)
  doAssert expected == Object(val: 1)
  doAssert location.load == Object(val: 1)
  expected = Object(val: 10)
  doAssert not location.compareExchangeWeak(expected, Object(val: 4), moAcquire)
  doAssert expected == Object(val: 1)
  doAssert location.load == Object(val: 1)
  expected = Object(val: 10)
  doAssert not location.compareExchangeWeak(expected, Object(val: 5), moRelease)
  doAssert expected == Object(val: 1)
  doAssert location.load == Object(val: 1)
  expected = Object(val: 10)
  doAssert not location.compareExchangeWeak(expected, Object(val: 6), moAcquireRelease)
  doAssert expected == Object(val: 1)
  doAssert location.load == Object(val: 1)


block objectCompareExchangeWeakSuccessFailureDoesExchange:
  var location: Atomic[Object]
  var expected = Object(val: 1)
  location.store(Object(val: 1))
  doAssert location.compareExchangeWeak(expected, Object(val: 2), moSequentiallyConsistent, moSequentiallyConsistent)
  doAssert expected == Object(val: 1)
  doAssert location.load == Object(val: 2)
  expected = Object(val: 2)
  doAssert location.compareExchangeWeak(expected, Object(val: 3), moRelaxed, moRelaxed)
  doAssert expected == Object(val: 2)
  doAssert location.load == Object(val: 3)
  expected = Object(val: 3)
  doAssert location.compareExchangeWeak(expected, Object(val: 4), moAcquire, moAcquire)
  doAssert expected == Object(val: 3)
  doAssert location.load == Object(val: 4)
  expected = Object(val: 4)
  doAssert location.compareExchangeWeak(expected, Object(val: 5), moRelease, moRelease)
  doAssert expected == Object(val: 4)
  doAssert location.load == Object(val: 5)
  expected = Object(val: 5)
  doAssert location.compareExchangeWeak(expected, Object(val: 6), moAcquireRelease, moAcquireRelease)
  doAssert expected == Object(val: 5)
  doAssert location.load == Object(val: 6)


block objectCompareExchangeWeakSuccessFailureDoesNotExchange:
  var location: Atomic[Object]
  var expected = Object(val: 10)
  location.store(Object(val: 1))
  doAssert not location.compareExchangeWeak(expected, Object(val: 2), moSequentiallyConsistent, moSequentiallyConsistent)
  doAssert expected == Object(val: 1)
  doAssert location.load == Object(val: 1)
  expected = Object(val: 10)
  doAssert not location.compareExchangeWeak(expected, Object(val: 3), moRelaxed, moRelaxed)
  doAssert expected == Object(val: 1)
  doAssert location.load == Object(val: 1)
  expected = Object(val: 10)
  doAssert not location.compareExchangeWeak(expected, Object(val: 4), moAcquire, moAcquire)
  doAssert expected == Object(val: 1)
  doAssert location.load == Object(val: 1)
  expected = Object(val: 10)
  doAssert not location.compareExchangeWeak(expected, Object(val: 5), moRelease, moRelease)
  doAssert expected == Object(val: 1)
  doAssert location.load == Object(val: 1)
  expected = Object(val: 10)
  doAssert not location.compareExchangeWeak(expected, Object(val: 6), moAcquireRelease, moAcquireRelease)
  doAssert expected == Object(val: 1)
  doAssert location.load == Object(val: 1)


# Numerical operations


block fetchAdd:
  var location: Atomic[int]
  doAssert location.fetchAdd(1) == 0
  doAssert location.fetchAdd(1, moRelaxed) == 1
  doAssert location.fetchAdd(1, moRelease) == 2
  doAssert location.load == 3


block fetchSub:
  var location: Atomic[int]
  doAssert location.fetchSub(1) == 0
  doAssert location.fetchSub(1, moRelaxed) == -1
  doAssert location.fetchSub(1, moRelease) == -2
  doAssert location.load == -3


block fetchAnd:
  var location: Atomic[int]

  for i in 0..16:
    for j in 0..16:
      location.store(i)
      doAssert(location.fetchAnd(j) == i)
      doAssert(location.load == i.bitand(j))

  for i in 0..16:
    for j in 0..16:
      location.store(i)
      doAssert(location.fetchAnd(j, moRelaxed) == i)
      doAssert(location.load == i.bitand(j))

  for i in 0..16:
    for j in 0..16:
      location.store(i)
      doAssert(location.fetchAnd(j, moRelease) == i)
      doAssert(location.load == i.bitand(j))


block fetchOr:
  var location: Atomic[int]

  for i in 0..16:
    for j in 0..16:
      location.store(i)
      doAssert(location.fetchOr(j) == i)
      doAssert(location.load == i.bitor(j))

  for i in 0..16:
    for j in 0..16:
      location.store(i)
      doAssert(location.fetchOr(j, moRelaxed) == i)
      doAssert(location.load == i.bitor(j))

  for i in 0..16:
    for j in 0..16:
      location.store(i)
      doAssert(location.fetchOr(j, moRelease) == i)
      doAssert(location.load == i.bitor(j))


block fetchXor:
  var location: Atomic[int]

  for i in 0..16:
    for j in 0..16:
      location.store(i)
      doAssert(location.fetchXor(j) == i)
      doAssert(location.load == i.bitxor(j))

  for i in 0..16:
    for j in 0..16:
      location.store(i)
      doAssert(location.fetchXor(j, moRelaxed) == i)
      doAssert(location.load == i.bitxor(j))

  for i in 0..16:
    for j in 0..16:
      location.store(i)
      doAssert(location.fetchXor(j, moRelease) == i)
      doAssert(location.load == i.bitxor(j))


block atomicInc:
  var location: Atomic[int]
  location.atomicInc
  doAssert location.load == 1
  location.atomicInc(1)
  doAssert location.load == 2
  location += 1
  doAssert location.load == 3


block atomicDec:
  var location: Atomic[int]
  location.atomicDec
  doAssert location.load == -1
  location.atomicDec(1)
  doAssert location.load == -2
  location -= 1
  doAssert location.load == -3


# Flag operations


block testAndSet:
  var location: AtomicFlag
  doAssert not location.testAndSet
  doAssert location.testAndSet
  doAssert location.testAndSet
  location.clear()
  doAssert not location.testAndSet(moRelaxed)
  doAssert location.testAndSet(moRelaxed)
  doAssert location.testAndSet(moRelaxed)
  location.clear()
  doAssert not location.testAndSet(moRelease)
  doAssert location.testAndSet(moRelease)
  doAssert location.testAndSet(moRelease)


block clear:
  var location: AtomicFlag
  discard location.testAndSet
  location.clear
  doAssert not location.testAndSet
  location.clear(moRelaxed)
  doAssert not location.testAndSet
  location.clear(moRelease)
  doAssert not location.testAndSet

block: # bug #18844
  when not defined(cpp): # cpp pending pr #18836
    type
      Deprivation = object of RootObj
        memes: Atomic[int]
      Zoomer = object
        dopamine: Deprivation

    block:
      var x = Deprivation()
      var y = Zoomer()
      doAssert x.memes.load == 0
      doAssert y.dopamine.memes.load == 0

    block:
      var x: Deprivation
      var y: Zoomer
      doAssert x.memes.load == 0
      doAssert y.dopamine.memes.load == 0

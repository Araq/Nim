#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## The `packedsets` module implements an efficient `Ordinal` set implemented as a
## `sparse bit set`:idx:.
##
## Supports any Ordinal type.
##
## See also
## ========
## * `sets module <sets.html>`_ for more general hash sets

import std/private/since
import std/hashes

when defined(nimPreviewSlimSystem):
  import std/assertions

type
  BitScalar = uint

const
  InitIntSetSize = 8              # must be a power of two!
  TrunkShift = 9
  BitsPerTrunk = 1 shl TrunkShift # needs to be a power of 2 and
                                  # divisible by 64
  TrunkMask = BitsPerTrunk - 1
  IntsPerTrunk = BitsPerTrunk div (sizeof(BitScalar) * 8)
  IntShift = 5 + ord(sizeof(BitScalar) == 8) # 5 or 6, depending on int width
  IntMask = 1 shl IntShift - 1

type
  Trunk {.acyclic.} = ref object
    next: Trunk                                 # all nodes are connected with this pointer
    key: int                                    # start address at bit 0
    bits: array[0..IntsPerTrunk - 1, BitScalar] # a bit vector

  TrunkSeq = seq[Trunk]

  PackedSet*[A: Ordinal] = object
    ## An efficient set of `Ordinal` types implemented as a sparse bit set.
    elems: int           # only valid for small numbers
    counter, max: int
    head: Trunk
    data: TrunkSeq
    a: array[0..33, int] # profiling shows that 34 elements are enough

proc mustRehash[T](t: T): bool {.inline.} =
  let length = t.max + 1
  assert length > t.counter
  result = (length * 2 < t.counter * 3) or (length - t.counter < 4)

proc nextTry(h, maxHash: Hash, perturb: var Hash): Hash {.inline.} =
  const PERTURB_SHIFT = 5
  var perturb2 = cast[uint](perturb) shr PERTURB_SHIFT
  perturb = cast[Hash](perturb2)
  result = ((5 * h) + 1 + perturb) and maxHash

proc packedSetGet[A](t: PackedSet[A], key: int): Trunk =
  var h = key and t.max
  var perturb = key
  while t.data[h] != nil:
    if t.data[h].key == key:
      return t.data[h]
    h = nextTry(h, t.max, perturb)
  result = nil

proc intSetRawInsert[A](t: PackedSet[A], data: var TrunkSeq, desc: Trunk) =
  var h = desc.key and t.max
  var perturb = desc.key
  while data[h] != nil:
    assert data[h] != desc
    h = nextTry(h, t.max, perturb)
  assert data[h] == nil
  data[h] = desc

proc intSetEnlarge[A](t: var PackedSet[A]) =
  var n: TrunkSeq
  var oldMax = t.max
  t.max = ((t.max + 1) * 2) - 1
  newSeq(n, t.max + 1)
  for i in countup(0, oldMax):
    if t.data[i] != nil: intSetRawInsert(t, n, t.data[i])
  swap(t.data, n)

proc intSetPut[A](t: var PackedSet[A], key: int): Trunk =
  var h = key and t.max
  var perturb = key
  while t.data[h] != nil:
    if t.data[h].key == key:
      return t.data[h]
    h = nextTry(h, t.max, perturb)
  if mustRehash(t): intSetEnlarge(t)
  inc(t.counter)
  h = key and t.max
  perturb = key
  while t.data[h] != nil: h = nextTry(h, t.max, perturb)
  assert t.data[h] == nil
  new(result)
  result.next = t.head
  result.key = key
  t.head = result
  t.data[h] = result

proc bitincl[A](s: var PackedSet[A], key: int) {.inline.} =
  var t = intSetPut(s, key shr TrunkShift)
  var u = key and TrunkMask
  t.bits[u shr IntShift] = t.bits[u shr IntShift] or
      (BitScalar(1) shl (u and IntMask))

proc exclImpl[A](s: var PackedSet[A], key: int) =
  if s.elems <= s.a.len:
    for i in 0..<s.elems:
      if s.a[i] == key:
        s.a[i] = s.a[s.elems - 1]
        dec(s.elems)
        return
  else:
    var t = packedSetGet(s, key shr TrunkShift)
    if t != nil:
      var u = key and TrunkMask
      t.bits[u shr IntShift] = t.bits[u shr IntShift] and
          not(BitScalar(1) shl (u and IntMask))

template dollarImpl(): untyped =
  result = "{"
  for key in items(s):
    if result.len > 1: result.add(", ")
    result.add $key
  result.add("}")

iterator items*[A](s: PackedSet[A]): A {.inline.} =
  ## Iterates over any included element of `s`.
  if s.elems <= s.a.len:
    for i in 0..<s.elems:
      yield A(s.a[i])
  else:
    var r = s.head
    while r != nil:
      var i = 0
      while i <= high(r.bits):
        var w: uint = r.bits[i]
        # taking a copy of r.bits[i] here is correct, because
        # modifying operations are not allowed during traversation
        var j = 0
        while w != 0: # test all remaining bits for zero
          if (w and 1) != 0: # the bit is set!
            yield A((r.key shl TrunkShift) or (i shl IntShift +% j))
          inc(j)
          w = w shr 1
        inc(i)
      r = r.next

proc initPackedSet*[A]: PackedSet[A] =
  ## Returns an empty `PackedSet[A]`.
  ## `A` must be `Ordinal`.
  ##
  ## **See also:**
  ## * `toPackedSet proc <#toPackedSet,openArray[A]>`_
  runnableExamples:
    let a = initPackedSet[int]()
    assert len(a) == 0

    type Id = distinct int
    var ids = initPackedSet[Id]()
    ids.incl(3.Id)

  result = PackedSet[A](
    elems: 0,
    counter: 0,
    max: 0,
    head: nil,
    data: @[])
  #  a: array[0..33, int] # profiling shows that 34 elements are enough

proc contains*[A](s: PackedSet[A], key: A): bool =
  ## Returns true if `key` is in `s`.
  ##
  ## This allows the usage of the `in` operator.
  runnableExamples:
    type ABCD = enum A, B, C, D

    let a = [1, 3, 5].toPackedSet
    assert a.contains(3)
    assert 3 in a
    assert not a.contains(8)
    assert 8 notin a

    let letters = [A, C].toPackedSet
    assert A in letters
    assert C in letters
    assert B notin letters

  if s.elems <= s.a.len:
    result = false
    for i in 0..<s.elems:
      if s.a[i] == ord(key): return true
  else:
    var t = packedSetGet(s, ord(key) shr TrunkShift)
    if t != nil:
      var u = ord(key) and TrunkMask
      result = (t.bits[u shr IntShift] and
                (BitScalar(1) shl (u and IntMask))) != 0
    else:
      result = false

proc incl*[A](s: var PackedSet[A], key: A) =
  ## Includes an element `key` in `s`.
  ##
  ## This doesn't do anything if `key` is already in `s`.
  ##
  ## **See also:**
  ## * `excl proc <#excl,PackedSet[A],A>`_ for excluding an element
  ## * `incl proc <#incl,PackedSet[A],PackedSet[A]>`_ for including a set
  ## * `containsOrIncl proc <#containsOrIncl,PackedSet[A],A>`_
  runnableExamples:
    var a = initPackedSet[int]()
    a.incl(3)
    a.incl(3)
    assert len(a) == 1

  if s.elems <= s.a.len:
    for i in 0..<s.elems:
      if s.a[i] == ord(key): return
    if s.elems < s.a.len:
      s.a[s.elems] = ord(key)
      inc(s.elems)
      return
    newSeq(s.data, InitIntSetSize)
    s.max = InitIntSetSize - 1
    for i in 0..<s.elems:
      bitincl(s, s.a[i])
    s.elems = s.a.len + 1
    # fall through:
  bitincl(s, ord(key))

proc incl*[A](s: var PackedSet[A], other: PackedSet[A]) =
  ## Includes all elements from `other` into `s`.
  ##
  ## This is the in-place version of `s + other <#+,PackedSet[A],PackedSet[A]>`_.
  ##
  ## **See also:**
  ## * `excl proc <#excl,PackedSet[A],PackedSet[A]>`_ for excluding a set
  ## * `incl proc <#incl,PackedSet[A],A>`_ for including an element
  ## * `containsOrIncl proc <#containsOrIncl,PackedSet[A],A>`_
  runnableExamples:
    var a = [1].toPackedSet
    a.incl([5].toPackedSet)
    assert len(a) == 2
    assert 5 in a

  for item in other.items: incl(s, item)

proc toPackedSet*[A](x: openArray[A]): PackedSet[A] {.since: (1, 3).} =
  ## Creates a new `PackedSet[A]` that contains the elements of `x`.
  ##
  ## Duplicates are removed.
  ##
  ## **See also:**
  ## * `initPackedSet proc <#initPackedSet>`_
  runnableExamples:
    let a = [5, 6, 7, 8, 8].toPackedSet
    assert len(a) == 4
    assert $a == "{5, 6, 7, 8}"

  result = initPackedSet[A]()
  for item in x:
    result.incl(item)

proc containsOrIncl*[A](s: var PackedSet[A], key: A): bool =
  ## Includes `key` in the set `s` and tells if `key` was already in `s`.
  ##
  ## The difference with regards to the `incl proc <#incl,PackedSet[A],A>`_ is
  ## that this proc returns true if `s` already contained `key`. The
  ## proc will return false if `key` was added as a new value to `s` during
  ## this call.
  ##
  ## **See also:**
  ## * `incl proc <#incl,PackedSet[A],A>`_ for including an element
  ## * `missingOrExcl proc <#missingOrExcl,PackedSet[A],A>`_
  runnableExamples:
    var a = initPackedSet[int]()
    assert a.containsOrIncl(3) == false
    assert a.containsOrIncl(3) == true
    assert a.containsOrIncl(4) == false

  if s.elems <= s.a.len:
    for i in 0..<s.elems:
      if s.a[i] == ord(key):
        return true
    incl(s, key)
    result = false
  else:
    var t = packedSetGet(s, ord(key) shr TrunkShift)
    if t != nil:
      var u = ord(key) and TrunkMask
      result = (t.bits[u shr IntShift] and BitScalar(1) shl (u and IntMask)) != 0
      if not result:
        t.bits[u shr IntShift] = t.bits[u shr IntShift] or
            (BitScalar(1) shl (u and IntMask))
    else:
      incl(s, key)
      result = false

proc excl*[A](s: var PackedSet[A], key: A) =
  ## Excludes `key` from the set `s`.
  ##
  ## This doesn't do anything if `key` is not found in `s`.
  ##
  ## **See also:**
  ## * `incl proc <#incl,PackedSet[A],A>`_ for including an element
  ## * `excl proc <#excl,PackedSet[A],PackedSet[A]>`_ for excluding a set
  ## * `missingOrExcl proc <#missingOrExcl,PackedSet[A],A>`_
  runnableExamples:
    var a = [3].toPackedSet
    a.excl(3)
    a.excl(3)
    a.excl(99)
    assert len(a) == 0

  exclImpl[A](s, ord(key))

proc excl*[A](s: var PackedSet[A], other: PackedSet[A]) =
  ## Excludes all elements from `other` from `s`.
  ##
  ## This is the in-place version of `s - other <#-,PackedSet[A],PackedSet[A]>`_.
  ##
  ## **See also:**
  ## * `incl proc <#incl,PackedSet[A],PackedSet[A]>`_ for including a set
  ## * `excl proc <#excl,PackedSet[A],A>`_ for excluding an element
  ## * `missingOrExcl proc <#missingOrExcl,PackedSet[A],A>`_
  runnableExamples:
    var a = [1, 5].toPackedSet
    a.excl([5].toPackedSet)
    assert len(a) == 1
    assert 5 notin a

  for item in other.items:
    excl(s, item)

proc len*[A](s: PackedSet[A]): int {.inline.} =
  ## Returns the number of elements in `s`.
  runnableExamples:
    let a = [1, 3, 5].toPackedSet
    assert len(a) == 3

  if s.elems < s.a.len:
    result = s.elems
  else:
    result = 0
    for _ in s.items:
      # pending bug #11167; when fixed, check each explicit `items` to see if it can be removed
      inc(result)

proc missingOrExcl*[A](s: var PackedSet[A], key: A): bool =
  ## Excludes `key` from the set `s` and tells if `key` was already missing from `s`.
  ##
  ## The difference with regards to the `excl proc <#excl,PackedSet[A],A>`_ is
  ## that this proc returns true if `key` was missing from `s`.
  ## The proc will return false if `key` was in `s` and it was removed
  ## during this call.
  ##
  ## **See also:**
  ## * `excl proc <#excl,PackedSet[A],A>`_ for excluding an element
  ## * `excl proc <#excl,PackedSet[A],PackedSet[A]>`_ for excluding a set
  ## * `containsOrIncl proc <#containsOrIncl,PackedSet[A],A>`_
  runnableExamples:
    var a = [5].toPackedSet
    assert a.missingOrExcl(5) == false
    assert a.missingOrExcl(5) == true

  var count = s.len
  exclImpl(s, ord(key))
  result = count == s.len

proc clear*[A](result: var PackedSet[A]) =
  ## Clears the `PackedSet[A]` back to an empty state.
  runnableExamples:
    var a = [5, 7].toPackedSet
    clear(a)
    assert len(a) == 0

  # setLen(result.data, InitIntSetSize)
  # for i in 0..InitIntSetSize - 1: result.data[i] = nil
  # result.max = InitIntSetSize - 1
  result.data = @[]
  result.max = 0
  result.counter = 0
  result.head = nil
  result.elems = 0

proc isNil*[A](x: PackedSet[A]): bool {.inline.} =
  ## Returns true if `x` is empty, false otherwise.
  runnableExamples:
    var a = initPackedSet[int]()
    assert a.isNil
    a.incl(2)
    assert not a.isNil
    a.excl(2)
    assert a.isNil

  x.head.isNil and x.elems == 0

proc `=copy`*[A](dest: var PackedSet[A], src: PackedSet[A]) =
  ## Copies `src` to `dest`.
  ## `dest` does not need to be initialized by the `initPackedSet proc <#initPackedSet>`_.
  if src.elems <= src.a.len:
    dest.data = @[]
    dest.max = 0
    dest.counter = src.counter
    dest.head = nil
    dest.elems = src.elems
    dest.a = src.a
  else:
    dest.counter = src.counter
    dest.max = src.max
    dest.elems = src.elems
    newSeq(dest.data, src.data.len)

    var it = src.head
    while it != nil:
      var h = it.key and dest.max
      var perturb = it.key
      while dest.data[h] != nil: h = nextTry(h, dest.max, perturb)
      assert dest.data[h] == nil
      var n: Trunk
      new(n)
      n.next = dest.head
      n.key = it.key
      n.bits = it.bits
      dest.head = n
      dest.data[h] = n
      it = it.next

proc assign*[A](dest: var PackedSet[A], src: PackedSet[A]) {.inline, deprecated.} =
  ## Copies `src` to `dest`.
  ## `dest` does not need to be initialized by the `initPackedSet proc <#initPackedSet>`_.
  runnableExamples:
    var
      a = initPackedSet[int]()
      b = initPackedSet[int]()
    b.incl(5)
    b.incl(7)
    a.assign(b)
    assert len(a) == 2
  `=copy`(dest, src)

proc union*[A](s1, s2: PackedSet[A]): PackedSet[A] =
  ## Returns the union of the sets `s1` and `s2`.
  ##
  ## The same as `s1 + s2 <#+,PackedSet[A],PackedSet[A]>`_.
  runnableExamples:
    let
      a = [1, 2, 3].toPackedSet
      b = [3, 4, 5].toPackedSet
      c = union(a, b)
    assert c.len == 5
    assert c == [1, 2, 3, 4, 5].toPackedSet
  result = default(PackedSet[A])
  result.assign(s1)
  incl(result, s2)

proc intersection*[A](s1, s2: PackedSet[A]): PackedSet[A] =
  ## Returns the intersection of the sets `s1` and `s2`.
  ##
  ## The same as `s1 * s2 <#*,PackedSet[A],PackedSet[A]>`_.
  runnableExamples:
    let
      a = [1, 2, 3].toPackedSet
      b = [3, 4, 5].toPackedSet
      c = intersection(a, b)
    assert c.len == 1
    assert c == [3].toPackedSet

  result = initPackedSet[A]()
  for item in s1.items:
    if contains(s2, item):
      incl(result, item)

proc difference*[A](s1, s2: PackedSet[A]): PackedSet[A] =
  ## Returns the difference of the sets `s1` and `s2`.
  ##
  ## The same as `s1 - s2 <#-,PackedSet[A],PackedSet[A]>`_.
  runnableExamples:
    let
      a = [1, 2, 3].toPackedSet
      b = [3, 4, 5].toPackedSet
      c = difference(a, b)
    assert c.len == 2
    assert c == [1, 2].toPackedSet

  result = initPackedSet[A]()
  for item in s1.items:
    if not contains(s2, item):
      incl(result, item)

proc symmetricDifference*[A](s1, s2: PackedSet[A]): PackedSet[A] =
  ## Returns the symmetric difference of the sets `s1` and `s2`.
  runnableExamples:
    let
      a = [1, 2, 3].toPackedSet
      b = [3, 4, 5].toPackedSet
      c = symmetricDifference(a, b)
    assert c.len == 4
    assert c == [1, 2, 4, 5].toPackedSet
  result = default(PackedSet[A])
  result.assign(s1)
  for item in s2.items:
    if containsOrIncl(result, item):
      excl(result, item)

proc `+`*[A](s1, s2: PackedSet[A]): PackedSet[A] {.inline.} =
  ## Alias for `union(s1, s2) <#union,PackedSet[A],PackedSet[A]>`_.
  result = union(s1, s2)

proc `*`*[A](s1, s2: PackedSet[A]): PackedSet[A] {.inline.} =
  ## Alias for `intersection(s1, s2) <#intersection,PackedSet[A],PackedSet[A]>`_.
  result = intersection(s1, s2)

proc `-`*[A](s1, s2: PackedSet[A]): PackedSet[A] {.inline.} =
  ## Alias for `difference(s1, s2) <#difference,PackedSet[A],PackedSet[A]>`_.
  result = difference(s1, s2)

proc disjoint*[A](s1, s2: PackedSet[A]): bool =
  ## Returns true if the sets `s1` and `s2` have no items in common.
  runnableExamples:
    let
      a = [1, 2].toPackedSet
      b = [2, 3].toPackedSet
      c = [3, 4].toPackedSet
    assert disjoint(a, b) == false
    assert disjoint(a, c) == true

  for item in s1.items:
    if contains(s2, item):
      return false
  return true

proc card*[A](s: PackedSet[A]): int {.inline.} =
  ## Alias for `len() <#len,PackedSet[A]>`_.
  ##
  ## Card stands for the [cardinality](https://en.wikipedia.org/wiki/Cardinality)
  ## of a set.
  result = s.len()

proc `<=`*[A](s1, s2: PackedSet[A]): bool =
  ## Returns true if `s1` is a subset of `s2`.
  ##
  ## A subset `s1` has all of its elements in `s2`, but `s2` doesn't necessarily
  ## have more elements than `s1`. That is, `s1` can be equal to `s2`.
  runnableExamples:
    let
      a = [1].toPackedSet
      b = [1, 2].toPackedSet
      c = [1, 3].toPackedSet
    assert a <= b
    assert b <= b
    assert not (c <= b)

  for item in s1.items:
    if not s2.contains(item):
      return false
  return true

proc `<`*[A](s1, s2: PackedSet[A]): bool =
  ## Returns true if `s1` is a proper subset of `s2`.
  ##
  ## A strict or proper subset `s1` has all of its elements in `s2`, but `s2` has
  ## more elements than `s1`.
  runnableExamples:
    let
      a = [1].toPackedSet
      b = [1, 2].toPackedSet
      c = [1, 3].toPackedSet
    assert a < b
    assert not (b < b)
    assert not (c < b)

  return s1 <= s2 and not (s2 <= s1)

proc `==`*[A](s1, s2: PackedSet[A]): bool =
  ## Returns true if both `s1` and `s2` have the same elements and set size.
  runnableExamples:
    assert [1, 2].toPackedSet == [2, 1].toPackedSet
    assert [1, 2].toPackedSet == [2, 1, 2].toPackedSet

  return s1 <= s2 and s2 <= s1

proc `$`*[A](s: PackedSet[A]): string =
  ## Converts `s` to a string.
  runnableExamples:
    let a = [1, 2, 3].toPackedSet
    assert $a == "{1, 2, 3}"

  dollarImpl()

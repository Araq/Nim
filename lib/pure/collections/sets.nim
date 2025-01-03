#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## The `sets` module implements an efficient `hash set`:idx: and
## ordered hash set.
##
## Hash sets are different from the `built in set type
## <manual.html#types-set-type>`_. Sets allow you to store any value that can be
## `hashed <hashes.html>`_ and they don't contain duplicate entries.
##
## Common usages of sets:
## * removing duplicates from a container by converting it with `toHashSet proc
##   <#toHashSet,openArray[A]>`_ (see also `sequtils.deduplicate func
##   <sequtils.html#deduplicate,openArray[T],bool>`_)
## * membership testing
## * mathematical operations on two sets, such as
##   `union <#union,HashSet[A],HashSet[A]>`_,
##   `intersection <#intersection,HashSet[A],HashSet[A]>`_,
##   `difference <#difference,HashSet[A],HashSet[A]>`_, and
##   `symmetric difference <#symmetricDifference,HashSet[A],HashSet[A]>`_
##
## **Examples:**
##
##   ```Nim
##   echo toHashSet([9, 5, 1])     # {9, 1, 5}
##   echo toOrderedSet([9, 5, 1])  # {9, 5, 1}
##
##   let
##     s1 = toHashSet([9, 5, 1])
##     s2 = toHashSet([3, 5, 7])
##
##   echo s1 + s2    # {9, 1, 3, 5, 7}
##   echo s1 - s2    # {1, 9}
##   echo s1 * s2    # {5}
##   echo s1 -+- s2  # {9, 1, 3, 7}
##   ```
##
## Note: The data types declared here have *value semantics*: This means
## that `=` performs a copy of the set.
##
## **See also:**
## * `intsets module <intsets.html>`_ for efficient int sets
## * `tables module <tables.html>`_ for hash tables


import
  std/[hashes, math]

when not defined(nimHasEffectsOf):
  {.pragma: effectsOf.}

{.pragma: myShallow.}
# For "integer-like A" that are too big for intsets/bit-vectors to be practical,
# it would be best to shrink hcode to the same size as the integer.  Larger
# codes should never be needed, and this can pack more entries per cache-line.
# Losing hcode entirely is also possible - if some element value is forbidden.
type
  KeyValuePair[A] = tuple[hcode: Hash, key: A]
  KeyValuePairSeq[A] = seq[KeyValuePair[A]]
  HashSet*[A] {.myShallow.} = object ## \
    ## A generic hash set.
    ##
    ## Use `init proc <#init,HashSet[A]>`_ or `initHashSet proc <#initHashSet>`_
    ## before calling other procs on it.
    data: KeyValuePairSeq[A]
    counter: int

type
  OrderedKeyValuePair[A] = tuple[
    hcode: Hash, next: int, key: A]
  OrderedKeyValuePairSeq[A] = seq[OrderedKeyValuePair[A]]
  OrderedSet*[A] {.myShallow.} = object ## \
    ## A generic hash set that remembers insertion order.
    ##
    ## Use `init proc <#init,OrderedSet[A]>`_ or `initOrderedSet proc
    ## <#initOrderedSet>`_ before calling other procs on it.
    data: OrderedKeyValuePairSeq[A]
    counter, first, last: int
  SomeSet*[A] = HashSet[A] | OrderedSet[A]
    ## Type union representing `HashSet` or `OrderedSet`.

const
  defaultInitialSize* = 64

include setimpl

# ---------------------------------------------------------------------
# ------------------------------ HashSet ------------------------------
# ---------------------------------------------------------------------


proc init*[A](s: var HashSet[A], initialSize = defaultInitialSize) =
  ## Initializes a hash set.
  ##
  ## Starting from Nim v0.20, sets are initialized by default and it is
  ## not necessary to call this function explicitly.
  ##
  ## You can call this proc on a previously initialized hash set, which will
  ## discard all its values. This might be more convenient than iterating over
  ## existing values and calling `excl() <#excl,HashSet[A],A>`_ on them.
  ##
  ## See also:
  ## * `initHashSet proc <#initHashSet>`_
  ## * `toHashSet proc <#toHashSet,openArray[A]>`_
  runnableExamples:
    var a: HashSet[int]
    init(a)

  initImpl(s, initialSize)

proc initHashSet*[A](initialSize = defaultInitialSize): HashSet[A] =
  ## Wrapper around `init proc <#init,HashSet[A]>`_ for initialization of
  ## hash sets.
  ##
  ## Returns an empty hash set you can assign directly in `var` blocks in a
  ## single line.
  ##
  ## Starting from Nim v0.20, sets are initialized by default and it is
  ## not necessary to call this function explicitly.
  ##
  ## See also:
  ## * `toHashSet proc <#toHashSet,openArray[A]>`_
  runnableExamples:
    var a = initHashSet[int]()
    a.incl(3)
    assert len(a) == 1
  result = default(HashSet[A])
  result.init(initialSize)

proc `[]`*[A](s: var HashSet[A], key: A): var A =
  ## Returns the element that is actually stored in `s` which has the same
  ## value as `key` or raises the `KeyError` exception.
  ##
  ## This is useful when one overloaded `hash` and `==` but still needs
  ## reference semantics for sharing.
  var hc: Hash
  var index = rawGet(s, key, hc)
  if index >= 0: result = s.data[index].key
  else:
    when compiles($key):
      raise newException(KeyError, "key not found: " & $key)
    else:
      raise newException(KeyError, "key not found")

proc contains*[A](s: HashSet[A], key: A): bool =
  ## Returns true if `key` is in `s`.
  ##
  ## This allows the usage of `in` operator.
  ##
  ## See also:
  ## * `incl proc <#incl,HashSet[A],A>`_
  ## * `containsOrIncl proc <#containsOrIncl,HashSet[A],A>`_
  runnableExamples:
    var values = initHashSet[int]()
    assert(not values.contains(2))
    assert 2 notin values

    values.incl(2)
    assert values.contains(2)
    assert 2 in values

  var hc: Hash
  var index = rawGet(s, key, hc)
  result = index >= 0

proc len*[A](s: HashSet[A]): int =
  ## Returns the number of elements in `s`.
  ##
  ## Due to an implementation detail you can call this proc on variables which
  ## have not been initialized yet. The proc will return zero as the length
  ## then.
  runnableExamples:
    var a: HashSet[string]
    assert len(a) == 0
    let s = toHashSet([3, 5, 7])
    assert len(s) == 3

  result = s.counter

proc card*[A](s: HashSet[A]): int =
  ## Alias for `len() <#len,HashSet[A]>`_.
  ##
  ## Card stands for the `cardinality
  ## <https://en.wikipedia.org/wiki/Cardinality>`_ of a set.
  result = s.counter

proc incl*[A](s: var HashSet[A], key: A) =
  ## Includes an element `key` in `s`.
  ##
  ## This doesn't do anything if `key` is already in `s`.
  ##
  ## See also:
  ## * `excl proc <#excl,HashSet[A],A>`_ for excluding an element
  ## * `incl proc <#incl,HashSet[A],HashSet[A]>`_ for including other set
  ## * `containsOrIncl proc <#containsOrIncl,HashSet[A],A>`_
  runnableExamples:
    var values = initHashSet[int]()
    values.incl(2)
    values.incl(2)
    assert values.len == 1

  inclImpl()

proc incl*[A](s: var HashSet[A], other: HashSet[A]) =
  ## Includes all elements from `other` set into `s` (must be declared as `var`).
  ##
  ## This is the in-place version of `s + other <#+,HashSet[A],HashSet[A]>`_.
  ##
  ## See also:
  ## * `excl proc <#excl,HashSet[A],HashSet[A]>`_ for excluding other set
  ## * `incl proc <#incl,HashSet[A],A>`_ for including an element
  ## * `containsOrIncl proc <#containsOrIncl,HashSet[A],A>`_
  runnableExamples:
    var
      values = toHashSet([1, 2, 3])
      others = toHashSet([3, 4, 5])
    values.incl(others)
    assert values.len == 5

  for item in other: incl(s, item)

proc toHashSet*[A](keys: openArray[A]): HashSet[A] =
  ## Creates a new hash set that contains the members of the given
  ## collection (seq, array, or string) `keys`.
  ##
  ## Duplicates are removed.
  ##
  ## See also:
  ## * `initHashSet proc <#initHashSet>`_
  runnableExamples:
    let
      a = toHashSet([5, 3, 2])
      b = toHashSet("abracadabra")
    assert len(a) == 3
    ## a == {2, 3, 5}
    assert len(b) == 5
    ## b == {'a', 'b', 'c', 'd', 'r'}

  result = initHashSet[A](keys.len)
  for key in items(keys): result.incl(key)

iterator items*[A](s: HashSet[A]): A =
  ## Iterates over elements of the set `s`.
  ##
  ## If you need a sequence with the elements you can use `sequtils.toSeq
  ## template <sequtils.html#toSeq.t,untyped>`_.
  ##
  ##   ```Nim
  ##   type
  ##     pair = tuple[a, b: int]
  ##   var
  ##     a, b = initHashSet[pair]()
  ##   a.incl((2, 3))
  ##   a.incl((3, 2))
  ##   a.incl((2, 3))
  ##   for x, y in a.items:
  ##     b.incl((x - 2, y + 1))
  ##   assert a.len == 2
  ##   echo b
  ##   # --> {(a: 1, b: 3), (a: 0, b: 4)}
  ##   ```
  let length = s.len
  for h in 0 .. high(s.data):
    if isFilled(s.data[h].hcode):
      yield s.data[h].key
      assert(len(s) == length, "the length of the HashSet changed while iterating over it")

proc containsOrIncl*[A](s: var HashSet[A], key: A): bool =
  ## Includes `key` in the set `s` and tells if `key` was already in `s`.
  ##
  ## The difference with regards to the `incl proc <#incl,HashSet[A],A>`_ is
  ## that this proc returns `true` if `s` already contained `key`. The
  ## proc will return `false` if `key` was added as a new value to `s` during
  ## this call.
  ##
  ## See also:
  ## * `incl proc <#incl,HashSet[A],A>`_ for including an element
  ## * `incl proc <#incl,HashSet[A],HashSet[A]>`_ for including other set
  ## * `missingOrExcl proc <#missingOrExcl,HashSet[A],A>`_
  runnableExamples:
    var values = initHashSet[int]()
    assert values.containsOrIncl(2) == false
    assert values.containsOrIncl(2) == true
    assert values.containsOrIncl(3) == false

  containsOrInclImpl()

proc excl*[A](s: var HashSet[A], key: A) =
  ## Excludes `key` from the set `s`.
  ##
  ## This doesn't do anything if `key` is not found in `s`.
  ##
  ## See also:
  ## * `incl proc <#incl,HashSet[A],A>`_ for including an element
  ## * `excl proc <#excl,HashSet[A],HashSet[A]>`_ for excluding other set
  ## * `missingOrExcl proc <#missingOrExcl,HashSet[A],A>`_
  runnableExamples:
    var s = toHashSet([2, 3, 6, 7])
    s.excl(2)
    s.excl(2)
    assert s.len == 3

  discard exclImpl(s, key)

proc excl*[A](s: var HashSet[A], other: HashSet[A]) =
  ## Excludes all elements of `other` set from `s`.
  ##
  ## This is the in-place version of `s - other <#-,HashSet[A],HashSet[A]>`_.
  ##
  ## See also:
  ## * `incl proc <#incl,HashSet[A],HashSet[A]>`_ for including other set
  ## * `excl proc <#excl,HashSet[A],A>`_ for excluding an element
  ## * `missingOrExcl proc <#missingOrExcl,HashSet[A],A>`_
  runnableExamples:
    var
      numbers = toHashSet([1, 2, 3, 4, 5])
      even = toHashSet([2, 4, 6, 8])
    numbers.excl(even)
    assert len(numbers) == 3
    ## numbers == {1, 3, 5}

  for item in other: discard exclImpl(s, item)

proc missingOrExcl*[A](s: var HashSet[A], key: A): bool =
  ## Excludes `key` in the set `s` and tells if `key` was already missing from `s`.
  ##
  ## The difference with regards to the `excl proc <#excl,HashSet[A],A>`_ is
  ## that this proc returns `true` if `key` was missing from `s`.
  ## The proc will return `false` if `key` was in `s` and it was removed
  ## during this call.
  ##
  ## See also:
  ## * `excl proc <#excl,HashSet[A],A>`_ for excluding an element
  ## * `excl proc <#excl,HashSet[A],HashSet[A]>`_ for excluding other set
  ## * `containsOrIncl proc <#containsOrIncl,HashSet[A],A>`_
  runnableExamples:
    var s = toHashSet([2, 3, 6, 7])
    assert s.missingOrExcl(4) == true
    assert s.missingOrExcl(6) == false
    assert s.missingOrExcl(6) == true

  exclImpl(s, key)

proc pop*[A](s: var HashSet[A]): A =
  ## Removes and returns an arbitrary element from the set `s`.
  ##
  ## Raises `KeyError` if the set `s` is empty.
  ##
  ## See also:
  ## * `clear proc <#clear,HashSet[A]>`_
  runnableExamples:
    var s = toHashSet([2, 1])
    assert [s.pop, s.pop] in [[1, 2], [2,1]] # order unspecified
    doAssertRaises(KeyError, echo s.pop)

  for h in 0 .. high(s.data):
    if isFilled(s.data[h].hcode):
      result = s.data[h].key
      excl(s, result)
      return result
  raise newException(KeyError, "set is empty")

proc clear*[A](s: var HashSet[A]) =
  ## Clears the HashSet back to an empty state, without shrinking
  ## any of the existing storage.
  ##
  ## `O(n)` operation, where `n` is the size of the hash bucket.
  ##
  ## See also:
  ## * `pop proc <#pop,HashSet[A]>`_
  runnableExamples:
    var s = toHashSet([3, 5, 7])
    clear(s)
    assert len(s) == 0

  s.counter = 0
  for i in 0 ..< s.data.len:
    s.data[i].hcode = 0
    {.push warning[UnsafeDefault]:off.}
    reset(s.data[i].key)
    {.pop.}


proc union*[A](s1, s2: HashSet[A]): HashSet[A] =
  ## Returns the union of the sets `s1` and `s2`.
  ##
  ## The same as `s1 + s2 <#+,HashSet[A],HashSet[A]>`_.
  ##
  ## The union of two sets is represented mathematically as *A ∪ B* and is the
  ## set of all objects that are members of `s1`, `s2` or both.
  ##
  ## See also:
  ## * `intersection proc <#intersection,HashSet[A],HashSet[A]>`_
  ## * `difference proc <#difference,HashSet[A],HashSet[A]>`_
  ## * `symmetricDifference proc <#symmetricDifference,HashSet[A],HashSet[A]>`_
  runnableExamples:
    let
      a = toHashSet(["a", "b"])
      b = toHashSet(["b", "c"])
      c = union(a, b)
    assert c == toHashSet(["a", "b", "c"])

  result = s1
  incl(result, s2)

proc intersection*[A](s1, s2: HashSet[A]): HashSet[A] =
  ## Returns the intersection of the sets `s1` and `s2`.
  ##
  ## The same as `s1 * s2 <#*,HashSet[A],HashSet[A]>`_.
  ##
  ## The intersection of two sets is represented mathematically as *A ∩ B* and
  ## is the set of all objects that are members of `s1` and `s2` at the same
  ## time.
  ##
  ## See also:
  ## * `union proc <#union,HashSet[A],HashSet[A]>`_
  ## * `difference proc <#difference,HashSet[A],HashSet[A]>`_
  ## * `symmetricDifference proc <#symmetricDifference,HashSet[A],HashSet[A]>`_
  runnableExamples:
    let
      a = toHashSet(["a", "b"])
      b = toHashSet(["b", "c"])
      c = intersection(a, b)
    assert c == toHashSet(["b"])

  result = initHashSet[A](max(min(s1.data.len, s2.data.len), 2))

  # iterate over the elements of the smaller set
  if s1.data.len < s2.data.len:
    for item in s1:
      if item in s2: incl(result, item)
  else:
    for item in s2:
      if item in s1: incl(result, item)


proc difference*[A](s1, s2: HashSet[A]): HashSet[A] =
  ## Returns the difference of the sets `s1` and `s2`.
  ##
  ## The same as `s1 - s2 <#-,HashSet[A],HashSet[A]>`_.
  ##
  ## The difference of two sets is represented mathematically as *A ∖ B* and is
  ## the set of all objects that are members of `s1` and not members of `s2`.
  ##
  ## See also:
  ## * `union proc <#union,HashSet[A],HashSet[A]>`_
  ## * `intersection proc <#intersection,HashSet[A],HashSet[A]>`_
  ## * `symmetricDifference proc <#symmetricDifference,HashSet[A],HashSet[A]>`_
  runnableExamples:
    let
      a = toHashSet(["a", "b"])
      b = toHashSet(["b", "c"])
      c = difference(a, b)
    assert c == toHashSet(["a"])

  result = initHashSet[A]()
  for item in s1:
    if not contains(s2, item):
      incl(result, item)

proc symmetricDifference*[A](s1, s2: HashSet[A]): HashSet[A] =
  ## Returns the symmetric difference of the sets `s1` and `s2`.
  ##
  ## The same as `s1 -+- s2 <#-+-,HashSet[A],HashSet[A]>`_.
  ##
  ## The symmetric difference of two sets is represented mathematically as *A △
  ## B* or *A ⊖ B* and is the set of all objects that are members of `s1` or
  ## `s2` but not both at the same time.
  ##
  ## See also:
  ## * `union proc <#union,HashSet[A],HashSet[A]>`_
  ## * `intersection proc <#intersection,HashSet[A],HashSet[A]>`_
  ## * `difference proc <#difference,HashSet[A],HashSet[A]>`_
  runnableExamples:
    let
      a = toHashSet(["a", "b"])
      b = toHashSet(["b", "c"])
      c = symmetricDifference(a, b)
    assert c == toHashSet(["a", "c"])

  result = s1
  for item in s2:
    if containsOrIncl(result, item): excl(result, item)

proc `+`*[A](s1, s2: HashSet[A]): HashSet[A] {.inline.} =
  ## Alias for `union(s1, s2) <#union,HashSet[A],HashSet[A]>`_.
  result = union(s1, s2)

proc `*`*[A](s1, s2: HashSet[A]): HashSet[A] {.inline.} =
  ## Alias for `intersection(s1, s2) <#intersection,HashSet[A],HashSet[A]>`_.
  result = intersection(s1, s2)

proc `-`*[A](s1, s2: HashSet[A]): HashSet[A] {.inline.} =
  ## Alias for `difference(s1, s2) <#difference,HashSet[A],HashSet[A]>`_.
  result = difference(s1, s2)

proc `-+-`*[A](s1, s2: HashSet[A]): HashSet[A] {.inline.} =
  ## Alias for `symmetricDifference(s1, s2)
  ## <#symmetricDifference,HashSet[A],HashSet[A]>`_.
  result = symmetricDifference(s1, s2)

proc disjoint*[A](s1, s2: HashSet[A]): bool =
  ## Returns `true` if the sets `s1` and `s2` have no items in common.
  runnableExamples:
    let
      a = toHashSet(["a", "b"])
      b = toHashSet(["b", "c"])
    assert disjoint(a, b) == false
    assert disjoint(a, b - a) == true

  for item in s1:
    if item in s2: return false
  return true

proc `<`*[A](s, t: HashSet[A]): bool =
  ## Returns true if `s` is a strict or proper subset of `t`.
  ##
  ## A strict or proper subset `s` has all of its members in `t` but `t` has
  ## more elements than `s`.
  runnableExamples:
    let
      a = toHashSet(["a", "b"])
      b = toHashSet(["b", "c"])
      c = intersection(a, b)
    assert c < a and c < b
    assert(not (a < a))

  s.counter != t.counter and s <= t

proc `<=`*[A](s, t: HashSet[A]): bool =
  ## Returns true if `s` is a subset of `t`.
  ##
  ## A subset `s` has all of its members in `t` and `t` doesn't necessarily
  ## have more members than `s`. That is, `s` can be equal to `t`.
  runnableExamples:
    let
      a = toHashSet(["a", "b"])
      b = toHashSet(["b", "c"])
      c = intersection(a, b)
    assert c <= a and c <= b
    assert a <= a

  result = false
  if s.counter > t.counter: return
  result = true
  for item in items(s):
    if not(t.contains(item)):
      result = false
      return

proc `==`*[A](s, t: HashSet[A]): bool =
  ## Returns true if both `s` and `t` have the same members and set size.
  runnableExamples:
    var
      a = toHashSet([1, 2])
      b = toHashSet([2, 1])
    assert a == b

  s.counter == t.counter and s <= t

proc map*[A, B](data: HashSet[A], op: proc (x: A): B {.closure.}): HashSet[B] {.effectsOf: op.} =
  ## Returns a new set after applying `op` proc on each of the elements of
  ##`data` set.
  ##
  ## You can use this proc to transform the elements from a set.
  runnableExamples:
    let
      a = toHashSet([1, 2, 3])
      b = a.map(proc (x: int): string = $x)
    assert b == toHashSet(["1", "2", "3"])

  result = initHashSet[B]()
  for item in items(data): result.incl(op(item))

proc hash*[A](s: HashSet[A]): Hash =
  ## Hashing of HashSet.
  for h in 0 .. high(s.data):
    result = result xor s.data[h].hcode
  result = !$result

proc `$`*[A](s: HashSet[A]): string =
  ## Converts the set `s` to a string, mostly for logging and printing purposes.
  ##
  ## Don't use this proc for serialization, the representation may change at
  ## any moment and values are not escaped.
  ##
  ## **Examples:**
  ##   ```Nim
  ##   echo toHashSet([2, 4, 5])
  ##   # --> {2, 4, 5}
  ##   echo toHashSet(["no", "esc'aping", "is \" provided"])
  ##   # --> {no, esc'aping, is " provided}
  ##   ```
  dollarImpl()


proc initSet*[A](initialSize = defaultInitialSize): HashSet[A] {.deprecated:
     "Deprecated since v0.20, use 'initHashSet'".} = initHashSet[A](initialSize)

proc toSet*[A](keys: openArray[A]): HashSet[A] {.deprecated:
     "Deprecated since v0.20, use 'toHashSet'".} = toHashSet[A](keys)

proc isValid*[A](s: HashSet[A]): bool {.deprecated:
     "Deprecated since v0.20; sets are initialized by default".} =
  ## Returns `true` if the set has been initialized (with `initHashSet proc
  ## <#initHashSet>`_ or `init proc <#init,HashSet[A]>`_).
  ##
  runnableExamples:
    proc savePreferences(options: HashSet[string]) =
      assert options.isValid, "Pass an initialized set!"
      # Do stuff here, may crash in release builds!
  result = s.data.len > 0



# ---------------------------------------------------------------------
# --------------------------- OrderedSet ------------------------------
# ---------------------------------------------------------------------

template forAllOrderedPairs(yieldStmt: untyped) {.dirty.} =
  if s.data.len > 0:
    var h = s.first
    var idx = 0
    while h >= 0:
      var nxt = s.data[h].next
      if isFilled(s.data[h].hcode):
        yieldStmt
        inc(idx)
      h = nxt


proc init*[A](s: var OrderedSet[A], initialSize = defaultInitialSize) =
  ## Initializes an ordered hash set.
  ##
  ## Starting from Nim v0.20, sets are initialized by default and it is
  ## not necessary to call this function explicitly.
  ##
  ## You can call this proc on a previously initialized hash set, which will
  ## discard all its values. This might be more convenient than iterating over
  ## existing values and calling `excl() <#excl,HashSet[A],A>`_ on them.
  ##
  ## See also:
  ## * `initOrderedSet proc <#initOrderedSet>`_
  ## * `toOrderedSet proc <#toOrderedSet,openArray[A]>`_
  runnableExamples:
    var a: OrderedSet[int]
    init(a)

  initImpl(s, initialSize)

proc initOrderedSet*[A](initialSize = defaultInitialSize): OrderedSet[A] =
  ## Wrapper around `init proc <#init,OrderedSet[A]>`_ for initialization of
  ## ordered hash sets.
  ##
  ## Returns an empty ordered hash set you can assign directly in `var` blocks
  ## in a single line.
  ##
  ## Starting from Nim v0.20, sets are initialized by default and it is
  ## not necessary to call this function explicitly.
  ##
  ## See also:
  ## * `toOrderedSet proc <#toOrderedSet,openArray[A]>`_
  runnableExamples:
    var a = initOrderedSet[int]()
    a.incl(3)
    assert len(a) == 1
  result = OrderedSet[A]()
  result.init(initialSize)

proc toOrderedSet*[A](keys: openArray[A]): OrderedSet[A] =
  ## Creates a new hash set that contains the members of the given
  ## collection (seq, array, or string) `keys`.
  ##
  ## Duplicates are removed.
  ##
  ## See also:
  ## * `initOrderedSet proc <#initOrderedSet>`_
  runnableExamples:
    let
      a = toOrderedSet([5, 3, 2])
      b = toOrderedSet("abracadabra")
    assert len(a) == 3
    ## a == {5, 3, 2} # different than in HashSet
    assert len(b) == 5
    ## b == {'a', 'b', 'r', 'c', 'd'} # different than in HashSet

  result = initOrderedSet[A](keys.len)
  for key in items(keys): result.incl(key)

proc contains*[A](s: OrderedSet[A], key: A): bool =
  ## Returns true if `key` is in `s`.
  ##
  ## This allows the usage of `in` operator.
  ##
  ## See also:
  ## * `incl proc <#incl,OrderedSet[A],A>`_
  ## * `containsOrIncl proc <#containsOrIncl,OrderedSet[A],A>`_
  runnableExamples:
    var values = initOrderedSet[int]()
    assert(not values.contains(2))
    assert 2 notin values

    values.incl(2)
    assert values.contains(2)
    assert 2 in values

  var hc: Hash
  var index = rawGet(s, key, hc)
  result = index >= 0

proc incl*[A](s: var OrderedSet[A], key: A) =
  ## Includes an element `key` in `s`.
  ##
  ## This doesn't do anything if `key` is already in `s`.
  ##
  ## See also:
  ## * `excl proc <#excl,OrderedSet[A],A>`_ for excluding an element
  ## * `incl proc <#incl,HashSet[A],OrderedSet[A]>`_ for including other set
  ## * `containsOrIncl proc <#containsOrIncl,OrderedSet[A],A>`_
  runnableExamples:
    var values = initOrderedSet[int]()
    values.incl(2)
    values.incl(2)
    assert values.len == 1

  inclImpl()

proc incl*[A](s: var HashSet[A], other: OrderedSet[A]) =
  ## Includes all elements from the OrderedSet `other` into
  ## HashSet `s` (must be declared as `var`).
  ##
  ## See also:
  ## * `incl proc <#incl,OrderedSet[A],A>`_ for including an element
  ## * `containsOrIncl proc <#containsOrIncl,OrderedSet[A],A>`_
  runnableExamples:
    var
      values = toHashSet([1, 2, 3])
      others = toOrderedSet([3, 4, 5])
    values.incl(others)
    assert values.len == 5

  for item in items(other): incl(s, item)

proc containsOrIncl*[A](s: var OrderedSet[A], key: A): bool =
  ## Includes `key` in the set `s` and tells if `key` was already in `s`.
  ##
  ## The difference with regards to the `incl proc <#incl,OrderedSet[A],A>`_ is
  ## that this proc returns `true` if `s` already contained `key`. The
  ## proc will return false if `key` was added as a new value to `s` during
  ## this call.
  ##
  ## See also:
  ## * `incl proc <#incl,OrderedSet[A],A>`_ for including an element
  ## * `missingOrExcl proc <#missingOrExcl,OrderedSet[A],A>`_
  runnableExamples:
    var values = initOrderedSet[int]()
    assert values.containsOrIncl(2) == false
    assert values.containsOrIncl(2) == true
    assert values.containsOrIncl(3) == false

  containsOrInclImpl()

proc excl*[A](s: var OrderedSet[A], key: A) =
  ## Excludes `key` from the set `s`. Efficiency: `O(n)`.
  ##
  ## This doesn't do anything if `key` is not found in `s`.
  ##
  ## See also:
  ## * `incl proc <#incl,OrderedSet[A],A>`_ for including an element
  ## * `missingOrExcl proc <#missingOrExcl,OrderedSet[A],A>`_
  runnableExamples:
    var s = toOrderedSet([2, 3, 6, 7])
    s.excl(2)
    s.excl(2)
    assert s.len == 3

  discard exclImpl(s, key)

proc missingOrExcl*[A](s: var OrderedSet[A], key: A): bool =
  ## Excludes `key` in the set `s` and tells if `key` was already missing from `s`.
  ## Efficiency: O(n).
  ##
  ## The difference with regards to the `excl proc <#excl,OrderedSet[A],A>`_ is
  ## that this proc returns `true` if `key` was missing from `s`.
  ## The proc will return `false` if `key` was in `s` and it was removed
  ## during this call.
  ##
  ## See also:
  ## * `excl proc <#excl,OrderedSet[A],A>`_
  ## * `containsOrIncl proc <#containsOrIncl,OrderedSet[A],A>`_
  runnableExamples:
    var s = toOrderedSet([2, 3, 6, 7])
    assert s.missingOrExcl(4) == true
    assert s.missingOrExcl(6) == false
    assert s.missingOrExcl(6) == true

  exclImpl(s, key)

proc clear*[A](s: var OrderedSet[A]) =
  ## Clears the OrderedSet back to an empty state, without shrinking
  ## any of the existing storage.
  ##
  ## `O(n)` operation where `n` is the size of the hash bucket.
  runnableExamples:
    var s = toOrderedSet([3, 5, 7])
    clear(s)
    assert len(s) == 0

  s.counter = 0
  s.first = -1
  s.last = -1
  for i in 0 ..< s.data.len:
    s.data[i].hcode = 0
    s.data[i].next = 0
    {.push warning[UnsafeDefault]:off.}
    reset(s.data[i].key)
    {.pop.}

proc len*[A](s: OrderedSet[A]): int {.inline.} =
  ## Returns the number of elements in `s`.
  ##
  ## Due to an implementation detail you can call this proc on variables which
  ## have not been initialized yet. The proc will return zero as the length
  ## then.
  runnableExamples:
    var a: OrderedSet[string]
    assert len(a) == 0
    let s = toHashSet([3, 5, 7])
    assert len(s) == 3

  result = s.counter

proc card*[A](s: OrderedSet[A]): int {.inline.} =
  ## Alias for `len() <#len,OrderedSet[A]>`_.
  ##
  ## Card stands for the `cardinality
  ## <https://en.wikipedia.org/wiki/Cardinality>`_ of a set.
  result = s.counter

proc `==`*[A](s, t: OrderedSet[A]): bool =
  ## Equality for ordered sets.
  runnableExamples:
    let
      a = toOrderedSet([1, 2])
      b = toOrderedSet([2, 1])
    assert(not (a == b))

  if s.counter != t.counter: return false
  var h = s.first
  var g = t.first
  var compared = 0
  while h >= 0 and g >= 0:
    var nxh = s.data[h].next
    var nxg = t.data[g].next
    if isFilled(s.data[h].hcode) and isFilled(t.data[g].hcode):
      if s.data[h].key == t.data[g].key:
        inc compared
      else:
        return false
    h = nxh
    g = nxg
  result = compared == s.counter

proc hash*[A](s: OrderedSet[A]): Hash =
  ## Hashing of OrderedSet.
  forAllOrderedPairs:
    result = result !& s.data[h].hcode
  result = !$result

proc `$`*[A](s: OrderedSet[A]): string =
  ## Converts the ordered hash set `s` to a string, mostly for logging and
  ## printing purposes.
  ##
  ## Don't use this proc for serialization, the representation may change at
  ## any moment and values are not escaped.
  ##
  ## **Examples:**
  ##   ```Nim
  ##   echo toOrderedSet([2, 4, 5])
  ##   # --> {2, 4, 5}
  ##   echo toOrderedSet(["no", "esc'aping", "is \" provided"])
  ##   # --> {no, esc'aping, is " provided}
  ##   ```
  dollarImpl()



iterator items*[A](s: OrderedSet[A]): A =
  ## Iterates over keys in the ordered set `s` in insertion order.
  ##
  ## If you need a sequence with the elements you can use `sequtils.toSeq
  ## template <sequtils.html#toSeq.t,untyped>`_.
  ##
  ##   ```Nim
  ##   var a = initOrderedSet[int]()
  ##   for value in [9, 2, 1, 5, 1, 8, 4, 2]:
  ##     a.incl(value)
  ##   for value in a.items:
  ##     echo "Got ", value
  ##   # --> Got 9
  ##   # --> Got 2
  ##   # --> Got 1
  ##   # --> Got 5
  ##   # --> Got 8
  ##   # --> Got 4
  ##   ```
  let length = s.len
  forAllOrderedPairs:
    yield s.data[h].key
    assert(len(s) == length, "the length of the OrderedSet changed while iterating over it")

iterator pairs*[A](s: OrderedSet[A]): tuple[a: int, b: A] =
  ## Iterates through (position, value) tuples of OrderedSet `s`.
  runnableExamples:
    let a = toOrderedSet("abracadabra")
    var p = newSeq[(int, char)]()
    for x in pairs(a):
      p.add(x)
    assert p == @[(0, 'a'), (1, 'b'), (2, 'r'), (3, 'c'), (4, 'd')]

  let length = s.len
  forAllOrderedPairs:
    yield (idx, s.data[h].key)
    assert(len(s) == length, "the length of the OrderedSet changed while iterating over it")

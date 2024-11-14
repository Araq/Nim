#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## The `tables` module implements variants of an efficient `hash table`:idx:
## (also often named `dictionary`:idx: in other programming languages) that is
## a mapping from keys to values.
##
## There are several different types of hash tables available:
## * `Table<#Table>`_ is the usual hash table,
## * `OrderedTable<#OrderedTable>`_ is like `Table` but remembers insertion order,
## * `CountTable<#CountTable>`_ is a mapping from a key to its number of occurrences
##
## For consistency with every other data type in Nim these have **value**
## semantics, this means that `=` performs a copy of the hash table.
##
## For `ref semantics<manual.html#types-reference-and-pointer-types>`_
## use their `Ref` variants: `TableRef<#TableRef>`_,
## `OrderedTableRef<#OrderedTableRef>`_, and `CountTableRef<#CountTableRef>`_.
##
## To give an example, when `a` is a `Table`, then `var b = a` gives `b`
## as a new independent table. `b` is initialised with the contents of `a`.
## Changing `b` does not affect `a` and vice versa:

runnableExamples:
  var
    a = {1: "one", 2: "two"}.toTable  # creates a Table
    b = a

  assert a == b

  b[3] = "three"
  assert 3 notin a
  assert 3 in b
  assert a != b

## On the other hand, when `a` is a `TableRef` instead, then changes to `b`
## also affect `a`. Both `a` and `b` **ref** the same data structure:

runnableExamples:
  var
    a = {1: "one", 2: "two"}.newTable  # creates a TableRef
    b = a

  assert a == b

  b[3] = "three"

  assert 3 in a
  assert 3 in b
  assert a == b

##
## ----
##

## # Basic usage


## ## Table
runnableExamples:
  from std/sequtils import zip

  let
    names = ["John", "Paul", "George", "Ringo"]
    years = [1940, 1942, 1943, 1940]

  var beatles = initTable[string, int]()

  for pairs in zip(names, years):
    let (name, birthYear) = pairs
    beatles[name] = birthYear

  assert beatles == {"George": 1943, "Ringo": 1940, "Paul": 1942, "John": 1940}.toTable


  var beatlesByYear = initTable[int, seq[string]]()

  for pairs in zip(years, names):
    let (birthYear, name) = pairs
    if not beatlesByYear.hasKey(birthYear):
      # if a key doesn't exist, we create one with an empty sequence
      # before we can add elements to it
      beatlesByYear[birthYear] = @[]
    beatlesByYear[birthYear].add(name)

  assert beatlesByYear == {1940: @["John", "Ringo"], 1942: @["Paul"], 1943: @["George"]}.toTable

## ## OrderedTable
## `OrderedTable<#OrderedTable>`_ is used when it is important to preserve
## the insertion order of keys.

runnableExamples:
  let
    a = [('z', 1), ('y', 2), ('x', 3)]
    ot = a.toOrderedTable  # ordered tables

  assert $ot == """{'z': 1, 'y': 2, 'x': 3}"""

## ## CountTable
## `CountTable<#CountTable>`_ is useful for counting number of items of some
## container (e.g. string, sequence or array), as it is a mapping where the
## items are the keys, and their number of occurrences are the values.
## For that purpose `toCountTable proc<#toCountTable,openArray[A]>`_
## comes handy:

runnableExamples:
  let myString = "abracadabra"
  let letterFrequencies = toCountTable(myString)
  assert $letterFrequencies == "{'a': 5, 'd': 1, 'b': 2, 'r': 2, 'c': 1}"

## The same could have been achieved by manually iterating over a container
## and increasing each key's value with `inc proc
## <#inc,CountTable[A],A,int>`_:

runnableExamples:
  let myString = "abracadabra"
  var letterFrequencies = initCountTable[char]()
  for c in myString:
    letterFrequencies.inc(c)
  assert $letterFrequencies == "{'d': 1, 'r': 2, 'c': 1, 'a': 5, 'b': 2}"

##
## ----
##

## ## Hashing
##
## If you are using simple standard types like `int` or `string` for the
## keys of the table you won't have any problems, but as soon as you try to use
## a more complex object as a key you will be greeted by a strange compiler
## error:
##
##     Error: type mismatch: got (Person)
##     but expected one of:
##     hashes.hash(x: openArray[A]): Hash
##     hashes.hash(x: int): Hash
##     hashes.hash(x: float): Hash
##
## What is happening here is that the types used for table keys require to have
## a `hash()` proc which will convert them to a `Hash <hashes.html#Hash>`_
## value, and the compiler is listing all the hash functions it knows.
## Additionally there has to be a `==` operator that provides the same
## semantics as its corresponding `hash` proc.
##
## After you add `hash` and `==` for your custom type everything will work.
## Currently, however, `hash` for objects is not defined, whereas
## `system.==` for objects does exist and performs a "deep" comparison (every
## field is compared) which is usually what you want. So in the following
## example implementing only `hash` suffices:

runnableExamples:
  import std/hashes

  type
    Person = object
      firstName, lastName: string

  proc hash(x: Person): Hash =
    ## Piggyback on the already available string hash proc.
    ##
    ## Without this proc nothing works!
    result = x.firstName.hash !& x.lastName.hash
    result = !$result

  var
    salaries = initTable[Person, int]()
    p1, p2: Person

  p1.firstName = "Jon"
  p1.lastName = "Ross"
  salaries[p1] = 30_000

  p2.firstName = "소진"
  p2.lastName = "박"
  salaries[p2] = 45_000

##
## ----
##

## # See also
##
## * `json module<json.html>`_ for table-like structure which allows
##   heterogeneous members
## * `strtabs module<strtabs.html>`_ for efficient hash tables
##   mapping from strings to strings
## * `hashes module<hashes.html>`_ for helper functions for hashing


import std/private/since
import std/[hashes, math, algorithm]


when not defined(nimHasEffectsOf):
  {.pragma: effectsOf.}

type
  KeyValuePair[A, B] = tuple[hcode: Hash, key: A, val: B]
  KeyValuePairSeq[A, B] = seq[KeyValuePair[A, B]]
  Table*[A, B] = object
    ## Generic hash table, consisting of a key-value pair.
    ##
    ## `data` and `counter` are internal implementation details which
    ## can't be accessed.
    ##
    ## For creating an empty Table, use `initTable proc<#initTable>`_.
    data: KeyValuePairSeq[A, B]
    counter: int
  TableRef*[A, B] = ref Table[A, B] ## Ref version of `Table<#Table>`_.
    ##
    ## For creating a new empty TableRef, use `newTable proc
    ## <#newTable>`_.


# ------------------------------ helpers ---------------------------------

# Do NOT move these to tableimpl.nim, because sharedtables uses that
# file and has its own implementation.
template maxHash(t): untyped = high(t.data)
template dataLen(t): untyped = len(t.data)

include tableimpl

proc raiseKeyError[T](key: T) {.noinline, noreturn.} =
  when compiles($key):
    raise newException(KeyError, "key not found: " & $key)
  else:
    raise newException(KeyError, "key not found")

template get(t, key): untyped =
  ## retrieves the value at `t[key]`. The value can be modified.
  ## If `key` is not in `t`, the `KeyError` exception is raised.
  mixin rawGet
  var hc: Hash
  var index = rawGet(t, key, hc)
  if index >= 0: result = t.data[index].val
  else:
    raiseKeyError(key)

proc enlarge[A, B](t: var Table[A, B]) =
  var n: KeyValuePairSeq[A, B]
  newSeq(n, len(t.data) * growthFactor)
  swap(t.data, n)
  for i in countup(0, high(n)):
    let eh = n[i].hcode
    if isFilled(eh):
      var j: Hash = eh and maxHash(t)
      while isFilled(t.data[j].hcode):
        j = nextTry(j, maxHash(t))
      when defined(js):
        rawInsert(t, t.data, n[i].key, n[i].val, eh, j)
      else:
        rawInsert(t, t.data, move n[i].key, move n[i].val, eh, j)




# -------------------------------------------------------------------
# ------------------------------ Table ------------------------------
# -------------------------------------------------------------------

proc initTable*[A, B](initialSize = defaultInitialSize): Table[A, B] =
  ## Creates a new hash table that is empty.
  ##
  ## Starting from Nim v0.20, tables are initialized by default and it is
  ## not necessary to call this function explicitly.
  ##
  ## See also:
  ## * `toTable proc<#toTable,openArray[]>`_
  ## * `newTable proc<#newTable>`_ for creating a `TableRef`
  runnableExamples:
    let
      a = initTable[int, string]()
      b = initTable[char, seq[int]]()
  result = default(Table[A, B])
  initImpl(result, initialSize)

proc `[]=`*[A, B](t: var Table[A, B], key: A, val: sink B) =
  ## Inserts a `(key, value)` pair into `t`.
  ##
  ## See also:
  ## * `[] proc<#[],Table[A,B],A>`_ for retrieving a value of a key
  ## * `hasKeyOrPut proc<#hasKeyOrPut,Table[A,B],A,B>`_
  ## * `mgetOrPut proc<#mgetOrPut,Table[A,B],A,B>`_
  ## * `del proc<#del,Table[A,B],A>`_ for removing a key from the table
  runnableExamples:
    var a = initTable[char, int]()
    a['x'] = 7
    a['y'] = 33
    doAssert a == {'x': 7, 'y': 33}.toTable

  putImpl(enlarge)

proc toTable*[A, B](pairs: openArray[(A, B)]): Table[A, B] =
  ## Creates a new hash table that contains the given `pairs`.
  ##
  ## `pairs` is a container consisting of `(key, value)` tuples.
  ##
  ## See also:
  ## * `initTable proc<#initTable>`_
  ## * `newTable proc<#newTable,openArray[]>`_ for a `TableRef` version
  runnableExamples:
    let a = [('a', 5), ('b', 9)]
    let b = toTable(a)
    assert b == {'a': 5, 'b': 9}.toTable

  result = initTable[A, B](pairs.len)
  for key, val in items(pairs): result[key] = val

proc `[]`*[A, B](t: Table[A, B], key: A): lent B =
  ## Retrieves the value at `t[key]`.
  ##
  ## If `key` is not in `t`, the `KeyError` exception is raised.
  ## One can check with `hasKey proc<#hasKey,Table[A,B],A>`_ whether
  ## the key exists.
  ##
  ## See also:
  ## * `getOrDefault proc<#getOrDefault,Table[A,B],A>`_ to return
  ##   a default value (e.g. zero for int) if the key doesn't exist
  ## * `getOrDefault proc<#getOrDefault,Table[A,B],A,B>`_ to return
  ##   a custom value if the key doesn't exist
  ## * `[]= proc<#[]=,Table[A,B],A,sinkB>`_ for inserting a new
  ##   (key, value) pair in the table
  ## * `hasKey proc<#hasKey,Table[A,B],A>`_ for checking if a key is in
  ##   the table
  runnableExamples:
    let a = {'a': 5, 'b': 9}.toTable
    doAssert a['a'] == 5
    doAssertRaises(KeyError):
      echo a['z']
  get(t, key)

proc `[]`*[A, B](t: var Table[A, B], key: A): var B =
  ## Retrieves the value at `t[key]`. The value can be modified.
  ##
  ## If `key` is not in `t`, the `KeyError` exception is raised.
  ##
  ## See also:
  ## * `getOrDefault proc<#getOrDefault,Table[A,B],A>`_ to return
  ##   a default value (e.g. zero for int) if the key doesn't exist
  ## * `getOrDefault proc<#getOrDefault,Table[A,B],A,B>`_ to return
  ##   a custom value if the key doesn't exist
  ## * `[]= proc<#[]=,Table[A,B],A,sinkB>`_ for inserting a new
  ##   (key, value) pair in the table
  ## * `hasKey proc<#hasKey,Table[A,B],A>`_ for checking if a key is in
  ##   the table
  get(t, key)

proc hasKey*[A, B](t: Table[A, B], key: A): bool =
  ## Returns true if `key` is in the table `t`.
  ##
  ## See also:
  ## * `contains proc<#contains,Table[A,B],A>`_ for use with the `in` operator
  ## * `[] proc<#[],Table[A,B],A>`_ for retrieving a value of a key
  ## * `getOrDefault proc<#getOrDefault,Table[A,B],A>`_ to return
  ##   a default value (e.g. zero for int) if the key doesn't exist
  ## * `getOrDefault proc<#getOrDefault,Table[A,B],A,B>`_ to return
  ##   a custom value if the key doesn't exist
  runnableExamples:
    let a = {'a': 5, 'b': 9}.toTable
    doAssert a.hasKey('a') == true
    doAssert a.hasKey('z') == false

  var hc: Hash
  result = rawGet(t, key, hc) >= 0

proc contains*[A, B](t: Table[A, B], key: A): bool =
  ## Alias of `hasKey proc<#hasKey,Table[A,B],A>`_ for use with
  ## the `in` operator.
  runnableExamples:
    let a = {'a': 5, 'b': 9}.toTable
    doAssert 'b' in a == true
    doAssert a.contains('z') == false

  return hasKey[A, B](t, key)

proc hasKeyOrPut*[A, B](t: var Table[A, B], key: A, val: B): bool =
  ## Returns true if `key` is in the table, otherwise inserts `value`.
  ##
  ## See also:
  ## * `hasKey proc<#hasKey,Table[A,B],A>`_
  ## * `[] proc<#[],Table[A,B],A>`_ for retrieving a value of a key
  ## * `getOrDefault proc<#getOrDefault,Table[A,B],A>`_ to return
  ##   a default value (e.g. zero for int) if the key doesn't exist
  ## * `getOrDefault proc<#getOrDefault,Table[A,B],A,B>`_ to return
  ##   a custom value if the key doesn't exist
  runnableExamples:
    var a = {'a': 5, 'b': 9}.toTable
    if a.hasKeyOrPut('a', 50):
      a['a'] = 99
    if a.hasKeyOrPut('z', 50):
      a['z'] = 99
    doAssert a == {'a': 99, 'b': 9, 'z': 50}.toTable

  hasKeyOrPutImpl(enlarge)

proc getOrDefault*[A, B](t: Table[A, B], key: A): B =
  ## Retrieves the value at `t[key]` if `key` is in `t`. Otherwise, the
  ## default initialization value for type `B` is returned (e.g. 0 for any
  ## integer type).
  ##
  ## See also:
  ## * `[] proc<#[],Table[A,B],A>`_ for retrieving a value of a key
  ## * `hasKey proc<#hasKey,Table[A,B],A>`_
  ## * `hasKeyOrPut proc<#hasKeyOrPut,Table[A,B],A,B>`_
  ## * `mgetOrPut proc<#mgetOrPut,Table[A,B],A,B>`_
  ## * `getOrDefault proc<#getOrDefault,Table[A,B],A,B>`_ to return
  ##   a custom value if the key doesn't exist
  runnableExamples:
    let a = {'a': 5, 'b': 9}.toTable
    doAssert a.getOrDefault('a') == 5
    doAssert a.getOrDefault('z') == 0
  result = default(B)
  getOrDefaultImpl(t, key)

proc getOrDefault*[A, B](t: Table[A, B], key: A, def: B): B =
  ## Retrieves the value at `t[key]` if `key` is in `t`.
  ## Otherwise, `def` is returned.
  ##
  ## See also:
  ## * `[] proc<#[],Table[A,B],A>`_ for retrieving a value of a key
  ## * `hasKey proc<#hasKey,Table[A,B],A>`_
  ## * `hasKeyOrPut proc<#hasKeyOrPut,Table[A,B],A,B>`_
  ## * `mgetOrPut proc<#mgetOrPut,Table[A,B],A,B>`_
  ## * `getOrDefault proc<#getOrDefault,Table[A,B],A>`_ to return
  ##   a default value (e.g. zero for int) if the key doesn't exist
  runnableExamples:
    let a = {'a': 5, 'b': 9}.toTable
    doAssert a.getOrDefault('a', 99) == 5
    doAssert a.getOrDefault('z', 99) == 99
  getOrDefaultImpl(t, key, def)

proc mgetOrPut*[A, B](t: var Table[A, B], key: A, val: B): var B =
  ## Retrieves value at `t[key]` or puts `val` if not present, either way
  ## returning a value which can be modified.
  ##
  ##
  ## Note that while the value returned is of type `var B`,
  ## it is easy to accidentally create a copy of the value at `t[key]`.
  ## Remember that seqs and strings are value types, and therefore
  ## cannot be copied into a separate variable for modification.
  ## See the example below.
  ##
  ## See also:
  ## * `[] proc<#[],Table[A,B],A>`_ for retrieving a value of a key
  ## * `hasKey proc<#hasKey,Table[A,B],A>`_
  ## * `hasKeyOrPut proc<#hasKeyOrPut,Table[A,B],A,B>`_
  ## * `getOrDefault proc<#getOrDefault,Table[A,B],A>`_ to return
  ##   a default value (e.g. zero for int) if the key doesn't exist
  ## * `getOrDefault proc<#getOrDefault,Table[A,B],A,B>`_ to return
  ##   a custom value if the key doesn't exist
  runnableExamples:
    var a = {'a': 5, 'b': 9}.toTable
    doAssert a.mgetOrPut('a', 99) == 5
    doAssert a.mgetOrPut('z', 99) == 99
    doAssert a == {'a': 5, 'b': 9, 'z': 99}.toTable

    # An example of accidentally creating a copy
    var t = initTable[int, seq[int]]()
    # In this example, we expect t[10] to be modified,
    # but it is not.
    var copiedSeq = t.mgetOrPut(10, @[10])
    copiedSeq.add(20)
    doAssert t[10] == @[10]
    # Correct
    t.mgetOrPut(25, @[25]).add(35)
    doAssert t[25] == @[25, 35]

  mgetOrPutImpl(enlarge)

proc mgetOrPut*[A, B](t: var Table[A, B], key: A): var B =
  ## Retrieves the value at `t[key]` or puts the
  ## default initialization value for type `B` (e.g. 0 for any
  ## integer type).
  runnableExamples:
    var a = {'a': 5}.newTable
    doAssert a.mgetOrPut('a') == 5
    a.mgetOrPut('z').inc
    doAssert a == {'a': 5, 'z': 1}.newTable

  mgetOrPutImpl(enlarge)

proc len*[A, B](t: Table[A, B]): int =
  ## Returns the number of keys in `t`.
  runnableExamples:
    let a = {'a': 5, 'b': 9}.toTable
    doAssert len(a) == 2

  result = t.counter

proc add*[A, B](t: var Table[A, B], key: A, val: sink B) {.deprecated:
    "Deprecated since v1.4; it was more confusing than useful, use `[]=`".} =
  ## Puts a new `(key, value)` pair into `t` even if `t[key]` already exists.
  ##
  ## **This can introduce duplicate keys into the table!**
  ##
  ## Use `[]= proc<#[]=,Table[A,B],A,sinkB>`_ for inserting a new
  ## (key, value) pair in the table without introducing duplicates.
  addImpl(enlarge)

template tabMakeEmpty(i) = t.data[i].hcode = 0
template tabCellEmpty(i) = isEmpty(t.data[i].hcode)
template tabCellHash(i)  = t.data[i].hcode

proc del*[A, B](t: var Table[A, B], key: A) =
  ## Deletes `key` from hash table `t`. Does nothing if the key does not exist.
  ##
  ## .. warning:: If duplicate keys were added (via the now deprecated `add` proc),
  ##   this may need to be called multiple times.
  ##
  ## See also:
  ## * `pop proc<#pop,Table[A,B],A,B>`_
  ## * `clear proc<#clear,Table[A,B]>`_ to empty the whole table
  runnableExamples:
    var a = {'a': 5, 'b': 9, 'c': 13}.toTable
    a.del('a')
    doAssert a == {'b': 9, 'c': 13}.toTable
    a.del('z')
    doAssert a == {'b': 9, 'c': 13}.toTable

  delImpl(tabMakeEmpty, tabCellEmpty, tabCellHash)

proc pop*[A, B](t: var Table[A, B], key: A, val: var B): bool =
  ## Deletes the `key` from the table.
  ## Returns `true`, if the `key` existed, and sets `val` to the
  ## mapping of the key. Otherwise, returns `false`, and the `val` is
  ## unchanged.
  ##
  ## .. warning:: If duplicate keys were added (via the now deprecated `add` proc),
  ##   this may need to be called multiple times.
  ##
  ## See also:
  ## * `del proc<#del,Table[A,B],A>`_
  ## * `clear proc<#clear,Table[A,B]>`_ to empty the whole table
  runnableExamples:
    var
      a = {'a': 5, 'b': 9, 'c': 13}.toTable
      i: int
    doAssert a.pop('b', i) == true
    doAssert a == {'a': 5, 'c': 13}.toTable
    doAssert i == 9
    i = 0
    doAssert a.pop('z', i) == false
    doAssert a == {'a': 5, 'c': 13}.toTable
    doAssert i == 0

  var hc: Hash
  var index = rawGet(t, key, hc)
  result = index >= 0
  if result:
    val = move(t.data[index].val)
    delImplIdx(t, index, tabMakeEmpty, tabCellEmpty, tabCellHash)

proc take*[A, B](t: var Table[A, B], key: A, val: var B): bool {.inline.} =
  ## Alias for:
  ## * `pop proc<#pop,Table[A,B],A,B>`_
  pop(t, key, val)

proc clear*[A, B](t: var Table[A, B]) =
  ## Resets the table so that it is empty.
  ##
  ## See also:
  ## * `del proc<#del,Table[A,B],A>`_
  ## * `pop proc<#pop,Table[A,B],A,B>`_
  runnableExamples:
    var a = {'a': 5, 'b': 9, 'c': 13}.toTable
    doAssert len(a) == 3
    clear(a)
    doAssert len(a) == 0

  clearImpl()

proc `$`*[A, B](t: Table[A, B]): string =
  ## The `$` operator for hash tables. Used internally when calling `echo`
  ## on a table.
  dollarImpl()

proc `==`*[A, B](s, t: Table[A, B]): bool =
  ## The `==` operator for hash tables. Returns `true` if the content of both
  ## tables contains the same key-value pairs. Insert order does not matter.
  runnableExamples:
    let
      a = {'a': 5, 'b': 9, 'c': 13}.toTable
      b = {'b': 9, 'c': 13, 'a': 5}.toTable
    doAssert a == b

  equalsImpl(s, t)

proc indexBy*[A, B, C](collection: A, index: proc(x: B): C): Table[C, B] =
  ## Index the collection with the proc provided.
  # TODO: As soon as supported, change collection: A to collection: A[B]
  result = initTable[C, B]()
  for item in collection:
    result[index(item)] = item



template withValue*[A, B](t: var Table[A, B], key: A, value, body: untyped) =
  ## Retrieves the value at `t[key]`.
  ##
  ## `value` can be modified in the scope of the `withValue` call.
  runnableExamples:
    type
      User = object
        name: string
        uid: int

    var t = initTable[int, User]()
    let u = User(name: "Hello", uid: 99)
    t[1] = u

    t.withValue(1, value):
      # block is executed only if `key` in `t`
      value.name = "Nim"
      value.uid = 1314

    t.withValue(2, value):
      value.name = "No"
      value.uid = 521

    assert t[1].name == "Nim"
    assert t[1].uid == 1314

  mixin rawGet
  var hc: Hash = default(Hash)
  var index = rawGet(t, key, hc)
  let hasKey = index >= 0
  if hasKey:
    var value {.inject.} = addr(t.data[index].val)
    body

template withValue*[A, B](t: var Table[A, B], key: A,
                          value, body1, body2: untyped) =
  ## Retrieves the value at `t[key]`.
  ##
  ## `value` can be modified in the scope of the `withValue` call.
  runnableExamples:
    type
      User = object
        name: string
        uid: int

    var t = initTable[int, User]()
    let u = User(name: "Hello", uid: 99)
    t[1] = u

    t.withValue(1, value):
      # block is executed only if `key` in `t`
      value.name = "Nim"
      value.uid = 1314

    t.withValue(521, value):
      doAssert false
    do:
      # block is executed when `key` not in `t`
      t[1314] = User(name: "exist", uid: 521)

    assert t[1].name == "Nim"
    assert t[1].uid == 1314
    assert t[1314].name == "exist"
    assert t[1314].uid == 521

  mixin rawGet
  var hc: Hash
  var index = rawGet(t, key, hc)
  let hasKey = index >= 0
  if hasKey:
    var value {.inject.} = addr(t.data[index].val)
    body1
  else:
    body2


iterator pairs*[A, B](t: Table[A, B]): (A, B) =
  ## Iterates over any `(key, value)` pair in the table `t`.
  ##
  ## See also:
  ## * `mpairs iterator<#mpairs.i,Table[A,B]>`_
  ## * `keys iterator<#keys.i,Table[A,B]>`_
  ## * `values iterator<#values.i,Table[A,B]>`_
  ##
  ## **Examples:**
  ##
  ##   ```Nim
  ##   let a = {
  ##     'o': [1, 5, 7, 9],
  ##     'e': [2, 4, 6, 8]
  ##     }.toTable
  ##
  ##   for k, v in a.pairs:
  ##     echo "key: ", k
  ##     echo "value: ", v
  ##
  ##   # key: e
  ##   # value: [2, 4, 6, 8]
  ##   # key: o
  ##   # value: [1, 5, 7, 9]
  ##   ```
  let L = len(t)
  for h in 0 .. high(t.data):
    if isFilled(t.data[h].hcode):
      yield (t.data[h].key, t.data[h].val)
      assert(len(t) == L, "the length of the table changed while iterating over it")

iterator mpairs*[A, B](t: var Table[A, B]): (A, var B) =
  ## Iterates over any `(key, value)` pair in the table `t` (must be
  ## declared as `var`). The values can be modified.
  ##
  ## See also:
  ## * `pairs iterator<#pairs.i,Table[A,B]>`_
  ## * `mvalues iterator<#mvalues.i,Table[A,B]>`_
  runnableExamples:
    var a = {
      'o': @[1, 5, 7, 9],
      'e': @[2, 4, 6, 8]
      }.toTable
    for k, v in a.mpairs:
      v.add(v[0] + 10)
    doAssert a == {'e': @[2, 4, 6, 8, 12], 'o': @[1, 5, 7, 9, 11]}.toTable

  let L = len(t)
  for h in 0 .. high(t.data):
    if isFilled(t.data[h].hcode):
      yield (t.data[h].key, t.data[h].val)
      assert(len(t) == L, "the length of the table changed while iterating over it")

iterator keys*[A, B](t: Table[A, B]): lent A =
  ## Iterates over any key in the table `t`.
  ##
  ## See also:
  ## * `pairs iterator<#pairs.i,Table[A,B]>`_
  ## * `values iterator<#values.i,Table[A,B]>`_
  runnableExamples:
    var a = {
      'o': @[1, 5, 7, 9],
      'e': @[2, 4, 6, 8]
      }.toTable
    for k in a.keys:
      a[k].add(99)
    doAssert a == {'e': @[2, 4, 6, 8, 99], 'o': @[1, 5, 7, 9, 99]}.toTable

  let L = len(t)
  for h in 0 .. high(t.data):
    if isFilled(t.data[h].hcode):
      yield t.data[h].key
      assert(len(t) == L, "the length of the table changed while iterating over it")

iterator values*[A, B](t: Table[A, B]): lent B =
  ## Iterates over any value in the table `t`.
  ##
  ## See also:
  ## * `pairs iterator<#pairs.i,Table[A,B]>`_
  ## * `keys iterator<#keys.i,Table[A,B]>`_
  ## * `mvalues iterator<#mvalues.i,Table[A,B]>`_
  runnableExamples:
    let a = {
      'o': @[1, 5, 7, 9],
      'e': @[2, 4, 6, 8]
      }.toTable
    for v in a.values:
      doAssert v.len == 4

  let L = len(t)
  for h in 0 .. high(t.data):
    if isFilled(t.data[h].hcode):
      yield t.data[h].val
      assert(len(t) == L, "the length of the table changed while iterating over it")

iterator mvalues*[A, B](t: var Table[A, B]): var B =
  ## Iterates over any value in the table `t` (must be
  ## declared as `var`). The values can be modified.
  ##
  ## See also:
  ## * `mpairs iterator<#mpairs.i,Table[A,B]>`_
  ## * `values iterator<#values.i,Table[A,B]>`_
  runnableExamples:
    var a = {
      'o': @[1, 5, 7, 9],
      'e': @[2, 4, 6, 8]
      }.toTable
    for v in a.mvalues:
      v.add(99)
    doAssert a == {'e': @[2, 4, 6, 8, 99], 'o': @[1, 5, 7, 9, 99]}.toTable

  let L = len(t)
  for h in 0 .. high(t.data):
    if isFilled(t.data[h].hcode):
      yield t.data[h].val
      assert(len(t) == L, "the length of the table changed while iterating over it")

iterator allValues*[A, B](t: Table[A, B]; key: A): B {.deprecated:
    "Deprecated since v1.4; tables with duplicated keys are deprecated".} =
  ## Iterates over any value in the table `t` that belongs to the given `key`.
  ##
  ## Used if you have a table with duplicate keys (as a result of using
  ## `add proc<#add,Table[A,B],A,sinkB>`_).
  ##
  runnableExamples:
    import std/[sequtils, algorithm]

    var a = {'a': 3, 'b': 5}.toTable
    for i in 1..3: a.add('z', 10*i)
    doAssert toSeq(a.pairs).sorted == @[('a', 3), ('b', 5), ('z', 10), ('z', 20), ('z', 30)]
    doAssert sorted(toSeq(a.allValues('z'))) == @[10, 20, 30]
  var h: Hash = genHash(key) and high(t.data)
  let L = len(t)
  while isFilled(t.data[h].hcode):
    if t.data[h].key == key:
      yield t.data[h].val
      assert(len(t) == L, "the length of the table changed while iterating over it")
    h = nextTry(h, high(t.data))



# -------------------------------------------------------------------
# ---------------------------- TableRef -----------------------------
# -------------------------------------------------------------------


proc newTable*[A, B](initialSize = defaultInitialSize): TableRef[A, B] =
  ## Creates a new ref hash table that is empty.
  ##
  ## See also:
  ## * `newTable proc<#newTable,openArray[]>`_ for creating a `TableRef`
  ##   from a collection of `(key, value)` pairs
  ## * `initTable proc<#initTable>`_ for creating a `Table`
  runnableExamples:
    let
      a = newTable[int, string]()
      b = newTable[char, seq[int]]()

  new(result)
  {.noSideEffect.}:
    result[] = initTable[A, B](initialSize)

proc newTable*[A, B](pairs: openArray[(A, B)]): TableRef[A, B] =
  ## Creates a new ref hash table that contains the given `pairs`.
  ##
  ## `pairs` is a container consisting of `(key, value)` tuples.
  ##
  ## See also:
  ## * `newTable proc<#newTable>`_
  ## * `toTable proc<#toTable,openArray[]>`_ for a `Table` version
  runnableExamples:
    let a = [('a', 5), ('b', 9)]
    let b = newTable(a)
    assert b == {'a': 5, 'b': 9}.newTable

  new(result)
  {.noSideEffect.}:
    result[] = toTable[A, B](pairs)

proc newTableFrom*[A, B, C](collection: A, index: proc(x: B): C): TableRef[C, B] =
  ## Index the collection with the proc provided.
  # TODO: As soon as supported, change collection: A to collection: A[B]
  result = newTable[C, B]()
  {.noSideEffect.}:
    for item in collection:
      result[index(item)] = item

proc `[]`*[A, B](t: TableRef[A, B], key: A): var B =
  ## Retrieves the value at `t[key]`.
  ##
  ## If `key` is not in `t`, the  `KeyError` exception is raised.
  ## One can check with `hasKey proc<#hasKey,TableRef[A,B],A>`_ whether
  ## the key exists.
  ##
  ## See also:
  ## * `getOrDefault proc<#getOrDefault,TableRef[A,B],A>`_ to return
  ##   a default value (e.g. zero for int) if the key doesn't exist
  ## * `getOrDefault proc<#getOrDefault,TableRef[A,B],A,B>`_ to return
  ##   a custom value if the key doesn't exist
  ## * `[]= proc<#[]=,TableRef[A,B],A,sinkB>`_ for inserting a new
  ##   (key, value) pair in the table
  ## * `hasKey proc<#hasKey,TableRef[A,B],A>`_ for checking if a key is in
  ##   the table
  runnableExamples:
    let a = {'a': 5, 'b': 9}.newTable
    doAssert a['a'] == 5
    doAssertRaises(KeyError):
      echo a['z']

  result = t[][key]

proc `[]=`*[A, B](t: TableRef[A, B], key: A, val: sink B) =
  ## Inserts a `(key, value)` pair into `t`.
  ##
  ## See also:
  ## * `[] proc<#[],TableRef[A,B],A>`_ for retrieving a value of a key
  ## * `hasKeyOrPut proc<#hasKeyOrPut,TableRef[A,B],A,B>`_
  ## * `mgetOrPut proc<#mgetOrPut,TableRef[A,B],A,B>`_
  ## * `del proc<#del,TableRef[A,B],A>`_ for removing a key from the table
  runnableExamples:
    var a = newTable[char, int]()
    a['x'] = 7
    a['y'] = 33
    doAssert a == {'x': 7, 'y': 33}.newTable

  t[][key] = val

proc hasKey*[A, B](t: TableRef[A, B], key: A): bool =
  ## Returns true if `key` is in the table `t`.
  ##
  ## See also:
  ## * `contains proc<#contains,TableRef[A,B],A>`_ for use with the `in`
  ##   operator
  ## * `[] proc<#[],TableRef[A,B],A>`_ for retrieving a value of a key
  ## * `getOrDefault proc<#getOrDefault,TableRef[A,B],A>`_ to return
  ##   a default value (e.g. zero for int) if the key doesn't exist
  ## * `getOrDefault proc<#getOrDefault,TableRef[A,B],A,B>`_ to return
  ##   a custom value if the key doesn't exist
  runnableExamples:
    let a = {'a': 5, 'b': 9}.newTable
    doAssert a.hasKey('a') == true
    doAssert a.hasKey('z') == false

  result = t[].hasKey(key)

proc contains*[A, B](t: TableRef[A, B], key: A): bool =
  ## Alias of `hasKey proc<#hasKey,TableRef[A,B],A>`_ for use with
  ## the `in` operator.
  runnableExamples:
    let a = {'a': 5, 'b': 9}.newTable
    doAssert 'b' in a == true
    doAssert a.contains('z') == false

  return hasKey[A, B](t, key)

proc hasKeyOrPut*[A, B](t: TableRef[A, B], key: A, val: B): bool =
  ## Returns true if `key` is in the table, otherwise inserts `value`.
  ##
  ## See also:
  ## * `hasKey proc<#hasKey,TableRef[A,B],A>`_
  ## * `[] proc<#[],TableRef[A,B],A>`_ for retrieving a value of a key
  ## * `getOrDefault proc<#getOrDefault,TableRef[A,B],A>`_ to return
  ##   a default value (e.g. zero for int) if the key doesn't exist
  ## * `getOrDefault proc<#getOrDefault,TableRef[A,B],A,B>`_ to return
  ##   a custom value if the key doesn't exist
  runnableExamples:
    var a = {'a': 5, 'b': 9}.newTable
    if a.hasKeyOrPut('a', 50):
      a['a'] = 99
    if a.hasKeyOrPut('z', 50):
      a['z'] = 99
    doAssert a == {'a': 99, 'b': 9, 'z': 50}.newTable

  t[].hasKeyOrPut(key, val)

proc getOrDefault*[A, B](t: TableRef[A, B], key: A): B =
  ## Retrieves the value at `t[key]` if `key` is in `t`. Otherwise, the
  ## default initialization value for type `B` is returned (e.g. 0 for any
  ## integer type).
  ##
  ## See also:
  ## * `[] proc<#[],TableRef[A,B],A>`_ for retrieving a value of a key
  ## * `hasKey proc<#hasKey,TableRef[A,B],A>`_
  ## * `hasKeyOrPut proc<#hasKeyOrPut,TableRef[A,B],A,B>`_
  ## * `mgetOrPut proc<#mgetOrPut,TableRef[A,B],A,B>`_
  ## * `getOrDefault proc<#getOrDefault,TableRef[A,B],A,B>`_ to return
  ##   a custom value if the key doesn't exist
  runnableExamples:
    let a = {'a': 5, 'b': 9}.newTable
    doAssert a.getOrDefault('a') == 5
    doAssert a.getOrDefault('z') == 0

  getOrDefault(t[], key)

proc getOrDefault*[A, B](t: TableRef[A, B], key: A, def: B): B =
  ## Retrieves the value at `t[key]` if `key` is in `t`.
  ## Otherwise, `def` is returned.
  ##
  ## See also:
  ## * `[] proc<#[],TableRef[A,B],A>`_ for retrieving a value of a key
  ## * `hasKey proc<#hasKey,TableRef[A,B],A>`_
  ## * `hasKeyOrPut proc<#hasKeyOrPut,TableRef[A,B],A,B>`_
  ## * `mgetOrPut proc<#mgetOrPut,TableRef[A,B],A,B>`_
  ## * `getOrDefault proc<#getOrDefault,TableRef[A,B],A>`_ to return
  ##   a default value (e.g. zero for int) if the key doesn't exist
  runnableExamples:
    let a = {'a': 5, 'b': 9}.newTable
    doAssert a.getOrDefault('a', 99) == 5
    doAssert a.getOrDefault('z', 99) == 99

  getOrDefault(t[], key, def)

proc mgetOrPut*[A, B](t: TableRef[A, B], key: A, val: B): var B =
  ## Retrieves value at `t[key]` or puts `val` if not present, either way
  ## returning a value which can be modified.
  ##
  ## Note that while the value returned is of type `var B`,
  ## it is easy to accidentally create an copy of the value at `t[key]`.
  ## Remember that seqs and strings are value types, and therefore
  ## cannot be copied into a separate variable for modification.
  ## See the example below.
  ##
  ## See also:
  ## * `[] proc<#[],TableRef[A,B],A>`_ for retrieving a value of a key
  ## * `hasKey proc<#hasKey,TableRef[A,B],A>`_
  ## * `hasKeyOrPut proc<#hasKeyOrPut,TableRef[A,B],A,B>`_
  ## * `getOrDefault proc<#getOrDefault,TableRef[A,B],A>`_ to return
  ##   a default value (e.g. zero for int) if the key doesn't exist
  ## * `getOrDefault proc<#getOrDefault,TableRef[A,B],A,B>`_ to return
  ##   a custom value if the key doesn't exist
  runnableExamples:
    var a = {'a': 5, 'b': 9}.newTable
    doAssert a.mgetOrPut('a', 99) == 5
    doAssert a.mgetOrPut('z', 99) == 99
    doAssert a == {'a': 5, 'b': 9, 'z': 99}.newTable

    # An example of accidentally creating a copy
    var t = newTable[int, seq[int]]()
    # In this example, we expect t[10] to be modified,
    # but it is not.
    var copiedSeq = t.mgetOrPut(10, @[10])
    copiedSeq.add(20)
    doAssert t[10] == @[10]
    # Correct
    t.mgetOrPut(25, @[25]).add(35)
    doAssert t[25] == @[25, 35]
  t[].mgetOrPut(key, val)

proc mgetOrPut*[A, B](t: TableRef[A, B], key: A): var B =
  ## Retrieves the value at `t[key]` or puts the
  ## default initialization value for type `B` (e.g. 0 for any
  ## integer type).
  runnableExamples:
    var a = {'a': 5}.newTable
    doAssert a.mgetOrPut('a') == 5
    a.mgetOrPut('z').inc
    doAssert a == {'a': 5, 'z': 1}.newTable

  t[].mgetOrPut(key)

proc len*[A, B](t: TableRef[A, B]): int =
  ## Returns the number of keys in `t`.
  runnableExamples:
    let a = {'a': 5, 'b': 9}.newTable
    doAssert len(a) == 2

  result = t.counter

proc add*[A, B](t: TableRef[A, B], key: A, val: sink B) {.deprecated:
    "Deprecated since v1.4; it was more confusing than useful, use `[]=`".} =
  ## Puts a new `(key, value)` pair into `t` even if `t[key]` already exists.
  ##
  ## **This can introduce duplicate keys into the table!**
  ##
  ## Use `[]= proc<#[]=,TableRef[A,B],A,sinkB>`_ for inserting a new
  ## (key, value) pair in the table without introducing duplicates.
  t[].add(key, val)

proc del*[A, B](t: TableRef[A, B], key: A) =
  ## Deletes `key` from hash table `t`. Does nothing if the key does not exist.
  ##
  ## .. warning:: If duplicate keys were added (via the now deprecated `add` proc),
  ##   this may need to be called multiple times.
  ##
  ## See also:
  ## * `pop proc<#pop,TableRef[A,B],A,B>`_
  ## * `clear proc<#clear,TableRef[A,B]>`_ to empty the whole table
  runnableExamples:
    var a = {'a': 5, 'b': 9, 'c': 13}.newTable
    a.del('a')
    doAssert a == {'b': 9, 'c': 13}.newTable
    a.del('z')
    doAssert a == {'b': 9, 'c': 13}.newTable

  t[].del(key)

proc pop*[A, B](t: TableRef[A, B], key: A, val: var B): bool =
  ## Deletes the `key` from the table.
  ## Returns `true`, if the `key` existed, and sets `val` to the
  ## mapping of the key. Otherwise, returns `false`, and the `val` is
  ## unchanged.
  ##
  ## .. warning:: If duplicate keys were added (via the now deprecated `add` proc),
  ##   this may need to be called multiple times.
  ##
  ## See also:
  ## * `del proc<#del,TableRef[A,B],A>`_
  ## * `clear proc<#clear,TableRef[A,B]>`_ to empty the whole table
  runnableExamples:
    var
      a = {'a': 5, 'b': 9, 'c': 13}.newTable
      i: int
    doAssert a.pop('b', i) == true
    doAssert a == {'a': 5, 'c': 13}.newTable
    doAssert i == 9
    i = 0
    doAssert a.pop('z', i) == false
    doAssert a == {'a': 5, 'c': 13}.newTable
    doAssert i == 0

  result = t[].pop(key, val)

proc take*[A, B](t: TableRef[A, B], key: A, val: var B): bool {.inline.} =
  ## Alias for:
  ## * `pop proc<#pop,TableRef[A,B],A,B>`_
  pop(t, key, val)

proc clear*[A, B](t: TableRef[A, B]) =
  ## Resets the table so that it is empty.
  ##
  ## See also:
  ## * `del proc<#del,Table[A,B],A>`_
  ## * `pop proc<#pop,Table[A,B],A,B>`_
  runnableExamples:
    var a = {'a': 5, 'b': 9, 'c': 13}.newTable
    doAssert len(a) == 3
    clear(a)
    doAssert len(a) == 0

  clearImpl()

proc `$`*[A, B](t: TableRef[A, B]): string =
  ## The `$` operator for hash tables. Used internally when calling `echo`
  ## on a table.
  dollarImpl()

proc `==`*[A, B](s, t: TableRef[A, B]): bool =
  ## The `==` operator for hash tables. Returns `true` if either both tables
  ## are `nil`, or neither is `nil` and the content of both tables contains the
  ## same key-value pairs. Insert order does not matter.
  runnableExamples:
    let
      a = {'a': 5, 'b': 9, 'c': 13}.newTable
      b = {'b': 9, 'c': 13, 'a': 5}.newTable
    doAssert a == b

  if isNil(s): result = isNil(t)
  elif isNil(t): result = false
  else: equalsImpl(s[], t[])



iterator pairs*[A, B](t: TableRef[A, B]): (A, B) =
  ## Iterates over any `(key, value)` pair in the table `t`.
  ##
  ## See also:
  ## * `mpairs iterator<#mpairs.i,TableRef[A,B]>`_
  ## * `keys iterator<#keys.i,TableRef[A,B]>`_
  ## * `values iterator<#values.i,TableRef[A,B]>`_
  ##
  ## **Examples:**
  ##
  ##   ```Nim
  ##   let a = {
  ##     'o': [1, 5, 7, 9],
  ##     'e': [2, 4, 6, 8]
  ##     }.newTable
  ##
  ##   for k, v in a.pairs:
  ##     echo "key: ", k
  ##     echo "value: ", v
  ##
  ##   # key: e
  ##   # value: [2, 4, 6, 8]
  ##   # key: o
  ##   # value: [1, 5, 7, 9]
  ##   ```
  let L = len(t)
  for h in 0 .. high(t.data):
    if isFilled(t.data[h].hcode):
      yield (t.data[h].key, t.data[h].val)
      assert(len(t) == L, "the length of the table changed while iterating over it")

iterator mpairs*[A, B](t: TableRef[A, B]): (A, var B) =
  ## Iterates over any `(key, value)` pair in the table `t`. The values
  ## can be modified.
  ##
  ## See also:
  ## * `pairs iterator<#pairs.i,TableRef[A,B]>`_
  ## * `mvalues iterator<#mvalues.i,TableRef[A,B]>`_
  runnableExamples:
    let a = {
      'o': @[1, 5, 7, 9],
      'e': @[2, 4, 6, 8]
      }.newTable
    for k, v in a.mpairs:
      v.add(v[0] + 10)
    doAssert a == {'e': @[2, 4, 6, 8, 12], 'o': @[1, 5, 7, 9, 11]}.newTable

  let L = len(t)
  for h in 0 .. high(t.data):
    if isFilled(t.data[h].hcode):
      yield (t.data[h].key, t.data[h].val)
      assert(len(t) == L, "the length of the table changed while iterating over it")

iterator keys*[A, B](t: TableRef[A, B]): lent A =
  ## Iterates over any key in the table `t`.
  ##
  ## See also:
  ## * `pairs iterator<#pairs.i,TableRef[A,B]>`_
  ## * `values iterator<#values.i,TableRef[A,B]>`_
  runnableExamples:
    let a = {
      'o': @[1, 5, 7, 9],
      'e': @[2, 4, 6, 8]
      }.newTable
    for k in a.keys:
      a[k].add(99)
    doAssert a == {'e': @[2, 4, 6, 8, 99], 'o': @[1, 5, 7, 9, 99]}.newTable

  let L = len(t)
  for h in 0 .. high(t.data):
    if isFilled(t.data[h].hcode):
      yield t.data[h].key
      assert(len(t) == L, "the length of the table changed while iterating over it")

iterator values*[A, B](t: TableRef[A, B]): lent B =
  ## Iterates over any value in the table `t`.
  ##
  ## See also:
  ## * `pairs iterator<#pairs.i,TableRef[A,B]>`_
  ## * `keys iterator<#keys.i,TableRef[A,B]>`_
  ## * `mvalues iterator<#mvalues.i,TableRef[A,B]>`_
  runnableExamples:
    let a = {
      'o': @[1, 5, 7, 9],
      'e': @[2, 4, 6, 8]
      }.newTable
    for v in a.values:
      doAssert v.len == 4

  let L = len(t)
  for h in 0 .. high(t.data):
    if isFilled(t.data[h].hcode):
      yield t.data[h].val
      assert(len(t) == L, "the length of the table changed while iterating over it")

iterator mvalues*[A, B](t: TableRef[A, B]): var B =
  ## Iterates over any value in the table `t`. The values can be modified.
  ##
  ## See also:
  ## * `mpairs iterator<#mpairs.i,TableRef[A,B]>`_
  ## * `values iterator<#values.i,TableRef[A,B]>`_
  runnableExamples:
    let a = {
      'o': @[1, 5, 7, 9],
      'e': @[2, 4, 6, 8]
      }.newTable
    for v in a.mvalues:
      v.add(99)
    doAssert a == {'e': @[2, 4, 6, 8, 99], 'o': @[1, 5, 7, 9, 99]}.newTable

  let L = len(t)
  for h in 0 .. high(t.data):
    if isFilled(t.data[h].hcode):
      yield t.data[h].val
      assert(len(t) == L, "the length of the table changed while iterating over it")








# ---------------------------------------------------------------------------
# ------------------------------ OrderedTable -------------------------------
# ---------------------------------------------------------------------------

type
  OrderedKeyValuePair[A, B] = tuple[
    hcode: Hash, next: int, key: A, val: B]
  OrderedKeyValuePairSeq[A, B] = seq[OrderedKeyValuePair[A, B]]
  OrderedTable*[A, B] = object
    ## Hash table that remembers insertion order.
    ##
    ## For creating an empty OrderedTable, use `initOrderedTable proc
    ## <#initOrderedTable>`_.
    data: OrderedKeyValuePairSeq[A, B]
    counter, first, last: int
  OrderedTableRef*[A, B] = ref OrderedTable[A, B] ## Ref version of
    ## `OrderedTable<#OrderedTable>`_.
    ##
    ## For creating a new empty OrderedTableRef, use `newOrderedTable proc
    ## <#newOrderedTable>`_.


# ------------------------------ helpers ---------------------------------

proc rawGetKnownHC[A, B](t: OrderedTable[A, B], key: A, hc: Hash): int =
  rawGetKnownHCImpl()

proc rawGetDeep[A, B](t: OrderedTable[A, B], key: A, hc: var Hash): int {.inline.} =
  rawGetDeepImpl()

proc rawGet[A, B](t: OrderedTable[A, B], key: A, hc: var Hash): int =
  rawGetImpl()

proc rawInsert[A, B](t: var OrderedTable[A, B],
                     data: var OrderedKeyValuePairSeq[A, B],
                     key: A, val: sink B, hc: Hash, h: Hash) =
  rawInsertImpl()
  data[h].next = -1
  if t.first < 0: t.first = h
  if t.last >= 0: data[t.last].next = h
  t.last = h

proc enlarge[A, B](t: var OrderedTable[A, B]) =
  var n: OrderedKeyValuePairSeq[A, B]
  newSeq(n, len(t.data) * growthFactor)
  var h = t.first
  t.first = -1
  t.last = -1
  swap(t.data, n)
  while h >= 0:
    var nxt = n[h].next
    let eh = n[h].hcode
    if isFilled(eh):
      var j: Hash = eh and maxHash(t)
      while isFilled(t.data[j].hcode):
        j = nextTry(j, maxHash(t))
      rawInsert(t, t.data, move n[h].key, move n[h].val, n[h].hcode, j)
    h = nxt

template forAllOrderedPairs(yieldStmt: untyped) {.dirty.} =
  if t.counter > 0:
    var h = t.first
    while h >= 0:
      var nxt = t.data[h].next
      if isFilled(t.data[h].hcode):
        yieldStmt
      h = nxt

# ----------------------------------------------------------------------

proc initOrderedTable*[A, B](initialSize = defaultInitialSize): OrderedTable[A, B] =
  ## Creates a new ordered hash table that is empty.
  ##
  ## Starting from Nim v0.20, tables are initialized by default and it is
  ## not necessary to call this function explicitly.
  ##
  ## See also:
  ## * `toOrderedTable proc<#toOrderedTable,openArray[]>`_
  ## * `newOrderedTable proc<#newOrderedTable>`_ for creating an
  ##   `OrderedTableRef`
  runnableExamples:
    let
      a = initOrderedTable[int, string]()
      b = initOrderedTable[char, seq[int]]()
  result = default(OrderedTable[A, B])
  initImpl(result, initialSize)

proc `[]=`*[A, B](t: var OrderedTable[A, B], key: A, val: sink B) =
  ## Inserts a `(key, value)` pair into `t`.
  ##
  ## See also:
  ## * `[] proc<#[],OrderedTable[A,B],A>`_ for retrieving a value of a key
  ## * `hasKeyOrPut proc<#hasKeyOrPut,OrderedTable[A,B],A,B>`_
  ## * `mgetOrPut proc<#mgetOrPut,OrderedTable[A,B],A,B>`_
  ## * `del proc<#del,OrderedTable[A,B],A>`_ for removing a key from the table
  runnableExamples:
    var a = initOrderedTable[char, int]()
    a['x'] = 7
    a['y'] = 33
    doAssert a == {'x': 7, 'y': 33}.toOrderedTable

  putImpl(enlarge)

proc toOrderedTable*[A, B](pairs: openArray[(A, B)]): OrderedTable[A, B] =
  ## Creates a new ordered hash table that contains the given `pairs`.
  ##
  ## `pairs` is a container consisting of `(key, value)` tuples.
  ##
  ## See also:
  ## * `initOrderedTable proc<#initOrderedTable>`_
  ## * `newOrderedTable proc<#newOrderedTable,openArray[]>`_ for an
  ##   `OrderedTableRef` version
  runnableExamples:
    let a = [('a', 5), ('b', 9)]
    let b = toOrderedTable(a)
    assert b == {'a': 5, 'b': 9}.toOrderedTable

  result = initOrderedTable[A, B](pairs.len)
  for key, val in items(pairs): result[key] = val

proc `[]`*[A, B](t: OrderedTable[A, B], key: A): lent B =
  ## Retrieves the value at `t[key]`.
  ##
  ## If `key` is not in `t`, the  `KeyError` exception is raised.
  ## One can check with `hasKey proc<#hasKey,OrderedTable[A,B],A>`_ whether
  ## the key exists.
  ##
  ## See also:
  ## * `getOrDefault proc<#getOrDefault,OrderedTable[A,B],A>`_ to return
  ##   a default value (e.g. zero for int) if the key doesn't exist
  ## * `getOrDefault proc<#getOrDefault,OrderedTable[A,B],A,B>`_ to return
  ##   a custom value if the key doesn't exist
  ## * `[]= proc<#[]=,OrderedTable[A,B],A,sinkB>`_ for inserting a new
  ##   (key, value) pair in the table
  ## * `hasKey proc<#hasKey,OrderedTable[A,B],A>`_ for checking if a
  ##   key is in the table
  runnableExamples:
    let a = {'a': 5, 'b': 9}.toOrderedTable
    doAssert a['a'] == 5
    doAssertRaises(KeyError):
      echo a['z']

  get(t, key)

proc `[]`*[A, B](t: var OrderedTable[A, B], key: A): var B =
  ## Retrieves the value at `t[key]`. The value can be modified.
  ##
  ## If `key` is not in `t`, the `KeyError` exception is raised.
  ##
  ## See also:
  ## * `getOrDefault proc<#getOrDefault,OrderedTable[A,B],A>`_ to return
  ##   a default value (e.g. zero for int) if the key doesn't exist
  ## * `getOrDefault proc<#getOrDefault,OrderedTable[A,B],A,B>`_ to return
  ##   a custom value if the key doesn't exist
  ## * `[]= proc<#[]=,OrderedTable[A,B],A,sinkB>`_ for inserting a new
  ##   (key, value) pair in the table
  ## * `hasKey proc<#hasKey,OrderedTable[A,B],A>`_ for checking if a
  ##   key is in the table
  get(t, key)

proc hasKey*[A, B](t: OrderedTable[A, B], key: A): bool =
  ## Returns true if `key` is in the table `t`.
  ##
  ## See also:
  ## * `contains proc<#contains,OrderedTable[A,B],A>`_ for use with the `in`
  ##   operator
  ## * `[] proc<#[],OrderedTable[A,B],A>`_ for retrieving a value of a key
  ## * `getOrDefault proc<#getOrDefault,OrderedTable[A,B],A>`_ to return
  ##   a default value (e.g. zero for int) if the key doesn't exist
  ## * `getOrDefault proc<#getOrDefault,OrderedTable[A,B],A,B>`_ to return
  ##   a custom value if the key doesn't exist
  runnableExamples:
    let a = {'a': 5, 'b': 9}.toOrderedTable
    doAssert a.hasKey('a') == true
    doAssert a.hasKey('z') == false

  var hc: Hash = default(Hash)
  result = rawGet(t, key, hc) >= 0

proc contains*[A, B](t: OrderedTable[A, B], key: A): bool =
  ## Alias of `hasKey proc<#hasKey,OrderedTable[A,B],A>`_ for use with
  ## the `in` operator.
  runnableExamples:
    let a = {'a': 5, 'b': 9}.toOrderedTable
    doAssert 'b' in a == true
    doAssert a.contains('z') == false

  return hasKey[A, B](t, key)

proc hasKeyOrPut*[A, B](t: var OrderedTable[A, B], key: A, val: B): bool =
  ## Returns true if `key` is in the table, otherwise inserts `value`.
  ##
  ## See also:
  ## * `hasKey proc<#hasKey,OrderedTable[A,B],A>`_
  ## * `[] proc<#[],OrderedTable[A,B],A>`_ for retrieving a value of a key
  ## * `getOrDefault proc<#getOrDefault,OrderedTable[A,B],A>`_ to return
  ##   a default value (e.g. zero for int) if the key doesn't exist
  ## * `getOrDefault proc<#getOrDefault,OrderedTable[A,B],A,B>`_ to return
  ##   a custom value if the key doesn't exist
  runnableExamples:
    var a = {'a': 5, 'b': 9}.toOrderedTable
    if a.hasKeyOrPut('a', 50):
      a['a'] = 99
    if a.hasKeyOrPut('z', 50):
      a['z'] = 99
    doAssert a == {'a': 99, 'b': 9, 'z': 50}.toOrderedTable

  hasKeyOrPutImpl(enlarge)

proc getOrDefault*[A, B](t: OrderedTable[A, B], key: A): B =
  ## Retrieves the value at `t[key]` if `key` is in `t`. Otherwise, the
  ## default initialization value for type `B` is returned (e.g. 0 for any
  ## integer type).
  ##
  ## See also:
  ## * `[] proc<#[],OrderedTable[A,B],A>`_ for retrieving a value of a key
  ## * `hasKey proc<#hasKey,OrderedTable[A,B],A>`_
  ## * `hasKeyOrPut proc<#hasKeyOrPut,OrderedTable[A,B],A,B>`_
  ## * `mgetOrPut proc<#mgetOrPut,OrderedTable[A,B],A,B>`_
  ## * `getOrDefault proc<#getOrDefault,OrderedTable[A,B],A,B>`_ to return
  ##   a custom value if the key doesn't exist
  runnableExamples:
    let a = {'a': 5, 'b': 9}.toOrderedTable
    doAssert a.getOrDefault('a') == 5
    doAssert a.getOrDefault('z') == 0
  result = default(B)
  getOrDefaultImpl(t, key)

proc getOrDefault*[A, B](t: OrderedTable[A, B], key: A, def: B): B =
  ## Retrieves the value at `t[key]` if `key` is in `t`.
  ## Otherwise, `def` is returned.
  ##
  ## See also:
  ## * `[] proc<#[],OrderedTable[A,B],A>`_ for retrieving a value of a key
  ## * `hasKey proc<#hasKey,OrderedTable[A,B],A>`_
  ## * `hasKeyOrPut proc<#hasKeyOrPut,OrderedTable[A,B],A,B>`_
  ## * `mgetOrPut proc<#mgetOrPut,OrderedTable[A,B],A,B>`_
  ## * `getOrDefault proc<#getOrDefault,OrderedTable[A,B],A>`_ to return
  ##   a default value (e.g. zero for int) if the key doesn't exist
  runnableExamples:
    let a = {'a': 5, 'b': 9}.toOrderedTable
    doAssert a.getOrDefault('a', 99) == 5
    doAssert a.getOrDefault('z', 99) == 99
  getOrDefaultImpl(t, key, def)

proc mgetOrPut*[A, B](t: var OrderedTable[A, B], key: A, val: B): var B =
  ## Retrieves value at `t[key]` or puts `val` if not present, either way
  ## returning a value which can be modified.
  ##
  ## See also:
  ## * `[] proc<#[],OrderedTable[A,B],A>`_ for retrieving a value of a key
  ## * `hasKey proc<#hasKey,OrderedTable[A,B],A>`_
  ## * `hasKeyOrPut proc<#hasKeyOrPut,OrderedTable[A,B],A,B>`_
  ## * `getOrDefault proc<#getOrDefault,OrderedTable[A,B],A>`_ to return
  ##   a default value (e.g. zero for int) if the key doesn't exist
  ## * `getOrDefault proc<#getOrDefault,OrderedTable[A,B],A,B>`_ to return
  ##   a custom value if the key doesn't exist
  runnableExamples:
    var a = {'a': 5, 'b': 9}.toOrderedTable
    doAssert a.mgetOrPut('a', 99) == 5
    doAssert a.mgetOrPut('z', 99) == 99
    doAssert a == {'a': 5, 'b': 9, 'z': 99}.toOrderedTable

  mgetOrPutImpl(enlarge)

proc mgetOrPut*[A, B](t: var OrderedTable[A, B], key: A): var B =
  ## Retrieves the value at `t[key]` or puts the
  ## default initialization value for type `B` (e.g. 0 for any
  ## integer type).
  runnableExamples:
    var a = {'a': 5}.toOrderedTable
    doAssert a.mgetOrPut('a') == 5
    a.mgetOrPut('z').inc
    doAssert a == {'a': 5, 'z': 1}.toOrderedTable

  mgetOrPutImpl(enlarge)

proc len*[A, B](t: OrderedTable[A, B]): int {.inline.} =
  ## Returns the number of keys in `t`.
  runnableExamples:
    let a = {'a': 5, 'b': 9}.toOrderedTable
    doAssert len(a) == 2

  result = t.counter

proc add*[A, B](t: var OrderedTable[A, B], key: A, val: sink B) {.deprecated:
    "Deprecated since v1.4; it was more confusing than useful, use `[]=`".} =
  ## Puts a new `(key, value)` pair into `t` even if `t[key]` already exists.
  ##
  ## **This can introduce duplicate keys into the table!**
  ##
  ## Use `[]= proc<#[]=,OrderedTable[A,B],A,sinkB>`_ for inserting a new
  ## (key, value) pair in the table without introducing duplicates.
  addImpl(enlarge)

proc del*[A, B](t: var OrderedTable[A, B], key: A) =
  ## Deletes `key` from hash table `t`. Does nothing if the key does not exist.
  ##
  ## O(n) complexity.
  ##
  ## See also:
  ## * `pop proc<#pop,OrderedTable[A,B],A,B>`_
  ## * `clear proc<#clear,OrderedTable[A,B]>`_ to empty the whole table
  runnableExamples:
    var a = {'a': 5, 'b': 9, 'c': 13}.toOrderedTable
    a.del('a')
    doAssert a == {'b': 9, 'c': 13}.toOrderedTable
    a.del('z')
    doAssert a == {'b': 9, 'c': 13}.toOrderedTable

  if t.counter == 0: return
  var n: OrderedKeyValuePairSeq[A, B]
  newSeq(n, len(t.data))
  var h = t.first
  t.first = -1
  t.last = -1
  swap(t.data, n)
  let hc = genHash(key)
  while h >= 0:
    var nxt = n[h].next
    if isFilled(n[h].hcode):
      if n[h].hcode == hc and n[h].key == key:
        dec t.counter
      else:
        var j = -1 - rawGetKnownHC(t, n[h].key, n[h].hcode)
        rawInsert(t, t.data, move n[h].key, move n[h].val, n[h].hcode, j)
    h = nxt

proc pop*[A, B](t: var OrderedTable[A, B], key: A, val: var B): bool {.since: (1, 1).} =
  ## Deletes the `key` from the table.
  ## Returns `true`, if the `key` existed, and sets `val` to the
  ## mapping of the key. Otherwise, returns `false`, and the `val` is
  ## unchanged.
  ##
  ## O(n) complexity.
  ##
  ## See also:
  ## * `del proc<#del,OrderedTable[A,B],A>`_
  ## * `clear proc<#clear,OrderedTable[A,B]>`_ to empty the whole table
  runnableExamples:
    var
      a = {'c': 5, 'b': 9, 'a': 13}.toOrderedTable
      i: int
    doAssert a.pop('b', i) == true
    doAssert a == {'c': 5, 'a': 13}.toOrderedTable
    doAssert i == 9
    i = 0
    doAssert a.pop('z', i) == false
    doAssert a == {'c': 5, 'a': 13}.toOrderedTable
    doAssert i == 0

  var hc: Hash
  var index = rawGet(t, key, hc)
  result = index >= 0
  if result:
    val = move(t.data[index].val)
    del(t, key)

proc clear*[A, B](t: var OrderedTable[A, B]) =
  ## Resets the table so that it is empty.
  ##
  ## See also:
  ## * `del proc<#del,OrderedTable[A,B],A>`_
  ## * `pop proc<#pop,OrderedTable[A,B],A,B>`_
  runnableExamples:
    var a = {'a': 5, 'b': 9, 'c': 13}.toOrderedTable
    doAssert len(a) == 3
    clear(a)
    doAssert len(a) == 0

  clearImpl()
  t.first = -1
  t.last = -1

proc sort*[A, B](t: var OrderedTable[A, B], cmp: proc (x, y: (A, B)): int,
    order = SortOrder.Ascending) {.effectsOf: cmp.} =
  ## Sorts `t` according to the function `cmp`.
  ##
  ## This modifies the internal list
  ## that kept the insertion order, so insertion order is lost after this
  ## call but key lookup and insertions remain possible after `sort` (in
  ## contrast to the `sort proc<#sort,CountTable[A]>`_ for count tables).
  runnableExamples:
    import std/[algorithm]
    var a = initOrderedTable[char, int]()
    for i, c in "cab":
      a[c] = 10*i
    doAssert a == {'c': 0, 'a': 10, 'b': 20}.toOrderedTable
    a.sort(system.cmp)
    doAssert a == {'a': 10, 'b': 20, 'c': 0}.toOrderedTable
    a.sort(system.cmp, order = SortOrder.Descending)
    doAssert a == {'c': 0, 'b': 20, 'a': 10}.toOrderedTable

  var list = t.first
  var
    p, q, e, tail, oldhead: int
    nmerges, psize, qsize, i: int
  if t.counter == 0: return
  var insize = 1
  while true:
    p = list; oldhead = list
    list = -1; tail = -1; nmerges = 0
    while p >= 0:
      inc(nmerges)
      q = p
      psize = 0
      i = 0
      while i < insize:
        inc(psize)
        q = t.data[q].next
        if q < 0: break
        inc(i)
      qsize = insize
      while psize > 0 or (qsize > 0 and q >= 0):
        if psize == 0:
          e = q; q = t.data[q].next; dec(qsize)
        elif qsize == 0 or q < 0:
          e = p; p = t.data[p].next; dec(psize)
        elif cmp((t.data[p].key, t.data[p].val),
                 (t.data[q].key, t.data[q].val)) * order <= 0:
          e = p; p = t.data[p].next; dec(psize)
        else:
          e = q; q = t.data[q].next; dec(qsize)
        if tail >= 0: t.data[tail].next = e
        else: list = e
        tail = e
      p = q
    t.data[tail].next = -1
    if nmerges <= 1: break
    insize = insize * 2
  t.first = list
  t.last = tail

proc `$`*[A, B](t: OrderedTable[A, B]): string =
  ## The `$` operator for ordered hash tables. Used internally when calling
  ## `echo` on a table.
  dollarImpl()

proc `==`*[A, B](s, t: OrderedTable[A, B]): bool =
  ## The `==` operator for ordered hash tables. Returns `true` if both the
  ## content and the order are equal.
  runnableExamples:
    let
      a = {'a': 5, 'b': 9, 'c': 13}.toOrderedTable
      b = {'b': 9, 'c': 13, 'a': 5}.toOrderedTable
    doAssert a != b

  if s.counter != t.counter:
    return false
  if s.counter == 0 and t.counter == 0:
    return true
  var ht = t.first
  var hs = s.first
  while ht >= 0 and hs >= 0:
    var nxtt = t.data[ht].next
    var nxts = s.data[hs].next
    if isFilled(t.data[ht].hcode) and isFilled(s.data[hs].hcode):
      if (s.data[hs].key != t.data[ht].key) or (s.data[hs].val != t.data[ht].val):
        return false
    ht = nxtt
    hs = nxts
  return true



iterator pairs*[A, B](t: OrderedTable[A, B]): (A, B) =
  ## Iterates over any `(key, value)` pair in the table `t` in insertion
  ## order.
  ##
  ## See also:
  ## * `mpairs iterator<#mpairs.i,OrderedTable[A,B]>`_
  ## * `keys iterator<#keys.i,OrderedTable[A,B]>`_
  ## * `values iterator<#values.i,OrderedTable[A,B]>`_
  ##
  ## **Examples:**
  ##
  ##   ```Nim
  ##   let a = {
  ##     'o': [1, 5, 7, 9],
  ##     'e': [2, 4, 6, 8]
  ##     }.toOrderedTable
  ##
  ##   for k, v in a.pairs:
  ##     echo "key: ", k
  ##     echo "value: ", v
  ##
  ##   # key: o
  ##   # value: [1, 5, 7, 9]
  ##   # key: e
  ##   # value: [2, 4, 6, 8]
  ##   ```

  let L = len(t)
  forAllOrderedPairs:
    yield (t.data[h].key, t.data[h].val)
    assert(len(t) == L, "the length of the table changed while iterating over it")

iterator mpairs*[A, B](t: var OrderedTable[A, B]): (A, var B) =
  ## Iterates over any `(key, value)` pair in the table `t` (must be
  ## declared as `var`) in insertion order. The values can be modified.
  ##
  ## See also:
  ## * `pairs iterator<#pairs.i,OrderedTable[A,B]>`_
  ## * `mvalues iterator<#mvalues.i,OrderedTable[A,B]>`_
  runnableExamples:
    var a = {
      'o': @[1, 5, 7, 9],
      'e': @[2, 4, 6, 8]
      }.toOrderedTable
    for k, v in a.mpairs:
      v.add(v[0] + 10)
    doAssert a == {'o': @[1, 5, 7, 9, 11],
                   'e': @[2, 4, 6, 8, 12]}.toOrderedTable

  let L = len(t)
  forAllOrderedPairs:
    yield (t.data[h].key, t.data[h].val)
    assert(len(t) == L, "the length of the table changed while iterating over it")

iterator keys*[A, B](t: OrderedTable[A, B]): lent A =
  ## Iterates over any key in the table `t` in insertion order.
  ##
  ## See also:
  ## * `pairs iterator<#pairs.i,OrderedTable[A,B]>`_
  ## * `values iterator<#values.i,OrderedTable[A,B]>`_
  runnableExamples:
    var a = {
      'o': @[1, 5, 7, 9],
      'e': @[2, 4, 6, 8]
      }.toOrderedTable
    for k in a.keys:
      a[k].add(99)
    doAssert a == {'o': @[1, 5, 7, 9, 99],
                   'e': @[2, 4, 6, 8, 99]}.toOrderedTable

  let L = len(t)
  forAllOrderedPairs:
    yield t.data[h].key
    assert(len(t) == L, "the length of the table changed while iterating over it")

iterator values*[A, B](t: OrderedTable[A, B]): lent B =
  ## Iterates over any value in the table `t` in insertion order.
  ##
  ## See also:
  ## * `pairs iterator<#pairs.i,OrderedTable[A,B]>`_
  ## * `keys iterator<#keys.i,OrderedTable[A,B]>`_
  ## * `mvalues iterator<#mvalues.i,OrderedTable[A,B]>`_
  runnableExamples:
    let a = {
      'o': @[1, 5, 7, 9],
      'e': @[2, 4, 6, 8]
      }.toOrderedTable
    for v in a.values:
      doAssert v.len == 4

  let L = len(t)
  forAllOrderedPairs:
    yield t.data[h].val
    assert(len(t) == L, "the length of the table changed while iterating over it")

iterator mvalues*[A, B](t: var OrderedTable[A, B]): var B =
  ## Iterates over any value in the table `t` (must be
  ## declared as `var`) in insertion order. The values
  ## can be modified.
  ##
  ## See also:
  ## * `mpairs iterator<#mpairs.i,OrderedTable[A,B]>`_
  ## * `values iterator<#values.i,OrderedTable[A,B]>`_
  runnableExamples:
    var a = {
      'o': @[1, 5, 7, 9],
      'e': @[2, 4, 6, 8]
      }.toOrderedTable
    for v in a.mvalues:
      v.add(99)
    doAssert a == {'o': @[1, 5, 7, 9, 99],
                   'e': @[2, 4, 6, 8, 99]}.toOrderedTable

  let L = len(t)
  forAllOrderedPairs:
    yield t.data[h].val
    assert(len(t) == L, "the length of the table changed while iterating over it")

# ---------------------------------------------------------------------------
# --------------------------- OrderedTableRef -------------------------------
# ---------------------------------------------------------------------------

proc newOrderedTable*[A, B](initialSize = defaultInitialSize): OrderedTableRef[A, B] =
  ## Creates a new ordered ref hash table that is empty.
  ##
  ## See also:
  ## * `newOrderedTable proc<#newOrderedTable,openArray[]>`_ for creating
  ##   an `OrderedTableRef` from a collection of `(key, value)` pairs
  ## * `initOrderedTable proc<#initOrderedTable>`_ for creating an
  ##   `OrderedTable`
  runnableExamples:
    let
      a = newOrderedTable[int, string]()
      b = newOrderedTable[char, seq[int]]()
  new(result)
  {.noSideEffect.}:
    result[] = initOrderedTable[A, B](initialSize)

proc newOrderedTable*[A, B](pairs: openArray[(A, B)]): OrderedTableRef[A, B] =
  ## Creates a new ordered ref hash table that contains the given `pairs`.
  ##
  ## `pairs` is a container consisting of `(key, value)` tuples.
  ##
  ## See also:
  ## * `newOrderedTable proc<#newOrderedTable>`_
  ## * `toOrderedTable proc<#toOrderedTable,openArray[]>`_ for an
  ##   `OrderedTable` version
  runnableExamples:
    let a = [('a', 5), ('b', 9)]
    let b = newOrderedTable(a)
    assert b == {'a': 5, 'b': 9}.newOrderedTable

  result = newOrderedTable[A, B](pairs.len)
  {.noSideEffect.}:
    for key, val in items(pairs): result[key] = val


proc `[]`*[A, B](t: OrderedTableRef[A, B], key: A): var B =
  ## Retrieves the value at `t[key]`.
  ##
  ## If `key` is not in `t`, the  `KeyError` exception is raised.
  ## One can check with `hasKey proc<#hasKey,OrderedTableRef[A,B],A>`_ whether
  ## the key exists.
  ##
  ## See also:
  ## * `getOrDefault proc<#getOrDefault,OrderedTableRef[A,B],A>`_ to return
  ##   a default value (e.g. zero for int) if the key doesn't exist
  ## * `getOrDefault proc<#getOrDefault,OrderedTableRef[A,B],A,B>`_ to return
  ##   a custom value if the key doesn't exist
  ## * `[]= proc<#[]=,OrderedTableRef[A,B],A,sinkB>`_ for inserting a new
  ##   (key, value) pair in the table
  ## * `hasKey proc<#hasKey,OrderedTableRef[A,B],A>`_ for checking if
  ##   a key is in the table
  runnableExamples:
    let a = {'a': 5, 'b': 9}.newOrderedTable
    doAssert a['a'] == 5
    doAssertRaises(KeyError):
      echo a['z']
  result = t[][key]

proc `[]=`*[A, B](t: OrderedTableRef[A, B], key: A, val: sink B) =
  ## Inserts a `(key, value)` pair into `t`.
  ##
  ## See also:
  ## * `[] proc<#[],OrderedTableRef[A,B],A>`_ for retrieving a value of a key
  ## * `hasKeyOrPut proc<#hasKeyOrPut,OrderedTableRef[A,B],A,B>`_
  ## * `mgetOrPut proc<#mgetOrPut,OrderedTableRef[A,B],A,B>`_
  ## * `del proc<#del,OrderedTableRef[A,B],A>`_ for removing a key from the table
  runnableExamples:
    var a = newOrderedTable[char, int]()
    a['x'] = 7
    a['y'] = 33
    doAssert a == {'x': 7, 'y': 33}.newOrderedTable

  t[][key] = val

proc hasKey*[A, B](t: OrderedTableRef[A, B], key: A): bool =
  ## Returns true if `key` is in the table `t`.
  ##
  ## See also:
  ## * `contains proc<#contains,OrderedTableRef[A,B],A>`_ for use with the `in`
  ##   operator
  ## * `[] proc<#[],OrderedTableRef[A,B],A>`_ for retrieving a value of a key
  ## * `getOrDefault proc<#getOrDefault,OrderedTableRef[A,B],A>`_ to return
  ##   a default value (e.g. zero for int) if the key doesn't exist
  ## * `getOrDefault proc<#getOrDefault,OrderedTableRef[A,B],A,B>`_ to return
  ##   a custom value if the key doesn't exist
  runnableExamples:
    let a = {'a': 5, 'b': 9}.newOrderedTable
    doAssert a.hasKey('a') == true
    doAssert a.hasKey('z') == false

  result = t[].hasKey(key)

proc contains*[A, B](t: OrderedTableRef[A, B], key: A): bool =
  ## Alias of `hasKey proc<#hasKey,OrderedTableRef[A,B],A>`_ for use with
  ## the `in` operator.
  runnableExamples:
    let a = {'a': 5, 'b': 9}.newOrderedTable
    doAssert 'b' in a == true
    doAssert a.contains('z') == false

  return hasKey[A, B](t, key)

proc hasKeyOrPut*[A, B](t: OrderedTableRef[A, B], key: A, val: B): bool =
  ## Returns true if `key` is in the table, otherwise inserts `value`.
  ##
  ## See also:
  ## * `hasKey proc<#hasKey,OrderedTableRef[A,B],A>`_
  ## * `[] proc<#[],OrderedTableRef[A,B],A>`_ for retrieving a value of a key
  ## * `getOrDefault proc<#getOrDefault,OrderedTableRef[A,B],A>`_ to return
  ##   a default value (e.g. zero for int) if the key doesn't exist
  ## * `getOrDefault proc<#getOrDefault,OrderedTableRef[A,B],A,B>`_ to return
  ##   a custom value if the key doesn't exist
  runnableExamples:
    var a = {'a': 5, 'b': 9}.newOrderedTable
    if a.hasKeyOrPut('a', 50):
      a['a'] = 99
    if a.hasKeyOrPut('z', 50):
      a['z'] = 99
    doAssert a == {'a': 99, 'b': 9, 'z': 50}.newOrderedTable

  result = t[].hasKeyOrPut(key, val)

proc getOrDefault*[A, B](t: OrderedTableRef[A, B], key: A): B =
  ## Retrieves the value at `t[key]` if `key` is in `t`. Otherwise, the
  ## default initialization value for type `B` is returned (e.g. 0 for any
  ## integer type).
  ##
  ## See also:
  ## * `[] proc<#[],OrderedTableRef[A,B],A>`_ for retrieving a value of a key
  ## * `hasKey proc<#hasKey,OrderedTableRef[A,B],A>`_
  ## * `hasKeyOrPut proc<#hasKeyOrPut,OrderedTableRef[A,B],A,B>`_
  ## * `mgetOrPut proc<#mgetOrPut,OrderedTableRef[A,B],A,B>`_
  ## * `getOrDefault proc<#getOrDefault,OrderedTableRef[A,B],A,B>`_ to return
  ##   a custom value if the key doesn't exist
  runnableExamples:
    let a = {'a': 5, 'b': 9}.newOrderedTable
    doAssert a.getOrDefault('a') == 5
    doAssert a.getOrDefault('z') == 0

  getOrDefault(t[], key)

proc getOrDefault*[A, B](t: OrderedTableRef[A, B], key: A, def: B): B =
  ## Retrieves the value at `t[key]` if `key` is in `t`.
  ## Otherwise, `def` is returned.
  ##
  ## See also:
  ## * `[] proc<#[],OrderedTableRef[A,B],A>`_ for retrieving a value of a key
  ## * `hasKey proc<#hasKey,OrderedTableRef[A,B],A>`_
  ## * `hasKeyOrPut proc<#hasKeyOrPut,OrderedTableRef[A,B],A,B>`_
  ## * `mgetOrPut proc<#mgetOrPut,OrderedTableRef[A,B],A,B>`_
  ## * `getOrDefault proc<#getOrDefault,OrderedTableRef[A,B],A>`_ to return
  ##   a default value (e.g. zero for int) if the key doesn't exist
  runnableExamples:
    let a = {'a': 5, 'b': 9}.newOrderedTable
    doAssert a.getOrDefault('a', 99) == 5
    doAssert a.getOrDefault('z', 99) == 99

  getOrDefault(t[], key, def)

proc mgetOrPut*[A, B](t: OrderedTableRef[A, B], key: A, val: B): var B =
  ## Retrieves value at `t[key]` or puts `val` if not present, either way
  ## returning a value which can be modified.
  ##
  ## See also:
  ## * `[] proc<#[],OrderedTableRef[A,B],A>`_ for retrieving a value of a key
  ## * `hasKey proc<#hasKey,OrderedTableRef[A,B],A>`_
  ## * `hasKeyOrPut proc<#hasKeyOrPut,OrderedTableRef[A,B],A,B>`_
  ## * `getOrDefault proc<#getOrDefault,OrderedTableRef[A,B],A>`_ to return
  ##   a default value (e.g. zero for int) if the key doesn't exist
  ## * `getOrDefault proc<#getOrDefault,OrderedTableRef[A,B],A,B>`_ to return
  ##   a custom value if the key doesn't exist
  runnableExamples:
    var a = {'a': 5, 'b': 9}.newOrderedTable
    doAssert a.mgetOrPut('a', 99) == 5
    doAssert a.mgetOrPut('z', 99) == 99
    doAssert a == {'a': 5, 'b': 9, 'z': 99}.newOrderedTable

  result = t[].mgetOrPut(key, val)

proc mgetOrPut*[A, B](t: OrderedTableRef[A, B], key: A): var B =
  ## Retrieves the value at `t[key]` or puts the
  ## default initialization value for type `B` (e.g. 0 for any
  ## integer type).
  runnableExamples:
    var a = {'a': 5}.toOrderedTable
    doAssert a.mgetOrPut('a') == 5
    a.mgetOrPut('z').inc
    doAssert a == {'a': 5, 'z': 1}.toOrderedTable

  t[].mgetOrPut(key)

proc len*[A, B](t: OrderedTableRef[A, B]): int {.inline.} =
  ## Returns the number of keys in `t`.
  runnableExamples:
    let a = {'a': 5, 'b': 9}.newOrderedTable
    doAssert len(a) == 2

  result = t.counter

proc add*[A, B](t: OrderedTableRef[A, B], key: A, val: sink B) {.deprecated:
    "Deprecated since v1.4; it was more confusing than useful, use `[]=`".} =
  ## Puts a new `(key, value)` pair into `t` even if `t[key]` already exists.
  ##
  ## **This can introduce duplicate keys into the table!**
  ##
  ## Use `[]= proc<#[]=,OrderedTableRef[A,B],A,sinkB>`_ for inserting a new
  ## (key, value) pair in the table without introducing duplicates.
  t[].add(key, val)

proc del*[A, B](t: OrderedTableRef[A, B], key: A) =
  ## Deletes `key` from hash table `t`. Does nothing if the key does not exist.
  ##
  ## See also:
  ## * `clear proc<#clear,OrderedTableRef[A,B]>`_ to empty the whole table
  runnableExamples:
    var a = {'a': 5, 'b': 9, 'c': 13}.newOrderedTable
    a.del('a')
    doAssert a == {'b': 9, 'c': 13}.newOrderedTable
    a.del('z')
    doAssert a == {'b': 9, 'c': 13}.newOrderedTable

  t[].del(key)

proc pop*[A, B](t: OrderedTableRef[A, B], key: A, val: var B): bool {.since: (1, 1).} =
  ## Deletes the `key` from the table.
  ## Returns `true`, if the `key` existed, and sets `val` to the
  ## mapping of the key. Otherwise, returns `false`, and the `val` is
  ## unchanged.
  ##
  ## See also:
  ## * `del proc<#del,OrderedTableRef[A,B],A>`_
  ## * `clear proc<#clear,OrderedTableRef[A,B]>`_ to empty the whole table
  runnableExamples:
    var
      a = {'c': 5, 'b': 9, 'a': 13}.newOrderedTable
      i: int
    doAssert a.pop('b', i) == true
    doAssert a == {'c': 5, 'a': 13}.newOrderedTable
    doAssert i == 9
    i = 0
    doAssert a.pop('z', i) == false
    doAssert a == {'c': 5, 'a': 13}.newOrderedTable
    doAssert i == 0

  pop(t[], key, val)

proc clear*[A, B](t: OrderedTableRef[A, B]) =
  ## Resets the table so that it is empty.
  ##
  ## See also:
  ## * `del proc<#del,OrderedTableRef[A,B],A>`_
  runnableExamples:
    var a = {'a': 5, 'b': 9, 'c': 13}.newOrderedTable
    doAssert len(a) == 3
    clear(a)
    doAssert len(a) == 0

  clear(t[])

proc sort*[A, B](t: OrderedTableRef[A, B], cmp: proc (x, y: (A, B)): int,
    order = SortOrder.Ascending) {.effectsOf: cmp.} =
  ## Sorts `t` according to the function `cmp`.
  ##
  ## This modifies the internal list
  ## that kept the insertion order, so insertion order is lost after this
  ## call but key lookup and insertions remain possible after `sort` (in
  ## contrast to the `sort proc<#sort,CountTableRef[A]>`_ for count tables).
  runnableExamples:
    import std/[algorithm]
    var a = newOrderedTable[char, int]()
    for i, c in "cab":
      a[c] = 10*i
    doAssert a == {'c': 0, 'a': 10, 'b': 20}.newOrderedTable
    a.sort(system.cmp)
    doAssert a == {'a': 10, 'b': 20, 'c': 0}.newOrderedTable
    a.sort(system.cmp, order = SortOrder.Descending)
    doAssert a == {'c': 0, 'b': 20, 'a': 10}.newOrderedTable

  t[].sort(cmp, order = order)

proc `$`*[A, B](t: OrderedTableRef[A, B]): string =
  ## The `$` operator for hash tables. Used internally when calling `echo`
  ## on a table.
  dollarImpl()

proc `==`*[A, B](s, t: OrderedTableRef[A, B]): bool =
  ## The `==` operator for ordered hash tables. Returns true if either both
  ## tables are `nil`, or neither is `nil` and the content and the order of
  ## both are equal.
  runnableExamples:
    let
      a = {'a': 5, 'b': 9, 'c': 13}.newOrderedTable
      b = {'b': 9, 'c': 13, 'a': 5}.newOrderedTable
    doAssert a != b

  if isNil(s): result = isNil(t)
  elif isNil(t): result = false
  else: result = s[] == t[]



iterator pairs*[A, B](t: OrderedTableRef[A, B]): (A, B) =
  ## Iterates over any `(key, value)` pair in the table `t` in insertion
  ## order.
  ##
  ## See also:
  ## * `mpairs iterator<#mpairs.i,OrderedTableRef[A,B]>`_
  ## * `keys iterator<#keys.i,OrderedTableRef[A,B]>`_
  ## * `values iterator<#values.i,OrderedTableRef[A,B]>`_
  ##
  ## **Examples:**
  ##
  ##   ```Nim
  ##   let a = {
  ##     'o': [1, 5, 7, 9],
  ##     'e': [2, 4, 6, 8]
  ##     }.newOrderedTable
  ##
  ##   for k, v in a.pairs:
  ##     echo "key: ", k
  ##     echo "value: ", v
  ##
  ##   # key: o
  ##   # value: [1, 5, 7, 9]
  ##   # key: e
  ##   # value: [2, 4, 6, 8]
  ##   ```

  let L = len(t)
  forAllOrderedPairs:
    yield (t.data[h].key, t.data[h].val)
    assert(len(t) == L, "the length of the table changed while iterating over it")

iterator mpairs*[A, B](t: OrderedTableRef[A, B]): (A, var B) =
  ## Iterates over any `(key, value)` pair in the table `t` in insertion
  ## order. The values can be modified.
  ##
  ## See also:
  ## * `pairs iterator<#pairs.i,OrderedTableRef[A,B]>`_
  ## * `mvalues iterator<#mvalues.i,OrderedTableRef[A,B]>`_
  runnableExamples:
    let a = {
      'o': @[1, 5, 7, 9],
      'e': @[2, 4, 6, 8]
      }.newOrderedTable
    for k, v in a.mpairs:
      v.add(v[0] + 10)
    doAssert a == {'o': @[1, 5, 7, 9, 11],
                   'e': @[2, 4, 6, 8, 12]}.newOrderedTable

  let L = len(t)
  forAllOrderedPairs:
    yield (t.data[h].key, t.data[h].val)
    assert(len(t) == L, "the length of the table changed while iterating over it")

iterator keys*[A, B](t: OrderedTableRef[A, B]): lent A =
  ## Iterates over any key in the table `t` in insertion order.
  ##
  ## See also:
  ## * `pairs iterator<#pairs.i,OrderedTableRef[A,B]>`_
  ## * `values iterator<#values.i,OrderedTableRef[A,B]>`_
  runnableExamples:
    let a = {
      'o': @[1, 5, 7, 9],
      'e': @[2, 4, 6, 8]
      }.newOrderedTable
    for k in a.keys:
      a[k].add(99)
    doAssert a == {'o': @[1, 5, 7, 9, 99], 'e': @[2, 4, 6, 8,
        99]}.newOrderedTable

  let L = len(t)
  forAllOrderedPairs:
    yield t.data[h].key
    assert(len(t) == L, "the length of the table changed while iterating over it")

iterator values*[A, B](t: OrderedTableRef[A, B]): lent B =
  ## Iterates over any value in the table `t` in insertion order.
  ##
  ## See also:
  ## * `pairs iterator<#pairs.i,OrderedTableRef[A,B]>`_
  ## * `keys iterator<#keys.i,OrderedTableRef[A,B]>`_
  ## * `mvalues iterator<#mvalues.i,OrderedTableRef[A,B]>`_
  runnableExamples:
    let a = {
      'o': @[1, 5, 7, 9],
      'e': @[2, 4, 6, 8]
      }.newOrderedTable
    for v in a.values:
      doAssert v.len == 4

  let L = len(t)
  forAllOrderedPairs:
    yield t.data[h].val
    assert(len(t) == L, "the length of the table changed while iterating over it")

iterator mvalues*[A, B](t: OrderedTableRef[A, B]): var B =
  ## Iterates over any value in the table `t` in insertion order. The values
  ## can be modified.
  ##
  ## See also:
  ## * `mpairs iterator<#mpairs.i,OrderedTableRef[A,B]>`_
  ## * `values iterator<#values.i,OrderedTableRef[A,B]>`_
  runnableExamples:
    let a = {
      'o': @[1, 5, 7, 9],
      'e': @[2, 4, 6, 8]
      }.newOrderedTable
    for v in a.mvalues:
      v.add(99)
    doAssert a == {'o': @[1, 5, 7, 9, 99],
                   'e': @[2, 4, 6, 8, 99]}.newOrderedTable

  let L = len(t)
  forAllOrderedPairs:
    yield t.data[h].val
    assert(len(t) == L, "the length of the table changed while iterating over it")







# -------------------------------------------------------------------------
# ------------------------------ CountTable -------------------------------
# -------------------------------------------------------------------------

type
  CountTable*[A] = object
    ## Hash table that counts the number of each key.
    ##
    ## For creating an empty CountTable, use `initCountTable proc
    ## <#initCountTable>`_.
    data: seq[tuple[key: A, val: int]]
    counter: int
    isSorted: bool
  CountTableRef*[A] = ref CountTable[A] ## Ref version of
    ## `CountTable<#CountTable>`_.
    ##
    ## For creating a new empty CountTableRef, use `newCountTable proc
    ## <#newCountTable>`_.


# ------------------------------ helpers ---------------------------------

proc ctRawInsert[A](t: CountTable[A], data: var seq[tuple[key: A, val: int]],
                  key: A, val: int) =
  var h: Hash = hash(key) and high(data)
  while data[h].val != 0: h = nextTry(h, high(data))
  data[h].key = key
  data[h].val = val

proc enlarge[A](t: var CountTable[A]) =
  var n: seq[tuple[key: A, val: int]]
  newSeq(n, len(t.data) * growthFactor)
  for i in countup(0, high(t.data)):
    if t.data[i].val != 0: ctRawInsert(t, n, move t.data[i].key, move t.data[i].val)
  swap(t.data, n)

proc rawGet[A](t: CountTable[A], key: A): int =
  if t.data.len == 0:
    return -1
  var h: Hash = hash(key) and high(t.data) # start with real hash value
  while t.data[h].val != 0:
    if t.data[h].key == key: return h
    h = nextTry(h, high(t.data))
  result = -1 - h # < 0 => MISSING; insert idx = -1 - result

template ctget(t, key, def: untyped): untyped =
  var index = rawGet(t, key)
  result = if index >= 0: t.data[index].val else: def

proc inc*[A](t: var CountTable[A], key: A, val = 1)

# ----------------------------------------------------------------------

proc initCountTable*[A](initialSize = defaultInitialSize): CountTable[A] =
  ## Creates a new count table that is empty.
  ##
  ## Starting from Nim v0.20, tables are initialized by default and it is
  ## not necessary to call this function explicitly.
  ##
  ## See also:
  ## * `toCountTable proc<#toCountTable,openArray[A]>`_
  ## * `newCountTable proc<#newCountTable>`_ for creating a
  ##   `CountTableRef`
  result = default(CountTable[A])
  initImpl(result, initialSize)

proc toCountTable*[A](keys: openArray[A]): CountTable[A] =
  ## Creates a new count table with every member of a container `keys`
  ## having a count of how many times it occurs in that container.
  result = initCountTable[A](keys.len)
  for key in items(keys): result.inc(key)

proc `[]`*[A](t: CountTable[A], key: A): int =
  ## Retrieves the value at `t[key]` if `key` is in `t`.
  ## Otherwise `0` is returned.
  ##
  ## See also:
  ## * `getOrDefault<#getOrDefault,CountTable[A],A,int>`_ to return
  ##   a custom value if the key doesn't exist
  ## * `[]= proc<#[]%3D,CountTable[A],A,int>`_ for inserting a new
  ##   (key, value) pair in the table
  ## * `hasKey proc<#hasKey,CountTable[A],A>`_ for checking if a key
  ##   is in the table
  assert(not t.isSorted, "CountTable must not be used after sorting")
  ctget(t, key, 0)

template cntMakeEmpty(i) = t.data[i].val = 0
template cntCellEmpty(i) = t.data[i].val == 0
template cntCellHash(i)  = hash(t.data[i].key)

proc `[]=`*[A](t: var CountTable[A], key: A, val: int) =
  ## Inserts a `(key, value)` pair into `t`.
  ##
  ## See also:
  ## * `[] proc<#[],CountTable[A],A>`_ for retrieving a value of a key
  ## * `inc proc<#inc,CountTable[A],A,int>`_ for incrementing a
  ##   value of a key
  assert(not t.isSorted, "CountTable must not be used after sorting")
  assert val >= 0
  if val == 0:
    delImplNoHCode(cntMakeEmpty, cntCellEmpty, cntCellHash)
  else:
    let h = rawGet(t, key)
    if h >= 0:
      t.data[h].val = val
    else:
      insertImpl()

proc inc*[A](t: var CountTable[A], key: A, val = 1) =
  ## Increments `t[key]` by `val` (default: 1).
  runnableExamples:
    var a = toCountTable("aab")
    a.inc('a')
    a.inc('b', 10)
    doAssert a == toCountTable("aaabbbbbbbbbbb")

  assert(not t.isSorted, "CountTable must not be used after sorting")
  var index = rawGet(t, key)
  if index >= 0:
    inc(t.data[index].val, val)
    if t.data[index].val == 0:
      delImplIdx(t, index, cntMakeEmpty, cntCellEmpty, cntCellHash)
  else:
    if val != 0:
      insertImpl()

proc len*[A](t: CountTable[A]): int =
  ## Returns the number of keys in `t`.
  result = t.counter

proc smallest*[A](t: CountTable[A]): tuple[key: A, val: int] =
  ## Returns the `(key, value)` pair with the smallest `val`. Efficiency: O(n)
  ##
  ## See also:
  ## * `largest proc<#largest,CountTable[A]>`_
  assert t.len > 0, "counttable is empty"
  var minIdx = -1
  for h in 0 .. high(t.data):
    if t.data[h].val > 0 and (minIdx == -1 or t.data[minIdx].val > t.data[h].val):
      minIdx = h
  result.key = t.data[minIdx].key
  result.val = t.data[minIdx].val

proc largest*[A](t: CountTable[A]): tuple[key: A, val: int] =
  ## Returns the `(key, value)` pair with the largest `val`. Efficiency: O(n)
  ##
  ## See also:
  ## * `smallest proc<#smallest,CountTable[A]>`_
  assert t.len > 0, "counttable is empty"
  var maxIdx = 0
  for h in 1 .. high(t.data):
    if t.data[maxIdx].val < t.data[h].val: maxIdx = h
  result.key = t.data[maxIdx].key
  result.val = t.data[maxIdx].val

proc hasKey*[A](t: CountTable[A], key: A): bool =
  ## Returns true if `key` is in the table `t`.
  ##
  ## See also:
  ## * `contains proc<#contains,CountTable[A],A>`_ for use with the `in`
  ##   operator
  ## * `[] proc<#[],CountTable[A],A>`_ for retrieving a value of a key
  ## * `getOrDefault proc<#getOrDefault,CountTable[A],A,int>`_ to return
  ##   a custom value if the key doesn't exist
  assert(not t.isSorted, "CountTable must not be used after sorting")
  result = rawGet(t, key) >= 0

proc contains*[A](t: CountTable[A], key: A): bool =
  ## Alias of `hasKey proc<#hasKey,CountTable[A],A>`_ for use with
  ## the `in` operator.
  return hasKey[A](t, key)

proc getOrDefault*[A](t: CountTable[A], key: A; def: int = 0): int =
  ## Retrieves the value at `t[key]` if `key` is in `t`. Otherwise, the
  ## integer value of `def` is returned.
  ##
  ## See also:
  ## * `[] proc<#[],CountTable[A],A>`_ for retrieving a value of a key
  ## * `hasKey proc<#hasKey,CountTable[A],A>`_ for checking if a key
  ##   is in the table
  ctget(t, key, def)

proc del*[A](t: var CountTable[A], key: A) {.since: (1, 1).} =
  ## Deletes `key` from table `t`. Does nothing if the key does not exist.
  ##
  ## See also:
  ## * `pop proc<#pop,CountTable[A],A,int>`_
  ## * `clear proc<#clear,CountTable[A]>`_ to empty the whole table
  runnableExamples:
    var a = toCountTable("aabbbccccc")
    a.del('b')
    assert a == toCountTable("aaccccc")
    a.del('b')
    assert a == toCountTable("aaccccc")
    a.del('c')
    assert a == toCountTable("aa")

  delImplNoHCode(cntMakeEmpty, cntCellEmpty, cntCellHash)

proc pop*[A](t: var CountTable[A], key: A, val: var int): bool {.since: (1, 1).} =
  ## Deletes the `key` from the table.
  ## Returns `true`, if the `key` existed, and sets `val` to the
  ## mapping of the key. Otherwise, returns `false`, and the `val` is
  ## unchanged.
  ##
  ## See also:
  ## * `del proc<#del,CountTable[A],A>`_
  ## * `clear proc<#clear,CountTable[A]>`_ to empty the whole table
  runnableExamples:
    var a = toCountTable("aabbbccccc")
    var i = 0
    assert a.pop('b', i)
    assert i == 3
    i = 99
    assert not a.pop('b', i)
    assert i == 99

  var index = rawGet(t, key)
  result = index >= 0
  if result:
    val = move(t.data[index].val)
    delImplIdx(t, index, cntMakeEmpty, cntCellEmpty, cntCellHash)

proc clear*[A](t: var CountTable[A]) =
  ## Resets the table so that it is empty.
  ##
  ## See also:
  ## * `del proc<#del,CountTable[A],A>`_
  ## * `pop proc<#pop,CountTable[A],A,int>`_
  clearImpl()
  t.isSorted = false

func ctCmp[T](a, b: tuple[key: T, val: int]): int =
  result = system.cmp(a.val, b.val)

proc sort*[A](t: var CountTable[A], order = SortOrder.Descending) =
  ## Sorts the count table so that, by default, the entry with the
  ## highest counter comes first.
  ##
  ## .. warning:: This is destructive! Once sorted, you must not modify `t` afterwards!
  ##
  ## You can use the iterators `pairs<#pairs.i,CountTable[A]>`_,
  ## `keys<#keys.i,CountTable[A]>`_, and `values<#values.i,CountTable[A]>`_
  ## to iterate over `t` in the sorted order.
  runnableExamples:
    import std/[algorithm, sequtils]
    var a = toCountTable("abracadabra")
    doAssert a == "aaaaabbrrcd".toCountTable
    a.sort()
    doAssert toSeq(a.values) == @[5, 2, 2, 1, 1]
    a.sort(SortOrder.Ascending)
    doAssert toSeq(a.values) == @[1, 1, 2, 2, 5]

  t.data.sort(cmp = ctCmp, order = order)
  t.isSorted = true

proc merge*[A](s: var CountTable[A], t: CountTable[A]) =
  ## Merges the second table into the first one (must be declared as `var`).
  runnableExamples:
    var a = toCountTable("aaabbc")
    let b = toCountTable("bcc")
    a.merge(b)
    doAssert a == toCountTable("aaabbbccc")

  assert(not s.isSorted, "CountTable must not be used after sorting")
  for key, value in t:
    s.inc(key, value)

when (NimMajor, NimMinor) <= (1, 0):
  proc merge*[A](s, t: CountTable[A]): CountTable[A] =
    ## Merges the two tables into a new one.
    runnableExamples:
      let
        a = toCountTable("aaabbc")
        b = toCountTable("bcc")
      doAssert merge(a, b) == toCountTable("aaabbbccc")

    result = initCountTable[A](nextPowerOfTwo(max(s.len, t.len)))
    for table in @[s, t]:
      for key, value in table:
        result.inc(key, value)

proc `$`*[A](t: CountTable[A]): string =
  ## The `$` operator for count tables. Used internally when calling `echo`
  ## on a table.
  dollarImpl()

proc `==`*[A](s, t: CountTable[A]): bool =
  ## The `==` operator for count tables. Returns `true` if both tables
  ## contain the same keys with the same count. Insert order does not matter.
  equalsImpl(s, t)


iterator pairs*[A](t: CountTable[A]): (A, int) =
  ## Iterates over any `(key, value)` pair in the table `t`.
  ##
  ## See also:
  ## * `mpairs iterator<#mpairs.i,CountTable[A]>`_
  ## * `keys iterator<#keys.i,CountTable[A]>`_
  ## * `values iterator<#values.i,CountTable[A]>`_
  ##
  ## **Examples:**
  ##
  ##   ```Nim
  ##   let a = toCountTable("abracadabra")
  ##
  ##   for k, v in pairs(a):
  ##     echo "key: ", k
  ##     echo "value: ", v
  ##
  ##   # key: a
  ##   # value: 5
  ##   # key: b
  ##   # value: 2
  ##   # key: c
  ##   # value: 1
  ##   # key: d
  ##   # value: 1
  ##   # key: r
  ##   # value: 2
  ##   ```
  let L = len(t)
  for h in 0 .. high(t.data):
    if t.data[h].val != 0:
      yield (t.data[h].key, t.data[h].val)
      assert(len(t) == L, "the length of the table changed while iterating over it")

iterator mpairs*[A](t: var CountTable[A]): (A, var int) =
  ## Iterates over any `(key, value)` pair in the table `t` (must be
  ## declared as `var`). The values can be modified.
  ##
  ## See also:
  ## * `pairs iterator<#pairs.i,CountTable[A]>`_
  ## * `mvalues iterator<#mvalues.i,CountTable[A]>`_
  runnableExamples:
    var a = toCountTable("abracadabra")
    for k, v in mpairs(a):
      v = 2
    doAssert a == toCountTable("aabbccddrr")

  let L = len(t)
  for h in 0 .. high(t.data):
    if t.data[h].val != 0:
      yield (t.data[h].key, t.data[h].val)
      assert(len(t) == L, "the length of the table changed while iterating over it")

iterator keys*[A](t: CountTable[A]): lent A =
  ## Iterates over any key in the table `t`.
  ##
  ## See also:
  ## * `pairs iterator<#pairs.i,CountTable[A]>`_
  ## * `values iterator<#values.i,CountTable[A]>`_
  runnableExamples:
    var a = toCountTable("abracadabra")
    for k in keys(a):
      a[k] = 2
    doAssert a == toCountTable("aabbccddrr")

  let L = len(t)
  for h in 0 .. high(t.data):
    if t.data[h].val != 0:
      yield t.data[h].key
      assert(len(t) == L, "the length of the table changed while iterating over it")

iterator values*[A](t: CountTable[A]): int =
  ## Iterates over any value in the table `t`.
  ##
  ## See also:
  ## * `pairs iterator<#pairs.i,CountTable[A]>`_
  ## * `keys iterator<#keys.i,CountTable[A]>`_
  ## * `mvalues iterator<#mvalues.i,CountTable[A]>`_
  runnableExamples:
    let a = toCountTable("abracadabra")
    for v in values(a):
      assert v < 10

  let L = len(t)
  for h in 0 .. high(t.data):
    if t.data[h].val != 0:
      yield t.data[h].val
      assert(len(t) == L, "the length of the table changed while iterating over it")

iterator mvalues*[A](t: var CountTable[A]): var int =
  ## Iterates over any value in the table `t` (must be
  ## declared as `var`). The values can be modified.
  ##
  ## See also:
  ## * `mpairs iterator<#mpairs.i,CountTable[A]>`_
  ## * `values iterator<#values.i,CountTable[A]>`_
  runnableExamples:
    var a = toCountTable("abracadabra")
    for v in mvalues(a):
      v = 2
    doAssert a == toCountTable("aabbccddrr")

  let L = len(t)
  for h in 0 .. high(t.data):
    if t.data[h].val != 0:
      yield t.data[h].val
      assert(len(t) == L, "the length of the table changed while iterating over it")







# ---------------------------------------------------------------------------
# ---------------------------- CountTableRef --------------------------------
# ---------------------------------------------------------------------------

proc inc*[A](t: CountTableRef[A], key: A, val = 1)

proc newCountTable*[A](initialSize = defaultInitialSize): CountTableRef[A] =
  ## Creates a new ref count table that is empty.
  ##
  ## See also:
  ## * `newCountTable proc<#newCountTable,openArray[A]>`_ for creating
  ##   a `CountTableRef` from a collection
  ## * `initCountTable proc<#initCountTable>`_ for creating a
  ##   `CountTable`
  new(result)
  {.noSideEffect.}:
    result[] = initCountTable[A](initialSize)

proc newCountTable*[A](keys: openArray[A]): CountTableRef[A] =
  ## Creates a new ref count table with every member of a container `keys`
  ## having a count of how many times it occurs in that container.
  result = newCountTable[A](keys.len)
  {.noSideEffect.}:
    for key in items(keys): result.inc(key)

proc `[]`*[A](t: CountTableRef[A], key: A): int =
  ## Retrieves the value at `t[key]` if `key` is in `t`.
  ## Otherwise `0` is returned.
  ##
  ## See also:
  ## * `getOrDefault<#getOrDefault,CountTableRef[A],A,int>`_ to return
  ##   a custom value if the key doesn't exist
  ## * `inc proc<#inc,CountTableRef[A],A,int>`_ to inc even if missing
  ## * `[]= proc<#[]%3D,CountTableRef[A],A,int>`_ for inserting a new
  ##   (key, value) pair in the table
  ## * `hasKey proc<#hasKey,CountTableRef[A],A>`_ for checking if a key
  ##   is in the table
  result = t[][key]

proc `[]=`*[A](t: CountTableRef[A], key: A, val: int) =
  ## Inserts a `(key, value)` pair into `t`.
  ##
  ## See also:
  ## * `[] proc<#[],CountTableRef[A],A>`_ for retrieving a value of a key
  ## * `inc proc<#inc,CountTableRef[A],A,int>`_ for incrementing a
  ##   value of a key
  assert val > 0
  {.noSideEffect.}:
    t[][key] = val

proc inc*[A](t: CountTableRef[A], key: A, val = 1) =
  ## Increments `t[key]` by `val` (default: 1).
  runnableExamples:
    var a = newCountTable("aab")
    a.inc('a')
    a.inc('b', 10)
    doAssert a == newCountTable("aaabbbbbbbbbbb")
  {.noSideEffect.}:
    t[].inc(key, val)

proc smallest*[A](t: CountTableRef[A]): tuple[key: A, val: int] =
  ## Returns the `(key, value)` pair with the smallest `val`. Efficiency: O(n)
  ##
  ## See also:
  ## * `largest proc<#largest,CountTableRef[A]>`_
  t[].smallest

proc largest*[A](t: CountTableRef[A]): tuple[key: A, val: int] =
  ## Returns the `(key, value)` pair with the largest `val`. Efficiency: O(n)
  ##
  ## See also:
  ## * `smallest proc<#smallest,CountTable[A]>`_
  t[].largest

proc hasKey*[A](t: CountTableRef[A], key: A): bool =
  ## Returns true if `key` is in the table `t`.
  ##
  ## See also:
  ## * `contains proc<#contains,CountTableRef[A],A>`_ for use with the `in`
  ##   operator
  ## * `[] proc<#[],CountTableRef[A],A>`_ for retrieving a value of a key
  ## * `getOrDefault proc<#getOrDefault,CountTableRef[A],A,int>`_ to return
  ##   a custom value if the key doesn't exist
  result = t[].hasKey(key)

proc contains*[A](t: CountTableRef[A], key: A): bool =
  ## Alias of `hasKey proc<#hasKey,CountTableRef[A],A>`_ for use with
  ## the `in` operator.
  return hasKey[A](t, key)

proc getOrDefault*[A](t: CountTableRef[A], key: A, def: int): int =
  ## Retrieves the value at `t[key]` if `key` is in `t`. Otherwise, the
  ## integer value of `def` is returned.
  ##
  ## See also:
  ## * `[] proc<#[],CountTableRef[A],A>`_ for retrieving a value of a key
  ## * `hasKey proc<#hasKey,CountTableRef[A],A>`_ for checking if a key
  ##   is in the table
  result = t[].getOrDefault(key, def)

proc len*[A](t: CountTableRef[A]): int =
  ## Returns the number of keys in `t`.
  result = t.counter

proc del*[A](t: CountTableRef[A], key: A) {.since: (1, 1).} =
  ## Deletes `key` from table `t`. Does nothing if the key does not exist.
  ##
  ## See also:
  ## * `pop proc<#pop,CountTableRef[A],A,int>`_
  ## * `clear proc<#clear,CountTableRef[A]>`_ to empty the whole table
  del(t[], key)

proc pop*[A](t: CountTableRef[A], key: A, val: var int): bool {.since: (1, 1).} =
  ## Deletes the `key` from the table.
  ## Returns `true`, if the `key` existed, and sets `val` to the
  ## mapping of the key. Otherwise, returns `false`, and the `val` is
  ## unchanged.
  ##
  ## See also:
  ## * `del proc<#del,CountTableRef[A],A>`_
  ## * `clear proc<#clear,CountTableRef[A]>`_ to empty the whole table
  pop(t[], key, val)

proc clear*[A](t: CountTableRef[A]) =
  ## Resets the table so that it is empty.
  ##
  ## See also:
  ## * `del proc<#del,CountTableRef[A],A>`_
  ## * `pop proc<#pop,CountTableRef[A],A,int>`_
  clear(t[])

proc sort*[A](t: CountTableRef[A], order = SortOrder.Descending) =
  ## Sorts the count table so that, by default, the entry with the
  ## highest counter comes first.
  ##
  ## **This is destructive! You must not modify `t` afterwards!**
  ##
  ## You can use the iterators `pairs<#pairs.i,CountTableRef[A]>`_,
  ## `keys<#keys.i,CountTableRef[A]>`_, and `values<#values.i,CountTableRef[A]>`_
  ## to iterate over `t` in the sorted order.
  t[].sort(order = order)

proc merge*[A](s, t: CountTableRef[A]) =
  ## Merges the second table into the first one.
  runnableExamples:
    let
      a = newCountTable("aaabbc")
      b = newCountTable("bcc")
    a.merge(b)
    doAssert a == newCountTable("aaabbbccc")

  s[].merge(t[])

proc `$`*[A](t: CountTableRef[A]): string =
  ## The `$` operator for count tables. Used internally when calling `echo`
  ## on a table.
  dollarImpl()

proc `==`*[A](s, t: CountTableRef[A]): bool =
  ## The `==` operator for count tables. Returns `true` if either both tables
  ## are `nil`, or neither is `nil` and both contain the same keys with the same
  ## count. Insert order does not matter.
  if isNil(s): result = isNil(t)
  elif isNil(t): result = false
  else: result = s[] == t[]


iterator pairs*[A](t: CountTableRef[A]): (A, int) =
  ## Iterates over any `(key, value)` pair in the table `t`.
  ##
  ## See also:
  ## * `mpairs iterator<#mpairs.i,CountTableRef[A]>`_
  ## * `keys iterator<#keys.i,CountTableRef[A]>`_
  ## * `values iterator<#values.i,CountTableRef[A]>`_
  ##
  ## **Examples:**
  ##
  ##   ```Nim
  ##   let a = newCountTable("abracadabra")
  ##
  ##   for k, v in pairs(a):
  ##     echo "key: ", k
  ##     echo "value: ", v
  ##
  ##   # key: a
  ##   # value: 5
  ##   # key: b
  ##   # value: 2
  ##   # key: c
  ##   # value: 1
  ##   # key: d
  ##   # value: 1
  ##   # key: r
  ##   # value: 2
  ##   ```
  let L = len(t)
  for h in 0 .. high(t.data):
    if t.data[h].val != 0:
      yield (t.data[h].key, t.data[h].val)
      assert(len(t) == L, "the length of the table changed while iterating over it")

iterator mpairs*[A](t: CountTableRef[A]): (A, var int) =
  ## Iterates over any `(key, value)` pair in the table `t`. The values can
  ## be modified.
  ##
  ## See also:
  ## * `pairs iterator<#pairs.i,CountTableRef[A]>`_
  ## * `mvalues iterator<#mvalues.i,CountTableRef[A]>`_
  runnableExamples:
    let a = newCountTable("abracadabra")
    for k, v in mpairs(a):
      v = 2
    doAssert a == newCountTable("aabbccddrr")

  let L = len(t)
  for h in 0 .. high(t.data):
    if t.data[h].val != 0:
      yield (t.data[h].key, t.data[h].val)
      assert(len(t) == L, "table modified while iterating over it")

iterator keys*[A](t: CountTableRef[A]): A =
  ## Iterates over any key in the table `t`.
  ##
  ## See also:
  ## * `pairs iterator<#pairs.i,CountTable[A]>`_
  ## * `values iterator<#values.i,CountTable[A]>`_
  runnableExamples:
    let a = newCountTable("abracadabra")
    for k in keys(a):
      a[k] = 2
    doAssert a == newCountTable("aabbccddrr")

  let L = len(t)
  for h in 0 .. high(t.data):
    if t.data[h].val != 0:
      yield t.data[h].key
      assert(len(t) == L, "the length of the table changed while iterating over it")

iterator values*[A](t: CountTableRef[A]): int =
  ## Iterates over any value in the table `t`.
  ##
  ## See also:
  ## * `pairs iterator<#pairs.i,CountTableRef[A]>`_
  ## * `keys iterator<#keys.i,CountTableRef[A]>`_
  ## * `mvalues iterator<#mvalues.i,CountTableRef[A]>`_
  runnableExamples:
    let a = newCountTable("abracadabra")
    for v in values(a):
      assert v < 10

  let L = len(t)
  for h in 0 .. high(t.data):
    if t.data[h].val != 0:
      yield t.data[h].val
      assert(len(t) == L, "the length of the table changed while iterating over it")

iterator mvalues*[A](t: CountTableRef[A]): var int =
  ## Iterates over any value in the table `t`. The values can be modified.
  ##
  ## See also:
  ## * `mpairs iterator<#mpairs.i,CountTableRef[A]>`_
  ## * `values iterator<#values.i,CountTableRef[A]>`_
  runnableExamples:
    var a = newCountTable("abracadabra")
    for v in mvalues(a):
      v = 2
    doAssert a == newCountTable("aabbccddrr")

  let L = len(t)
  for h in 0 .. high(t.data):
    if t.data[h].val != 0:
      yield t.data[h].val
      assert(len(t) == L, "the length of the table changed while iterating over it")

proc hash*[K,V](s: Table[K,V]): Hash =
  for p in pairs(s):
    result = result xor hash(p)
  result = !$result

proc hash*[K,V](s: OrderedTable[K,V]): Hash =
  for p in pairs(s):
    result = result !& hash(p)
  result = !$result

proc hash*[V](s: CountTable[V]): Hash =
  for p in pairs(s):
    result = result xor hash(p)
  result = !$result

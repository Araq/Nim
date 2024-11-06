#
#
#            Nim's Runtime Library
#        (c) Copyright 2024 Nim Contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Although this module has `seq` in its name, it implements operations
## not only for the `seq`:idx: type, but for three built-in container types
## under the `openArray` umbrella:
## * sequences
## * strings
## * array
##
## The `system` module defines several common functions, such as:
## * `newSeq[T]` for creating new sequences of type `T`
## * `@` for converting arrays and strings to sequences
## * `add` for adding new elements to strings and sequences
## * `&` for string and seq concatenation
## * `in` (alias for `contains`) and `notin` for checking if an item is
##   in a container
##
## This module builds upon that, providing additional functionality in form of
## procs, iterators and templates inspired by functional programming
## languages.
##
## For functional style programming you have different options at your disposal:
## * the `sugar.collect macro<sugar.html#collect.m%2Cuntyped%2Cuntyped>`_
## * pass an `anonymous proc<manual.html#procedures-anonymous-procs>`_
## * import the `sugar module<sugar.html>`_  and use
##   the `=> macro<sugar.html#%3D>.m,untyped,untyped>`_
## * use `...It templates<#18>`_
##   (`mapIt<#mapIt.t,typed,untyped>`_,
##   `filterIt<#filterIt.t,untyped,untyped>`_, etc.)
##
## Chaining of functions is possible thanks to the
## `method call syntax<manual.html#procedures-method-call-syntax>`_.

runnableExamples:
  import std/sugar

  # Creating a sequence from 1 to 10, multiplying each member by 2,
  # keeping only the members which are not divisible by 6.
  let
    foo = toSeq(1..10).map(x => x * 2).filter(x => x mod 6 != 0)
    bar = toSeq(1..10).mapIt(it * 2).filterIt(it mod 6 != 0)
    baz = collect:
      for i in 1..10:
        let j = 2 * i
        if j mod 6 != 0:
          j

  doAssert foo == bar
  doAssert foo == baz
  doAssert foo == @[2, 4, 8, 10, 14, 16, 20]

  doAssert foo.any(x => x > 17)
  doAssert not bar.allIt(it < 20)
  doAssert foo.foldl(a + b) == 74 # sum of all members


runnableExamples:
  from std/strutils import join

  let
    vowels = @"aeiou"
    foo = "sequtils is an awesome module"

  doAssert (vowels is seq[char]) and (vowels == @['a', 'e', 'i', 'o', 'u'])
  doAssert foo.filterIt(it notin vowels).join == "sqtls s n wsm mdl"

## See also
## ========
## * `strutils module<strutils.html>`_ for common string functions
## * `sugar module<sugar.html>`_ for syntactic sugar macros
## * `algorithm module<algorithm.html>`_ for common generic algorithms
## * `json module<json.html>`_ for a structure which allows
##   heterogeneous members


import std/private/since

import std/macros
from std/typetraits import supportsCopyMem

when defined(nimPreviewSlimSystem):
  import std/assertions


when defined(nimHasEffectsOf):
  {.experimental: "strictEffects".}
else:
  {.pragma: effectsOf.}

macro evalOnceAs(expAlias, exp: untyped,
                 letAssigneable: static[bool]): untyped =
  ## Injects `expAlias` in caller scope, to avoid bugs involving multiple
  ## substitution in macro arguments such as
  ## https://github.com/nim-lang/Nim/issues/7187.
  ## `evalOnceAs(myAlias, myExp)` will behave as `let myAlias = myExp`
  ## except when `letAssigneable` is false (e.g. to handle openArray) where
  ## it just forwards `exp` unchanged.
  expectKind(expAlias, nnkIdent)
  var val = exp

  result = newStmtList()
  # If `exp` is not a symbol we evaluate it once here and then use the temporary
  # symbol as alias
  if exp.kind != nnkSym and letAssigneable:
    val = genSym()
    result.add(newLetStmt(val, exp))

  result.add(
    newProc(name = genSym(nskTemplate, $expAlias), params = [getType(untyped)],
      body = val, procType = nnkTemplateDef))

func concat*[T](seqs: varargs[seq[T]]): seq[T] =
  ## Takes several sequences' items and returns them inside a new sequence.
  ## All sequences must be of the same type.
  ##
  ## **See also:**
  ## * `distribute func<#distribute,seq[T],Positive>`_ for a reverse
  ##   operation
  ##
  runnableExamples:
    let
      s1 = @[1, 2, 3]
      s2 = @[4, 5]
      s3 = @[6, 7]
      total = concat(s1, s2, s3)
    assert total == @[1, 2, 3, 4, 5, 6, 7]

  var L = 0
  for seqitm in items(seqs): inc(L, len(seqitm))
  newSeq(result, L)
  var i = 0
  for s in items(seqs):
    for itm in items(s):
      result[i] = itm
      inc(i)

func addUnique*[T](s: var seq[T], x: sink T) =
  ## Adds `x` to the container `s` if it is not already present. 
  ## Uses `==` to check if the item is already present.
  runnableExamples:
    var a = @[1, 2, 3]
    a.addUnique(4)
    a.addUnique(4)
    assert a == @[1, 2, 3, 4]

  for i in 0..high(s):
    if s[i] == x: return
  when declared(ensureMove):
    s.add ensureMove(x)
  else:
    s.add x

func count*[T](s: openArray[T], x: T): int =
  ## Returns the number of occurrences of the item `x` in the container `s`.
  ##
  runnableExamples:
    let
      a = @[1, 2, 2, 3, 2, 4, 2]
      b = "abracadabra"
    assert count(a, 2) == 4
    assert count(a, 99) == 0
    assert count(b, 'r') == 2
  result = 0
  for itm in items(s):
    if itm == x:
      inc result

func cycle*[T](s: openArray[T], n: Natural): seq[T] =
  ## Returns a new sequence with the items of the container `s` repeated
  ## `n` times.
  ## `n` must be a non-negative number (zero or more).
  ##
  runnableExamples:
    let
      s = @[1, 2, 3]
      total = s.cycle(3)
    assert total == @[1, 2, 3, 1, 2, 3, 1, 2, 3]

  result = newSeq[T](n * s.len)
  var o = 0
  for x in 0 ..< n:
    for e in s:
      result[o] = e
      inc o

proc repeat*[T](x: T, n: Natural): seq[T] =
  ## Returns a new sequence with the item `x` repeated `n` times.
  ## `n` must be a non-negative number (zero or more).
  ##
  runnableExamples:
    let
      total = repeat(5, 3)
    assert total == @[5, 5, 5]

  result = newSeq[T](n)
  for i in 0 ..< n:
    result[i] = x

func deduplicate*[T](s: openArray[T], isSorted: bool = false): seq[T] =
  ## Returns a new sequence without duplicates.
  ##
  ## Setting the optional argument `isSorted` to true (default: false)
  ## uses a faster algorithm for deduplication.
  ##
  runnableExamples:
    let
      dup1 = @[1, 1, 3, 4, 2, 2, 8, 1, 4]
      dup2 = @["a", "a", "c", "d", "d"]
      unique1 = deduplicate(dup1)
      unique2 = deduplicate(dup2, isSorted = true)
    assert unique1 == @[1, 3, 4, 2, 8]
    assert unique2 == @["a", "c", "d"]

  result = @[]
  if s.len > 0:
    if isSorted:
      var prev = s[0]
      result.add(prev)
      for i in 1..s.high:
        if s[i] != prev:
          prev = s[i]
          result.add(prev)
    else:
      for itm in items(s):
        if not result.contains(itm): result.add(itm)

func minIndex*[T](s: openArray[T]): int {.since: (1, 1).} =
  ## Returns the index of the minimum value of `s`.
  ## `T` needs to have a `<` operator.
  runnableExamples:
    let
      a = @[1, 2, 3, 4]
      b = @[6, 5, 4, 3]
      c = [2, -7, 8, -5]
      d = "ziggy"
    assert minIndex(a) == 0
    assert minIndex(b) == 3
    assert minIndex(c) == 1
    assert minIndex(d) == 2
  result = 0
  for i in 1..high(s):
    if s[i] < s[result]: result = i

func maxIndex*[T](s: openArray[T]): int {.since: (1, 1).} =
  ## Returns the index of the maximum value of `s`.
  ## `T` needs to have a `<` operator.
  runnableExamples:
    let
      a = @[1, 2, 3, 4]
      b = @[6, 5, 4, 3]
      c = [2, -7, 8, -5]
      d = "ziggy"
    assert maxIndex(a) == 3
    assert maxIndex(b) == 0
    assert maxIndex(c) == 2
    assert maxIndex(d) == 0
  result = 0
  for i in 1..high(s):
    if s[i] > s[result]: result = i

func minmax*[T](x: openArray[T]): (T, T) =
  ## The minimum and maximum values of `x`. `T` needs to have a `<` operator.
  var l = x[0]
  var h = x[0]
  for i in 1..high(x):
    if x[i] < l: l = x[i]
    if h < x[i]: h = x[i]
  result = (l, h)


template zipImpl(s1, s2, retType: untyped): untyped =
  proc zip*[S, T](s1: openArray[S], s2: openArray[T]): retType =
    ## Returns a new sequence with a combination of the two input containers.
    ##
    ## The input containers can be of different types.
    ## If one container is shorter, the remaining items in the longer container
    ## are discarded.
    ##
    ## **Note**: For Nim 1.0.x and older version, `zip` returned a seq of
    ## named tuples with fields `a` and `b`. For Nim versions 1.1.x and newer,
    ## `zip` returns a seq of unnamed tuples.
    runnableExamples:
      let
        short = @[1, 2, 3]
        long = @[6, 5, 4, 3, 2, 1]
        words = @["one", "two", "three"]
        letters = "abcd"
        zip1 = zip(short, long)
        zip2 = zip(short, words)
      assert zip1 == @[(1, 6), (2, 5), (3, 4)]
      assert zip2 == @[(1, "one"), (2, "two"), (3, "three")]
      assert zip1[2][0] == 3
      assert zip2[1][1] == "two"
      when (NimMajor, NimMinor) <= (1, 0):
        let
          zip3 = zip(long, letters)
        assert zip3 == @[(a: 6, b: 'a'), (5, 'b'), (4, 'c'), (3, 'd')]
        assert zip3[0].b == 'a'
      else:
        let
          zip3: seq[tuple[num: int, letter: char]] = zip(long, letters)
        assert zip3 == @[(6, 'a'), (5, 'b'), (4, 'c'), (3, 'd')]
        assert zip3[0].letter == 'a'

    var m = min(s1.len, s2.len)
    newSeq(result, m)
    for i in 0 ..< m:
      result[i] = (s1[i], s2[i])

when (NimMajor, NimMinor) <= (1, 0):
  zipImpl(s1, s2, seq[tuple[a: S, b: T]])
else:
  zipImpl(s1, s2, seq[(S, T)])

proc unzip*[S, T](s: openArray[(S, T)]): (seq[S], seq[T]) {.since: (1, 1).} =
  ## Returns a tuple of two sequences split out from a sequence of 2-field tuples.
  runnableExamples:
    let
      zipped = @[(1, 'a'), (2, 'b'), (3, 'c')]
      unzipped1 = @[1, 2, 3]
      unzipped2 = @['a', 'b', 'c']
    assert zipped.unzip() == (unzipped1, unzipped2)
    assert zip(unzipped1, unzipped2).unzip() == (unzipped1, unzipped2)
  result = (newSeq[S](s.len), newSeq[T](s.len))
  for i in 0..<s.len:
    result[0][i] = s[i][0]
    result[1][i] = s[i][1]

func distribute*[T](s: seq[T], num: Positive, spread = true): seq[seq[T]] =
  ## Splits and distributes a sequence `s` into `num` sub-sequences.
  ##
  ## Returns a sequence of `num` sequences. For *some* input values this is the
  ## inverse of the `concat <#concat,varargs[seq[T]]>`_ func.
  ## The input sequence `s` can be empty, which will produce
  ## `num` empty sequences.
  ##
  ## If `spread` is false and the length of `s` is not a multiple of `num`, the
  ## func will max out the first sub-sequence with `1 + len(s) div num`
  ## entries, leaving the remainder of elements to the last sequence.
  ##
  ## On the other hand, if `spread` is true, the func will distribute evenly
  ## the remainder of the division across all sequences, which makes the result
  ## more suited to multithreading where you are passing equal sized work units
  ## to a thread pool and want to maximize core usage.
  ##
  runnableExamples:
    let numbers = @[1, 2, 3, 4, 5, 6, 7]
    assert numbers.distribute(3) == @[@[1, 2, 3], @[4, 5], @[6, 7]]
    assert numbers.distribute(3, false) == @[@[1, 2, 3], @[4, 5, 6], @[7]]
    assert numbers.distribute(6)[0] == @[1, 2]
    assert numbers.distribute(6)[1] == @[3]

  if num < 2:
    result = @[s]
    return

  # Create the result and calculate the stride size and the remainder if any.
  result = newSeq[seq[T]](num)
  var
    stride = s.len div num
    first = 0
    last = 0
    extra = s.len mod num

  if extra == 0 or spread == false:
    # Use an algorithm which overcounts the stride and minimizes reading limits.
    if extra > 0: inc(stride)
    for i in 0 ..< num:
      result[i] = newSeq[T]()
      for g in first ..< min(s.len, first + stride):
        result[i].add(s[g])
      first += stride
  else:
    # Use an undercounting algorithm which *adds* the remainder each iteration.
    for i in 0 ..< num:
      last = first + stride
      if extra > 0:
        extra -= 1
        inc(last)
      result[i] = newSeq[T]()
      for g in first ..< last:
        result[i].add(s[g])
      first = last

proc map*[T, S](s: openArray[T], op: proc (x: T): S {.closure.}):
                                                            seq[S] {.inline, effectsOf: op.} =
  ## Returns a new sequence with the results of the `op` proc applied to every
  ## item in the container `s`.
  ##
  ## Since the input is not modified, you can use it to
  ## transform the type of the elements in the input container.
  ##
  ## Instead of using `map` and `filter`, consider using the `collect` macro
  ## from the `sugar` module.
  ##
  ## **See also:**
  ## * `sugar.collect macro<sugar.html#collect.m%2Cuntyped%2Cuntyped>`_
  ## * `mapIt template<#mapIt.t,typed,untyped>`_
  ## * `apply proc<#apply,openArray[T],proc(T)_2>`_ for the in-place version
  ##
  runnableExamples:
    let
      a = @[1, 2, 3, 4]
      b = map(a, proc(x: int): string = $x)
    assert b == @["1", "2", "3", "4"]

  newSeq(result, s.len)
  for i in 0 ..< s.len:
    result[i] = op(s[i])

proc apply*[T](s: var openArray[T], op: proc (x: var T) {.closure.})
                                                              {.inline, effectsOf: op.} =
  ## Applies `op` to every item in `s`, modifying it directly.
  ##
  ## Note that the container `s` must be declared as a `var`,
  ## since `s` is modified in-place.
  ## The parameter function takes a `var T` type parameter.
  ##
  ## **See also:**
  ## * `applyIt template<#applyIt.t,untyped,untyped>`_
  ## * `map proc<#map,openArray[T],proc(T)>`_
  ##
  runnableExamples:
    var a = @["1", "2", "3", "4"]
    apply(a, proc(x: var string) = x &= "42")
    assert a == @["142", "242", "342", "442"]

  for i in 0 ..< s.len: op(s[i])

proc apply*[T](s: var openArray[T], op: proc (x: T): T {.closure.})
                                                              {.inline, effectsOf: op.} =
  ## Applies `op` to every item in `s` modifying it directly.
  ##
  ## Note that the container `s` must be declared as a `var`
  ## and it is required for your input and output types to
  ## be the same, since `s` is modified in-place.
  ## The parameter function takes and returns a `T` type variable.
  ##
  ## **See also:**
  ## * `applyIt template<#applyIt.t,untyped,untyped>`_
  ## * `map proc<#map,openArray[T],proc(T)>`_
  ##
  runnableExamples:
    var a = @["1", "2", "3", "4"]
    apply(a, proc(x: string): string = x & "42")
    assert a == @["142", "242", "342", "442"]

  for i in 0 ..< s.len: s[i] = op(s[i])

proc apply*[T](s: openArray[T], op: proc (x: T) {.closure.}) {.inline, since: (1, 3), effectsOf: op.} =
  ## Same as `apply` but for a proc that does not return anything
  ## and does not mutate `s` directly.
  runnableExamples:
    var message: string
    apply([0, 1, 2, 3, 4], proc(item: int) = message.addInt item)
    assert message == "01234"
  for i in 0 ..< s.len: op(s[i])

iterator filter*[T](s: openArray[T], pred: proc(x: T): bool {.closure.}): T {.effectsOf: pred.} =
  ## Iterates through a container `s` and yields every item that fulfills the
  ## predicate `pred` (a function that returns a `bool`).
  ##
  ## Instead of using `map` and `filter`, consider using the `collect` macro
  ## from the `sugar` module.
  ##
  ## **See also:**
  ## * `sugar.collect macro<sugar.html#collect.m%2Cuntyped%2Cuntyped>`_
  ## * `filter proc<#filter,openArray[T],proc(T)>`_
  ## * `filterIt template<#filterIt.t,untyped,untyped>`_
  ##
  runnableExamples:
    let numbers = @[1, 4, 5, 8, 9, 7, 4]
    var evens = newSeq[int]()
    for n in filter(numbers, proc (x: int): bool = x mod 2 == 0):
      evens.add(n)
    assert evens == @[4, 8, 4]

  for i in 0 ..< s.len:
    if pred(s[i]):
      yield s[i]

proc filter*[T](s: openArray[T], pred: proc(x: T): bool {.closure.}): seq[T]
                                                                  {.inline, effectsOf: pred.} =
  ## Returns a new sequence with all the items of `s` that fulfill the
  ## predicate `pred` (a function that returns a `bool`).
  ##
  ## Instead of using `map` and `filter`, consider using the `collect` macro
  ## from the `sugar` module.
  ##
  ## **See also:**
  ## * `sugar.collect macro<sugar.html#collect.m%2Cuntyped%2Cuntyped>`_
  ## * `filterIt template<#filterIt.t,untyped,untyped>`_
  ## * `filter iterator<#filter.i,openArray[T],proc(T)>`_
  ## * `keepIf proc<#keepIf,seq[T],proc(T)>`_ for the in-place version
  ##
  runnableExamples:
    let
      colors = @["red", "yellow", "black"]
      f1 = filter(colors, proc(x: string): bool = x.len < 6)
      f2 = filter(colors, proc(x: string): bool = x.contains('y'))
    assert f1 == @["red", "black"]
    assert f2 == @["yellow"]

  result = newSeq[T]()
  for i in 0 ..< s.len:
    if pred(s[i]):
      result.add(s[i])

proc keepIf*[T](s: var seq[T], pred: proc(x: T): bool {.closure.})
                                                                {.inline, effectsOf: pred.} =
  ## Keeps the items in the passed sequence `s` if they fulfill the
  ## predicate `pred` (a function that returns a `bool`).
  ##
  ## Note that `s` must be declared as a `var`.
  ##
  ## Similar to the `filter proc<#filter,openArray[T],proc(T)>`_,
  ## but modifies the sequence directly.
  ##
  ## **See also:**
  ## * `keepItIf template<#keepItIf.t,seq,untyped>`_
  ## * `filter proc<#filter,openArray[T],proc(T)>`_
  ##
  runnableExamples:
    var floats = @[13.0, 12.5, 5.8, 2.0, 6.1, 9.9, 10.1]
    keepIf(floats, proc(x: float): bool = x > 10)
    assert floats == @[13.0, 12.5, 10.1]

  var pos = 0
  for i in 0 ..< len(s):
    if pred(s[i]):
      if pos != i:
        when defined(gcDestructors):
          s[pos] = move(s[i])
        else:
          shallowCopy(s[pos], s[i])
      inc(pos)
  setLen(s, pos)

func delete*[T](s: var seq[T]; slice: Slice[int]) =
  ## Deletes the items `s[slice]`, raising `IndexDefect` if the slice contains
  ## elements out of range.
  ##
  ## This operation moves all elements after `s[slice]` in linear time.
  runnableExamples:
    var a = @[10, 11, 12, 13, 14]
    doAssertRaises(IndexDefect): a.delete(4..5)
    assert a == @[10, 11, 12, 13, 14]
    a.delete(4..4)
    assert a == @[10, 11, 12, 13]
    a.delete(1..2)
    assert a == @[10, 13]
    a.delete(1..<1) # empty slice
    assert a == @[10, 13]
  when compileOption("boundChecks"):
    if not (slice.a < s.len and slice.a >= 0 and slice.b < s.len):
      raise newException(IndexDefect, $(slice: slice, len: s.len))
  if slice.b >= slice.a:
    template defaultImpl =
      var i = slice.a
      var j = slice.b + 1
      var newLen = s.len - j + i
      while i < newLen:
        when defined(gcDestructors):
          s[i] = move(s[j])
        else:
          s[i].shallowCopy(s[j])
        inc(i)
        inc(j)
      setLen(s, newLen)
    when nimvm: defaultImpl()
    else:
      when defined(js):
        let n = slice.b - slice.a + 1
        let first = slice.a
        {.emit: "`s`.splice(`first`, `n`);".}
      else:
        defaultImpl()

func delete*[T](s: var seq[T]; first, last: Natural) {.deprecated: "use `delete(s, first..last)`".} =
  ## Deletes the items of a sequence `s` at positions `first..last`
  ## (including both ends of the range).
  ## This modifies `s` itself, it does not return a copy.
  runnableExamples("--warning:deprecated:off"):
    let outcome = @[1, 1, 1, 1, 1, 1, 1, 1]
    var dest = @[1, 1, 1, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1]
    dest.delete(3, 8)
    assert outcome == dest
  doAssert first <= last
  if first >= s.len:
    return
  var i = first
  var j = min(len(s), last + 1)
  var newLen = len(s) - j + i
  while i < newLen:
    when defined(gcDestructors):
      s[i] = move(s[j])
    else:
      s[i].shallowCopy(s[j])
    inc(i)
    inc(j)
  setLen(s, newLen)

func insert*[T](dest: var seq[T], src: openArray[T], pos = 0) =
  ## Inserts items from `src` into `dest` at position `pos`. This modifies
  ## `dest` itself, it does not return a copy.
  ##
  ## Note that the elements of `src` and `dest` must be of the same type.
  ##
  runnableExamples:
    var dest = @[1, 1, 1, 1, 1, 1, 1, 1]
    let
      src = @[2, 2, 2, 2, 2, 2]
      outcome = @[1, 1, 1, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1]
    dest.insert(src, 3)
    assert dest == outcome

  var j = len(dest) - 1
  var i = j + len(src)
  if i == j: return
  dest.setLen(i + 1)

  # Move items after `pos` to the end of the sequence.
  while j >= pos:
    when defined(gcDestructors):
      dest[i] = move(dest[j])
    else:
      dest[i].shallowCopy(dest[j])
    dec(i)
    dec(j)
  # Insert items from `dest` into `dest` at `pos`
  inc(j)
  for item in src:
    dest[j] = item
    inc(j)


template filterIt*(s, pred: untyped): untyped =
  ## Returns a new sequence with all the items of `s` that fulfill the
  ## predicate `pred`.
  ##
  ## Unlike the `filter proc<#filter,openArray[T],proc(T)>`_ and
  ## `filter iterator<#filter.i,openArray[T],proc(T)>`_,
  ## the predicate needs to be an expression using the `it` variable
  ## for testing, like: `filterIt("abcxyz", it == 'x')`.
  ##
  ## Instead of using `mapIt` and `filterIt`, consider using the `collect` macro
  ## from the `sugar` module.
  ##
  ## **See also:**
  ## * `sugar.collect macro<sugar.html#collect.m%2Cuntyped%2Cuntyped>`_
  ## * `filter proc<#filter,openArray[T],proc(T)>`_
  ## * `filter iterator<#filter.i,openArray[T],proc(T)>`_
  ##
  runnableExamples:
    let
      temperatures = @[-272.15, -2.0, 24.5, 44.31, 99.9, -113.44]
      acceptable = temperatures.filterIt(it < 50 and it > -10)
      notAcceptable = temperatures.filterIt(it > 50 or it < -10)
    assert acceptable == @[-2.0, 24.5, 44.31]
    assert notAcceptable == @[-272.15, 99.9, -113.44]

  var result = newSeq[typeof(s[0])]()
  for it {.inject.} in items(s):
    if pred: result.add(it)
  result

template keepItIf*(varSeq: seq, pred: untyped) =
  ## Keeps the items in the passed sequence (must be declared as a `var`)
  ## if they fulfill the predicate.
  ##
  ## Unlike the `keepIf proc<#keepIf,seq[T],proc(T)>`_,
  ## the predicate needs to be an expression using
  ## the `it` variable for testing, like: `keepItIf("abcxyz", it == 'x')`.
  ##
  ## **See also:**
  ## * `keepIf proc<#keepIf,seq[T],proc(T)>`_
  ## * `filterIt template<#filterIt.t,untyped,untyped>`_
  ##
  runnableExamples:
    var candidates = @["foo", "bar", "baz", "foobar"]
    candidates.keepItIf(it.len == 3 and it[0] == 'b')
    assert candidates == @["bar", "baz"]

  var pos = 0
  for i in 0 ..< len(varSeq):
    let it {.inject.} = varSeq[i]
    if pred:
      if pos != i:
        when defined(gcDestructors):
          varSeq[pos] = move(varSeq[i])
        else:
          shallowCopy(varSeq[pos], varSeq[i])
      inc(pos)
  setLen(varSeq, pos)

since (1, 1):
  template countIt*(s, pred: untyped): int =
    ## Returns a count of all the items that fulfill the predicate.
    ##
    ## The predicate needs to be an expression using
    ## the `it` variable for testing, like: `countIt(@[1, 2, 3], it > 2)`.
    ##
    runnableExamples:
      let numbers = @[-3, -2, -1, 0, 1, 2, 3, 4, 5, 6]
      iterator iota(n: int): int =
        for i in 0..<n: yield i
      assert numbers.countIt(it < 0) == 3
      assert countIt(iota(10), it < 2) == 2

    var result = 0
    for it {.inject.} in s:
      if pred: result += 1
    result

proc all*[T](s: openArray[T], pred: proc(x: T): bool {.closure.}): bool {.effectsOf: pred.} =
  ## Iterates through a container and checks if every item fulfills the
  ## predicate.
  ##
  ## **See also:**
  ## * `allIt template<#allIt.t,untyped,untyped>`_
  ## * `any proc<#any,openArray[T],proc(T)>`_
  ##
  runnableExamples:
    let numbers = @[1, 4, 5, 8, 9, 7, 4]
    assert all(numbers, proc (x: int): bool = x < 10) == true
    assert all(numbers, proc (x: int): bool = x < 9) == false

  for i in s:
    if not pred(i):
      return false
  true

template allIt*(s, pred: untyped): bool =
  ## Iterates through a container and checks if every item fulfills the
  ## predicate.
  ##
  ## Unlike the `all proc<#all,openArray[T],proc(T)>`_,
  ## the predicate needs to be an expression using
  ## the `it` variable for testing, like: `allIt("abba", it == 'a')`.
  ##
  ## **See also:**
  ## * `all proc<#all,openArray[T],proc(T)>`_
  ## * `anyIt template<#anyIt.t,untyped,untyped>`_
  ##
  runnableExamples:
    let numbers = @[1, 4, 5, 8, 9, 7, 4]
    assert numbers.allIt(it < 10) == true
    assert numbers.allIt(it < 9) == false

  var result = true
  for it {.inject.} in items(s):
    if not pred:
      result = false
      break
  result

proc any*[T](s: openArray[T], pred: proc(x: T): bool {.closure.}): bool {.effectsOf: pred.} =
  ## Iterates through a container and checks if at least one item
  ## fulfills the predicate.
  ##
  ## **See also:**
  ## * `anyIt template<#anyIt.t,untyped,untyped>`_
  ## * `all proc<#all,openArray[T],proc(T)>`_
  ##
  runnableExamples:
    let numbers = @[1, 4, 5, 8, 9, 7, 4]
    assert any(numbers, proc (x: int): bool = x > 8) == true
    assert any(numbers, proc (x: int): bool = x > 9) == false

  for i in s:
    if pred(i):
      return true
  false

template anyIt*(s, pred: untyped): bool =
  ## Iterates through a container and checks if at least one item
  ## fulfills the predicate.
  ##
  ## Unlike the `any proc<#any,openArray[T],proc(T)>`_,
  ## the predicate needs to be an expression using
  ## the `it` variable for testing, like: `anyIt("abba", it == 'a')`.
  ##
  ## **See also:**
  ## * `any proc<#any,openArray[T],proc(T)>`_
  ## * `allIt template<#allIt.t,untyped,untyped>`_
  ##
  runnableExamples:
    let numbers = @[1, 4, 5, 8, 9, 7, 4]
    assert numbers.anyIt(it > 8) == true
    assert numbers.anyIt(it > 9) == false

  var result = false
  for it {.inject.} in items(s):
    if pred:
      result = true
      break
  result

template toSeq1(s: not iterator): untyped =
  # overload for typed but not iterator
  type OutType = typeof(items(s))
  when compiles(s.len):
    block:
      evalOnceAs(s2, s, compiles((let _ = s)))
      var i = 0
      var result = newSeq[OutType](s2.len)
      for it in s2:
        result[i] = it
        i += 1
      result
  else:
    var result: seq[OutType]# = @[]
    for it in s:
      result.add(it)
    result

template toSeq2(iter: iterator): untyped =
  # overload for iterator
  evalOnceAs(iter2, iter(), false)
  when compiles(iter2.len):
    var i = 0
    var result = newSeq[typeof(iter2)](iter2.len)
    for x in iter2:
      result[i] = x
      inc i
    result
  else:
    type OutType = typeof(iter2())
    var result: seq[OutType]# = @[]
    when compiles(iter2()):
      evalOnceAs(iter4, iter, false)
      let iter3 = iter4()
      for x in iter3():
        result.add(x)
    else:
      for x in iter2():
        result.add(x)
    result

template toSeq*(iter: untyped): untyped =
  ## Transforms any iterable (anything that can be iterated over, e.g. with
  ## a for-loop) into a sequence.
  ##
  runnableExamples:
    let
      myRange = 1..5
      mySet: set[int8] = {5'i8, 3, 1}
    assert typeof(myRange) is HSlice[system.int, system.int]
    assert typeof(mySet) is set[int8]

    let
      mySeq1 = toSeq(myRange)
      mySeq2 = toSeq(mySet)
    assert mySeq1 == @[1, 2, 3, 4, 5]
    assert mySeq2 == @[1'i8, 3, 5]

  when compiles(toSeq1(iter)):
    toSeq1(iter)
  elif compiles(toSeq2(iter)):
    toSeq2(iter)
  else:
    # overload for untyped, e.g.: `toSeq(myInlineIterator(3))`
    when compiles(iter.len):
      block:
        evalOnceAs(iter2, iter, true)
        var result = newSeq[typeof(iter)](iter2.len)
        var i = 0
        for x in iter2:
          result[i] = x
          inc i
        result
    else:
      var result: seq[typeof(iter)] = @[]
      for x in iter:
        result.add(x)
      result

template foldl*(sequence, operation: untyped): untyped =
  ## Template to fold a sequence from left to right, returning the accumulation.
  ##
  ## The sequence is required to have at least a single element. Debug versions
  ## of your program will assert in this situation but release versions will
  ## happily go ahead. If the sequence has a single element it will be returned
  ## without applying `operation`.
  ##
  ## The `operation` parameter should be an expression which uses the
  ## variables `a` and `b` for each step of the fold. Since this is a left
  ## fold, for non associative binary operations like subtraction think that
  ## the sequence of numbers 1, 2 and 3 will be parenthesized as (((1) - 2) -
  ## 3).
  ##
  ## **See also:**
  ## * `foldl template<#foldl.t,,,>`_ with a starting parameter
  ## * `foldr template<#foldr.t,untyped,untyped>`_
  ##
  runnableExamples:
    let
      numbers = @[5, 9, 11]
      addition = foldl(numbers, a + b)
      subtraction = foldl(numbers, a - b)
      multiplication = foldl(numbers, a * b)
      words = @["nim", "is", "cool"]
      concatenation = foldl(words, a & b)
      procs = @["proc", "Is", "Also", "Fine"]


    func foo(acc, cur: string): string =
      result = acc & cur

    assert addition == 25, "Addition is (((5)+9)+11)"
    assert subtraction == -15, "Subtraction is (((5)-9)-11)"
    assert multiplication == 495, "Multiplication is (((5)*9)*11)"
    assert concatenation == "nimiscool"
    assert foldl(procs, foo(a, b)) == "procIsAlsoFine"

  let s = sequence
  assert s.len > 0, "Can't fold empty sequences"
  var result: typeof(s[0])
  result = s[0]
  for i in 1..<s.len:
    let
      a {.inject.} = result
      b {.inject.} = s[i]
    result = operation
  result

template foldl*(sequence, operation, first): untyped =
  ## Template to fold a sequence from left to right, returning the accumulation.
  ##
  ## This version of `foldl` gets a **starting parameter**. This makes it possible
  ## to accumulate the sequence into a different type than the sequence elements.
  ##
  ## The `operation` parameter should be an expression which uses the variables
  ## `a` and `b` for each step of the fold. The `first` parameter is the
  ## start value (the first `a`) and therefore defines the type of the result.
  ##
  ## **See also:**
  ## * `foldr template<#foldr.t,untyped,untyped>`_
  ##
  runnableExamples:
    let
      numbers = @[0, 8, 1, 5]
      digits = foldl(numbers, a & (chr(b + ord('0'))), "")
    assert digits == "0815"

  var result: typeof(first) = first
  for x in items(sequence):
    let
      a {.inject.} = result
      b {.inject.} = x
    result = operation
  result

template foldr*(sequence, operation: untyped): untyped =
  ## Template to fold a sequence from right to left, returning the accumulation.
  ##
  ## The sequence is required to have at least a single element. Debug versions
  ## of your program will assert in this situation but release versions will
  ## happily go ahead. If the sequence has a single element it will be returned
  ## without applying `operation`.
  ##
  ## The `operation` parameter should be an expression which uses the
  ## variables `a` and `b` for each step of the fold. Since this is a right
  ## fold, for non associative binary operations like subtraction think that
  ## the sequence of numbers 1, 2 and 3 will be parenthesized as (1 - (2 -
  ## (3))).
  ##
  ## **See also:**
  ## * `foldl template<#foldl.t,untyped,untyped>`_
  ## * `foldl template<#foldl.t,,,>`_ with a starting parameter
  ##
  runnableExamples:
    let
      numbers = @[5, 9, 11]
      addition = foldr(numbers, a + b)
      subtraction = foldr(numbers, a - b)
      multiplication = foldr(numbers, a * b)
      words = @["nim", "is", "cool"]
      concatenation = foldr(words, a & b)
    assert addition == 25, "Addition is (5+(9+(11)))"
    assert subtraction == 7, "Subtraction is (5-(9-(11)))"
    assert multiplication == 495, "Multiplication is (5*(9*(11)))"
    assert concatenation == "nimiscool"

  let s = sequence # xxx inefficient, use {.evalonce.} pending #13750
  let n = s.len
  assert n > 0, "Can't fold empty sequences"
  var result = s[n - 1]
  for i in countdown(n - 2, 0):
    let
      a {.inject.} = s[i]
      b {.inject.} = result
    result = operation
  result

template mapIt*(s: typed, op: untyped): untyped =
  ## Returns a new sequence with the results of the `op` proc applied to every
  ## item in the container `s`.
  ##
  ## Since the input is not modified you can use it to
  ## transform the type of the elements in the input container.
  ##
  ## The template injects the `it` variable which you can use directly in an
  ## expression.
  ##
  ## Instead of using `mapIt` and `filterIt`, consider using the `collect` macro
  ## from the `sugar` module.
  ##
  ## **See also:**
  ## * `sugar.collect macro<sugar.html#collect.m%2Cuntyped%2Cuntyped>`_
  ## * `map proc<#map,openArray[T],proc(T)>`_
  ## * `applyIt template<#applyIt.t,untyped,untyped>`_ for the in-place version
  ##
  runnableExamples:
    let
      nums = @[1, 2, 3, 4]
      strings = nums.mapIt($(4 * it))
    assert strings == @["4", "8", "12", "16"]

  type OutType = typeof((
    block:
      var it{.inject.}: typeof(items(s), typeOfIter);
      op), typeOfProc)
  when OutType is not (proc):
    # Here, we avoid to create closures in loops.
    # This avoids https://github.com/nim-lang/Nim/issues/12625
    when compiles(s.len):
      block: # using a block avoids https://github.com/nim-lang/Nim/issues/8580

        # BUG: `evalOnceAs(s2, s, false)` would lead to C compile errors
        # (`error: use of undeclared identifier`) instead of Nim compile errors
        evalOnceAs(s2, s, compiles((let _ = s)))

        var i = 0
        var result = newSeq[OutType](s2.len)
        for it {.inject.} in s2:
          result[i] = op
          i += 1
        result
    else:
      var result: seq[OutType]# = @[]
      # use `items` to avoid https://github.com/nim-lang/Nim/issues/12639
      for it {.inject.} in items(s):
        result.add(op)
      result
  else:
    # `op` is going to create closures in loops, let's fallback to `map`.
    # NOTE: Without this fallback, developers have to define a helper function and
    # call `map`:
    #   [1, 2].map((it) => ((x: int) => it + x))
    # With this fallback, above code can be simplified to:
    #   [1, 2].mapIt((x: int) => it + x)
    # In this case, `mapIt` is just syntax sugar for `map`.
    type InType = typeof(items(s), typeOfIter)
    # Use a help proc `f` to create closures for each element in `s`
    let f = proc (x: InType): OutType =
              let it {.inject.} = x
              op
    map(s, f)

template applyIt*(varSeq, op: untyped) =
  ## Convenience template around the mutable `apply` proc to reduce typing.
  ##
  ## The template injects the `it` variable which you can use directly in an
  ## expression. The expression has to return the same type as the elements
  ## of the sequence you are mutating.
  ##
  ## **See also:**
  ## * `apply proc<#apply,openArray[T],proc(T)_2>`_
  ## * `mapIt template<#mapIt.t,typed,untyped>`_
  ##
  runnableExamples:
    var nums = @[1, 2, 3, 4]
    nums.applyIt(it * 3)
    assert nums[0] + nums[3] == 15

  for i in low(varSeq) .. high(varSeq):
    let it {.inject.} = varSeq[i]
    varSeq[i] = op


template newSeqWith*(len: int, init: untyped): untyped =
  ## Creates a new `seq` of length `len`, calling `init` to initialize
  ## each value of the seq.
  ##
  ## Useful for creating "2D" seqs - seqs containing other seqs
  ## or to populate fields of the created seq.
  runnableExamples:
    ## Creates a seq containing 5 bool seqs, each of length of 3.
    var seq2D = newSeqWith(5, newSeq[bool](3))
    assert seq2D.len == 5
    assert seq2D[0].len == 3
    assert seq2D[4][2] == false

    ## Creates a seq with random numbers
    import std/random
    var seqRand = newSeqWith(20, rand(1.0))
    assert seqRand[0] != seqRand[1]
  type T = typeof(init)
  let newLen = len
  when supportsCopyMem(T) and declared(newSeqUninit):
    var result = newSeqUninit[T](newLen)
  else: # TODO: use `newSeqUnsafe` when that's available
    var result = newSeq[T](newLen)
  for i in 0 ..< newLen:
    result[i] = init
  move(result) # refs bug #7295

func mapLitsImpl(constructor: NimNode; op: NimNode; nested: bool;
                 filter = nnkLiterals): NimNode =
  if constructor.kind in filter:
    result = newNimNode(nnkCall, lineInfoFrom = constructor)
    result.add op
    result.add constructor
  else:
    result = copyNimNode(constructor)
    for v in constructor:
      if nested or v.kind in filter:
        result.add mapLitsImpl(v, op, nested, filter)
      else:
        result.add v

macro mapLiterals*(constructor, op: untyped;
                   nested = true): untyped =
  ## Applies `op` to each of the **atomic** literals like `3`
  ## or `"abc"` in the specified `constructor` AST. This can
  ## be used to map every array element to some target type:
  runnableExamples:
    let x = mapLiterals([0.1, 1.2, 2.3, 3.4], int)
    doAssert x is array[4, int]
    doAssert x == [int(0.1), int(1.2), int(2.3), int(3.4)]
  ## If `nested` is true (which is the default), the literals are replaced
  ## everywhere in the `constructor` AST, otherwise only the first level
  ## is considered:
  runnableExamples:
    let a = mapLiterals((1.2, (2.3, 3.4), 4.8), int)
    let b = mapLiterals((1.2, (2.3, 3.4), 4.8), int, nested=false)
    assert a == (1, (2, 3), 4)
    assert b == (1, (2.3, 3.4), 4)

    let c = mapLiterals((1, (2, 3), 4, (5, 6)), `$`)
    let d = mapLiterals((1, (2, 3), 4, (5, 6)), `$`, nested=false)
    assert c == ("1", ("2", "3"), "4", ("5", "6"))
    assert d == ("1", (2, 3), "4", (5, 6))
  ## There are no constraints for the `constructor` AST, it
  ## works for nested tuples of arrays of sets etc.
  result = mapLitsImpl(constructor, op, nested.boolVal)

iterator items*[T](xs: iterator: T): T =
  ## Iterates over each element yielded by a closure iterator. This may
  ## not seem particularly useful on its own, but this allows closure
  ## iterators to be used by the mapIt, filterIt, allIt, anyIt, etc.
  ## templates.
  for x in xs():
    yield x

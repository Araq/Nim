## Default iterators for some Nim types.

when defined(nimPreviewSlimSystem):
  import std/assertions

when not defined(nimNoLentIterators):
  template lent2(T): untyped = lent T
else:
  template lent2(T): untyped = T

template unCheckedInc(x) =
  {.push overflowChecks: off.}
  inc(x)
  {.pop.}

iterator items*[T: not char](a: openArray[T]): lent2 T {.inline.} =
  ## Iterates over each item of `a`.
  var i = 0
  while i < len(a):
    yield a[i]
    unCheckedInc(i)

iterator items*[T: char](a: openArray[T]): T {.inline.} =
  ## Iterates over each item of `a`.
  # a VM bug currently prevents taking address of openArray[char]
  # elements converted from a string (would fail in `tests/misc/thallo.nim`)
  # in any case there's no performance advantage of returning char by address.
  var i = 0
  while i < len(a):
    yield a[i]
    unCheckedInc(i)

iterator mitems*[T](a: var openArray[T]): var T {.inline.} =
  ## Iterates over each item of `a` so that you can modify the yielded value.
  var i = 0
  while i < len(a):
    yield a[i]
    unCheckedInc(i)

iterator items*[IX, T](a: array[IX, T]): lent2 T {.inline.} =
  ## Iterates over each item of `a`.
  when a.len > 0:
    var i = low(IX)
    while true:
      yield a[i]
      if i >= high(IX): break
      unCheckedInc(i)

iterator mitems*[IX, T](a: var array[IX, T]): var T {.inline.} =
  ## Iterates over each item of `a` so that you can modify the yielded value.
  when a.len > 0:
    var i = low(IX)
    while true:
      yield a[i]
      if i >= high(IX): break
      unCheckedInc(i)

iterator items*[T](a: set[T]): T {.inline.} =
  ## Iterates over each element of `a`. `items` iterates only over the
  ## elements that are really in the set (and not over the ones the set is
  ## able to hold).
  var i = low(T).int
  while i <= high(T).int:
    when T is enum and not defined(js):
      if cast[T](i) in a: yield cast[T](i)
    else:
      if T(i) in a: yield T(i)
    unCheckedInc(i)

iterator items*(a: cstring): char {.inline.} =
  ## Iterates over each item of `a`.
  runnableExamples:
    from std/sequtils import toSeq
    assert toSeq("abc\0def".cstring) == @['a', 'b', 'c']
    assert toSeq("abc".cstring) == @['a', 'b', 'c']
  #[
  assert toSeq(nil.cstring) == @[] # xxx fails with SIGSEGV
  this fails with SIGSEGV; unclear whether we want to instead yield nothing
  or pay a small price to check for `nil`, a benchmark is needed. Note that
  other procs support `nil`.
  ]#
  template impl() =
    var i = 0
    let n = len(a)
    while i < n:
      yield a[i]
      unCheckedInc(i)
  when defined(js): impl()
  else:
    when nimvm:
      # xxx `cstring` should behave like c backend instead.
      impl()
    else:
      var i = 0
      while a[i] != '\0':
        yield a[i]
        unCheckedInc(i)

iterator mitems*(a: var cstring): var char {.inline.} =
  ## Iterates over each item of `a` so that you can modify the yielded value.
  # xxx this should give CT error in js RT.
  runnableExamples:
    from std/sugar import collect
    var a = "abc\0def"
    prepareMutation(a)
    var b = a.cstring
    let s = collect:
      for bi in mitems(b):
        if bi == 'b': bi = 'B'
        bi
    assert s == @['a', 'B', 'c']
    assert b == "aBc"
    assert a == "aBc\0def"

  template impl() =
    var i = 0
    let n = len(a)
    while i < n:
      yield a[i]
      unCheckedInc(i)
  when defined(js): impl()
  else:
    when nimvm: impl()
    else:
      var i = 0
      while a[i] != '\0':
        yield a[i]
        unCheckedInc(i)

iterator items*[T: enum and Ordinal](E: typedesc[T]): T =
  ## Iterates over the values of `E`.
  ## See also `enumutils.items` for enums with holes.
  runnableExamples:
    type Goo = enum g0 = 2, g1, g2
    from std/sequtils import toSeq
    assert Goo.toSeq == [g0, g1, g2]
  for v in low(E) .. high(E):
    yield v

iterator items*[T: Ordinal](s: Slice[T]): T =
  ## Iterates over the slice `s`, yielding each value between `s.a` and `s.b`
  ## (inclusively).
  for x in s.a .. s.b:
    yield x

iterator pairs*[T](a: openArray[T]): tuple[key: int, val: T] {.inline.} =
  ## Iterates over each item of `a`. Yields `(index, a[index])` pairs.
  var i = 0
  while i < len(a):
    yield (i, a[i])
    unCheckedInc(i)

iterator mpairs*[T](a: var openArray[T]): tuple[key: int, val: var T]{.inline.} =
  ## Iterates over each item of `a`. Yields `(index, a[index])` pairs.
  ## `a[index]` can be modified.
  var i = 0
  while i < len(a):
    yield (i, a[i])
    unCheckedInc(i)

iterator pairs*[IX, T](a: array[IX, T]): tuple[key: IX, val: T] {.inline.} =
  ## Iterates over each item of `a`. Yields `(index, a[index])` pairs.
  when a.len > 0:
    var i = low(IX)
    while true:
      yield (i, a[i])
      if i >= high(IX): break
      unCheckedInc(i)

iterator mpairs*[IX, T](a: var array[IX, T]): tuple[key: IX, val: var T] {.inline.} =
  ## Iterates over each item of `a`. Yields `(index, a[index])` pairs.
  ## `a[index]` can be modified.
  when a.len > 0:
    var i = low(IX)
    while true:
      yield (i, a[i])
      if i >= high(IX): break
      unCheckedInc(i)

iterator pairs*[T](a: seq[T]): tuple[key: int, val: T] {.inline.} =
  ## Iterates over each item of `a`. Yields `(index, a[index])` pairs.
  var i = 0
  let L = len(a)
  while i < L:
    yield (i, a[i])
    unCheckedInc(i)
    assert(len(a) == L, "the length of the seq changed while iterating over it")

iterator mpairs*[T](a: var seq[T]): tuple[key: int, val: var T] {.inline.} =
  ## Iterates over each item of `a`. Yields `(index, a[index])` pairs.
  ## `a[index]` can be modified.
  var i = 0
  let L = len(a)
  while i < L:
    yield (i, a[i])
    unCheckedInc(i)
    assert(len(a) == L, "the length of the seq changed while iterating over it")

iterator pairs*(a: string): tuple[key: int, val: char] {.inline.} =
  ## Iterates over each item of `a`. Yields `(index, a[index])` pairs.
  var i = 0
  let L = len(a)
  while i < L:
    yield (i, a[i])
    unCheckedInc(i)
    assert(len(a) == L, "the length of the string changed while iterating over it")

iterator mpairs*(a: var string): tuple[key: int, val: var char] {.inline.} =
  ## Iterates over each item of `a`. Yields `(index, a[index])` pairs.
  ## `a[index]` can be modified.
  var i = 0
  let L = len(a)
  while i < L:
    yield (i, a[i])
    unCheckedInc(i)
    assert(len(a) == L, "the length of the string changed while iterating over it")

iterator pairs*(a: cstring): tuple[key: int, val: char] {.inline.} =
  ## Iterates over each item of `a`. Yields `(index, a[index])` pairs.
  when defined(js):
    var i = 0
    var L = len(a)
    while i < L:
      yield (i, a[i])
      unCheckedInc(i)
  else:
    var i = 0
    while a[i] != '\0':
      yield (i, a[i])
      unCheckedInc(i)

iterator mpairs*(a: var cstring): tuple[key: int, val: var char] {.inline.} =
  ## Iterates over each item of `a`. Yields `(index, a[index])` pairs.
  ## `a[index]` can be modified.
  when defined(js):
    var i = 0
    var L = len(a)
    while i < L:
      yield (i, a[i])
      unCheckedInc(i)
  else:
    var i = 0
    while a[i] != '\0':
      yield (i, a[i])
      unCheckedInc(i)

iterator items*[T](a: seq[T]): lent2 T {.inline.} =
  ## Iterates over each item of `a`.
  var i = 0
  let L = len(a)
  while i < L:
    yield a[i]
    unCheckedInc(i)
    assert(len(a) == L, "the length of the seq changed while iterating over it")

iterator mitems*[T](a: var seq[T]): var T {.inline.} =
  ## Iterates over each item of `a` so that you can modify the yielded value.
  var i = 0
  let L = len(a)
  while i < L:
    yield a[i]
    unCheckedInc(i)
    assert(len(a) == L, "the length of the seq changed while iterating over it")

iterator items*(a: string): char {.inline.} =
  ## Iterates over each item of `a`.
  var i = 0
  let L = len(a)
  while i < L:
    yield a[i]
    unCheckedInc(i)
    assert(len(a) == L, "the length of the string changed while iterating over it")

iterator mitems*(a: var string): var char {.inline.} =
  ## Iterates over each item of `a` so that you can modify the yielded value.
  var i = 0
  let L = len(a)
  while i < L:
    yield a[i]
    unCheckedInc(i)
    assert(len(a) == L, "the length of the string changed while iterating over it")


iterator fields*[T: tuple|object](x: T): RootObj {.
  magic: "Fields", noSideEffect.} =
  ## Iterates over every field of `x`.
  ##
  ## .. warning:: This really transforms the 'for' and unrolls the loop.
  ##   The current implementation also has a bug
  ##   that affects symbol binding in the loop body.
  runnableExamples:
    var t = (1, "foo")
    for v in fields(t): v = default(typeof(v))
    doAssert t == (0, "")

iterator fields*[S:tuple|object, T:tuple|object](x: S, y: T): tuple[key: string, val: RootObj] {.
  magic: "Fields", noSideEffect.} =
  ## Iterates over every field of `x` and `y`.
  ##
  ## .. warning:: This really transforms the 'for' and unrolls the loop.
  ##   The current implementation also has a bug that affects symbol binding
  ##   in the loop body.
  runnableExamples:
    var t1 = (1, "foo")
    var t2 = default(typeof(t1))
    for v1, v2 in fields(t1, t2): v2 = v1
    doAssert t1 == t2

iterator fieldPairs*[T: tuple|object](x: T): tuple[key: string, val: RootObj] {.
  magic: "FieldPairs", noSideEffect.} =
  ## Iterates over every field of `x` returning their name and value.
  ##
  ## When you iterate over objects with different field types you have to use
  ## the compile time `when` instead of a runtime `if` to select the code
  ## you want to run for each type. To perform the comparison use the `is
  ## operator <manual.html#generics-is-operator>`_.
  ## Another way to do the same without `when` is to leave the task of
  ## picking the appropriate code to a secondary proc which you overload for
  ## each field type and pass the `value` to.
  ##
  ## .. warning:: This really transforms the 'for' and unrolls the loop. The
  ##   current implementation also has a bug that affects symbol binding in the
  ##   loop body.
  runnableExamples:
    type
      Custom = object
        foo: string
        bar: bool
    proc `$`(x: Custom): string =
      result = "Custom:"
      for name, value in x.fieldPairs:
        when value is bool:
          result.add("\n\t" & name & " is " & $value)
        else:
          result.add("\n\t" & name & " '" & value & "'")

iterator fieldPairs*[S: tuple|object, T: tuple|object](x: S, y: T): tuple[
  key: string, a, b: RootObj] {.
  magic: "FieldPairs", noSideEffect.} =
  ## Iterates over every field of `x` and `y`.
  ##
  ## .. warning:: This really transforms the 'for' and unrolls the loop.
  ##   The current implementation also has a bug that affects symbol binding
  ##   in the loop body.
  runnableExamples:
    type Foo = object
      x1: int
      x2: string
    var a1 = Foo(x1: 12, x2: "abc")
    var a2: Foo
    for name, v1, v2 in fieldPairs(a1, a2):
      when name == "x2": v2 = v1
    doAssert a2 == Foo(x1: 0, x2: "abc")

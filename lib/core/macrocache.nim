#
#
#            Nim's Runtime Library
#        (c) Copyright 2018 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module provides an API for macros to collect compile-time information
## across module boundaries. It should be used instead of global `{.compileTime.}`
## variables as those break incremental compilation.
##
## The main feature of this module is that if you create `CacheTable`s or
## any other `Cache` types with the same name in different modules, their
## content will be shared, meaning that you can fill a `CacheTable` in
## one module, and iterate over its contents in another.

runnableExamples:
  import std/macros

  const mcTable = CacheTable"myTable"
  const mcSeq = CacheSeq"mySeq"
  const mcCounter = CacheCounter"myCounter"

  static:
    # add new key "val" with the value `myval`
    let myval = newLit("hello ic")
    mcTable["val"] = myval
    assert mcTable["val"].kind == nnkStrLit

  # Can access the same cache from different static contexts
  # All the information is retained
  static:
    # get value from `mcTable` and add it to `mcSeq`
    mcSeq.add(mcTable["val"])
    assert mcSeq.len == 1

  static:
    assert mcSeq[0].strVal == "hello ic"

    # increase `mcCounter` by 3
    mcCounter.inc(3)
    assert mcCounter.value == 3


when defined(nimPreviewSlimSystem):
  import std/assertions

type
  CacheSeq* = distinct string
    ## Compile-time sequence of `NimNode`s.
  CacheTable* = distinct string
    ## Compile-time table of key-value pairs.
    ##
    ## Keys are `string`s and values are `NimNode`s.
  CacheCounter* = distinct string
    ## Compile-time counter, uses `int` for storing the count.

proc value*(c: CacheCounter): int {.magic: "NccValue".} =
  ## Returns the value of a counter `c`.
  runnableExamples:
    static:
      let counter = CacheCounter"valTest"
      # default value is 0
      assert counter.value == 0

      inc counter
      assert counter.value == 1

proc inc*(c: CacheCounter; by = 1) {.magic: "NccInc".} =
  ## Increments the counter `c` with the value `by`.
  runnableExamples:
    static:
      let counter = CacheCounter"incTest"
      inc counter
      inc counter, 5

      assert counter.value == 6

proc add*(s: CacheSeq; value: NimNode) {.magic: "NcsAdd".} =
  ## Adds `value` to `s`.
  runnableExamples:
    import std/macros
    const mySeq = CacheSeq"addTest"

    static:
      mySeq.add(newLit(5))
      mySeq.add(newLit("hello ic"))

      assert mySeq.len == 2
      assert mySeq[1].strVal == "hello ic"

proc incl*(s: CacheSeq; value: NimNode) {.magic: "NcsIncl".} =
  ## Adds `value` to `s`.
  ##
  ## .. hint:: This doesn't do anything if `value` is already in `s`.
  runnableExamples:
    import std/macros
    const mySeq = CacheSeq"inclTest"

    static:
      mySeq.incl(newLit(5))
      mySeq.incl(newLit(5))

      # still one element
      assert mySeq.len == 1

proc len*(s: CacheSeq): int {.magic: "NcsLen".} =
  ## Returns the length of `s`.
  runnableExamples:
    import std/macros

    const mySeq = CacheSeq"lenTest"
    static:
      let val = newLit("helper")
      mySeq.add(val)
      assert mySeq.len == 1

      mySeq.add(val)
      assert mySeq.len == 2

proc `[]`*(s: CacheSeq; i: int): NimNode {.magic: "NcsAt".} =
  ## Returns the `i`th value from `s`.
  runnableExamples:
    import std/macros

    const mySeq = CacheSeq"subTest"
    static:
      mySeq.add(newLit(42))
      assert mySeq[0].intVal == 42

proc `[]`*(s: CacheSeq; i: BackwardsIndex): NimNode =
  ## Returns the `i`th last value from `s`.
  runnableExamples:
    import std/macros

    const mySeq = CacheSeq"backTest"
    static:
      mySeq &= newLit(42)
      mySeq &= newLit(7)
      assert mySeq[^1].intVal == 7  # Last item
      assert mySeq[^2].intVal == 42 # Second last item
  s[s.len - int(i)]

iterator items*(s: CacheSeq): NimNode =
  ## Iterates over each item in `s`.
  runnableExamples:
    import std/macros
    const myseq = CacheSeq"itemsTest"

    static:
      myseq.add(newLit(5))
      myseq.add(newLit(42))

      for val in myseq:
        # check that all values in `myseq` are int literals
        assert val.kind == nnkIntLit

  for i in 0 ..< len(s): yield s[i]

proc `[]=`*(t: CacheTable; key: string, value: NimNode) {.magic: "NctPut".} =
  ## Inserts a `(key, value)` pair into `t`.
  ##
  ## .. warning:: `key` has to be unique! Assigning `value` to a `key` that is already
  ##   in the table will result in a compiler error.
  runnableExamples:
    import std/macros

    const mcTable = CacheTable"subTest"
    static:
      # assign newLit(5) to the key "value"
      mcTable["value"] = newLit(5)

      # check that we can get the value back
      assert mcTable["value"].kind == nnkIntLit

proc len*(t: CacheTable): int {.magic: "NctLen".} =
  ## Returns the number of elements in `t`.
  runnableExamples:
    import std/macros

    const dataTable = CacheTable"lenTest"
    static:
      dataTable["key"] = newLit(5)
      assert dataTable.len == 1

proc `[]`*(t: CacheTable; key: string): NimNode {.magic: "NctGet".} =
  ## Retrieves the `NimNode` value at `t[key]`.
  runnableExamples:
    import std/macros

    const mcTable = CacheTable"subTest"
    static:
      mcTable["toAdd"] = newStmtList()

      # get the NimNode back
      assert mcTable["toAdd"].kind == nnkStmtList

proc hasKey*(t: CacheTable; key: string): bool =
  ## Returns true if `key` is in the table `t`.
  ##
  ## See also:
  ## * [contains proc][contains(CacheTable, string)] for use with the `in` operator
  runnableExamples:
    import std/macros
    const mcTable = CacheTable"hasKeyEx"
    static:
      assert not mcTable.hasKey("foo")
      mcTable["foo"] = newEmptyNode()
      # Will now be true since we inserted a value
      assert mcTable.hasKey("foo")
  raiseAssert "implemented in the vmops"

proc contains*(t: CacheTable; key: string): bool {.inline.} =
  ## Alias of [hasKey][hasKey(CacheTable, string)] for use with the `in` operator.
  runnableExamples:
    import std/macros
    const mcTable = CacheTable"containsEx"
    static:
      mcTable["foo"] = newEmptyNode()
      # Will be true since we gave it a value before
      assert "foo" in mcTable
  t.hasKey(key)

proc hasNext(t: CacheTable; iter: int): bool {.magic: "NctHasNext".}
proc next(t: CacheTable; iter: int): (string, NimNode, int) {.magic: "NctNext".}

iterator pairs*(t: CacheTable): (string, NimNode) =
  ## Iterates over all `(key, value)` pairs in `t`.
  runnableExamples:
    import std/macros
    const mytabl = CacheTable"values"

    static:
      mytabl["intVal"] = newLit(5)
      mytabl["otherVal"] = newLit(6)
      for key, val in mytabl:
        # make sure that we actually get the same keys
        assert key in ["intVal", "otherVal"]

        # all vals are int literals
        assert val.kind == nnkIntLit

  var h = 0
  while hasNext(t, h):
    let (a, b, h2) = next(t, h)
    yield (a, b)
    h = h2

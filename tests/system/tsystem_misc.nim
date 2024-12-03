discard """
  output:'''1
1
2
3
11
12
13
14
15
2
3
4
2
1
2
3
2
48
49
50
51
52
53
54
55
56
57
2
'''
"""


block:
  const a2 = $(int)
  const a3 = $int
  doAssert a2 == "int"
  doAssert a3 == "int"

  proc fun[T: typedesc](t: T) =
    const a2 = $(t)
    const a3 = $t
    doAssert a2 == "int"
    doAssert a3 == "int"
  fun(int)

# check high/low implementations
doAssert high(int) > low(int)
doAssert high(int8) > low(int8)
doAssert high(int16) > low(int16)
doAssert high(int32) > low(int32)
doAssert high(int64) > low(int64)
# doAssert high(uint) > low(uint) # reconsider depending on issue #6620
doAssert high(uint8) > low(uint8)
doAssert high(uint16) > low(uint16)
doAssert high(uint32) > low(uint32)
# doAssert high(uint64) > low(uint64) # reconsider depending on issue #6620
doAssert high(float) > low(float)
doAssert high(float32) > low(float32)
doAssert high(float64) > low(float64)

proc foo(a: openArray[int]) =
  for x in a: echo x

foo(toOpenArray([1, 2, 3], 0, 0))

foo(toOpenArray([1, 2, 3], 0, 2))

var arr: array[8..12, int] = [11, 12, 13, 14, 15]

foo(toOpenArray(arr, 8, 12))

var seqq = @[1, 2, 3, 4, 5]
foo(toOpenArray(seqq, 1, 3))

# empty openArray issue #7904
foo(toOpenArray(seqq, 0, -1))
foo(toOpenArray(seqq, 1, 0))
doAssertRaises(IndexDefect):
  foo(toOpenArray(seqq, 0, -2))

foo(toOpenArray(arr, 9, 8))
foo(toOpenArray(arr, 0, -1))
foo(toOpenArray(arr, 1, 0))
doAssertRaises(IndexDefect):
  foo(toOpenArray(arr, 10, 8))

# test openArray of openArray
proc oaEmpty(a: openArray[int]) =
  foo(toOpenArray(a, 0, -1))

proc oaFirstElm(a: openArray[int]) =
  foo(toOpenArray(a, 0, 0))

oaEmpty(toOpenArray(seqq, 0, -1))
oaEmpty(toOpenArray(seqq, 1, 0))
oaEmpty(toOpenArray(seqq, 1, 2))
oaFirstElm(toOpenArray(seqq, 1, seqq.len-1))

var arrNeg: array[-3 .. -1, int] = [1, 2, 3]
foo(toOpenArray(arrNeg, -3, -1))
foo(toOpenArray(arrNeg, 0, -1))
foo(toOpenArray(arrNeg, -3, -4))
doAssertRaises(IndexDefect):
  foo(toOpenArray(arrNeg, -4, -1))
doAssertRaises(IndexDefect):
  foo(toOpenArray(arrNeg, -1, 0))
doAssertRaises(IndexDefect):
  foo(toOpenArray(arrNeg, -1, -3))
doAssertRaises(Exception):
  raise newException(Exception, "foo")

block:
  var didThrow = false
  try:
    doAssertRaises(IndexDefect): # should fail since it's wrong exception
      raise newException(FieldDefect, "foo")
  except AssertionDefect:
    # ok, throwing was correct behavior
    didThrow = true
  doAssert didThrow

type seqqType = ptr UncheckedArray[int]
let qData = cast[seqqType](addr seqq[0])
oaFirstElm(toOpenArray(qData, 1, 3))

proc foo(a: openArray[byte]) =
  for x in a: echo x

let str = "0123456789"
foo(toOpenArrayByte(str, 0, str.high))


template boundedOpenArray[T](x: seq[T], first, last: int): openArray[T] =
  toOpenarray(x, max(0, first), min(x.high, last))

# bug #9281

proc foo[T](x: openArray[T]) =
  echo x.len

let a = @[1, 2, 3]

# a.boundedOpenArray(1, 2).foo()  # Works
echo a.boundedOpenArray(1, 2).len # Internal compiler error

block: # `$`*[T: tuple|object](x: T)
  doAssert $(foo1:0, bar1:"a") == """(foo1: 0, bar1: "a")"""
  doAssert $(foo1:0, ) == """(foo1: 0)"""
  doAssert $(0, "a") == """(0, "a")"""
  doAssert $(0, ) == "(0,)"
  type Foo = object
    x:int
    x2:float
  doAssert $Foo(x:2) == "(x: 2, x2: 0.0)"
  doAssert $() == "()"

# this is a call indirection to prevent `toInt` to be resolved at compile time.
proc testToInt(arg: float64, a: int, b: BiggestInt) =
  doAssert toInt(arg) == a
  doAssert toBiggestInt(arg) == b

testToInt(0.45, 0, 0)    # should round towards 0
testToInt(-0.45, 0, 0)   # should round towards 0
testToInt(0.5, 1, 1)     # should round away from 0
testToInt(-0.5, -1, -1)  # should round away from 0
testToInt(13.37, 13, 13)    # should round towards 0
testToInt(-13.37, -13, -13) # should round towards 0
testToInt(7.8, 8, 8)     # should round away from 0
testToInt(-7.8, -8, -8)  # should round away from 0

# test min/max for correct NaN handling

proc testMinMax(a,b: float32) =
  doAssert max(float32(a),float32(b)) == 0'f32
  doAssert min(float32(a),float32(b)) == 0'f32
  doAssert max(float64(a),float64(b)) == 0'f64
  doAssert min(float64(a),float64(b)) == 0'f64

testMinMax(0.0, NaN)
testMinMax(NaN, 0.0)


block:
  type Foo = enum
    k1, k2
  var
    a = {k1}
    b = {k1,k2}
  doAssert a < b


block: # Ordinal
  doAssert int is Ordinal
  doAssert uint is Ordinal
  doAssert int64 is Ordinal
  doAssert uint64 is Ordinal
  doAssert char is Ordinal
  type Foo = enum k1, k2
  doAssert Foo is Ordinal
  doAssert Foo is SomeOrdinal
  doAssert enum is SomeOrdinal

  # these fail:
  # doAssert enum is Ordinal # fails
  # doAssert Ordinal is SomeOrdinal
  # doAssert SomeOrdinal is Ordinal

block:
  proc p() = discard

  doAssert not compiles(echo p.rawProc.repr)
  doAssert not compiles(echo p.rawEnv.repr)
  doAssert not compiles(echo p.finished)

proc bug23223 = # bug #23223
  var stuff = "hello"
  stuff.insert ""
  doAssert stuff == "hello"

bug23223()

block: # bug #23894
  let v = high(uint) div 2
  let s = v + 1 # 9223372036854775808
  let m = succ v
  doAssert s == m

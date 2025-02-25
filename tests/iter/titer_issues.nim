discard """
  target: "c js"
  output: '''
0
1
2
3
4
1
start
false
0
1
2
end
@[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 18, 20, 21, 24, 27, 30, 36, 40, 42]
1002
0
1
2
7
9002
9004
9006
9008
9010
9012
9014
9016
9018
@[1, 2]
@[1, 2, 3]
1
nested finally
outer finally
nested finally
outer finally
nested finally
outer finally
nested finally
outer finally
In defer
trying
exception caught
finally block
'''
"""


import sequtils, strutils


block t338:
  proc moo(): iterator (): int =
    iterator fooGen: int {.closure.} =
      while true:
        yield result
        result.inc
    return fooGen

  var foo = moo()

  for i in 0 .. 4:
    echo foo()



block t8041:
  iterator xy[T](a: T, b: set[T]): T =
    if a in b:
      yield a

  for a in xy(1'i8, {}):
    for b in xy(a, {}):
      echo a



block t3837_chained:
  iterator t1(): int {.closure.} =
    yield 1

  iterator t2(): int {.closure.} =
    for i in t1():
      yield i

  for i in t2():
    echo $i


  proc iter1(): (iterator: int) =
    let coll = [0,1,2]
    result = iterator: int {.closure.} =
      for i in coll:
        yield i

  proc iter2(it: (iterator: int)): (iterator: int)  =
    result = iterator: int {.closure.} =
      echo finished(it)
      for i in it():
        yield i

  echo "start"
  let myiter1 = iter1()
  let myiter2 = iter2(myiter1)
  for i in myiter2():
    echo i
  echo "end"


  type Iterable[T] = (iterator: T) | Slice[T]
    ## Everything that can be iterated over, iterators and slices so far.

  proc toIter[T](s: Slice[T]): iterator: T =
    ## Iterate over a slice.
    iterator it: T {.closure.} =
      for x in s.a..s.b:
        yield x
    return it

  proc toIter[T](i: iterator: T): iterator: T =
    ## Nop
    i

  iterator map[T,S](i: Iterable[T], f: proc(x: T): S): S =
    let i = toIter(i)
    for x in i():
      yield f(x)

  proc filter[T](i: Iterable[T], f: proc(x: T): bool): iterator: T =
    let i = toIter(i)
    iterator it: T {.closure.} =
      for x in i():
        if f(x):
          yield x
    result = it

  iterator filter[T](i: Iterable[T], f: proc(x: T): bool): T =
    let i = toIter(i)
    for x in i():
      if f(x):
        yield x

  var it = toSeq(filter(2..10, proc(x: int): bool = x mod 2 == 0))
  doAssert it == @[2, 4, 6, 8, 10]
  it = toSeq(map(filter(2..10, proc(x: int): bool = x mod 2 == 0), proc(x: int): int = x * 2))
  doAssert it == @[4, 8, 12, 16, 20]



block t3221_complex:
  iterator permutations[T](ys: openArray[T]): seq[T] =
    var
      d = 1
      c = newSeq[int](ys.len)
      xs = newSeq[T](ys.len)
    for i, y in ys: xs[i] = y
    yield xs
    block outer:
      while true:
        while d > 1:
          dec d
          c[d] = 0
        while c[d] >= d:
          inc d
          if d >= ys.len: break outer
        let i = if (d and 1) == 1: c[d] else: 0
        swap xs[i], xs[d]
        yield xs
        inc c[d]

  proc dig_vectors(): void =
    var v_nums: seq[int]
    v_nums = newSeq[int](1)
    for perm in permutations(toSeq(0 .. 1)):
      v_nums[0] = 1

  dig_vectors()



block t3499_keepstate:
  proc slice[T](iter: iterator(): T {.closure.}, sl: auto): seq[T] =
    var res: seq[int64] = @[]
    var i = 0
    for n in iter():
      if i > sl.b:
        break
      if i >= sl.a:
        res.add(n)
      inc i
    res

  iterator harshad(): int64 {.closure.} =
    for n in 1 ..< int64.high:
      var sum = 0
      for ch in string($n):
        sum += parseInt("" & ch)
      if n mod sum == 0:
        yield n

  echo harshad.slice 0 ..< 20

  for n in harshad():
    if n > 1000:
      echo n
      break

  # bug #3499 last snippet fixed
  # bug #705  last snippet fixed



block t1725_nested:
  iterator factory(): int {.closure.} =
    iterator bar(): int {.closure.} =
      yield 0
      yield 1
      yield 2

    for x in bar(): yield x

  for x in factory():
    echo x



block t2023_objiter:
  type
    Obj = object
      iter: iterator (): int8 {.closure.}

  iterator test(): int8 {.closure.} =
    yield 7

  proc init():Obj=
    result.iter = test

  var o = init()
  echo(o.iter())


block:
  # bug #13739
  iterator myIter(arg: openArray[int]): int =
    var tmp = 0
    let len = arg.len
    while tmp < len:
      yield arg[tmp] * 2
      inc tmp

  proc someProc() =
    var data = [4501,4502,4503,4504,4505,4506,4507,4508,4509]
    # StmtListExpr should not get special treatment.
    for x in myIter((discard;data)):
      echo x

  someProc()

block:
  # bug #12576
  iterator ff(sq: varargs[seq[int]]): int =
    for x in sq:
      echo x

  for x in ff(@[1, 2], @[1, 2, 3]):
    echo x


# bug #19575

iterator bb() {.closure.} =
    while true:
        try: discard
        except: break
        finally: break

var a = bb

iterator cc() {.closure.} =
    while true:
        try: discard
        except:
          if true:
            break
        finally:
          if true:
            break

var a2 = cc

# bug #16876
block:
  iterator a(num: int): int {.closure.} =
      if num == 1:
          yield num
      else:
          for i in a(num - 1):
              yield i

  for i in a(5):
    echo i

block:
  # bug #19911 (return in nested try)

  # try yield -> try
  iterator p1: int {.closure.} =
    try:
      yield 0
      try:
        return
      finally:
        echo "nested finally"
      echo "shouldn't run"
    finally:
      echo "outer finally"
    echo "shouldn't run"

  for _ in p1():
    discard

  # try -> try yield
  iterator p2: int {.closure.} =
    try:
      try:
        yield 0
        return
      finally:
        echo "nested finally"
      echo "shouldn't run"
    finally:
      echo "outer finally"
    echo "shouldn't run"

  for _ in p2():
    discard

  # try yield -> try yield
  iterator p3: int {.closure.} =
    try:
      yield 0
      try:
        yield 0
        return
      finally:
        echo "nested finally"
      echo "shouldn't run"
    finally:
      echo "outer finally"
    echo "shouldn't run"

  for _ in p3():
    discard

  # try -> try
  iterator p4: int {.closure.} =
    try:
      try:
        return
      finally:
        echo "nested finally"
      echo "shouldn't run"
    finally:
      echo "outer finally"
    echo "shouldn't run"

  for _ in p4():
    discard

# bug #18824
iterator poc_iterator: int {.closure.}  =
  block bug18824:
    try:
      break bug18824
    finally:
      echo "In defer"

for _ in poc_iterator():
  discard

# bug #20624
iterator tryFinally() {.closure.} =
  block route:
    try:
      echo "trying"
      raise
    except:
      echo "exception caught"
      break route
    finally:
      echo "finally block"

var x = tryFinally
x()

block: # bug #24033
  type Query = ref object

  iterator pairs(query: Query): (int, (string, float32)) =
    var output: (int, (string, float32)) = (0, ("foo", 3.14))
    for id in @[0, 1, 2]:
      output[0] = id
      yield output

  var collections: seq[(int, string, string)]

  for id, (str, num) in Query():
    collections.add (id, str, $num)

  doAssert collections[1] == (1, "foo", "3.14")

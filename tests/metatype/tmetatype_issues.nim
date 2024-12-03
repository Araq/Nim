discard """
output:'''
void
("string", "string")
1 mod 7
@[2, 2, 2, 2, 2]
impl 2 called
asd
Foo
Bar
'''
joinable: false
"""

import typetraits, macros


block t898:
  proc measureTime(e: auto) =
    echo e.type.name

  proc generate(a: int): void =
    discard

  proc runExample =
    var builder: int = 0

    measureTime:
      builder.generate()

  measureTime:
    discard



block t7528:
  macro bar(n: untyped) =
    result = newNimNode(nnkStmtList, n)
    result.add(newCall("write", newIdentNode("stdout"), n))

  proc foo0[T](): auto = return (T.name, T.name)
  bar foo0[string]()
  echo ""



block t5638:
  type X = object
    a_impl: int

  proc a(x: X): int =
    x.a_impl

  var x: X
  assert(not compiles((block:
    x.a = 1
  )))



block t3706:
  type Modulo[M: static[int]] = distinct int
  proc modulo(a: int, M: static[int]): Modulo[M] = Modulo[M](a %% M)
  proc `+`[M: static[int]](a, b: Modulo[M]): Modulo[M] = (a.int + b.int).modulo(M)
  proc `$`[M: static[int]](a: Modulo[M]): string = $(a.int) & " mod " & $(M)

  let
    a = 3.modulo(7)
    b = 5.modulo(7)
  echo a + b



block t3144:
  type IntArray[N: static[int]] = array[N, int]

  proc `$`(a: IntArray): string = $(@(a))

  proc `+=`[N: static[int]](a: var IntArray[N], b: IntArray[N]) =
    for i in 0 ..< N:
      a[i] += b[i]

  proc zeros(N: static[int]): IntArray[N] =
    for i in 0 ..< N:
      result[i] = 0

  proc ones(N: static[int]): IntArray[N] =
    for i in 0 ..< N:
      result[i] = 1

  proc sum[N: static[int]](vs: seq[IntArray[N]]): IntArray[N] =
    result = zeros(N)
    for v in vs:
      result += v

  echo sum(@[ones(5), ones(5)])



block t6533:
  type Value[T: static[int]] = typedesc
  proc foo(order: Value[1]): auto = 0
  doAssert foo(Value[1]) == 0



block t2266:
  proc impl(op: static[int]) = echo "impl 1 called"
  proc impl(op: static[int], init: int) = echo "impl 2 called"

  macro wrapper2: untyped = newCall(bindSym"impl", newLit(0), newLit(0))

  wrapper2() # Code generation for this fails.



block t602:
  type
    TTest = object
    TTest2 = object
    TFoo = TTest | TTest2

  proc f(src: ptr TFoo, dst: ptr TFoo) =
    echo("asd")

  var x: TTest
  f(addr x, addr x)



block t3338:
  type
    Base[T] = Foo[T] | Bar[T]

    Foo[T] = ref object
      x: T

    Bar[T] = ref object
      x: T

  proc test[T](ks: Foo[T], x, y: T): T =
    echo("Foo")
    return x + y + ks.x

  proc test[T](ks: Bar[T], x, y: T): T =
    echo("Bar")
    return x

  proc add[T](ksa: Base[T]) =
    var test = ksa.test(5, 10)
    ksa.x = test

  var t1 = Foo[int32]()
  t1.add()
  doAssert t1.x == 15

  var t2 = Bar[int32]()
  t2.add()
  doAssert t2.x == 5

block: # issue #24203
  proc b(G: typedesc) =
    type U = G
  template s(h: untyped) = h
  s(b(typeof (0, 0)))
  b(seq[int])
  b((int, int))
  b(typeof (0, 0))

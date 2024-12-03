discard """
  output: '''
20.0 USD
true
true
true
true
true
f
0
10
10
5
()
false
10
true
true
true
true
p has been called.
p has been called.
implicit generic
generic
false
true
-1
Meow
10 0.0
1 2.0
'''
joinable: false
"""

import macros, typetraits, os, posix


block t5983:
  const currencies = ["USD", "EUR"] # in real code 120 currencies

  type USD = distinct float # in real code 120 types generates using macro
  type EUR = distinct float

  type CurrencyAmount = concept c
    type t = c.type
    const name = c.type.name
    name in currencies

  proc `$`(x: CurrencyAmount): string =
    $float(x) & " " & x.name

  let amount = 20.USD
  echo amount


block t3414:
  type
    View[T] = concept v
      v.empty is bool
      v.front is T
      popFront v

  proc find(view: View; target: View.T): View =
    result = view

    while not result.empty:
      if view.front == target:
        return

      mixin popFront
      popFront result

  proc popFront[T](s: var seq[T]) = discard
  proc empty[T](s: seq[T]): bool = false

  var s1 = @[1, 2, 3]
  let s2 = s1.find(10)


block t1128:
  type
    TFooContainer[T] = object

    TContainer[T] = concept var c
      foo(c, T)

  proc foo[T](c: var TFooContainer[T], val: T) =
    discard

  proc bar(c: var TContainer) =
    discard

  var fooContainer: TFooContainer[int]
  echo fooContainer is TFooContainer # true.
  echo fooContainer is TFooContainer[int] # true.
  fooContainer.bar()



block t5642:
  type DataTable = concept x
    x is object
    for f in fields(x):
      f is seq

  type Students = object
    id : seq[int]
    name : seq[string]
    age: seq[int]

  proc nrow(dt: DataTable) : Natural =
    var totalLen = 0
    for f in fields(dt):
      totalLen += f.len
    return totalLen

  let
    stud = Students(id: @[1,2,3], name: @["Vas", "Pas", "NafNaf"], age: @[10,16,32])

  doAssert nrow(stud) == 9



import t5888lib/ca, t5888lib/opt
block t5888:
  type LocalCA = ca.CA

  proc f(c: CA) =
    echo "f"
    echo c.x

  var o = new(Opt)

  echo o is CA
  echo o is LocalCA
  echo o is ca.CA

  o.f()



import json
block t5968:
  type
    Enumerable[T] = concept e
      for it in e:
        it is T

  proc cmap[T, G](e: Enumerable[T], fn: proc(t: T): G): seq[G] =
    result = @[]
    for it in e: result.add(fn(it))

  var x = %["hello", "world"]

  var z = x.cmap(proc(it: JsonNode): string = it.getStr & "!")
  assert z == @["hello!", "world!"]



import sugar
block t6462:
  type
    FilterMixin[T] = ref object
      test: (T) -> bool
      trans: (T) -> T

    SeqGen[T] = ref object
      fil: FilterMixin[T]

    WithFilter[T] = concept a
      a.fil is FilterMixin[T]

  proc test[T](a: WithFilter[T]): (T) -> bool =
    a.fil.test

  var s = SeqGen[int](fil: FilterMixin[int](test: nil, trans: nil))
  doAssert s.test() == nil



block t6770:
  type GA = concept c
    c.a is int

  type A = object
    a: int

  type AA = object
    case exists: bool
    of true:
      a: int
    else:
      discard

  proc print(inp: GA) =
    echo inp.a

  let failing = AA(exists: true, a: 10)
  let working = A(a:10)
  print(working)
  print(failing)



block t7952:
  type
    HasLen = concept iter
      len(iter) is int

  proc echoLen(x: HasLen) =
    echo len(x)

  echoLen([1, 2, 3, 4, 5])



block t8280:
  type
    Iterable[T] = concept x
      for elem in x:
        elem is T

  proc max[A](iter: Iterable[A]): A =
    discard

  type
    MyType = object

  echo max(@[MyType()])



import math
block t3452:
  type
    Node = concept n
      `==`(n, n) is bool
    Graph1 = concept g
      type N = Node
      distance(g, N, N) is float
    Graph2 = concept g
      distance(g, Node, Node) is float
    Graph3 = concept g
      var x: Node
      distance(g, x, x) is float
    XY = tuple[x, y: int]
    MyGraph = object
      points: seq[XY]

  static:
    assert XY is Node

  proc distance( g: MyGraph, a, b: XY): float =
    sqrt( pow(float(a.x - b.x), 2) + pow(float(a.y - b.y), 2) )

  static:
    assert MyGraph is Graph1
    assert MyGraph is Graph2
    assert MyGraph is Graph3



block t6691:
  type
    ConceptA = concept c
    ConceptB = concept c
        c.myProc(ConceptA)
    Obj = object

  proc myProc(obj: Obj, x: ConceptA) = discard

  echo Obj is ConceptB



block t6782:
  type
    Reader = concept c
      c.read(openArray[byte], int, int) is int
    Rdr = concept c
      c.rd(openArray[byte], int, int) is int

  type TestFile = object

  proc read(r: TestFile, dest: openArray[byte], offset: int, limit: int): int =
      result = 0
  proc rd(r: TestFile, dest: openArray[byte], offset: int, limit: int): int =
      result = 0

  doAssert TestFile is Reader
  doAssert TestFile is Rdr



block t7114:
  type
    MyConcept = concept x
      x.close() # error, doesn't work
    MyConceptImplementer = object

  proc close(self: MyConceptImplementer) = discard
  proc takeConcept(window: MyConcept) =
    discard

  takeConcept(MyConceptImplementer())



block t7510:
  type
    A[T] = concept a
        a.x is T
    B[T] = object
        x: T
  proc getx(v: A): v.T = v.x
  var v = B[int32](x: 10)
  echo v.getx



block misc_issues:
  # https://github.com/nim-lang/Nim/issues/1147
  type TTest = object
    vals: seq[int]

  proc add(self: var TTest, val: int) =
    self.vals.add(val)

  type CAddable = concept x
    x[].add(int)

  echo((ref TTest) is CAddable) # true

  # https://github.com/nim-lang/Nim/issues/1570
  type ConcretePointOfFloat = object
    x, y: float

  type ConcretePoint[Value] = object
    x, y: Value

  type AbstractPointOfFloat = concept p
    p.x is float and p.y is float

  let p1 = ConcretePointOfFloat(x: 0, y: 0)
  let p2 = ConcretePoint[float](x: 0, y: 0)

  echo p1 is AbstractPointOfFloat      # true
  echo p2 is AbstractPointOfFloat      # true
  echo p2.x is float and p2.y is float # true

  # https://github.com/nim-lang/Nim/issues/2018
  type ProtocolFollower = concept c
    true # not a particularly involved protocol

  type ImplementorA = object
  type ImplementorB = object

  proc p[A: ProtocolFollower, B: ProtocolFollower](a: A, b: B) =
    echo "p has been called."

  p(ImplementorA(), ImplementorA())
  p(ImplementorA(), ImplementorB())

  # https://github.com/nim-lang/Nim/issues/2423
  proc put[T](c: seq[T], x: T) = echo "generic"
  proc put(c: seq) = echo "implicit generic"

  type
    Container[T] = concept c
      put(c)
      put(c, T)

  proc c1(x: Container) = echo "implicit generic"
  c1(@[1])

  proc c2[T](x: Container[T]) = echo "generic"
  c2(@[1])

  # https://github.com/nim-lang/Nim/issues/2882
  type
    Paper = object
      name: string

    Bendable = concept x
      bend(x is Bendable)

  proc bend(p: Paper): Paper = Paper(name: "bent-" & p.name)

  var paper = Paper(name: "red")
  echo paper is Bendable

  type
    A = concept self
      size(self) is int

    B = object

  proc size(self: B): int =
    return -1

  proc size(self: A): int =
    return 0

  let b = B()
  echo b is A
  echo b.size()

  # https://github.com/nim-lang/Nim/issues/7125
  type
    Thing = concept x
      x.hello is string
    Cat = object

  proc hello(d: Cat): string = "Meow"

  proc sayHello(c: Thing) = echo(c.hello)

  # used to be 'var a: Thing = Cat()' but that's not valid Nim code
  # anyway and will be an error soon.
  var a: Cat = Cat()
  a.sayHello()


# bug #16897

type
  Fp[N: static int, T] = object
    big: array[N, T]

type
  QuadraticExt* = concept x
    ## Quadratic Extension concept (like complex)
    type BaseField = auto
    x.c0 is BaseField
    x.c1 is BaseField
var address = pointer(nil)
proc prod(r: var QuadraticExt, b: QuadraticExt) =
  if address == nil:
    address = addr b
    prod(r, b)
  else:
    assert address == addr b

type
  Fp2[N: static int, T] {.byref.} = object
    c0, c1: Fp[N, T]

# This should be passed by reference,
# but concepts do not respect the 24 bytes rule
# or `byref` pragma.
var r, b: Fp2[6, uint64]

prod(r, b)


block: # bug #21263
  type
    DateDayFraction = concept # no T, an atom
      proc date(a: Self): int
      proc fraction(b: Self): float
    Date = distinct int
    DateDayFractionImpl = object
      date : int
      fraction : float

  proc date(a: Date): int = a.int
  proc fraction(a:Date): float = 0.0

  proc date(a: DateDayFractionImpl): int = a.date
  proc fraction(b: DateDayFractionImpl): float = b.fraction


  proc print(a: DateDayFraction) =
    echo a.date, " ", a.fraction

  print(10.Date) # ok
  print(DateDayFractionImpl(date: 1, fraction: 2))  # error

import sets
import deques

type AnyTree[V] = concept t, type T
  for v in t.leaves(V):
    v is V

type BreadthOrder[V] = ref object
  frontier: Deque[V]
  visited: HashSet[V]

proc expand[V, T](order: ref BreadthOrder[T], tree: AnyTree[V], node: V, transform: (V) -> (T)) =
  for leaf in tree.leaves(node):
    if not order.visited.containsOrIncl(transform(leaf)):
      order.frontier.addLast(transform(leaf))

proc hasNext[V](order: ref BreadthOrder[V]): bool =
  order.frontier.len > 0

proc init[V](_: typedesc[BreadthOrder]): ref BreadthOrder[V] =
  result.new()
  result[] = BreadthOrder[V](frontier: initDeque[V](), visited: initHashSet[V]())

proc popNext[V](order: ref BreadthOrder[V]): V =
  order.frontier.popFirst()

type LevelNode[V] = tuple
  depth: uint
  node: V

proc depthOf*[V](orderType: typedesc[BreadthOrder], tree: AnyTree[V], root, goal: V): uint =
  if root == goal:
    return 0
  var order = init[LevelNode[V]](orderType)
  order.expand(tree, root, (leaf) => (1.uint, leaf))
  while order.hasNext():
    let depthNode: LevelNode[V] = order.popNext()
    if depthNode.node == goal:
      return depthNode.depth
    order.expand(tree, depthNode.node, (leaf) => (depthNode.depth + 1, leaf))

type CappedStringTree = ref object
  symbols: string
  cap: Natural

iterator leaves*(t: CappedStringTree, s: string): string =
  if s.len < t.cap:
    for c in t.symbols:
      yield s & c

block: # bug #12852
  var tree = CappedStringTree(symbols: "^v><", cap: 5)

  doAssert BreadthOrder.depthOf(tree, "", ">>>") == 3

block: #bug #22723
  type
    Node  = concept n, type T 
      for i in n.children:
        i is T
      n.parent is T

    Nd = ref object
      parent: Nd
      children: seq[Nd]

  proc addChild(parent, child: Node) =
    parent.children.add(child)
    child.parent = parent

  proc foo =
    var
      a = Nd()
      b = Nd()
    a.addChild(b)
    doAssert a.children.len == 1

  foo()

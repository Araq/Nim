discard """
  outputsub: '''1
2
3
4
5
6
89
90
90
0 0 1
0 1 2
0 2 3
1 0 4
1 1 5
1 2 6
1 3 7
after 6 6
MEM 0'''
joinable: false
  cmd: "nim c --gc:orc -d:useMalloc $file"
  valgrind: "true"
"""

import typetraits

type
  myseq*[T] = object
    len, cap: int
    data: ptr UncheckedArray[T]

# XXX make code memory safe for overflows in '*'
var
  allocCount, deallocCount: int

proc `=destroy`*[T](x: var myseq[T]) =
  if x.data != nil:
    when not supportsCopyMem(T):
      for i in 0..<x.len: `=destroy`(x[i])
    dealloc(x.data)
    inc deallocCount
    x.data = nil
    x.len = 0
    x.cap = 0

proc `=copy`*[T](a: var myseq[T]; b: myseq[T]) =
  if a.data == b.data: return
  if a.data != nil:
    `=destroy`(a)
    #dealloc(a.data)
    #inc deallocCount
    #a.data = nil
  a.len = b.len
  a.cap = b.cap
  if b.data != nil:
    a.data = cast[type(a.data)](alloc(a.cap * sizeof(T)))
    inc allocCount
    when supportsCopyMem(T):
      copyMem(a.data, b.data, a.cap * sizeof(T))
    else:
      for i in 0..<a.len:
        a.data[i] = b.data[i]

proc `=sink`*[T](a: var myseq[T]; b: myseq[T]) =
  if a.data != nil and a.data != b.data:
    dealloc(a.data)
    inc deallocCount
  a.len = b.len
  a.cap = b.cap
  a.data = b.data

proc `=trace`*[T](x: var myseq[T]; env: pointer) =
  if x.data != nil:
    for i in 0..<x.len: `=trace`(x[i], env)

proc resize[T](s: var myseq[T]) =
  let oldCap = s.cap
  if oldCap == 0: s.cap = 8
  else: s.cap = (s.cap * 3) shr 1
  if s.data == nil: inc allocCount
  s.data = cast[typeof(s.data)](realloc0(s.data, oldCap * sizeof(T), s.cap * sizeof(T)))

proc reserveSlot[T](x: var myseq[T]): ptr T =
  if x.len >= x.cap: resize(x)
  result = addr(x.data[x.len])
  inc x.len

template add*[T](x: var myseq[T]; y: T) =
  reserveSlot(x)[] = y

proc shrink*[T](x: var myseq[T]; newLen: int) =
  assert newLen <= x.len
  assert newLen >= 0
  when not supportsCopyMem(T):
    for i in countdown(x.len - 1, newLen - 1):
      `=destroy`(x.data[i])
  x.len = newLen

proc grow*[T](x: var myseq[T]; newLen: int; value: T) =
  if newLen <= x.len: return
  assert newLen >= 0
  let oldCap = x.cap
  if oldCap == 0: x.cap = newLen
  else: x.cap = max(newLen, (oldCap * 3) shr 1)
  if x.data == nil: inc allocCount
  x.data = cast[type(x.data)](realloc0(x.data, oldCap * sizeof(T), x.cap * sizeof(T)))
  for i in x.len..<newLen:
    x.data[i] = value
  x.len = newLen

template default[T](t: typedesc[T]): T =
  var v: T
  v

proc setLen*[T](x: var myseq[T]; newLen: int) {.deprecated.} =
  if newlen < x.len: shrink(x, newLen)
  else: grow(x, newLen, default(T))

template `[]`*[T](x: myseq[T]; i: Natural): T =
  assert i < x.len
  x.data[i]

template `[]=`*[T](x: myseq[T]; i: Natural; y: T) =
  assert i < x.len
  x.data[i] = y

proc createSeq*[T](elems: varargs[T]): myseq[T] =
  result = myseq[T](
    cap: max(elems.len, 2),
    len: elems.len)

  result.data = cast[type(result.data)](alloc0(result.cap * sizeof(T)))

  inc allocCount
  when supportsCopyMem(T):
    copyMem(result.data, addr(elems[0]), result.cap * sizeof(T))
  else:
    for i in 0..<result.len:
      result.data[i] = elems[i]

proc len*[T](x: myseq[T]): int {.inline.} = x.len

proc main =
  var s = createSeq(1, 2, 3, 4, 5, 6)
  s.add 89
  s.grow s.len + 2, 90
  for i in 0 ..< s.len:
    echo s[i]

  var nested = createSeq(createSeq(1, 2, 3), createSeq(4, 5, 6, 7))
  for i in 0 ..< nested.len:
    for j in 0 ..< nested[i].len:
      echo i, " ", j, " ", nested[i][j]

main()
echo "after ", allocCount, " ", deallocCount

type
  Node = ref object
    name: char
    sccId: int
    kids: myseq[Node]
    rc: int

proc edge(a, b: Node) =
  inc b.rc
  a.kids.add b

proc createNode(name: char): Node =
  new result
  result.name = name
  result.kids = createSeq[Node]()

proc use(x: Node) = discard

proc buildComplexGraph: Node =
  # see https://en.wikipedia.org/wiki/Strongly_connected_component for the
  # graph:
  let a = createNode('a')
  let b = createNode('b')
  let c = createNode('c')
  let d = createNode('d')
  let e = createNode('e')

  a.edge c
  c.edge b
  c.edge e
  b.edge a
  d.edge c
  e.edge d


  let f = createNode('f')
  b.edge f
  e.edge f

  let g = createNode('g')
  let h = createNode('h')
  let i = createNode('i')

  f.edge g
  f.edge i
  g.edge h
  h.edge i
  i.edge g

  let j = createNode('j')

  h.edge j
  i.edge j

  let k = createNode('k')
  let l = createNode('l')

  f.edge k
  k.edge l
  l.edge k
  k.edge j

  let m = createNode('m')
  let n = createNode('n')
  let p = createNode('p')
  let q = createNode('q')

  m.edge n
  n.edge p
  n.edge q
  q.edge p
  p.edge m

  q.edge k

  d.edge m
  e.edge n

  result = a

proc main2 =
  let g = buildComplexGraph()

main2()
GC_fullCollect()
echo "MEM ", getOccupiedMem()

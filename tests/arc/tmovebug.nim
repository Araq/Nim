discard """
  cmd: "nim c --gc:arc $file"
  output: '''5
(w: 5)
(w: -5)
c.text = hello
c.text = hello
p.text = hello
p.toks = @["hello"]
c.text = hello
c[].text = hello
pA.text = hello
pA.toks = @["hello"]
c.text = hello
c.text = hello
pD.text = hello
pD.toks = @["hello"]
c.text = hello
c.text = hello
pOD.text = hello
pOD.toks = @["hello"]
fff
fff
2
fff
fff
2
fff
fff
2
mmm
fff
fff
fff
3
mmm
sink me (sink)
assign me (not sink)
sink me (not sink)
sinked and not optimized to a bitcopy
sinked and not optimized to a bitcopy
sinked and not optimized to a bitcopy
(data: @[0, 0])
(data: @[0, 0])
(data: @[0, 0])
(data: @[0, 0])
(data: @[0, 0])
(data: @[0, 0])
(data: @[0, 0])
100
hey
hey
(a: "a", b: 2)
ho
(a: "b", b: 3)
(b: "b", a: 2)
ho
(b: "a", a: 3)
hey
break
break
hey
ho
hey
ho
ho
king
live long; long live
king
hi
try
bye
()
()
()
1
destroy
1
destroy
1
destroy
copy (self-assign)
1
destroy
1
destroy
1
destroy
destroy
copy
@[(f: 2), (f: 2), (f: 3)]
destroy
destroy
destroy
sink
sink
destroy
copy
(f: 1)
destroy
destroy
part-to-whole assigment:
sink
(children: @[])
destroy
sink
(children: @[])
destroy
copy
destroy
(f: 1)
destroy
'''
"""

# move bug
type
  TMyObj = object
    p: pointer
    len: int

var destroyCounter = 0

proc `=destroy`(o: var TMyObj) =
  if o.p != nil:
    dealloc o.p
    o.p = nil
    inc destroyCounter

proc `=`(dst: var TMyObj, src: TMyObj) =
  `=destroy`(dst)
  dst.p = alloc(src.len)
  dst.len = src.len

proc `=sink`(dst: var TMyObj, src: TMyObj) =
  `=destroy`(dst)
  dst.p = src.p
  dst.len = src.len

type
  TObjKind = enum Z, A, B
  TCaseObj = object
    case kind: TObjKind
    of Z: discard
    of A:
      x1: int # this int plays important role
      x2: TMyObj
    of B:
      y: TMyObj

proc use(a: TCaseObj) = discard

proc moveBug(i: var int) =
  var a: array[2, TCaseObj]
  a[i] = TCaseObj(kind: A, x1: 5000, x2: TMyObj(len: 5, p: alloc(5))) # 1
  a[i+1] = a[i] # 2
  inc i
  use(a[i-1])

var x = 0
moveBug(x)

proc moveBug2(): (TCaseObj, TCaseObj) =
  var a: array[2, TCaseObj]
  a[0] = TCaseObj(kind: A, x1: 5000, x2: TMyObj(len: 5, p: alloc(5)))
  a[1] = a[0] # can move 3
  result[0] = TCaseObj(kind: A, x1: 5000, x2: TMyObj(len: 5, p: alloc(5))) # 4
  result[1] = result[0] # 5

proc main =
  discard moveBug2()

main()
echo destroyCounter

# bug #13314

type
  O = object
    v: int
  R = ref object
    w: int

proc `$`(r: R): string = $r[]

proc tbug13314 =
  var t5 = R(w: 5)
  var execute = proc () =
    echo t5

  execute()
  t5.w = -5
  execute()

tbug13314()

#-------------------------------------------------------------------------
# bug #13368

import strutils
proc procStat() =
  for line in @["a b", "c d", "e f"]:
    let cols = line.splitWhitespace(maxSplit=1)
    let x = cols[0]
    let (nm, rest) = (cols[0], cols[1])
procStat()


# bug #14269

import sugar, strutils

type
  Cursor = object
    text: string
  Parsed = object
    text: string
    toks: seq[string]

proc tokenize(c: var Cursor): seq[string] =
  dump c.text
  return c.text.splitWhitespace()

proc parse(): Parsed =
  var c = Cursor(text: "hello")
  dump c.text
  return Parsed(text: c.text, toks: c.tokenize) # note: c.tokenized uses c.text

let p = parse()
dump p.text
dump p.toks


proc tokenizeA(c: ptr Cursor): seq[string] =
  dump c[].text
  return c[].text.splitWhitespace()

proc parseA(): Parsed =
  var c = Cursor(text: "hello")
  dump c.text
  return Parsed(text: c.text, toks: c.addr.tokenizeA) # note: c.tokenized uses c.text

let pA = parseA()
dump pA.text
dump pA.toks


proc tokenizeD(c: Cursor): seq[string] =
  dump c.text
  return c.text.splitWhitespace()

proc parseD(): Parsed =
  var c = cast[ptr Cursor](alloc0(sizeof(Cursor)))
  c[] = Cursor(text: "hello")
  dump c.text
  return Parsed(text: c.text, toks: c[].tokenizeD) # note: c.tokenized uses c.text

let pD = parseD()
dump pD.text
dump pD.toks

# Bug would only pop up with owned refs
proc tokenizeOD(c: Cursor): seq[string] =
  dump c.text
  return c.text.splitWhitespace()

proc parseOD(): Parsed =
  var c = new Cursor
  c[] = Cursor(text: "hello")
  dump c.text
  return Parsed(text: c.text, toks: c[].tokenizeOD) # note: c.tokenized uses c.text

let pOD = parseOD()
dump pOD.text
dump pOD.toks

when false:
  # Bug would only pop up with owned refs and implicit derefs, but since they don't work together..
  {.experimental: "implicitDeref".}
  proc tokenizeOHD(c: Cursor): seq[string] =
    dump c.text
    return c.text.splitWhitespace()

  proc parseOHD(): Parsed =
    var c = new Cursor
    c[] = Cursor(text: "hello")
    dump c.text
    return Parsed(text: c.text, toks: c.tokenizeOHD) # note: c.tokenized uses c.text

  let pOHD = parseOHD()
  dump pOHD.text
  dump pOHD.toks

# bug #13456

iterator combinations[T](s: openArray[T], k: int): seq[T] =
  let n = len(s)
  assert k >= 0 and k <= n
  var pos = newSeq[int](k)
  var current = newSeq[T](k)
  for i in 0..k-1:
    pos[k-i-1] = i
  var done = false
  while not done:
    for i in 0..k-1:
      current[i] = s[pos[k-i-1]]
    yield current
    var i = 0
    while i < k:
      pos[i] += 1
      if pos[i] < n-i:
        for j in 0..i-1:
          pos[j] = pos[i] + i - j
        break
      i += 1
    if i >= k:
      break

type
  UndefEx = object of ValueError

proc main2 =
  var delayedSyms = @[1, 2, 3]
  var unp: seq[int]
  block myb:
    for a in 1 .. 2:
      if delayedSyms.len > a:
        unp = delayedSyms
        for t in unp.combinations(a + 1):
          try:
            var h = false
            for k in t:
              echo "fff"
            if h: continue
            if true:
              raise newException(UndefEx, "forward declaration")
            break myb
          except UndefEx:
            echo t.len
        echo "mmm"

main2()



type ME = object
  who: string

proc `=`(x: var ME, y: ME) =
  if y.who.len > 0: echo "assign ",y.who

proc `=sink`(x: var ME, y: ME) =
  if y.who.len > 0: echo "sink ",y.who

var dump: ME
template use(x) = dump = x
template def(x) = x = dump

var c = true

proc shouldSink() =
  var x = ME(who: "me (sink)")
  use(x) # we analyse this
  if c: def(x)
  else: def(x)
  use(x) # ok, with the [else] part.

shouldSink()

dump = ME()

proc shouldNotSink() =
  var x = ME(who: "me (not sink)")
  use(x) # we analyse this
  if c: def(x)
  use(x) # Not ok without the '[else]'

shouldNotSink()

# bug #14568
import os

type O2 = object
  s: seq[int]

proc `=sink`(dest: var O2, src: O2) =
  echo "sinked and not optimized to a bitcopy"

var testSeq: O2

proc update() =
  # testSeq.add(0) # uncommenting this line fixes the leak
  testSeq = O2(s: @[])
  testSeq.s.add(0)

for i in 1..3:
  update()


# bug #14961
type
  Foo = object
    data: seq[int]

proc initFoo(len: int): Foo =
  result = (let s = newSeq[int](len); Foo(data: s) )

var f = initFoo(2)
echo initFoo(2)

proc initFoo2(len: int) =
  echo   if true:
             let s = newSeq[int](len); Foo(data: s)
         else:
             let s = newSeq[int](len); Foo(data: s)

initFoo2(2)

proc initFoo3(len: int) =
  echo (block:
         let s = newSeq[int](len); Foo(data: s))

initFoo3(2)

proc initFoo4(len: int) =
  echo (let s = newSeq[int](len); Foo(data: s))

initFoo4(2)

proc initFoo5(len: int) =
  echo (case true
        of true:
          let s = newSeq[int](len); Foo(data: s)
        of false:
          let s = newSeq[int](len); Foo(data: s))

initFoo5(2)

proc initFoo6(len: int) =
  echo (block:
          try:
            let s = newSeq[int](len); Foo(data: s)
          finally: discard)

initFoo6(2)

proc initFoo7(len: int) =
  echo (block:
          try:
            raise newException(CatchableError, "sup")
            let s = newSeq[int](len); Foo(data: s)
          except CatchableError:
            let s = newSeq[int](len); Foo(data: s) )

initFoo7(2)


# bug #14902
iterator zip[T](s: openArray[T]): (T, T) =
  var i = 0
  while i < 10:
    yield (s[i mod 2], s[i mod 2 + 1])
    inc i

var lastMem = int.high

proc leak =
  const len = 10
  var x = @[newString(len), newString(len), newString(len)]

  var c = 0
  for (a, b) in zip(x):
    let newMem = getOccupiedMem()
    assert newMem <= lastMem
    lastMem = newMem
    c += a.len
  echo c

leak()


proc consume(a: sink string) = echo a

proc weirdScopes =
  if (let a = "hey"; a.len > 0):
    echo a

  while (let a = "hey"; a.len > 0):
    echo a
    break

  var a = block: (a: "a", b: 2)
  echo a
  (discard; a) = (echo "ho"; (a: "b", b: 3))
  echo a

  var b = try: (b: "b", a: 2)
          except: raise
  echo b
  (discard; b) = (echo "ho"; (b: "a", a: 3))
  echo b

  var s = "break"
  consume((echo "hey"; s))
  echo s

  echo (block:
          var a = "hey"
          (echo "hey"; "ho"))

  var b2 = "ho"
  echo (block:
          var a = "hey"
          (echo "hey"; b2))
  echo b2

  type status = enum
    alive

  var king = "king"
  echo (block:
          var a = "a"
          when true:
            var b = "b"
            case alive
            of alive:
              try:
                var c = "c"
                if true:
                  king
                else:
                  "the abyss"
              except:
                echo "he ded"
                "dead king")
  echo "live long; long live"
  echo king

weirdScopes()


# bug #14985
proc getScope(): string =
  if true:
    return "hi"
  else:
    "else"

echo getScope()

proc getScope3(): string =
  try:
    "try"
  except:
    return "except"

echo getScope3()

proc getScope2(): string =
  case true
  of true:
    return "bye"
  else:
    "else"

echo getScope2()


#--------------------------------------------------------------------
#bug  #15609

type
  Wrapper = object
    discard

proc newWrapper(): ref Wrapper =
  new(result)
  result


proc newWrapper2(a: int): ref Wrapper =
  new(result)
  if a > 0:
    result
  else:
    new(Wrapper)


let w1 = newWrapper()
echo $w1[]

let w2 = newWrapper2(1)
echo $w2[]

let w3 = newWrapper2(-1)
echo $w3[]


#--------------------------------------------------------------------
#self-assignments

# Self-assignments that are not statically determinable will get
# turned into `=copy` calls as caseBracketExprCopy demonstrates.
# (`=copy` handles self-assignments at runtime)

type
  OO = object
    f: int
  W = object
    o: OO

proc `=destroy`(x: var OO) =
  if x.f != 0:
    echo "destroy"
    x.f = 0

proc `=sink`(x: var OO, y: OO) =
  `=destroy`(x)
  echo "sink"
  x.f = y.f

proc `=copy`(x: var OO, y: OO) =
  if x.f != y.f:
    `=destroy`(x)
    echo "copy"
    x.f = y.f
  else:
    echo "copy (self-assign)"

proc caseSym =
  var o = OO(f: 1)
  o = o # NOOP
  echo o.f # "1"
  # "destroy"

caseSym()

proc caseDotExpr =
  var w = W(o: OO(f: 1))
  w.o = w.o # NOOP
  echo w.o.f # "1"
  # "destroy"

caseDotExpr()

proc caseBracketExpr =
  var w = [0: OO(f: 1)]
  w[0] = w[0] # NOOP
  echo w[0].f # "1"
  # "destroy"

caseBracketExpr()

proc caseBracketExprCopy =
  var w = [0: OO(f: 1)]
  let i = 0
  w[i] = w[0] # "copy (self-assign)"
  echo w[0].f # "1"
  # "destroy"

caseBracketExprCopy()

proc caseDotExprAddr =
  var w = W(o: OO(f: 1))
  w.o = addr(w.o)[] # NOOP
  echo w.o.f # "1"
  # "destroy"

caseDotExprAddr()

proc caseBracketExprAddr =
  var w = [0: OO(f: 1)]
  addr(w[0])[] = addr(addr(w[0])[])[] # NOOP
  echo w[0].f # "1"
  # "destroy"

caseBracketExprAddr()

proc caseNotAConstant =
  var i = 0
  proc rand: int =
    result = i
    inc i
  var s = @[OO(f: 1), OO(f: 2), OO(f: 3)]
  s[rand()] = s[rand()] # "destroy" "copy"
  echo s # @[(f: 2), (f: 2), (f: 3)]

caseNotAConstant()

proc potentialSelfAssign(i: var int) =
  var a: array[2, OO]
  a[i] = OO(f: 1) # turned into a memcopy
  a[1] = OO(f: 2)
  a[i+1] = a[i] # This must not =sink, but =copy
  inc i
  echo a[i-1] # (f: 1)

potentialSelfAssign (var xi = 0; xi)


#--------------------------------------------------------------------
echo "part-to-whole assigment:"

type
  Tree = object
    children: seq[Tree]

  TreeDefaultHooks = object
    children: seq[TreeDefaultHooks]

proc `=destroy`(x: var Tree) = echo "destroy"
proc `=sink`(x: var Tree, y: Tree) = echo "sink"
proc `=copy`(x: var Tree, y: Tree) = echo "copy"

proc partToWholeSeq =
  var t = Tree(children: @[Tree()])
  t = t.children[0] # This should be sunk, but with the special transform (tmp = t.children[0]; wasMoved(0); `=sink`(t, tmp))

  var tc = TreeDefaultHooks(children: @[TreeDefaultHooks()])
  tc = tc.children[0] # Ditto; if this were sunk with the normal transform (`=sink`(t, t.children[0]); wasMoved(t.children[0]))
  echo tc             #        then it would crash because t.children[0] does not exist after the call to `=sink`

partToWholeSeq()

proc partToWholeSeqRTIndex =
  var i = 0
  var t = Tree(children: @[Tree()])
  t = t.children[i] # See comment in partToWholeSeq

  var tc = TreeDefaultHooks(children: @[TreeDefaultHooks()])
  tc = tc.children[i] # See comment in partToWholeSeq
  echo tc

partToWholeSeqRTIndex()

type List = object
  next: ref List

proc `=destroy`(x: var List) = echo "destroy"
proc `=sink`(x: var List, y: List) = echo "sink"
proc `=copy`(x: var List, y: List) = echo "copy"

proc partToWholeUnownedRef =
  var t = List(next: new List)
  t = t.next[] # Copy because t.next is not an owned ref, and thus t.next[] cannot be moved

partToWholeUnownedRef()


#--------------------------------------------------------------------
# test that nodes that get copied during the transformation
# (like dot exprs) don't loose their firstWrite/lastRead property

type
  OOO = object
    initialized: bool

  C = object
    o: OOO

proc `=destroy`(o: var OOO) =
  doAssert o.initialized, "OOO was destroyed before initialization!"

proc initO(): OOO =
  OOO(initialized: true)

proc initC(): C =
  C(o: initO())

proc pair(): tuple[a: C, b: C] =
  result = (a: initC(), b: initC())# <- when firstWrite tries to find this node to start its analysis it fails, because injectdestructors uses copyTree/shallowCopy

discard pair()


# bug #17450
proc noConsume(x: OO) {.nosinks.} = echo x

proc main3 =
  var i = 1
  noConsume:
    block:
      OO(f: i)

main3()

# misc
proc smoltest(x: bool): bool =
  result = false
  while true:
    if true: return x

discard smoltest(true)

# bug #18002
type
  TTypeAttachedOp = enum
    attachedAsgn
    attachedSink
    attachedTrace

  PNode = ref object
    discard

proc genAddrOf(n: PNode) =
  assert n != nil, "moved?!"

proc atomicClosureOp =
  let x = PNode()

  genAddrOf:
    block:
      x

  case attachedTrace
  of attachedSink: discard
  of attachedAsgn: discard
  of attachedTrace: genAddrOf(x)

atomicClosureOp()


template assertEq(a, b: untyped): untyped =
  block:
    let
      aval = a
      bval = b

    if aval != bval:
      quit "bug!"

proc convoluted =
  let _ = (;
    var val1: string;
    if true: val1 = "22"
    else: val1 = ""
    true
  )

  assertEq val1, "22"
  assertEq val1, "22"

convoluted()

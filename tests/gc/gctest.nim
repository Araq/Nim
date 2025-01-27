discard """
  outputsub: "finished"
  retries: 2
"""

# Test the garbage collector.

import
  strutils

type
  PNode = ref TNode
  TNode {.final.} = object
    le, ri: PNode
    data: string

  TTable {.final.} = object
    counter, max: int
    data: seq[string]

  TBNode {.final.} = object
    other: PNode  # a completely different tree
    data: string
    sons: seq[TBNode] # directly embedded!
    t: TTable

  TCaseKind = enum nkStr, nkWhole, nkList
  PCaseNode = ref TCaseNode
  TCaseNode {.final.} = object
    case kind: TCaseKind
    of nkStr: data: string
    of nkList: sons: seq[PCaseNode]
    else: unused: seq[string]

  TIdObj* = object of RootObj
    id*: int  # unique id; use this for comparisons and not the pointers

  PIdObj* = ref TIdObj
  PIdent* = ref TIdent
  TIdent*{.acyclic.} = object of TIdObj
    s*: string
    next*: PIdent             # for hash-table chaining
    h*: int                   # hash value of s

var
  flip: int

proc newCaseNode(data: string): PCaseNode =
  if flip == 0:
    result = PCaseNode(kind: nkStr, data: data)
  else:
    result = PCaseNode(kind: nkWhole, unused: @["", "abc", "abdc"])
  flip = 1 - flip

proc newCaseNode(a, b: PCaseNode): PCaseNode =
  result = PCaseNode(kind: nkList, sons: @[a, b])

proc caseTree(lvl: int = 0): PCaseNode =
  if lvl == 3: result = newCaseNode("data item")
  else: result = newCaseNode(caseTree(lvl+1), caseTree(lvl+1))

proc finalizeNode(n: PNode) =
  assert(n != nil)
  write(stdout, "finalizing: ")
  writeLine(stdout, "not nil")

var
  id: int = 1

proc buildTree(depth = 1): PNode =
  if depth == 7: return nil
  new(result, finalizeNode)
  result.le = buildTree(depth+1)
  result.ri = buildTree(depth+1)
  result.data = $id
  inc(id)

proc returnTree(): PNode =
  writeLine(stdout, "creating id: " & $id)
  new(result, finalizeNode)
  result.data = $id
  new(result.le, finalizeNode)
  result.le.data = $id & ".1"
  new(result.ri, finalizeNode)
  result.ri.data = $id & ".2"
  inc(id)

  # now create a cycle:
  writeLine(stdout, "creating id (cyclic): " & $id)
  var cycle: PNode
  new(cycle, finalizeNode)
  cycle.data = $id
  cycle.le = cycle
  cycle.ri = cycle
  inc(id)
  #writeLine(stdout, "refcount: " & $refcount(cycle))
  #writeLine(stdout, "refcount le: " & $refcount(cycle.le))
  #writeLine(stdout, "refcount ri: " & $refcount(cycle.ri))

proc printTree(t: PNode) =
  if t == nil: return
  writeLine(stdout, "printing")
  writeLine(stdout, t.data)
  printTree(t.le)
  printTree(t.ri)

proc unsureNew(result: var PNode) =
  writeLine(stdout, "creating unsure id: " & $id)
  new(result, finalizeNode)
  result.data = $id
  new(result.le, finalizeNode)
  result.le.data = $id & ".a"
  new(result.ri, finalizeNode)
  result.ri.data = $id & ".b"
  inc(id)

proc setSons(n: var TBNode) =
  n.sons = @[] # free memory of the sons
  n.t.data = @[]
  var
    m: seq[string]
  m = @[]
  setLen(m, len(n.t.data) * 2)
  for i in 0..high(m):
    m[i] = "..."
  n.t.data = m

proc buildBTree(father: var TBNode) =
  father.data = "father"
  father.other = nil
  father.sons = @[]
  for i in 1..10:
    write(stdout, "next iteration!\n")
    var n: TBNode
    n.other = returnTree()
    n.data = "B node: " & $i
    if i mod 2 == 0: n.sons = @[] # nil and [] need to be handled correctly!
    add father.sons, n
    father.t.counter = 0
    father.t.max = 3
    father.t.data = @["ha", "lets", "stress", "it"]
  setSons(father)

proc getIdent(identifier: cstring, length: int, h: int): PIdent =
  new(result)
  result.h = h
  result.s = newString(length)

proc main() =
  discard getIdent("addr", 4, 0)
  discard getIdent("hall", 4, 0)
  discard getIdent("echo", 4, 0)
  discard getIdent("huch", 4, 0)

  var
    father: TBNode
  for i in 1..1_00:
    buildBTree(father)

  for i in 1..1_00:
    var t = returnTree()
    var t2: PNode
    unsureNew(t2)
  write(stdout, "now building bigger trees: ")
  var t2: PNode
  for i in 1..100:
    t2 = buildTree()
  printTree(t2)
  write(stdout, "now test sequences of strings:")
  var s: seq[string] = @[]
  for i in 1..100:
    add s, "hohoho" # test reallocation
  writeLine(stdout, s[89])
  write(stdout, "done!\n")

var
  father {.threadvar.}: TBNode
  s {.threadvar.}: string

  fatherAsGlobal: TBNode

proc start =
  s = ""
  s = ""
  writeLine(stdout, repr(caseTree()))
  father.t.data = @["ha", "lets", "stress", "it"]
  father.t.data = @["ha", "lets", "stress", "it"]
  var t = buildTree()
  write(stdout, repr(t[]))
  buildBTree(father)
  write(stdout, repr(father))

  write(stdout, "starting main...\n")
  main()

  GC_fullCollect()
  # the M&S GC fails with this call and it's unclear why. Definitely something
  # we need to fix!
  #GC_fullCollect()
  writeLine(stdout, GC_getStatistics())
  write(stdout, "finished\n")

fatherAsGlobal.t.data = @["ha", "lets", "stress", "it"]
var tg = buildTree()
buildBTree(fatherAsGlobal)

var thr: array[8, Thread[void]]
for i in low(thr)..high(thr):
  createThread(thr[i], start)
joinThreads(thr)
start()

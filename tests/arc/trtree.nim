discard """
  output: '''1 [2, 3, 4, 7]
[0, 0]'''
  targets: "c"
  joinable: false
disabled: 32bit
  cmd: "nim c --gc:arc $file"
"""

# bug #13110: This test failed with --gc:arc.

# this test wasn't written for 32 bit
# don't join because the code is too messy.

# Nim RTree and R*Tree implementation
# S. Salewski, 06-JAN-2018

# http://www-db.deis.unibo.it/courses/SI-LS/papers/Gut84.pdf
# http://dbs.mathematik.uni-marburg.de/publications/myPapers/1990/BKSS90.pdf

# RT: range type like float, int
# D: Dimension
# M: Max entries in one node
# LT: leaf type

type
  Dim* = static[int]
  Ext[RT] = tuple[a, b: RT] # extend (range)
  Box*[D: Dim; RT] = array[D, Ext[RT]] # Rectangle for 2D
  BoxCenter*[D: Dim; RT] = array[D, RT]
  L*[D: Dim; RT, LT] = tuple[b: Box[D, RT]; l: LT] # called Index Entry or index record in the Guttman paper
  H[M, D: Dim; RT, LT] = ref object of RootRef
    parent: H[M, D, RT, LT]
    numEntries: int
    level: int
  N[M, D: Dim; RT, LT] = tuple[b: Box[D, RT]; n: H[M, D, RT, LT]]
  LA[M, D: Dim; RT, LT] = array[M, L[D, RT, LT]]
  NA[M, D: Dim; RT, LT] = array[M, N[M, D, RT, LT]]
  Leaf[M, D: Dim; RT, LT] = ref object of H[M, D, RT, LT]
    a: LA[M, D, RT, LT]
  Node[M, D: Dim; RT, LT] = ref object of H[M, D, RT, LT]
    a: NA[M, D, RT, LT]

  RTree*[M, D: Dim; RT, LT] = ref object of RootRef
    root: H[M, D, RT, LT]
    bigM: int
    m: int

  RStarTree*[M, D: Dim; RT, LT] = ref object of RTree[M, D, RT, LT]
    firstOverflow: array[32, bool]
    p: int

proc newLeaf[M, D: Dim; RT, LT](): Leaf[M, D, RT, LT] =
  new result

proc newNode[M, D: Dim; RT, LT](): Node[M, D, RT, LT] =
  new result

proc newRTree*[M, D: Dim; RT, LT](minFill: range[30 .. 50] = 40): RTree[M, D, RT, LT] =
  assert(M > 1 and M < 101)
  new result
  result.bigM = M
  result.m = M * minFill div 100
  result.root = newLeaf[M, D, RT, LT]()

proc newRStarTree*[M, D: Dim; RT, LT](minFill: range[30 .. 50] = 40): RStarTree[M, D, RT, LT] =
  assert(M > 1 and M < 101)
  new result
  result.bigM = M
  result.m = M * minFill div 100
  result.p = M * 30 div 100
  result.root = newLeaf[M, D, RT, LT]()

proc center(r: Box): auto =#BoxCenter[r.len, typeof(r[0].a)] =
  var res = default(BoxCenter[r.len, typeof(r[0].a)])
  for i in 0 .. r.high:
    when r[0].a is SomeInteger:
      res[i] = (r[i].a + r[i].b) div 2
    elif r[0].a is SomeFloat:
      res[i] = (r[i].a + r[i].b) / 2
    else: assert false
  return res

proc distance(c1, c2: BoxCenter): auto =
  var res: typeof(c1[0]) = default(typeof(c1[0]))
  for i in 0 .. c1.high:
    res += (c1[i] - c2[i]) * (c1[i] - c2[i])
  return res

proc overlap(r1, r2: Box): auto =
  result = typeof(r1[0].a)(1)
  for i in 0 .. r1.high:
    result *= (min(r1[i].b, r2[i].b) - max(r1[i].a, r2[i].a))
    if result <= 0: return 0

proc union(r1, r2: Box): Box =
  result = default(Box)
  for i in 0 .. r1.high:
    result[i].a = min(r1[i].a, r2[i].a)
    result[i].b = max(r1[i].b, r2[i].b)

proc intersect(r1, r2: Box): bool =
  for i in 0 .. r1.high:
    if r1[i].b < r2[i].a or r1[i].a > r2[i].b:
      return false
  return true

proc area(r: Box): auto = #typeof(r[0].a) =
  result = typeof(r[0].a)(1)
  for i in 0 .. r.high:
    result *= r[i].b - r[i].a

proc margin(r: Box): auto = #typeof(r[0].a) =
  result = typeof(r[0].a)(0)
  for i in 0 .. r.high:
    result += r[i].b - r[i].a

# how much enlargement does r1 need to include r2
proc enlargement(r1, r2: Box): auto =
  area(union(r1, r2)) - area(r1)

proc search*[M, D: Dim; RT, LT](t: RTree[M, D, RT, LT]; b: Box[D, RT]): seq[LT] =
  proc s[M, D: Dim; RT, LT](n: H[M, D, RT, LT]; b: Box[D, RT]; res: var seq[LT]) =
    if n of Node[M, D, RT, LT]:
      let h = Node[M, D, RT, LT](n)
      for i in 0 ..< n.numEntries:
        if intersect(h.a[i].b, b):
          s(h.a[i].n, b, res)
    elif n of Leaf[M, D, RT, LT]:
      let h = Leaf[M, D, RT, LT](n)
      for i in 0 ..< n.numEntries:
        if intersect(h.a[i].b, b):
          res.add(h.a[i].l)
    else: assert false
  result = newSeq[LT]()
  s(t.root, b, result)

# Insertion
# a R*TREE proc
proc chooseSubtree[M, D: Dim; RT, LT](t: RTree[M, D, RT, LT]; b: Box[D, RT]; level: int): H[M, D, RT, LT] =
  assert level >= 0
  var it = t.root
  while it.level > level:
    let nn = Node[M, D, RT, LT](it)
    var i0 = 0 # selected index
    var minLoss = typeof(b[0].a).high
    if it.level == 1: # childreen are leaves -- determine the minimum overlap costs
      for i in 0 ..< it.numEntries:
        let nx = union(nn.a[i].b, b)
        var loss = 0
        for j in 0 ..< it.numEntries:
          if i == j: continue
          loss += (overlap(nx, nn.a[j].b) - overlap(nn.a[i].b, nn.a[j].b)) # overlap (i, j) == (j, i), so maybe cache that?
        var rep = loss < minLoss
        if loss == minLoss:
          let l2 = enlargement(nn.a[i].b, b) - enlargement(nn.a[i0].b, b)
          rep = l2 < 0
          if l2 == 0:
            let l3 = area(nn.a[i].b) - area(nn.a[i0].b)
            rep = l3 < 0
            if l3 == 0:
              rep = nn.a[i].n.numEntries < nn.a[i0].n.numEntries
        if rep:
          i0 = i
          minLoss = loss
    else:
      for i in 0 ..< it.numEntries:
        let loss = enlargement(nn.a[i].b, b)
        var rep = loss < minLoss
        if loss == minLoss:
          let l3 = area(nn.a[i].b) - area(nn.a[i0].b)
          rep = l3 < 0
          if l3 == 0:
            rep = nn.a[i].n.numEntries < nn.a[i0].n.numEntries
        if rep:
          i0 = i
          minLoss = loss
    it = nn.a[i0].n
  return it

proc pickSeeds[M, D: Dim; RT, LT](t: RTree[M, D, RT, LT]; n: Node[M, D, RT, LT] | Leaf[M, D, RT, LT]; bx: Box[D, RT]): (int, int) =
  var i0, j0: int = 0
  var bi, bj: typeof(bx)
  var largestWaste = typeof(bx[0].a).low
  for i in -1 .. n.a.high:
    for j in 0 .. n.a.high:
      if unlikely(i == j): continue
      if unlikely(i < 0):
        bi = bx
      else:
        bi = n.a[i].b
      bj = n.a[j].b
      let b = union(bi, bj)
      let h = area(b) - area(bi) - area(bj)
      if h > largestWaste:
        largestWaste = h
        i0 = i
        j0 = j
  return (i0, j0)

proc pickNext[M, D: Dim; RT, LT](t: RTree[M, D, RT, LT]; n0, n1, n2: Node[M, D, RT, LT] | Leaf[M, D, RT, LT]; b1, b2: Box[D, RT]): int =
  result = 0
  let a1 = area(b1)
  let a2 = area(b2)
  var d = typeof(a1).low
  for i in 0 ..< n0.numEntries:
    let d1 = area(union(b1, n0.a[i].b)) - a1
    let d2 = area(union(b2, n0.a[i].b)) - a2
    if (d1 - d2) * (d1 - d2) > d:
      result = i
      d = (d1 - d2) * (d1 - d2)

from algorithm import SortOrder, sort
proc sortPlus[T](a: var openArray[T], ax: var T, cmp: proc (x, y: T): int {.closure.}, order = algorithm.SortOrder.Ascending) =
  var j = 0
  let sign = if order == algorithm.SortOrder.Ascending: 1 else: -1
  for i in 1 .. a.high:
    if cmp(a[i], a[j]) * sign < 0:
      j = i
  if cmp(a[j], ax) * sign < 0:
    swap(ax, a[j])
  a.sort(cmp, order)

# R*TREE procs
proc rstarSplit[M, D: Dim; RT, LT](t: RStarTree[M, D, RT, LT]; n: var Node[M, D, RT, LT] | var Leaf[M, D, RT, LT]; lx: L[D, RT, LT] | N[M, D, RT, LT]): typeof(n) =
  type NL = typeof(lx)
  var nBest: typeof(n)
  new nBest
  var lx = lx
  when n is Node[M, D, RT, LT]:
    lx.n.parent = n
  var lxbest: typeof(lx) = default(typeof(lx))
  var m0 = lx.b[0].a.typeof.high
  for d2 in 0 ..< 2 * D:
    let d = d2 div 2
    if d2 mod 2 == 0:
      sortPlus(n.a, lx, proc (x, y: NL): int = cmp(x.b[d].a, y.b[d].a))
    else:
      sortPlus(n.a, lx, proc (x, y: NL): int = cmp(x.b[d].b, y.b[d].b))
    for i in t.m - 1 .. n.a.high - t.m + 1:
      var b = lx.b
      for j in 0 ..< i: # we can precalculate union() for range 0 .. t.m - 1, but that seems to give no real benefit.Maybe for very large M?
        #echo "x",j
        b = union(n.a[j].b, b)
      var m = margin(b)
      b = n.a[^1].b
      for j in i ..< n.a.high: # again, precalculation of tail would be possible
        #echo "y",j
        b = union(n.a[j].b, b)
      m += margin(b)
      if m < m0:
        nbest[] = n[]
        lxbest = lx
        m0 = m
  var i0 = -1
  var o0 = lx.b[0].a.typeof.high
  for i in t.m - 1 .. n.a.typeof.high - t.m + 1:
    var b1 = lxbest.b
    for j in 0 ..< i:
      b1 = union(nbest.a[j].b, b1)
    var b2 = nbest.a[^1].b
    for j in i ..< n.a.high:
      b2 = union(nbest.a[j].b, b2)
    let o = overlap(b1, b2)
    if o < o0:
      i0 = i
      o0 = o
  n.a[0] = lxbest
  for i in 0 ..< i0:
    n.a[i + 1] = nbest.a[i]
  new result
  result.level = n.level
  result.parent = n.parent
  for i in i0 .. n.a.high:
    result.a[i - i0] = nbest.a[i]
  n.numEntries = i0 + 1
  result.numEntries = M - i0
  when n is Node[M, D, RT, LT]:
    for i in 0 ..< result.numEntries:
      result.a[i].n.parent = result

proc quadraticSplit[M, D: Dim; RT, LT](t: RTree[M, D, RT, LT]; n: var Node[M, D, RT, LT] | var Leaf[M, D, RT, LT]; lx: L[D, RT, LT] | N[M, D, RT, LT]): typeof(n) =
  var n1, n2: typeof(n)
  var s1, s2: int
  new n1
  new n2
  n1.parent = n.parent
  n2.parent = n.parent
  n1.level = n.level
  n2.level = n.level
  var lx = lx
  when n is Node[M, D, RT, LT]:
    lx.n.parent = n
  (s1, s2) = pickSeeds(t, n, lx.b)
  assert s1 >= -1 and s2 >= 0
  if unlikely(s1 < 0):
    n1.a[0] = lx
  else:
    n1.a[0] = n.a[s1]
    dec(n.numEntries)
    if s2 == n.numEntries: # important fix
      s2 = s1
    n.a[s1] = n.a[n.numEntries]
  inc(n1.numEntries)
  var b1 = n1.a[0].b
  n2.a[0] = n.a[s2]
  dec(n.numEntries)
  n.a[s2] = n.a[n.numEntries]
  inc(n2.numEntries)
  var b2 = n2.a[0].b
  if s1 >= 0:
    n.a[n.numEntries] = lx
    inc(n.numEntries)
  while n.numEntries > 0 and n1.numEntries < (t.bigM + 1 - t.m) and n2.numEntries < (t.bigM + 1 - t.m):
    let next = pickNext(t, n, n1, n2, b1, b2)
    let d1 = area(union(b1, n.a[next].b)) - area(b1)
    let d2 = area(union(b2, n.a[next].b)) - area(b2)
    if (d1 < d2) or (d1 == d2 and ((area(b1) < area(b2)) or (area(b1) == area(b2) and n1.numEntries < n2.numEntries))):
      n1.a[n1.numEntries] = n.a[next]
      b1 = union(b1, n.a[next].b)
      inc(n1.numEntries)
    else:
      n2.a[n2.numEntries] = n.a[next]
      b2 = union(b2, n.a[next].b)
      inc(n2.numEntries)
    dec(n.numEntries)
    n.a[next] = n.a[n.numEntries]
  if n.numEntries == 0:
    discard
  elif n1.numEntries == (t.bigM + 1 - t.m):
    while n.numEntries > 0:
      dec(n.numEntries)
      n2.a[n2.numEntries] = n.a[n.numEntries]
      inc(n2.numEntries)
  elif n2.numEntries == (t.bigM + 1 - t.m):
    while n.numEntries > 0:
      dec(n.numEntries)
      n1.a[n1.numEntries] = n.a[n.numEntries]
      inc(n1.numEntries)
  when n is Node[M, D, RT, LT]:
    for i in 0 ..< n2.numEntries:
      n2.a[i].n.parent = n2
  n[] = n1[]
  return n2

proc overflowTreatment[M, D: Dim; RT, LT](t: RStarTree[M, D, RT, LT]; n: var Node[M, D, RT, LT] | var Leaf[M, D, RT, LT]; lx: L[D, RT, LT] | N[M, D, RT, LT]): typeof(n)

proc adjustTree[M, D: Dim; RT, LT](t: RTree[M, D, RT, LT]; l, ll: H[M, D, RT, LT]; hb: Box[D, RT]) =
  var n = l
  var nn = ll
  assert n != nil
  while true:
    if n == t.root:
      if nn == nil:
        break
      t.root = newNode[M, D, RT, LT]()
      t.root.level = n.level + 1
      Node[M, D, RT, LT](t.root).a[0].n = n
      n.parent = t.root
      nn.parent = t.root
      t.root.numEntries = 1
    let p = Node[M, D, RT, LT](n.parent)
    var i = 0
    while p.a[i].n != n:
      inc(i)
    var b: typeof(p.a[0].b) = default(typeof(p.a[0].b))
    if n of Leaf[M, D, RT, LT]:
      when false:#if likely(nn.isNil): # no performance gain
        b = union(p.a[i].b, Leaf[M, D, RT, LT](n).a[n.numEntries - 1].b)
      else:
        b = Leaf[M, D, RT, LT](n).a[0].b
        for j in 1 ..< n.numEntries:
          b = trtree.union(b, Leaf[M, D, RT, LT](n).a[j].b)
    elif n of Node[M, D, RT, LT]:
      b = Node[M, D, RT, LT](n).a[0].b
      for j in 1 ..< n.numEntries:
        b = union(b, Node[M, D, RT, LT](n).a[j].b)
    else:
      assert false
    #if nn.isNil and p.a[i].b == b: break # no performance gain
    p.a[i].b = b
    n = H[M, D, RT, LT](p)
    if unlikely(nn != nil):
      if nn of Leaf[M, D, RT, LT]:
        b = Leaf[M, D, RT, LT](nn).a[0].b
        for j in 1 ..< nn.numEntries:
          b = union(b, Leaf[M, D, RT, LT](nn).a[j].b)
      elif nn of Node[M, D, RT, LT]:
        b = Node[M, D, RT, LT](nn).a[0].b
        for j in 1 ..< nn.numEntries:
          b = union(b, Node[M, D, RT, LT](nn).a[j].b)
      else:
        assert false
      if p.numEntries < p.a.len:
        p.a[p.numEntries].b = b
        p.a[p.numEntries].n = nn
        inc(p.numEntries)
        assert n != nil
        nn = nil
      else:
        let h: N[M, D, RT, LT] = (b, nn)
        nn = quadraticSplit(t, p, h)
    assert n == H[M, D, RT, LT](p)
    assert n != nil
    assert t.root != nil

proc insert*[M, D: Dim; RT, LT](t: RTree[M, D, RT, LT]; leaf: N[M, D, RT, LT] | L[D, RT, LT]; level: int = 0) =
  when leaf is N[M, D, RT, LT]:
    assert level > 0
    type NodeLeaf = Node[M, D, RT, LT]
  else:
    assert level == 0
    type NodeLeaf = Leaf[M, D, RT, LT]
  for d in leaf.b:
    assert d.a <= d.b
  let l = NodeLeaf(chooseSubtree(t, leaf.b, level))
  if l.numEntries < l.a.len:
    l.a[l.numEntries] = leaf
    inc(l.numEntries)
    when leaf is N[M, D, RT, LT]:
      leaf.n.parent = l
    adjustTree(t, l, nil, leaf.b)
  else:
    let l2 = quadraticSplit(t, l, leaf)
    assert l2.level == l.level
    adjustTree(t, l, l2, leaf.b)

# R*Tree insert procs
proc rsinsert[M, D: Dim; RT, LT](t: RStarTree[M, D, RT, LT]; leaf: N[M, D, RT, LT] | L[D, RT, LT]; level: int)

proc reInsert[M, D: Dim; RT, LT](t: RStarTree[M, D, RT, LT]; n: var Node[M, D, RT, LT] | var Leaf[M, D, RT, LT]; lx: L[D, RT, LT] | N[M, D, RT, LT]) =
  type NL = typeof(lx)
  var lx = lx
  var buf: typeof(n.a) = default(typeof(n.a))
  let p = Node[M, D, RT, LT](n.parent)
  var i = 0
  while p.a[i].n != n:
    inc(i)
  let c = center(p.a[i].b)
  sortPlus(n.a, lx, proc (x, y: NL): int = cmp(distance(center(x.b), c), distance(center(y.b), c)))
  n.numEntries = M - t.p
  swap(n.a[n.numEntries], lx)
  inc n.numEntries
  var b = n.a[0].b
  for i in 1 ..< n.numEntries:
    b = union(b, n.a[i].b)
  p.a[i].b = b
  for i in M - t.p + 1 .. n.a.high:
    buf[i] = n.a[i]
  rsinsert(t, lx, n.level)
  for i in M - t.p + 1 .. n.a.high:
    rsinsert(t, buf[i], n.level)

proc overflowTreatment[M, D: Dim; RT, LT](t: RStarTree[M, D, RT, LT]; n: var Node[M, D, RT, LT] | var Leaf[M, D, RT, LT]; lx: L[D, RT, LT] | N[M, D, RT, LT]): typeof(n) =
  if n.level != t.root.level and t.firstOverflow[n.level]:
    t.firstOverflow[n.level] = false
    reInsert(t, n, lx)
    return nil
  else:
    let l2 = rstarSplit(t, n, lx)
    assert l2.level == n.level
    return l2

proc rsinsert[M, D: Dim; RT, LT](t: RStarTree[M, D, RT, LT]; leaf: N[M, D, RT, LT] | L[D, RT, LT]; level: int) =
  when leaf is N[M, D, RT, LT]:
    assert level > 0
    type NodeLeaf = Node[M, D, RT, LT]
  else:
    assert level == 0
    type NodeLeaf = Leaf[M, D, RT, LT]
  let l = NodeLeaf(chooseSubtree(t, leaf.b, level))
  if l.numEntries < l.a.len:
    l.a[l.numEntries] = leaf
    inc(l.numEntries)
    when leaf is N[M, D, RT, LT]:
      leaf.n.parent = l
    adjustTree(t, l, nil, leaf.b)
  else:
    when leaf is N[M, D, RT, LT]: # TODO do we need this?
      leaf.n.parent = l
    let l2 = overflowTreatment(t, l, leaf)
    if l2 != nil:
      assert l2.level == l.level
      adjustTree(t, l, l2, leaf.b)

proc insert*[M, D: Dim; RT, LT](t: RStarTree[M, D, RT, LT]; leaf: L[D, RT, LT]) =
  for d in leaf.b:
    assert d.a <= d.b
  for i in mitems(t.firstOverflow):
    i = true
  rsinsert(t, leaf, 0)

# delete
proc findLeaf[M, D: Dim; RT, LT](t: RTree[M, D, RT, LT]; leaf: L[D, RT, LT]): Leaf[M, D, RT, LT] =
  proc fl[M, D: Dim; RT, LT](h: H[M, D, RT, LT]; leaf: L[D, RT, LT]): Leaf[M, D, RT, LT] =
    var n = h
    if n of Node[M, D, RT, LT]:
      for i in 0 ..< n.numEntries:
        if intersect(Node[M, D, RT, LT](n).a[i].b, leaf.b):
          let l = fl(Node[M, D, RT, LT](n).a[i].n, leaf)
          if l != nil:
            return l
    elif n of Leaf[M, D, RT, LT]:
      for i in 0 ..< n.numEntries:
        if Leaf[M, D, RT, LT](n).a[i] == leaf:
          return Leaf[M, D, RT, LT](n)
    else:
      assert false
    return nil
  fl(t.root, leaf)

proc condenseTree[M, D: Dim; RT, LT](t: RTree[M, D, RT, LT]; leaf: Leaf[M, D, RT, LT]) =
  var n: H[M, D, RT, LT] = leaf
  var q = newSeq[H[M, D, RT, LT]]()
  var b: typeof(leaf.a[0].b) = default(typeof(leaf.a[0].b))
  while n != t.root:
    let p = Node[M, D, RT, LT](n.parent)
    var i = 0
    while p.a[i].n != n:
      inc(i)
    if n.numEntries < t.m:
      dec(p.numEntries)
      p.a[i] = p.a[p.numEntries]
      q.add(n)
    else:
      if n of Leaf[M, D, RT, LT]:
        b = Leaf[M, D, RT, LT](n).a[0].b
        for j in 1 ..< n.numEntries:
          b = union(b, Leaf[M, D, RT, LT](n).a[j].b)
      elif n of Node[M, D, RT, LT]:
        b = Node[M, D, RT, LT](n).a[0].b
        for j in 1 ..< n.numEntries:
          b = union(b, Node[M, D, RT, LT](n).a[j].b)
      else:
        assert false
      p.a[i].b = b
    n = n.parent
  if t of RStarTree[M, D, RT, LT]:
    for n in q:
      if n of Leaf[M, D, RT, LT]:
        for i in 0 ..< n.numEntries:
          for i in mitems(RStarTree[M, D, RT, LT](t).firstOverflow):
            i = true
          rsinsert(RStarTree[M, D, RT, LT](t), Leaf[M, D, RT, LT](n).a[i], 0)
      elif n of Node[M, D, RT, LT]:
        for i in 0 ..< n.numEntries:
          for i in mitems(RStarTree[M, D, RT, LT](t).firstOverflow):
            i = true
          rsinsert(RStarTree[M, D, RT, LT](t), Node[M, D, RT, LT](n).a[i], n.level)
      else:
        assert false
  else:
    for n in q:
      if n of Leaf[M, D, RT, LT]:
        for i in 0 ..< n.numEntries:
          insert(t, Leaf[M, D, RT, LT](n).a[i])
      elif n of Node[M, D, RT, LT]:
        for i in 0 ..< n.numEntries:
          insert(t, Node[M, D, RT, LT](n).a[i], n.level)
      else:
        assert false

proc delete*[M, D: Dim; RT, LT](t: RTree[M, D, RT, LT]; leaf: L[D, RT, LT]): bool {.discardable.} =
  let l = findLeaf(t, leaf)
  if l.isNil:
    return false
  else:
    var i = 0
    while l.a[i] != leaf:
      inc(i)
    dec(l.numEntries)
    l.a[i] = l.a[l.numEntries]
    condenseTree(t, l)
    if t.root.numEntries == 1:
      if t.root of Node[M, D, RT, LT]:
        t.root = Node[M, D, RT, LT](t.root).a[0].n
      t.root.parent = nil
    return true


var t = [4, 1, 3, 2]
var xt = 7
sortPlus(t, xt, system.cmp, SortOrder.Ascending)
echo xt, " ", t

type
  RSE = L[2, int, int]
  RSeq = seq[RSE]

proc rseq_search(rs: RSeq; rse: RSE): seq[int] =
  result = newSeq[int]()
  for i in rs:
    if intersect(i.b, rse.b):
      result.add(i.l)

proc rseq_delete(rs: var RSeq; rse: RSE): bool =
  result = false
  for i in 0 .. rs.high:
    if rs[i] == rse:
      #rs.delete(i)
      rs[i] = rs[rs.high]
      rs.setLen(rs.len - 1)
      return true

import random, algorithm

proc test(n: int) =
  var b: Box[2, int] = default(Box[2, int])
  echo center(b)
  var x1, x2, y1, y2: int
  var t = newRStarTree[8, 2, int, int]()
  #var t = newRTree[8, 2, int, int]()
  var rs = newSeq[RSE]()
  for i in 0 .. 5:
    for i in 0 .. n - 1:
      x1 = rand(1000)
      y1 = rand(1000)
      x2 = x1 + rand(25)
      y2 = y1 + rand(25)
      b = [(x1, x2), (y1, y2)]
      let el: L[2, int, int] = (b, i + 7)
      t.insert(el)
      rs.add(el)

    for i in 0 .. (n div 4):
      let j = rand(rs.high)
      var el = rs[j]
      assert t.delete(el)
      assert rs.rseq_delete(el)

    for i in 0 .. n - 1:
      x1 = rand(1000)
      y1 = rand(1000)
      x2 = x1 + rand(100)
      y2 = y1 + rand(100)
      b = [(x1, x2), (y1, y2)]
      let el: L[2, int, int] = (b, i)
      let r = search(t, b)
      let r2 = rseq_search(rs, el)
      assert r.len == r2.len
      assert r.sorted(system.cmp) == r2.sorted(system.cmp)

test(500)

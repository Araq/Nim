discard """
  cmd: "nim c --gc:orc -d:useMalloc -d:nimStressOrc $file"
  valgrind: "leaks"
  output: "done"
"""

import tables
import sets
import net

type
  BasicBlock = object
    inEdges: seq[ref BasicBlock]
    outEdges: seq[ref BasicBlock]
    name: int

proc newBasicBlock(name: int): ref BasicBlock =
  new(result)
  result.inEdges = newSeq[ref BasicBlock]()
  result.outEdges = newSeq[ref BasicBlock]()
  result.name = name

proc hash(x: ref BasicBlock): int {.inline.} =
  result = x.name

type
  BasicBlockEdge = object
    fr: ref BasicBlock
    to: ref BasicBlock

  Cfg = object
    basicBlockMap: Table[int, ref BasicBlock]
    edgeList: seq[BasicBlockEdge]
    startNode: ref BasicBlock

proc newCfg(): Cfg =
  result = Cfg()
  result.basicBlockMap = initTable[int, ref BasicBlock]()
  result.edgeList = newSeq[BasicBlockEdge]()

proc createNode(self: var Cfg, name: int): ref BasicBlock =
  #var node: ref BasicBlock
  result = self.basicBlockMap.getOrDefault(name)
  if result == nil:
    result = newBasicBlock(name)
    self.basicBlockMap.add name, result

  if self.startNode == nil:
    self.startNode = result

proc addEdge(self: var Cfg, edge: BasicBlockEdge) =
  self.edgeList.add(edge)

proc getNumNodes(self: Cfg): int =
  self.basicBlockMap.len

proc newBasicBlockEdge(cfg: var Cfg, fromName: int, toName: int) =
  var newEdge = BasicBlockEdge()
  newEdge.fr = cfg.createNode(fromName)
  newEdge.to = cfg.createNode(toName)
  newEdge.fr.outEdges.add(newEdge.to)
  newEdge.to.inEdges.add(newEdge.fr)
  cfg.addEdge(newEdge)

type
  SimpleLoop = object
    basicBlocks: seq[ref BasicBlock] # TODO: set here
    children: seq[ref SimpleLoop] # TODO: set here
    parent: ref SimpleLoop
    header: ref BasicBlock
    isRoot: bool
    isReducible: bool
    counter: int
    nestingLevel: int
    depthLevel: int

proc newSimpleLoop(): ref SimpleLoop =
  new(result)
  result.basicBlocks = newSeq[ref BasicBlock]()
  result.children = newSeq[ref SimpleLoop]()
  result.parent = nil
  result.header = nil
  result.isRoot = false
  result.isReducible = true
  result.counter = 0
  result.nestingLevel = 0
  result.depthLevel = 0

proc addNode(self: ref SimpleLoop, bb: ref BasicBlock) =
  self.basicBlocks.add bb

proc addChildLoop(self: ref SimpleLoop, loop: ref SimpleLoop) =
  self.children.add loop

proc setParent(self: ref SimpleLoop, parent: ref SimpleLoop) =
  self.parent = parent
  self.parent.addChildLoop(self)

proc setHeader(self: ref SimpleLoop, bb: ref BasicBlock) =
  self.basicBlocks.add(bb)
  self.header = bb

proc setNestingLevel(self: ref SimpleLoop, level: int) =
  self.nestingLevel = level
  if level == 0: self.isRoot = true

var loop_counter: int = 0

type
  Lsg = object
    loops: seq[ref SimpleLoop]
    root: ref SimpleLoop

proc createNewLoop(self: var Lsg): ref SimpleLoop =
  var s = newSimpleLoop()
  loop_counter += 1
  s.counter = loop_counter
  s

proc addLoop(self: var Lsg, l: ref SimpleLoop) =
  self.loops.add l

proc newLsg(): Lsg =
  result = Lsg()
  result.loops = newSeq[ref SimpleLoop]()
  result.root = result.createNewLoop()
  result.root.setNestingLevel(0)
  result.addLoop(result.root)

proc getNumLoops(self: Lsg): int =
  self.loops.len

type
  UnionFindNode = object
    parent: ref UnionFindNode
    bb: ref BasicBlock
    l: ref SimpleLoop
    dfsNumber: int

proc newUnionFindNode(): ref UnionFindNode =
  new(result)
  result.parent = nil
  result.bb = nil
  result.l = nil
  result.dfsNumber = 0

proc initNode(self: ref UnionFindNode, bb: ref BasicBlock, dfsNumber: int) =
  self.parent = self
  self.bb = bb
  self.dfsNumber = dfsNumber

proc findSet(self: ref UnionFindNode): ref UnionFindNode =
  var nodeList = newSeq[ref UnionFindNode]()
  var node = self

  while node != node.parent:
    var parent = node.parent
    if parent != parent.parent: nodeList.add node
    node = parent

  for iter in nodeList: iter.parent = node.parent
  node

proc union(self: ref UnionFindNode, unionFindNode: ref UnionFindNode) =
  self.parent = unionFindNode


const
  BB_NONHEADER    = 1 # a regular BB
  BB_REDUCIBLE    = 2 # reducible loop
  BB_SELF         = 3 # single BB loop
  BB_IRREDUCIBLE  = 4 # irreducible loop
  BB_DEAD         = 5 # a dead BB

  # # Marker for uninitialized nodes.
  UNVISITED = -1

  # # Safeguard against pathologic algorithm behavior.
  MAXNONBACKPREDS = (32 * 1024)

type
  HavlakLoopFinder = object
    cfg: Cfg
    lsg: Lsg

proc newHavlakLoopFinder(cfg: sink Cfg, lsg: sink Lsg): HavlakLoopFinder =
  result = HavlakLoopFinder()
  result.cfg = cfg
  result.lsg = lsg

proc isAncestor(w: int, v: int, last: seq[int]): bool =
  w <= v and v <= last[w]

proc dfs(currentNode: ref BasicBlock, nodes: var seq[ref UnionFindNode], number: var Table[ref BasicBlock, int], last: var seq[int], current: int): int =
  nodes[current].initNode(currentNode, current)
  number[currentNode] = current

  var lastid = current
  for target in currentNode.outEdges:
    if number[target] == UNVISITED:
      lastid = dfs(target, nodes, number, last, lastid + 1)

  last[number[currentNode]] = lastid
  return lastid

proc findLoops(self: var HavlakLoopFinder): int =
  var startNode = self.cfg.startNode
  if startNode == nil: return 0
  var size = self.cfg.getNumNodes

  var nonBackPreds = newSeq[HashSet[int]]()
  var backPreds = newSeq[seq[int]]()
  var number = initTable[ref BasicBlock, int]()
  var header = newSeq[int](size)
  var types = newSeq[int](size)
  var last = newSeq[int](size)
  var nodes = newSeq[ref UnionFindNode]()

  for i in 1..size:
    nonBackPreds.add initHashSet[int](1)
    backPreds.add newSeq[int]()
    nodes.add newUnionFindNode()

  # Step a:
  #   - initialize all nodes as unvisited.
  #   - depth-first traversal and numbering.
  #   - unreached BB's are marked as dead.
  #
  for v in self.cfg.basicBlockMap.values: number[v] = UNVISITED
  discard dfs(startNode, nodes, number, last, 0)

  # Step b:
  #   - iterate over all nodes.
  #
  #   A backedge comes from a descendant in the DFS tree, and non-backedges
  #   from non-descendants (following Tarjan).
  #
  #   - check incoming edges 'v' and add them to either
  #     - the list of backedges (backPreds) or
  #     - the list of non-backedges (nonBackPreds)
  #
  for w in 0 ..< size:
    header[w] = 0
    types[w]  = BB_NONHEADER

    var nodeW = nodes[w].bb
    if nodeW != nil:
      for nodeV in nodeW.inEdges:
        var v = number[nodeV]
        if v != UNVISITED:
          if isAncestor(w, v, last):
            backPreds[w].add v
          else:
            nonBackPreds[w].incl v
    else:
      types[w] = BB_DEAD

  # Start node is root of all other loops.
  header[0] = 0

  # Step c:
  #
  # The outer loop, unchanged from Tarjan. It does nothing except
  # for those nodes which are the destinations of backedges.
  # For a header node w, we chase backward from the sources of the
  # backedges adding nodes to the set P, representing the body of
  # the loop headed by w.
  #
  # By running through the nodes in reverse of the DFST preorder,
  # we ensure that inner loop headers will be processed before the
  # headers for surrounding loops.

  for w in countdown(size - 1, 0):
    # this is 'P' in Havlak's paper
    var nodePool = newSeq[ref UnionFindNode]()

    var nodeW = nodes[w].bb
    if nodeW != nil: # dead BB
      # Step d:
      for v in backPreds[w]:
        if v != w:
          nodePool.add nodes[v].findSet
        else:
          types[w] = BB_SELF

      # Copy nodePool to workList.
      #
      var workList = newSeq[ref UnionFindNode]()
      for x in nodePool: workList.add x

      if nodePool.len != 0: types[w] = BB_REDUCIBLE

      # work the list...
      #
      while workList.len > 0:
        var x = workList[0]
        workList.del(0)

        # Step e:
        #
        # Step e represents the main difference from Tarjan's method.
        # Chasing upwards from the sources of a node w's backedges. If
        # there is a node y' that is not a descendant of w, w is marked
        # the header of an irreducible loop, there is another entry
        # into this loop that avoids w.
        #

        # The algorithm has degenerated. Break and
        # return in this case.
        #
        var nonBackSize = nonBackPreds[x.dfsNumber].len
        if nonBackSize > MAXNONBACKPREDS: return 0

        for iter in nonBackPreds[x.dfsNumber]:
          var y = nodes[iter]
          var ydash = y.findSet

          if not isAncestor(w, ydash.dfsNumber, last):
            types[w] = BB_IRREDUCIBLE
            nonBackPreds[w].incl ydash.dfsNumber
          else:
            if ydash.dfsNumber != w and not nodePool.contains(ydash):
              workList.add ydash
              nodePool.add ydash

      # Collapse/Unionize nodes in a SCC to a single node
      # For every SCC found, create a loop descriptor and link it in.
      #
      if (nodePool.len > 0) or (types[w] == BB_SELF):
        var l = self.lsg.createNewLoop

        l.setHeader(nodeW)
        l.isReducible = types[w] != BB_IRREDUCIBLE

        # At this point, one can set attributes to the loop, such as:
        #
        # the bottom node:
        #    iter  = backPreds(w).begin();
        #    loop bottom is: nodes(iter).node;
        #
        # the number of backedges:
        #    backPreds(w).size()
        #
        # whether this loop is reducible:
        #    types(w) != BB_IRREDUCIBLE
        #
        nodes[w].l = l

        for node in nodePool:
          # Add nodes to loop descriptor.
          header[node.dfsNumber] = w
          node.union(nodes[w])

          # Nested loops are not added, but linked together.
          var node_l = node.l
          if node_l != nil:
            node_l.setParent(l)
          else:
            l.addNode(node.bb)

        self.lsg.addLoop(l)

  result = self.lsg.getNumLoops


type
  LoopTesterApp = object
    cfg: Cfg
    lsg: Lsg

proc newLoopTesterApp(): LoopTesterApp =
  result = LoopTesterApp()
  result.cfg = newCfg()
  result.lsg = newLsg()

proc buildDiamond(self: var LoopTesterApp, start: int): int =
  var bb0 = start
  newBasicBlockEdge(self.cfg, bb0, bb0 + 1)
  newBasicBlockEdge(self.cfg, bb0, bb0 + 2)
  newBasicBlockEdge(self.cfg, bb0 + 1, bb0 + 3)
  newBasicBlockEdge(self.cfg, bb0 + 2, bb0 + 3)
  result = bb0 + 3

proc buildConnect(self: var LoopTesterApp, start1: int, end1: int) =
  newBasicBlockEdge(self.cfg, start1, end1)

proc buildStraight(self: var LoopTesterApp, start: int, n: int): int =
  for i in 0..n-1:
    self.buildConnect(start + i, start + i + 1)
  result = start + n

proc buildBaseLoop(self: var LoopTesterApp, from1: int): int =
  var header   = self.buildStraight(from1, 1)
  var diamond1 = self.buildDiamond(header)
  var d11      = self.buildStraight(diamond1, 1)
  var diamond2 = self.buildDiamond(d11)
  var footer   = self.buildStraight(diamond2, 1)

  self.buildConnect(diamond2, d11)
  self.buildConnect(diamond1, header)
  self.buildConnect(footer, from1)
  result = self.buildStraight(footer, 1)

proc run(self: var LoopTesterApp) =
  discard self.cfg.createNode(0)
  discard self.buildBaseLoop(0)
  discard self.cfg.createNode(1)
  self.buildConnect(0, 2)

  for i in 1..8:
    # yes, it's 8 and it's correct.
    var h = newHavlakLoopFinder(self.cfg, newLsg())
    discard h.findLoops()

  echo "done"

var l = newLoopTesterApp()
l.run()

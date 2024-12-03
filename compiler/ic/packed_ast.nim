#
#
#           The Nim Compiler
#        (c) Copyright 2020 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Packed AST representation, mostly based on a seq of nodes.
## For IC support. Far future: Rewrite the compiler passes to
## use this representation directly in all the transformations,
## it is superior.

import std/[hashes, tables, strtabs]
import bitabs, rodfiles
import ".." / [ast, options]

import iclineinfos

when defined(nimPreviewSlimSystem):
  import std/assertions

type
  SymId* = distinct int32
  ModuleId* = distinct int32
  NodePos* = distinct int

  NodeId* = distinct int32

  PackedItemId* = object
    module*: LitId       # 0 if it's this module
    item*: int32         # same as the in-memory representation

const
  nilItemId* = PackedItemId(module: LitId(0), item: 0.int32)

const
  emptyNodeId* = NodeId(-1)

type
  PackedLib* = object
    kind*: TLibKind
    generated*: bool
    isOverridden*: bool
    name*: LitId
    path*: NodeId

  PackedSym* = object
    id*: int32
    kind*: TSymKind
    name*: LitId
    typ*: PackedItemId
    flags*: TSymFlags
    magic*: TMagic
    info*: PackedLineInfo
    ast*: NodeId
    owner*: PackedItemId
    guard*: PackedItemId
    bitsize*: int
    alignment*: int # for alignment
    options*: TOptions
    position*: int
    offset*: int32
    disamb*: int32
    externalName*: LitId # instead of TLoc
    locFlags*: TLocFlags
    annex*: PackedLib
    when hasFFI:
      cname*: LitId
    constraint*: NodeId
    instantiatedFrom*: PackedItemId

  PackedType* = object
    id*: int32
    kind*: TTypeKind
    callConv*: TCallingConvention
    #nodekind*: TNodeKind
    flags*: TTypeFlags
    types*: seq[PackedItemId]
    n*: NodeId
    #nodeflags*: TNodeFlags
    sym*: PackedItemId
    owner*: PackedItemId
    size*: BiggestInt
    align*: int16
    paddingAtEnd*: int16
    # not serialized: loc*: TLoc because it is backend-specific
    typeInst*: PackedItemId
    nonUniqueId*: int32

  PackedNode* = object     # 8 bytes
    x: uint32
    info*: PackedLineInfo

  PackedTree* = object ## usually represents a full Nim module
    nodes: seq[PackedNode]
    withFlags: seq[(int32, TNodeFlags)]
    withTypes: seq[(int32, PackedItemId)]

  PackedInstantiation* = object
    key*, sym*: PackedItemId
    concreteTypes*: seq[PackedItemId]

const
  NodeKindBits = 8'u32
  NodeKindMask = (1'u32 shl NodeKindBits) - 1'u32

template kind*(n: PackedNode): TNodeKind = TNodeKind(n.x and NodeKindMask)
template uoperand*(n: PackedNode): uint32 = (n.x shr NodeKindBits)
template soperand*(n: PackedNode): int32 = int32(uoperand(n))

template toX(k: TNodeKind; operand: uint32): uint32 =
  uint32(k) or (operand shl NodeKindBits)

template toX(k: TNodeKind; operand: LitId): uint32 =
  uint32(k) or (operand.uint32 shl NodeKindBits)

template typeId*(n: PackedNode): PackedItemId = n.typ

proc `==`*(a, b: SymId): bool {.borrow.}
proc hash*(a: SymId): Hash {.borrow.}

proc `==`*(a, b: NodePos): bool {.borrow.}
#proc `==`*(a, b: PackedItemId): bool {.borrow.}
proc `==`*(a, b: NodeId): bool {.borrow.}

proc newTreeFrom*(old: PackedTree): PackedTree =
  result = PackedTree(nodes: @[])
  when false: result.sh = old.sh

proc addIdent*(tree: var PackedTree; s: LitId; info: PackedLineInfo) =
  tree.nodes.add PackedNode(x: toX(nkIdent, uint32(s)), info: info)

proc addSym*(tree: var PackedTree; s: int32; info: PackedLineInfo) =
  tree.nodes.add PackedNode(x: toX(nkSym, cast[uint32](s)), info: info)

proc addSymDef*(tree: var PackedTree; s: SymId; info: PackedLineInfo) =
  tree.nodes.add PackedNode(x: toX(nkSym, cast[uint32](s)), info: info)

proc isAtom*(tree: PackedTree; pos: int): bool {.inline.} = tree.nodes[pos].kind <= nkNilLit

type
  PatchPos = distinct int

proc addNode*(t: var PackedTree; kind: TNodeKind; operand: int32;
              typeId: PackedItemId = nilItemId; info: PackedLineInfo;
              flags: TNodeFlags = {}) =
  t.nodes.add PackedNode(x: toX(kind, cast[uint32](operand)), info: info)
  if flags != {}:
    t.withFlags.add (t.nodes.len.int32 - 1, flags)
  if typeId != nilItemId:
    t.withTypes.add (t.nodes.len.int32 - 1, typeId)

proc prepare*(tree: var PackedTree; kind: TNodeKind; flags: TNodeFlags; typeId: PackedItemId; info: PackedLineInfo): PatchPos =
  result = PatchPos tree.nodes.len
  tree.addNode(kind = kind, flags = flags, operand = 0, info = info, typeId = typeId)

proc prepare*(dest: var PackedTree; source: PackedTree; sourcePos: NodePos): PatchPos =
  result = PatchPos dest.nodes.len
  dest.nodes.add source.nodes[sourcePos.int]

proc patch*(tree: var PackedTree; pos: PatchPos) =
  let pos = pos.int
  let k = tree.nodes[pos].kind
  assert k > nkNilLit
  let distance = int32(tree.nodes.len - pos)
  assert distance > 0
  tree.nodes[pos].x = toX(k, cast[uint32](distance))

proc len*(tree: PackedTree): int {.inline.} = tree.nodes.len

proc `[]`*(tree: PackedTree; i: NodePos): lent PackedNode {.inline.} =
  tree.nodes[i.int]

template rawSpan(n: PackedNode): int = int(uoperand(n))

proc nextChild(tree: PackedTree; pos: var int) {.inline.} =
  if tree.nodes[pos].kind > nkNilLit:
    assert tree.nodes[pos].uoperand > 0
    inc pos, tree.nodes[pos].rawSpan
  else:
    inc pos

iterator sonsReadonly*(tree: PackedTree; n: NodePos): NodePos =
  var pos = n.int
  assert tree.nodes[pos].kind > nkNilLit
  let last = pos + tree.nodes[pos].rawSpan
  inc pos
  while pos < last:
    yield NodePos pos
    nextChild tree, pos

iterator sons*(dest: var PackedTree; tree: PackedTree; n: NodePos): NodePos =
  let patchPos = prepare(dest, tree, n)
  for x in sonsReadonly(tree, n): yield x
  patch dest, patchPos

iterator isons*(dest: var PackedTree; tree: PackedTree;
                n: NodePos): (int, NodePos) =
  var i = 0
  for ch0 in sons(dest, tree, n):
    yield (i, ch0)
    inc i

iterator sonsFrom1*(tree: PackedTree; n: NodePos): NodePos =
  var pos = n.int
  assert tree.nodes[pos].kind > nkNilLit
  let last = pos + tree.nodes[pos].rawSpan
  inc pos
  if pos < last:
    nextChild tree, pos
  while pos < last:
    yield NodePos pos
    nextChild tree, pos

iterator sonsWithoutLast2*(tree: PackedTree; n: NodePos): NodePos =
  var count = 0
  for child in sonsReadonly(tree, n):
    inc count
  var pos = n.int
  assert tree.nodes[pos].kind > nkNilLit
  let last = pos + tree.nodes[pos].rawSpan
  inc pos
  while pos < last and count > 2:
    yield NodePos pos
    dec count
    nextChild tree, pos

proc parentImpl(tree: PackedTree; n: NodePos): NodePos =
  # finding the parent of a node is rather easy:
  var pos = n.int - 1
  while pos >= 0 and (isAtom(tree, pos) or (pos + tree.nodes[pos].rawSpan - 1 < n.int)):
    dec pos
  #assert pos >= 0, "node has no parent"
  result = NodePos(pos)

template parent*(n: NodePos): NodePos = parentImpl(tree, n)

proc hasXsons*(tree: PackedTree; n: NodePos; x: int): bool =
  var count = 0
  if tree.nodes[n.int].kind > nkNilLit:
    for child in sonsReadonly(tree, n): inc count
  result = count == x

proc hasAtLeastXsons*(tree: PackedTree; n: NodePos; x: int): bool =
  if tree.nodes[n.int].kind > nkNilLit:
    var count = 0
    for child in sonsReadonly(tree, n):
      inc count
      if count >= x: return true
  return false

proc firstSon*(tree: PackedTree; n: NodePos): NodePos {.inline.} =
  NodePos(n.int+1)
proc kind*(tree: PackedTree; n: NodePos): TNodeKind {.inline.} =
  tree.nodes[n.int].kind
proc litId*(tree: PackedTree; n: NodePos): LitId {.inline.} =
  LitId tree.nodes[n.int].uoperand
proc info*(tree: PackedTree; n: NodePos): PackedLineInfo {.inline.} =
  tree.nodes[n.int].info

proc findType*(tree: PackedTree; n: NodePos): PackedItemId =
  for x in tree.withTypes:
    if x[0] == int32(n): return x[1]
    if x[0] > int32(n): return nilItemId
  return nilItemId

proc findFlags*(tree: PackedTree; n: NodePos): TNodeFlags =
  for x in tree.withFlags:
    if x[0] == int32(n): return x[1]
    if x[0] > int32(n): return {}
  return {}

template typ*(n: NodePos): PackedItemId =
  tree.findType(n)
template flags*(n: NodePos): TNodeFlags =
  tree.findFlags(n)

template uoperand*(n: NodePos): uint32 =
  tree.nodes[n.int].uoperand

proc span*(tree: PackedTree; pos: int): int {.inline.} =
  if isAtom(tree, pos): 1 else: tree.nodes[pos].rawSpan

proc sons2*(tree: PackedTree; n: NodePos): (NodePos, NodePos) =
  assert(not isAtom(tree, n.int))
  let a = n.int+1
  let b = a + span(tree, a)
  result = (NodePos a, NodePos b)

proc sons3*(tree: PackedTree; n: NodePos): (NodePos, NodePos, NodePos) =
  assert(not isAtom(tree, n.int))
  let a = n.int+1
  let b = a + span(tree, a)
  let c = b + span(tree, b)
  result = (NodePos a, NodePos b, NodePos c)

proc ithSon*(tree: PackedTree; n: NodePos; i: int): NodePos =
  result = default(NodePos)
  if tree.nodes[n.int].kind > nkNilLit:
    var count = 0
    for child in sonsReadonly(tree, n):
      if count == i: return child
      inc count
  assert false, "node has no i-th child"

when false:
  proc `@`*(tree: PackedTree; lit: LitId): lent string {.inline.} =
    tree.sh.strings[lit]

template kind*(n: NodePos): TNodeKind = tree.nodes[n.int].kind
template info*(n: NodePos): PackedLineInfo = tree.nodes[n.int].info
template litId*(n: NodePos): LitId = LitId tree.nodes[n.int].uoperand

template symId*(n: NodePos): SymId = SymId tree.nodes[n.int].soperand

proc firstSon*(n: NodePos): NodePos {.inline.} = NodePos(n.int+1)

const
  externIntLit* = {nkCharLit,
    nkIntLit,
    nkInt8Lit,
    nkInt16Lit,
    nkInt32Lit,
    nkInt64Lit,
    nkUIntLit,
    nkUInt8Lit,
    nkUInt16Lit,
    nkUInt32Lit,
    nkUInt64Lit}

  externSIntLit* = {nkIntLit, nkInt8Lit, nkInt16Lit, nkInt32Lit, nkInt64Lit}
  externUIntLit* = {nkUIntLit, nkUInt8Lit, nkUInt16Lit, nkUInt32Lit, nkUInt64Lit}
  directIntLit* = nkNone

template copyInto*(dest, n, body) =
  let patchPos = prepare(dest, tree, n)
  body
  patch dest, patchPos

template copyIntoKind*(dest, kind, info, body) =
  let patchPos = prepare(dest, kind, info)
  body
  patch dest, patchPos

proc getNodeId*(tree: PackedTree): NodeId {.inline.} = NodeId tree.nodes.len

iterator allNodes*(tree: PackedTree): NodePos =
  var p = 0
  while p < tree.len:
    yield NodePos(p)
    let s = span(tree, p)
    inc p, s

proc toPackedItemId*(item: int32): PackedItemId {.inline.} =
  PackedItemId(module: LitId(0), item: item)

proc load*(f: var RodFile; t: var PackedTree) =
  loadSeq f, t.nodes
  loadSeq f, t.withFlags
  loadSeq f, t.withTypes

proc store*(f: var RodFile; t: PackedTree) =
  storeSeq f, t.nodes
  storeSeq f, t.withFlags
  storeSeq f, t.withTypes

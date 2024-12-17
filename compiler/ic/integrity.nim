#
#
#           The Nim Compiler
#        (c) Copyright 2021 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Integrity checking for a set of .rod files.
## The set must cover a complete Nim project.

import std/[sets, tables]

when defined(nimPreviewSlimSystem):
  import std/assertions

import ".." / [ast, modulegraphs]
import packed_ast, bitabs, ic

type
  CheckedContext = object
    g: ModuleGraph
    thisModule: int32
    checkedSyms: HashSet[ItemId]
    checkedTypes: HashSet[ItemId]

proc checkType(c: var CheckedContext; typeId: PackedItemId)
proc checkForeignSym(c: var CheckedContext; symId: PackedItemId)
proc checkNode(c: var CheckedContext; tree: PackedTree; n: NodePos)

proc checkTypeObj(c: var CheckedContext; typ: PackedType) =
  for child in typ.types:
    checkType(c, child)
  if typ.n != emptyNodeId:
    checkNode(c, c.g.packed[c.thisModule].fromDisk.bodies, NodePos typ.n)
  if typ.sym != nilItemId:
    checkForeignSym(c, typ.sym)
  if typ.owner != nilItemId:
    checkForeignSym(c, typ.owner)
  checkType(c, typ.typeInst)

proc checkType(c: var CheckedContext; typeId: PackedItemId) =
  if typeId == nilItemId: return
  let itemId = translateId(typeId, c.g.packed, c.thisModule, c.g.config)
  if not c.checkedTypes.containsOrIncl(itemId):
    let oldThisModule = c.thisModule
    c.thisModule = itemId.module
    checkTypeObj c, c.g.packed[itemId.module].fromDisk.types[itemId.item]
    c.thisModule = oldThisModule

proc checkSym(c: var CheckedContext; s: PackedSym) =
  if s.name != LitId(0):
    assert c.g.packed[c.thisModule].fromDisk.strings.hasLitId s.name
  checkType c, s.typ
  if s.ast != emptyNodeId:
    checkNode(c, c.g.packed[c.thisModule].fromDisk.bodies, NodePos s.ast)
  if s.owner != nilItemId:
    checkForeignSym(c, s.owner)

proc checkLocalSym(c: var CheckedContext; item: int32) =
  let itemId = ItemId(module: c.thisModule, item: item)
  if not c.checkedSyms.containsOrIncl(itemId):
    checkSym c, c.g.packed[c.thisModule].fromDisk.syms[item]

proc checkForeignSym(c: var CheckedContext; symId: PackedItemId) =
  let itemId = translateId(symId, c.g.packed, c.thisModule, c.g.config)
  if not c.checkedSyms.containsOrIncl(itemId):
    let oldThisModule = c.thisModule
    c.thisModule = itemId.module
    checkSym c, c.g.packed[itemId.module].fromDisk.syms[itemId.item]
    c.thisModule = oldThisModule

proc checkNode(c: var CheckedContext; tree: PackedTree; n: NodePos) =
  let t = findType(tree, n)
  if t != nilItemId:
    checkType(c, t)
  case n.kind
  of nkEmpty, nkNilLit, nkType, nkNilRodNode:
    discard
  of nkIdent:
    assert c.g.packed[c.thisModule].fromDisk.strings.hasLitId n.litId
  of nkSym:
    checkLocalSym(c, tree[n].soperand)
  of directIntLit:
    discard
  of externIntLit, nkFloatLit..nkFloat128Lit:
    assert c.g.packed[c.thisModule].fromDisk.numbers.hasLitId n.litId
  of nkStrLit..nkTripleStrLit:
    assert c.g.packed[c.thisModule].fromDisk.strings.hasLitId n.litId
  of nkModuleRef:
    let (n1, n2) = sons2(tree, n)
    assert n1.kind == nkNone
    assert n2.kind == nkNone
    checkForeignSym(c, PackedItemId(module: n1.litId, item: tree[n2].soperand))
  else:
    for n0 in sonsReadonly(tree, n):
      checkNode(c, tree, n0)

proc checkTree(c: var CheckedContext; t: PackedTree) =
  for p in allNodes(t): checkNode(c, t, p)

proc checkLocalSymIds(c: var CheckedContext; m: PackedModule; symIds: seq[int32]) =
  for symId in symIds:
    assert symId >= 0 and symId < m.syms.len, $symId & " " & $m.syms.len

proc checkModule(c: var CheckedContext; m: PackedModule) =
  # We check that:
  # - Every symbol references existing types and symbols.
  # - Every tree node references existing types and symbols.
  for _, v in pairs(m.syms):
    checkLocalSym c, v.id

  checkTree c, m.toReplay
  checkTree c, m.topLevel

  for e in m.exports:
    #assert e[1] >= 0 and e[1] < m.syms.len
    assert e[0] == m.syms[e[1]].name

  for e in m.compilerProcs:
    #assert e[1] >= 0 and e[1] < m.syms.len
    assert e[0] == m.syms[e[1]].name

  checkLocalSymIds c, m, m.converters
  checkLocalSymIds c, m, m.methods
  checkLocalSymIds c, m, m.trmacros
  checkLocalSymIds c, m, m.pureEnums
  #[
    To do: Check all these fields:

    reexports*: seq[(LitId, PackedItemId)]
    macroUsages*: seq[(PackedItemId, PackedLineInfo)]

    typeInstCache*: seq[(PackedItemId, PackedItemId)]
    procInstCache*: seq[PackedInstantiation]
    attachedOps*: seq[(TTypeAttachedOp, PackedItemId, PackedItemId)]
    methodsPerGenericType*: seq[(PackedItemId, int, PackedItemId)]
    enumToStringProcs*: seq[(PackedItemId, PackedItemId)]
    methodsPerType*: seq[(PackedItemId, PackedItemId)]
    dispatchers*: seq[PackedItemId]
  ]#

proc checkIntegrity*(g: ModuleGraph) =
  var c = CheckedContext(g: g)
  for i in 0..<len(g.packed):
    # case statement here to enforce exhaustive checks.
    case g.packed[i].status
    of undefined:
      discard "nothing to do"
    of loading:
      assert false, "cannot check integrity: Module still loading"
    of stored, storing, outdated, loaded:
      c.thisModule = int32 i
      checkModule(c, g.packed[i].fromDisk)

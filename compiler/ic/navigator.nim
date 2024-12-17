#
#
#           The Nim Compiler
#        (c) Copyright 2021 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Supports the "nim check --ic:on --defusages:FILE,LINE,COL"
## IDE-like features. It uses the set of .rod files to accomplish
## its task. The set must cover a complete Nim project.

import std/[sets, tables]

from std/os import nil
from std/private/miscdollars import toLocation

when defined(nimPreviewSlimSystem):
  import std/assertions

import ".." / [ast, modulegraphs, msgs, options]
import iclineinfos
import packed_ast, bitabs, ic

type
  UnpackedLineInfo = object
    file: LitId
    line, col: int
  NavContext = object
    g: ModuleGraph
    thisModule: int32
    trackPos: UnpackedLineInfo
    alreadyEmitted: HashSet[string]
    outputSep: char # for easier testing, use short filenames and spaces instead of tabs.

proc isTracked(man: LineInfoManager; current: PackedLineInfo, trackPos: UnpackedLineInfo, tokenLen: int): bool =
  let (currentFile, currentLine, currentCol) = man.unpack(current)
  if currentFile == trackPos.file and currentLine == trackPos.line:
    let col = trackPos.col
    if col >= currentCol and col < currentCol+tokenLen:
      result = true
    else:
      result = false
  else:
    result = false

proc searchLocalSym(c: var NavContext; s: PackedSym; info: PackedLineInfo): bool =
  result = s.name != LitId(0) and
    isTracked(c.g.packed[c.thisModule].fromDisk.man, info, c.trackPos, c.g.packed[c.thisModule].fromDisk.strings[s.name].len)

proc searchForeignSym(c: var NavContext; s: ItemId; info: PackedLineInfo): bool =
  let name = c.g.packed[s.module].fromDisk.syms[s.item].name
  result = name != LitId(0) and
    isTracked(c.g.packed[c.thisModule].fromDisk.man, info, c.trackPos, c.g.packed[s.module].fromDisk.strings[name].len)

const
  EmptyItemId = ItemId(module: -1'i32, item: -1'i32)

proc search(c: var NavContext; tree: PackedTree): ItemId =
  # We use the linear representation here directly:
  for i in 0..<len(tree):
    let i = NodePos(i)
    case tree[i].kind
    of nkSym:
      let item = tree[i].soperand
      if searchLocalSym(c, c.g.packed[c.thisModule].fromDisk.syms[item], tree[i].info):
        return ItemId(module: c.thisModule, item: item)
    of nkModuleRef:
      let (currentFile, currentLine, currentCol) = c.g.packed[c.thisModule].fromDisk.man.unpack(tree[i].info)
      if currentLine == c.trackPos.line and currentFile == c.trackPos.file:
        let (n1, n2) = sons2(tree, i)
        assert n1.kind == nkInt32Lit
        assert n2.kind == nkInt32Lit
        let pId = PackedItemId(module: n1.litId, item: tree[n2].soperand)
        let itemId = translateId(pId, c.g.packed, c.thisModule, c.g.config)
        if searchForeignSym(c, itemId, tree[i].info):
          return itemId
    else: discard
  return EmptyItemId

proc isDecl(tree: PackedTree; n: NodePos): bool =
  # XXX This is not correct yet.
  const declarativeNodes = procDefs + {nkMacroDef, nkTemplateDef,
    nkLetSection, nkVarSection, nkUsingStmt, nkConstSection, nkTypeSection,
    nkIdentDefs, nkEnumTy, nkVarTuple}
  result = n.int >= 0 and tree[n].kind in declarativeNodes

proc usage(c: var NavContext; info: PackedLineInfo; isDecl: bool) =
  let (fileId, line, col) = unpack(c.g.packed[c.thisModule].fromDisk.man, info)
  var m = ""
  var file = c.g.packed[c.thisModule].fromDisk.strings[fileId]
  if c.outputSep == ' ':
    file = os.extractFilename file
  toLocation(m, file, line, col + ColOffset)
  if not c.alreadyEmitted.containsOrIncl(m):
    msgWriteln c.g.config, (if isDecl: "def" else: "usage") & c.outputSep & m

proc list(c: var NavContext; tree: PackedTree; sym: ItemId) =
  for i in 0..<len(tree):
    let i = NodePos(i)
    case tree[i].kind
    of nkSym:
      let item = tree[i].soperand
      if sym.item == item and sym.module == c.thisModule:
        usage(c, tree[i].info, isDecl(tree, parent(i)))
    of nkModuleRef:
      let (n1, n2) = sons2(tree, i)
      assert n1.kind == nkNone
      assert n2.kind == nkNone
      let pId = PackedItemId(module: n1.litId, item: tree[n2].soperand)
      let itemId = translateId(pId, c.g.packed, c.thisModule, c.g.config)
      if itemId.item == sym.item and sym.module == itemId.module:
        usage(c, tree[i].info, isDecl(tree, parent(i)))
    else: discard

proc searchForIncludeFile(g: ModuleGraph; fullPath: string): int =
  for i in 0..<len(g.packed):
    for k in 1..high(g.packed[i].fromDisk.includes):
      # we start from 1 because the first "include" file is
      # the module's filename.
      if os.cmpPaths(g.packed[i].fromDisk.strings[g.packed[i].fromDisk.includes[k][0]], fullPath) == 0:
        return i
  return -1

proc nav(g: ModuleGraph) =
  # translate the track position to a packed position:
  let unpacked = g.config.m.trackPos
  var mid = unpacked.fileIndex.int

  let fullPath = toFullPath(g.config, unpacked.fileIndex)

  if g.packed[mid].status == undefined:
    # check if 'mid' is an include file of some other module:
    mid = searchForIncludeFile(g, fullPath)

  if mid < 0:
    localError(g.config, unpacked, "unknown file name: " & fullPath)
    return

  let fileId = g.packed[mid].fromDisk.strings.getKeyId(fullPath)

  if fileId == LitId(0):
    internalError(g.config, unpacked, "cannot find a valid file ID")
    return

  var c = NavContext(
    g: g,
    thisModule: int32 mid,
    trackPos: UnpackedLineInfo(line: unpacked.line.int, col: unpacked.col.int, file: fileId),
    outputSep: if isDefined(g.config, "nimIcNavigatorTests"): ' ' else: '\t'
  )
  var symId = search(c, g.packed[mid].fromDisk.topLevel)
  if symId == EmptyItemId:
    symId = search(c, g.packed[mid].fromDisk.bodies)

  if symId == EmptyItemId:
    localError(g.config, unpacked, "no symbol at this position")
    return

  for i in 0..<len(g.packed):
    # case statement here to enforce exhaustive checks.
    case g.packed[i].status
    of undefined:
      discard "nothing to do"
    of loading:
      assert false, "cannot check integrity: Module still loading"
    of stored, storing, outdated, loaded:
      c.thisModule = int32 i
      list(c, g.packed[i].fromDisk.topLevel, symId)
      list(c, g.packed[i].fromDisk.bodies, symId)

proc navDefinition*(g: ModuleGraph) = nav(g)
proc navUsages*(g: ModuleGraph) = nav(g)
proc navDefusages*(g: ModuleGraph) = nav(g)

proc writeRodFiles*(g: ModuleGraph) =
  for i in 0..<len(g.packed):
    case g.packed[i].status
    of undefined, loading, stored, loaded:
      discard "nothing to do"
    of storing, outdated:
      closeRodFile(g, g.packed[i].module)

#
#
#           The Nim Compiler
#        (c) Copyright 2020 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import std / [hashes, tables, intsets, sha1]
import packed_ast, bitabs, rodfiles
import ".." / [ast, idents, lineinfos, msgs, ropes, options,
  pathutils, condsyms]

from std / os import removeFile, isAbsolute

type
  PackedConfig* = object
    backend: TBackend
    selectedGC: TGCMode
    cCompiler: TSystemCC
    options: TOptions
    globalOptions: TGlobalOptions

  PackedModule* = object ## the parts of a PackedEncoder that are part of the .rod file
    definedSymbols: string
    includes: seq[(LitId, string)] # first entry is the module filename itself
    imports: seq[LitId] # the modules this module depends on
    toReplay: PackedTree # pragmas and VM specific state to replay.
    topLevel*: PackedTree  # top level statements
    bodies*: PackedTree # other trees. Referenced from typ.n and sym.ast by their position.
    #producedGenerics*: Table[GenericKey, SymId]
    exports*: seq[(LitId, int32)]
    reexports*: seq[(LitId, PackedItemId)]
    compilerProcs*, trmacros*, converters*, pureEnums*: seq[(LitId, int32)]
    methods*: seq[(LitId, PackedItemId, int32)]
    macroUsages*: seq[(PackedItemId, PackedLineInfo)]
    sh*: Shared
    cfg: PackedConfig

  PackedEncoder* = object
    #m*: PackedModule
    thisModule*: int32
    lastFile*: FileIndex # remember the last lookup entry.
    lastLit*: LitId
    filenames*: Table[FileIndex, LitId]
    pendingTypes*: seq[PType]
    pendingSyms*: seq[PSym]
    typeMarker*: IntSet #Table[ItemId, TypeId]  # ItemId.item -> TypeId
    symMarker*: IntSet #Table[ItemId, SymId]    # ItemId.item -> SymId
    config*: ConfigRef

template primConfigFields(fn: untyped) {.dirty.} =
  fn backend
  fn selectedGC
  fn cCompiler
  fn options
  fn globalOptions

proc definedSymbolsAsString(config: ConfigRef): string =
  result = newStringOfCap(200)
  result.add "config"
  for d in definedSymbolNames(config.symbols):
    result.add ' '
    result.add d

proc rememberConfig(c: var PackedEncoder; m: var PackedModule; config: ConfigRef; pc: PackedConfig) =
  m.definedSymbols = definedSymbolsAsString(config)
  #template rem(x) =
  #  c.m.cfg.x = config.x
  #primConfigFields rem
  m.cfg = pc

proc configIdentical(m: PackedModule; config: ConfigRef): bool =
  result = m.definedSymbols == definedSymbolsAsString(config)
  #if not result:
  #  echo "A ", m.definedSymbols, " ", definedSymbolsAsString(config)
  template eq(x) =
    result = result and m.cfg.x == config.x
    #if not result:
    #  echo "B ", m.cfg.x, " ", config.x
  primConfigFields eq

proc rememberStartupConfig*(dest: var PackedConfig, config: ConfigRef) =
  template rem(x) =
    dest.x = config.x
  primConfigFields rem

proc hashFileCached(conf: ConfigRef; fileIdx: FileIndex): string =
  result = msgs.getHash(conf, fileIdx)
  if result.len == 0:
    let fullpath = msgs.toFullPath(conf, fileIdx)
    result = $secureHashFile(fullpath)
    msgs.setHash(conf, fileIdx, result)

proc toLitId(x: FileIndex; c: var PackedEncoder; m: var PackedModule): LitId =
  ## store a file index as a literal
  if x == c.lastFile:
    result = c.lastLit
  else:
    result = c.filenames.getOrDefault(x)
    if result == LitId(0):
      let p = msgs.toFullPath(c.config, x)
      result = getOrIncl(m.sh.strings, p)
      c.filenames[x] = result
    c.lastFile = x
    c.lastLit = result
    assert result != LitId(0)

proc toFileIndex(x: LitId; m: PackedModule; config: ConfigRef): FileIndex =
  result = msgs.fileInfoIdx(config, AbsoluteFile m.sh.strings[x])

proc includesIdentical(m: var PackedModule; config: ConfigRef): bool =
  for it in mitems(m.includes):
    if hashFileCached(config, toFileIndex(it[0], m, config)) != it[1]:
      return false
  result = true

proc initEncoder*(c: var PackedEncoder; m: var PackedModule; moduleSym: PSym; config: ConfigRef; pc: PackedConfig) =
  ## setup a context for serializing to packed ast
  m.sh = Shared()
  c.thisModule = moduleSym.itemId.module
  c.config = config
  m.bodies = newTreeFrom(m.topLevel)
  m.toReplay = newTreeFrom(m.topLevel)

  let thisNimFile = FileIndex c.thisModule
  var h = msgs.getHash(config, thisNimFile)
  if h.len == 0:
    let fullpath = msgs.toFullPath(config, thisNimFile)
    if isAbsolute(fullpath):
      # For NimScript compiler API support the main Nim file might be from a stream.
      h = $secureHashFile(fullpath)
      msgs.setHash(config, thisNimFile, h)
  m.includes.add((toLitId(thisNimFile, c, m), h)) # the module itself

  rememberConfig(c, m, config, pc)

proc addIncludeFileDep*(c: var PackedEncoder; m: var PackedModule; f: FileIndex) =
  m.includes.add((toLitId(f, c, m), hashFileCached(c.config, f)))

proc addImportFileDep*(c: var PackedEncoder; m: var PackedModule; f: FileIndex) =
  m.imports.add toLitId(f, c, m)

proc addExported*(c: var PackedEncoder; m: var PackedModule; s: PSym) =
  let nameId = getOrIncl(m.sh.strings, s.name.s)
  m.exports.add((nameId, s.itemId.item))

proc addConverter*(c: var PackedEncoder; m: var PackedModule; s: PSym) =
  let nameId = getOrIncl(m.sh.strings, s.name.s)
  m.converters.add((nameId, s.itemId.item))

proc addTrmacro*(c: var PackedEncoder; m: var PackedModule; s: PSym) =
  let nameId = getOrIncl(m.sh.strings, s.name.s)
  m.trmacros.add((nameId, s.itemId.item))

proc addPureEnum*(c: var PackedEncoder; m: var PackedModule; s: PSym) =
  let nameId = getOrIncl(m.sh.strings, s.name.s)
  assert s.kind == skType
  m.pureEnums.add((nameId, s.itemId.item))

proc addMethod*(c: var PackedEncoder; m: var PackedModule; s: PSym) =
  let nameId = getOrIncl(m.sh.strings, s.name.s)
  discard "to do"
  # c.m.methods.add((nameId, s.itemId.item))

proc addReexport*(c: var PackedEncoder; m: var PackedModule; s: PSym) =
  let nameId = getOrIncl(m.sh.strings, s.name.s)
  m.reexports.add((nameId, PackedItemId(module: toLitId(s.itemId.module.FileIndex, c, m),
                                        item: s.itemId.item)))

proc addCompilerProc*(c: var PackedEncoder; m: var PackedModule; s: PSym) =
  let nameId = getOrIncl(m.sh.strings, s.name.s)
  m.compilerProcs.add((nameId, s.itemId.item))

proc toPackedNode*(n: PNode; ir: var PackedTree; c: var PackedEncoder; m: var PackedModule)
proc toPackedSym*(s: PSym; c: var PackedEncoder; m: var PackedModule): PackedItemId
proc toPackedType(t: PType; c: var PackedEncoder; m: var PackedModule): PackedItemId

proc flush(c: var PackedEncoder; m: var PackedModule) =
  ## serialize any pending types or symbols from the context
  while true:
    if c.pendingTypes.len > 0:
      discard toPackedType(c.pendingTypes.pop, c, m)
    elif c.pendingSyms.len > 0:
      discard toPackedSym(c.pendingSyms.pop, c, m)
    else:
      break

proc toLitId(x: string; m: var PackedModule): LitId =
  ## store a string as a literal
  result = getOrIncl(m.sh.strings, x)

proc toLitId(x: BiggestInt; m: var PackedModule): LitId =
  ## store an integer as a literal
  result = getOrIncl(m.sh.integers, x)

proc toPackedInfo(x: TLineInfo; c: var PackedEncoder; m: var PackedModule): PackedLineInfo =
  PackedLineInfo(line: x.line, col: x.col, file: toLitId(x.fileIndex, c, m))

proc safeItemId(s: PSym; c: var PackedEncoder; m: var PackedModule): PackedItemId {.inline.} =
  ## given a symbol, produce an ItemId with the correct properties
  ## for local or remote symbols, packing the symbol as necessary
  if s == nil:
    result = nilItemId
  elif s.itemId.module == c.thisModule:
    result = PackedItemId(module: LitId(0), item: s.itemId.item)
  else:
    result = PackedItemId(module: toLitId(s.itemId.module.FileIndex, c, m),
                          item: s.itemId.item)

proc addModuleRef(n: PNode; ir: var PackedTree; c: var PackedEncoder; m: var PackedModule) =
  ## add a remote symbol reference to the tree
  let info = n.info.toPackedInfo(c, m)
  ir.nodes.add PackedNode(kind: nkModuleRef, operand: 2.int32,  # 2 kids...
                          typeId: toPackedType(n.typ, c, m), info: info)
  ir.nodes.add PackedNode(kind: nkInt32Lit, info: info,
                          operand: toLitId(n.sym.itemId.module.FileIndex, c, m).int32)
  ir.nodes.add PackedNode(kind: nkInt32Lit, info: info,
                          operand: n.sym.itemId.item)

proc addMissing(c: var PackedEncoder; p: PSym) =
  ## consider queuing a symbol for later addition to the packed tree
  if p != nil and p.itemId.module == c.thisModule:
    if p.itemId.item notin c.symMarker:
      c.pendingSyms.add p

proc addMissing(c: var PackedEncoder; p: PType) =
  ## consider queuing a type for later addition to the packed tree
  if p != nil and p.uniqueId.module == c.thisModule:
    if p.uniqueId.item notin c.typeMarker:
      c.pendingTypes.add p

template storeNode(dest, src, field) =
  var nodeId: NodeId
  if src.field != nil:
    nodeId = getNodeId(m.bodies)
    toPackedNode(src.field, m.bodies, c, m)
  else:
    nodeId = emptyNodeId
  dest.field = nodeId

proc toPackedType(t: PType; c: var PackedEncoder; m: var PackedModule): PackedItemId =
  ## serialize a ptype
  if t.isNil: return nilItemId

  if t.uniqueId.module != c.thisModule:
    # XXX Assert here that it already was serialized in the foreign module!
    # it is a foreign type:
    return PackedItemId(module: toLitId(t.uniqueId.module.FileIndex, c, m), item: t.uniqueId.item)

  if not c.typeMarker.containsOrIncl(t.uniqueId.item):
    if t.uniqueId.item >= m.sh.types.len:
      setLen m.sh.types, t.uniqueId.item+1

    var p = PackedType(kind: t.kind, flags: t.flags, callConv: t.callConv,
      size: t.size, align: t.align, nonUniqueId: t.itemId.item,
      paddingAtEnd: t.paddingAtEnd, lockLevel: t.lockLevel)
    storeNode(p, t, n)

    for op, s in pairs t.attachedOps:
      c.addMissing s
      p.attachedOps[op] = s.safeItemId(c, m)

    p.typeInst = t.typeInst.toPackedType(c, m)
    for kid in items t.sons:
      p.types.add kid.toPackedType(c, m)
    for i, s in items t.methods:
      c.addMissing s
      p.methods.add (i, s.safeItemId(c, m))
    c.addMissing t.sym
    p.sym = t.sym.safeItemId(c, m)
    c.addMissing t.owner
    p.owner = t.owner.safeItemId(c, m)

    # fill the reserved slot, nothing else:
    m.sh.types[t.uniqueId.item] = p

  result = PackedItemId(module: LitId(0), item: t.uniqueId.item)

proc toPackedLib(l: PLib; c: var PackedEncoder; m: var PackedModule): PackedLib =
  ## the plib hangs off the psym via the .annex field
  if l.isNil: return
  result.kind = l.kind
  result.generated = l.generated
  result.isOverriden = l.isOverriden
  result.name = toLitId($l.name, m)
  storeNode(result, l, path)

proc toPackedSym*(s: PSym; c: var PackedEncoder; m: var PackedModule): PackedItemId =
  ## serialize a psym
  if s.isNil: return nilItemId

  if s.itemId.module != c.thisModule:
    # XXX Assert here that it already was serialized in the foreign module!
    # it is a foreign symbol:
    return PackedItemId(module: toLitId(s.itemId.module.FileIndex, c, m), item: s.itemId.item)

  if not c.symMarker.containsOrIncl(s.itemId.item):
    if s.itemId.item >= m.sh.syms.len:
      setLen m.sh.syms, s.itemId.item+1

    var p = PackedSym(kind: s.kind, flags: s.flags, info: s.info.toPackedInfo(c, m), magic: s.magic,
      position: s.position, offset: s.offset, options: s.options,
      name: s.name.s.toLitId(m))

    storeNode(p, s, ast)
    storeNode(p, s, constraint)

    if s.kind in {skLet, skVar, skField, skForVar}:
      c.addMissing s.guard
      p.guard = s.guard.safeItemId(c, m)
      p.bitsize = s.bitsize
      p.alignment = s.alignment

    p.externalName = toLitId(if s.loc.r.isNil: "" else: $s.loc.r, m)
    c.addMissing s.typ
    p.typ = s.typ.toPackedType(c, m)
    c.addMissing s.owner
    p.owner = s.owner.safeItemId(c, m)
    p.annex = toPackedLib(s.annex, c, m)
    when hasFFI:
      p.cname = toLitId(s.cname, m)

    # fill the reserved slot, nothing else:
    m.sh.syms[s.itemId.item] = p

  result = PackedItemId(module: LitId(0), item: s.itemId.item)

proc toSymNode(n: PNode; ir: var PackedTree; c: var PackedEncoder; m: var PackedModule) =
  ## store a local or remote psym reference in the tree
  assert n.kind == nkSym
  template s: PSym = n.sym
  let id = s.toPackedSym(c, m).item
  if s.itemId.module == c.thisModule:
    # it is a symbol that belongs to the module we're currently
    # packing:
    ir.addSym(id, toPackedInfo(n.info, c, m))
  else:
    # store it as an external module reference:
    addModuleRef(n, ir, c, m)

proc toPackedNode*(n: PNode; ir: var PackedTree; c: var PackedEncoder; m: var PackedModule) =
  ## serialize a node into the tree
  if n.isNil: return
  let info = toPackedInfo(n.info, c, m)
  case n.kind
  of nkNone, nkEmpty, nkNilLit, nkType:
    ir.nodes.add PackedNode(kind: n.kind, flags: n.flags, operand: 0,
                            typeId: toPackedType(n.typ, c, m), info: info)
  of nkIdent:
    ir.nodes.add PackedNode(kind: n.kind, flags: n.flags,
                            operand: int32 getOrIncl(m.sh.strings, n.ident.s),
                            typeId: toPackedType(n.typ, c, m), info: info)
  of nkSym:
    toSymNode(n, ir, c, m)
  of directIntLit:
    ir.nodes.add PackedNode(kind: n.kind, flags: n.flags,
                            operand: int32(n.intVal),
                            typeId: toPackedType(n.typ, c, m), info: info)
  of externIntLit:
    ir.nodes.add PackedNode(kind: n.kind, flags: n.flags,
                            operand: int32 getOrIncl(m.sh.integers, n.intVal),
                            typeId: toPackedType(n.typ, c, m), info: info)
  of nkStrLit..nkTripleStrLit:
    ir.nodes.add PackedNode(kind: n.kind, flags: n.flags,
                            operand: int32 getOrIncl(m.sh.strings, n.strVal),
                            typeId: toPackedType(n.typ, c, m), info: info)
  of nkFloatLit..nkFloat128Lit:
    ir.nodes.add PackedNode(kind: n.kind, flags: n.flags,
                            operand: int32 getOrIncl(m.sh.floats, n.floatVal),
                            typeId: toPackedType(n.typ, c, m), info: info)
  else:
    let patchPos = ir.prepare(n.kind, n.flags,
                              toPackedType(n.typ, c, m), info)
    for i in 0..<n.len:
      toPackedNode(n[i], ir, c, m)
    ir.patch patchPos

  when false:
    ir.flush c   # flush any pending types and symbols

proc addPragmaComputation*(c: var PackedEncoder; m: var PackedModule; n: PNode) =
  toPackedNode(n, m.toReplay, c, m)

proc toPackedNodeIgnoreProcDefs*(n: PNode, encoder: var PackedEncoder; m: var PackedModule) =
  case n.kind
  of routineDefs:
    # we serialize n[namePos].sym instead
    if n[namePos].kind == nkSym:
      discard toPackedSym(n[namePos].sym, encoder, m)
    else:
      toPackedNode(n, m.topLevel, encoder, m)
  else:
    toPackedNode(n, m.topLevel, encoder, m)

proc toPackedNodeTopLevel*(n: PNode, encoder: var PackedEncoder; m: var PackedModule) =
  toPackedNodeIgnoreProcDefs(n, encoder, m)
  flush encoder, m

proc storePrim*(f: var RodFile; x: PackedType) =
  for y in fields(x):
    when y is seq:
      storeSeq(f, y)
    else:
      storePrim(f, y)

proc loadPrim*(f: var RodFile; x: var PackedType) =
  for y in fields(x):
    when y is seq:
      loadSeq(f, y)
    else:
      loadPrim(f, y)

proc loadError(err: RodFileError; filename: AbsoluteFile) =
  echo "Error: ", $err, "\nloading file: ", filename.string

proc loadRodFile*(filename: AbsoluteFile; m: var PackedModule; config: ConfigRef): RodFileError =
  m.sh = Shared()
  var f = rodfiles.open(filename.string)
  f.loadHeader()
  f.loadSection configSection

  f.loadPrim m.definedSymbols
  f.loadPrim m.cfg

  if f.err == ok and not configIdentical(m, config):
    f.err = configMismatch

  template loadSeqSection(section, data) {.dirty.} =
    f.loadSection section
    f.loadSeq data

  template loadTabSection(section, data) {.dirty.} =
    f.loadSection section
    f.load data

  loadTabSection stringsSection, m.sh.strings

  loadSeqSection checkSumsSection, m.includes
  if not includesIdentical(m, config):
    f.err = includeFileChanged

  loadSeqSection depsSection, m.imports

  loadTabSection integersSection, m.sh.integers
  loadTabSection floatsSection, m.sh.floats

  loadSeqSection exportsSection, m.exports

  loadSeqSection reexportsSection, m.reexports

  loadSeqSection compilerProcsSection, m.compilerProcs

  loadSeqSection trmacrosSection, m.trmacros

  loadSeqSection convertersSection, m.converters
  loadSeqSection methodsSection, m.methods
  loadSeqSection pureEnumsSection, m.pureEnums
  loadSeqSection macroUsagesSection, m.macroUsages

  loadSeqSection toReplaySection, m.toReplay.nodes
  loadSeqSection topLevelSection, m.topLevel.nodes
  loadSeqSection bodiesSection, m.bodies.nodes
  loadSeqSection symsSection, m.sh.syms
  loadSeqSection typesSection, m.sh.types

  close(f)
  result = f.err

# -------------------------------------------------------------------------

proc storeError(err: RodFileError; filename: AbsoluteFile) =
  echo "Error: ", $err, "; couldn't write to ", filename.string
  removeFile(filename.string)

proc saveRodFile*(filename: AbsoluteFile; encoder: var PackedEncoder; m: var PackedModule) =
  #rememberConfig(encoder, encoder.config)

  var f = rodfiles.create(filename.string)
  f.storeHeader()
  f.storeSection configSection
  f.storePrim m.definedSymbols
  f.storePrim m.cfg

  template storeSeqSection(section, data) {.dirty.} =
    f.storeSection section
    f.storeSeq data

  template storeTabSection(section, data) {.dirty.} =
    f.storeSection section
    f.store data

  storeTabSection stringsSection, m.sh.strings

  storeSeqSection checkSumsSection, m.includes

  storeSeqSection depsSection, m.imports

  storeTabSection integersSection, m.sh.integers
  storeTabSection floatsSection, m.sh.floats

  storeSeqSection exportsSection, m.exports

  storeSeqSection reexportsSection, m.reexports

  storeSeqSection compilerProcsSection, m.compilerProcs

  storeSeqSection trmacrosSection, m.trmacros
  storeSeqSection convertersSection, m.converters
  storeSeqSection methodsSection, m.methods
  storeSeqSection pureEnumsSection, m.pureEnums
  storeSeqSection macroUsagesSection, m.macroUsages

  storeSeqSection toReplaySection, m.toReplay.nodes
  storeSeqSection topLevelSection, m.topLevel.nodes

  storeSeqSection bodiesSection, m.bodies.nodes
  storeSeqSection symsSection, m.sh.syms

  storeSeqSection typesSection, m.sh.types
  close(f)
  if f.err != ok:
    storeError(f.err, filename)

  when false:
    # basic loader testing:
    var m2: PackedModule
    discard loadRodFile(filename, m2, encoder.config)
    echo "loaded ", filename.string

# ----------------------------------------------------------------------------

type
  PackedDecoder* = object
    thisModule*: int32
    lastLit*: LitId
    lastFile*: FileIndex # remember the last lookup entry.
    config*: ConfigRef
    cache: IdentCache

type
  ModuleStatus* = enum
    undefined,
    storing,
    loading,
    loaded,
    outdated

  LoadedModule* = object
    status*: ModuleStatus
    symsInit, typesInit: bool
    fromDisk*: PackedModule
    syms: seq[PSym] # indexed by itemId
    types: seq[PType]
    module*: PSym # the one true module symbol.
    iface: Table[PIdent, seq[PackedItemId]] # PackedItemId so that it works with reexported symbols too

  PackedModuleGraph* = seq[LoadedModule] # indexed by FileIndex

proc loadType(c: var PackedDecoder; g: var PackedModuleGraph; t: PackedItemId): PType
proc loadSym(c: var PackedDecoder; g: var PackedModuleGraph; s: PackedItemId): PSym

proc toFileIndexCached(c: var PackedDecoder; g: var PackedModuleGraph; f: LitId): FileIndex =
  if c.lastLit == f:
    result = c.lastFile
  else:
    result = toFileIndex(f, g[c.thisModule].fromDisk, c.config)
    c.lastLit = f
    c.lastFile = result

proc translateLineInfo(c: var PackedDecoder; g: var PackedModuleGraph;
                       x: PackedLineInfo): TLineInfo =
  assert g[c.thisModule].status == loaded
  result = TLineInfo(line: x.line, col: x.col,
            fileIndex: toFileIndexCached(c, g, x.file))

proc loadNodes(c: var PackedDecoder; g: var PackedModuleGraph;
               tree: PackedTree; n: NodePos): PNode =
  let k = n.kind
  result = newNodeIT(k, translateLineInfo(c, g, n.info),
    loadType(c, g, n.typ))
  result.flags = n.flags

  case k
  of nkEmpty, nkNilLit, nkType:
    discard
  of nkIdent:
    result.ident = getIdent(c.cache, g[c.thisModule].fromDisk.sh.strings[n.litId])
  of nkSym:
    result.sym = loadSym(c, g, PackedItemId(module: LitId(0), item: tree.nodes[n.int].operand))
  of directIntLit:
    result.intVal = tree.nodes[n.int].operand
  of externIntLit:
    result.intVal = g[c.thisModule].fromDisk.sh.integers[n.litId]
  of nkStrLit..nkTripleStrLit:
    result.strVal = g[c.thisModule].fromDisk.sh.strings[n.litId]
  of nkFloatLit..nkFloat128Lit:
    result.floatVal = g[c.thisModule].fromDisk.sh.floats[n.litId]
  of nkModuleRef:
    let (n1, n2) = sons2(tree, n)
    assert n1.kind == nkInt32Lit
    assert n2.kind == nkInt32Lit
    transitionNoneToSym(result)
    result.sym = loadSym(c, g, PackedItemId(module: n1.litId, item: tree.nodes[n2.int].operand))
  else:
    for n0 in sonsReadonly(tree, n):
      result.add loadNodes(c, g, tree, n0)

proc loadProcHeader(c: var PackedDecoder; g: var PackedModuleGraph;
                    tree: PackedTree; n: NodePos): PNode =
  # do not load the body of the proc. This will be done later in
  # getProcBody, if required.
  let k = n.kind
  result = newNodeIT(k, translateLineInfo(c, g, n.info),
    loadType(c, g, n.typ))
  result.flags = n.flags
  assert k in {nkProcDef, nkMethodDef, nkIteratorDef, nkFuncDef, nkConverterDef}
  var i = 0
  for n0 in sonsReadonly(tree, n):
    if i != bodyPos:
      result.add loadNodes(c, g, tree, n0)
    else:
      result.add nil
    inc i

proc loadProcBody(c: var PackedDecoder; g: var PackedModuleGraph;
                  tree: PackedTree; n: NodePos): PNode =
  var i = 0
  for n0 in sonsReadonly(tree, n):
    if i == bodyPos:
      result = loadNodes(c, g, tree, n0)
    inc i

proc moduleIndex*(c: var PackedDecoder; g: var PackedModuleGraph;
                  s: PackedItemId): int32 {.inline.} =
  result = if s.module == LitId(0): c.thisModule
           else: toFileIndexCached(c, g, s.module).int32

proc symHeaderFromPacked(c: var PackedDecoder; g: var PackedModuleGraph;
                         s: PackedSym; si, item: int32): PSym =
  result = PSym(itemId: ItemId(module: si, item: item),
    kind: s.kind, magic: s.magic, flags: s.flags,
    info: translateLineInfo(c, g, s.info),
    options: s.options,
    position: s.position,
    name: getIdent(c.cache, g[si].fromDisk.sh.strings[s.name])
  )

template loadAstBody(p, field) =
  if p.field != emptyNodeId:
    result.field = loadNodes(c, g, g[si].fromDisk.bodies, NodePos p.field)

template loadAstBodyLazy(p, field) =
  if p.field != emptyNodeId:
    result.field = loadProcHeader(c, g, g[si].fromDisk.bodies, NodePos p.field)

proc loadLib(c: var PackedDecoder; g: var PackedModuleGraph;
             si, item: int32; l: PackedLib): PLib =
  # XXX: hack; assume a zero LitId means the PackedLib is all zero (empty)
  if l.name.int == 0:
    result = nil
  else:
    result = PLib(generated: l.generated, isOverriden: l.isOverriden,
                  kind: l.kind, name: rope g[si].fromDisk.sh.strings[l.name])
    loadAstBody(l, path)

proc symBodyFromPacked(c: var PackedDecoder; g: var PackedModuleGraph;
                       s: PackedSym; si, item: int32; result: PSym) =
  result.typ = loadType(c, g, s.typ)
  loadAstBody(s, constraint)
  if result.kind in {skProc, skFunc, skIterator, skConverter, skMethod}:
    loadAstBodyLazy(s, ast)
  else:
    loadAstBody(s, ast)
  result.annex = loadLib(c, g, si, item, s.annex)
  when hasFFI:
    result.cname = g[si].fromDisk.sh.strings[s.cname]

  if s.kind in {skLet, skVar, skField, skForVar}:
    result.guard = loadSym(c, g, s.guard)
    result.bitsize = s.bitsize
    result.alignment = s.alignment
  result.owner = loadSym(c, g, s.owner)
  let externalName = g[si].fromDisk.sh.strings[s.externalName]
  if externalName != "":
    result.loc.r = rope externalName

proc loadSym(c: var PackedDecoder; g: var PackedModuleGraph; s: PackedItemId): PSym =
  if s == nilItemId:
    result = nil
  else:
    let si = moduleIndex(c, g, s)
    assert g[si].status == loaded
    if not g[si].symsInit:
      g[si].symsInit = true
      setLen g[si].syms, g[si].fromDisk.sh.syms.len

    if g[si].syms[s.item] == nil:
      let packed = addr(g[si].fromDisk.sh.syms[s.item])

      if packed.kind != skModule:
        result = symHeaderFromPacked(c, g, packed[], si, s.item)
        # store it here early on, so that recursions work properly:
        g[si].syms[s.item] = result
        symBodyFromPacked(c, g, packed[], si, s.item, result)
      else:
        result = g[si].module
        assert result != nil

    else:
      result = g[si].syms[s.item]

proc typeHeaderFromPacked(c: var PackedDecoder; g: var PackedModuleGraph;
                          t: PackedType; si, item: int32): PType =
  result = PType(itemId: ItemId(module: si, item: t.nonUniqueId), kind: t.kind,
                flags: t.flags, size: t.size, align: t.align,
                paddingAtEnd: t.paddingAtEnd, lockLevel: t.lockLevel,
                uniqueId: ItemId(module: si, item: item))

proc typeBodyFromPacked(c: var PackedDecoder; g: var PackedModuleGraph;
                        t: PackedType; si, item: int32; result: PType) =
  result.sym = loadSym(c, g, t.sym)
  result.owner = loadSym(c, g, t.owner)
  for op, item in pairs t.attachedOps:
    result.attachedOps[op] = loadSym(c, g, item)
  result.typeInst = loadType(c, g, t.typeInst)
  for son in items t.types:
    result.sons.add loadType(c, g, son)
  loadAstBody(t, n)
  for gen, id in items t.methods:
    result.methods.add((gen, loadSym(c, g, id)))

proc loadType(c: var PackedDecoder; g: var PackedModuleGraph; t: PackedItemId): PType =
  if t == nilItemId:
    result = nil
  else:
    let si = moduleIndex(c, g, t)
    assert g[si].status == loaded
    if not g[si].typesInit:
      g[si].typesInit = true
      setLen g[si].types, g[si].fromDisk.sh.types.len

    if g[si].types[t.item] == nil:
      let packed = addr(g[si].fromDisk.sh.types[t.item])
      result = typeHeaderFromPacked(c, g, packed[], si, t.item)
      # store it here early on, so that recursions work properly:
      g[si].types[t.item] = result
      typeBodyFromPacked(c, g, packed[], si, t.item, result)
    else:
      result = g[si].types[t.item]

proc setupLookupTables(g: var PackedModuleGraph; conf: ConfigRef; cache: IdentCache;
                       fileIdx: FileIndex; m: var LoadedModule) =
  m.iface = initTable[PIdent, seq[PackedItemId]]()
  for e in m.fromDisk.exports:
    let nameLit = e[0]
    m.iface.mgetOrPut(cache.getIdent(m.fromDisk.sh.strings[nameLit]), @[]).add(PackedItemId(module: LitId(0), item: e[1]))
  for re in m.fromDisk.reexports:
    let nameLit = re[0]
    m.iface.mgetOrPut(cache.getIdent(m.fromDisk.sh.strings[nameLit]), @[]).add(re[1])

  let filename = AbsoluteFile toFullPath(conf, fileIdx)
  # We cannot call ``newSym`` here, because we have to circumvent the ID
  # mechanism, which we do in order to assign each module a persistent ID.
  m.module = PSym(kind: skModule, itemId: ItemId(module: int32(fileIdx), item: 0'i32),
                  name: getIdent(cache, splitFile(filename).name),
                  info: newLineInfo(fileIdx, 1, 1),
                  position: int(fileIdx))

proc loadToReplayNodes(g: var PackedModuleGraph; conf: ConfigRef; cache: IdentCache;
                       fileIdx: FileIndex; m: var LoadedModule) =
  m.module.ast = newNode(nkStmtList)
  if m.fromDisk.toReplay.len > 0:
    var decoder = PackedDecoder(
      thisModule: int32(fileIdx),
      lastLit: LitId(0),
      lastFile: FileIndex(-1),
      config: conf,
      cache: cache)
    var p = 0
    while p < m.fromDisk.toReplay.len:
      m.module.ast.add loadNodes(decoder, g, m.fromDisk.toReplay, NodePos p)
      let s = span(m.fromDisk.toReplay, p)
      inc p, s

proc needsRecompile(g: var PackedModuleGraph; conf: ConfigRef; cache: IdentCache;
                    fileIdx: FileIndex): bool =
  let m = int(fileIdx)
  if m >= g.len:
    g.setLen(m+1)

  case g[m].status
  of undefined:
    g[m].status = loading
    let fullpath = msgs.toFullPath(conf, fileIdx)
    let rod = toRodFile(conf, AbsoluteFile fullpath)
    let err = loadRodFile(rod, g[m].fromDisk, conf)
    if err == ok:
      result = false
      # check its dependencies:
      for dep in g[m].fromDisk.imports:
        let fid = toFileIndex(dep, g[m].fromDisk, conf)
        # Warning: we need to traverse the full graph, so
        # do **not use break here**!
        if needsRecompile(g, conf, cache, fid):
          result = true

      if not result:
        setupLookupTables(g, conf, cache, fileIdx, g[m])
      g[m].status = if result: outdated else: loaded
    else:
      loadError(err, rod)
      g[m].status = outdated
      result = true
  of loading, loaded:
    result = false
  of outdated, storing:
    result = true

proc moduleFromRodFile*(g: var PackedModuleGraph; conf: ConfigRef; cache: IdentCache;
                        fileIdx: FileIndex): PSym =
  ## Returns 'nil' if the module needs to be recompiled.
  if needsRecompile(g, conf, cache, fileIdx):
    result = nil
  else:
    result = g[int fileIdx].module
    assert result != nil
    loadToReplayNodes(g, conf, cache, fileIdx, g[int fileIdx])

template setupDecoder() {.dirty.} =
  var decoder = PackedDecoder(
    thisModule: int32(module),
    lastLit: LitId(0),
    lastFile: FileIndex(-1),
    config: config,
    cache: cache)

proc loadProcBody*(config: ConfigRef, cache: IdentCache;
                   g: var PackedModuleGraph; s: PSym): PNode =
  let mId = s.itemId.module
  var decoder = PackedDecoder(
    thisModule: mId,
    lastLit: LitId(0),
    lastFile: FileIndex(-1),
    config: config,
    cache: cache)
  let pos = g[mId].fromDisk.sh.syms[s.itemId.item].ast
  assert pos != emptyNodeId
  result = loadProcBody(decoder, g, g[mId].fromDisk.bodies, NodePos pos)

proc simulateLoadedModule*(g: var PackedModuleGraph; conf: ConfigRef; cache: IdentCache;
                           moduleSym: PSym; m: PackedModule) =
  # For now only used for heavy debugging. In the future we could use this to reduce the
  # compiler's memory consumption.
  let idx = moduleSym.position
  assert g[idx].status in {storing}
  g[idx].status = loaded
  assert g[idx].module == moduleSym
  setupLookupTables(g, conf, cache, FileIndex(idx), g[idx])
  loadToReplayNodes(g, conf, cache, FileIndex(idx), g[idx])

# ---------------- symbol table handling ----------------

type
  RodIter* = object
    decoder: PackedDecoder
    values: seq[PackedItemId]
    i: int

proc initRodIter*(it: var RodIter; config: ConfigRef, cache: IdentCache;
                  g: var PackedModuleGraph; module: FileIndex;
                  name: PIdent): PSym =
  it.decoder = PackedDecoder(
    thisModule: int32(module),
    lastLit: LitId(0),
    lastFile: FileIndex(-1),
    config: config,
    cache: cache)
  it.values = g[int module].iface.getOrDefault(name)
  it.i = 0
  if it.i < it.values.len:
    result = loadSym(it.decoder, g, it.values[it.i])
    inc it.i

proc initRodIterAllSyms*(it: var RodIter; config: ConfigRef, cache: IdentCache;
                         g: var PackedModuleGraph; module: FileIndex): PSym =
  it.decoder = PackedDecoder(
    thisModule: int32(module),
    lastLit: LitId(0),
    lastFile: FileIndex(-1),
    config: config,
    cache: cache)
  it.values = @[]
  for v in g[int module].iface.values:
    it.values.add v
  it.i = 0
  if it.i < it.values.len:
    result = loadSym(it.decoder, g, it.values[it.i])
    inc it.i

proc nextRodIter*(it: var RodIter; g: var PackedModuleGraph): PSym =
  if it.i < it.values.len:
    result = loadSym(it.decoder, g, it.values[it.i])
    inc it.i

iterator interfaceSymbols*(config: ConfigRef, cache: IdentCache;
                           g: var PackedModuleGraph; module: FileIndex;
                           name: PIdent): PSym =
  setupDecoder()
  let values = g[int module].iface.getOrDefault(name)
  for pid in values:
    let s = loadSym(decoder, g, pid)
    assert s != nil
    yield s

proc interfaceSymbol*(config: ConfigRef, cache: IdentCache;
                      g: var PackedModuleGraph; module: FileIndex;
                      name: PIdent): PSym =
  setupDecoder()
  let values = g[int module].iface.getOrDefault(name)
  result = loadSym(decoder, g, values[0])

# ------------------------- .rod file viewer ---------------------------------

proc rodViewer*(rodfile: AbsoluteFile; config: ConfigRef, cache: IdentCache) =
  var m: PackedModule
  if loadRodFile(rodfile, m, config) != ok:
    echo "Error: could not load: ", rodfile.string
    quit 1

  when true:
    echo "exports:"
    for ex in m.exports:
      echo "  ", m.sh.strings[ex[0]]
      assert ex[0] == m.sh.syms[ex[1]].name
      # ex[1] int32

    echo "reexports:"
    for ex in m.reexports:
      echo "  ", m.sh.strings[ex[0]]
    #  reexports*: seq[(LitId, PackedItemId)]
  echo "symbols: ", m.sh.syms.len, " types: ", m.sh.types.len,
    " top level nodes: ", m.topLevel.nodes.len, " other nodes: ", m.bodies.nodes.len,
    " strings: ", m.sh.strings.len, " integers: ", m.sh.integers.len,
    " floats: ", m.sh.floats.len

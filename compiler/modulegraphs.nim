#
#
#           The Nim Compiler
#        (c) Copyright 2017 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements the module graph data structure. The module graph
## represents a complete Nim project. Single modules can either be kept in RAM
## or stored in a rod-file.

import std/[intsets, tables, hashes, strtabs, algorithm, os, strutils, parseutils]
import ../dist/checksums/src/checksums/md5
import ast, astalgo, options, lineinfos,idents, btrees, ropes, msgs, pathutils, packages, suggestsymdb
import ic / [packed_ast, ic]


when defined(nimPreviewSlimSystem):
  import std/assertions

type
  SigHash* = distinct MD5Digest

  LazySym* = object
    id*: FullId
    sym*: PSym

  Iface* = object       ## data we don't want to store directly in the
                        ## ast.PSym type for s.kind == skModule
    module*: PSym       ## module this "Iface" belongs to
    converters*: seq[LazySym]
    patterns*: seq[LazySym]
    pureEnums*: seq[LazySym]
    interf: TStrTable
    interfHidden: TStrTable
    uniqueName*: Rope

  Operators* = object
    opNot*, opContains*, opLe*, opLt*, opAnd*, opOr*, opIsNil*, opEq*: PSym
    opAdd*, opSub*, opMul*, opDiv*, opLen*: PSym

  FullId* = object
    module*: int
    packed*: PackedItemId

  LazyType* = object
    id*: FullId
    typ*: PType

  LazyInstantiation* = object
    module*: int
    sym*: FullId
    concreteTypes*: seq[FullId]
    inst*: PInstantiation

  PipelinePass* = enum
    NonePass
    SemPass
    JSgenPass
    CgenPass
    EvalPass
    InterpreterPass
    GenDependPass
    Docgen2TexPass
    Docgen2JsonPass
    Docgen2Pass

  ModuleGraph* {.acyclic.} = ref object
    ifaces*: seq[Iface]  ## indexed by int32 fileIdx
    packed*: PackedModuleGraph
    encoders*: seq[PackedEncoder]

    typeInstCache*: Table[ItemId, seq[LazyType]] # A symbol's ItemId.
    procInstCache*: Table[ItemId, seq[LazyInstantiation]] # A symbol's ItemId.
    attachedOps*: array[TTypeAttachedOp, Table[ItemId, LazySym]] # Type ID, destructors, etc.
    methodsPerGenericType*: Table[ItemId, seq[(int, LazySym)]] # Type ID, attached methods
    memberProcsPerType*: Table[ItemId, seq[PSym]] # Type ID, attached member procs (only c++, virtual,member and ctor so far).
    initializersPerType*: Table[ItemId, PNode] # Type ID, AST call to the default ctor (c++ only)
    enumToStringProcs*: Table[ItemId, LazySym]
    emittedTypeInfo*: Table[string, FileIndex]

    startupPackedConfig*: PackedConfig
    packageSyms*: TStrTable
    deps*: IntSet # the dependency graph or potentially its transitive closure.
    importDeps*: Table[FileIndex, seq[FileIndex]] # explicit import module dependencies
    suggestMode*: bool # whether we are in nimsuggest mode or not.
    invalidTransitiveClosure: bool
    interactive*: bool
    withinSystem*: bool # in system.nim or a module imported by system.nim
    inclToMod*: Table[FileIndex, FileIndex] # mapping of include file to the
                                            # first module that included it
    importStack*: seq[FileIndex]  # The current import stack. Used for detecting recursive
                                  # module dependencies.
    backend*: RootRef # minor hack so that a backend can extend this easily
    config*: ConfigRef
    cache*: IdentCache
    vm*: RootRef # unfortunately the 'vm' state is shared project-wise, this will
                 # be clarified in later compiler implementations.
    repl*: RootRef # REPL state is shared project-wise.
    doStopCompile*: proc(): bool {.closure.}
    usageSym*: PSym # for nimsuggest
    owners*: seq[PSym]
    suggestSymbols*: SuggestSymbolDatabase
    suggestErrors*: Table[FileIndex, seq[Suggest]]
    methods*: seq[tuple[methods: seq[PSym], dispatcher: PSym]] # needs serialization!
    bucketTable*: CountTable[ItemId]
    objectTree*: Table[ItemId, seq[tuple[depth: int, value: PType]]]
    methodsPerType*: Table[ItemId, seq[LazySym]]
    dispatchers*: seq[LazySym]

    systemModule*: PSym
    sysTypes*: array[TTypeKind, PType]
    compilerprocs*: TStrTable
    exposed*: TStrTable
    packageTypes*: TStrTable
    emptyNode*: PNode
    canonTypes*: Table[SigHash, PType]
    symBodyHashes*: Table[int, SigHash] # symId to digest mapping
    importModuleCallback*: proc (graph: ModuleGraph; m: PSym, fileIdx: FileIndex): PSym {.nimcall.}
    includeFileCallback*: proc (graph: ModuleGraph; m: PSym, fileIdx: FileIndex): PNode {.nimcall.}
    cacheSeqs*: Table[string, PNode] # state that is shared to support the 'macrocache' API; IC: implemented
    cacheCounters*: Table[string, BiggestInt] # IC: implemented
    cacheTables*: Table[string, BTree[string, PNode]] # IC: implemented
    passes*: seq[TPass]
    pipelinePass*: PipelinePass
    onDefinition*: proc (graph: ModuleGraph; s: PSym; info: TLineInfo) {.nimcall.}
    onDefinitionResolveForward*: proc (graph: ModuleGraph; s: PSym; info: TLineInfo) {.nimcall.}
    onUsage*: proc (graph: ModuleGraph; s: PSym; info: TLineInfo) {.nimcall.}
    globalDestructors*: seq[PNode]
    strongSemCheck*: proc (graph: ModuleGraph; owner: PSym; body: PNode) {.nimcall.}
    compatibleProps*: proc (graph: ModuleGraph; formal, actual: PType): bool {.nimcall.}
    idgen*: IdGenerator
    operators*: Operators

    cachedFiles*: StringTableRef

  TPassContext* = object of RootObj # the pass's context
    idgen*: IdGenerator
  PPassContext* = ref TPassContext

  TPassOpen* = proc (graph: ModuleGraph; module: PSym; idgen: IdGenerator): PPassContext {.nimcall.}
  TPassClose* = proc (graph: ModuleGraph; p: PPassContext, n: PNode): PNode {.nimcall.}
  TPassProcess* = proc (p: PPassContext, topLevelStmt: PNode): PNode {.nimcall.}

  TPass* = tuple[open: TPassOpen,
                 process: TPassProcess,
                 close: TPassClose,
                 isFrontend: bool]

proc resetForBackend*(g: ModuleGraph) =
  g.compilerprocs = initStrTable()
  g.typeInstCache.clear()
  g.procInstCache.clear()
  for a in mitems(g.attachedOps):
    a.clear()
  g.methodsPerGenericType.clear()
  g.enumToStringProcs.clear()
  g.dispatchers.setLen(0)
  g.methodsPerType.clear()

const
  cb64 = [
    "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N",
    "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
    "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n",
    "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9a",
    "9b", "9c"]

proc toBase64a(s: cstring, len: int): string =
  ## encodes `s` into base64 representation.
  result = newStringOfCap(((len + 2) div 3) * 4)
  result.add "__"
  var i = 0
  while i < len - 2:
    let a = ord(s[i])
    let b = ord(s[i+1])
    let c = ord(s[i+2])
    result.add cb64[a shr 2]
    result.add cb64[((a and 3) shl 4) or ((b and 0xF0) shr 4)]
    result.add cb64[((b and 0x0F) shl 2) or ((c and 0xC0) shr 6)]
    result.add cb64[c and 0x3F]
    inc(i, 3)
  if i < len-1:
    let a = ord(s[i])
    let b = ord(s[i+1])
    result.add cb64[a shr 2]
    result.add cb64[((a and 3) shl 4) or ((b and 0xF0) shr 4)]
    result.add cb64[((b and 0x0F) shl 2)]
  elif i < len:
    let a = ord(s[i])
    result.add cb64[a shr 2]
    result.add cb64[(a and 3) shl 4]

template interfSelect(iface: Iface, importHidden: bool): TStrTable =
  var ret = iface.interf.addr # without intermediate ptr, it creates a copy and compiler becomes 15x slower!
  if importHidden: ret = iface.interfHidden.addr
  ret[]

template semtab(g: ModuleGraph, m: PSym): TStrTable =
  g.ifaces[m.position].interf

template semtabAll*(g: ModuleGraph, m: PSym): TStrTable =
  g.ifaces[m.position].interfHidden

proc initStrTables*(g: ModuleGraph, m: PSym) =
  semtab(g, m) = initStrTable()
  semtabAll(g, m) = initStrTable()

proc strTableAdds*(g: ModuleGraph, m: PSym, s: PSym) =
  strTableAdd(semtab(g, m), s)
  strTableAdd(semtabAll(g, m), s)

proc isCachedModule(g: ModuleGraph; module: int): bool {.inline.} =
  result = module < g.packed.len and g.packed[module].status == loaded

proc isCachedModule*(g: ModuleGraph; m: PSym): bool {.inline.} =
  isCachedModule(g, m.position)

proc simulateCachedModule(g: ModuleGraph; moduleSym: PSym; m: PackedModule) =
  when false:
    echo "simulating ", moduleSym.name.s, " ", moduleSym.position
  simulateLoadedModule(g.packed, g.config, g.cache, moduleSym, m)

proc initEncoder*(g: ModuleGraph; module: PSym) =
  let id = module.position
  if id >= g.encoders.len:
    setLen g.encoders, id+1
  ic.initEncoder(g.encoders[id],
    g.packed[id].fromDisk, module, g.config, g.startupPackedConfig)

type
  ModuleIter* = object
    fromRod: bool
    modIndex: int
    ti: TIdentIter
    rodIt: RodIter
    importHidden: bool

proc initModuleIter*(mi: var ModuleIter; g: ModuleGraph; m: PSym; name: PIdent): PSym =
  assert m.kind == skModule
  mi.modIndex = m.position
  mi.fromRod = isCachedModule(g, mi.modIndex)
  mi.importHidden = optImportHidden in m.options
  if mi.fromRod:
    result = initRodIter(mi.rodIt, g.config, g.cache, g.packed, FileIndex mi.modIndex, name, mi.importHidden)
  else:
    result = initIdentIter(mi.ti, g.ifaces[mi.modIndex].interfSelect(mi.importHidden), name)

proc nextModuleIter*(mi: var ModuleIter; g: ModuleGraph): PSym =
  if mi.fromRod:
    result = nextRodIter(mi.rodIt, g.packed)
  else:
    result = nextIdentIter(mi.ti, g.ifaces[mi.modIndex].interfSelect(mi.importHidden))

iterator allSyms*(g: ModuleGraph; m: PSym): PSym =
  let importHidden = optImportHidden in m.options
  if isCachedModule(g, m):
    var rodIt: RodIter = default(RodIter)
    var r = initRodIterAllSyms(rodIt, g.config, g.cache, g.packed, FileIndex m.position, importHidden)
    while r != nil:
      yield r
      r = nextRodIter(rodIt, g.packed)
  else:
    for s in g.ifaces[m.position].interfSelect(importHidden).data:
      if s != nil:
        yield s

proc someSym*(g: ModuleGraph; m: PSym; name: PIdent): PSym =
  let importHidden = optImportHidden in m.options
  if isCachedModule(g, m):
    result = interfaceSymbol(g.config, g.cache, g.packed, FileIndex(m.position), name, importHidden)
  else:
    result = strTableGet(g.ifaces[m.position].interfSelect(importHidden), name)

proc someSymAmb*(g: ModuleGraph; m: PSym; name: PIdent; amb: var bool): PSym =
  let importHidden = optImportHidden in m.options
  if isCachedModule(g, m):
    result = nil
    for s in interfaceSymbols(g.config, g.cache, g.packed, FileIndex(m.position), name, importHidden):
      if result == nil:
        # set result to the first symbol
        result = s
      else:
        # another symbol found
        amb = true
        break
  else:
    var ti: TIdentIter = default(TIdentIter)
    result = initIdentIter(ti, g.ifaces[m.position].interfSelect(importHidden), name)
    if result != nil and nextIdentIter(ti, g.ifaces[m.position].interfSelect(importHidden)) != nil:
      # another symbol exists with same name
      amb = true

proc systemModuleSym*(g: ModuleGraph; name: PIdent): PSym =
  result = someSym(g, g.systemModule, name)

iterator systemModuleSyms*(g: ModuleGraph; name: PIdent): PSym =
  var mi: ModuleIter = default(ModuleIter)
  var r = initModuleIter(mi, g, g.systemModule, name)
  while r != nil:
    yield r
    r = nextModuleIter(mi, g)

proc resolveType(g: ModuleGraph; t: var LazyType): PType =
  result = t.typ
  if result == nil and isCachedModule(g, t.id.module):
    result = loadTypeFromId(g.config, g.cache, g.packed, t.id.module, t.id.packed)
    t.typ = result
  assert result != nil

proc resolveSym(g: ModuleGraph; t: var LazySym): PSym =
  result = t.sym
  if result == nil and isCachedModule(g, t.id.module):
    result = loadSymFromId(g.config, g.cache, g.packed, t.id.module, t.id.packed)
    t.sym = result
  assert result != nil

proc resolveInst(g: ModuleGraph; t: var LazyInstantiation): PInstantiation =
  result = t.inst
  if result == nil and isCachedModule(g, t.module):
    result = PInstantiation(sym: loadSymFromId(g.config, g.cache, g.packed, t.sym.module, t.sym.packed))
    result.concreteTypes = newSeq[PType](t.concreteTypes.len)
    for i in 0..high(result.concreteTypes):
      result.concreteTypes[i] = loadTypeFromId(g.config, g.cache, g.packed,
          t.concreteTypes[i].module, t.concreteTypes[i].packed)
    t.inst = result
  assert result != nil

proc resolveAttachedOp*(g: ModuleGraph; t: var LazySym): PSym =
  result = t.sym
  if result == nil:
    result = loadSymFromId(g.config, g.cache, g.packed, t.id.module, t.id.packed)
    t.sym = result
  assert result != nil

iterator typeInstCacheItems*(g: ModuleGraph; s: PSym): PType =
  if g.typeInstCache.contains(s.itemId):
    let x = addr(g.typeInstCache[s.itemId])
    for t in mitems(x[]):
      yield resolveType(g, t)

iterator procInstCacheItems*(g: ModuleGraph; s: PSym): PInstantiation =
  if g.procInstCache.contains(s.itemId):
    let x = addr(g.procInstCache[s.itemId])
    for t in mitems(x[]):
      yield resolveInst(g, t)


proc getAttachedOp*(g: ModuleGraph; t: PType; op: TTypeAttachedOp): PSym =
  ## returns the requested attached operation for type `t`. Can return nil
  ## if no such operation exists.
  if g.attachedOps[op].contains(t.itemId):
    result = resolveAttachedOp(g, g.attachedOps[op][t.itemId])
  else:
    result = nil

proc setAttachedOp*(g: ModuleGraph; module: int; t: PType; op: TTypeAttachedOp; value: PSym) =
  ## we also need to record this to the packed module.
  g.attachedOps[op][t.itemId] = LazySym(sym: value)

proc setAttachedOpPartial*(g: ModuleGraph; module: int; t: PType; op: TTypeAttachedOp; value: PSym) =
  ## we also need to record this to the packed module.
  g.attachedOps[op][t.itemId] = LazySym(sym: value)

proc completePartialOp*(g: ModuleGraph; module: int; t: PType; op: TTypeAttachedOp; value: PSym) =
  if g.config.symbolFiles != disabledSf:
    assert module < g.encoders.len
    assert isActive(g.encoders[module])
    toPackedGeneratedProcDef(value, g.encoders[module], g.packed[module].fromDisk)
    #storeAttachedProcDef(t, op, value, g.encoders[module], g.packed[module].fromDisk)

iterator getDispatchers*(g: ModuleGraph): PSym =
  for i in g.dispatchers.mitems:
    yield resolveSym(g, i)

proc addDispatchers*(g: ModuleGraph, value: PSym) =
  # TODO: add it for packed modules
  g.dispatchers.add LazySym(sym: value)

iterator resolveLazySymSeq(g: ModuleGraph, list: var seq[LazySym]): PSym =
  for it in list.mitems:
    yield resolveSym(g, it)

proc setMethodsPerType*(g: ModuleGraph; id: ItemId, methods: seq[LazySym]) =
  # TODO: add it for packed modules
  g.methodsPerType[id] = methods

iterator getMethodsPerType*(g: ModuleGraph; t: PType): PSym =
  if g.methodsPerType.contains(t.itemId):
    for it in mitems g.methodsPerType[t.itemId]:
      yield resolveSym(g, it)

proc getToStringProc*(g: ModuleGraph; t: PType): PSym =
  result = resolveSym(g, g.enumToStringProcs[t.itemId])
  assert result != nil

proc setToStringProc*(g: ModuleGraph; t: PType; value: PSym) =
  g.enumToStringProcs[t.itemId] = LazySym(sym: value)

iterator methodsForGeneric*(g: ModuleGraph; t: PType): (int, PSym) =
  if g.methodsPerGenericType.contains(t.itemId):
    for it in mitems g.methodsPerGenericType[t.itemId]:
      yield (it[0], resolveSym(g, it[1]))

proc addMethodToGeneric*(g: ModuleGraph; module: int; t: PType; col: int; m: PSym) =
  g.methodsPerGenericType.mgetOrPut(t.itemId, @[]).add (col, LazySym(sym: m))

proc hasDisabledAsgn*(g: ModuleGraph; t: PType): bool =
  let op = getAttachedOp(g, t, attachedAsgn)
  result = op != nil and sfError in op.flags

proc copyTypeProps*(g: ModuleGraph; module: int; dest, src: PType) =
  for k in low(TTypeAttachedOp)..high(TTypeAttachedOp):
    let op = getAttachedOp(g, src, k)
    if op != nil:
      setAttachedOp(g, module, dest, k, op)

proc loadCompilerProc*(g: ModuleGraph; name: string): PSym =
  result = nil
  if g.config.symbolFiles == disabledSf: return nil

  # slow, linear search, but the results are cached:
  for module in 0..<len(g.packed):
    #if isCachedModule(g, module):
    let x = searchForCompilerproc(g.packed[module], name)
    if x >= 0:
      result = loadSymFromId(g.config, g.cache, g.packed, module, toPackedItemId(x))
      if result != nil:
        strTableAdd(g.compilerprocs, result)
      return result

proc loadPackedSym*(g: ModuleGraph; s: var LazySym) =
  if s.sym == nil:
    s.sym = loadSymFromId(g.config, g.cache, g.packed, s.id.module, s.id.packed)

proc `$`*(u: SigHash): string =
  toBase64a(cast[cstring](unsafeAddr u), sizeof(u))

proc `==`*(a, b: SigHash): bool =
  result = equalMem(unsafeAddr a, unsafeAddr b, sizeof(a))

proc hash*(u: SigHash): Hash =
  result = 0
  for x in 0..3:
    result = (result shl 8) or u.MD5Digest[x].int

proc hash*(x: FileIndex): Hash {.borrow.}

template getPContext(): untyped =
  when c is PContext: c
  else: c.c

when defined(nimsuggest):
  template onUse*(info: TLineInfo; s: PSym) = discard
  template onDefResolveForward*(info: TLineInfo; s: PSym) = discard
else:
  template onUse*(info: TLineInfo; s: PSym) = discard
  template onDef*(info: TLineInfo; s: PSym) = discard
  template onDefResolveForward*(info: TLineInfo; s: PSym) = discard

proc stopCompile*(g: ModuleGraph): bool {.inline.} =
  result = g.doStopCompile != nil and g.doStopCompile()

proc createMagic*(g: ModuleGraph; idgen: IdGenerator; name: string, m: TMagic): PSym =
  result = newSym(skProc, getIdent(g.cache, name), idgen, nil, unknownLineInfo, {})
  result.magic = m
  result.flags = {sfNeverRaises}

proc createMagic(g: ModuleGraph; name: string, m: TMagic): PSym =
  result = createMagic(g, g.idgen, name, m)

proc uniqueModuleName*(conf: ConfigRef; m: PSym): string =
  ## The unique module name is guaranteed to only contain {'A'..'Z', 'a'..'z', '0'..'9', '_'}
  ## so that it is useful as a C identifier snippet.
  let fid = FileIndex(m.position)
  let path = AbsoluteFile toFullPath(conf, fid)
  var isLib = false
  var rel = ""
  if path.string.startsWith(conf.libpath.string):
    isLib = true
    rel = relativeTo(path, conf.libpath).string
  else:
    rel = relativeTo(path, conf.projectPath).string

  if not isLib and not belongsToProjectPackage(conf, m):
    # special handlings for nimble packages
    when DirSep == '\\':
      let rel2 = replace(rel, '\\', '/')
    else:
      let rel2 = rel
    const pkgs2 = "pkgs2/"
    var start = rel2.find(pkgs2)
    if start >= 0:
      start += pkgs2.len
      start += skipUntil(rel2, {'/'}, start)
      if start+1 < rel2.len:
        rel = "pkg/" & rel2[start+1..<rel.len] # strips paths

  let trunc = if rel.endsWith(".nim"): rel.len - len(".nim") else: rel.len
  result = newStringOfCap(trunc)
  for i in 0..<trunc:
    let c = rel[i]
    case c
    of 'a'..'z', '0'..'9':
      result.add c
    of {os.DirSep, os.AltSep}:
      result.add 'Z' # because it looks a bit like '/'
    of '.':
      result.add 'O' # a circle
    else:
      # We mangle upper letters too so that there cannot
      # be clashes with our special meanings of 'Z' and 'O'
      result.addInt ord(c)

proc registerModule*(g: ModuleGraph; m: PSym) =
  assert m != nil
  assert m.kind == skModule

  if m.position >= g.ifaces.len:
    setLen(g.ifaces, m.position + 1)

  if m.position >= g.packed.len:
    setLen(g.packed.pm, m.position + 1)

  g.ifaces[m.position] = Iface(module: m, converters: @[], patterns: @[],
                               uniqueName: rope(uniqueModuleName(g.config, m)))
  initStrTables(g, m)

proc registerModuleById*(g: ModuleGraph; m: FileIndex) =
  registerModule(g, g.packed[int m].module)

proc initOperators*(g: ModuleGraph): Operators =
  # These are safe for IC.
  # Public because it's used by DrNim.
  result = Operators(
    opLe: createMagic(g, "<=", mLeI),
    opLt: createMagic(g, "<", mLtI),
    opAnd: createMagic(g, "and", mAnd),
    opOr: createMagic(g, "or", mOr),
    opIsNil: createMagic(g, "isnil", mIsNil),
    opEq: createMagic(g, "==", mEqI),
    opAdd: createMagic(g, "+", mAddI),
    opSub: createMagic(g, "-", mSubI),
    opMul: createMagic(g, "*", mMulI),
    opDiv: createMagic(g, "div", mDivI),
    opLen: createMagic(g, "len", mLengthSeq),
    opNot: createMagic(g, "not", mNot),
    opContains: createMagic(g, "contains", mInSet)
  )

proc initModuleGraphFields(result: ModuleGraph) =
  # A module ID of -1 means that the symbol is not attached to a module at all,
  # but to the module graph:
  result.idgen = IdGenerator(module: -1'i32, symId: 0'i32, typeId: 0'i32)
  result.packageSyms = initStrTable()
  result.deps = initIntSet()
  result.importDeps = initTable[FileIndex, seq[FileIndex]]()
  result.ifaces = @[]
  result.importStack = @[]
  result.inclToMod = initTable[FileIndex, FileIndex]()
  result.owners = @[]
  result.suggestSymbols = initTable[FileIndex, SuggestFileSymbolDatabase]()
  result.suggestErrors = initTable[FileIndex, seq[Suggest]]()
  result.methods = @[]
  result.compilerprocs = initStrTable()
  result.exposed = initStrTable()
  result.packageTypes = initStrTable()
  result.emptyNode = newNode(nkEmpty)
  result.cacheSeqs = initTable[string, PNode]()
  result.cacheCounters = initTable[string, BiggestInt]()
  result.cacheTables = initTable[string, BTree[string, PNode]]()
  result.canonTypes = initTable[SigHash, PType]()
  result.symBodyHashes = initTable[int, SigHash]()
  result.operators = initOperators(result)
  result.emittedTypeInfo = initTable[string, FileIndex]()
  result.cachedFiles = newStringTable()

proc newModuleGraph*(cache: IdentCache; config: ConfigRef): ModuleGraph =
  result = ModuleGraph()
  result.config = config
  result.cache = cache
  initModuleGraphFields(result)

proc resetAllModules*(g: ModuleGraph) =
  g.packageSyms = initStrTable()
  g.deps = initIntSet()
  g.ifaces = @[]
  g.importStack = @[]
  g.inclToMod = initTable[FileIndex, FileIndex]()
  g.usageSym = nil
  g.owners = @[]
  g.methods = @[]
  g.compilerprocs = initStrTable()
  g.exposed = initStrTable()
  initModuleGraphFields(g)

proc getModule*(g: ModuleGraph; fileIdx: FileIndex): PSym =
  result = nil
  if fileIdx.int32 >= 0:
    if isCachedModule(g, fileIdx.int32):
      result = g.packed[fileIdx.int32].module
    elif fileIdx.int32 < g.ifaces.len:
      result = g.ifaces[fileIdx.int32].module

proc moduleOpenForCodegen*(g: ModuleGraph; m: FileIndex): bool {.inline.} =
  if g.config.symbolFiles == disabledSf:
    result = true
  else:
    result = g.packed[m.int32].status notin {undefined, stored, loaded}

proc rememberEmittedTypeInfo*(g: ModuleGraph; m: FileIndex; ti: string) =
  #assert(not isCachedModule(g, m.int32))
  if g.config.symbolFiles != disabledSf:
    #assert g.encoders[m.int32].isActive
    assert g.packed[m.int32].status != stored
    g.packed[m.int32].fromDisk.emittedTypeInfo.add ti
    #echo "added typeinfo ", m.int32, " ", ti, " suspicious ", not g.encoders[m.int32].isActive

proc rememberFlag*(g: ModuleGraph; m: PSym; flag: ModuleBackendFlag) =
  if g.config.symbolFiles != disabledSf:
    #assert g.encoders[m.int32].isActive
    assert g.packed[m.position].status != stored
    g.packed[m.position].fromDisk.backendFlags.incl flag

proc closeRodFile*(g: ModuleGraph; m: PSym) =
  if g.config.symbolFiles in {readOnlySf, v2Sf}:
    # For stress testing we seek to reload the symbols from memory. This
    # way much of the logic is tested but the test is reproducible as it does
    # not depend on the hard disk contents!
    let mint = m.position
    saveRodFile(toRodFile(g.config, AbsoluteFile toFullPath(g.config, FileIndex(mint))),
                g.encoders[mint], g.packed[mint].fromDisk)
    g.packed[mint].status = stored

  elif g.config.symbolFiles == stressTest:
    # debug code, but maybe a good idea for production? Could reduce the compiler's
    # memory consumption considerably at the cost of more loads from disk.
    let mint = m.position
    simulateCachedModule(g, m, g.packed[mint].fromDisk)
    g.packed[mint].status = loaded

proc dependsOn(a, b: int): int {.inline.} = (a shl 15) + b

proc addDep*(g: ModuleGraph; m: PSym, dep: FileIndex) =
  assert m.position == m.info.fileIndex.int32
  if g.suggestMode:
    g.deps.incl m.position.dependsOn(dep.int)
    # we compute the transitive closure later when querying the graph lazily.
    # this improves efficiency quite a lot:
    #invalidTransitiveClosure = true

proc addIncludeDep*(g: ModuleGraph; module, includeFile: FileIndex) =
  discard hasKeyOrPut(g.inclToMod, includeFile, module)

proc parentModule*(g: ModuleGraph; fileIdx: FileIndex): FileIndex =
  ## returns 'fileIdx' if the file belonging to this index is
  ## directly used as a module or else the module that first
  ## references this include file.
  if fileIdx.int32 >= 0 and fileIdx.int32 < g.ifaces.len and g.ifaces[fileIdx.int32].module != nil:
    result = fileIdx
  else:
    result = g.inclToMod.getOrDefault(fileIdx)

proc transitiveClosure(g: var IntSet; n: int) =
  # warshall's algorithm
  for k in 0..<n:
    for i in 0..<n:
      for j in 0..<n:
        if i != j and not g.contains(i.dependsOn(j)):
          if g.contains(i.dependsOn(k)) and g.contains(k.dependsOn(j)):
            g.incl i.dependsOn(j)

proc markDirty*(g: ModuleGraph; fileIdx: FileIndex) =
  let m = g.getModule fileIdx
  if m != nil:
    g.suggestSymbols.del(fileIdx)
    g.suggestErrors.del(fileIdx)
    incl m.flags, sfDirty

proc unmarkAllDirty*(g: ModuleGraph) =
  for i in 0i32..<g.ifaces.len.int32:
    let m = g.ifaces[i].module
    if m != nil:
      m.flags.excl sfDirty

proc isDirty*(g: ModuleGraph; m: PSym): bool =
  result = g.suggestMode and sfDirty in m.flags

proc markClientsDirty*(g: ModuleGraph; fileIdx: FileIndex) =
  # we need to mark its dependent modules D as dirty right away because after
  # nimsuggest is done with this module, the module's dirty flag will be
  # cleared but D still needs to be remembered as 'dirty'.
  if g.invalidTransitiveClosure:
    g.invalidTransitiveClosure = false
    transitiveClosure(g.deps, g.ifaces.len)

  # every module that *depends* on this file is also dirty:
  for i in 0i32..<g.ifaces.len.int32:
    if g.deps.contains(i.dependsOn(fileIdx.int)):
      g.markDirty(FileIndex(i))

proc needsCompilation*(g: ModuleGraph): bool =
  # every module that *depends* on this file is also dirty:
  result = false
  for i in 0i32..<g.ifaces.len.int32:
    let m = g.ifaces[i].module
    if m != nil:
      if sfDirty in m.flags:
        return true

proc needsCompilation*(g: ModuleGraph, fileIdx: FileIndex): bool =
  result = false
  let module = g.getModule(fileIdx)
  if module != nil and g.isDirty(module):
    return true

  for i in 0i32..<g.ifaces.len.int32:
    let m = g.ifaces[i].module
    if m != nil and g.isDirty(m) and g.deps.contains(fileIdx.int32.dependsOn(i)):
      return true

proc getBody*(g: ModuleGraph; s: PSym): PNode {.inline.} =
  result = s.ast[bodyPos]
  if result == nil and g.config.symbolFiles in {readOnlySf, v2Sf, stressTest}:
    result = loadProcBody(g.config, g.cache, g.packed, s)
    s.ast[bodyPos] = result
  assert result != nil

proc moduleFromRodFile*(g: ModuleGraph; fileIdx: FileIndex;
                        cachedModules: var seq[FileIndex]): PSym =
  ## Returns 'nil' if the module needs to be recompiled.
  if g.config.symbolFiles in {readOnlySf, v2Sf, stressTest}:
    result = moduleFromRodFile(g.packed, g.config, g.cache, fileIdx, cachedModules)
  else:
    result = nil

proc configComplete*(g: ModuleGraph) =
  rememberStartupConfig(g.startupPackedConfig, g.config)

proc onProcessing*(graph: ModuleGraph, fileIdx: FileIndex, moduleStatus: string, fromModule: PSym, ) =
  let conf = graph.config
  let isNimscript = conf.isDefined("nimscript")
  if (not isNimscript) or hintProcessing in conf.cmdlineNotes:
    let path = toFilenameOption(conf, fileIdx, conf.filenameOption)
    let indent = ">".repeat(graph.importStack.len)
    let fromModule2 = if fromModule != nil: $fromModule.name.s else: "(toplevel)"
    let mode = if isNimscript: "(nims) " else: ""
    rawMessage(conf, hintProcessing, "$#$# $#: $#: $#" % [mode, indent, fromModule2, moduleStatus, path])

proc getPackage*(graph: ModuleGraph; fileIdx: FileIndex): PSym =
  ## Returns a package symbol for yet to be defined module for fileIdx.
  ## The package symbol is added to the graph if it doesn't exist.
  let pkgSym = getPackage(graph.config, graph.cache, fileIdx)
  # check if the package is already in the graph
  result = graph.packageSyms.strTableGet(pkgSym.name)
  if result == nil:
     # the package isn't in the graph, so create and add it
    result = pkgSym
    graph.packageSyms.strTableAdd(pkgSym)

func belongsToStdlib*(graph: ModuleGraph, sym: PSym): bool =
  ## Check if symbol belongs to the 'stdlib' package.
  sym.getPackageSymbol.getPackageId == graph.systemModule.getPackageId

proc fileSymbols*(graph: ModuleGraph, fileIdx: FileIndex): SuggestFileSymbolDatabase =
  result = graph.suggestSymbols.getOrDefault(fileIdx, newSuggestFileSymbolDatabase(fileIdx, optIdeExceptionInlayHints in graph.config.globalOptions))
  doAssert(result.fileIndex == fileIdx)

iterator suggestSymbolsIter*(g: ModuleGraph): SymInfoPair =
  for xs in g.suggestSymbols.values:
    for i in xs.lineInfo.low..xs.lineInfo.high:
      yield xs.getSymInfoPair(i)

iterator suggestErrorsIter*(g: ModuleGraph): Suggest =
  for xs in g.suggestErrors.values:
    for x in xs:
      yield x

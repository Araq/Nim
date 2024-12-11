#
#
#           The Nim Compiler
#        (c) Copyright 2017 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module contains the data structures for the semantic checking phase.

import std/[tables, intsets, sets]

when defined(nimPreviewSlimSystem):
  import std/assertions

import
  options, ast, msgs, idents, renderer,
  magicsys, vmdef, modulegraphs, lineinfos, pathutils, layeredtable

import ic / ic

type
  TOptionEntry* = object      # entries to put on a stack for pragma parsing
    options*: TOptions
    defaultCC*: TCallingConvention
    dynlib*: PLib
    notes*: TNoteKinds
    features*: set[Feature]
    otherPragmas*: PNode      # every pragma can be pushed
    warningAsErrors*: TNoteKinds

  POptionEntry* = ref TOptionEntry
  PProcCon* = ref TProcCon
  TProcCon* {.acyclic.} = object # procedure context; also used for top-level
                                 # statements
    owner*: PSym              # the symbol this context belongs to
    resultSym*: PSym          # the result symbol (if we are in a proc)
    nestedLoopCounter*: int   # whether we are in a loop or not
    nestedBlockCounter*: int  # whether we are in a block or not
    breakInLoop*: bool        # whether we are in a loop without block
    next*: PProcCon           # used for stacking procedure contexts
    mappingExists*: bool
    mapping*: Table[ItemId, PSym]
    caseContext*: seq[tuple[n: PNode, idx: int]]
    localBindStmts*: seq[PNode]

  TMatchedConcept* = object
    candidateType*: PType
    prev*: ptr TMatchedConcept
    depth*: int

  TInstantiationPair* = object
    genericSym*: PSym
    inst*: PInstantiation

  TExprFlag* = enum
    efLValue, efWantIterator, efWantIterable, efInTypeof,
    efNeedStatic,
      # Use this in contexts where a static value is mandatory
    efPreferStatic,
      # Use this in contexts where a static value could bring more
      # information, but it's not strictly mandatory. This may become
      # the default with implicit statics in the future.
    efPreferNilResult,
      # Use this if you want a certain result (e.g. static value),
      # but you don't want to trigger a hard error. For example,
      # you may be in position to supply a better error message
      # to the user.
    efWantStmt, efAllowStmt, efDetermineType, efExplain,
    efWantValue, efOperand, efNoSemCheck,
    efNoEvaluateGeneric, efInCall, efFromHlo, efNoSem2Check,
    efNoUndeclared, efIsDotCall, efCannotBeDotCall,
      # Use this if undeclared identifiers should not raise an error during
      # overload resolution.
    efTypeAllowed # typeAllowed will be called after
    efWantNoDefaults
    efIgnoreDefaults # var statements without initialization
    efAllowSymChoice # symchoice node should not be resolved

  TExprFlags* = set[TExprFlag]

  ImportMode* = enum
    importAll, importSet, importExcept
  ImportedModule* = object
    m*: PSym
    case mode*: ImportMode
    of importAll: discard
    of importSet:
      imported*: IntSet          # of PIdent.id
    of importExcept:
      exceptSet*: IntSet         # of PIdent.id

  PContext* = ref TContext
  TContext* = object of TPassContext # a context represents the module
                                     # that is currently being compiled
    enforceVoidContext*: PType
      # for `if cond: stmt else: foo`, `foo` will be evaluated under
      # enforceVoidContext != nil
    voidType*: PType # for typeof(stmt)
    module*: PSym              # the module sym belonging to the context
    currentScope*: PScope      # current scope
    moduleScope*: PScope       # scope for modules
    imports*: seq[ImportedModule] # scope for all imported symbols
    topLevelScope*: PScope     # scope for all top-level symbols
    p*: PProcCon               # procedure context
    intTypeCache*: array[-5..32, PType] # cache some common integer types
                                        # to avoid type allocations
    nilTypeCache*: PType
    matchedConcept*: ptr TMatchedConcept # the current concept being matched
    friendModules*: seq[PSym]  # friend modules; may access private data;
                               # this is used so that generic instantiations
                               # can access private object fields
    instCounter*: int          # to prevent endless instantiations
    templInstCounter*: ref int # gives every template instantiation a unique id
    inGenericContext*: int     # > 0 if we are in a generic type
    inStaticContext*: int      # > 0 if we are inside a static: block
    inUnrolledContext*: int    # > 0 if we are unrolling a loop
    compilesContextId*: int    # > 0 if we are in a ``compiles`` magic
    compilesContextIdGenerator*: int
    inGenericInst*: int        # > 0 if we are instantiating a generic
    converters*: seq[PSym]
    patterns*: seq[PSym]       # sequence of pattern matchers
    optionStack*: seq[POptionEntry]
    libs*: seq[PLib]           # all libs used by this module
    semConstExpr*: proc (c: PContext, n: PNode; expectedType: PType = nil): PNode {.nimcall.} # for the pragmas
    semExpr*: proc (c: PContext, n: PNode, flags: TExprFlags = {}, expectedType: PType = nil): PNode {.nimcall.}
    semExprWithType*: proc (c: PContext, n: PNode, flags: TExprFlags = {}, expectedType: PType = nil): PNode {.nimcall.}
    semTryExpr*: proc (c: PContext, n: PNode, flags: TExprFlags = {}): PNode {.nimcall.}
    semTryConstExpr*: proc (c: PContext, n: PNode; expectedType: PType = nil): PNode {.nimcall.}
    computeRequiresInit*: proc (c: PContext, t: PType): bool {.nimcall.}
    hasUnresolvedArgs*: proc (c: PContext, n: PNode): bool

    semOperand*: proc (c: PContext, n: PNode, flags: TExprFlags = {}): PNode {.nimcall.}
    semConstBoolExpr*: proc (c: PContext, n: PNode): PNode {.nimcall.} # XXX bite the bullet
    semOverloadedCall*: proc (c: PContext, n, nOrig: PNode,
                              filter: TSymKinds, flags: TExprFlags, expectedType: PType = nil): PNode {.nimcall.}
    semTypeNode*: proc(c: PContext, n: PNode, prev: PType): PType {.nimcall.}
    semInferredLambda*: proc(c: PContext, pt: LayeredIdTable, n: PNode): PNode
    semGenerateInstance*: proc (c: PContext, fn: PSym, pt: LayeredIdTable,
                                info: TLineInfo): PSym
    instantiateOnlyProcType*: proc (c: PContext, pt: LayeredIdTable,
                                    prc: PSym, info: TLineInfo): PType
      # used by sigmatch for explicit generic instantiations
    fitDefaultNode*: proc (c: PContext, n: var PNode, expectedType: PType)
    includedFiles*: IntSet    # used to detect recursive include files
    pureEnumFields*: TStrTable   # pure enum fields that can be used unambiguously
    userPragmas*: TStrTable
    evalContext*: PEvalContext
    unknownIdents*: IntSet     # ids of all unknown identifiers to prevent
                               # naming it multiple times
    generics*: seq[TInstantiationPair] # pending list of instantiated generics to compile
    topStmts*: int # counts the number of encountered top level statements
    lastGenericIdx*: int      # used for the generics stack
    hloLoopDetector*: int     # used to prevent endless loops in the HLO
    inParallelStmt*: int
    instTypeBoundOp*: proc (c: PContext; dc: PSym; t: PType; info: TLineInfo;
                            op: TTypeAttachedOp; col: int): PSym {.nimcall.}
    cache*: IdentCache
    graph*: ModuleGraph
    signatures*: TStrTable
    recursiveDep*: string
    suggestionsMade*: bool
    isAmbiguous*: bool # little hack
    features*: set[Feature]
    inTypeContext*, inConceptDecl*: int
    unusedImports*: seq[(PSym, TLineInfo)]
    exportIndirections*: HashSet[(int, int)] # (module.id, symbol.id)
    importModuleMap*: Table[int, int] # (module.id, module.id)
    lastTLineInfo*: TLineInfo
    sideEffects*: Table[int, seq[(TLineInfo, PSym)]] # symbol.id index
    inUncheckedAssignSection*: int
    importModuleLookup*: Table[int, seq[int]] # (module.ident.id, [module.id])
    skipTypes*: seq[PNode] # used to skip types between passes in type section. So far only used for inheritance, sets and generic bodies.
    inTypeofContext*: int
  TBorrowState* = enum
    bsNone, bsReturnNotMatch, bsNoDistinct, bsGeneric, bsNotSupported, bsMatch

template config*(c: PContext): ConfigRef = c.graph.config

proc getIntLitType*(c: PContext; literal: PNode): PType =
  # we cache some common integer literal types for performance:
  let value = literal.intVal
  if value >= low(c.intTypeCache) and value <= high(c.intTypeCache):
    result = c.intTypeCache[value.int]
    if result == nil:
      let ti = getSysType(c.graph, literal.info, tyInt)
      result = copyType(ti, c.idgen, ti.owner)
      result.n = literal
      c.intTypeCache[value.int] = result
  else:
    let ti = getSysType(c.graph, literal.info, tyInt)
    result = copyType(ti, c.idgen, ti.owner)
    result.n = literal

proc setIntLitType*(c: PContext; result: PNode) =
  let i = result.intVal
  case c.config.target.intSize
  of 8: result.typ() = getIntLitType(c, result)
  of 4:
    if i >= low(int32) and i <= high(int32):
      result.typ() = getIntLitType(c, result)
    else:
      result.typ() = getSysType(c.graph, result.info, tyInt64)
  of 2:
    if i >= low(int16) and i <= high(int16):
      result.typ() = getIntLitType(c, result)
    elif i >= low(int32) and i <= high(int32):
      result.typ() = getSysType(c.graph, result.info, tyInt32)
    else:
      result.typ() = getSysType(c.graph, result.info, tyInt64)
  of 1:
    # 8 bit CPUs are insane ...
    if i >= low(int8) and i <= high(int8):
      result.typ() = getIntLitType(c, result)
    elif i >= low(int16) and i <= high(int16):
      result.typ() = getSysType(c.graph, result.info, tyInt16)
    elif i >= low(int32) and i <= high(int32):
      result.typ() = getSysType(c.graph, result.info, tyInt32)
    else:
      result.typ() = getSysType(c.graph, result.info, tyInt64)
  else:
    internalError(c.config, result.info, "invalid int size")

proc makeInstPair*(s: PSym, inst: PInstantiation): TInstantiationPair =
  result = TInstantiationPair(genericSym: s, inst: inst)

proc filename*(c: PContext): string =
  # the module's filename
  result = toFilename(c.config, FileIndex c.module.position)

proc scopeDepth*(c: PContext): int {.inline.} =
  result = if c.currentScope != nil: c.currentScope.depthLevel
           else: 0

proc getCurrOwner*(c: PContext): PSym =
  # owner stack (used for initializing the
  # owner field of syms)
  # the documentation comment always gets
  # assigned to the current owner
  result = c.graph.owners[^1]

proc pushOwner*(c: PContext; owner: PSym) =
  c.graph.owners.add(owner)

proc popOwner*(c: PContext) =
  if c.graph.owners.len > 0: setLen(c.graph.owners, c.graph.owners.len - 1)
  else: internalError(c.config, "popOwner")

proc lastOptionEntry*(c: PContext): POptionEntry =
  result = c.optionStack[^1]

proc popProcCon*(c: PContext) {.inline.} = c.p = c.p.next

proc put*(p: PProcCon; key, val: PSym) =
  if not p.mappingExists:
    p.mapping = initTable[ItemId, PSym]()
    p.mappingExists = true
  #echo "put into table ", key.info
  p.mapping[key.itemId] = val

proc get*(p: PProcCon; key: PSym): PSym =
  if not p.mappingExists: return nil
  result = p.mapping.getOrDefault(key.itemId)

proc getGenSym*(c: PContext; s: PSym): PSym =
  if sfGenSym notin s.flags: return s
  var it = c.p
  while it != nil:
    result = get(it, s)
    if result != nil:
      #echo "got from table ", result.name.s, " ", result.info
      return result
    it = it.next
  result = s

proc considerGenSyms*(c: PContext; n: PNode) =
  if n == nil:
    discard "can happen for nkFormalParams/nkArgList"
  elif n.kind == nkSym:
    let s = getGenSym(c, n.sym)
    if n.sym != s:
      n.sym = s
  else:
    for i in 0..<n.safeLen:
      considerGenSyms(c, n[i])

proc newOptionEntry*(conf: ConfigRef): POptionEntry =
  new(result)
  result.options = conf.options
  result.defaultCC = ccNimCall
  result.dynlib = nil
  result.notes = conf.notes
  result.warningAsErrors = conf.warningAsErrors

proc pushOptionEntry*(c: PContext): POptionEntry =
  new(result)
  var prev = c.optionStack[^1]
  result.options = c.config.options
  result.defaultCC = prev.defaultCC
  result.dynlib = prev.dynlib
  result.notes = c.config.notes
  result.warningAsErrors = c.config.warningAsErrors
  result.features = c.features
  c.optionStack.add(result)

proc popOptionEntry*(c: PContext) =
  c.config.options = c.optionStack[^1].options
  c.config.notes = c.optionStack[^1].notes
  c.config.warningAsErrors = c.optionStack[^1].warningAsErrors
  c.features = c.optionStack[^1].features
  c.optionStack.setLen(c.optionStack.len - 1)

proc newContext*(graph: ModuleGraph; module: PSym): PContext =
  new(result)
  result.optionStack = @[newOptionEntry(graph.config)]
  result.libs = @[]
  result.module = module
  result.friendModules = @[module]
  result.converters = @[]
  result.patterns = @[]
  result.includedFiles = initIntSet()
  result.pureEnumFields = initStrTable()
  result.userPragmas = initStrTable()
  result.generics = @[]
  result.unknownIdents = initIntSet()
  result.cache = graph.cache
  result.graph = graph
  result.signatures = initStrTable()
  result.features = graph.config.features
  if graph.config.symbolFiles != disabledSf:
    let id = module.position
    if graph.config.cmd != cmdM:
      assert graph.packed[id].status in {undefined, outdated}
    graph.packed[id].status = storing
    graph.packed[id].module = module
    initEncoder graph, module

template packedRepr*(c): untyped = c.graph.packed[c.module.position].fromDisk
template encoder*(c): untyped = c.graph.encoders[c.module.position]

proc addIncludeFileDep*(c: PContext; f: FileIndex) =
  if c.config.symbolFiles != disabledSf:
    addIncludeFileDep(c.encoder, c.packedRepr, f)

proc addImportFileDep*(c: PContext; f: FileIndex) =
  if c.config.symbolFiles != disabledSf:
    addImportFileDep(c.encoder, c.packedRepr, f)

proc addPragmaComputation*(c: PContext; n: PNode) =
  if c.config.symbolFiles != disabledSf:
    addPragmaComputation(c.encoder, c.packedRepr, n)

proc inclSym(sq: var seq[PSym], s: PSym): bool =
  for i in 0..<sq.len:
    if sq[i].id == s.id: return false
  sq.add s
  result = true

proc addConverter*(c: PContext, conv: LazySym) =
  assert conv.sym != nil
  if inclSym(c.converters, conv.sym):
    add(c.graph.ifaces[c.module.position].converters, conv)

proc addConverterDef*(c: PContext, conv: LazySym) =
  addConverter(c, conv)
  if c.config.symbolFiles != disabledSf:
    addConverter(c.encoder, c.packedRepr, conv.sym)

proc addPureEnum*(c: PContext, e: LazySym) =
  assert e.sym != nil
  add(c.graph.ifaces[c.module.position].pureEnums, e)
  if c.config.symbolFiles != disabledSf:
    addPureEnum(c.encoder, c.packedRepr, e.sym)

proc addPattern*(c: PContext, p: LazySym) =
  assert p.sym != nil
  if inclSym(c.patterns, p.sym):
    add(c.graph.ifaces[c.module.position].patterns, p)
  if c.config.symbolFiles != disabledSf:
    addTrmacro(c.encoder, c.packedRepr, p.sym)

proc exportSym*(c: PContext; s: PSym) =
  strTableAdds(c.graph, c.module, s)
  if c.config.symbolFiles != disabledSf:
    addExported(c.encoder, c.packedRepr, s)

proc reexportSym*(c: PContext; s: PSym) =
  strTableAdds(c.graph, c.module, s)
  if c.config.symbolFiles != disabledSf:
    addReexport(c.encoder, c.packedRepr, s)

proc newLib*(kind: TLibKind): PLib =
  new(result)
  result.kind = kind          #result.syms = initObjectSet()

proc addToLib*(lib: PLib, sym: PSym) =
  #if sym.annex != nil and not isGenericRoutine(sym):
  #  LocalError(sym.info, errInvalidPragma)
  sym.annex = lib

proc newTypeS*(kind: TTypeKind; c: PContext; son: sink PType = nil): PType =
  result = newType(kind, c.idgen, getCurrOwner(c), son = son)

proc makePtrType*(owner: PSym, baseType: PType; idgen: IdGenerator): PType =
  result = newType(tyPtr, idgen, owner, skipIntLit(baseType, idgen))

proc makePtrType*(c: PContext, baseType: PType): PType =
  makePtrType(getCurrOwner(c), baseType, c.idgen)

proc makeTypeWithModifier*(c: PContext,
                           modifier: TTypeKind,
                           baseType: PType): PType =
  assert modifier in {tyVar, tyLent, tyPtr, tyRef, tyStatic, tyTypeDesc}

  if modifier in {tyVar, tyLent, tyTypeDesc} and baseType.kind == modifier:
    result = baseType
  else:
    result = newTypeS(modifier, c, skipIntLit(baseType, c.idgen))

proc makeVarType*(c: PContext, baseType: PType; kind = tyVar): PType =
  if baseType.kind == kind:
    result = baseType
  else:
    result = newTypeS(kind, c, skipIntLit(baseType, c.idgen))

proc makeTypeSymNode*(c: PContext, typ: PType, info: TLineInfo): PNode =
  let typedesc = newTypeS(tyTypeDesc, c)
  incl typedesc.flags, tfCheckedForDestructor
  internalAssert(c.config, typ != nil)
  typedesc.addSonSkipIntLit(typ, c.idgen)
  let sym = newSym(skType, c.cache.idAnon, c.idgen, getCurrOwner(c), info,
                   c.config.options).linkTo(typedesc)
  result = newSymNode(sym, info)

proc makeTypeFromExpr*(c: PContext, n: PNode): PType =
  result = newTypeS(tyFromExpr, c)
  assert n != nil
  result.n = n

when false:
  proc newTypeWithSons*(owner: PSym, kind: TTypeKind, sons: seq[PType];
                        idgen: IdGenerator): PType =
    result = newType(kind, idgen, owner, sons = sons)

  proc newTypeWithSons*(c: PContext, kind: TTypeKind,
                        sons: seq[PType]): PType =
    result = newType(kind, c.idgen, getCurrOwner(c), sons = sons)

proc makeStaticExpr*(c: PContext, n: PNode): PNode =
  result = newNodeI(nkStaticExpr, n.info)
  result.sons = @[n]
  result.typ() = if n.typ != nil and n.typ.kind == tyStatic: n.typ
               else: newTypeS(tyStatic, c, n.typ)

proc makeAndType*(c: PContext, t1, t2: PType): PType =
  result = newTypeS(tyAnd, c)
  result.rawAddSon t1
  result.rawAddSon t2
  propagateToOwner(result, t1)
  propagateToOwner(result, t2)
  result.flags.incl((t1.flags + t2.flags) * {tfHasStatic})
  result.flags.incl tfHasMeta

proc makeOrType*(c: PContext, t1, t2: PType): PType =
  if t1.kind != tyOr and t2.kind != tyOr:
    result = newTypeS(tyOr, c)
    result.rawAddSon t1
    result.rawAddSon t2
  else:
    result = newTypeS(tyOr, c)
    template addOr(t1) =
      if t1.kind == tyOr:
        for x in t1.kids: result.rawAddSon x
      else:
        result.rawAddSon t1
    addOr(t1)
    addOr(t2)
  propagateToOwner(result, t1)
  propagateToOwner(result, t2)
  result.flags.incl((t1.flags + t2.flags) * {tfHasStatic})
  result.flags.incl tfHasMeta

proc makeNotType*(c: PContext, t1: PType): PType =
  result = newTypeS(tyNot, c, son = t1)
  propagateToOwner(result, t1)
  result.flags.incl(t1.flags * {tfHasStatic})
  result.flags.incl tfHasMeta

proc nMinusOne(c: PContext; n: PNode): PNode =
  result = newTreeI(nkCall, n.info, newSymNode(getSysMagic(c.graph, n.info, "pred", mPred)), n)

# Remember to fix the procs below this one when you make changes!
proc makeRangeWithStaticExpr*(c: PContext, n: PNode): PType =
  let intType = getSysType(c.graph, n.info, tyInt)
  result = newTypeS(tyRange, c, son = intType)
  if n.typ != nil and n.typ.n == nil:
    result.flags.incl tfUnresolved
  result.n = newTreeI(nkRange, n.info, newIntTypeNode(0, intType),
    makeStaticExpr(c, nMinusOne(c, n)))

template rangeHasUnresolvedStatic*(t: PType): bool =
  tfUnresolved in t.flags

proc errorType*(c: PContext): PType =
  ## creates a type representing an error state
  result = newTypeS(tyError, c)
  result.flags.incl tfCheckedForDestructor

proc errorNode*(c: PContext, n: PNode): PNode =
  result = newNodeI(nkEmpty, n.info)
  result.typ() = errorType(c)

# These mimic localError
template localErrorNode*(c: PContext, n: PNode, info: TLineInfo, msg: TMsgKind, arg: string): PNode =
  liMessage(c.config, info, msg, arg, doNothing, instLoc())
  errorNode(c, n)

template localErrorNode*(c: PContext, n: PNode, info: TLineInfo, arg: string): PNode =
  liMessage(c.config, info, errGenerated, arg, doNothing, instLoc())
  errorNode(c, n)

template localErrorNode*(c: PContext, n: PNode, msg: TMsgKind, arg: string): PNode =
  let n2 = n
  liMessage(c.config, n2.info, msg, arg, doNothing, instLoc())
  errorNode(c, n2)

template localErrorNode*(c: PContext, n: PNode, arg: string): PNode =
  let n2 = n
  liMessage(c.config, n2.info, errGenerated, arg, doNothing, instLoc())
  errorNode(c, n2)

when false:
  proc fillTypeS*(dest: PType, kind: TTypeKind, c: PContext) =
    dest.kind = kind
    dest.owner = getCurrOwner(c)
    dest.size = - 1

proc makeRangeType*(c: PContext; first, last: BiggestInt;
                    info: TLineInfo; intType: PType = nil): PType =
  let intType = if intType != nil: intType else: getSysType(c.graph, info, tyInt)
  var n = newNodeI(nkRange, info)
  n.add newIntTypeNode(first, intType)
  n.add newIntTypeNode(last, intType)
  result = newTypeS(tyRange, c)
  result.n = n
  addSonSkipIntLit(result, intType, c.idgen) # basetype of range

proc isSelf*(t: PType): bool {.inline.} =
  ## Is this the magical 'Self' type from concepts?
  t.kind == tyTypeDesc and tfPacked in t.flags

proc makeTypeDesc*(c: PContext, typ: PType): PType =
  if typ.kind == tyTypeDesc and not isSelf(typ):
    result = typ
  else:
    result = newTypeS(tyTypeDesc, c, skipIntLit(typ, c.idgen))
    incl result.flags, tfCheckedForDestructor

proc symFromType*(c: PContext; t: PType, info: TLineInfo): PSym =
  if t.sym != nil: return t.sym
  result = newSym(skType, getIdent(c.cache, "AnonType"), c.idgen, t.owner, info)
  result.flags.incl sfAnon
  result.typ = t

proc symNodeFromType*(c: PContext, t: PType, info: TLineInfo): PNode =
  result = newSymNode(symFromType(c, t, info), info)
  result.typ() = makeTypeDesc(c, t)

proc markIndirect*(c: PContext, s: PSym) {.inline.} =
  if s.kind in {skProc, skFunc, skConverter, skMethod, skIterator}:
    incl(s.flags, sfAddrTaken)
    # XXX add to 'c' for global analysis

proc illFormedAst*(n: PNode; conf: ConfigRef) =
  globalError(conf, n.info, errIllFormedAstX, renderTree(n, {renderNoComments}))

proc illFormedAstLocal*(n: PNode; conf: ConfigRef) =
  localError(conf, n.info, errIllFormedAstX, renderTree(n, {renderNoComments}))

proc checkSonsLen*(n: PNode, length: int; conf: ConfigRef) =
  if n.len != length: illFormedAst(n, conf)

proc checkMinSonsLen*(n: PNode, length: int; conf: ConfigRef) =
  if n.len < length: illFormedAst(n, conf)

proc isTopLevel*(c: PContext): bool {.inline.} =
  result = c.currentScope.depthLevel <= 2

proc isTopLevelInsideDeclaration*(c: PContext, sym: PSym): bool {.inline.} =
  # for routeKinds the scope isn't closed yet:
  c.currentScope.depthLevel <= 2 + ord(sym.kind in routineKinds)

proc pushCaseContext*(c: PContext, caseNode: PNode) =
  c.p.caseContext.add((caseNode, 0))

proc popCaseContext*(c: PContext) =
  discard pop(c.p.caseContext)

proc setCaseContextIdx*(c: PContext, idx: int) =
  c.p.caseContext[^1].idx = idx

template addExport*(c: PContext; s: PSym) =
  ## convenience to export a symbol from the current module
  addExport(c.graph, c.module, s)

proc storeRodNode*(c: PContext, n: PNode) =
  if c.config.symbolFiles != disabledSf:
    toPackedNodeTopLevel(n, c.encoder, c.packedRepr)

proc addToGenericProcCache*(c: PContext; s: PSym; inst: PInstantiation) =
  c.graph.procInstCache.mgetOrPut(s.itemId, @[]).add LazyInstantiation(module: c.module.position, inst: inst)
  if c.config.symbolFiles != disabledSf:
    storeInstantiation(c.encoder, c.packedRepr, s, inst)

proc addToGenericCache*(c: PContext; s: PSym; inst: PType) =
  c.graph.typeInstCache.mgetOrPut(s.itemId, @[]).add LazyType(typ: inst)
  if c.config.symbolFiles != disabledSf:
    storeTypeInst(c.encoder, c.packedRepr, s, inst)

proc sealRodFile*(c: PContext) =
  if c.config.symbolFiles != disabledSf:
    if c.graph.vm != nil:
      for (m, n) in PCtx(c.graph.vm).vmstateDiff:
        if m == c.module:
          addPragmaComputation(c, n)
    c.idgen.sealed = true # no further additions are allowed

proc rememberExpansion*(c: PContext; info: TLineInfo; expandedSym: PSym) =
  ## Templates and macros are very special in Nim; these have
  ## inlining semantics so after semantic checking they leave no trace
  ## in the sem'checked AST. This is very bad for IDE-like tooling
  ## ("find all usages of this template" would not work). We need special
  ## logic to remember macro/template expansions. This is done here and
  ## delegated to the "rod" file mechanism.
  if c.config.symbolFiles != disabledSf:
    storeExpansion(c.encoder, c.packedRepr, info, expandedSym)

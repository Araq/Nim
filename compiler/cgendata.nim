#
#
#           The Nim Compiler
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module contains the data structures for the C code generation phase.

import
  ast, ropes, options,
  lineinfos, pathutils, modulegraphs, cbuilderbase

import std/[intsets, tables, sets]

type
  TLabel* = Rope              # for the C generator a label is just a rope
  TCFileSection* = enum       # the sections a generated C file consists of
    cfsHeaders,               # section for C include file headers
    cfsFrameDefines           # section for nim frame macros
    cfsForwardTypes,          # section for C forward typedefs
    cfsTypes,                 # section for C typedefs
    cfsSeqTypes,              # section for sequence types only
                              # this is needed for strange type generation
                              # reasons
    cfsTypeInfo,              # section for type information (ag ABI checks)
    cfsProcHeaders,           # section for C procs prototypes
    cfsStrData,               # section for constant string literals
    cfsData,                  # section for C constant data
    cfsVars,                  # section for C variable declarations
    cfsProcs,                 # section for C procs that are not inline
    cfsInitProc,              # section for the C init proc
    cfsDatInitProc,           # section for the C datInit proc
    cfsTypeInit1,             # section 1 for declarations of type information
    cfsTypeInit3,             # section 3 for init of type information
    cfsDynLibInit,            # section for init of dynamic library binding
  TCTypeKind* = enum          # describes the type kind of a C type
    ctVoid, ctChar, ctBool,
    ctInt, ctInt8, ctInt16, ctInt32, ctInt64,
    ctFloat, ctFloat32, ctFloat64, ctFloat128,
    ctUInt, ctUInt8, ctUInt16, ctUInt32, ctUInt64,
    ctArray, ctPtrToArray, ctStruct, ctPtr, ctNimStr, ctNimSeq, ctProc,
    ctCString
  TCFileSections* = array[TCFileSection, Builder] # represents a generated C file
  TCProcSection* = enum       # the sections a generated C proc consists of
    cpsLocals,                # section of local variables for C proc
    cpsInit,                  # section for init of variables for C proc
    cpsStmts                  # section of local statements for C proc
  TCProcSections* = array[TCProcSection, Builder] # represents a generated C proc
  BModule* = ref TCGen
  BProc* = ref TCProc
  TBlock* = object
    id*: int                  # the ID of the label; positive means that it
    label*: Rope              # generated text for the label
                              # nil if label is not used
    sections*: TCProcSections # the code belonging
    isLoop*: bool             # whether block is a loop
    nestedTryStmts*: int16    # how many try statements is it nested into
    nestedExceptStmts*: int16 # how many except statements is it nested into
    frameLen*: int16

  TCProcFlag* = enum
    beforeRetNeeded,
    threadVarAccessed,
    hasCurFramePointer,
    noSafePoints,
    nimErrorFlagAccessed,
    nimErrorFlagDeclared,
    nimErrorFlagDisabled

  TCProc = object             # represents C proc that is currently generated
    prc*: PSym                # the Nim proc that this C proc belongs to
    flags*: set[TCProcFlag]
    lastLineInfo*: TLineInfo  # to avoid generating excessive 'nimln' statements
    currLineInfo*: TLineInfo  # AST codegen will make this superfluous
    nestedTryStmts*: seq[tuple[fin: PNode, inExcept: bool, label: Natural]]
                              # in how many nested try statements we are
                              # (the vars must be volatile then)
                              # bool is true when are in the except part of a try block
    finallySafePoints*: seq[Rope]  # For correctly cleaning up exceptions when
                                   # using return in finally statements
    labels*: Natural          # for generating unique labels in the C proc
    blocks*: seq[TBlock]      # nested blocks
    breakIdx*: int            # the block that will be exited
                              # with a regular break
    options*: TOptions        # options that should be used for code
                              # generation; this is the same as prc.options
                              # unless prc == nil
    optionsStack*: seq[(TOptions, TNoteKinds)]
    module*: BModule          # used to prevent excessive parameter passing
    withinLoop*: int          # > 0 if we are within a loop
    splitDecls*: int          # > 0 if we are in some context for C++ that
                              # requires 'T x = T()' to become 'T x; x = T()'
                              # (yes, C++ is weird like that)
    withinTryWithExcept*: int # required for goto based exception handling
    withinBlockLeaveActions*: int # complex to explain
    sigConflicts*: CountTable[string]
    inUncheckedAssignSection*: int

  TTypeSeq* = seq[PType]
  TypeCache* = Table[SigHash, Rope]
  TypeCacheWithOwner* = Table[SigHash, tuple[str: Rope, owner: int32]]

  CodegenFlag* = enum
    preventStackTrace,  # true if stack traces need to be prevented
    usesThreadVars,     # true if the module uses a thread var
    frameDeclared,      # hack for ROD support so that we don't declare
                        # a frame var twice in an init proc
    isHeaderFile,       # C source file is the header file
    includesStringh,    # C source file already includes ``<string.h>``
    objHasKidsValid     # whether we can rely on tfObjHasKids
    useAliveDataFromDce # use the `alive: IntSet` field instead of
                        # computing alive data on our own.

  BModuleList* = ref object of RootObj
    mainModProcs*, mainModInit*, otherModsInit*, mainDatInit*: Builder
    mapping*: Rope             # the generated mapping file (if requested)
    modules*: seq[BModule]     # list of all compiled modules
    modulesClosed*: seq[BModule] # list of the same compiled modules, but in the order they were closed
    forwardedProcs*: seq[PSym] # proc:s that did not yet have a body
    generatedHeader*: BModule
    typeInfoMarker*: TypeCacheWithOwner
    typeInfoMarkerV2*: TypeCacheWithOwner
    config*: ConfigRef
    graph*: ModuleGraph
    strVersion*, seqVersion*: int # version of the string/seq implementation to use

    nimtv*: Builder         # Nim thread vars; the struct body
    nimtvDeps*: seq[PType]  # type deps: every module needs whole struct
    nimtvDeclared*: IntSet  # so that every var/field exists only once
                            # in the struct
                            # 'nimtv' is incredibly hard to modularize! Best
                            # effort is to store all thread vars in a ROD
                            # section and with their type deps and load them
                            # unconditionally...
                            # nimtvDeps is VERY hard to cache because it's
                            # not a list of IDs nor can it be made to be one.
    mangledPrcs*: HashSet[string]

  TCGen = object of PPassContext # represents a C source file
    s*: TCFileSections        # sections of the C file
    flags*: set[CodegenFlag]
    module*: PSym
    filename*: AbsoluteFile
    cfilename*: AbsoluteFile  # filename of the module (including path,
                              # without extension)
    tmpBase*: Rope            # base for temp identifier generation
    typeCache*: TypeCache     # cache the generated types
    typeABICache*: HashSet[SigHash] # cache for ABI checks; reusing typeCache
                              # would be ideal but for some reason enums
                              # don't seem to get cached so it'd generate
                              # 1 ABI check per occurrence in code
    forwTypeCache*: TypeCache # cache for forward declarations of types
    declaredThings*: IntSet   # things we have declared in this .c file
    declaredProtos*: IntSet   # prototypes we have declared in this .c file
    alive*: IntSet            # symbol IDs of alive data as computed by `dce.nim`
    headerFiles*: seq[string] # needed headers to include
    typeInfoMarker*: TypeCache # needed for generating type information
    typeInfoMarkerV2*: TypeCache
    initProc*: BProc          # code for init procedure
    preInitProc*: BProc       # code executed before the init proc
    hcrCreateTypeInfosProc*: Builder # type info globals are in here when HCR=on
    inHcrInitGuard*: bool     # We are currently within a HCR reloading guard.
    hcrInitGuard*: IfBuilder
    typeStack*: TTypeSeq      # used for type generation
    dataCache*: TNodeTable
    typeNodes*, nimTypes*: int # used for type info generation
    typeNodesName*, nimTypesName*: Rope # used for type info generation
    labels*: Natural          # for generating unique module-scope names
    extensionLoaders*: array['0'..'9', Builder] # special procs for the
                                             # OpenGL wrapper
    sigConflicts*: CountTable[SigHash]
    g*: BModuleList

template config*(m: BModule): ConfigRef = m.g.config
template config*(p: BProc): ConfigRef = p.module.g.config
template vccAndC*(p: BProc): bool = p.module.config.cCompiler == ccVcc and p.module.config.backend == backendC

proc includeHeader*(this: BModule; header: string) =
  if not this.headerFiles.contains header:
    this.headerFiles.add header

proc s*(p: BProc, s: TCProcSection): var Builder {.inline.} =
  # section in the current block
  result = p.blocks[^1].sections[s]

proc procSec*(p: BProc, s: TCProcSection): var Builder {.inline.} =
  # top level proc sections
  result = p.blocks[0].sections[s]

proc initBlock*(): TBlock =
  result = TBlock()
  for i in low(result.sections)..high(result.sections):
    result.sections[i] = newBuilder("")

proc newProc*(prc: PSym, module: BModule): BProc =
  result = BProc(
    prc: prc,
    module: module,
    optionsStack: if module.initProc != nil: module.initProc.optionsStack
                  else: @[],
    options: if prc != nil: prc.options
             else: module.config.options,
    blocks: @[initBlock()],
    sigConflicts: initCountTable[string]())
  if optQuirky in result.options:
    result.flags = {nimErrorFlagDisabled}

proc newModuleList*(g: ModuleGraph): BModuleList =
  BModuleList(typeInfoMarker: initTable[SigHash, tuple[str: Rope, owner: int32]](),
    config: g.config, graph: g, nimtvDeclared: initIntSet())

iterator cgenModules*(g: BModuleList): BModule =
  for m in g.modulesClosed:
    # iterate modules in the order they were closed
    yield m

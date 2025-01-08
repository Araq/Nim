#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import
  lineinfos, platform,
  prefixmatches, pathutils, nimpaths

import std/[tables, os, strutils, strtabs, sets]
from std/terminal import isatty
from std/times import utc, fromUnix, local, getTime, format, DateTime
from std/private/globs import nativeToUnixPath

when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions]


const
  hasTinyCBackend* = defined(tinyc)
  useEffectSystem* = true
  useWriteTracking* = false
  hasFFI* = defined(nimHasLibFFI)
  copyrightYear* = "2025"

  nimEnableCovariance* = defined(nimEnableCovariance)

type                          # please make sure we have under 32 options
                              # (improves code efficiency a lot!)
  TOption* = enum             # **keep binary compatible**
    optNone, optObjCheck, optFieldCheck, optRangeCheck, optBoundsCheck,
    optOverflowCheck, optRefCheck,
    optNaNCheck, optInfCheck, optStaticBoundsCheck, optStyleCheck,
    optAssert, optLineDir, optWarns, optHints,
    optOptimizeSpeed, optOptimizeSize,
    optStackTrace, # stack tracing support
    optStackTraceMsgs, # enable custom runtime msgs via `setFrameMsg`
    optLineTrace,             # line tracing support (includes stack tracing)
    optByRef,                 # use pass by ref for objects
                              # (for interfacing with C)
    optProfiler,              # profiler turned on
    optImplicitStatic,        # optimization: implicit at compile time
                              # evaluation
    optTrMacros,              # en/disable pattern matching
    optMemTracker,
    optSinkInference          # 'sink T' inference
    optCursorInference
    optImportHidden
    optQuirky

  TOptions* = set[TOption]
  TGlobalOption* = enum
    gloptNone, optForceFullMake,
    optWasNimscript,          # redundant with `cmdNimscript`, could be removed
    optListCmd, optCompileOnly, optNoLinking,
    optCDebug,                # turn on debugging information
    optGenDynLib,             # generate a dynamic library
    optGenStaticLib,          # generate a static library
    optGenGuiApp,             # generate a GUI application
    optGenScript,             # generate a script file to compile the *.c files
    optGenCDeps,              # generate a list of *.c files to be read by CMake
    optGenMapping,            # generate a mapping file
    optRun,                   # run the compiled project
    optUseNimcache,           # save artifacts (including binary) in $nimcache
    optStyleHint,             # check that the names adhere to NEP-1
    optStyleError,            # enforce that the names adhere to NEP-1
    optStyleUsages,           # only enforce consistent **usages** of the symbol
    optSkipSystemConfigFile,  # skip the system's cfg/nims config file
    optSkipProjConfigFile,    # skip the project's cfg/nims config file
    optSkipUserConfigFile,    # skip the users's cfg/nims config file
    optSkipParentConfigFiles, # skip parent dir's cfg/nims config files
    optNoMain,                # do not generate a "main" proc
    optUseColors,             # use colors for hints, warnings, and errors
    optThreads,               # support for multi-threading
    optStdout,                # output to stdout
    optThreadAnalysis,        # thread analysis pass
    optTlsEmulation,          # thread var emulation turned on
    optGenIndex               # generate index file for documentation;
    optGenIndexOnly           # generate only index file for documentation
    optNoImportdoc            # disable loading external documentation files
    optEmbedOrigSrc           # embed the original source in the generated code
                              # also: generate header file
    optIdeDebug               # idetools: debug mode
    optIdeTerse               # idetools: use terse descriptions
    optIdeExceptionInlayHints
    optExcessiveStackTrace    # fully qualified module filenames
    optShowAllMismatches      # show all overloading resolution candidates
    optWholeProject           # for 'doc': output any dependency
    optDocInternal            # generate documentation for non-exported symbols
    optMixedMode              # true if some module triggered C++ codegen
    optDeclaredLocs           # show declaration locations in messages
    optNoNimblePath
    optHotCodeReloading
    optDynlibOverrideAll
    optSeqDestructors         # active if the implementation uses the new
                              # string/seq implementation based on destructors
    optTinyRtti               # active if we use the new "tiny RTTI"
                              # implementation
    optOwnedRefs              # active if the Nim compiler knows about 'owned'.
    optMultiMethods
    optBenchmarkVM            # Enables cpuTime() in the VM
    optProduceAsm             # produce assembler code
    optPanics                 # turn panics (sysFatal) into a process termination
    optSourcemap
    optProfileVM              # enable VM profiler
    optEnableDeepCopy         # ORC specific: enable 'deepcopy' for all types.
    optShowNonExportedFields  # for documentation: show fields that are not exported
    optJsBigInt64             # use bigints for 64-bit integers in JS

  TGlobalOptions* = set[TGlobalOption]

const
  harmlessOptions* = {optForceFullMake, optNoLinking, optRun, optUseColors, optStdout}
  genSubDir* = RelativeDir"nimcache"
  NimExt* = "nim"
  RodExt* = "rod"
  HtmlExt* = "html"
  JsonExt* = "json"
  TagsExt* = "tags"
  TexExt* = "tex"
  IniExt* = "ini"
  DefaultConfig* = RelativeFile"nim.cfg"
  DefaultConfigNims* = RelativeFile"config.nims"
  DocConfig* = RelativeFile"nimdoc.cfg"
  DocTexConfig* = RelativeFile"nimdoc.tex.cfg"
  htmldocsDir* = htmldocsDirname.RelativeDir
  docRootDefault* = "@default" # using `@` instead of `$` to avoid shell quoting complications
  oKeepVariableNames* = true
  spellSuggestSecretSauce* = -1

type
  TBackend* = enum
    backendInvalid = "" # for parseEnum
    backendC = "c"
    backendCpp = "cpp"
    backendJs = "js"
    backendObjc = "objc"
    # backendNimscript = "nimscript" # this could actually work
    # backendLlvm = "llvm" # probably not well supported; was cmdCompileToLLVM

  Command* = enum  ## Nim's commands
    cmdNone # not yet processed command
    cmdUnknown # command unmapped
    cmdCompileToC, cmdCompileToCpp, cmdCompileToOC, cmdCompileToJS,
    cmdCrun # compile and run in nimache
    cmdTcc # run the project via TCC backend
    cmdCheck # semantic checking for whole project
    cmdM     # only compile a single
    cmdParse # parse a single file (for debugging)
    cmdRod # .rod to some text representation (for debugging)
    cmdIdeTools # ide tools (e.g. nimsuggest)
    cmdNimscript # evaluate nimscript
    cmdDoc0
    cmdDoc      # convert .nim doc comments to HTML
    cmdDoc2tex  # convert .nim doc comments to LaTeX
    cmdRst2html # convert a reStructuredText file to HTML
    cmdRst2tex # convert a reStructuredText file to TeX
    cmdMd2html # convert a Markdown file to HTML
    cmdMd2tex # convert a Markdown file to TeX
    cmdJsondoc0
    cmdJsondoc
    cmdCtags
    cmdBuildindex
    cmdGendepend
    cmdDump
    cmdInteractive # start interactive session
    cmdNop
    cmdJsonscript # compile a .json build file
    # old unused: cmdInterpret, cmdDef: def feature (find definition for IDEs)

const
  cmdBackends* = {cmdCompileToC, cmdCompileToCpp, cmdCompileToOC,
                  cmdCompileToJS, cmdCrun}
  cmdDocLike* = {cmdDoc0, cmdDoc, cmdDoc2tex, cmdJsondoc0, cmdJsondoc,
                 cmdCtags, cmdBuildindex}

type
  TStringSeq* = seq[string]
  TGCMode* = enum             # the selected GC
    gcUnselected = "unselected"
    gcNone = "none"
    gcBoehm = "boehm"
    gcRegions = "regions"
    gcArc = "arc"
    gcOrc = "orc"
    gcAtomicArc = "atomicArc"
    gcMarkAndSweep = "markAndSweep"
    gcHooks = "hooks"
    gcRefc = "refc"
    gcGo = "go"
    # gcRefc and the GCs that follow it use a write barrier,
    # as far as usesWriteBarrier() is concerned

  IdeCmd* = enum
    ideNone, ideSug, ideCon, ideDef, ideUse, ideDus, ideChk, ideChkFile, ideMod,
    ideHighlight, ideOutline, ideKnown, ideMsg, ideProject, ideGlobalSymbols,
    ideRecompile, ideChanged, ideType, ideDeclaration, ideExpand, ideInlayHints

  Feature* = enum  ## experimental features; DO NOT RENAME THESE!
    dotOperators,
    callOperator,
    parallel,
    destructor,
    notnil,
    dynamicBindSym,
    forLoopMacros, # not experimental anymore; remains here for backwards compatibility
    caseStmtMacros, # ditto
    codeReordering,
    compiletimeFFI,
      ## This requires building nim with `-d:nimHasLibFFI`
      ## which itself requires `koch installdeps libffi`, see #10150
      ## Note: this feature can't be localized with {.push.}
    vmopsDanger,
    strictFuncs,
    views,
    strictNotNil,
    overloadableEnums, # deadcode
    strictEffects,
    unicodeOperators, # deadcode
    flexibleOptionalParams,
    strictDefs, # deadcode
    strictCaseObjects,
    inferGenericTypes,
    openSym, # remove nfDisabledOpenSym when this is default
    # alternative to above:
    genericsOpenSym
    vtables
    typeBoundOps

  LegacyFeature* = enum
    allowSemcheckedAstModification,
      ## Allows to modify a NimNode where the type has already been
      ## flagged with nfSem. If you actually do this, it will cause
      ## bugs.
    checkUnsignedConversions
      ## Historically and especially in version 1.0.0 of the language
      ## conversions to unsigned numbers were checked. In 1.0.4 they
      ## are not anymore.
    laxEffects
      ## Lax effects system prior to Nim 2.0.
    verboseTypeMismatch
    emitGenerics
      ## generics are emitted in the module that contains them.
      ## Useful for libraries that rely on local passC
    jsNoLambdaLifting
      ## Old transformation for closures in JS backend
    noStrictDefs
      ## disable "strictdefs"

  SymbolFilesOption* = enum
    disabledSf, writeOnlySf, readOnlySf, v2Sf, stressTest

  TSystemCC* = enum
    ccNone, ccGcc, ccNintendoSwitch, ccLLVM_Gcc, ccCLang, ccBcc, ccVcc,
    ccTcc, ccEnv, ccIcl, ccIcc, ccClangCl, ccHipcc, ccNvcc

  ExceptionSystem* = enum
    excNone,   # no exception system selected yet
    excSetjmp, # setjmp based exception handling
    excCpp,    # use C++'s native exception handling
    excGoto,   # exception handling based on goto (should become the new default for C)
    excQuirky  # quirky exception handling

  CfileFlag* {.pure.} = enum
    Cached,    ## no need to recompile this time
    External   ## file was introduced via .compile pragma

  Cfile* = object
    nimname*: string
    cname*, obj*: AbsoluteFile
    flags*: set[CfileFlag]
    customArgs*: string
  CfileList* = seq[Cfile]

  Suggest* = ref object
    section*: IdeCmd
    qualifiedPath*: seq[string]
    name*: ptr string         # not used beyond sorting purposes; name is also
                              # part of 'qualifiedPath'
    filePath*: string
    line*: int                   # Starts at 1
    column*: int                 # Starts at 0
    doc*: string           # Not escaped (yet)
    forth*: string               # type
    quality*: range[0..100]   # matching quality
    isGlobal*: bool # is a global variable
    contextFits*: bool # type/non-type context matches
    prefix*: PrefixMatch
    symkind*: byte
    scope*, localUsages*, globalUsages*: int # more usages is better
    tokenLen*: int
    version*: int
    endLine*: uint16
    endCol*: int
    inlayHintInfo*: SuggestInlayHint

  Suggestions* = seq[Suggest]

  SuggestInlayHintKind* = enum
    sihkType = "Type",
    sihkParameter = "Parameter"
    sihkException = "Exception"

  SuggestInlayHint* = ref object
    kind*: SuggestInlayHintKind
    line*: int                   # Starts at 1
    column*: int                 # Starts at 0
    label*: string
    paddingLeft*: bool
    paddingRight*: bool
    allowInsert*: bool
    tooltip*: string

  ProfileInfo* = object
    time*: float
    count*: int

  ProfileData* = ref object
    data*: TableRef[TLineInfo, ProfileInfo]

  StdOrrKind* = enum
    stdOrrStdout
    stdOrrStderr

  FilenameOption* = enum
    foAbs # absolute path, e.g.: /pathto/bar/foo.nim
    foRelProject # relative to project path, e.g.: ../foo.nim
    foCanonical # canonical module name
    foLegacyRelProj # legacy, shortest of (foAbs, foRelProject)
    foName # lastPathPart, e.g.: foo.nim
    foStacktrace # if optExcessiveStackTrace: foAbs else: foName

  ConfigRef* {.acyclic.} = ref object ## every global configuration
                          ## fields marked with '*' are subject to
                          ## the incremental compilation mechanisms
                          ## (+) means "part of the dependency"
    backend*: TBackend # set via `nim x` or `nim --backend:x`
    target*: Target       # (+)
    linesCompiled*: int   # all lines that have been compiled
    options*: TOptions    # (+)
    globalOptions*: TGlobalOptions # (+)
    macrosToExpand*: StringTableRef
    arcToExpand*: StringTableRef
    m*: MsgConfig
    filenameOption*: FilenameOption # how to render paths in compiler messages
    unitSep*: string
    evalTemplateCounter*: int
    evalMacroCounter*: int
    exitcode*: int8
    cmd*: Command  # raw command parsed as enum
    cmdInput*: string  # input command
    projectIsCmd*: bool # whether we're compiling from a command input
    implicitCmd*: bool # whether some flag triggered an implicit `command`
    selectedGC*: TGCMode       # the selected GC (+)
    exc*: ExceptionSystem
    hintProcessingDots*: bool # true for dots, false for filenames
    verbosity*: int            # how verbose the compiler is
    numberOfProcessors*: int   # number of processors
    lastCmdTime*: float        # when caas is enabled, we measure each command
    symbolFiles*: SymbolFilesOption
    spellSuggestMax*: int # max number of spelling suggestions for typos

    cppDefines*: HashSet[string] # (*)
    headerFile*: string
    nimbasePattern*: string # pattern to find nimbase.h
    features*: set[Feature]
    legacyFeatures*: set[LegacyFeature]
    arguments*: string ## the arguments to be passed to the program that
                       ## should be run
    ideCmd*: IdeCmd
    cCompiler*: TSystemCC # the used compiler
    modifiedyNotes*: TNoteKinds # notes that have been set/unset from either cmdline/configs
    cmdlineNotes*: TNoteKinds # notes that have been set/unset from cmdline
    foreignPackageNotes*: TNoteKinds
    notes*: TNoteKinds # notes after resolving all logic(defaults, verbosity)/cmdline/configs
    warningAsErrors*: TNoteKinds
    mainPackageNotes*: TNoteKinds
    mainPackageId*: int
    errorCounter*: int
    hintCounter*: int
    warnCounter*: int
    errorMax*: int
    maxLoopIterationsVM*: int ## VM: max iterations of all loops
    maxCallDepthVM*: int ## VM: max call depth
    isVmTrace*: bool
    configVars*: StringTableRef
    symbols*: StringTableRef ## We need to use a StringTableRef here as defined
                             ## symbols are always guaranteed to be style
                             ## insensitive. Otherwise hell would break lose.
    packageCache*: StringTableRef
    nimblePaths*: seq[AbsoluteDir]
    searchPaths*: seq[AbsoluteDir]
    lazyPaths*: seq[AbsoluteDir]
    outFile*: RelativeFile
    outDir*: AbsoluteDir
    jsonBuildFile*: AbsoluteFile
    prefixDir*, libpath*, nimcacheDir*: AbsoluteDir
    dllOverrides*, moduleOverrides*, cfileSpecificOptions*: StringTableRef
    projectName*: string # holds a name like 'nim'
    projectPath*: AbsoluteDir # holds a path like /home/alice/projects/nim/compiler/
    projectFull*: AbsoluteFile # projectPath/projectName
    projectIsStdin*: bool # whether we're compiling from stdin
    lastMsgWasDot*: set[StdOrrKind] # the last compiler message was a single '.'
    projectMainIdx*: FileIndex # the canonical path id of the main module
    projectMainIdx2*: FileIndex # consider merging with projectMainIdx
    command*: string # the main command (e.g. cc, check, scan, etc)
    commandArgs*: seq[string] # any arguments after the main command
    commandLine*: string
    extraCmds*: seq[string] # for writeJsonBuildInstructions
    implicitImports*: seq[string] # modules that are to be implicitly imported
    implicitIncludes*: seq[string] # modules that are to be implicitly included
    docSeeSrcUrl*: string # if empty, no seeSrc will be generated. \
    # The string uses the formatting variables `path` and `line`.
    docRoot*: string ## see nim --fullhelp for --docRoot
    docCmd*: string ## see nim --fullhelp for --docCmd

    configFiles*: seq[AbsoluteFile]     # config files (cfg,nims)
    cIncludes*: seq[AbsoluteDir]  # directories to search for included files
    cLibs*: seq[AbsoluteDir]      # directories to search for lib files
    cLinkedLibs*: seq[string]     # libraries to link

    externalToLink*: seq[string]  # files to link in addition to the file
                                  # we compiled (*)
    linkOptionsCmd*: string
    compileOptionsCmd*: seq[string]
    linkOptions*: string          # (*)
    compileOptions*: string       # (*)
    cCompilerPath*: string
    toCompile*: CfileList         # (*)
    suggestionResultHook*: proc (result: Suggest) {.closure.}
    suggestVersion*: int
    suggestMaxResults*: int
    lastLineInfo*: TLineInfo
    writelnHook*: proc (output: string) {.closure, gcsafe.}
    structuredErrorHook*: proc (config: ConfigRef; info: TLineInfo; msg: string;
                                severity: Severity) {.closure, gcsafe.}
    cppCustomNamespace*: string
    nimMainPrefix*: string
    vmProfileData*: ProfileData

    expandProgress*: bool
    expandLevels*: int
    expandNodeResult*: string
    expandPosition*: TLineInfo

    currentConfigDir*: string # used for passPP only; absolute dir
    clientProcessId*: int



proc assignIfDefault*[T](result: var T, val: T, def = default(T)) =
  ## if `result` was already assigned to a value (that wasn't `def`), this is a noop.
  if result == def: result = val

template setErrorMaxHighMaybe*(conf: ConfigRef) =
  ## do not stop after first error (but honor --errorMax if provided)
  assignIfDefault(conf.errorMax, high(int))

proc setNoteDefaults*(conf: ConfigRef, note: TNoteKind, enabled = true) =
  template fun(op) =
    conf.notes.op note
    conf.mainPackageNotes.op note
    conf.foreignPackageNotes.op note
  if enabled: fun(incl) else: fun(excl)

proc setNote*(conf: ConfigRef, note: TNoteKind, enabled = true) =
  # see also `prepareConfigNotes` which sets notes
  if note notin conf.cmdlineNotes:
    if enabled: incl(conf.notes, note) else: excl(conf.notes, note)

proc hasHint*(conf: ConfigRef, note: TNoteKind): bool =
  # ternary states instead of binary states would simplify logic
  if optHints notin conf.options: false
  elif note in {hintConf, hintProcessing}:
    # could add here other special notes like hintSource
    # these notes apply globally.
    note in conf.mainPackageNotes
  else: note in conf.notes

proc hasWarn*(conf: ConfigRef, note: TNoteKind): bool {.inline.} =
  optWarns in conf.options and note in conf.notes

proc hcrOn*(conf: ConfigRef): bool = return optHotCodeReloading in conf.globalOptions

when false:
  template depConfigFields*(fn) {.dirty.} = # deadcode
    fn(target)
    fn(options)
    fn(globalOptions)
    fn(selectedGC)

const oldExperimentalFeatures* = {dotOperators, callOperator, parallel}

const
  ChecksOptions* = {optObjCheck, optFieldCheck, optRangeCheck,
    optOverflowCheck, optBoundsCheck, optAssert, optNaNCheck, optInfCheck,
    optStyleCheck}

  DefaultOptions* = {optObjCheck, optFieldCheck, optRangeCheck,
    optBoundsCheck, optOverflowCheck, optAssert, optWarns, optRefCheck,
    optHints, optStackTrace, optLineTrace, # consider adding `optStackTraceMsgs`
    optTrMacros, optStyleCheck, optCursorInference}
  DefaultGlobalOptions* = {optThreadAnalysis, optExcessiveStackTrace,
    optJsBigInt64}

proc getSrcTimestamp(): DateTime =
  try:
    result = utc(fromUnix(parseInt(getEnv("SOURCE_DATE_EPOCH",
                                          "not a number"))))
  except ValueError:
    # Environment variable malformed.
    # https://reproducible-builds.org/specs/source-date-epoch/: "If the
    # value is malformed, the build process SHOULD exit with a non-zero
    # error code", which this doesn't do. This uses local time, because
    # that maintains compatibility with existing usage.
    result = utc getTime()

proc getDateStr*(): string =
  result = format(getSrcTimestamp(), "yyyy-MM-dd")

proc getClockStr*(): string =
  result = format(getSrcTimestamp(), "HH:mm:ss")

template newPackageCache*(): untyped =
  newStringTable(when FileSystemCaseSensitive:
                   modeCaseInsensitive
                 else:
                   modeCaseSensitive)

proc newProfileData(): ProfileData =
  ProfileData(data: newTable[TLineInfo, ProfileInfo]())

const foreignPackageNotesDefault* = {
  hintProcessing, warnUnknownMagic, hintQuitCalled, hintExecuting, hintUser, warnUser}

proc isDefined*(conf: ConfigRef; symbol: string): bool

when defined(nimDebugUtils):
  # this allows inserting debugging utilties in all modules that import `options`
  # with a single switch, which is useful when debugging compiler.
  import debugutils
  export debugutils

proc initConfigRefCommon(conf: ConfigRef) =
  conf.selectedGC = gcUnselected
  conf.verbosity = 1
  conf.hintProcessingDots = true
  conf.options = DefaultOptions
  conf.globalOptions = DefaultGlobalOptions
  conf.filenameOption = foAbs
  conf.foreignPackageNotes = foreignPackageNotesDefault
  conf.notes = NotesVerbosity[1]
  conf.mainPackageNotes = NotesVerbosity[1]

proc newConfigRef*(): ConfigRef =
  result = ConfigRef(
    cCompiler: ccGcc,
    macrosToExpand: newStringTable(modeStyleInsensitive),
    arcToExpand: newStringTable(modeStyleInsensitive),
    m: initMsgConfig(),
    cppDefines: initHashSet[string](),
    headerFile: "", features: {}, legacyFeatures: {},
    configVars: newStringTable(modeStyleInsensitive),
    symbols: newStringTable(modeStyleInsensitive),
    packageCache: newPackageCache(),
    searchPaths: @[],
    lazyPaths: @[],
    outFile: RelativeFile"",
    outDir: AbsoluteDir"",
    prefixDir: AbsoluteDir"",
    libpath: AbsoluteDir"", nimcacheDir: AbsoluteDir"",
    dllOverrides: newStringTable(modeCaseInsensitive),
    moduleOverrides: newStringTable(modeStyleInsensitive),
    cfileSpecificOptions: newStringTable(modeCaseSensitive),
    projectName: "", # holds a name like 'nim'
    projectPath: AbsoluteDir"", # holds a path like /home/alice/projects/nim/compiler/
    projectFull: AbsoluteFile"", # projectPath/projectName
    projectIsStdin: false, # whether we're compiling from stdin
    projectMainIdx: FileIndex(0'i32), # the canonical path id of the main module
    command: "", # the main command (e.g. cc, check, scan, etc)
    commandArgs: @[], # any arguments after the main command
    commandLine: "",
    implicitImports: @[], # modules that are to be implicitly imported
    implicitIncludes: @[], # modules that are to be implicitly included
    docSeeSrcUrl: "",
    cIncludes: @[],   # directories to search for included files
    cLibs: @[],       # directories to search for lib files
    cLinkedLibs: @[],  # libraries to link
    backend: backendInvalid,
    externalToLink: @[],
    linkOptionsCmd: "",
    compileOptionsCmd: @[],
    linkOptions: "",
    compileOptions: "",
    ccompilerpath: "",
    toCompile: @[],
    arguments: "",
    suggestMaxResults: 10_000,
    maxLoopIterationsVM: 10_000_000,
    maxCallDepthVM: 2_000,
    vmProfileData: newProfileData(),
    spellSuggestMax: spellSuggestSecretSauce,
    currentConfigDir: ""
  )
  initConfigRefCommon(result)
  setTargetFromSystem(result.target)
  # enable colors by default on terminals
  if terminal.isatty(stderr):
    incl(result.globalOptions, optUseColors)
  when defined(nimDebugUtils):
    onNewConfigRef(result)

proc newPartialConfigRef*(): ConfigRef =
  ## create a new ConfigRef that is only good enough for error reporting.
  when defined(nimDebugUtils):
    result = getConfigRef()
  else:
    result = ConfigRef()
    initConfigRefCommon(result)

proc cppDefine*(c: ConfigRef; define: string) =
  c.cppDefines.incl define

proc isDefined*(conf: ConfigRef; symbol: string): bool =
  if conf.symbols.hasKey(symbol):
    result = true
  elif cmpIgnoreStyle(symbol, CPU[conf.target.targetCPU].name) == 0:
    result = true
  elif cmpIgnoreStyle(symbol, platform.OS[conf.target.targetOS].name) == 0:
    result = true
  else:
    case symbol.normalize
    of "x86": result = conf.target.targetCPU == cpuI386
    of "itanium": result = conf.target.targetCPU == cpuIa64
    of "x8664": result = conf.target.targetCPU == cpuAmd64
    of "posix", "unix":
      result = conf.target.targetOS in {osLinux, osMorphos, osSkyos, osIrix, osPalmos,
                            osQnx, osAtari, osAix,
                            osHaiku, osVxWorks, osSolaris, osNetbsd,
                            osFreebsd, osOpenbsd, osDragonfly, osMacosx, osIos,
                            osAndroid, osNintendoSwitch, osFreeRTOS, osCrossos, osZephyr, osNuttX}
    of "linux":
      result = conf.target.targetOS in {osLinux, osAndroid}
    of "bsd":
      result = conf.target.targetOS in {osNetbsd, osFreebsd, osOpenbsd, osDragonfly, osCrossos}
    of "freebsd":
      result = conf.target.targetOS in {osFreebsd, osCrossos}
    of "emulatedthreadvars":
      result = platform.OS[conf.target.targetOS].props.contains(ospLacksThreadVars)
    of "msdos": result = conf.target.targetOS == osDos
    of "mswindows", "win32": result = conf.target.targetOS == osWindows
    of "macintosh":
      result = conf.target.targetOS in {osMacos, osMacosx, osIos}
    of "osx", "macosx":
      result = conf.target.targetOS in {osMacosx, osIos}
    of "sunos": result = conf.target.targetOS == osSolaris
    of "nintendoswitch":
      result = conf.target.targetOS == osNintendoSwitch
    of "freertos", "lwip":
      result = conf.target.targetOS == osFreeRTOS
    of "zephyr":
      result = conf.target.targetOS == osZephyr
    of "nuttx":
      result = conf.target.targetOS == osNuttX
    of "littleendian": result = CPU[conf.target.targetCPU].endian == littleEndian
    of "bigendian": result = CPU[conf.target.targetCPU].endian == bigEndian
    of "cpu8": result = CPU[conf.target.targetCPU].bit == 8
    of "cpu16": result = CPU[conf.target.targetCPU].bit == 16
    of "cpu32": result = CPU[conf.target.targetCPU].bit == 32
    of "cpu64": result = CPU[conf.target.targetCPU].bit == 64
    of "nimrawsetjmp":
      result = conf.target.targetOS in {osSolaris, osNetbsd, osFreebsd, osOpenbsd,
                            osDragonfly, osMacosx}
    else: result = false

template quitOrRaise*(conf: ConfigRef, msg = "") =
  # xxx in future work, consider whether to also intercept `msgQuit` calls
  if conf.isDefined("nimDebug"):
    raiseAssert msg
  else:
    quit(msg) # quits with QuitFailure

proc importantComments*(conf: ConfigRef): bool {.inline.} = conf.cmd in cmdDocLike + {cmdIdeTools}
proc usesWriteBarrier*(conf: ConfigRef): bool {.inline.} = conf.selectedGC >= gcRefc

template compilationCachePresent*(conf: ConfigRef): untyped =
  false
#  conf.symbolFiles in {v2Sf, writeOnlySf}

template optPreserveOrigSource*(conf: ConfigRef): untyped =
  optEmbedOrigSrc in conf.globalOptions

proc mainCommandArg*(conf: ConfigRef): string =
  ## This is intended for commands like check or parse
  ## which will work on the main project file unless
  ## explicitly given a specific file argument
  if conf.commandArgs.len > 0:
    result = conf.commandArgs[0]
  else:
    result = conf.projectName

proc existsConfigVar*(conf: ConfigRef; key: string): bool =
  result = hasKey(conf.configVars, key)

proc getConfigVar*(conf: ConfigRef; key: string, default = ""): string =
  result = conf.configVars.getOrDefault(key, default)

proc setConfigVar*(conf: ConfigRef; key, val: string) =
  conf.configVars[key] = val

proc getOutFile*(conf: ConfigRef; filename: RelativeFile, ext: string): AbsoluteFile =
  # explains regression https://github.com/nim-lang/Nim/issues/6583#issuecomment-625711125
  # Yet another reason why "" should not mean ".";  `""/something` should raise
  # instead of implying "" == "." as it's bug prone.
  doAssert conf.outDir.string.len > 0
  result = conf.outDir / changeFileExt(filename, ext)

proc absOutFile*(conf: ConfigRef): AbsoluteFile =
  doAssert not conf.outDir.isEmpty
  doAssert not conf.outFile.isEmpty
  result = conf.outDir / conf.outFile
  when defined(posix):
    if dirExists(result.string): result.string.add ".out"

proc prepareToWriteOutput*(conf: ConfigRef): AbsoluteFile =
  ## Create the output directory and returns a full path to the output file
  result = conf.absOutFile
  createDir result.string.parentDir

proc getPrefixDir*(conf: ConfigRef): AbsoluteDir =
  ## Gets the prefix dir, usually the parent directory where the binary resides.
  ##
  ## This is overridden by some tools (namely nimsuggest) via the ``conf.prefixDir``
  ## field.
  ## This should resolve to root of nim sources, whether running nim from a local
  ##  clone or using installed nim, so that these exist: `result/doc/advopt.txt`
  ## and `result/lib/system.nim`
  if not conf.prefixDir.isEmpty: result = conf.prefixDir
  else:
    let binParent = AbsoluteDir splitPath(getAppDir()).head
    when defined(posix):
      if binParent == AbsoluteDir"/usr":
        result = AbsoluteDir"/usr/lib/nim"
      elif binParent == AbsoluteDir"/usr/local":
        result = AbsoluteDir"/usr/local/lib/nim"
      else:
        result = binParent
    else:
      result = binParent

proc setDefaultLibpath*(conf: ConfigRef) =
  # set default value (can be overwritten):
  if conf.libpath.isEmpty:
    # choose default libpath:
    var prefix = getPrefixDir(conf)
    conf.libpath = prefix / RelativeDir"lib"

    # Special rule to support other tools (nimble) which import the compiler
    # modules and make use of them.
    let realNimPath = findExe("nim")
    # Find out if $nim/../../lib/system.nim exists.
    let parentNimLibPath = realNimPath.parentDir.parentDir / "lib"
    if not fileExists(conf.libpath.string / "system.nim") and
        fileExists(parentNimLibPath / "system.nim"):
      conf.libpath = AbsoluteDir parentNimLibPath

proc canonicalizePath*(conf: ConfigRef; path: AbsoluteFile): AbsoluteFile =
  result = AbsoluteFile path.string.expandFilename

proc setFromProjectName*(conf: ConfigRef; projectName: string) =
  try:
    conf.projectFull = canonicalizePath(conf, AbsoluteFile projectName)
  except OSError:
    conf.projectFull = AbsoluteFile projectName
  let p = splitFile(conf.projectFull)
  let dir = if p.dir.isEmpty: AbsoluteDir getCurrentDir() else: p.dir
  try:
    conf.projectPath = AbsoluteDir canonicalizePath(conf, AbsoluteFile dir)
  except OSError:
    conf.projectPath = dir
  conf.projectName = p.name

proc removeTrailingDirSep*(path: string): string =
  if (path.len > 0) and (path[^1] == DirSep):
    result = substr(path, 0, path.len - 2)
  else:
    result = path

proc disableNimblePath*(conf: ConfigRef) =
  incl conf.globalOptions, optNoNimblePath
  conf.lazyPaths.setLen(0)
  conf.nimblePaths.setLen(0)

proc clearNimblePath*(conf: ConfigRef) =
  conf.lazyPaths.setLen(0)
  conf.nimblePaths.setLen(0)

include packagehandling

proc getOsCacheDir(): string =
  when defined(posix):
    result = getEnv("XDG_CACHE_HOME", getHomeDir() / ".cache") / "nim"
  else:
    result = getHomeDir() / genSubDir.string

proc getNimcacheDir*(conf: ConfigRef): AbsoluteDir =
  proc nimcacheSuffix(conf: ConfigRef): string =
    if conf.cmd == cmdCheck: "_check"
    elif isDefined(conf, "release") or isDefined(conf, "danger"): "_r"
    else: "_d"

  # XXX projectName should always be without a file extension!
  result =
    if not conf.nimcacheDir.isEmpty:
      conf.nimcacheDir
    elif conf.backend == backendJs:
      if conf.outDir.isEmpty:
        conf.projectPath / genSubDir
      else:
        conf.outDir / genSubDir
    else:
      AbsoluteDir(getOsCacheDir() / splitFile(conf.projectName).name &
        nimcacheSuffix(conf))

proc pathSubs*(conf: ConfigRef; p, config: string): string =
  let home = removeTrailingDirSep(os.getHomeDir())
  result = unixToNativePath(p % [
    "nim", getPrefixDir(conf).string,
    "lib", conf.libpath.string,
    "home", home,
    "config", config,
    "projectname", conf.projectName,
    "projectpath", conf.projectPath.string,
    "projectdir", conf.projectPath.string,
    "nimcache", getNimcacheDir(conf).string]).expandTilde

iterator nimbleSubs*(conf: ConfigRef; p: string): string =
  let pl = p.toLowerAscii
  if "$nimblepath" in pl or "$nimbledir" in pl:
    for i in countdown(conf.nimblePaths.len-1, 0):
      let nimblePath = removeTrailingDirSep(conf.nimblePaths[i].string)
      yield p % ["nimblepath", nimblePath, "nimbledir", nimblePath]
  else:
    yield p

proc toGeneratedFile*(conf: ConfigRef; path: AbsoluteFile,
                      ext: string): AbsoluteFile =
  ## converts "/home/a/mymodule.nim", "rod" to "/home/a/nimcache/mymodule.rod"
  result = getNimcacheDir(conf) / RelativeFile path.string.splitPath.tail.changeFileExt(ext)

proc completeGeneratedFilePath*(conf: ConfigRef; f: AbsoluteFile,
                                createSubDir: bool = true): AbsoluteFile =
  ## Return an absolute path of a generated intermediary file.
  ## Optionally creates the cache directory if `createSubDir` is `true`.
  let subdir = getNimcacheDir(conf)
  if createSubDir:
    try:
      createDir(subdir.string)
    except OSError:
      conf.quitOrRaise "cannot create directory: " & subdir.string
  result = subdir / RelativeFile f.string.splitPath.tail

proc rawFindFile(conf: ConfigRef; f: RelativeFile; suppressStdlib: bool): AbsoluteFile =
  for it in conf.searchPaths:
    if suppressStdlib and it.string.startsWith(conf.libpath.string):
      continue
    result = it / f
    if fileExists(result):
      return canonicalizePath(conf, result)
  result = AbsoluteFile""

proc rawFindFile2(conf: ConfigRef; f: RelativeFile): AbsoluteFile =
  for i, it in conf.lazyPaths:
    result = it / f
    if fileExists(result):
      # bring to front
      for j in countdown(i, 1):
        swap(conf.lazyPaths[j], conf.lazyPaths[j-1])

      return canonicalizePath(conf, result)
  result = AbsoluteFile""

template patchModule(conf: ConfigRef) {.dirty.} =
  if not result.isEmpty and conf.moduleOverrides.len > 0:
    let key = getPackageName(conf, result.string) & "_" & splitFile(result).name
    if conf.moduleOverrides.hasKey(key):
      let ov = conf.moduleOverrides[key]
      if ov.len > 0: result = AbsoluteFile(ov)

const stdlibDirs* = [
  "pure", "core", "arch",
  "pure/collections",
  "pure/concurrency",
  "pure/unidecode", "impure",
  "wrappers", "wrappers/linenoise",
  "windows", "posix", "js",
  "deprecated/pure"]

const
  pkgPrefix = "pkg/"
  stdPrefix* = "std/"

proc getRelativePathFromConfigPath*(conf: ConfigRef; f: AbsoluteFile, isTitle = false): RelativeFile =
  result = RelativeFile("")
  let f = $f
  if isTitle:
    for dir in stdlibDirs:
      let path = conf.libpath.string / dir / f.lastPathPart
      if path.cmpPaths(f) == 0:
        return RelativeFile(stdPrefix & f.splitFile.name)
  template search(paths) =
    for it in paths:
      let it = $it
      if f.isRelativeTo(it):
        return relativePath(f, it).RelativeFile
  search(conf.searchPaths)
  search(conf.lazyPaths)

proc findFile*(conf: ConfigRef; f: string; suppressStdlib = false): AbsoluteFile =
  if f.isAbsolute:
    result = if f.fileExists: AbsoluteFile(f) else: AbsoluteFile""
  else:
    result = rawFindFile(conf, RelativeFile f, suppressStdlib)
    if result.isEmpty:
      result = rawFindFile(conf, RelativeFile f.toLowerAscii, suppressStdlib)
      if result.isEmpty:
        result = rawFindFile2(conf, RelativeFile f)
        if result.isEmpty:
          result = rawFindFile2(conf, RelativeFile f.toLowerAscii)
  patchModule(conf)

proc findModule*(conf: ConfigRef; modulename, currentModule: string): AbsoluteFile =
  # returns path to module
  var m = addFileExt(modulename, NimExt)
  var hasRelativeDot = false
  if m.startsWith(pkgPrefix):
    result = findFile(conf, m.substr(pkgPrefix.len), suppressStdlib = true)
  else:
    if m.startsWith(stdPrefix):
      result = AbsoluteFile("")
      let stripped = m.substr(stdPrefix.len)
      for candidate in stdlibDirs:
        let path = (conf.libpath.string / candidate / stripped)
        if fileExists(path):
          result = AbsoluteFile path
          break
    else: # If prefixed with std/ why would we add the current module path!
      let currentPath = currentModule.splitFile.dir
      result = AbsoluteFile currentPath / m
      if m.startsWith('.') and not fileExists(result):
        result = AbsoluteFile ""
        hasRelativeDot = true

    if not fileExists(result) and not hasRelativeDot:
      result = findFile(conf, m)
  patchModule(conf)

proc findProjectNimFile*(conf: ConfigRef; pkg: string): string =
  const extensions = [".nims", ".cfg", ".nimcfg", ".nimble"]
  var
    candidates: seq[string] = @[]
    dir = pkg
    prev = dir
    nimblepkg = ""
  let pkgname = pkg.lastPathPart()
  while true:
    for k, f in os.walkDir(dir, relative = true):
      if k == pcFile and f != "config.nims":
        let (_, name, ext) = splitFile(f)
        if ext in extensions:
          let x = changeFileExt(dir / name, ".nim")
          if fileExists(x):
            candidates.add x
          if ext == ".nimble":
            if nimblepkg.len == 0:
              nimblepkg = name
              # Since nimble packages can have their source in a subfolder,
              # check the last folder we were in for a possible match.
              if dir != prev:
                let x = prev / x.extractFilename()
                if fileExists(x):
                  candidates.add x
            else:
              # If we found more than one nimble file, chances are that we
              # missed the real project file, or this is an invalid nimble
              # package. Either way, bailing is the better choice.
              return ""
    let pkgname = if nimblepkg.len > 0: nimblepkg else: pkgname
    for c in candidates:
      if pkgname in c.extractFilename(): return c
    if candidates.len > 0:
      return candidates[0]
    prev = dir
    dir = parentDir(dir)
    if dir == "": break
  return ""

proc canonicalImportAux*(conf: ConfigRef, file: AbsoluteFile): string =
  ##[
  Shows the canonical module import, e.g.:
  system, std/tables, fusion/pointers, system/assertions, std/private/asciitables
  ]##
  var ret = getRelativePathFromConfigPath(conf, file, isTitle = true)
  let dir = getNimbleFile(conf, $file).parentDir.AbsoluteDir
  if not dir.isEmpty:
    let relPath = relativeTo(file, dir)
    if not relPath.isEmpty and (ret.isEmpty or relPath.string.len < ret.string.len):
      ret = relPath
  if ret.isEmpty:
    ret = relativeTo(file, conf.projectPath)
  result = ret.string

proc canonicalImport*(conf: ConfigRef, file: AbsoluteFile): string =
  let ret = canonicalImportAux(conf, file)
  result = ret.nativeToUnixPath.changeFileExt("")

proc canonDynlibName(s: string): string =
  let start = if s.startsWith("lib"): 3 else: 0
  let ende = strutils.find(s, {'(', ')', '.'})
  if ende >= 0:
    result = s.substr(start, ende-1)
  else:
    result = s.substr(start)

proc inclDynlibOverride*(conf: ConfigRef; lib: string) =
  conf.dllOverrides[lib.canonDynlibName] = "true"

proc isDynlibOverride*(conf: ConfigRef; lib: string): bool =
  result = optDynlibOverrideAll in conf.globalOptions or
     conf.dllOverrides.hasKey(lib.canonDynlibName)

proc showNonExportedFields*(conf: ConfigRef) =
  incl(conf.globalOptions, optShowNonExportedFields)

proc expandDone*(conf: ConfigRef): bool =
  result = conf.ideCmd == ideExpand and conf.expandLevels == 0 and conf.expandProgress

proc parseIdeCmd*(s: string): IdeCmd =
  case s:
  of "sug": ideSug
  of "con": ideCon
  of "def": ideDef
  of "use": ideUse
  of "dus": ideDus
  of "chk": ideChk
  of "chkFile": ideChkFile
  of "mod": ideMod
  of "highlight": ideHighlight
  of "outline": ideOutline
  of "known": ideKnown
  of "msg": ideMsg
  of "project": ideProject
  of "globalSymbols": ideGlobalSymbols
  of "recompile": ideRecompile
  of "changed": ideChanged
  of "type": ideType
  else: ideNone

proc `$`*(c: IdeCmd): string =
  case c:
  of ideSug: "sug"
  of ideCon: "con"
  of ideDef: "def"
  of ideUse: "use"
  of ideDus: "dus"
  of ideChk: "chk"
  of ideChkFile: "chkFile"
  of ideMod: "mod"
  of ideNone: "none"
  of ideHighlight: "highlight"
  of ideOutline: "outline"
  of ideKnown: "known"
  of ideMsg: "msg"
  of ideProject: "project"
  of ideGlobalSymbols: "globalSymbols"
  of ideDeclaration: "declaration"
  of ideExpand: "expand"
  of ideRecompile: "recompile"
  of ideChanged: "changed"
  of ideType: "type"
  of ideInlayHints: "inlayHints"

proc floatInt64Align*(conf: ConfigRef): int16 =
  ## Returns either 4 or 8 depending on reasons.
  if conf != nil and conf.target.targetCPU == cpuI386:
    #on Linux/BSD i386, double are aligned to 4bytes (except with -malign-double)
    if conf.target.targetOS != osWindows:
      # on i386 for all known POSIX systems, 64bits ints are aligned
      # to 4bytes (except with -malign-double)
      return 4
  return 8

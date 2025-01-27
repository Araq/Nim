#
#
#           The Nim Compiler
#        (c) Copyright 2018 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module contains the `TMsgKind` enum as well as the
## `TLineInfo` object.

import ropes, pathutils
import std/[hashes, tables]

const
  explanationsBaseUrl* = "https://nim-lang.github.io/Nim"
    # was: "https://nim-lang.org/docs" but we're now usually showing devel docs
    # instead of latest release docs.

proc createDocLink*(urlSuffix: string): string =
  # os.`/` is not appropriate for urls.
  result = explanationsBaseUrl
  if urlSuffix.len > 0 and urlSuffix[0] == '/':
    result.add urlSuffix
  else:
    result.add "/" & urlSuffix

type
  TMsgKind* = enum
    # fatal errors
    errUnknown, errFatal, errInternal,
    # non-fatal errors
    errIllFormedAstX, errCannotOpenFile,
    errXExpected,
    errRstMissingClosing,
    errRstGridTableNotImplemented,
    errRstMarkdownIllformedTable,
    errRstIllformedTable,
    errRstNewSectionExpected,
    errRstGeneralParseError,
    errRstInvalidDirectiveX,
    errRstInvalidField,
    errRstFootnoteMismatch,
    errRstSandboxedDirective,
    errProveInit, # deadcode
    errGenerated,
    errFailedMove,
    errUser,
    # warnings
    warnCannotOpenFile = "CannotOpenFile", warnOctalEscape = "OctalEscape",
    warnXIsNeverRead = "XIsNeverRead", warnXmightNotBeenInit = "XmightNotBeenInit",
    warnDeprecated = "Deprecated", warnConfigDeprecated = "ConfigDeprecated",
    warnDotLikeOps = "DotLikeOps",
    warnSmallLshouldNotBeUsed = "SmallLshouldNotBeUsed", warnUnknownMagic = "UnknownMagic",
    warnRstRedefinitionOfLabel = "RedefinitionOfLabel",
    warnRstUnknownSubstitutionX = "UnknownSubstitutionX",
    warnRstAmbiguousLink = "AmbiguousLink",
    warnRstBrokenLink = "BrokenLink",
    warnRstLanguageXNotSupported = "LanguageXNotSupported",
    warnRstFieldXNotSupported = "FieldXNotSupported",
    warnRstUnusedImportdoc = "UnusedImportdoc",
    warnRstStyle = "warnRstStyle",
    warnCommentXIgnored = "CommentXIgnored",
    warnTypelessParam = "TypelessParam",
    warnUseBase = "UseBase", warnWriteToForeignHeap = "WriteToForeignHeap",
    warnUnsafeCode = "UnsafeCode", warnUnusedImportX = "UnusedImport",
    warnInheritFromException = "InheritFromException", warnEachIdentIsTuple = "EachIdentIsTuple",
    warnUnsafeSetLen = "UnsafeSetLen", warnUnsafeDefault = "UnsafeDefault",
    warnProveInit = "ProveInit", warnProveField = "ProveField", warnProveIndex = "ProveIndex",
    warnUnreachableElse = "UnreachableElse", warnUnreachableCode = "UnreachableCode",
    warnStaticIndexCheck = "IndexCheck", warnGcUnsafe = "GcUnsafe", warnGcUnsafe2 = "GcUnsafe2",
    warnUninit = "Uninit", warnGcMem = "GcMem", warnDestructor = "Destructor",
    warnLockLevel = "LockLevel", # deadcode
    warnResultShadowed = "ResultShadowed",
    warnInconsistentSpacing = "Spacing",  warnCaseTransition = "CaseTransition",
    warnCycleCreated = "CycleCreated", warnObservableStores = "ObservableStores",
    warnStrictNotNil = "StrictNotNil",
    warnResultUsed = "ResultUsed",
    warnCannotOpen = "CannotOpen",
    warnFileChanged = "FileChanged",
    warnSuspiciousEnumConv = "EnumConv",
    warnAnyEnumConv = "AnyEnumConv",
    warnHoleEnumConv = "HoleEnumConv",
    warnCstringConv = "CStringConv",
    warnPtrToCstringConv = "PtrToCstringConv",
    warnEffect = "Effect",
    warnCastSizes = "CastSizes", # deadcode
    warnAboveMaxSizeSet = "AboveMaxSizeSet",
    warnImplicitTemplateRedefinition = "ImplicitTemplateRedefinition",
    warnUnnamedBreak = "UnnamedBreak",
    warnStmtListLambda = "StmtListLambda",
    warnBareExcept = "BareExcept",
    warnImplicitDefaultValue = "ImplicitDefaultValue",
    warnIgnoredSymbolInjection = "IgnoredSymbolInjection",
    warnStdPrefix = "StdPrefix"
    warnUnknownNotes = "UnknownNotes"
    warnUser = "User",
    warnGlobalVarConstructorTemporary = "GlobalVarConstructorTemporary",
    # hints
    hintSuccess = "Success", hintSuccessX = "SuccessX",
    hintCC = "CC",
    hintXDeclaredButNotUsed = "XDeclaredButNotUsed", hintDuplicateModuleImport = "DuplicateModuleImport",
    hintXCannotRaiseY = "XCannotRaiseY", hintConvToBaseNotNeeded = "ConvToBaseNotNeeded",
    hintConvFromXtoItselfNotNeeded = "ConvFromXtoItselfNotNeeded", hintExprAlwaysX = "ExprAlwaysX",
    hintQuitCalled = "QuitCalled", hintProcessing = "Processing", hintProcessingStmt = "ProcessingStmt", hintCodeBegin = "CodeBegin",
    hintCodeEnd = "CodeEnd", hintConf = "Conf", hintPath = "Path",
    hintConditionAlwaysTrue = "CondTrue", hintConditionAlwaysFalse = "CondFalse", hintName = "Name",
    hintPattern = "Pattern", hintExecuting = "Exec", hintLinking = "Link", hintDependency = "Dependency",
    hintSource = "Source", hintPerformance = "Performance", hintStackTrace = "StackTrace",
    hintGCStats = "GCStats", hintGlobalVar = "GlobalVar", hintExpandMacro = "ExpandMacro",
    hintUser = "User", hintUserRaw = "UserRaw", hintExtendedContext = "ExtendedContext",
    hintMsgOrigin = "MsgOrigin", # since 1.3.5
    hintDeclaredLoc = "DeclaredLoc", # since 1.5.1

const
  MsgKindToStr*: array[TMsgKind, string] = [
    errUnknown: "unknown error",
    errFatal: "fatal error: $1",
    errInternal: "internal error: $1",
    errIllFormedAstX: "illformed AST: $1",
    errCannotOpenFile: "cannot open '$1'",
    errXExpected: "'$1' expected",
    errRstMissingClosing: "$1",
    errRstGridTableNotImplemented: "grid table is not implemented",
    errRstMarkdownIllformedTable: "illformed delimiter row of a markdown table",
    errRstIllformedTable: "Illformed table: $1",
    errRstNewSectionExpected: "new section expected $1",
    errRstGeneralParseError: "general parse error",
    errRstInvalidDirectiveX: "invalid directive: '$1'",
    errRstInvalidField: "invalid field: $1",
    errRstFootnoteMismatch: "number of footnotes and their references don't match: $1",
    errRstSandboxedDirective: "disabled directive: '$1'",
    errProveInit: "Cannot prove that '$1' is initialized.",  # deadcode
    errGenerated: "$1",
    errFailedMove: "$1",
    errUser: "$1",
    warnCannotOpenFile: "cannot open '$1'",
    warnOctalEscape: "octal escape sequences do not exist; leading zero is ignored",
    warnXIsNeverRead: "'$1' is never read",
    warnXmightNotBeenInit: "'$1' might not have been initialized",
    warnDeprecated: "$1",
    warnConfigDeprecated: "config file '$1' is deprecated",
    warnDotLikeOps: "$1",
    warnSmallLshouldNotBeUsed: "'l' should not be used as an identifier; may look like '1' (one)",
    warnUnknownMagic: "unknown magic '$1' might crash the compiler",
    warnRstRedefinitionOfLabel: "redefinition of label '$1'",
    warnRstUnknownSubstitutionX: "unknown substitution '$1'",
    warnRstAmbiguousLink: "ambiguous doc link $1",
    warnRstBrokenLink: "broken link '$1'",
    warnRstLanguageXNotSupported: "language '$1' not supported",
    warnRstFieldXNotSupported: "field '$1' not supported",
    warnRstUnusedImportdoc: "importdoc for '$1' is not used",
    warnRstStyle: "RST style: $1",
    warnCommentXIgnored: "comment '$1' ignored",
    warnTypelessParam: "", # deadcode
    warnUseBase: "use {.base.} for base methods; baseless methods are deprecated",
    warnWriteToForeignHeap: "write to foreign heap",
    warnUnsafeCode: "unsafe code: '$1'",
    warnUnusedImportX: "imported and not used: '$1'",
    warnInheritFromException: "inherit from a more precise exception type like ValueError, " &
      "IOError or OSError. If these don't suit, inherit from CatchableError or Defect.",
    warnEachIdentIsTuple: "each identifier is a tuple",
    warnUnsafeSetLen: "setLen can potentially expand the sequence, " &
                      "but the element type '$1' doesn't have a valid default value",
    warnUnsafeDefault: "The '$1' type doesn't have a valid default value",
    warnProveInit: "Cannot prove that '$1' is initialized. This will become a compile time error in the future.",
    warnProveField: "cannot prove that field '$1' is accessible",
    warnProveIndex: "cannot prove index '$1' is valid",
    warnUnreachableElse: "unreachable else, all cases are already covered",
    warnUnreachableCode: "unreachable code after 'return' statement or '{.noReturn.}' proc",
    warnStaticIndexCheck: "$1",
    warnGcUnsafe: "not GC-safe: '$1'",
    warnGcUnsafe2: "$1",
    warnUninit: "use explicit initialization of '$1' for clarity",
    warnGcMem: "'$1' uses GC'ed memory",
    warnDestructor: "usage of a type with a destructor in a non destructible context. This will become a compile time error in the future.",
    warnLockLevel: "$1", # deadcode
    warnResultShadowed: "Special variable 'result' is shadowed.",
    warnInconsistentSpacing: "Number of spaces around '$#' is not consistent",
    warnCaseTransition: "Potential object case transition, instantiate new object instead",
    warnCycleCreated: "$1",
    warnObservableStores: "observable stores to '$1'",
    warnStrictNotNil: "$1",
    warnResultUsed: "used 'result' variable",
    warnCannotOpen: "cannot open: $1",
    warnFileChanged: "file changed: $1",
    warnSuspiciousEnumConv: "$1",
    warnAnyEnumConv: "$1",
    warnHoleEnumConv: "$1",
    warnCstringConv: "$1",
    warnPtrToCstringConv: "unsafe conversion to 'cstring' from '$1'; Use a `cast` operation like `cast[cstring](x)`; this will become a compile time error in the future",
    warnEffect: "$1",
    warnCastSizes: "$1", # deadcode
    warnAboveMaxSizeSet: "$1",
    warnImplicitTemplateRedefinition: "template '$1' is implicitly redefined; this is deprecated, add an explicit .redefine pragma",
    warnUnnamedBreak: "Using an unnamed break in a block is deprecated; Use a named block with a named break instead",
    warnStmtListLambda: "statement list expression assumed to be anonymous proc; this is deprecated, use `do (): ...` or `proc () = ...` instead",
    warnBareExcept: "$1",
    warnImplicitDefaultValue: "$1",
    warnIgnoredSymbolInjection: "$1",
    warnStdPrefix: "$1 needs the 'std' prefix",
    warnUnknownNotes: "$1",
    warnUser: "$1",
    warnGlobalVarConstructorTemporary: "global variable '$1' initialization requires a temporary variable",
    hintSuccess: "operation successful: $#",
    # keep in sync with `testament.isSuccess`
    hintSuccessX: "$build\n$loc lines; ${sec}s; $mem; proj: $project; out: $output",
    hintCC: "CC: $1",
    hintXDeclaredButNotUsed: "'$1' is declared but not used",
    hintDuplicateModuleImport: "$1",
    hintXCannotRaiseY: "$1",
    hintConvToBaseNotNeeded: "conversion to base object is not needed",
    hintConvFromXtoItselfNotNeeded: "conversion from $1 to itself is pointless",
    hintExprAlwaysX: "expression evaluates always to '$1'",
    hintQuitCalled: "quit() called",
    hintProcessing: "$1",
    hintProcessingStmt: "$1",
    hintCodeBegin: "generated code listing:",
    hintCodeEnd: "end of listing",
    hintConf: "used config file '$1'",
    hintPath: "added path: '$1'",
    hintConditionAlwaysTrue: "condition is always true: '$1'",
    hintConditionAlwaysFalse: "condition is always false: '$1'",
    hintName: "$1",
    hintPattern: "$1",
    hintExecuting: "$1",
    hintLinking: "$1",
    hintDependency: "$1",
    hintSource: "$1",
    hintPerformance: "$1",
    hintStackTrace: "$1",
    hintGCStats: "$1",
    hintGlobalVar: "global variable declared here",
    hintExpandMacro: "expanded macro: $1",
    hintUser: "$1",
    hintUserRaw: "$1",
    hintExtendedContext: "$1",
    hintMsgOrigin: "$1",
    hintDeclaredLoc: "$1"
  ]

const
  fatalMsgs* = {errUnknown..errInternal}
  errMin* = errUnknown
  errMax* = errUser
  warnMin* = warnCannotOpenFile
  warnMax* = pred(hintSuccess)
  hintMin* = hintSuccess
  hintMax* = high(TMsgKind)
  rstWarnings* = {warnRstRedefinitionOfLabel..warnRstStyle}

type
  TNoteKind* = range[warnMin..hintMax] # "notes" are warnings or hints
  TNoteKinds* = set[TNoteKind]

proc computeNotesVerbosity(): array[0..3, TNoteKinds] =
  result = default(array[0..3, TNoteKinds])
  result[3] = {low(TNoteKind)..high(TNoteKind)} - {warnObservableStores, warnResultUsed, warnAnyEnumConv, warnBareExcept, warnStdPrefix}
  result[2] = result[3] - {hintStackTrace, hintExtendedContext, hintDeclaredLoc, hintProcessingStmt}
  result[1] = result[2] - {warnProveField, warnProveIndex,
    warnGcUnsafe, hintPath, hintDependency, hintCodeBegin, hintCodeEnd,
    hintSource, hintGlobalVar, hintGCStats, hintMsgOrigin, hintPerformance}
  result[0] = result[1] - {hintSuccessX, hintSuccess, hintConf,
    hintProcessing, hintPattern, hintExecuting, hintLinking, hintCC}

const
  NotesVerbosity* = computeNotesVerbosity()
  errXMustBeCompileTime* = "'$1' can only be used in compile-time context"
  errArgsNeedRunOption* = "arguments can only be given if the '--run' option is selected"
  errFloatToString* = "cannot convert '$1' to '$2'"

type
  TFileInfo* = object
    fullPath*: AbsoluteFile    # This is a canonical full filesystem path
    projPath*: RelativeFile    # This is relative to the project's root
    shortName*: string         # short name of the module
    quotedName*: Rope          # cached quoted short name for codegen
                               # purposes
    quotedFullName*: Rope      # cached quoted full name for codegen
                               # purposes

    lines*: seq[string]        # the source code of the module
                               #   used for better error messages and
                               #   embedding the original source in the
                               #   generated code
    dirtyFile*: AbsoluteFile   # the file that is actually read into memory
                               # and parsed; usually "" but is used
                               # for 'nimsuggest'
    hash*: string              # the checksum of the file
    dirty*: bool               # for 'nimpretty' like tooling
    when defined(nimpretty):
      fullContent*: string
  FileIndex* = distinct int32
  TLineInfo* = object          # This is designed to be as small as possible,
                               # because it is used
                               # in syntax nodes. We save space here by using
                               # two int16 and an int32.
                               # On 64 bit and on 32 bit systems this is
                               # only 8 bytes.
    line*: uint16
    col*: int16
    fileIndex*: FileIndex
    when defined(nimpretty):
      offsetA*, offsetB*: int
      commentOffsetA*, commentOffsetB*: int

  TErrorOutput* = enum
    eStdOut
    eStdErr

  TErrorOutputs* = set[TErrorOutput]

  ERecoverableError* = object of ValueError
  ESuggestDone* = object of ValueError

proc `==`*(a, b: FileIndex): bool {.borrow.}

proc hash*(i: TLineInfo): Hash =
  hash (i.line.int, i.col.int, i.fileIndex.int)

proc raiseRecoverableError*(msg: string) {.noinline, noreturn.} =
  raise newException(ERecoverableError, msg)

const
  InvalidFileIdx* = FileIndex(-1)
  unknownLineInfo* = TLineInfo(line: 0, col: -1, fileIndex: InvalidFileIdx)

type
  Severity* {.pure.} = enum ## VS Code only supports these three
    Hint, Warning, Error

const
  trackPosInvalidFileIdx* = FileIndex(-2) # special marker so that no suggestions
                                          # are produced within comments and string literals
  commandLineIdx* = FileIndex(-3)

type
  MsgConfig* = object ## does not need to be stored in the incremental cache
    trackPos*: TLineInfo
    trackPosAttached*: bool ## whether the tracking position was attached to
                            ## some close token.

    errorOutputs*: TErrorOutputs
    msgContext*: seq[tuple[info: TLineInfo, detail: string]]
    lastError*: TLineInfo
    filenameToIndexTbl*: Table[string, FileIndex]
    fileInfos*: seq[TFileInfo]
    systemFileIdx*: FileIndex


proc initMsgConfig*(): MsgConfig =
  result = MsgConfig(msgContext: @[], lastError: unknownLineInfo,
                     filenameToIndexTbl: initTable[string, FileIndex](),
                     fileInfos: @[], errorOutputs: {eStdOut, eStdErr}
  )
  result.filenameToIndexTbl["???"] = FileIndex(-1)

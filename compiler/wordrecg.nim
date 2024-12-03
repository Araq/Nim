#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# This module contains a word recognizer, i.e. a simple
# procedure which maps special words to an enumeration.
# It is primarily needed because Pascal's case statement
# does not support strings. Without this the code would
# be slow and unreadable.

type
  TSpecialWord* = enum
    wInvalid = "",
    wAddr = "addr", wAnd = "and", wAs = "as", wAsm = "asm",
    wBind = "bind", wBlock = "block", wBreak = "break", wCase = "case", wCast = "cast",
    wConcept = "concept", wConst = "const", wContinue = "continue", wConverter = "converter",
    wDefer = "defer", wDiscard = "discard", wDistinct = "distinct", wDiv = "div", wDo = "do",
    wElif = "elif", wElse = "else", wEnd = "end", wEnum = "enum", wExcept = "except",
    wExport = "export", wFinally = "finally", wFor = "for", wFrom = "from", wFunc = "func",
    wIf = "if", wImport = "import", wIn = "in", wInclude = "include", wInterface = "interface",
    wIs = "is", wIsnot = "isnot",  wIterator = "iterator", wLet = "let", wMacro = "macro",
    wMethod = "method", wMixin = "mixin", wMod = "mod", wNil = "nil", wNot = "not", wNotin = "notin",
    wObject = "object", wOf = "of", wOr = "or", wOut = "out", wProc = "proc", wPtr = "ptr",
    wRaise = "raise", wRef = "ref", wReturn = "return", wShl = "shl", wShr = "shr", wStatic = "static",
    wTemplate = "template", wTry = "try", wTuple = "tuple", wType = "type", wUsing = "using",
    wVar = "var", wWhen = "when", wWhile = "while", wXor = "xor", wYield = "yield",

    wColon = ":", wColonColon = "::", wEquals = "=", wDot = ".", wDotDot = "..",
    wStar = "*", wMinus = "-",
    wUnderscore = "_",
    wMagic = "magic", wThread = "thread", wFinal = "final", wProfiler = "profiler",
    wMemTracker = "memtracker", wObjChecks = "objchecks",
    wIntDefine = "intdefine", wStrDefine = "strdefine", wBoolDefine = "booldefine",
    wCursor = "cursor", wNoalias = "noalias", wEffectsOf = "effectsOf",
    wUncheckedAssign = "uncheckedAssign", wRunnableExamples = "runnableExamples",

    wImmediate = "immediate", wConstructor = "constructor", wDestructor = "destructor",
    wDelegator = "delegator", wOverride = "override", wImportCpp = "importcpp",
    wCppNonPod = "cppNonPod",
    wImportObjC = "importobjc", wImportCompilerProc = "importCompilerProc",
    wImportc = "importc", wImportJs = "importjs", wExportc = "exportc", wExportCpp = "exportcpp",
    wExportNims = "exportnims",
    wIncompleteStruct = "incompleteStruct", # deprecated
    wCompleteStruct = "completeStruct", wRequiresInit = "requiresInit", wAlign = "align",
    wNodecl = "nodecl", wPure = "pure", wSideEffect = "sideEffect", wHeader = "header",
    wNoSideEffect = "noSideEffect", wGcSafe = "gcsafe", wNoreturn = "noreturn",
    wNosinks = "nosinks", wLib = "lib", wDynlib = "dynlib",
    wCompilerProc = "compilerproc", wCore = "core", wProcVar = "procvar",
    wBase = "base", wUsed = "used", wFatal = "fatal", wError = "error", wWarning = "warning",
    wHint = "hint",
    wWarningAsError = "warningAsError",
    wHintAsError = "hintAsError",
    wLine = "line", wPush = "push",
    wPop = "pop", wDefine = "define", wUndef = "undef", wLineDir = "lineDir",
    wStackTrace = "stackTrace", wLineTrace = "lineTrace", wLink = "link", wCompile = "compile",
    wLinksys = "linksys", wDeprecated = "deprecated", wVarargs = "varargs", wCallconv = "callconv",
    wDebugger = "debugger", wNimcall = "nimcall", wStdcall = "stdcall", wCdecl = "cdecl",
    wSafecall = "safecall", wSyscall = "syscall", wInline = "inline", wNoInline = "noinline",
    wFastcall = "fastcall", wThiscall = "thiscall", wClosure = "closure", wNoconv = "noconv",
    wOn = "on", wOff = "off", wChecks = "checks", wRangeChecks = "rangeChecks",
    wBoundChecks = "boundChecks", wOverflowChecks = "overflowChecks", wNilChecks = "nilChecks",
    wFloatChecks = "floatChecks", wNanChecks = "nanChecks", wInfChecks = "infChecks",
    wStyleChecks = "styleChecks", wStaticBoundchecks = "staticBoundChecks",
    wNonReloadable = "nonReloadable", wExecuteOnReload = "executeOnReload",

    wAssertions = "assertions", wPatterns = "patterns", wTrMacros = "trmacros",
    wSinkInference = "sinkInference", wWarnings = "warnings",
    wHints = "hints", wOptimization = "optimization", wRaises = "raises",
    wWrites = "writes", wReads = "reads", wSize = "size", wEffects = "effects", wTags = "tags",
    wForbids = "forbids", wRequires = "requires", wEnsures = "ensures", wInvariant = "invariant",
    wAssume = "assume", wAssert = "assert",
    wDeadCodeElimUnused = "deadCodeElim",  # deprecated, dead code elim always happens
    wSafecode = "safecode", wPackage = "package", wNoForward = "noforward", wReorder = "reorder",
    wNoRewrite = "norewrite", wNoDestroy = "nodestroy", wPragma = "pragma",
    wCompileTime = "compileTime", wNoInit = "noinit", wPassc = "passc", wPassl = "passl",
    wLocalPassc = "localPassC", wBorrow = "borrow", wDiscardable = "discardable",
    wFieldChecks = "fieldChecks", wSubsChar = "subschar", wAcyclic = "acyclic",
    wShallow = "shallow", wUnroll = "unroll", wLinearScanEnd = "linearScanEnd",
    wComputedGoto = "computedGoto", wExperimental = "experimental", wDoctype = "doctype",
    wWrite = "write", wGensym = "gensym", wInject = "inject", wDirty = "dirty",
    wInheritable = "inheritable", wThreadVar = "threadvar", wEmit = "emit",
    wAsmNoStackFrame = "asmNoStackFrame", wAsmSyntax = "asmSyntax", wImplicitStatic = "implicitStatic",
    wGlobal = "global", wCodegenDecl = "codegenDecl", wUnchecked = "unchecked",
    wGuard = "guard", wLocks = "locks", wPartial = "partial", wExplain = "explain",
    wLiftLocals = "liftlocals", wEnforceNoRaises = "enforceNoRaises", wSystemRaisesDefect = "systemRaisesDefect",
    wRedefine = "redefine", wCallsite = "callsite",
    wQuirky = "quirky",

    # codegen keywords, but first the ones that are also pragmas:
    wExtern = "extern", wGoto = "goto", wRegister = "register",
    wUnion = "union", wPacked = "packed", wVirtual = "virtual",
    wVolatile = "volatile", wMember = "member",
    wByCopy = "bycopy", wByRef = "byref",

    # codegen keywords but not pragmas:
    wAuto = "auto", wBool = "bool", wCatch = "catch", wChar = "char",
    wClass = "class", wCompl = "compl", wConstCast = "const_cast", wDefault = "default",
    wDelete = "delete", wDouble = "double", wDynamicCast = "dynamic_cast",
    wExplicit = "explicit", wFalse = "false", wFloat = "float",
    wFriend = "friend", wInt = "int", wLong = "long", wMutable = "mutable",
    wNamespace = "namespace", wNew = "new", wOperator = "operator", wPrivate = "private",
    wProtected = "protected", wPublic = "public",
    wReinterpretCast = "reinterpret_cast", wRestrict = "restrict", wShort = "short",
    wSigned = "signed", wSizeof = "sizeof", wStaticCast = "static_cast", wStruct = "struct",
    wSwitch = "switch", wThis = "this", wThrow = "throw", wTrue = "true", wTypedef = "typedef",
    wTypeid = "typeid", wTypeof = "typeof",  wTypename = "typename",
    wUnsigned = "unsigned", wVoid = "void", 

    wAlignas = "alignas", wAlignof = "alignof", wConstexpr = "constexpr", wDecltype = "decltype",
    wNullptr = "nullptr", wNoexcept = "noexcept",
    wThreadLocal = "thread_local", wStaticAssert = "static_assert",
    wChar16 = "char16_t", wChar32 = "char32_t", wWchar = "wchar_t",

    wStdIn = "stdin", wStdOut = "stdout", wStdErr = "stderr",

    wInOut = "inout", wOneWay = "oneway",
    # end of codegen keywords

    wBitsize = "bitsize", wImportHidden = "all",
    wSendable = "sendable"

  TSpecialWords* = set[TSpecialWord]

const
  oprLow* = ord(wColon)
  oprHigh* = ord(wDotDot)

  nimKeywordsLow* = ord(wAsm)
  nimKeywordsHigh* = ord(wYield)

  ccgKeywordsLow* = ord(wExtern)
  ccgKeywordsHigh* = ord(wOneWay)

  cppNimSharedKeywords* = {
    wAsm, wBreak, wCase, wConst, wContinue, wDo, wElse, wEnum, wExport,
    wFor, wIf, wReturn, wStatic, wTemplate, wTry, wWhile, wUsing}
  
  nonPragmaWordsLow* = wAuto
  nonPragmaWordsHigh* = wOneWay


from std/enumutils import genEnumCaseStmt
from std/strutils import normalize
proc findStr*[T: enum](a, b: static[T], s: string, default: T): T =
  genEnumCaseStmt(T, s, default, ord(a), ord(b), normalize)

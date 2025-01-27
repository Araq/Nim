#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# This module implements semantic checking for pragmas

import
  condsyms, ast, astalgo, idents, semdata, msgs, renderer,
  wordrecg, ropes, options, extccomp, magicsys, trees,
  types, lookups, lineinfos, pathutils, linter, modulepaths

from sigmatch import trySuggestPragmas

import std/[os, math, strutils]

when defined(nimPreviewSlimSystem):
  import std/assertions

from ic / ic import addCompilerProc

const
  FirstCallConv* = wNimcall
  LastCallConv* = wNoconv

const
  declPragmas = {wImportc, wImportObjC, wImportCpp, wImportJs, wExportc, wExportCpp,
    wExportNims, wExtern, wDeprecated, wNodecl, wError, wUsed}
    ## common pragmas for declarations, to a good approximation
  procPragmas* = declPragmas + {FirstCallConv..LastCallConv,
    wMagic, wNoSideEffect, wSideEffect, wNoreturn, wNosinks, wDynlib, wHeader,
    wCompilerProc, wNonReloadable, wCore, wProcVar, wVarargs, wCompileTime,
    wBorrow, wImportCompilerProc, wThread,
    wAsmNoStackFrame, wDiscardable, wNoInit, wCodegenDecl,
    wGensym, wInject, wRaises, wEffectsOf, wTags, wForbids, wLocks, wDelegator, wGcSafe,
    wConstructor, wLiftLocals, wStackTrace, wLineTrace, wNoDestroy,
    wRequires, wEnsures, wEnforceNoRaises, wSystemRaisesDefect, wVirtual, wQuirky, wMember}
  converterPragmas* = procPragmas
  methodPragmas* = procPragmas+{wBase}-{wImportCpp}
  templatePragmas* = {wDeprecated, wError, wGensym, wInject, wDirty,
    wDelegator, wExportNims, wUsed, wPragma, wRedefine, wCallsite}
  macroPragmas* = declPragmas + {FirstCallConv..LastCallConv,
    wMagic, wNoSideEffect, wCompilerProc, wNonReloadable, wCore,
    wDiscardable, wGensym, wInject, wDelegator}
  iteratorPragmas* = declPragmas + {FirstCallConv..LastCallConv, wNoSideEffect, wSideEffect,
    wMagic, wBorrow,
    wDiscardable, wGensym, wInject, wRaises, wEffectsOf,
    wTags, wForbids, wLocks, wGcSafe, wRequires, wEnsures}
  exprPragmas* = {wLine, wLocks, wNoRewrite, wGcSafe, wNoSideEffect}
  stmtPragmas* = {
    wHint, wWarning, wError,
    wFatal, wDefine, wUndef, wCompile, wLink, wLinksys, wPure, wPush, wPop,
    wPassl, wPassc, wLocalPassc,
    wDeadCodeElimUnused,  # deprecated, always on
    wDeprecated,
    wPragma, wEmit, wUnroll,
    wLinearScanEnd, wPatterns, wTrMacros, wEffects, wNoForward, wReorder, wComputedGoto,
    wExperimental, wDoctype, wThis, wUsed, wInvariant, wAssume, wAssert}
  stmtPragmasTopLevel* = {wChecks, wObjChecks, wFieldChecks, wRangeChecks,
    wBoundChecks, wOverflowChecks, wNilChecks, wStaticBoundchecks,
    wStyleChecks, wAssertions,
    wWarnings, wHints,
    wLineDir, wStackTrace, wLineTrace, wOptimization,
    wFloatChecks, wInfChecks, wNanChecks}
  lambdaPragmas* = {FirstCallConv..LastCallConv,
    wNoSideEffect, wSideEffect, wNoreturn, wNosinks, wDynlib, wHeader,
    wThread, wAsmNoStackFrame,
    wRaises, wLocks, wTags, wForbids, wRequires, wEnsures, wEffectsOf,
    wGcSafe, wCodegenDecl, wNoInit, wCompileTime}
  typePragmas* = declPragmas + {wMagic, wAcyclic,
    wPure, wHeader, wCompilerProc, wCore, wFinal, wSize, wShallow,
    wIncompleteStruct, wCompleteStruct, wByCopy, wByRef,
    wInheritable, wGensym, wInject, wRequiresInit, wUnchecked, wUnion, wPacked,
    wCppNonPod, wBorrow, wGcSafe, wPartial, wExplain, wPackage, wCodegenDecl,
    wSendable, wNoInit}
  fieldPragmas* = declPragmas + {wGuard, wBitsize, wCursor,
    wRequiresInit, wNoalias, wAlign, wNoInit} - {wExportNims, wNodecl} # why exclude these?
  varPragmas* = declPragmas + {wVolatile, wRegister, wThreadVar,
    wMagic, wHeader, wCompilerProc, wCore, wDynlib,
    wNoInit, wCompileTime, wGlobal, wLiftLocals,
    wGensym, wInject, wCodegenDecl,
    wGuard, wGoto, wCursor, wNoalias, wAlign}
  constPragmas* = declPragmas + {wHeader, wMagic,
    wGensym, wInject,
    wIntDefine, wStrDefine, wBoolDefine, wDefine,
    wCompilerProc, wCore}
  paramPragmas* = {wNoalias, wInject, wGensym, wByRef, wByCopy, wCodegenDecl, wExportc, wExportCpp}
  letPragmas* = varPragmas
  procTypePragmas* = {FirstCallConv..LastCallConv, wVarargs, wNoSideEffect,
                      wThread, wRaises, wEffectsOf, wLocks, wTags, wForbids, wGcSafe,
                      wRequires, wEnsures}
  forVarPragmas* = {wInject, wGensym}
  allRoutinePragmas* = methodPragmas + iteratorPragmas + lambdaPragmas
  enumFieldPragmas* = {wDeprecated}

proc getPragmaVal*(procAst: PNode; name: TSpecialWord): PNode =
  result = nil
  let p = procAst[pragmasPos]
  if p.kind == nkEmpty: return nil
  for it in p:
    if it.kind in nkPragmaCallKinds and it.len == 2 and it[0].kind == nkIdent and
        it[0].ident.id == ord(name):
      return it[1]

proc pragma*(c: PContext, sym: PSym, n: PNode, validPragmas: TSpecialWords;
            isStatement: bool = false)

proc recordPragma(c: PContext; n: PNode; args: varargs[string]) =
  var recorded = newNodeI(nkReplayAction, n.info)
  for i in 0..args.high:
    recorded.add newStrNode(args[i], n.info)
  addPragmaComputation(c, recorded)

const
  errStringLiteralExpected = "string literal expected"
  errIntLiteralExpected = "integer literal expected"

proc invalidPragma*(c: PContext; n: PNode) =
  localError(c.config, n.info, "invalid pragma: " & renderTree(n, {renderNoComments}))

proc illegalCustomPragma*(c: PContext, n: PNode, s: PSym) =
  var msg = "cannot attach a custom pragma to '" & s.name.s & "'"
  if s != nil:
    msg.add("; custom pragmas are not supported for ")
    case s.kind
    of skForVar: msg.add("`for` loop variables")
    of skEnumField: msg.add("enum fields")
    of skModule: msg.add("modules")
    else: msg.add("symbol kind " & $s.kind)
  localError(c.config, n.info, msg)

proc pragmaProposition(c: PContext, n: PNode) =
  if n.kind notin nkPragmaCallKinds or n.len != 2:
    localError(c.config, n.info, "proposition expected")
  else:
    n[1] = c.semExpr(c, n[1])

proc pragmaEnsures(c: PContext, n: PNode) =
  if n.kind notin nkPragmaCallKinds or n.len != 2:
    localError(c.config, n.info, "proposition expected")
  else:
    openScope(c)
    let o = getCurrOwner(c)
    if o.kind in routineKinds and o.typ != nil and o.typ.returnType != nil:
      var s = newSym(skResult, getIdent(c.cache, "result"), c.idgen, o, n.info)
      s.typ = o.typ.returnType
      incl(s.flags, sfUsed)
      addDecl(c, s)
    n[1] = c.semExpr(c, n[1])
    closeScope(c)

proc setExternName(c: PContext; s: PSym, extname: string, info: TLineInfo) =
  # special cases to improve performance:
  if extname == "$1":
    s.loc.snippet = rope(s.name.s)
  elif '$' notin extname:
    s.loc.snippet = rope(extname)
  else:
    try:
      s.loc.snippet = rope(extname % s.name.s)
    except ValueError:
      localError(c.config, info, "invalid extern name: '" & extname & "'. (Forgot to escape '$'?)")
  when hasFFI:
    s.cname = $s.loc.snippet


proc makeExternImport(c: PContext; s: PSym, extname: string, info: TLineInfo) =
  setExternName(c, s, extname, info)
  incl(s.flags, sfImportc)
  excl(s.flags, sfForward)

proc makeExternExport(c: PContext; s: PSym, extname: string, info: TLineInfo) =
  setExternName(c, s, extname, info)
  incl(s.flags, sfExportc)

proc processImportCompilerProc(c: PContext; s: PSym, extname: string, info: TLineInfo) =
  setExternName(c, s, extname, info)
  incl(s.flags, sfImportc)
  excl(s.flags, sfForward)
  incl(s.loc.flags, lfImportCompilerProc)

proc processImportCpp(c: PContext; s: PSym, extname: string, info: TLineInfo) =
  setExternName(c, s, extname, info)
  incl(s.flags, sfImportc)
  incl(s.flags, sfInfixCall)
  excl(s.flags, sfForward)
  if c.config.backend == backendC:
    let m = s.getModule()
    incl(m.flags, sfCompileToCpp)
  incl c.config.globalOptions, optMixedMode

proc processImportObjC(c: PContext; s: PSym, extname: string, info: TLineInfo) =
  setExternName(c, s, extname, info)
  incl(s.flags, sfImportc)
  incl(s.flags, sfNamedParamCall)
  excl(s.flags, sfForward)
  let m = s.getModule()
  incl(m.flags, sfCompileToObjc)

proc newEmptyStrNode(c: PContext; n: PNode, strVal: string = ""): PNode {.noinline.} =
  result = newNodeIT(nkStrLit, n.info, getSysType(c.graph, n.info, tyString))
  result.strVal = strVal

proc getStrLitNode(c: PContext, n: PNode): PNode =
  if n.kind notin nkPragmaCallKinds or n.len != 2:
    localError(c.config, n.info, errStringLiteralExpected)
    # error correction:
    result = newEmptyStrNode(c, n)
  else:
    n[1] = c.semConstExpr(c, n[1])
    case n[1].kind
    of nkStrLit, nkRStrLit, nkTripleStrLit: result = n[1]
    else:
      localError(c.config, n.info, errStringLiteralExpected)
      # error correction:
      result = newEmptyStrNode(c, n)

proc expectStrLit(c: PContext, n: PNode): string =
  result = getStrLitNode(c, n).strVal

proc expectIntLit(c: PContext, n: PNode): int =
  result = 0
  if n.kind notin nkPragmaCallKinds or n.len != 2:
    localError(c.config, n.info, errIntLiteralExpected)
  else:
    n[1] = c.semConstExpr(c, n[1])
    case n[1].kind
    of nkIntLit..nkInt64Lit: result = int(n[1].intVal)
    else: localError(c.config, n.info, errIntLiteralExpected)

proc getOptionalStr(c: PContext, n: PNode, defaultStr: string): string =
  if n.kind in nkPragmaCallKinds: result = expectStrLit(c, n)
  else: result = defaultStr

proc processVirtual(c: PContext, n: PNode, s: PSym, flag: TSymFlag) =
  s.constraint = newEmptyStrNode(c, n, getOptionalStr(c, n, "$1"))
  s.constraint.strVal = s.constraint.strVal % s.name.s
  s.flags.incl {flag, sfInfixCall, sfExportc, sfMangleCpp}

  s.typ.callConv = ccMember
  incl c.config.globalOptions, optMixedMode

proc processCodegenDecl(c: PContext, n: PNode, sym: PSym) =
  sym.constraint = getStrLitNode(c, n)
  sym.flags.incl sfCodegenDecl

proc processMagic(c: PContext, n: PNode, s: PSym) =
  #if sfSystemModule notin c.module.flags:
  #  liMessage(n.info, errMagicOnlyInSystem)
  if n.kind notin nkPragmaCallKinds or n.len != 2:
    localError(c.config, n.info, errStringLiteralExpected)
    return
  var v: string
  if n[1].kind == nkIdent: v = n[1].ident.s
  else: v = expectStrLit(c, n)
  for m in TMagic:
    if substr($m, 1) == v:
      s.magic = m
      break
  if s.magic == mNone: message(c.config, n.info, warnUnknownMagic, v)

proc wordToCallConv(sw: TSpecialWord): TCallingConvention =
  # this assumes that the order of special words and calling conventions is
  # the same
  TCallingConvention(ord(ccNimCall) + ord(sw) - ord(wNimcall))

proc isTurnedOn(c: PContext, n: PNode): bool =
  result = false
  if n.kind in nkPragmaCallKinds and n.len == 2:
    let x = c.semConstBoolExpr(c, n[1])
    n[1] = x
    if x.kind == nkIntLit: return x.intVal != 0
  localError(c.config, n.info, "'on' or 'off' expected")

proc onOff(c: PContext, n: PNode, op: TOptions, resOptions: var TOptions) =
  if isTurnedOn(c, n): resOptions.incl op
  else: resOptions.excl op

proc pragmaNoForward*(c: PContext, n: PNode; flag=sfNoForward) =
  if isTurnedOn(c, n):
    incl(c.module.flags, flag)
    c.features.incl codeReordering
  else:
    excl(c.module.flags, flag)
    # c.features.excl codeReordering

  # deprecated as of 0.18.1
  message(c.config, n.info, warnDeprecated,
          "use {.experimental: \"codeReordering\".} instead; " &
          (if flag == sfNoForward: "{.noForward.}" else: "{.reorder.}") & " is deprecated")

proc pragmaAsm*(c: PContext, n: PNode): char =
  ## Checks asm pragmas and get's the asm subschar (default: '`').
  result = '\0'
  if n != nil:
    for i in 0..<n.len:
      let it = n[i]
      if it.kind in nkPragmaCallKinds and it.len == 2 and it[0].kind == nkIdent:
        case whichKeyword(it[0].ident)
        of wSubsChar:
          if it[1].kind == nkCharLit: result = chr(int(it[1].intVal))
          else: invalidPragma(c, it)
        of wAsmSyntax:
          let s = expectStrLit(c, it)
          if s notin ["gcc", "vcc"]: invalidPragma(c, it)
        else: invalidPragma(c, it)
      else:
        invalidPragma(c, it)

proc processCallConv(c: PContext, n: PNode) =
  if n.kind in nkPragmaCallKinds and n.len == 2 and n[1].kind == nkIdent:
    let sw = whichKeyword(n[1].ident)
    case sw
    of FirstCallConv..LastCallConv:
      c.optionStack[^1].defaultCC = wordToCallConv(sw)
    else: localError(c.config, n.info, "calling convention expected")
  else:
    localError(c.config, n.info, "calling convention expected")

proc getLib(c: PContext, kind: TLibKind, path: PNode): PLib =
  for it in c.libs:
    if it.kind == kind and trees.exprStructuralEquivalent(it.path, path):
      return it

  result = newLib(kind)
  result.path = path
  c.libs.add result
  if path.kind in {nkStrLit..nkTripleStrLit}:
    result.isOverridden = options.isDynlibOverride(c.config, path.strVal)

proc expectDynlibNode(c: PContext, n: PNode): PNode =
  if n.kind notin nkPragmaCallKinds or n.len != 2:
    localError(c.config, n.info, errStringLiteralExpected)
    # error correction:
    result = newEmptyStrNode(c, n)
  else:
    # For the OpenGL wrapper we support:
    # {.dynlib: myGetProcAddr(...).}
    result = c.semExpr(c, n[1])
    if result.kind == nkSym and result.sym.kind == skConst:
      result = c.semConstExpr(c, result) # fold const
    if result.typ == nil or result.typ.kind notin {tyPointer, tyString, tyProc}:
      localError(c.config, n.info, errStringLiteralExpected)
      result = newEmptyStrNode(c, n)

proc processDynLib(c: PContext, n: PNode, sym: PSym) =
  if (sym == nil) or (sym.kind == skModule):
    let lib = getLib(c, libDynamic, expectDynlibNode(c, n))
    if not lib.isOverridden:
      c.optionStack[^1].dynlib = lib
  else:
    if n.kind in nkPragmaCallKinds:
      var lib = getLib(c, libDynamic, expectDynlibNode(c, n))
      if not lib.isOverridden:
        addToLib(lib, sym)
        incl(sym.loc.flags, lfDynamicLib)
    else:
      incl(sym.loc.flags, lfExportLib)
    # since we'll be loading the dynlib symbols dynamically, we must use
    # a calling convention that doesn't introduce custom name mangling
    # cdecl is the default - the user can override this explicitly
    if sym.kind in routineKinds and sym.typ != nil and
       tfExplicitCallConv notin sym.typ.flags:
      sym.typ.callConv = ccCDecl

proc processNote(c: PContext, n: PNode) =
  template handleNote(enumVals, notes) =
    let x = findStr(enumVals.a, enumVals.b, n[0][1].ident.s, errUnknown)
    if x != errUnknown:
      nk = TNoteKind(x)
      let x = c.semConstBoolExpr(c, n[1])
      n[1] = x
      if x.kind == nkIntLit and x.intVal != 0: incl(notes, nk)
      else: excl(notes, nk)
    else:
      invalidPragma(c, n)

  if n.kind in nkPragmaCallKinds and n.len == 2 and
      n[0].kind == nkBracketExpr and
      n[0].len == 2 and
      n[0][1].kind == nkIdent and n[0][0].kind == nkIdent:
    var nk: TNoteKind
    case whichKeyword(n[0][0].ident)
    of wHint: handleNote(hintMin .. hintMax, c.config.notes)
    of wWarning: handleNote(warnMin .. warnMax, c.config.notes)
    of wWarningAsError: handleNote(warnMin .. warnMax, c.config.warningAsErrors)
    of wHintAsError: handleNote(hintMin .. hintMax, c.config.warningAsErrors)
    else: invalidPragma(c, n)
  else: invalidPragma(c, n)

proc pragmaToOptions*(w: TSpecialWord): TOptions {.inline.} =
  case w
  of wChecks: ChecksOptions
  of wObjChecks: {optObjCheck}
  of wFieldChecks: {optFieldCheck}
  of wRangeChecks: {optRangeCheck}
  of wBoundChecks: {optBoundsCheck}
  of wOverflowChecks: {optOverflowCheck}
  of wFloatChecks: {optNaNCheck, optInfCheck}
  of wNanChecks: {optNaNCheck}
  of wInfChecks: {optInfCheck}
  of wStaticBoundchecks: {optStaticBoundsCheck}
  of wStyleChecks: {optStyleCheck}
  of wAssertions: {optAssert}
  of wWarnings: {optWarns}
  of wHints: {optHints}
  of wLineDir: {optLineDir}
  of wStackTrace: {optStackTrace}
  of wLineTrace: {optLineTrace}
  of wDebugger: {optNone}
  of wProfiler: {optProfiler, optMemTracker}
  of wMemTracker: {optMemTracker}
  of wByRef: {optByRef}
  of wImplicitStatic: {optImplicitStatic}
  of wPatterns, wTrMacros: {optTrMacros}
  of wSinkInference: {optSinkInference}
  of wQuirky: {optQuirky}
  else: {}

proc processExperimental(c: PContext; n: PNode) =
  if n.kind notin nkPragmaCallKinds or n.len != 2:
    c.features.incl oldExperimentalFeatures
  else:
    n[1] = c.semConstExpr(c, n[1])
    case n[1].kind
    of nkStrLit, nkRStrLit, nkTripleStrLit:
      try:
        let feature = parseEnum[Feature](n[1].strVal)
        c.features.incl feature
        if feature == codeReordering:
          if not isTopLevel(c):
              localError(c.config, n.info,
                         "Code reordering experimental pragma only valid at toplevel")
          c.module.flags.incl sfReorder
      except ValueError:
        localError(c.config, n[1].info, "unknown experimental feature")
    else:
      localError(c.config, n.info, errStringLiteralExpected)

proc tryProcessOption(c: PContext, n: PNode, resOptions: var TOptions): bool =
  result = true
  if n.kind notin nkPragmaCallKinds or n.len != 2: result = false
  elif n[0].kind == nkBracketExpr: processNote(c, n)
  elif n[0].kind != nkIdent: result = false
  else:
    let sw = whichKeyword(n[0].ident)
    if sw == wExperimental:
      processExperimental(c, n)
      return true
    let opts = pragmaToOptions(sw)
    if opts != {}:
      onOff(c, n, opts, resOptions)
    else:
      case sw
      of wCallconv: processCallConv(c, n)
      of wDynlib: processDynLib(c, n, nil)
      of wOptimization:
        if n[1].kind != nkIdent:
          invalidPragma(c, n)
        else:
          case n[1].ident.s.normalize
          of "speed":
            incl(resOptions, optOptimizeSpeed)
            excl(resOptions, optOptimizeSize)
          of "size":
            excl(resOptions, optOptimizeSpeed)
            incl(resOptions, optOptimizeSize)
          of "none":
            excl(resOptions, optOptimizeSpeed)
            excl(resOptions, optOptimizeSize)
          else: localError(c.config, n.info, "'none', 'speed' or 'size' expected")
      else: result = false

proc processOption(c: PContext, n: PNode, resOptions: var TOptions) =
  if not tryProcessOption(c, n, resOptions):
    # calling conventions (boring...):
    localError(c.config, n.info, "option expected")

proc checkPushedPragma(c: PContext, n: PNode) =
  let keyDeep = n.kind in nkPragmaCallKinds and n.len > 1
  var key = if keyDeep: n[0] else: n
  if key.kind in nkIdentKinds:
    let ident = considerQuotedIdent(c, key)
    var userPragma = strTableGet(c.userPragmas, ident)
    if userPragma == nil:
      let k = whichKeyword(ident)
      # TODO: might as well make a list which is not accepted by `push`: emit, cast etc.
      if k == wEmit:
        localError(c.config, n.info, "an 'emit' pragma cannot be pushed")

proc processPush(c: PContext, n: PNode, start: int) =
  if n[start-1].kind in nkPragmaCallKinds:
    localError(c.config, n.info, "'push' cannot have arguments")
  var x = pushOptionEntry(c)
  for i in start..<n.len:
    if not tryProcessOption(c, n[i], c.config.options):
      # simply store it somewhere:
      checkPushedPragma(c, n[i])
      if x.otherPragmas.isNil:
        x.otherPragmas = newNodeI(nkPragma, n.info)
      x.otherPragmas.add n[i]
    #localError(c.config, n.info, errOptionExpected)

  # If stacktrace is disabled globally we should not enable it
  if optStackTrace notin c.optionStack[0].options:
    c.config.options.excl(optStackTrace)
  when defined(debugOptions):
    echo c.config $ n.info, " PUSH config is now ", c.config.options

proc processPop(c: PContext, n: PNode) =
  if c.optionStack.len <= 1:
    localError(c.config, n.info, "{.pop.} without a corresponding {.push.}")
  else:
    popOptionEntry(c)
  when defined(debugOptions):
    echo c.config $ n.info, " POP config is now ", c.config.options

proc processDefineConst(c: PContext, n: PNode, sym: PSym, kind: TMagic) =
  sym.magic = kind
  if n.kind in nkPragmaCallKinds and n.len == 2:
    # could also use TLib
    n[1] = getStrLitNode(c, n)

proc processDefine(c: PContext, n: PNode, sym: PSym) =
  if sym != nil and sym.kind == skConst:
    processDefineConst(c, n, sym, mGenericDefine)
  elif (n.kind in nkPragmaCallKinds and n.len == 2) and (n[1].kind == nkIdent):
    defineSymbol(c.config.symbols, n[1].ident.s)
  else:
    invalidPragma(c, n)

proc processUndef(c: PContext, n: PNode) =
  if (n.kind in nkPragmaCallKinds and n.len == 2) and (n[1].kind == nkIdent):
    undefSymbol(c.config.symbols, n[1].ident.s)
  else:
    invalidPragma(c, n)

proc relativeFile(c: PContext; n: PNode; ext=""): AbsoluteFile =
  var s = expectStrLit(c, n)
  if ext.len > 0 and splitFile(s).ext == "":
    s = addFileExt(s, ext)
  result = AbsoluteFile parentDir(toFullPath(c.config, n.info)) / s
  if not fileExists(result):
    if isAbsolute(s): result = AbsoluteFile s
    else:
      result = findFile(c.config, s)
      if result.isEmpty: result = AbsoluteFile s

proc processCompile(c: PContext, n: PNode) =
  ## This pragma can take two forms. The first is a simple file input:
  ##     {.compile: "file.c".}
  ## The second is a tuple where the second arg is the output name strutils formatter:
  ##     {.compile: ("file.c", "$1.o").}
  proc docompile(c: PContext; it: PNode; src, dest: AbsoluteFile; customArgs: string) =
    var cf = Cfile(nimname: splitFile(src).name,
                   cname: src, obj: dest, flags: {CfileFlag.External},
                   customArgs: customArgs)
    if not fileExists(src):
      localError(c.config, n.info, "cannot find: " & src.string)
    else:
      extccomp.addExternalFileToCompile(c.config, cf)
      recordPragma(c, it, "compile", src.string, dest.string, customArgs)

  proc getStrLit(c: PContext, n: PNode; i: int): string =
    n[i] = c.semConstExpr(c, n[i])
    case n[i].kind
    of nkStrLit, nkRStrLit, nkTripleStrLit:
      when defined(gcArc) or defined(gcOrc) or defined(gcAtomicArc):
        result = n[i].strVal
      else:
        shallowCopy(result, n[i].strVal)
    else:
      localError(c.config, n.info, errStringLiteralExpected)
      result = ""

  let it = if n.kind in nkPragmaCallKinds and n.len == 2: n[1] else: n
  if it.kind in {nkPar, nkTupleConstr} and it.len == 2:
    let s = getStrLit(c, it, 0)
    let dest = getStrLit(c, it, 1)
    var found = parentDir(toFullPath(c.config, n.info)) / s
    for f in os.walkFiles(found):
      let obj = completeCfilePath(c.config, AbsoluteFile(dest % extractFilename(f)))
      docompile(c, it, AbsoluteFile f, obj, "")
  else:
    var s = ""
    var customArgs = ""
    if n.kind in nkCallKinds:
      s = getStrLit(c, n, 1)
      if n.len == 3:
        customArgs = getStrLit(c, n, 2)
      else:
        localError(c.config, n.info, "'.compile' pragma takes up 2 arguments")
    else:
      s = expectStrLit(c, n)

    var found = AbsoluteFile(parentDir(toFullPath(c.config, n.info)) / s)
    if not fileExists(found):
      if isAbsolute(s): found = AbsoluteFile s
      else:
        found = findFile(c.config, s)
        if found.isEmpty: found = AbsoluteFile s
    let mangled = completeCfilePath(c.config, mangleModuleName(c.config, found).AbsoluteFile)
    let obj = toObjFile(c.config, mangled)
    docompile(c, it, found, obj, customArgs)

proc processLink(c: PContext, n: PNode) =
  let found = relativeFile(c, n, CC[c.config.cCompiler].objExt)
  extccomp.addExternalFileToLink(c.config, found)
  recordPragma(c, n, "link", found.string)

proc semAsmOrEmit*(con: PContext, n: PNode, marker: char): PNode =
  case n[1].kind
  of nkStrLit, nkRStrLit, nkTripleStrLit:
    result = newNodeI(if n.kind == nkAsmStmt: nkAsmStmt else: nkArgList, n.info)
    if n.kind == nkAsmStmt: result.add n[0] # save asm pragmas for NIR
    var str = n[1].strVal
    if str == "":
      localError(con.config, n.info, "empty 'asm' statement")
      return
    # now parse the string literal and substitute symbols:
    var a = 0
    while true:
      var b = strutils.find(str, marker, a)
      var sub = if b < 0: substr(str, a) else: substr(str, a, b - 1)
      if sub != "": result.add newStrNode(nkStrLit, sub)
      if b < 0: break
      var c = strutils.find(str, marker, b + 1)
      if c < 0: sub = substr(str, b + 1)
      else: sub = substr(str, b + 1, c - 1)
      if sub != "":
        var amb = false
        var e = searchInScopes(con, getIdent(con.cache, sub), amb)
        # XXX what to do here if 'amb' is true?
        if e != nil:
          incl(e.flags, sfUsed)
          if isDefined(con.config, "nimPreviewAsmSemSymbol"):
            result.add con.semExprWithType(con, newSymNode(e), {efTypeAllowed})
          else:
            result.add newSymNode(e)
        else:
          result.add newStrNode(nkStrLit, sub)
      else:
        # an empty '``' produces a single '`'
        result.add newStrNode(nkStrLit, $marker)
      if c < 0: break
      a = c + 1
  else:
    illFormedAstLocal(n, con.config)
    result = newNodeI(nkAsmStmt, n.info)
    if n.kind == nkAsmStmt: result.add n[0]

proc pragmaEmit(c: PContext, n: PNode) =
  if n.kind notin nkPragmaCallKinds or n.len != 2:
    localError(c.config, n.info, errStringLiteralExpected)
  else:
    let n1 = n[1]
    if n1.kind == nkBracket:
      var b = newNodeI(nkBracket, n1.info, n1.len)
      for i in 0..<n1.len:
        b[i] = c.semExprWithType(c, n1[i], {efTypeAllowed})
      n[1] = b
    else:
      n[1] = c.semConstExpr(c, n1)
      case n[1].kind
      of nkStrLit, nkRStrLit, nkTripleStrLit:
        n[1] = semAsmOrEmit(c, n, '`')
      else:
        localError(c.config, n.info, errStringLiteralExpected)

proc noVal(c: PContext; n: PNode) =
  if n.kind in nkPragmaCallKinds and n.len > 1: invalidPragma(c, n)

proc pragmaUnroll(c: PContext, n: PNode) =
  if c.p.nestedLoopCounter <= 0:
    invalidPragma(c, n)
  elif n.kind in nkPragmaCallKinds and n.len == 2:
    var unrollFactor = expectIntLit(c, n)
    if unrollFactor <% 32:
      n[1] = newIntNode(nkIntLit, unrollFactor)
    else:
      invalidPragma(c, n)

proc pragmaLine(c: PContext, n: PNode) =
  if n.kind in nkPragmaCallKinds and n.len == 2:
    n[1] = c.semConstExpr(c, n[1])
    let a = n[1]
    if a.kind in {nkPar, nkTupleConstr}:
      # unpack the tuple
      var x = a[0]
      var y = a[1]
      if x.kind == nkExprColonExpr: x = x[1]
      if y.kind == nkExprColonExpr: y = y[1]
      if x.kind != nkStrLit:
        localError(c.config, n.info, errStringLiteralExpected)
      elif y.kind != nkIntLit:
        localError(c.config, n.info, errIntLiteralExpected)
      else:
        n.info.fileIndex = fileInfoIdx(c.config, AbsoluteFile(x.strVal))
        n.info.line = uint16(y.intVal)
    else:
      localError(c.config, n.info, "tuple expected")
  else:
    # sensible default:
    n.info = getInfoContext(c.config, -1)

proc processPragma(c: PContext, n: PNode, i: int) =
  ## Create and add a new custom pragma `{.pragma: name.}` node to the module's context.
  let it = n[i]
  if it.kind notin nkPragmaCallKinds and it.safeLen == 2:
    invalidPragma(c, n)
    return
  elif it.safeLen != 2 or it[0].kind != nkIdent or it[1].kind != nkIdent:
    invalidPragma(c, n)
    return

  var userPragma = newSym(skTemplate, it[1].ident, c.idgen, c.module, it.info, c.config.options)
  styleCheckDef(c, userPragma)
  userPragma.ast = newTreeI(nkPragma, n.info, n.sons[i+1..^1])
  strTableAdd(c.userPragmas, userPragma)

proc pragmaRaisesOrTags(c: PContext, n: PNode) =
  proc processExc(c: PContext, x: PNode) =
    if c.hasUnresolvedArgs(c, x):
      x.typ() = makeTypeFromExpr(c, x)
    else:
      var t = skipTypes(c.semTypeNode(c, x, nil), skipPtrs)
      if t.kind notin {tyObject, tyOr}:
        localError(c.config, x.info, errGenerated, "invalid type for raises/tags list")
      x.typ() = t

  if n.kind in nkPragmaCallKinds and n.len == 2:
    let it = n[1]
    if it.kind notin {nkCurly, nkBracket}:
      processExc(c, it)
    else:
      for e in items(it): processExc(c, e)
  else:
    invalidPragma(c, n)

proc pragmaLockStmt(c: PContext; it: PNode) =
  if it.kind notin nkPragmaCallKinds or it.len != 2:
    invalidPragma(c, it)
  else:
    let n = it[1]
    if n.kind != nkBracket:
      localError(c.config, n.info, errGenerated, "locks pragma takes a list of expressions")
    else:
      for i in 0..<n.len:
        n[i] = c.semExpr(c, n[i])

proc typeBorrow(c: PContext; sym: PSym, n: PNode) =
  if n.kind in nkPragmaCallKinds and n.len == 2:
    let it = n[1]
    if it.kind != nkAccQuoted:
      localError(c.config, n.info, "a type can only borrow `.` for now")
  incl(sym.typ.flags, tfBorrowDot)

proc markCompilerProc(c: PContext; s: PSym) =
  # minor hack ahead: FlowVar is the only generic .compilerproc type which
  # should not have an external name set:
  if s.kind != skType or s.name.s != "FlowVar":
    makeExternExport(c, s, "$1", s.info)
  incl(s.flags, sfCompilerProc)
  incl(s.flags, sfUsed)
  registerCompilerProc(c.graph, s)
  if c.config.symbolFiles != disabledSf:
    addCompilerProc(c.encoder, c.packedRepr, s)

proc deprecatedStmt(c: PContext; outerPragma: PNode) =
  let pragma = outerPragma[1]
  if pragma.kind in {nkStrLit..nkTripleStrLit}:
    incl(c.module.flags, sfDeprecated)
    c.module.constraint = getStrLitNode(c, outerPragma)
    return
  if pragma.kind != nkBracket:
    localError(c.config, pragma.info, "list of key:value pairs expected"); return
  message(c.config, pragma.info, warnDeprecated,
    "deprecated statement is now a no-op, use regular deprecated pragma")

proc pragmaGuard(c: PContext; it: PNode; kind: TSymKind): PSym =
  if it.kind notin nkPragmaCallKinds or it.len != 2:
    invalidPragma(c, it); return
  let n = it[1]
  if n.kind == nkSym:
    result = n.sym
  elif kind == skField:
    # First check if the guard is a global variable:
    result = qualifiedLookUp(c, n, {})
    if result.isNil or result.kind notin {skLet, skVar} or
        sfGlobal notin result.flags:
      # We return a dummy symbol; later passes over the type will repair it.
      # Generic instantiation needs to know about this too. But we're lazy
      # and perform the lookup on demand instead.
      result = newSym(skUnknown, considerQuotedIdent(c, n), c.idgen, nil, n.info,
        c.config.options)
  else:
    result = qualifiedLookUp(c, n, {checkUndeclared})

proc semCustomPragma(c: PContext, n: PNode, sym: PSym): PNode =
  var callNode: PNode

  case n.kind
  of nkIdentKinds:
    # pragma -> pragma()
    callNode = newTree(nkCall, n)
  of nkExprColonExpr:
    # pragma: arg -> pragma(arg)
    callNode = newTree(nkCall, n[0], n[1])
  of nkPragmaCallKinds - {nkExprColonExpr}:
    callNode = n
  else:
    invalidPragma(c, n)
    return n

  trySuggestPragmas(c, callNode[0])

  let r = c.semOverloadedCall(c, callNode, n, {skTemplate}, {efNoUndeclared})
  if r.isNil or sfCustomPragma notin r[0].sym.flags:
    invalidPragma(c, n)
    return n

  # we have a valid custom pragma
  if sym != nil and sym.kind in {skEnumField, skForVar, skModule}:
    illegalCustomPragma(c, n, sym)
    return n

  result = r
  # Transform the nkCall node back to its original form if possible
  if n.kind == nkIdent and r.len == 1:
    # pragma() -> pragma
    result = result[0]
  elif n.kind == nkExprColonExpr and r.len == 2:
    # pragma(arg) -> pragma: arg
    result.transitionSonsKind(n.kind)

proc processEffectsOf(c: PContext, n: PNode; owner: PSym) =
  proc processParam(c: PContext; n: PNode) =
    let r = c.semExpr(c, n)
    if r.kind == nkSym and r.sym.kind == skParam:
      if r.sym.owner == owner:
        incl r.sym.flags, sfEffectsDelayed
      else:
        localError(c.config, n.info, errGenerated, "parameter cannot be declared as .effectsOf")
    else:
      localError(c.config, n.info, errGenerated, "parameter name expected")

  if n.kind notin nkPragmaCallKinds or n.len != 2:
    localError(c.config, n.info, errGenerated, "parameter name expected")
  else:
    let it = n[1]
    if it.kind in {nkCurly, nkBracket}:
      for x in items(it): processParam(c, x)
    else:
      processParam(c, it)

proc singlePragma(c: PContext, sym: PSym, n: PNode, i: var int,
                  validPragmas: TSpecialWords,
                  comesFromPush, isStatement: bool): bool =
  result = false
  var it = n[i]
  let keyDeep = it.kind in nkPragmaCallKinds and it.len > 1
  var key = if keyDeep: it[0] else: it
  if key.kind == nkBracketExpr:
    processNote(c, it)
    return
  elif key.kind == nkCast:
    if comesFromPush:
      localError(c.config, n.info, "a 'cast' pragma cannot be pushed")
    elif not isStatement:
      localError(c.config, n.info, "'cast' pragma only allowed in a statement context")
    case whichPragma(key[1])
    of wRaises, wTags, wForbids: pragmaRaisesOrTags(c, key[1])
    else: discard
    return
  elif key.kind notin nkIdentKinds:
    n[i] = semCustomPragma(c, it, sym)
    return
  let ident = considerQuotedIdent(c, key)
  var userPragma = strTableGet(c.userPragmas, ident)
  if userPragma != nil:
    styleCheckUse(c, key.info, userPragma)

    # number of pragmas increase/decrease with user pragma expansion
    inc c.instCounter
    defer: dec c.instCounter
    if c.instCounter > 100:
      globalError(c.config, it.info, "recursive dependency: " & userPragma.name.s)

    if keyDeep:
      localError(c.config, it.info, "user pragma cannot have arguments")

    pragma(c, sym, userPragma.ast, validPragmas, isStatement)
    n.sons[i..i] = userPragma.ast.sons # expand user pragma with its content
    i.inc(userPragma.ast.len - 1) # inc by -1 is ok, user pragmas was empty
  else:
    let k = whichKeyword(ident)
    if k in validPragmas:
      checkPragmaUse(c, key.info, k, ident.s, (if sym != nil: sym else: c.module))
      case k
      of wExportc, wExportCpp:
        makeExternExport(c, sym, getOptionalStr(c, it, "$1"), it.info)
        if k == wExportCpp:
          if c.config.backend != backendCpp:
            localError(c.config, it.info, "exportcpp requires `cpp` backend, got: " & $c.config.backend)
          else:
            incl(sym.flags, sfMangleCpp)
        incl(sym.flags, sfUsed) # avoid wrong hints
      of wImportc:
        let name = getOptionalStr(c, it, "$1")
        cppDefine(c.config, name)
        recordPragma(c, it, "cppdefine", name)
        makeExternImport(c, sym, name, it.info)
      of wImportCompilerProc:
        let name = getOptionalStr(c, it, "$1")
        cppDefine(c.config, name)
        recordPragma(c, it, "cppdefine", name)
        processImportCompilerProc(c, sym, name, it.info)
      of wExtern: setExternName(c, sym, expectStrLit(c, it), it.info)
      of wDirty:
        if sym.kind == skTemplate: incl(sym.flags, sfDirty)
        else: invalidPragma(c, it)
      of wRedefine:
        if sym.kind == skTemplate: incl(sym.flags, sfTemplateRedefinition)
        else: invalidPragma(c, it)
      of wCallsite:
        if sym.kind == skTemplate: incl(sym.flags, sfCallsite)
        else: invalidPragma(c, it)
      of wImportCpp:
        processImportCpp(c, sym, getOptionalStr(c, it, "$1"), it.info)
      of wCppNonPod:
        incl(sym.flags, sfCppNonPod)
      of wImportJs:
        if c.config.backend != backendJs:
          localError(c.config, it.info, "`importjs` pragma requires the JavaScript target")
        let name = getOptionalStr(c, it, "$1")
        incl(sym.flags, sfImportc)
        incl(sym.flags, sfInfixCall)
        if sym.kind in skProcKinds and {'(', '#', '@'} notin name:
          localError(c.config, n.info, "`importjs` for routines requires a pattern")
        setExternName(c, sym, name, it.info)
      of wImportObjC:
        processImportObjC(c, sym, getOptionalStr(c, it, "$1"), it.info)
      of wSize:
        if sym.typ == nil: invalidPragma(c, it)
        var size = expectIntLit(c, it)
        case size
        of 1, 2, 4:
          sym.typ.size = size
          sym.typ.align = int16 size
        of 8:
          sym.typ.size = 8
          sym.typ.align = floatInt64Align(c.config)
        else:
          localError(c.config, it.info, "size may only be 1, 2, 4 or 8")
      of wAlign:
        let alignment = expectIntLit(c, it)
        if isPowerOfTwo(alignment) and alignment > 0:
          sym.alignment = max(sym.alignment, alignment)
        else:
          localError(c.config, it.info, "power of two expected")
      of wNodecl:
        noVal(c, it)
        incl(sym.loc.flags, lfNoDecl)
      of wPure, wAsmNoStackFrame:
        noVal(c, it)
        if sym != nil:
          if k == wPure and sym.kind in routineKinds: invalidPragma(c, it)
          else: incl(sym.flags, sfPure)
      of wVolatile:
        noVal(c, it)
        incl(sym.flags, sfVolatile)
      of wCursor:
        noVal(c, it)
        incl(sym.flags, sfCursor)
      of wRegister:
        noVal(c, it)
        incl(sym.flags, sfRegister)
      of wNoalias:
        noVal(c, it)
        incl(sym.flags, sfNoalias)
      of wEffectsOf:
        processEffectsOf(c, it, sym)
      of wThreadVar:
        noVal(c, it)
        incl(sym.flags, {sfThread, sfGlobal})
      of wDeadCodeElimUnused:
        warningDeprecated(c.config, n.info, "'{.deadcodeelim: on.}' is deprecated, now a noop")  # deprecated, dead code elim always on
      of wNoForward: pragmaNoForward(c, it)
      of wReorder: pragmaNoForward(c, it, flag = sfReorder)
      of wMagic: processMagic(c, it, sym)
      of wCompileTime:
        noVal(c, it)
        if comesFromPush:
          if sym.kind in {skProc, skFunc}:
            incl(sym.flags, sfCompileTime)
        else:
          incl(sym.flags, sfCompileTime)
        #incl(sym.loc.flags, lfNoDecl)
      of wGlobal:
        noVal(c, it)
        incl(sym.flags, sfGlobal)
        incl(sym.flags, sfPure)
      of wConstructor:
        incl(sym.flags, sfConstructor)
        if sfImportc notin sym.flags:
          sym.constraint = newEmptyStrNode(c, it, getOptionalStr(c, it, ""))
          sym.constraint.strVal = sym.constraint.strVal
          sym.flags.incl {sfExportc, sfMangleCpp}
          sym.typ.callConv = ccNoConvention
      of wHeader:
        var lib = getLib(c, libHeader, getStrLitNode(c, it))
        addToLib(lib, sym)
        incl(sym.flags, sfImportc)
        incl(sym.loc.flags, lfHeader)
        incl(sym.loc.flags, lfNoDecl)
        # implies nodecl, because otherwise header would not make sense
        if sym.loc.snippet == "": sym.loc.snippet = rope(sym.name.s)
      of wNoSideEffect:
        noVal(c, it)
        if sym != nil:
          incl(sym.flags, sfNoSideEffect)
          if sym.typ != nil: incl(sym.typ.flags, tfNoSideEffect)
      of wSideEffect:
        noVal(c, it)
        incl(sym.flags, sfSideEffect)
      of wNoreturn:
        noVal(c, it)
        # Disable the 'noreturn' annotation when in the "Quirky Exceptions" mode!
        if c.config.exc != excQuirky:
          incl(sym.flags, sfNoReturn)
        if sym.typ.returnType != nil:
          localError(c.config, sym.ast[paramsPos][0].info,
            ".noreturn with return type not allowed")
      of wNoDestroy:
        noVal(c, it)
        incl(sym.flags, sfGeneratedOp)
      of wNosinks:
        noVal(c, it)
        incl(sym.flags, sfWasForwarded)
      of wDynlib:
        processDynLib(c, it, sym)
      of wCompilerProc, wCore:
        noVal(c, it)           # compilerproc may not get a string!
        cppDefine(c.graph.config, sym.name.s)
        recordPragma(c, it, "cppdefine", sym.name.s)
        if sfFromGeneric notin sym.flags: markCompilerProc(c, sym)
      of wNonReloadable:
        sym.flags.incl sfNonReloadable
      of wProcVar:
        # old procvar annotation, no longer needed
        noVal(c, it)
      of wExplain:
        sym.flags.incl sfExplain
      of wDeprecated:
        if sym != nil and sym.kind in routineKinds + {skType, skVar, skLet, skConst}:
          if it.kind in nkPragmaCallKinds: discard getStrLitNode(c, it)
          incl(sym.flags, sfDeprecated)
        elif sym != nil and sym.kind != skModule:
          # We don't support the extra annotation field
          if it.kind in nkPragmaCallKinds:
            localError(c.config, it.info, "annotation to deprecated not supported here")
          incl(sym.flags, sfDeprecated)
        # At this point we're quite sure this is a statement and applies to the
        # whole module
        elif it.kind in nkPragmaCallKinds: deprecatedStmt(c, it)
        else: incl(c.module.flags, sfDeprecated)
      of wVarargs:
        noVal(c, it)
        if sym.typ == nil: invalidPragma(c, it)
        else: incl(sym.typ.flags, tfVarargs)
      of wBorrow:
        if sym.kind == skType:
          typeBorrow(c, sym, it)
        else:
          noVal(c, it)
          incl(sym.flags, sfBorrow)
      of wFinal:
        noVal(c, it)
        if sym.typ == nil: invalidPragma(c, it)
        else: incl(sym.typ.flags, tfFinal)
      of wInheritable:
        noVal(c, it)
        if sym.typ == nil or tfFinal in sym.typ.flags: invalidPragma(c, it)
        else: incl(sym.typ.flags, tfInheritable)
      of wPackage:
        noVal(c, it)
        if sym.typ == nil: invalidPragma(c, it)
        else: incl(sym.flags, sfForward)
      of wAcyclic:
        noVal(c, it)
        if sym.typ == nil: invalidPragma(c, it)
        else: incl(sym.typ.flags, tfAcyclic)
      of wShallow:
        noVal(c, it)
        if sym.typ == nil: invalidPragma(c, it)
        else: incl(sym.typ.flags, tfShallow)
      of wThread:
        noVal(c, it)
        incl(sym.flags, sfThread)
        if sym.typ != nil:
          incl(sym.typ.flags, tfThread)
          if sym.typ.callConv == ccClosure: sym.typ.callConv = ccNimCall
      of wSendable:
        noVal(c, it)
        if sym != nil and sym.typ != nil:
          incl(sym.typ.flags, tfSendable)
        else:
          invalidPragma(c, it)
      of wGcSafe:
        noVal(c, it)
        if sym != nil:
          if sym.kind != skType: incl(sym.flags, sfThread)
          if sym.typ != nil: incl(sym.typ.flags, tfGcSafe)
          else: invalidPragma(c, it)
        else:
          discard "no checking if used as a code block"
      of wPacked:
        noVal(c, it)
        if sym.typ == nil: invalidPragma(c, it)
        else: incl(sym.typ.flags, tfPacked)
      of wHint:
        let s = expectStrLit(c, it)
        recordPragma(c, it, "hint", s)
        message(c.config, it.info, hintUser, s)
      of wWarning:
        let s = expectStrLit(c, it)
        recordPragma(c, it, "warning", s)
        message(c.config, it.info, warnUser, s)
      of wError:
        if sym != nil and (sym.isRoutine or sym.kind == skType) and not isStatement:
          # This is subtle but correct: the error *statement* is only
          # allowed when 'wUsed' is not in validPragmas. Here this is the easiest way to
          # distinguish properly between
          # ``proc p() {.error}`` and ``proc p() = {.error: "msg".}``
          if it.kind in nkPragmaCallKinds: discard getStrLitNode(c, it)
          incl(sym.flags, sfError)
          excl(sym.flags, sfForward)
        else:
          let s = expectStrLit(c, it)
          recordPragma(c, it, "error", s)
          localError(c.config, it.info, errUser, s)
      of wFatal: fatal(c.config, it.info, expectStrLit(c, it))
      of wDefine: processDefine(c, it, sym)
      of wUndef: processUndef(c, it)
      of wCompile:
        let m = sym.getModule()
        incl(m.flags, sfUsed)
        processCompile(c, it)
      of wLink: processLink(c, it)
      of wPassl:
        let m = sym.getModule()
        incl(m.flags, sfUsed)
        let s = expectStrLit(c, it)
        extccomp.addLinkOption(c.config, s)
        recordPragma(c, it, "passl", s)
      of wPassc:
        let m = sym.getModule()
        incl(m.flags, sfUsed)
        let s = expectStrLit(c, it)
        extccomp.addCompileOption(c.config, s)
        recordPragma(c, it, "passc", s)
      of wLocalPassc:
        assert sym != nil and sym.kind == skModule
        let s = expectStrLit(c, it)
        appendToModule(sym, n)
        extccomp.addLocalCompileOption(c.config, s, toFullPathConsiderDirty(c.config, sym.info.fileIndex))
        recordPragma(c, it, "localpassl", s)
      of wPush:
        processPush(c, n, i + 1)
        result = true
      of wPop:
        processPop(c, it)
        result = true
      of wPragma:
        if not sym.isNil and sym.kind == skTemplate:
          sym.flags.incl sfCustomPragma
        else:
          processPragma(c, n, i)
          result = true
      of wDiscardable:
        noVal(c, it)
        if sym != nil: incl(sym.flags, sfDiscardable)
      of wNoInit:
        noVal(c, it)
        if sym != nil: incl(sym.flags, sfNoInit)
      of wCodegenDecl: processCodegenDecl(c, it, sym)
      of wChecks, wObjChecks, wFieldChecks, wRangeChecks, wBoundChecks,
         wOverflowChecks, wNilChecks, wAssertions, wWarnings, wHints,
         wLineDir, wOptimization, wStaticBoundchecks, wStyleChecks,
         wCallconv, wDebugger, wProfiler,
         wFloatChecks, wNanChecks, wInfChecks, wPatterns, wTrMacros:
        processOption(c, it, c.config.options)
      of wStackTrace, wLineTrace:
        if sym.kind in {skProc, skMethod, skConverter}:
          processOption(c, it, sym.options)
        else:
          processOption(c, it, c.config.options)
      of FirstCallConv..LastCallConv:
        assert(sym != nil)
        if sym.typ == nil: invalidPragma(c, it)
        else:
          sym.typ.callConv = wordToCallConv(k)
          sym.typ.flags.incl tfExplicitCallConv
      of wEmit: pragmaEmit(c, it)
      of wUnroll: pragmaUnroll(c, it)
      of wLinearScanEnd, wComputedGoto: noVal(c, it)
      of wEffects:
        # is later processed in effect analysis:
        noVal(c, it)
      of wIncompleteStruct:
        noVal(c, it)
        if sym.typ == nil: invalidPragma(c, it)
        else: incl(sym.typ.flags, tfIncompleteStruct)
      of wCompleteStruct:
        noVal(c, it)
        if sym.typ == nil: invalidPragma(c, it)
        else: incl(sym.typ.flags, tfCompleteStruct)
      of wUnchecked:
        noVal(c, it)
        if sym.typ == nil or sym.typ.kind notin {tyArray, tyUncheckedArray}:
          invalidPragma(c, it)
        else:
          sym.typ.kind = tyUncheckedArray
      of wUnion:
        if c.config.backend == backendJs:
          localError(c.config, it.info, "`{.union.}` is not implemented for js backend.")
        else:
          noVal(c, it)
          if sym.typ == nil: invalidPragma(c, it)
          else: incl(sym.typ.flags, tfUnion)
      of wRequiresInit:
        noVal(c, it)
        if sym.kind == skField:
          sym.flags.incl sfRequiresInit
        elif sym.typ != nil:
          incl(sym.typ.flags, tfNeedsFullInit)
        else:
          invalidPragma(c, it)
      of wByRef:
        noVal(c, it)
        if sym != nil and sym.kind == skParam:
          sym.options.incl optByRef
        elif sym == nil or sym.typ == nil:
          processOption(c, it, c.config.options)
        else:
          incl(sym.typ.flags, tfByRef)
      of wByCopy:
        noVal(c, it)
        if sym.kind == skParam:
          incl(sym.flags, sfByCopy)
        elif sym.kind != skType or sym.typ == nil: invalidPragma(c, it)
        else: incl(sym.typ.flags, tfByCopy)
      of wPartial:
        noVal(c, it)
        if sym.kind != skType or sym.typ == nil: invalidPragma(c, it)
        else:
          incl(sym.typ.flags, tfPartial)
      of wInject, wGensym:
        # We check for errors, but do nothing with these pragmas otherwise
        # as they are handled directly in 'evalTemplate'.
        noVal(c, it)
        if sym == nil: invalidPragma(c, it)
      of wLine: pragmaLine(c, it)
      of wRaises, wTags, wForbids: pragmaRaisesOrTags(c, it)
      of wLocks:
        if sym == nil: pragmaLockStmt(c, it)
        elif sym.typ == nil: invalidPragma(c, it)
        else: warningDeprecated(c.config, n.info, "'Lock levels' are deprecated, now a noop")
      of wBitsize:
        if sym == nil or sym.kind != skField:
          invalidPragma(c, it)
        else:
          sym.bitsize = expectIntLit(c, it)
          if sym.bitsize <= 0:
            localError(c.config, it.info, "bitsize needs to be positive")
      of wGuard:
        if sym == nil or sym.kind notin {skVar, skLet, skField}:
          invalidPragma(c, it)
        else:
          sym.guard = pragmaGuard(c, it, sym.kind)
      of wGoto:
        if sym == nil or sym.kind notin {skVar, skLet}:
          invalidPragma(c, it)
        else:
          sym.flags.incl sfGoto
      of wExportNims:
        if sym == nil: invalidPragma(c, it)
        else: magicsys.registerNimScriptSymbol(c.graph, sym)
      of wExperimental:
        if not isTopLevel(c):
          localError(c.config, n.info, "'experimental' pragma only valid as toplevel statement or in a 'push' environment")
        processExperimental(c, it)
      of wDoctype:
        if not isTopLevel(c):
          localError(c.config, n.info, "\"doctype\" pragma only valid as top-level statement")
      of wNoRewrite:
        noVal(c, it)
      of wBase:
        noVal(c, it)
        sym.flags.incl sfBase
      of wIntDefine:
        processDefineConst(c, n, sym, mIntDefine)
      of wStrDefine:
        processDefineConst(c, n, sym, mStrDefine)
      of wBoolDefine:
        processDefineConst(c, n, sym, mBoolDefine)
      of wUsed:
        noVal(c, it)
        if sym == nil: invalidPragma(c, it)
        else: sym.flags.incl sfUsed
      of wLiftLocals:
        sym.flags.incl(sfForceLift)
      of wRequires, wInvariant, wAssume, wAssert:
        pragmaProposition(c, it)
      of wEnsures:
        pragmaEnsures(c, it)
      of wEnforceNoRaises, wQuirky:
        sym.flags.incl sfNeverRaises
      of wSystemRaisesDefect:
        sym.flags.incl sfSystemRaisesDefect
      of wVirtual:
        processVirtual(c, it, sym, sfVirtual)
      of wMember:
        processVirtual(c, it, sym, sfMember)

      else: invalidPragma(c, it)
    elif comesFromPush and whichKeyword(ident) != wInvalid:
      discard "ignore the .push pragma; it doesn't apply"
    else:
      # semCustomPragma gives appropriate error for invalid pragmas
      n[i] = semCustomPragma(c, it, sym)

proc overwriteLineInfo(n: PNode; info: TLineInfo) =
  n.info = info
  for i in 0..<n.safeLen:
    overwriteLineInfo(n[i], info)

proc mergePragmas(n, pragmas: PNode) =
  var pragmas = copyTree(pragmas)
  overwriteLineInfo pragmas, n.info
  if n[pragmasPos].kind == nkEmpty:
    n[pragmasPos] = pragmas
  else:
    for p in pragmas: n[pragmasPos].add p

proc mergeValidPragmas(n, pragmas: PNode, validPragmas: TSpecialWords) =
  if n[pragmasPos].kind == nkEmpty:
    n[pragmasPos] = newNodeI(nkPragma, n.info)
  for p in pragmas:
    let prag = whichPragma(p)
    if prag in validPragmas:
      let copy = copyTree(p)
      overwriteLineInfo copy, n.info
      n[pragmasPos].add copy

proc implicitPragmas*(c: PContext, sym: PSym, info: TLineInfo,
                      validPragmas: TSpecialWords) =
  if sym != nil and sym.kind != skModule:
    for it in c.optionStack:
      let o = it.otherPragmas
      if not o.isNil and sfFromGeneric notin sym.flags: # bug #23019
        pushInfoContext(c.config, info)
        var i = 0
        while i < o.len:
          if singlePragma(c, sym, o, i, validPragmas, true, false):
            internalError(c.config, info, "implicitPragmas")
          inc i
        popInfoContext(c.config)
        if sym.kind in routineKinds and sym.ast != nil:
          mergeValidPragmas(sym.ast, o, validPragmas)

    if lfExportLib in sym.loc.flags and sfExportc notin sym.flags:
      localError(c.config, info, ".dynlib requires .exportc")
    var lib = c.optionStack[^1].dynlib
    if {lfDynamicLib, lfHeader} * sym.loc.flags == {} and
        sfImportc in sym.flags and lib != nil:
      incl(sym.loc.flags, lfDynamicLib)
      addToLib(lib, sym)
      if sym.loc.snippet == "": sym.loc.snippet = rope(sym.name.s)

proc hasPragma*(n: PNode, pragma: TSpecialWord): bool =
  if n == nil: return false

  for p in n:
    var key = if p.kind in nkPragmaCallKinds and p.len > 1: p[0] else: p
    if key.kind == nkIdent and whichKeyword(key.ident) == pragma:
      return true

  return false

proc pragmaRec(c: PContext, sym: PSym, n: PNode, validPragmas: TSpecialWords;
               isStatement: bool) =
  if n == nil: return
  var i = 0
  while i < n.len:
    if singlePragma(c, sym, n, i, validPragmas, false, isStatement): break
    inc i

proc pragma(c: PContext, sym: PSym, n: PNode, validPragmas: TSpecialWords;
            isStatement: bool) =
  if n == nil: return
  pragmaRec(c, sym, n, validPragmas, isStatement)
  # XXX: in the case of a callable def, this should use its info
  implicitPragmas(c, sym, n.info, validPragmas)

proc pragmaCallable*(c: PContext, sym: PSym, n: PNode, validPragmas: TSpecialWords,
                    isStatement: bool = false) =
  if n == nil: return
  if n[pragmasPos].kind != nkEmpty:
    pragmaRec(c, sym, n[pragmasPos], validPragmas, isStatement)

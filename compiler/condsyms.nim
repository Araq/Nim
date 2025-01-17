#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# This module handles the conditional symbols.

import
  std/strtabs

from options import Feature
from lineinfos import hintMin, hintMax, warnMin, warnMax

proc defineSymbol*(symbols: StringTableRef; symbol: string, value: string = "true") =
  symbols[symbol] = value

proc undefSymbol*(symbols: StringTableRef; symbol: string) =
  symbols.del(symbol)

#proc lookupSymbol*(symbols: StringTableRef; symbol: string): string =
#  result = if isDefined(symbol): gSymbols[symbol] else: nil

iterator definedSymbolNames*(symbols: StringTableRef): string =
  for key in keys(symbols):
    yield key

proc countDefinedSymbols*(symbols: StringTableRef): int =
  symbols.len

proc initDefines*(symbols: StringTableRef) =
  # for bootstrapping purposes and old code:
  template defineSymbol(s) = symbols.defineSymbol(s)
  defineSymbol("nimhygiene") # deadcode
  defineSymbol("niminheritable") # deadcode
  defineSymbol("nimmixin") # deadcode
  defineSymbol("nimeffects") # deadcode
  defineSymbol("nimbabel") # deadcode
  defineSymbol("nimcomputedgoto") # deadcode
  defineSymbol("nimunion") # deadcode
  defineSymbol("nimnewshared") # deadcode
  defineSymbol("nimNewTypedesc") # deadcode
  defineSymbol("nimrequiresnimframe") # deadcode
  defineSymbol("nimparsebiggestfloatmagic") # deadcode
  defineSymbol("nimlocks") # deadcode
  defineSymbol("nimnode") # deadcode
  defineSymbol("nimvarargstyped") # deadcode
  defineSymbol("nimtypedescfixed") # deadcode
  defineSymbol("nimKnowsNimvm") # deadcode
  defineSymbol("nimArrIdx") # deadcode
  defineSymbol("nimHasalignOf") # deadcode
  defineSymbol("nimDistros") # deadcode
  defineSymbol("nimHasCppDefine") # deadcode
  defineSymbol("nimGenericInOutFlags") # deadcode
  when false: defineSymbol("nimHasOpt") # deadcode
  defineSymbol("nimNoArrayToCstringConversion") # deadcode
  defineSymbol("nimHasRunnableExamples") # deadcode
  defineSymbol("nimNewDot") # deadcode
  defineSymbol("nimHasNilChecks") # deadcode
  defineSymbol("nimSymKind") # deadcode
  defineSymbol("nimVmEqIdent") # deadcode
  defineSymbol("nimNoNil") # deadcode
  defineSymbol("nimNoZeroTerminator") # deadcode
  defineSymbol("nimNotNil") # deadcode
  defineSymbol("nimVmExportFixed") # deadcode
  defineSymbol("nimHasSymOwnerInMacro") # deadcode
  defineSymbol("nimNewRuntime") # deadcode
  defineSymbol("nimIncrSeqV3") # deadcode
  defineSymbol("nimAshr") # deadcode
  defineSymbol("nimNoNilSeqs") # deadcode
  defineSymbol("nimNoNilSeqs2") # deadcode
  defineSymbol("nimHasUserErrors") # deadcode
  defineSymbol("nimUncheckedArrayTyp") # deadcode
  defineSymbol("nimHasTypeof") # deadcode
  defineSymbol("nimErrorProcCanHaveBody") # deadcode
  defineSymbol("nimHasInstantiationOfInMacro") # deadcode
  defineSymbol("nimHasHotCodeReloading") # deadcode
  defineSymbol("nimHasNilSeqs") # deadcode
  defineSymbol("nimHasSignatureHashInMacro") # deadcode
  defineSymbol("nimHasDefault") # deadcode
  defineSymbol("nimMacrosSizealignof") # deadcode
  defineSymbol("nimNoZeroExtendMagic") # deadcode
  defineSymbol("nimMacrosGetNodeId") # deadcode
  defineSymbol("nimFixedForwardGeneric") # deadcode
  defineSymbol("nimToOpenArrayCString") # deadcode
  defineSymbol("nimHasUsed") # deadcode
  defineSymbol("nimnomagic64") # deadcode
  defineSymbol("nimNewShiftOps") # deadcode
  defineSymbol("nimHasCursor") # deadcode
  defineSymbol("nimAlignPragma") # deadcode
  defineSymbol("nimHasExceptionsQuery") # deadcode
  defineSymbol("nimHasIsNamedTuple") # deadcode
  defineSymbol("nimHashOrdinalFixed") # deadcode
  defineSymbol("nimHasSinkInference") # deadcode
  defineSymbol("nimNewIntegerOps") # deadcode
  defineSymbol("nimHasInvariant") # deadcode



  for f in Feature:
    defineSymbol("nimHas" & $f)

  for s in warnMin..warnMax:
    defineSymbol("nimHasWarning" & $s)
  for s in hintMin..hintMax:
    defineSymbol("nimHasHint" & $s)

  defineSymbol("nimFixedOwned")
  defineSymbol("nimHasStyleChecks")

  when defined(nimHasLibFFI):
    # Renaming as we can't conflate input vs output define flags; e.g. this
    # will report the right thing regardless of whether user adds
    # `-d:nimHasLibFFI` in his user config.
    defineSymbol("nimHasLibFFIEnabled") # deadcode

  defineSymbol("nimHasStacktraceMsgs") # deadcode
  defineSymbol("nimDoesntTrackDefects")
  defineSymbol("nimHasLentIterators") # deadcode
  defineSymbol("nimHasDeclaredMagic") # deadcode
  defineSymbol("nimHasStacktracesModule") # deadcode
  defineSymbol("nimHasEffectTraitsModule")
  defineSymbol("nimHasCastPragmaBlocks")
  defineSymbol("nimHasDeclaredLocs")
  defineSymbol("nimHasJsBigIntBackend")
  defineSymbol("nimHasWarningAsError")
  defineSymbol("nimHasHintAsError")
  defineSymbol("nimHasSpellSuggest")
  defineSymbol("nimHasCustomLiterals")
  defineSymbol("nimHasUnifiedTuple")
  defineSymbol("nimHasIterable")
  defineSymbol("nimHasTypeofVoid") # deadcode
  defineSymbol("nimHasDragonBox") # deadcode
  defineSymbol("nimHasHintAll")
  defineSymbol("nimHasTrace")
  defineSymbol("nimHasEffectsOf")

  defineSymbol("nimHasEnforceNoRaises")
  defineSymbol("nimHasTopDownInference")
  defineSymbol("nimHasTemplateRedefinitionPragma")
  defineSymbol("nimHasCstringCase")
  defineSymbol("nimHasCallsitePragma")

  defineSymbol("nimHasWarnCastSizes") # deadcode
  defineSymbol("nimHasOutParams")
  defineSymbol("nimHasSystemRaisesDefect")
  defineSymbol("nimHasWarnUnnamedBreak")
  defineSymbol("nimHasGenericDefine")
  defineSymbol("nimHasDefineAliases")
  defineSymbol("nimHasWarnBareExcept")
  defineSymbol("nimHasDup")
  defineSymbol("nimHasChecksums")
  defineSymbol("nimHasSendable")
  defineSymbol("nimAllowNonVarDestructor")
  defineSymbol("nimHasQuirky")
  defineSymbol("nimHasEnsureMove")
  defineSymbol("nimHasNoReturnError")

  defineSymbol("nimUseStrictDefs") # deadcode
  defineSymbol("nimHasNolineTooLong")

  defineSymbol("nimHasCastExtendedVm")
  defineSymbol("nimHasWarnStdPrefix")

  defineSymbol("nimHasVtables")
  defineSymbol("nimHasGenericsOpenSym2")
  defineSymbol("nimHasGenericsOpenSym3")
  defineSymbol("nimHasJsNoLambdaLifting")
  defineSymbol("nimHasDefaultFloatRoundtrip")
  defineSymbol("nimHasXorSet")


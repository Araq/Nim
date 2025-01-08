#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements the style checker.

import std/strutils
from std/sugar import dup

import options, ast, msgs, idents, lineinfos, wordrecg, astmsgs, semdata, packages, modulegraphs
export packages

const
  Letters* = {'a'..'z', 'A'..'Z', '0'..'9', '\x80'..'\xFF', '_'}

proc identLen*(line: string, start: int): int =
  result = 0
  while start+result < line.len and line[start+result] in Letters:
    inc result

proc `=~`(s: string, a: openArray[string]): bool =
  result = false
  for x in a:
    if s.startsWith(x): return true

proc beautifyName(s: string, k: TSymKind): string =
  # minimal set of rules here for transition:
  # GC_ is allowed

  let allUpper = allCharsInSet(s, {'A'..'Z', '0'..'9', '_'})
  if allUpper and k in {skConst, skEnumField, skType}: return s
  result = newStringOfCap(s.len)
  var i = 0
  case k
  of skType, skGenericParam:
    # Types should start with a capital unless builtins like 'int' etc.:
    if s =~ ["int", "uint", "cint", "cuint", "clong", "cstring", "string",
             "char", "byte", "bool", "openArray", "seq", "array", "void",
             "pointer", "float", "csize", "csize_t", "cdouble", "cchar", "cschar",
             "cshort", "cu", "nil", "typedesc", "auto", "any",
             "range", "openarray", "varargs", "set", "cfloat", "ref", "ptr",
             "untyped", "typed", "static", "sink", "lent", "type", "owned", "iterable"]:
      result.add s[i]
    else:
      result.add toUpperAscii(s[i])
  of skConst, skEnumField:
    # for 'const' we keep how it's spelt; either upper case or lower case:
    result.add s[0]
  else:
    # as a special rule, don't transform 'L' to 'l'
    if s.len == 1 and s[0] == 'L': result.add 'L'
    elif '_' in s: result.add(s[i])
    else: result.add toLowerAscii(s[0])
  inc i
  while i < s.len:
    if s[i] == '_':
      if i+1 >= s.len:
        discard "trailing underscores should be stripped off"
      elif i > 0 and s[i-1] in {'A'..'Z'}:
        # don't skip '_' as it's essential for e.g. 'GC_disable'
        result.add('_')
        inc i
        result.add s[i]
      else:
        inc i
        result.add toUpperAscii(s[i])
    elif allUpper:
      result.add toLowerAscii(s[i])
    else:
      result.add s[i]
    inc i

proc differ*(line: string, a, b: int, x: string): string =
  proc substrEq(s: string, pos, last: int, substr: string): bool =
    result = true
    for i in 0..<substr.len:
      if pos+i > last or s[pos+i] != substr[i]: return false

  result = ""
  if not substrEq(line, a, b, x):
    let y = line[a..b]
    if cmpIgnoreStyle(y, x) == 0:
      result = y

proc nep1CheckDefImpl(conf: ConfigRef; info: TLineInfo; s: PSym; k: TSymKind) =
  let beau = beautifyName(s.name.s, k)
  if s.name.s != beau:
    lintReport(conf, info, beau, s.name.s)

template styleCheckDef*(ctx: PContext; info: TLineInfo; sym: PSym; k: TSymKind) =
  ## Check symbol definitions adhere to NEP1 style rules.
  if optStyleCheck in ctx.config.options and # ignore if styleChecks are off
     {optStyleHint, optStyleError} * ctx.config.globalOptions != {} and # check only if hint/error is enabled
     hintName in ctx.config.notes and # ignore if name checks are not requested
     ctx.config.belongsToProjectPackageMaybeNil(getModule(ctx.graph, info.fileIndex)) and # ignore foreign packages
     optStyleUsages notin ctx.config.globalOptions and # ignore if requested to only check name usage
     sym.kind != skResult and # ignore `result`
     sym.kind != skTemp and # ignore temporary variables created by the compiler
     sym.name.s[0] in Letters and # ignore operators TODO: what about unicode symbols???
     k notin {skType, skGenericParam} and # ignore types and generic params
     (sym.typ == nil or sym.typ.kind != tyTypeDesc) and # ignore `typedesc`
     {sfImportc, sfExportc} * sym.flags == {} and # ignore FFI
     sfAnon notin sym.flags: # ignore if created by compiler
    nep1CheckDefImpl(ctx.config, info, sym, k)

template styleCheckDef*(ctx: PContext; info: TLineInfo; s: PSym) =
  ## Check symbol definitions adhere to NEP1 style rules.
  styleCheckDef(ctx, info, s, s.kind)

template styleCheckDef*(ctx: PContext; s: PSym) =
  ## Check symbol definitions adhere to NEP1 style rules.
  styleCheckDef(ctx, s.info, s, s.kind)

proc differs(conf: ConfigRef; info: TLineInfo; newName: string): string =
  let line = sourceLine(conf, info)
  var first = min(info.col.int, line.len)
  if first < 0: return
  #inc first, skipIgnoreCase(line, "proc ", first)
  while first > 0 and line[first-1] in Letters: dec first
  if first < 0: return
  if first+1 < line.len and line[first] == '`': inc first

  let last = first+identLen(line, first)-1
  result = differ(line, first, last, newName)

proc styleCheckUseImpl(conf: ConfigRef; info: TLineInfo; s: PSym) =
  let newName = s.name.s
  let badName = differs(conf, info, newName)
  if badName.len > 0:
    lintReport(conf, info, newName, badName, "".dup(addDeclaredLoc(conf, s)))

template styleCheckUse*(ctx: PContext; info: TLineInfo; sym: PSym) =
  ## Check symbol uses match their definition's style.
  if {optStyleHint, optStyleError} * ctx.config.globalOptions != {} and # ignore if styleChecks are off
     hintName in ctx.config.notes and # ignore if name checks are not requested
     ctx.config.belongsToProjectPackageMaybeNil(getModule(ctx.graph, info.fileIndex)) and # ignore foreign packages
     sym.kind != skTemp and # ignore temporary variables created by the compiler
     sym.name.s[0] in Letters and # ignore operators TODO: what about unicode symbols???
     sfAnon notin sym.flags: # ignore temporary variables created by the compiler
    styleCheckUseImpl(ctx.config, info, sym)

proc checkPragmaUseImpl(conf: ConfigRef; info: TLineInfo; w: TSpecialWord; pragmaName: string) =
  let wanted = $w
  if pragmaName != wanted:
    lintReport(conf, info, wanted, pragmaName)

template checkPragmaUse*(ctx: PContext; info: TLineInfo; w: TSpecialWord; pragmaName: string, sym: PSym) =
  ## Check builtin pragma uses match their definition's style.
  ## Note: This only applies to builtin pragmas, not user pragmas.
  if {optStyleHint, optStyleError} * ctx.config.globalOptions != {} and # ignore if styleChecks are off
     hintName in ctx.config.notes and # ignore if name checks are not requested
     ctx.config.belongsToProjectPackageMaybeNil(getModule(ctx.graph, info.fileIndex)): # ignore foreign packages
    checkPragmaUseImpl(ctx.config, info, w, pragmaName)

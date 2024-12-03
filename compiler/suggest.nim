#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This file implements features required for IDE support.
##
## Due to Nim's nature and the fact that ``system.nim`` is always imported,
## there are lots of potential symbols. Furthermore thanks to templates and
## macros even context based analysis does not help much: In a context like
## ``let x: |`` where a type has to follow, that type might be constructed from
## a template like ``extractField(MyObject, fieldName)``. We deal with this
## problem by smart sorting so that the likely symbols come first. This sorting
## is done this way:
##
## - If there is a prefix (foo|), symbols starting with this prefix come first.
## - If the prefix is part of the name (but the name doesn't start with it),
##   these symbols come second.
## - If we have a prefix, only symbols matching this prefix are returned and
##   nothing else.
## - If we have no prefix, consider the context. We currently distinguish
##   between type and non-type contexts.
## - Finally, sort matches by relevance. The relevance is determined by the
##   number of usages, so ``strutils.replace`` comes before
##   ``strutils.wordWrap``.
## - In any case, sorting also considers scoping information. Local variables
##   get high priority.

# included from sigmatch.nim

import prefixmatches, suggestsymdb
from wordrecg import wDeprecated, wError, wAddr, wYield

import std/[algorithm, sets, parseutils, tables]

when defined(nimsuggest):
  import pathutils # importer

const
  sep = '\t'

#template sectionSuggest(): expr = "##begin\n" & getStackTrace() & "##end\n"

template origModuleName(m: PSym): string = m.name.s

proc findDocComment(n: PNode): PNode =
  if n == nil: return nil
  if n.comment.len > 0: return n
  if n.kind in {nkStmtList, nkStmtListExpr, nkObjectTy, nkRecList} and n.len > 0:
    result = findDocComment(n[0])
    if result != nil: return
    if n.len > 1:
      result = findDocComment(n[1])
  elif n.kind in {nkAsgn, nkFastAsgn, nkSinkAsgn} and n.len == 2:
    result = findDocComment(n[1])
  else:
    result = nil

proc extractDocComment(g: ModuleGraph; s: PSym): string =
  var n = findDocComment(s.ast)
  if n.isNil and s.kind in routineKinds and s.ast != nil:
    n = findDocComment(getBody(g, s))
  if not n.isNil:
    result = n.comment.replace("\n##", "\n").strip
  else:
    result = ""

proc cmpSuggestions(a, b: Suggest): int =
  template cf(field) {.dirty.} =
    result = b.field.int - a.field.int
    if result != 0: return result

  cf prefix
  cf contextFits
  cf scope
  # when the first type matches, it's better when it's a generic match:
  cf quality
  cf localUsages
  cf globalUsages
  # if all is equal, sort alphabetically for deterministic output,
  # independent of hashing order:
  result = cmp(a.name[], b.name[])

proc scanForTrailingAsterisk(line: string, start: int): int =
  result = 0
  while start+result < line.len and line[start+result] in {' ', '\t'}:
    inc result
  if start+result < line.len and line[start+result] == '*':
    inc result
  else:
    result = 0

proc getTokenLenFromSource(conf: ConfigRef; ident: string; info: TLineInfo; skipTrailingAsterisk: bool = false): int =
  let
    line = sourceLine(conf, info)
    column = toColumn(info)

  proc isOpeningBacktick(col: int): bool =
    if col >= 0 and col < line.len:
      if line[col] == '`':
        not isOpeningBacktick(col - 1)
      else:
        isOpeningBacktick(col - 1)
    else:
      false

  if column > line.len:
    result = 0
  elif column > 0 and line[column - 1] == '`' and isOpeningBacktick(column - 1):
    result = skipUntil(line, '`', column)
    if cmpIgnoreStyle(line[column..column + result - 1], ident) != 0:
      result = 0
  elif column >= 0 and line[column] == '`' and isOpeningBacktick(column):
    result = skipUntil(line, '`', column + 1) + 2
    if cmpIgnoreStyle(line[column + 1..column + result - 2], ident) != 0:
      result = 0
  elif ident[0] in linter.Letters and ident[^1] != '=':
    result = identLen(line, column)
    if cmpIgnoreStyle(line[column..column + result - 1], ident[0..min(result-1,len(ident)-1)]) != 0:
      result = 0
    if skipTrailingAsterisk and result > 0:
      result += scanForTrailingAsterisk(line, column + result)
  else:
    var sourceIdent: string = ""
    result = parseWhile(line, sourceIdent,
                        OpChars + {'[', '(', '{', ']', ')', '}'}, column)
    if ident[^1] == '=' and ident[0] in linter.Letters:
      if sourceIdent != "=":
        result = 0
    elif sourceIdent.len > ident.len and sourceIdent[0..ident.high] == ident:
      result = ident.len
    elif sourceIdent != ident:
      result = 0

proc symToSuggest*(g: ModuleGraph; s: PSym, isLocal: bool, section: IdeCmd, info: TLineInfo;
                  quality: range[0..100]; prefix: PrefixMatch;
                  inTypeContext: bool; scope: int;
                  useSuppliedInfo = false,
                  endLine: uint16 = 0,
                  endCol = 0, extractDocs = true): Suggest =
  new(result)
  result.section = section
  result.quality = quality
  result.isGlobal = sfGlobal in s.flags
  result.prefix = prefix
  result.contextFits = inTypeContext == (s.kind in {skType, skGenericParam})
  result.scope = scope
  result.name = addr s.name.s
  when defined(nimsuggest):
    result.globalUsages = s.allUsages.len
    var c = 0
    for u in s.allUsages:
      if u.fileIndex == info.fileIndex: inc c
    result.localUsages = c
  result.symkind = byte s.kind
  if optIdeTerse notin g.config.globalOptions:
    result.qualifiedPath = @[]
    if not isLocal and s.kind != skModule:
      let ow = s.owner
      if ow != nil and ow.kind != skModule and ow.owner != nil:
        let ow2 = ow.owner
        result.qualifiedPath.add(ow2.origModuleName)
      if ow != nil:
        result.qualifiedPath.add(ow.origModuleName)
    if s.name.s[0] in OpChars + {'[', '{', '('} or
       s.name.id in ord(wAddr)..ord(wYield):
      result.qualifiedPath.add('`' & s.name.s & '`')
    else:
      result.qualifiedPath.add(s.name.s)

    if s.typ != nil:
      if section == ideInlayHints:
        result.forth = typeToString(s.typ, preferInlayHint)
      else:
        result.forth = typeToString(s.typ, preferInferredEffects)
    else:
      result.forth = ""
    when defined(nimsuggest) and not defined(noDocgen) and not defined(leanCompiler):
      if extractDocs:
        result.doc = extractDocComment(g, s)
  if s.kind == skModule and s.ast.len != 0 and section != ideHighlight:
    result.filePath = toFullPath(g.config, s.ast[0].info)
    result.line = 1
    result.column = 0
    result.tokenLen = 0
  else:
    let infox =
      if useSuppliedInfo or section in {ideUse, ideHighlight, ideOutline, ideDeclaration}:
        info
      else:
        s.info
    result.filePath = toFullPath(g.config, infox)
    result.line = toLinenumber(infox)
    result.column = toColumn(infox)
    result.tokenLen = if section notin {ideHighlight, ideInlayHints}:
                        s.name.s.len
                      else:
                        getTokenLenFromSource(g.config, s.name.s, infox, section == ideInlayHints)
  result.version = g.config.suggestVersion
  result.endLine = endLine
  result.endCol = endCol

proc `$`*(suggest: SuggestInlayHint): string =
  result = $suggest.kind
  result.add(sep)
  result.add($suggest.line)
  result.add(sep)
  result.add($suggest.column)
  result.add(sep)
  result.add(suggest.label)
  result.add(sep)
  result.add($suggest.paddingLeft)
  result.add(sep)
  result.add($suggest.paddingRight)
  result.add(sep)
  result.add($suggest.allowInsert)
  result.add(sep)
  result.add(suggest.tooltip)

proc `$`*(suggest: Suggest): string =
  if suggest.section == ideInlayHints:
    result = $suggest.inlayHintInfo
  else:
    result = $suggest.section
    result.add(sep)
    if suggest.section == ideHighlight:
      if suggest.symkind.TSymKind == skVar and suggest.isGlobal:
        result.add("skGlobalVar")
      elif suggest.symkind.TSymKind == skLet and suggest.isGlobal:
        result.add("skGlobalLet")
      else:
        result.add($suggest.symkind.TSymKind)
      result.add(sep)
      result.add($suggest.line)
      result.add(sep)
      result.add($suggest.column)
      result.add(sep)
      result.add($suggest.tokenLen)
    else:
      result.add($suggest.symkind.TSymKind)
      result.add(sep)
      if suggest.qualifiedPath.len != 0:
        result.add(suggest.qualifiedPath.join("."))
      result.add(sep)
      result.add(suggest.forth)
      result.add(sep)
      result.add(suggest.filePath)
      result.add(sep)
      result.add($suggest.line)
      result.add(sep)
      result.add($suggest.column)
      result.add(sep)
      when defined(nimsuggest) and not defined(noDocgen) and not defined(leanCompiler):
        result.add(suggest.doc.escape)
      if suggest.version == 0 or suggest.version == 3:
        result.add(sep)
        result.add($suggest.quality)
        if suggest.section == ideSug:
          result.add(sep)
          result.add($suggest.prefix)

    if (suggest.version == 3 and suggest.section in {ideOutline, ideExpand}):
      result.add(sep)
      result.add($suggest.endLine)
      result.add(sep)
      result.add($suggest.endCol)

proc suggestToSuggestInlayTypeHint*(sug: Suggest): SuggestInlayHint =
  SuggestInlayHint(
    kind: sihkType,
    line: sug.line,
    column: sug.column + sug.tokenLen,
    label: ": " & sug.forth,
    paddingLeft: false,
    paddingRight: false,
    allowInsert: true,
    tooltip: ""
  )

proc suggestToSuggestInlayExceptionHintLeft*(sug: Suggest, propagatedExceptions: seq[PType]): SuggestInlayHint =
  SuggestInlayHint(
    kind: sihkException,
    line: sug.line,
    column: sug.column,
    label: "try ",
    paddingLeft: false,
    paddingRight: false,
    allowInsert: false,
    tooltip: "propagated exceptions: " & $propagatedExceptions
  )

proc suggestToSuggestInlayExceptionHintRight*(sug: Suggest, propagatedExceptions: seq[PType]): SuggestInlayHint =
  SuggestInlayHint(
    kind: sihkException,
    line: sug.line,
    column: sug.column + sug.tokenLen,
    label: "!",
    paddingLeft: false,
    paddingRight: false,
    allowInsert: false,
    tooltip: "propagated exceptions: " & $propagatedExceptions
  )

proc suggestResult*(conf: ConfigRef; s: Suggest) =
  if not isNil(conf.suggestionResultHook):
    conf.suggestionResultHook(s)
  else:
    conf.suggestWriteln($s)

proc produceOutput(a: var Suggestions; conf: ConfigRef) =
  if conf.ideCmd in {ideSug, ideCon}:
    a.sort cmpSuggestions
  when defined(debug):
    # debug code
    writeStackTrace()
  if a.len > conf.suggestMaxResults: a.setLen(conf.suggestMaxResults)
  if not isNil(conf.suggestionResultHook):
    for s in a:
      conf.suggestionResultHook(s)
  else:
    for s in a:
      conf.suggestWriteln($s)

proc filterSym(s: PSym; prefix: PNode; res: var PrefixMatch): bool {.inline.} =
  proc prefixMatch(s: PSym; n: PNode): PrefixMatch =
    case n.kind
    of nkIdent: result = n.ident.s.prefixMatch(s.name.s)
    of nkSym: result = n.sym.name.s.prefixMatch(s.name.s)
    of nkOpenSymChoice, nkClosedSymChoice, nkAccQuoted:
      if n.len > 0:
        result = prefixMatch(s, n[0])
      else:
        result = default(PrefixMatch)
    else: result = default(PrefixMatch)
  if s.kind != skModule:
    if prefix != nil:
      res = prefixMatch(s, prefix)
      result = res != PrefixMatch.None
    else:
      result = true
  else:
    result = false

proc filterSymNoOpr(s: PSym; prefix: PNode; res: var PrefixMatch): bool {.inline.} =
  result = filterSym(s, prefix, res) and s.name.s[0] in lexer.SymChars and
     not isKeyword(s.name)

proc fieldVisible*(c: PContext, f: PSym): bool {.inline.} =
  let fmoduleId = getModule(f).id
  result = sfExported in f.flags or fmoduleId == c.module.id

  if not result:
    for module in c.friendModules:
      if fmoduleId == module.id: return true
    if f.kind == skField:
      var symObj = f.owner.typ.toObjectFromRefPtrGeneric.sym
      assert symObj != nil
      for scope in allScopes(c.currentScope):
        for sym in scope.allowPrivateAccess:
          if symObj.id == sym.id: return true

proc getQuality(s: PSym): range[0..100] =
  result = 100
  if s.typ != nil and s.typ.paramsLen > 0:
    var exp = s.typ.firstParamType.skipTypes({tyGenericInst, tyVar, tyLent, tyAlias, tySink})
    if exp.kind == tyVarargs: exp = elemType(exp)
    if exp.kind in {tyUntyped, tyTyped, tyGenericParam, tyAnything}: result = 50

  # penalize deprecated symbols
  if sfDeprecated in s.flags:
    result = result - 5

proc suggestField(c: PContext, s: PSym; f: PNode; info: TLineInfo; outputs: var Suggestions) =
  var pm: PrefixMatch = default(PrefixMatch)
  if filterSym(s, f, pm) and fieldVisible(c, s):
    outputs.add(symToSuggest(c.graph, s, isLocal=true, ideSug, info,
                              s.getQuality, pm, c.inTypeContext > 0, 0))

template wholeSymTab(cond, section: untyped) {.dirty.} =
  for (item, scopeN, isLocal) in uniqueSyms(c):
    let it = item
    var pm: PrefixMatch = default(PrefixMatch)
    if cond:
      outputs.add(symToSuggest(c.graph, it, isLocal = isLocal, section, info, getQuality(it),
                                pm, c.inTypeContext > 0, scopeN))

proc suggestSymList(c: PContext, list, f: PNode; info: TLineInfo, outputs: var Suggestions) =
  for i in 0..<list.len:
    if list[i].kind == nkSym:
      suggestField(c, list[i].sym, f, info, outputs)
    #else: InternalError(list.info, "getSymFromList")

proc suggestObject(c: PContext, n, f: PNode; info: TLineInfo, outputs: var Suggestions) =
  case n.kind
  of nkRecList:
    for i in 0..<n.len: suggestObject(c, n[i], f, info, outputs)
  of nkRecCase:
    if n.len > 0:
      suggestObject(c, n[0], f, info, outputs)
      for i in 1..<n.len: suggestObject(c, lastSon(n[i]), f, info, outputs)
  of nkSym: suggestField(c, n.sym, f, info, outputs)
  else: discard

proc nameFits(c: PContext, s: PSym, n: PNode): bool =
  var op = if n.kind in nkCallKinds: n[0] else: n
  if op.kind in {nkOpenSymChoice, nkClosedSymChoice}: op = op[0]
  if op.kind == nkDotExpr: op = op[1]
  var opr: PIdent
  case op.kind
  of nkSym: opr = op.sym.name
  of nkIdent: opr = op.ident
  else: return false
  result = opr.id == s.name.id

proc argsFit(c: PContext, candidate: PSym, n, nOrig: PNode): bool =
  case candidate.kind
  of OverloadableSyms:
    var m = newCandidate(c, candidate, nil)
    sigmatch.partialMatch(c, n, nOrig, m)
    result = m.state != csNoMatch
  else:
    result = false

proc suggestCall(c: PContext, n, nOrig: PNode, outputs: var Suggestions) =
  let info = n.info
  wholeSymTab(filterSym(it, nil, pm) and nameFits(c, it, n) and argsFit(c, it, n, nOrig),
              ideCon)

proc suggestVar(c: PContext, n: PNode, outputs: var Suggestions) =
  let info = n.info
  wholeSymTab(nameFits(c, it, n), ideCon)

proc typeFits(c: PContext, s: PSym, firstArg: PType): bool {.inline.} =
  if s.typ != nil and s.typ.paramsLen > 0 and s.typ.firstParamType != nil:
    # special rule: if system and some weird generic match via 'tyUntyped'
    # or 'tyGenericParam' we won't list it either to reduce the noise (nobody
    # wants 'system.`-|` as suggestion
    let m = s.getModule()
    if m != nil and sfSystemModule in m.flags:
      if s.kind == skType: return
      var exp = s.typ.firstParamType.skipTypes({tyGenericInst, tyVar, tyLent, tyAlias, tySink})
      if exp.kind == tyVarargs: exp = elemType(exp)
      if exp.kind in {tyUntyped, tyTyped, tyGenericParam, tyAnything}: return
    result = sigmatch.argtypeMatches(c, s.typ.firstParamType, firstArg)
  else:
    result = false

proc suggestOperations(c: PContext, n, f: PNode, typ: PType, outputs: var Suggestions) =
  assert typ != nil
  let info = n.info
  wholeSymTab(filterSymNoOpr(it, f, pm) and typeFits(c, it, typ), ideSug)

proc suggestEverything(c: PContext, n, f: PNode, outputs: var Suggestions) =
  # do not produce too many symbols:
  for (it, scopeN, isLocal) in uniqueSyms(c):
    var pm: PrefixMatch = default(PrefixMatch)
    if filterSym(it, f, pm):
      outputs.add(symToSuggest(c.graph, it, isLocal = isLocal, ideSug, n.info,
                               it.getQuality, pm, c.inTypeContext > 0, scopeN))

proc suggestFieldAccess(c: PContext, n, field: PNode, outputs: var Suggestions) =
  # special code that deals with ``myObj.``. `n` is NOT the nkDotExpr-node, but
  # ``myObj``.
  var typ = n.typ
  var pm: PrefixMatch = default(PrefixMatch)
  when defined(nimsuggest):
    if n.kind == nkSym and n.sym.kind == skError and c.config.suggestVersion == 0:
      # consider 'foo.|' where 'foo' is some not imported module.
      let fullPath = findModule(c.config, n.sym.name.s, toFullPath(c.config, n.info))
      if fullPath.isEmpty:
        # error: no known module name:
        typ = nil
      else:
        let m = c.graph.importModuleCallback(c.graph, c.module, fileInfoIdx(c.config, fullPath))
        if m == nil: typ = nil
        else:
          for it in allSyms(c.graph, n.sym):
            if filterSym(it, field, pm):
              outputs.add(symToSuggest(c.graph, it, isLocal=false, ideSug,
                                        n.info, it.getQuality, pm,
                                        c.inTypeContext > 0, -100))
          outputs.add(symToSuggest(c.graph, m, isLocal=false, ideMod, n.info,
                                    100, PrefixMatch.None, c.inTypeContext > 0,
                                    -99))

  if typ == nil:
    # a module symbol has no type for example:
    if n.kind == nkSym and n.sym.kind == skModule:
      if n.sym == c.module:
        # all symbols accessible, because we are in the current module:
        for it in items(c.topLevelScope.symbols):
          if filterSym(it, field, pm):
            outputs.add(symToSuggest(c.graph, it, isLocal=false, ideSug,
                                      n.info, it.getQuality, pm,
                                      c.inTypeContext > 0, -99))
      else:
        for it in allSyms(c.graph, n.sym):
          if filterSym(it, field, pm):
            outputs.add(symToSuggest(c.graph, it, isLocal=false, ideSug,
                                      n.info, it.getQuality, pm,
                                      c.inTypeContext > 0, -99))
    else:
      # fallback:
      suggestEverything(c, n, field, outputs)
  else:
    let orig = typ
    typ = skipTypes(orig, {tyTypeDesc, tyGenericInst, tyVar, tyLent, tyPtr, tyRef, tyAlias, tySink, tyOwned})

    if typ.kind == tyEnum and n.kind == nkSym and n.sym.kind == skType:
      # look up if the identifier belongs to the enum:
      var t = typ
      while t != nil:
        suggestSymList(c, t.n, field, n.info, outputs)
        t = t.baseClass
    elif typ.kind == tyObject:
      var t = typ
      while true:
        suggestObject(c, t.n, field, n.info, outputs)
        if t.baseClass == nil: break
        t = skipTypes(t.baseClass, skipPtrs)
    elif typ.kind == tyTuple and typ.n != nil:
      # All tuple fields are in scope
      # So go through each field and add it to the suggestions (If it passes the filter)
      for node in typ.n:
        if node.kind == nkSym:
          let s = node.sym
          var pm: PrefixMatch = default(PrefixMatch)
          if filterSym(s, field, pm):
            outputs.add(symToSuggest(c.graph, s, isLocal=true, ideSug, n.info,
                                     s.getQuality, pm, c.inTypeContext > 0, 0))

    suggestOperations(c, n, field, orig, outputs)
    if typ != orig:
      suggestOperations(c, n, field, typ, outputs)

type
  TCheckPointResult* = enum
    cpNone, cpFuzzy, cpExact

proc inCheckpoint*(current, trackPos: TLineInfo): TCheckPointResult =
  if current.fileIndex == trackPos.fileIndex:
    result = cpNone
    if current.line == trackPos.line and
        abs(current.col-trackPos.col) < 4:
      return cpExact
    if current.line >= trackPos.line:
      return cpFuzzy
  else:
    result = cpNone

proc isTracked*(current, trackPos: TLineInfo, tokenLen: int): bool =
  if current.fileIndex==trackPos.fileIndex and current.line==trackPos.line:
    let col = trackPos.col
    if col >= current.col and col <= current.col+tokenLen-1:
      result = true
    else:
      result = false
  else:
    result = false

proc isTracked*(current, trackPos: TinyLineInfo, tokenLen: int): bool =
  if current.line==trackPos.line:
    let col = trackPos.col
    if col >= current.col and col <= current.col+tokenLen-1:
      result = true
    else:
      result = false
  else:
    result = false

when defined(nimsuggest):
  # Since TLineInfo defined a == operator that doesn't include the column,
  # we map TLineInfo to a unique int here for this lookup table:
  proc infoToInt(info: TLineInfo): int64 =
    info.fileIndex.int64 + info.line.int64 shl 32 + info.col.int64 shl 48

  proc addNoDup(s: PSym; info: TLineInfo) =
    # ensure nothing gets too slow:
    if s.allUsages.len > 500: return
    let infoAsInt = info.infoToInt
    for infoB in s.allUsages:
      if infoB.infoToInt == infoAsInt: return
    s.allUsages.add(info)

proc findUsages(g: ModuleGraph; info: TLineInfo; s: PSym; usageSym: var PSym) =
  if g.config.suggestVersion == 1:
    if usageSym == nil and isTracked(info, g.config.m.trackPos, s.name.s.len):
      usageSym = s
      suggestResult(g.config, symToSuggest(g, s, isLocal=false, ideUse, info, 100, PrefixMatch.None, false, 0))
    elif s == usageSym:
      if g.config.lastLineInfo != info:
        suggestResult(g.config, symToSuggest(g, s, isLocal=false, ideUse, info, 100, PrefixMatch.None, false, 0))
      g.config.lastLineInfo = info

when defined(nimsuggest):
  proc listUsages*(g: ModuleGraph; s: PSym) =
    #echo "usages ", s.allUsages.len
    for info in s.allUsages:
      let x = if info == s.info and info.col == s.info.col: ideDef else: ideUse
      suggestResult(g.config, symToSuggest(g, s, isLocal=false, x, info, 100, PrefixMatch.None, false, 0))

proc findDefinition(g: ModuleGraph; info: TLineInfo; s: PSym; usageSym: var PSym) =
  if s.isNil: return
  if isTracked(info, g.config.m.trackPos, s.name.s.len) or (s == usageSym and sfForward notin s.flags):
    suggestResult(g.config, symToSuggest(g, s, isLocal=false, ideDef, info, 100, PrefixMatch.None, false, 0, useSuppliedInfo = s == usageSym))
    if sfForward notin s.flags and g.config.suggestVersion < 3:
      suggestQuit()
    else:
      usageSym = s

proc ensureIdx[T](x: var T, y: int) =
  if x.len <= y: x.setLen(y+1)

proc ensureSeq[T](x: var seq[T]) =
  if x == nil: newSeq(x, 0)

proc suggestSym*(g: ModuleGraph; info: TLineInfo; s: PSym; usageSym: var PSym; isDecl=true) {.inline.} =
  ## misnamed: should be 'symDeclared'
  let conf = g.config
  when defined(nimsuggest):
    g.suggestSymbols.add SymInfoPair(sym: s, info: info, isDecl: isDecl), optIdeExceptionInlayHints in g.config.globalOptions

    if conf.suggestVersion == 0:
      if s.allUsages.len == 0:
        s.allUsages = @[info]
      else:
        s.addNoDup(info)

    if conf.ideCmd == ideUse:
      findUsages(g, info, s, usageSym)
    elif conf.ideCmd == ideDef:
      findDefinition(g, info, s, usageSym)
    elif conf.ideCmd == ideDus and s != nil:
      if isTracked(info, conf.m.trackPos, s.name.s.len):
        suggestResult(conf, symToSuggest(g, s, isLocal=false, ideDef, info, 100, PrefixMatch.None, false, 0))
      findUsages(g, info, s, usageSym)
    elif conf.ideCmd == ideHighlight and info.fileIndex == conf.m.trackPos.fileIndex:
      suggestResult(conf, symToSuggest(g, s, isLocal=false, ideHighlight, info, 100, PrefixMatch.None, false, 0))
    elif conf.ideCmd == ideOutline and isDecl:
      # if a module is included then the info we have is inside the include and
      # we need to walk up the owners until we find the outer most module,
      # which will be the last skModule prior to an skPackage.
      var
        parentFileIndex = info.fileIndex # assume we're in the correct module
        parentModule = s.owner
      while parentModule != nil and parentModule.kind == skModule:
        parentFileIndex = parentModule.info.fileIndex
        parentModule = parentModule.owner

      if parentFileIndex == conf.m.trackPos.fileIndex:
        suggestResult(conf, symToSuggest(g, s, isLocal=false, ideOutline, info, 100, PrefixMatch.None, false, 0))

proc warnAboutDeprecated(conf: ConfigRef; info: TLineInfo; s: PSym) =
  var pragmaNode: PNode
  pragmaNode = if s.kind == skEnumField: extractPragma(s.owner) else: extractPragma(s)
  let name =
    if s.kind == skEnumField and sfDeprecated notin s.flags: "enum '" & s.owner.name.s & "' which contains field '" & s.name.s & "'"
    else: s.name.s
  if pragmaNode != nil:
    for it in pragmaNode:
      if whichPragma(it) == wDeprecated and it.safeLen == 2 and
          it[1].kind in {nkStrLit..nkTripleStrLit}:
        message(conf, info, warnDeprecated, it[1].strVal & "; " & name & " is deprecated")
        return
  message(conf, info, warnDeprecated, name & " is deprecated")

proc userError(conf: ConfigRef; info: TLineInfo; s: PSym) =
  let pragmaNode = extractPragma(s)
  template bail(prefix: string) =
    localError(conf, info, "$1usage of '$2' is an {.error.} defined at $3" %
      [prefix, s.name.s, toFileLineCol(conf, s.ast.info)])
  if pragmaNode != nil:
    for it in pragmaNode:
      if whichPragma(it) == wError and it.safeLen == 2 and
          it[1].kind in {nkStrLit..nkTripleStrLit}:
        bail(it[1].strVal & "; ")
        return
  bail("")

proc markOwnerModuleAsUsed(c: PContext; s: PSym) =
  var module = s
  while module != nil and module.kind != skModule:
    module = module.owner
  if module != nil and module != c.module:
    var i = 0
    while i <= high(c.unusedImports):
      let candidate = c.unusedImports[i][0]
      if candidate == module or c.importModuleMap.getOrDefault(candidate.id, int.low) == module.id or
        c.exportIndirections.contains((candidate.id, s.id)):
        # mark it as used:
        c.unusedImports.del(i)
      else:
        inc i

proc markUsed(c: PContext; info: TLineInfo; s: PSym; checkStyle = true) =
  let conf = c.config
  incl(s.flags, sfUsed)
  if s.kind == skEnumField and s.owner != nil:
    incl(s.owner.flags, sfUsed)
    if sfDeprecated in s.owner.flags:
      warnAboutDeprecated(conf, info, s)
  if {sfDeprecated, sfError} * s.flags != {}:
    if sfDeprecated in s.flags:
      if not (c.lastTLineInfo.line == info.line and
              c.lastTLineInfo.col == info.col):
        warnAboutDeprecated(conf, info, s)
        c.lastTLineInfo = info

    if sfError in s.flags: userError(conf, info, s)
  when defined(nimsuggest):
    suggestSym(c.graph, info, s, c.graph.usageSym, false)
  if checkStyle:
    styleCheckUse(c, info, s)
  markOwnerModuleAsUsed(c, s)

proc safeSemExpr*(c: PContext, n: PNode): PNode =
  # use only for idetools support!
  try:
    result = c.semExpr(c, n)
  except ERecoverableError:
    result = c.graph.emptyNode

proc sugExpr(c: PContext, n: PNode, outputs: var Suggestions) =
  if n.kind == nkDotExpr:
    var obj = safeSemExpr(c, n[0])
    # it can happen that errnously we have collected the fieldname
    # of the next line, so we check the 'field' is actually on the same
    # line as the object to prevent this from happening:
    let prefix = if n.len == 2 and n[1].info.line == n[0].info.line and
       not c.config.m.trackPosAttached: n[1] else: nil
    suggestFieldAccess(c, obj, prefix, outputs)

    #if optIdeDebug in gGlobalOptions:
    #  echo "expression ", renderTree(obj), " has type ", typeToString(obj.typ)
    #writeStackTrace()
  elif n.kind == nkIdent:
    let
      prefix = if c.config.m.trackPosAttached: nil else: n
      info = n.info
    wholeSymTab(filterSym(it, prefix, pm), ideSug)
  else:
    let prefix = if c.config.m.trackPosAttached: nil else: n
    suggestEverything(c, n, prefix, outputs)

proc suggestExprNoCheck*(c: PContext, n: PNode) =
  # This keeps semExpr() from coming here recursively:
  if c.compilesContextId > 0: return
  inc(c.compilesContextId)
  var outputs: Suggestions = @[]
  if c.config.ideCmd == ideSug:
    sugExpr(c, n, outputs)
  elif c.config.ideCmd == ideCon:
    if n.kind in nkCallKinds:
      var a = copyNode(n)
      var x = safeSemExpr(c, n[0])
      if x.kind == nkEmpty or x.typ == nil: x = n[0]
      a.add x
      for i in 1..<n.len:
        # use as many typed arguments as possible:
        var x = safeSemExpr(c, n[i])
        if x.kind == nkEmpty or x.typ == nil: break
        a.add x
      suggestCall(c, a, n, outputs)
    elif n.kind in nkIdentKinds:
      var x = safeSemExpr(c, n)
      if x.kind == nkEmpty or x.typ == nil: x = n
      suggestVar(c, x, outputs)

  dec(c.compilesContextId)
  if outputs.len > 0 and c.config.ideCmd in {ideSug, ideCon, ideDef}:
    produceOutput(outputs, c.config)
    suggestQuit()

proc suggestExpr*(c: PContext, n: PNode) =
  if exactEquals(c.config.m.trackPos, n.info): suggestExprNoCheck(c, n)

proc suggestDecl*(c: PContext, n: PNode; s: PSym) =
  let attached = c.config.m.trackPosAttached
  if attached: inc(c.inTypeContext)
  defer:
    if attached: dec(c.inTypeContext)
  # If user is typing out an enum field, then don't provide suggestions
  if s.kind == skEnumField and c.config.cmd == cmdIdeTools and exactEquals(c.config.m.trackPos, n.info):
    suggestQuit()
  suggestExpr(c, n)

proc suggestStmt*(c: PContext, n: PNode) =
  suggestExpr(c, n)

proc suggestEnum*(c: PContext; n: PNode; t: PType) =
  var outputs: Suggestions = @[]
  suggestSymList(c, t.n, nil, n.info, outputs)
  produceOutput(outputs, c.config)
  if outputs.len > 0: suggestQuit()

proc suggestPragmas*(c: PContext, n: PNode) =
  ## Suggests anything that might be a pragma
  ## - template that has {.pragma.}
  ## - macros
  ## - user pragmas
  let info = n.info
  var outputs: Suggestions = @[]
  # First filter for template/macros
  wholeSymTab(filterSym(it, n, pm) and
    (sfCustomPragma in it.flags or it.kind == skMacro),
    ideSug)

  # Now show suggestions for user pragmas
  for pragma in c.userPragmas:
    var pm = default(PrefixMatch)
    if filterSym(pragma, n, pm):
      outputs &= symToSuggest(c.graph, pragma, isLocal=true, ideSug, info,
                                pragma.getQuality, pm, c.inTypeContext > 0, 0,
                                extractDocs=false)

  produceOutput(outputs, c.config)
  if outputs.len > 0:
    suggestQuit()

template trySuggestPragmas*(c: PContext, n: PNode) =
  ## Runs [suggestPragmas] when compiling nimsuggest and
  ## we are querying the node
  when defined(nimsuggest):
    let tmp = n
    if c.config.ideCmd == ideSug and exactEquals(c.config.m.trackPos, tmp.info):
      suggestPragmas(c, tmp)

proc suggestSentinel*(c: PContext) =
  if c.config.ideCmd != ideSug or c.module.position != c.config.m.trackPos.fileIndex.int32: return
  if c.compilesContextId > 0: return
  inc(c.compilesContextId)
  var outputs: Suggestions = @[]
  # suggest everything:
  for (it, scopeN, isLocal) in uniqueSyms(c):
    var pm: PrefixMatch = default(PrefixMatch)
    if filterSymNoOpr(it, nil, pm):
      outputs.add(symToSuggest(c.graph, it, isLocal = isLocal, ideSug,
          newLineInfo(c.config.m.trackPos.fileIndex, 0, -1), it.getQuality,
          PrefixMatch.None, false, scopeN))

  dec(c.compilesContextId)
  produceOutput(outputs, c.config)

when defined(nimsuggest):
  proc onDef(graph: ModuleGraph, s: PSym, info: TLineInfo) =
    if graph.config.suggestVersion >= 3 and info.exactEquals(s.info):
       suggestSym(graph, info, s, graph.usageSym)

  template getPContext(): untyped =
    when c is PContext: c
    else: c.c

  template onDef*(info: TLineInfo; s: PSym) =
    let c = getPContext()
    onDef(c.graph, s, info)

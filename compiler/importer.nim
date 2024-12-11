#
#
#           The Nim Compiler
#        (c) Copyright 2013 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements the symbol importing mechanism.

import
  ast, astalgo, msgs, options, idents, lookups,
  semdata, modulepaths, sigmatch, lineinfos,
  modulegraphs, wordrecg
from std/strutils import `%`, startsWith
from std/sequtils import addUnique
import std/[sets, tables, intsets]

when defined(nimPreviewSlimSystem):
  import std/assertions

proc readExceptSet*(c: PContext, n: PNode): IntSet =
  assert n.kind in {nkImportExceptStmt, nkExportExceptStmt}
  result = initIntSet()
  for i in 1..<n.len:
    let ident = lookups.considerQuotedIdent(c, n[i])
    result.incl(ident.id)

proc declarePureEnumField*(c: PContext; s: PSym) =
  # XXX Remove the outer 'if' statement and see what breaks.
  var amb = false
  if someSymFromImportTable(c, s.name, amb) == nil:
    strTableAdd(c.pureEnumFields, s)
    when false:
      let checkB = strTableGet(c.pureEnumFields, s.name)
      if checkB == nil:
        strTableAdd(c.pureEnumFields, s)
    when false:
      # mark as ambiguous:
      incl(c.ambiguousSymbols, checkB.id)
      incl(c.ambiguousSymbols, s.id)

proc importPureEnumField(c: PContext; s: PSym) =
  var amb = false
  if someSymFromImportTable(c, s.name, amb) == nil:
    strTableAdd(c.pureEnumFields, s)
    when false:
      let checkB = strTableGet(c.pureEnumFields, s.name)
      if checkB == nil:
        strTableAdd(c.pureEnumFields, s)
    when false:
      # mark as ambiguous:
      incl(c.ambiguousSymbols, checkB.id)
      incl(c.ambiguousSymbols, s.id)

proc importPureEnumFields(c: PContext; s: PSym; etyp: PType) =
  assert sfPure in s.flags
  for j in 0..<etyp.n.len:
    var e = etyp.n[j].sym
    if e.kind != skEnumField:
      internalError(c.config, s.info, "rawImportSymbol")
      # BUGFIX: because of aliases for enums the symbol may already
      # have been put into the symbol table
      # BUGFIX: but only iff they are the same symbols!
    for check in importedItems(c, e.name):
      if check.id == e.id:
        e = nil
        break
    if e != nil:
      importPureEnumField(c, e)

proc rawImportSymbol(c: PContext, s, origin: PSym; importSet: var IntSet) =
  # This does not handle stubs, because otherwise loading on demand would be
  # pointless in practice. So importing stubs is fine here!
  # check if we have already a symbol of the same name:
  when false:
    var check = someSymFromImportTable(c, s.name)
    if check != nil and check.id != s.id:
      if s.kind notin OverloadableSyms or check.kind notin OverloadableSyms:
        # s and check need to be qualified:
        incl(c.ambiguousSymbols, s.id)
        incl(c.ambiguousSymbols, check.id)
  # thanks to 'export' feature, it could be we import the same symbol from
  # multiple sources, so we need to call 'strTableAdd' here:
  when false:
    # now lazy. Speeds up the compiler and is a prerequisite for IC.
    strTableAdd(c.importTable.symbols, s)
  else:
    importSet.incl s.id
  if s.kind == skType:
    var etyp = s.typ
    if etyp.kind in {tyBool, tyEnum}:
      for j in 0..<etyp.n.len:
        var e = etyp.n[j].sym
        if e.kind != skEnumField:
          internalError(c.config, s.info, "rawImportSymbol")
          # BUGFIX: because of aliases for enums the symbol may already
          # have been put into the symbol table
          # BUGFIX: but only iff they are the same symbols!
        for check in importedItems(c, e.name):
          if check.id == e.id:
            e = nil
            break
        if e != nil:
          if sfPure notin s.flags:
            rawImportSymbol(c, e, origin, importSet)
          else:
            importPureEnumField(c, e)
  else:
    if s.kind == skConverter: addConverter(c, LazySym(sym: s))
    if hasPattern(s): addPattern(c, LazySym(sym: s))
  if s.owner != origin:
    c.exportIndirections.incl((origin.id, s.id))

proc splitPragmas(c: PContext, n: PNode): (PNode, seq[TSpecialWord]) =
  template bail = globalError(c.config, n.info, "invalid pragma")
  result = (nil, @[])
  if n.kind == nkPragmaExpr:
    if n.len == 2 and n[1].kind == nkPragma:
      result[0] = n[0]
      for ni in n[1]:
        if ni.kind == nkIdent: result[1].add whichKeyword(ni.ident)
        else: bail()
    else: bail()
  else:
    result[0] = n
    if result[0].safeLen > 0:
      (result[0][^1], result[1]) = splitPragmas(c, result[0][^1])

proc importSymbol(c: PContext, n: PNode, fromMod: PSym; importSet: var IntSet) =
  let (n, kws) = splitPragmas(c, n)
  if kws.len > 0:
    globalError(c.config, n.info, "unexpected pragma")

  let ident = lookups.considerQuotedIdent(c, n)
  let s = someSym(c.graph, fromMod, ident)
  if s == nil:
    errorUndeclaredIdentifier(c, n.info, ident.s)
  else:
    when false:
      if s.kind == skStub: loadStub(s)
    let multiImport = s.kind notin ExportableSymKinds or s.kind in skProcKinds
    # for an enumeration we have to add all identifiers
    if multiImport:
      # for a overloadable syms add all overloaded routines
      var it: ModuleIter = default(ModuleIter)
      var e = initModuleIter(it, c.graph, fromMod, s.name)
      while e != nil:
        if e.name.id != s.name.id: internalError(c.config, n.info, "importSymbol: 3")
        if s.kind in ExportableSymKinds:
          rawImportSymbol(c, e, fromMod, importSet)
        e = nextModuleIter(it, c.graph)
    else:
      rawImportSymbol(c, s, fromMod, importSet)
    suggestSym(c.graph, n.info, s, c.graph.usageSym, false)

proc addImport(c: PContext; im: sink ImportedModule) =
  for i in 0..high(c.imports):
    if c.imports[i].m == im.m:
      # we have already imported the module: Check which import
      # is more "powerful":
      case c.imports[i].mode
      of importAll: discard "already imported all symbols"
      of importSet:
        case im.mode
        of importAll, importExcept:
          # XXX: slightly wrong semantics for 'importExcept'...
          # But we should probably change the spec and disallow this case.
          c.imports[i] = im
        of importSet:
          # merge the import sets:
          c.imports[i].imported.incl im.imported
      of importExcept:
        case im.mode
        of importAll:
          c.imports[i] = im
        of importSet:
          discard
        of importExcept:
          var cut = initIntSet()
          # only exclude what is consistent between the two sets:
          for j in im.exceptSet:
            if j in c.imports[i].exceptSet:
              cut.incl j
          c.imports[i].exceptSet = cut
      return
  c.imports.add im

template addUnnamedIt(c: PContext, fromMod: PSym; filter: untyped) {.dirty.} =
  for it in mitems c.graph.ifaces[fromMod.position].converters:
    if filter:
      loadPackedSym(c.graph, it)
      if sfExported in it.sym.flags:
        addConverter(c, it)
  for it in mitems c.graph.ifaces[fromMod.position].patterns:
    if filter:
      loadPackedSym(c.graph, it)
      if sfExported in it.sym.flags:
        addPattern(c, it)
  for it in mitems c.graph.ifaces[fromMod.position].pureEnums:
    if filter:
      loadPackedSym(c.graph, it)
      importPureEnumFields(c, it.sym, it.sym.typ)

proc importAllSymbolsExcept(c: PContext, fromMod: PSym, exceptSet: IntSet) =
  c.addImport ImportedModule(m: fromMod, mode: importExcept, exceptSet: exceptSet)
  addUnnamedIt(c, fromMod, it.sym.name.id notin exceptSet)

proc importAllSymbols*(c: PContext, fromMod: PSym) =
  c.addImport ImportedModule(m: fromMod, mode: importAll)
  addUnnamedIt(c, fromMod, true)
  when false:
    var exceptSet: IntSet
    importAllSymbolsExcept(c, fromMod, exceptSet)

proc importForwarded(c: PContext, n: PNode, exceptSet: IntSet; fromMod: PSym; importSet: var IntSet) =
  if n.isNil: return
  case n.kind
  of nkExportStmt:
    for a in n:
      assert a.kind == nkSym
      let s = a.sym
      if s.kind == skModule:
        importAllSymbolsExcept(c, s, exceptSet)
      elif exceptSet.isNil or s.name.id notin exceptSet:
        rawImportSymbol(c, s, fromMod, importSet)
  of nkExportExceptStmt:
    localError(c.config, n.info, "'export except' not implemented")
  else:
    for i in 0..n.safeLen-1:
      importForwarded(c, n[i], exceptSet, fromMod, importSet)

proc importModuleAs(c: PContext; n: PNode, realModule: PSym, importHidden: bool): PSym =
  result = realModule
  template createModuleAliasImpl(ident): untyped =
    createModuleAlias(realModule, c.idgen, ident, n.info, c.config.options)
  if n.kind != nkImportAs: discard
  elif n.len != 2 or n[1].kind != nkIdent:
    localError(c.config, n.info, "module alias must be an identifier")
  elif n[1].ident.id != realModule.name.id:
    # some misguided guy will write 'import abc.foo as foo' ...
    result = createModuleAliasImpl(n[1].ident)
  if result == realModule:
    # avoids modifying `realModule`, see D20201209T194412 for `import {.all.}`
    result = createModuleAliasImpl(realModule.name)
  if importHidden:
    result.options.incl optImportHidden
  let moduleIdent = if n.kind in {nkInfix, nkImportAs}: n[^1] else: n
  result.info = moduleIdent.info
  c.unusedImports.add((result, result.info))
  c.importModuleMap[result.id] = realModule.id
  c.importModuleLookup.mgetOrPut(result.name.id, @[]).addUnique realModule.id

proc transformImportAs(c: PContext; n: PNode): tuple[node: PNode, importHidden: bool] =
  result = (nil, false)
  var ret = default(typeof(result))
  proc processPragma(n2: PNode): PNode =
    let (result2, kws) = splitPragmas(c, n2)
    result = result2
    for ai in kws:
      case ai
      of wImportHidden: ret.importHidden = true
      else: globalError(c.config, n.info, "invalid pragma, expected: " & ${wImportHidden})

  if n.kind == nkInfix and considerQuotedIdent(c, n[0]).s == "as":
    ret.node = newNodeI(nkImportAs, n.info)
    ret.node.add n[1].processPragma
    ret.node.add n[2]
  else:
    ret.node = n.processPragma
  return ret

proc myImportModule(c: PContext, n: var PNode, importStmtResult: PNode): PSym =
  let transf = transformImportAs(c, n)
  n = transf.node
  let f = checkModuleName(c.config, n)
  if f != InvalidFileIdx:
    addImportFileDep(c, f)
    let L = c.graph.importStack.len
    let recursion = c.graph.importStack.find(f)
    c.graph.importStack.add f
    #echo "adding ", toFullPath(f), " at ", L+1
    if recursion >= 0:
      var err = ""
      for i in recursion..<L:
        if i > recursion: err.add "\n"
        err.add toFullPath(c.config, c.graph.importStack[i]) & " imports " &
                toFullPath(c.config, c.graph.importStack[i+1])
      c.recursiveDep = err

    var realModule: PSym
    discard pushOptionEntry(c)
    realModule = c.graph.importModuleCallback(c.graph, c.module, f)
    result = importModuleAs(c, n, realModule, transf.importHidden)
    popOptionEntry(c)

    #echo "set back to ", L
    c.graph.importStack.setLen(L)
    # we cannot perform this check reliably because of
    # test: modules/import_in_config) # xxx is that still true?
    if realModule == c.module:
      localError(c.config, n.info, "module '$1' cannot import itself" % realModule.name.s)
    if sfDeprecated in realModule.flags:
      var prefix = ""
      if realModule.constraint != nil: prefix = realModule.constraint.strVal & "; "
      message(c.config, n.info, warnDeprecated, prefix & realModule.name.s & " is deprecated")
    let moduleName = getModuleName(c.config, n)
    if belongsToStdlib(c.graph, result) and not startsWith(moduleName, stdPrefix) and
        not startsWith(moduleName, "system/") and not startsWith(moduleName, "packages/"):
      message(c.config, n.info, warnStdPrefix, realModule.name.s)

    proc suggestMod(n: PNode; s: PSym) =
      if n.kind == nkImportAs:
        suggestMod(n[0], realModule)
      elif n.kind == nkInfix:
        suggestMod(n[2], s)
      else:
        suggestSym(c.graph, n.info, s, c.graph.usageSym, false)
    suggestMod(n, result)
    importStmtResult.add newSymNode(result, n.info)
    #newStrNode(toFullPath(c.config, f), n.info)
  else:
    result = nil

proc afterImport(c: PContext, m: PSym) =
  if isCachedModule(c.graph, m): return
  # fixes bug #17510, for re-exported symbols
  let realModuleId = c.importModuleMap[m.id]
  for s in allSyms(c.graph, m):
    if s.owner.id != realModuleId:
      c.exportIndirections.incl((m.id, s.id))

proc impMod(c: PContext; it: PNode; importStmtResult: PNode) =
  var it = it
  let m = myImportModule(c, it, importStmtResult)
  if m != nil:
    # ``addDecl`` needs to be done before ``importAllSymbols``!
    addDecl(c, m) # add symbol to symbol table of module
    importAllSymbols(c, m)
    #importForwarded(c, m.ast, emptySet, m)
    afterImport(c, m)

proc evalImport*(c: PContext, n: PNode): PNode =
  result = newNodeI(nkImportStmt, n.info)
  for i in 0..<n.len:
    let it = n[i]
    if it.kind in {nkInfix, nkPrefix} and it[^1].kind == nkBracket:
      let lastPos = it.len - 1
      var imp = copyNode(it)
      newSons(imp, it.len)
      for i in 0 ..< lastPos: imp[i] = it[i]
      imp[lastPos] = imp[0] # dummy entry, replaced in the loop
      for x in it[lastPos]:
        # transform `a/b/[c as d]` to `/a/b/c as d`
        if x.kind == nkInfix and x[0].ident.s == "as":
          var impAs = copyNode(x)
          newSons(impAs, 3)
          impAs[0] = x[0]
          imp[lastPos] = x[1]
          impAs[1] = imp
          impAs[2] = x[2]
          impMod(c, impAs, result)
        else:
          imp[lastPos] = x
          impMod(c, imp, result)
    else:
      impMod(c, it, result)

proc evalFrom*(c: PContext, n: PNode): PNode =
  result = newNodeI(nkImportStmt, n.info)
  checkMinSonsLen(n, 2, c.config)
  var m = myImportModule(c, n[0], result)
  if m != nil:
    n[0] = newSymNode(m)
    addDecl(c, m)               # add symbol to symbol table of module

    var im = ImportedModule(m: m, mode: importSet, imported: initIntSet())
    for i in 1..<n.len:
      if n[i].kind != nkNilLit:
        importSymbol(c, n[i], m, im.imported)
    c.addImport im
    afterImport(c, m)

proc evalImportExcept*(c: PContext, n: PNode): PNode =
  result = newNodeI(nkImportStmt, n.info)
  checkMinSonsLen(n, 2, c.config)
  var m = myImportModule(c, n[0], result)
  if m != nil:
    n[0] = newSymNode(m)
    addDecl(c, m)               # add symbol to symbol table of module
    importAllSymbolsExcept(c, m, readExceptSet(c, n))
    #importForwarded(c, m.ast, exceptSet, m)
    afterImport(c, m)

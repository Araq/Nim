#
#
#           The Nim Compiler
#        (c) Copyright 2021 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Dead code elimination (=DCE) for IC.

import std/[intsets, tables]

when defined(nimPreviewSlimSystem):
  import std/assertions

import ".." / [ast, options, lineinfos, types]

import packed_ast, ic, bitabs

type
  AliveSyms* = seq[IntSet]
  AliveContext* = object ## Purpose is to fill the 'alive' field.
    stack: seq[(int, TOptions, NodePos)] ## A stack for marking symbols as alive.
    decoder: PackedDecoder ## We need a PackedDecoder for module ID address translations.
    thisModule: int  ## The module we're currently analysing for DCE.
    alive: AliveSyms ## The final result of our computation.
    options: TOptions
    compilerProcs: Table[string, (int, int32)]

proc isExportedToC(c: var AliveContext; g: PackedModuleGraph; symId: int32): bool =
  ## "Exported to C" procs are special (these are marked with '.exportc') because these
  ## must not be optimized away!
  let symPtr = unsafeAddr g[c.thisModule].fromDisk.syms[symId]
  let flags = symPtr.flags
  # due to a bug/limitation in the lambda lifting, unused inner procs
  # are not transformed correctly; issue (#411). However, the whole purpose here
  # is to eliminate unused procs. So there is no special logic required for this case.
  if sfCompileTime notin flags:
    if ({sfExportc, sfCompilerProc} * flags != {}) or
        (symPtr.kind == skMethod):
      result = true
    else:
      result = false
      # XXX: This used to be a condition to:
      #  (sfExportc in prc.flags and lfExportLib in prc.loc.flags) or
    if sfCompilerProc in flags:
      c.compilerProcs[g[c.thisModule].fromDisk.strings[symPtr.name]] = (c.thisModule, symId)
  else:
    result = false

template isNotGeneric(n: NodePos): bool = ithSon(tree, n, genericParamsPos).kind == nkEmpty

proc followLater(c: var AliveContext; g: PackedModuleGraph; module: int; item: int32) =
  ## Marks a symbol 'item' as used and later in 'followNow' the symbol's body will
  ## be analysed.
  if not c.alive[module].containsOrIncl(item):
    var body = g[module].fromDisk.syms[item].ast
    if body != emptyNodeId:
      let opt = g[module].fromDisk.syms[item].options
      if g[module].fromDisk.syms[item].kind in routineKinds:
        body = NodeId ithSon(g[module].fromDisk.bodies, NodePos body, bodyPos)
      c.stack.add((module, opt, NodePos(body)))

    when false:
      let nid = g[module].fromDisk.syms[item].name
      if nid != LitId(0):
        let name = g[module].fromDisk.strings[nid]
        if name in ["nimFrame", "callDepthLimitReached"]:
          echo "I was called! ", name, " body exists: ", body != emptyNodeId, " ", module, " ", item

proc requestCompilerProc(c: var AliveContext; g: PackedModuleGraph; name: string) =
  let (module, item) = c.compilerProcs[name]
  followLater(c, g, module, item)

proc loadTypeKind(t: PackedItemId; c: AliveContext; g: PackedModuleGraph; toSkip: set[TTypeKind]): TTypeKind =
  template kind(t: ItemId): TTypeKind = g[t.module].fromDisk.types[t.item].kind

  var t2 = translateId(t, g, c.thisModule, c.decoder.config)
  result = t2.kind
  while result in toSkip:
    t2 = translateId(g[t2.module].fromDisk.types[t2.item].types[^1], g, t2.module, c.decoder.config)
    result = t2.kind

proc rangeCheckAnalysis(c: var AliveContext; g: PackedModuleGraph; tree: PackedTree; n: NodePos) =
  ## Replicates the logic of `ccgexprs.genRangeChck`.
  ## XXX Refactor so that the duplicated logic is avoided. However, for now it's not clear
  ## the approach has enough merit.
  var dest = loadTypeKind(n.typ, c, g, abstractVar)
  if optRangeCheck notin c.options or dest in {tyUInt..tyUInt64}:
    discard "no need to generate a check because it was disabled"
  else:
    let n0t = loadTypeKind(n.firstSon.typ, c, g, {})
    if n0t in {tyUInt, tyUInt64}:
      c.requestCompilerProc(g, "raiseRangeErrorNoArgs")
    else:
      let raiser =
        case loadTypeKind(n.typ, c, g, abstractVarRange)
        of tyUInt..tyUInt64, tyChar: "raiseRangeErrorU"
        of tyFloat..tyFloat128: "raiseRangeErrorF"
        else: "raiseRangeErrorI"
      c.requestCompilerProc(g, raiser)

proc aliveCode(c: var AliveContext; g: PackedModuleGraph; tree: PackedTree; n: NodePos) =
  ## Marks the symbols we encounter when we traverse the AST at `tree[n]` as alive, unless
  ## it is purely in a declarative context (type section etc.).
  case n.kind
  of nkNone..pred(nkSym), succ(nkSym)..nkNilLit:
    discard "ignore non-sym atoms"
  of nkSym:
    # This symbol is alive and everything its body references.
    followLater(c, g, c.thisModule, tree[n].soperand)
  of nkModuleRef:
    let (n1, n2) = sons2(tree, n)
    assert n1.kind == nkNone
    assert n2.kind == nkNone
    let m = n1.litId
    let item = tree[n2].soperand
    let otherModule = toFileIndexCached(c.decoder, g, c.thisModule, m).int
    followLater(c, g, otherModule, item)
  of nkMacroDef, nkTemplateDef, nkTypeSection, nkTypeOfExpr,
     nkCommentStmt, nkIncludeStmt,
     nkImportStmt, nkImportExceptStmt, nkExportStmt, nkExportExceptStmt,
     nkFromStmt, nkStaticStmt:
    discard
  of nkVarSection, nkLetSection, nkConstSection:
    # XXX ignore the defining local variable name?
    for son in sonsReadonly(tree, n):
      aliveCode(c, g, tree, son)
  of nkChckRangeF, nkChckRange64, nkChckRange:
    rangeCheckAnalysis(c, g, tree, n)
  of nkProcDef, nkConverterDef, nkMethodDef, nkFuncDef, nkIteratorDef:
    if n.firstSon.kind == nkSym and isNotGeneric(n):
      let item = tree[n.firstSon].soperand
      if isExportedToC(c, g, item):
        # This symbol is alive and everything its body references.
        followLater(c, g, c.thisModule, item)
  else:
    for son in sonsReadonly(tree, n):
      aliveCode(c, g, tree, son)

proc followNow(c: var AliveContext; g: PackedModuleGraph) =
  ## Mark all entries in the stack. Marking can add more entries
  ## to the stack but eventually we have looked at every alive symbol.
  while c.stack.len > 0:
    let (modId, opt, ast) = c.stack.pop()
    c.thisModule = modId
    c.options = opt
    aliveCode(c, g, g[modId].fromDisk.bodies, ast)

proc computeAliveSyms*(g: PackedModuleGraph; conf: ConfigRef): AliveSyms =
  ## Entry point for our DCE algorithm.
  var c = AliveContext(stack: @[], decoder: PackedDecoder(config: conf),
                       thisModule: -1, alive: newSeq[IntSet](g.len),
                       options: conf.options)
  for i in countdown(len(g)-1, 0):
    if g[i].status != undefined:
      c.thisModule = i
      for p in allNodes(g[i].fromDisk.topLevel):
        aliveCode(c, g, g[i].fromDisk.topLevel, p)

  followNow(c, g)
  result = move(c.alive)

proc isAlive*(a: AliveSyms; module: int, item: int32): bool =
  ## Backends use this to query if a symbol is `alive` which means
  ## we need to produce (C/C++/etc) code for it.
  result = a[module].contains(item)


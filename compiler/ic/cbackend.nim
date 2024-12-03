#
#
#           The Nim Compiler
#        (c) Copyright 2021 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## New entry point into our C/C++ code generator. Ideally
## somebody would rewrite the old backend (which is 8000 lines of crufty Nim code)
## to work on packed trees directly and produce the C code as an AST which can
## then be rendered to text in a very simple manner. Unfortunately nobody wrote
## this code. So instead we wrap the existing cgen.nim and its friends so that
## we call directly into the existing code generation logic but avoiding the
## naive, outdated `passes` design. Thus you will see some
## `useAliveDataFromDce in flags` checks in the old code -- the old code is
## also doing cross-module dependency tracking and DCE that we don't need
## anymore. DCE is now done as prepass over the entire packed module graph.

import std/[packedsets, algorithm, tables]

when defined(nimPreviewSlimSystem):
  import std/assertions

import ".."/[ast, options, lineinfos, modulegraphs, cgendata, cgen,
  pathutils, extccomp, msgs, modulepaths]

import packed_ast, ic, dce, rodfiles

proc unpackTree(g: ModuleGraph; thisModule: int;
                tree: PackedTree; n: NodePos): PNode =
  var decoder = initPackedDecoder(g.config, g.cache)
  result = loadNodes(decoder, g.packed, thisModule, tree, n)

proc setupBackendModule(g: ModuleGraph; m: var LoadedModule) =
  if g.backend == nil:
    g.backend = cgendata.newModuleList(g)
  assert g.backend != nil
  var bmod = cgen.newModule(BModuleList(g.backend), m.module, g.config)
  bmod.idgen = idgenFromLoadedModule(m)

proc generateCodeForModule(g: ModuleGraph; m: var LoadedModule; alive: var AliveSyms) =
  var bmod = BModuleList(g.backend).modules[m.module.position]
  assert bmod != nil
  bmod.flags.incl useAliveDataFromDce
  bmod.alive = move alive[m.module.position]

  for p in allNodes(m.fromDisk.topLevel):
    let n = unpackTree(g, m.module.position, m.fromDisk.topLevel, p)
    cgen.genTopLevelStmt(bmod, n)

  finalCodegenActions(g, bmod, newNodeI(nkStmtList, m.module.info))
  for disp in getDispatchers(g):
    genProcAux(bmod, disp)
  m.fromDisk.backendFlags = cgen.whichInitProcs(bmod)

proc replayTypeInfo(g: ModuleGraph; m: var LoadedModule; origin: FileIndex) =
  for x in mitems(m.fromDisk.emittedTypeInfo):
    #echo "found type ", x, " for file ", int(origin)
    g.emittedTypeInfo[x] = origin

proc addFileToLink(config: ConfigRef; m: PSym) =
  let filename = AbsoluteFile toFullPath(config, m.position.FileIndex)
  let ext =
      if config.backend == backendCpp: ".nim.cpp"
      elif config.backend == backendObjc: ".nim.m"
      else: ".nim.c"
  let cfile = changeFileExt(completeCfilePath(config,
                            mangleModuleName(config, filename).AbsoluteFile), ext)
  let objFile = completeCfilePath(config, toObjFile(config, cfile))
  if fileExists(objFile):
    var cf = Cfile(nimname: m.name.s, cname: cfile,
                   obj: objFile,
                   flags: {CfileFlag.Cached})
    addFileToCompile(config, cf)

when defined(debugDce):
  import os, std/packedsets

proc storeAliveSymsImpl(asymFile: AbsoluteFile; s: seq[int32]) =
  var f = rodfiles.create(asymFile.string)
  f.storeHeader()
  f.storeSection aliveSymsSection
  f.storeSeq(s)
  close f

template prepare {.dirty.} =
  let asymFile = toRodFile(config, AbsoluteFile toFullPath(config, position.FileIndex), ".alivesyms")
  var s = newSeqOfCap[int32](alive[position].len)
  for a in items(alive[position]): s.add int32(a)
  sort(s)

proc storeAliveSyms(config: ConfigRef; position: int; alive: AliveSyms) =
  prepare()
  storeAliveSymsImpl(asymFile, s)

proc aliveSymsChanged(config: ConfigRef; position: int; alive: AliveSyms): bool =
  prepare()
  var f2 = rodfiles.open(asymFile.string)
  f2.loadHeader()
  f2.loadSection aliveSymsSection
  var oldData: seq[int32] = @[]
  f2.loadSeq(oldData)
  f2.close
  if f2.err == ok and oldData == s:
    result = false
  else:
    when defined(debugDce):
      let oldAsSet = toPackedSet[int32](oldData)
      let newAsSet = toPackedSet[int32](s)
      echo "set of live symbols changed ", asymFile.changeFileExt("rod"), " ", position, " ", f2.err
      echo "in old but not in new ", oldAsSet.difference(newAsSet), " number of entries in old ", oldAsSet.len
      echo "in new but not in old ", newAsSet.difference(oldAsSet), " number of entries in new ", newAsSet.len
      #if execShellCmd(getAppFilename() & " rod " & quoteShell(asymFile.changeFileExt("rod"))) != 0:
      #  echo "command failed"
    result = true
    storeAliveSymsImpl(asymFile, s)

proc genPackedModule(g: ModuleGraph, i: int; alive: var AliveSyms) =
  # case statement here to enforce exhaustive checks.
  case g.packed[i].status
  of undefined:
    discard "nothing to do"
  of loading, stored:
    assert false
  of storing, outdated:
    storeAliveSyms(g.config, g.packed[i].module.position, alive)
    generateCodeForModule(g, g.packed[i], alive)
    closeRodFile(g, g.packed[i].module)
  of loaded:
    if g.packed[i].loadedButAliveSetChanged:
      generateCodeForModule(g, g.packed[i], alive)
    else:
      addFileToLink(g.config, g.packed[i].module)
      replayTypeInfo(g, g.packed[i], FileIndex(i))

      if g.backend == nil:
        g.backend = cgendata.newModuleList(g)
      registerInitProcs(BModuleList(g.backend), g.packed[i].module, g.packed[i].fromDisk.backendFlags)

proc generateCode*(g: ModuleGraph) =
  ## The single entry point, generate C(++) code for the entire
  ## Nim program aka `ModuleGraph`.
  resetForBackend(g)
  var alive = computeAliveSyms(g.packed, g.config)

  when false:
    for i in 0..<len(g.packed):
      echo i, " is of status ", g.packed[i].status, " ", toFullPath(g.config, FileIndex(i))

  # First pass: Setup all the backend modules for all the modules that have
  # changed:
  for i in 0..<len(g.packed):
    # case statement here to enforce exhaustive checks.
    case g.packed[i].status
    of undefined:
      discard "nothing to do"
    of loading, stored:
      assert false
    of storing, outdated:
      setupBackendModule(g, g.packed[i])
    of loaded:
      # Even though this module didn't change, DCE might trigger a change.
      # Consider this case: Module A uses symbol S from B and B does not use
      # S itself. A is then edited not to use S either. Thus we have to
      # recompile B in order to remove S from the final result.
      if aliveSymsChanged(g.config, g.packed[i].module.position, alive):
        g.packed[i].loadedButAliveSetChanged = true
        setupBackendModule(g, g.packed[i])

  # Second pass: Code generation.
  let mainModuleIdx = g.config.projectMainIdx2.int
  # We need to generate the main module last, because only then
  # all init procs have been registered:
  for i in 0..<len(g.packed):
    if i != mainModuleIdx:
      genPackedModule(g, i, alive)
  if mainModuleIdx >= 0:
    genPackedModule(g, mainModuleIdx, alive)

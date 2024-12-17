#
#
#           The Nim Compiler
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements the passes functionality. A pass must implement the
## `TPass` interface.

import
  options, ast, llstream, msgs,
  idents,
  syntaxes, modulegraphs, reorder,
  lineinfos,
  pipelineutils,
  modules, pathutils, packages,
  sem, semdata

import ic/replayer

export skipCodegen, resolveMod, prepareConfigNotes

when defined(nimsuggest):
  import ../dist/checksums/src/checksums/sha1

when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions]

import std/tables

type
  TPassData* = tuple[input: PNode, closeOutput: PNode]

# a pass is a tuple of procedure vars ``TPass.close`` may produce additional
# nodes. These are passed to the other close procedures.
# This mechanism used to be used for the instantiation of generics.

proc makePass*(open: TPassOpen = nil,
               process: TPassProcess = nil,
               close: TPassClose = nil,
               isFrontend = false): TPass =
  result = (open, process, close, isFrontend)

const
  maxPasses = 10

type
  TPassContextArray = array[0..maxPasses - 1, PPassContext]

proc clearPasses*(g: ModuleGraph) =
  g.passes.setLen(0)

proc registerPass*(g: ModuleGraph; p: TPass) =
  internalAssert g.config, g.passes.len < maxPasses
  g.passes.add(p)

proc openPasses(g: ModuleGraph; a: var TPassContextArray;
                module: PSym; idgen: IdGenerator) =
  for i in 0..<g.passes.len:
    if not isNil(g.passes[i].open):
      a[i] = g.passes[i].open(g, module, idgen)
    else: a[i] = nil

proc closePasses(graph: ModuleGraph; a: var TPassContextArray) =
  var m: PNode = nil
  for i in 0..<graph.passes.len:
    if not isNil(graph.passes[i].close):
      m = graph.passes[i].close(graph, a[i], m)
    a[i] = nil                # free the memory here

proc processTopLevelStmt(graph: ModuleGraph, n: PNode, a: var TPassContextArray): bool =
  # this implements the code transformation pipeline
  var m = n
  for i in 0..<graph.passes.len:
    if not isNil(graph.passes[i].process):
      m = graph.passes[i].process(a[i], m)
      if isNil(m): return false
  result = true

proc processImplicits(graph: ModuleGraph; implicits: seq[string], nodeKind: TNodeKind,
                      a: var TPassContextArray; m: PSym) =
  # XXX fixme this should actually be relative to the config file!
  let relativeTo = toFullPath(graph.config, m.info)
  for module in items(implicits):
    # implicit imports should not lead to a module importing itself
    if m.position != resolveMod(graph.config, module, relativeTo).int32:
      var importStmt = newNodeI(nodeKind, m.info)
      var str = newStrNode(nkStrLit, module)
      str.info = m.info
      importStmt.add str
      if not processTopLevelStmt(graph, importStmt, a): break

proc processModule*(graph: ModuleGraph; module: PSym; idgen: IdGenerator;
                    stream: PLLStream): bool {.discardable.} =
  if graph.stopCompile(): return true
  var
    p: Parser = default(Parser)
    a: TPassContextArray = default(TPassContextArray)
    s: PLLStream
    fileIdx = module.fileIdx
  prepareConfigNotes(graph, module)
  openPasses(graph, a, module, idgen)
  if stream == nil:
    let filename = toFullPathConsiderDirty(graph.config, fileIdx)
    s = llStreamOpen(filename, fmRead)
    if s == nil:
      rawMessage(graph.config, errCannotOpenFile, filename.string)
      return false
  else:
    s = stream

  when defined(nimsuggest):
    let filename = toFullPathConsiderDirty(graph.config, fileIdx).string
    msgs.setHash(graph.config, fileIdx, $sha1.secureHashFile(filename))

  while true:
    openParser(p, fileIdx, s, graph.cache, graph.config)

    if (not belongsToStdlib(graph, module)) or module.name.s == "distros":
      # XXX what about caching? no processing then? what if I change the
      # modules to include between compilation runs? we'd need to track that
      # in ROD files. I think we should enable this feature only
      # for the interactive mode.
      if module.name.s != "nimscriptapi":
        processImplicits graph, graph.config.implicitImports, nkImportStmt, a, module
        processImplicits graph, graph.config.implicitIncludes, nkIncludeStmt, a, module

    checkFirstLineIndentation(p)
    block processCode:
      if graph.stopCompile(): break processCode
      var n = parseTopLevelStmt(p)
      if n.kind == nkEmpty: break processCode

      # read everything, no streaming possible
      var sl = newNodeI(nkStmtList, n.info)
      sl.add n
      while true:
        var n = parseTopLevelStmt(p)
        if n.kind == nkEmpty: break
        sl.add n
      if sfReorder in module.flags or codeReordering in graph.config.features:
        sl = reorder(graph, sl, module)
      discard processTopLevelStmt(graph, sl, a)

    closeParser(p)
    if s.kind != llsStdIn: break
  closePasses(graph, a)
  if graph.config.backend notin {backendC, backendCpp, backendObjc}:
    # We only write rod files here if no C-like backend is active.
    # The C-like backends have been patched to support the IC mechanism.
    # They are responsible for closing the rod files. See `cbackend.nim`.
    closeRodFile(graph, module)
  result = true

proc compileModule*(graph: ModuleGraph; fileIdx: FileIndex; flags: TSymFlags, fromModule: PSym = nil): PSym =
  var flags = flags
  if fileIdx == graph.config.projectMainIdx2: flags.incl sfMainModule
  result = graph.getModule(fileIdx)

  template processModuleAux(moduleStatus) =
    onProcessing(graph, fileIdx, moduleStatus, fromModule = fromModule)
    var s: PLLStream = nil
    if sfMainModule in flags:
      if graph.config.projectIsStdin: s = stdin.llStreamOpen
      elif graph.config.projectIsCmd: s = llStreamOpen(graph.config.cmdInput)
    discard processModule(graph, result, idGeneratorFromModule(result), s)
  if result == nil:
    var cachedModules: seq[FileIndex] = @[]
    result = moduleFromRodFile(graph, fileIdx, cachedModules)
    let filename = AbsoluteFile toFullPath(graph.config, fileIdx)
    if result == nil:
      result = newModule(graph, fileIdx)
      result.flags.incl flags
      registerModule(graph, result)
      processModuleAux("import")
    else:
      if sfSystemModule in flags:
        graph.systemModule = result
      partialInitModule(result, graph, fileIdx, filename)
    for m in cachedModules:
      registerModuleById(graph, m)
      replayStateChanges(graph.packed.pm[m.int].module, graph)
      replayGenericCacheInformation(graph, m.int)
  elif graph.isDirty(result):
    result.flags.excl sfDirty
    # reset module fields:
    initStrTables(graph, result)
    result.ast = nil
    processModuleAux("import(dirty)")
    graph.markClientsDirty(fileIdx)

proc importModule*(graph: ModuleGraph; s: PSym, fileIdx: FileIndex): PSym =
  # this is called by the semantic checking phase
  assert graph.config != nil
  result = compileModule(graph, fileIdx, {}, s)
  graph.addDep(s, fileIdx)
  # keep track of import relationships
  if graph.config.hcrOn:
    graph.importDeps.mgetOrPut(FileIndex(s.position), @[]).add(fileIdx)
  #if sfSystemModule in result.flags:
  #  localError(result.info, errAttemptToRedefine, result.name.s)
  # restore the notes for outer module:
  graph.config.notes =
    if graph.config.belongsToProjectPackage(s) or isDefined(graph.config, "booting"): graph.config.mainPackageNotes
    else: graph.config.foreignPackageNotes

proc connectCallbacks*(graph: ModuleGraph) =
  graph.includeFileCallback = modules.includeModule
  graph.importModuleCallback = importModule

proc compileSystemModule*(graph: ModuleGraph) =
  if graph.systemModule == nil:
    connectCallbacks(graph)
    graph.config.m.systemFileIdx = fileInfoIdx(graph.config,
        graph.config.libpath / RelativeFile"system.nim")
    discard graph.compileModule(graph.config.m.systemFileIdx, {sfSystemModule})

proc compileProject*(graph: ModuleGraph; projectFileIdx = InvalidFileIdx) =
  connectCallbacks(graph)
  let conf = graph.config
  wantMainModule(conf)
  configComplete(graph)

  let systemFileIdx = fileInfoIdx(conf, conf.libpath / RelativeFile"system.nim")
  let projectFile = if projectFileIdx == InvalidFileIdx: conf.projectMainIdx else: projectFileIdx
  conf.projectMainIdx2 = projectFile

  let packSym = getPackage(graph, projectFile)
  graph.config.mainPackageId = packSym.getPackageId
  graph.importStack.add projectFile

  if projectFile == systemFileIdx:
    discard graph.compileModule(projectFile, {sfMainModule, sfSystemModule})
  else:
    graph.compileSystemModule()
    discard graph.compileModule(projectFile, {sfMainModule})

proc mySemOpen(graph: ModuleGraph; module: PSym; idgen: IdGenerator): PPassContext =
  result = preparePContext(graph, module, idgen)

proc mySemClose(graph: ModuleGraph; context: PPassContext, n: PNode): PNode =
  var c = PContext(context)
  closePContext(graph, c, n)

proc mySemProcess(context: PPassContext, n: PNode): PNode =
  result = semWithPContext(PContext(context), n)

const semPass* = makePass(mySemOpen, mySemProcess, mySemClose,
                          isFrontend = true)

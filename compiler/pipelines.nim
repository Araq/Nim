import sem, cgen, modulegraphs, ast, llstream, parser, msgs,
       lineinfos, reorder, options, semdata, cgendata, modules, pathutils,
       packages, syntaxes, depends, vm, pragmas, idents, lookups, wordrecg,
       liftdestructors

import pipelineutils

import ../dist/checksums/src/checksums/sha1

when not defined(leanCompiler):
  import jsgen, docgen2

import std/[syncio, objectdollar, assertions, tables, strutils, strtabs]
import renderer
import ic/replayer

proc setPipeLinePass*(graph: ModuleGraph; pass: PipelinePass) =
  graph.pipelinePass = pass

proc processPipeline(graph: ModuleGraph; semNode: PNode; bModule: PPassContext): PNode =
  case graph.pipelinePass
  of CgenPass:
    result = semNode
    if bModule != nil:
      genTopLevelStmt(BModule(bModule), result)
  of JSgenPass:
    when not defined(leanCompiler):
      result = processJSCodeGen(bModule, semNode)
    else:
      result = nil
  of GenDependPass:
    result = addDotDependency(bModule, semNode)
  of SemPass:
    result = graph.emptyNode
  of Docgen2Pass, Docgen2TexPass:
    when not defined(leanCompiler):
      result = processNode(bModule, semNode)
    else:
      result = nil
  of Docgen2JsonPass:
    when not defined(leanCompiler):
      result = processNodeJson(bModule, semNode)
    else:
      result = nil
  of EvalPass, InterpreterPass:
    result = interpreterCode(bModule, semNode)
  of NonePass:
    raiseAssert "use setPipeLinePass to set a proper PipelinePass"

proc processImplicitImports*(graph: ModuleGraph; implicits: seq[string], nodeKind: TNodeKind,
                             m: PSym, ctx: PContext, bModule: PPassContext, idgen: IdGenerator) =
  # XXX fixme this should actually be relative to the config file!
  let relativeTo = toFullPath(graph.config, m.info)
  for module in items(implicits):
    # implicit imports should not lead to a module importing itself
    if m.position != resolveMod(graph.config, module, relativeTo).int32:
      var importStmt = newNodeI(nodeKind, m.info)
      var str = newStrNode(nkStrLit, module)
      str.info = m.info
      importStmt.add str
      message(graph.config, importStmt.info, hintProcessingStmt, $idgen[])
      let semNode = semWithPContext(ctx, importStmt)
      if semNode == nil or processPipeline(graph, semNode, bModule) == nil:
        break

proc prePass*(c: PContext; n: PNode) =
  for son in n:
    if son.kind == nkPragma:
      for s in son:
        var key = if s.kind in nkPragmaCallKinds and s.len > 1: s[0] else: s
        if key.kind in {nkBracketExpr, nkCast} or key.kind notin nkIdentKinds:
          continue
        let ident = whichKeyword(considerQuotedIdent(c, key))
        case ident
        of wReorder:
          pragmaNoForward(c, s, flag = sfReorder)
        of wExperimental:
          if isTopLevel(c) and s.kind in nkPragmaCallKinds and s.len == 2:
            let name = c.semConstExpr(c, s[1])
            case name.kind
            of nkStrLit, nkRStrLit, nkTripleStrLit:
              try:
                let feature = parseEnum[Feature](name.strVal)
                if feature == codeReordering:
                  c.features.incl feature
                  c.module.flags.incl sfReorder
              except ValueError:
                discard
            else:
              discard
        else:
          discard

proc processPipelineModule*(graph: ModuleGraph; module: PSym; idgen: IdGenerator;
                    stream: PLLStream): bool =
  if graph.stopCompile(): return true
  var
    p: Parser = default(Parser)
    s: PLLStream
    fileIdx = module.fileIdx

  prepareConfigNotes(graph, module)
  let ctx = preparePContext(graph, module, idgen)
  let bModule: PPassContext =
    case graph.pipelinePass
    of CgenPass:
      setupCgen(graph, module, idgen)
    of JSgenPass:
      when not defined(leanCompiler):
        setupJSgen(graph, module, idgen)
      else:
        nil
    of EvalPass, InterpreterPass:
      setupEvalGen(graph, module, idgen)
    of GenDependPass:
      setupDependPass(graph, module, idgen)
    of Docgen2Pass:
      when not defined(leanCompiler):
        openHtml(graph, module, idgen)
      else:
        nil
    of Docgen2TexPass:
      when not defined(leanCompiler):
        openTex(graph, module, idgen)
      else:
        nil
    of Docgen2JsonPass:
      when not defined(leanCompiler):
        openJson(graph, module, idgen)
      else:
        nil
    of SemPass:
      nil
    of NonePass:
      raiseAssert "use setPipeLinePass to set a proper PipelinePass"

  if stream == nil:
    let filename = toFullPathConsiderDirty(graph.config, fileIdx)
    s = llStreamOpen(filename, fmRead)
    if s == nil:
      rawMessage(graph.config, errCannotOpenFile, filename.string)
      return false
    graph.interactive = false
  else:
    s = stream
    graph.interactive = stream.kind == llsStdIn
  while true:
    syntaxes.openParser(p, fileIdx, s, graph.cache, graph.config)

    if not belongsToStdlib(graph, module) or (belongsToStdlib(graph, module) and module.name.s == "distros"):
      # XXX what about caching? no processing then? what if I change the
      # modules to include between compilation runs? we'd need to track that
      # in ROD files. I think we should enable this feature only
      # for the interactive mode.
      if module.name.s != "nimscriptapi":
        processImplicitImports graph, graph.config.implicitImports, nkImportStmt, module, ctx, bModule, idgen
        processImplicitImports graph, graph.config.implicitIncludes, nkIncludeStmt, module, ctx, bModule, idgen

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

      prePass(ctx, sl)
      if sfReorder in module.flags or codeReordering in graph.config.features:
        sl = reorder(graph, sl, module)
      if graph.pipelinePass != EvalPass:
        message(graph.config, sl.info, hintProcessingStmt, $idgen[])
      var semNode = semWithPContext(ctx, sl)
      discard processPipeline(graph, semNode, bModule)

    closeParser(p)
    if s.kind != llsStdIn: break
  let finalNode = closePContext(graph, ctx, nil)
  case graph.pipelinePass
  of CgenPass:
    if bModule != nil:
      let m = BModule(bModule)
      finalCodegenActions(graph, m, finalNode)
      if graph.dispatchers.len > 0:
        let ctx = preparePContext(graph, module, idgen)
        for disp in getDispatchers(graph):
          let retTyp = disp.typ.returnType
          if retTyp != nil:
            # TODO: properly semcheck the code of dispatcher?
            createTypeBoundOps(graph, ctx, retTyp, disp.ast.info, idgen)
          genProcAux(m, disp)
        discard closePContext(graph, ctx, nil)
  of JSgenPass:
    when not defined(leanCompiler):
      discard finalJSCodeGen(graph, bModule, finalNode)
  of EvalPass, InterpreterPass:
    discard interpreterCode(bModule, finalNode)
  of SemPass, GenDependPass:
    discard
  of Docgen2Pass, Docgen2TexPass:
    when not defined(leanCompiler):
      discard closeDoc(graph, bModule, finalNode)
  of Docgen2JsonPass:
    when not defined(leanCompiler):
      discard closeJson(graph, bModule, finalNode)
  of NonePass:
    raiseAssert "use setPipeLinePass to set a proper PipelinePass"

  if graph.config.backend notin {backendC, backendCpp, backendObjc}:
    # We only write rod files here if no C-like backend is active.
    # The C-like backends have been patched to support the IC mechanism.
    # They are responsible for closing the rod files. See `cbackend.nim`.
    closeRodFile(graph, module)
  result = true

proc compilePipelineModule*(graph: ModuleGraph; fileIdx: FileIndex; flags: TSymFlags; fromModule: PSym = nil): PSym =
  var flags = flags
  if fileIdx == graph.config.projectMainIdx2: flags.incl sfMainModule
  result = graph.getModule(fileIdx)

  template processModuleAux(moduleStatus) =
    onProcessing(graph, fileIdx, moduleStatus, fromModule = fromModule)
    var s: PLLStream = nil
    if sfMainModule in flags:
      if graph.config.projectIsStdin: s = stdin.llStreamOpen
      elif graph.config.projectIsCmd: s = llStreamOpen(graph.config.cmdInput)
    discard processPipelineModule(graph, result, idGeneratorFromModule(result), s)
  if result == nil:
    var cachedModules: seq[FileIndex] = @[]
    result = moduleFromRodFile(graph, fileIdx, cachedModules)
    let path = toFullPath(graph.config, fileIdx)
    let filename = AbsoluteFile path
    if fileExists(filename): # it could be a stdinfile
      graph.cachedFiles[path] = $secureHashFile(path)
    if result == nil:
      result = newModule(graph, fileIdx)
      result.flags.incl flags
      registerModule(graph, result)
      processModuleAux("import")
    else:
      if sfSystemModule in flags:
        graph.systemModule = result
      if sfMainModule in flags and graph.config.cmd == cmdM:
        result.flags.incl flags
        registerModule(graph, result)
        processModuleAux("import")
      partialInitModule(result, graph, fileIdx, filename)
    for m in cachedModules:
      registerModuleById(graph, m)
      if sfMainModule in flags and graph.config.cmd == cmdM:
        discard
      else:
        replayStateChanges(graph.packed.pm[m.int].module, graph)
        replayGenericCacheInformation(graph, m.int)
  elif graph.isDirty(result):
    result.flags.excl sfDirty
    # reset module fields:
    initStrTables(graph, result)
    result.ast = nil
    processModuleAux("import(dirty)")
    graph.markClientsDirty(fileIdx)

proc importPipelineModule(graph: ModuleGraph; s: PSym, fileIdx: FileIndex): PSym =
  # this is called by the semantic checking phase
  assert graph.config != nil
  result = compilePipelineModule(graph, fileIdx, {}, s)
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

proc connectPipelineCallbacks*(graph: ModuleGraph) =
  graph.includeFileCallback = modules.includeModule
  graph.importModuleCallback = importPipelineModule

proc compilePipelineSystemModule*(graph: ModuleGraph) =
  if graph.systemModule == nil:
    connectPipelineCallbacks(graph)
    graph.config.m.systemFileIdx = fileInfoIdx(graph.config,
        graph.config.libpath / RelativeFile"system.nim")
    discard graph.compilePipelineModule(graph.config.m.systemFileIdx, {sfSystemModule})

proc compilePipelineProject*(graph: ModuleGraph; projectFileIdx = InvalidFileIdx) =
  connectPipelineCallbacks(graph)
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
    discard graph.compilePipelineModule(projectFile, {sfMainModule, sfSystemModule})
  else:
    graph.compilePipelineSystemModule()
    discard graph.compilePipelineModule(projectFile, {sfMainModule})

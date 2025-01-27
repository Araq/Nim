#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# implements the command dispatcher and several commands

when not defined(nimcore):
  {.error: "nimcore MUST be defined for Nim's core tooling".}

import
  std/[strutils, os, times, tables, with, json],
  llstream, ast, lexer, syntaxes, options, msgs,
  condsyms,
  idents, extccomp,
  cgen, nversion,
  platform, nimconf, depends,
  modules,
  modulegraphs, lineinfos, pathutils, vmprofiler


when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions]

import ic / [cbackend, integrity, navigator, ic]

import ../dist/checksums/src/checksums/sha1

import pipelines

when not defined(leanCompiler):
  import docgen

proc writeDepsFile(g: ModuleGraph) =
  let fname = g.config.nimcacheDir / RelativeFile(g.config.projectName & ".deps")
  let f = open(fname.string, fmWrite)
  for m in g.ifaces:
    if m.module != nil:
      f.writeLine(toFullPath(g.config, m.module.position.FileIndex))
  for k in g.inclToMod.keys:
    if g.getModule(k).isNil:  # don't repeat includes which are also modules
      f.writeLine(toFullPath(g.config, k))
  f.close()

proc writeCMakeDepsFile(conf: ConfigRef) =
  ## write a list of C files for build systems like CMake.
  ## only updated when the C file list changes.
  let fname = getNimcacheDir(conf) / conf.outFile.changeFileExt("cdeps")
  # generate output files list
  var cfiles: seq[string] = @[]
  for it in conf.toCompile: cfiles.add(it.cname.string)
  let fileset = cfiles.toCountTable()
  # read old cfiles list
  var fl: File = default(File)
  var prevset = initCountTable[string]()
  if open(fl, fname.string, fmRead):
    for line in fl.lines: prevset.inc(line)
    fl.close()
  # write cfiles out
  if fileset != prevset:
    fl = open(fname.string, fmWrite)
    for line in cfiles: fl.writeLine(line)
    fl.close()

proc commandGenDepend(graph: ModuleGraph) =
  setPipeLinePass(graph, GenDependPass)
  compilePipelineProject(graph)
  let project = graph.config.projectFull
  writeDepsFile(graph)
  generateDot(graph, project)

  # dot in graphivz tool kit is required
  let graphvizDotPath = findExe("dot")
  if graphvizDotPath.len == 0:
    quit("gendepend: Graphviz's tool dot is required," &
    "see https://graphviz.org/download for downloading")

  execExternalProgram(graph.config, "dot -Tpng -o" &
      changeFileExt(project, "png").string &
      ' ' & changeFileExt(project, "dot").string)

proc commandCheck(graph: ModuleGraph) =
  let conf = graph.config
  conf.setErrorMaxHighMaybe
  defineSymbol(conf.symbols, "nimcheck")
  if optWasNimscript in conf.globalOptions:
    defineSymbol(conf.symbols, "nimscript")
    defineSymbol(conf.symbols, "nimconfig")
  elif conf.backend == backendJs:
    setTarget(conf.target, osJS, cpuJS)
  setPipeLinePass(graph, SemPass)
  compilePipelineProject(graph)

  if conf.symbolFiles != disabledSf:
    case conf.ideCmd
    of ideDef: navDefinition(graph)
    of ideUse: navUsages(graph)
    of ideDus: navDefusages(graph)
    else: discard
    writeRodFiles(graph)

when not defined(leanCompiler):
  proc commandDoc2(graph: ModuleGraph; ext: string) =
    handleDocOutputOptions graph.config
    graph.config.setErrorMaxHighMaybe
    case ext:
    of TexExt:
      setPipeLinePass(graph, Docgen2TexPass)
    of JsonExt:
      setPipeLinePass(graph, Docgen2JsonPass)
    of HtmlExt:
      setPipeLinePass(graph, Docgen2Pass)
    else: raiseAssert $ext
    compilePipelineProject(graph)

proc commandCompileToC(graph: ModuleGraph) =
  let conf = graph.config
  extccomp.initVars(conf)
  if conf.symbolFiles == disabledSf:
    if {optRun, optForceFullMake} * conf.globalOptions == {optRun} or isDefined(conf, "nimBetterRun"):
      if not changeDetectedViaJsonBuildInstructions(conf, conf.jsonBuildInstructionsFile):
        # nothing changed
        graph.config.notes = graph.config.mainPackageNotes
        return

  if not extccomp.ccHasSaneOverflow(conf):
    conf.symbols.defineSymbol("nimEmulateOverflowChecks")

  if conf.symbolFiles == disabledSf:
    setPipeLinePass(graph, CgenPass)
  else:
    setPipeLinePass(graph, SemPass)
  compilePipelineProject(graph)
  if graph.config.errorCounter > 0:
    return # issue #9933
  if conf.symbolFiles == disabledSf:
    cgenWriteModules(graph.backend, conf)
  else:
    if isDefined(conf, "nimIcIntegrityChecks"):
      checkIntegrity(graph)
    generateCode(graph)
    # graph.backend can be nil under IC when nothing changed at all:
    if graph.backend != nil:
      cgenWriteModules(graph.backend, conf)
  if conf.cmd != cmdTcc and graph.backend != nil:
    extccomp.callCCompiler(conf)
    # for now we do not support writing out a .json file with the build instructions when HCR is on
    if not conf.hcrOn:
      extccomp.writeJsonBuildInstructions(conf, graph.cachedFiles)
    if optGenScript in graph.config.globalOptions:
      writeDepsFile(graph)
    if optGenCDeps in graph.config.globalOptions:
      writeCMakeDepsFile(conf)

proc commandJsonScript(graph: ModuleGraph) =
  extccomp.runJsonBuildInstructions(graph.config, graph.config.jsonBuildInstructionsFile)

proc commandCompileToJS(graph: ModuleGraph) =
  let conf = graph.config
  when defined(leanCompiler):
    globalError(conf, unknownLineInfo, "compiler wasn't built with JS code generator")
  else:
    conf.exc = excCpp
    setTarget(conf.target, osJS, cpuJS)
    defineSymbol(conf.symbols, "ecmascript") # For backward compatibility
    setPipeLinePass(graph, JSgenPass)
    compilePipelineProject(graph)
    if optGenScript in conf.globalOptions:
      writeDepsFile(graph)

proc commandInteractive(graph: ModuleGraph) =
  graph.config.setErrorMaxHighMaybe
  initDefines(graph.config.symbols)
  defineSymbol(graph.config.symbols, "nimscript")
  # note: seems redundant with -d:nimHasLibFFI
  when hasFFI: defineSymbol(graph.config.symbols, "nimffi")
  setPipeLinePass(graph, InterpreterPass)
  compilePipelineSystemModule(graph)
  if graph.config.commandArgs.len > 0:
    discard graph.compilePipelineModule(fileInfoIdx(graph.config, graph.config.projectFull), {})
  else:
    var m = graph.makeStdinModule()
    incl(m.flags, sfMainModule)
    var idgen = IdGenerator(module: m.itemId.module, symId: m.itemId.item, typeId: 0)
    let s = llStreamOpenStdIn(onPrompt = proc() = flushDot(graph.config))
    discard processPipelineModule(graph, m, idgen, s)

proc commandScan(cache: IdentCache, config: ConfigRef) =
  var f = addFileExt(AbsoluteFile mainCommandArg(config), NimExt)
  var stream = llStreamOpen(f, fmRead)
  if stream != nil:
    var
      L: Lexer = default(Lexer)
      tok: Token = default(Token)
    openLexer(L, f, stream, cache, config)
    while true:
      rawGetTok(L, tok)
      printTok(config, tok)
      if tok.tokType == tkEof: break
    closeLexer(L)
  else:
    rawMessage(config, errGenerated, "cannot open file: " & f.string)

proc commandView(graph: ModuleGraph) =
  let f = toAbsolute(mainCommandArg(graph.config), AbsoluteDir getCurrentDir()).addFileExt(RodExt)
  rodViewer(f, graph.config, graph.cache)

const
  PrintRopeCacheStats = false

proc hashMainCompilationParams*(conf: ConfigRef): string =
  ## doesn't have to be complete; worst case is a cache hit and recompilation.
  var state = newSha1State()
  with state:
    update os.getAppFilename() # nim compiler
    update conf.commandLine # excludes `arguments`, as it should
    update $conf.projectFull # so that running `nim r main` from 2 directories caches differently
  result = $SecureHash(state.finalize())

proc setOutFile*(conf: ConfigRef) =
  proc libNameTmpl(conf: ConfigRef): string {.inline.} =
    result = if conf.target.targetOS == osWindows: "$1.lib" else: "lib$1.a"

  if conf.outFile.isEmpty:
    var base = conf.projectName
    if optUseNimcache in conf.globalOptions:
      base.add "_" & hashMainCompilationParams(conf)
    let targetName =
      if conf.backend == backendJs: base & ".js"
      elif optGenDynLib in conf.globalOptions:
        platform.OS[conf.target.targetOS].dllFrmt % base
      elif optGenStaticLib in conf.globalOptions: libNameTmpl(conf) % base
      else: base & platform.OS[conf.target.targetOS].exeExt
    conf.outFile = RelativeFile targetName

proc mainCommand*(graph: ModuleGraph) =
  let conf = graph.config
  let cache = graph.cache

  conf.lastCmdTime = epochTime()
  conf.searchPaths.add(conf.libpath)

  proc customizeForBackend(backend: TBackend) =
    ## Sets backend specific options but don't compile to backend yet in
    ## case command doesn't require it. This must be called by all commands.
    if conf.backend == backendInvalid:
      # only set if wasn't already set, to allow override via `nim c -b:cpp`
      conf.backend = backend

    defineSymbol(graph.config.symbols, $conf.backend)
    case conf.backend
    of backendC:
      if conf.exc == excNone: conf.exc = excSetjmp
    of backendCpp:
      if conf.exc == excNone: conf.exc = excCpp
    of backendObjc: discard
    of backendJs:
      if conf.hcrOn:
        # XXX: At the moment, system.nim cannot be compiled in JS mode
        # with "-d:useNimRtl". The HCR option has been processed earlier
        # and it has added this define implictly, so we must undo that here.
        # A better solution might be to fix system.nim
        undefSymbol(conf.symbols, "useNimRtl")
    of backendInvalid: raiseAssert "unreachable"

  proc compileToBackend() =
    customizeForBackend(conf.backend)
    setOutFile(conf)
    case conf.backend
    of backendC: commandCompileToC(graph)
    of backendCpp: commandCompileToC(graph)
    of backendObjc: commandCompileToC(graph)
    of backendJs: commandCompileToJS(graph)
    of backendInvalid: raiseAssert "unreachable"

  template docLikeCmd(body) =
    when defined(leanCompiler):
      conf.quitOrRaise "compiler wasn't built with documentation generator"
    else:
      wantMainModule(conf)
      let docConf = if conf.cmd == cmdDoc2tex: DocTexConfig else: DocConfig
      loadConfigs(docConf, cache, conf, graph.idgen)
      defineSymbol(conf.symbols, "nimdoc")
      body

  ## command prepass
  if conf.cmd == cmdCrun: conf.globalOptions.incl {optRun, optUseNimcache}
  if conf.cmd notin cmdBackends + {cmdTcc}: customizeForBackend(backendC)
  if conf.outDir.isEmpty:
    # doc like commands can generate a lot of files (especially with --project)
    # so by default should not end up in $PWD nor in $projectPath.
    var ret = if optUseNimcache in conf.globalOptions: getNimcacheDir(conf)
              else: conf.projectPath
    if not ret.string.isAbsolute: # `AbsoluteDir` is not a real guarantee
      rawMessage(conf, errCannotOpenFile, ret.string & "/")
    if conf.cmd in cmdDocLike + {cmdRst2html, cmdRst2tex, cmdMd2html, cmdMd2tex}:
      ret = ret / htmldocsDir
    conf.outDir = ret

  ## process all commands
  case conf.cmd
  of cmdBackends:
    compileToBackend()
    when BenchIC:
      echoTimes graph.packed
  of cmdTcc:
    when hasTinyCBackend:
      extccomp.setCC(conf, "tcc", unknownLineInfo)
      if conf.backend != backendC:
        rawMessage(conf, errGenerated, "'run' requires c backend, got: '$1'" % $conf.backend)
      compileToBackend()
    else:
      rawMessage(conf, errGenerated, "'run' command not available; rebuild with -d:tinyc")
  of cmdDoc0: docLikeCmd commandDoc(cache, conf)
  of cmdDoc:
    docLikeCmd():
      conf.setNoteDefaults(warnRstRedefinitionOfLabel, false) # issue #13218
        # because currently generates lots of false positives due to conflation
        # of labels links in doc comments, e.g. for random.rand:
        #  ## * `rand proc<#rand,Rand,Natural>`_ that returns an integer
        #  ## * `rand proc<#rand,Rand,range[]>`_ that returns a float
      commandDoc2(graph, HtmlExt)
      if optGenIndex in conf.globalOptions and optWholeProject in conf.globalOptions:
        commandBuildIndex(conf, $conf.outDir)
  of cmdRst2html, cmdMd2html:
    # XXX: why are warnings disabled by default for rst2html and rst2tex?
    for warn in rstWarnings:
      conf.setNoteDefaults(warn, true)
    conf.setNoteDefaults(warnRstRedefinitionOfLabel, false) # similar to issue #13218
    when defined(leanCompiler):
      conf.quitOrRaise "compiler wasn't built with documentation generator"
    else:
      loadConfigs(DocConfig, cache, conf, graph.idgen)
      commandRst2Html(cache, conf, preferMarkdown = (conf.cmd == cmdMd2html))
  of cmdRst2tex, cmdMd2tex, cmdDoc2tex:
    for warn in rstWarnings:
      conf.setNoteDefaults(warn, true)
    when defined(leanCompiler):
      conf.quitOrRaise "compiler wasn't built with documentation generator"
    else:
      if conf.cmd in {cmdRst2tex, cmdMd2tex}:
        loadConfigs(DocTexConfig, cache, conf, graph.idgen)
        commandRst2TeX(cache, conf, preferMarkdown = (conf.cmd == cmdMd2tex))
      else:
        docLikeCmd commandDoc2(graph, TexExt)
  of cmdJsondoc0: docLikeCmd commandJson(cache, conf)
  of cmdJsondoc:
    docLikeCmd():
      commandDoc2(graph, JsonExt)
      if optGenIndex in conf.globalOptions and optWholeProject in conf.globalOptions:
        commandBuildIndexJson(conf, $conf.outDir)
  of cmdCtags: docLikeCmd commandTags(cache, conf)
  of cmdBuildindex: docLikeCmd commandBuildIndex(conf, $conf.projectFull, conf.outFile)
  of cmdGendepend: commandGenDepend(graph)
  of cmdDump:
    if getConfigVar(conf, "dump.format") == "json":
      wantMainModule(conf)

      var definedSymbols = newJArray()
      for s in definedSymbolNames(conf.symbols): definedSymbols.elems.add(%s)

      var libpaths = newJArray()
      var lazyPaths = newJArray()
      for dir in conf.searchPaths: libpaths.elems.add(%dir.string)
      for dir in conf.lazyPaths: lazyPaths.elems.add(%dir.string)

      var hints = newJObject() # consider factoring with `listHints`
      for a in hintMin..hintMax:
        hints[$a] = %(a in conf.notes)
      var warnings = newJObject()
      for a in warnMin..warnMax:
        warnings[$a] = %(a in conf.notes)

      var dumpdata = %[
        (key: "version", val: %VersionAsString),
        (key: "nimExe", val: %(getAppFilename())),
        (key: "prefixdir", val: %conf.getPrefixDir().string),
        (key: "libpath", val: %conf.libpath.string),
        (key: "project_path", val: %conf.projectFull.string),
        (key: "defined_symbols", val: definedSymbols),
        (key: "lib_paths", val: %libpaths),
        (key: "lazyPaths", val: %lazyPaths),
        (key: "outdir", val: %conf.outDir.string),
        (key: "out", val: %conf.outFile.string),
        (key: "nimcache", val: %getNimcacheDir(conf).string),
        (key: "hints", val: hints),
        (key: "warnings", val: warnings),
      ]

      msgWriteln(conf, $dumpdata, {msgStdout, msgSkipHook, msgNoUnitSep})
        # `msgNoUnitSep` to avoid generating invalid json, refs bug #17853
    else:
      msgWriteln(conf, "-- list of currently defined symbols --",
                 {msgStdout, msgSkipHook, msgNoUnitSep})
      for s in definedSymbolNames(conf.symbols): msgWriteln(conf, s, {msgStdout, msgSkipHook, msgNoUnitSep})
      msgWriteln(conf, "-- end of list --", {msgStdout, msgSkipHook})

      for it in conf.searchPaths: msgWriteln(conf, it.string)
  of cmdCheck:
    commandCheck(graph)
  of cmdM:
    graph.config.symbolFiles = v2Sf
    setUseIc(graph.config.symbolFiles != disabledSf)
    commandCheck(graph)
  of cmdParse:
    wantMainModule(conf)
    discard parseFile(conf.projectMainIdx, cache, conf)
  of cmdRod:
    wantMainModule(conf)
    commandView(graph)
    #msgWriteln(conf, "Beware: Indentation tokens depend on the parser's state!")
  of cmdInteractive: commandInteractive(graph)
  of cmdNimscript:
    if conf.projectIsCmd or conf.projectIsStdin: discard
    elif not fileExists(conf.projectFull):
      rawMessage(conf, errGenerated, "NimScript file does not exist: " & conf.projectFull.string)
    # main NimScript logic handled in `loadConfigs`.
  of cmdNop: discard
  of cmdJsonscript:
    setOutFile(graph.config)
    commandJsonScript(graph)
  of cmdUnknown, cmdNone, cmdIdeTools:
    rawMessage(conf, errGenerated, "invalid command: " & conf.command)

  if conf.errorCounter == 0 and conf.cmd notin {cmdTcc, cmdDump, cmdNop}:
    if optProfileVM in conf.globalOptions:
      echo conf.dump(conf.vmProfileData)
    genSuccessX(conf)

  when PrintRopeCacheStats:
    echo "rope cache stats: "
    echo "  tries : ", gCacheTries
    echo "  misses: ", gCacheMisses
    echo "  int tries: ", gCacheIntTries
    echo "  efficiency: ", formatFloat(1-(gCacheMisses.float/gCacheTries.float),
                                       ffDecimal, 3)

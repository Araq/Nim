#
#
#           The Nim Compiler
#        (c) Copyright 2018 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Helpers for binaries that use compiler passes, e.g.: nim, nimsuggest

import
  options, idents, nimconf, extccomp, commands, msgs,
  lineinfos, modulegraphs, condsyms, pathutils

import std/[os, parseopt]

proc prependCurDir*(f: AbsoluteFile): AbsoluteFile =
  when defined(unix):
    if os.isAbsolute(f.string): result = f
    else: result = AbsoluteFile("./" & f.string)
  else:
    result = f

proc addCmdPrefix*(result: var string, kind: CmdLineKind) =
  # consider moving this to std/parseopt
  case kind
  of cmdLongOption: result.add "--"
  of cmdShortOption: result.add "-"
  of cmdArgument, cmdEnd: discard

type
  NimProg* = ref object
    suggestMode*: bool
    supportsStdinFile*: bool
    processCmdLine*: proc(pass: TCmdLinePass, cmd: string; config: ConfigRef)

proc initDefinesProg*(self: NimProg, conf: ConfigRef, name: string) =
  condsyms.initDefines(conf.symbols)
  defineSymbol conf.symbols, name

proc processCmdLineAndProjectPath*(self: NimProg, conf: ConfigRef) =
  self.processCmdLine(passCmd1, "", conf)
  if conf.projectIsCmd and conf.projectName in ["-", ""]:
    handleCmdInput(conf)
  elif self.supportsStdinFile and conf.projectName == "-":
    handleStdinInput(conf)
  elif conf.projectName != "":
    setFromProjectName(conf, conf.projectName)
  else:
    conf.projectPath = AbsoluteDir canonicalizePath(conf, AbsoluteFile getCurrentDir())

proc loadConfigsAndProcessCmdLine*(self: NimProg, cache: IdentCache; conf: ConfigRef;
                                   graph: ModuleGraph): bool =
  if self.suggestMode:
    conf.setCmd cmdIdeTools
  if conf.cmd == cmdNimscript:
    incl(conf.globalOptions, optWasNimscript)
  loadConfigs(DefaultConfig, cache, conf, graph.idgen) # load all config files
  # restores `conf.notes` after loading config files
  # because it has overwrites the notes when compiling the system module which
  # is a foreign module compared to the project
  if conf.cmd in cmdBackends:
    conf.notes = conf.mainPackageNotes

  if not self.suggestMode:
    let scriptFile = conf.projectFull.changeFileExt("nims")
    # 'nim foo.nims' means to just run the NimScript file and do nothing more:
    if fileExists(scriptFile) and scriptFile == conf.projectFull:
      if conf.cmd == cmdNone: conf.setCmd cmdNimscript
      if conf.cmd == cmdNimscript: return false
  # now process command line arguments again, because some options in the
  # command line can overwrite the config file's settings
  if conf.backend != backendJs: # bug #19059
    extccomp.initVars(conf)
  self.processCmdLine(passCmd2, "", conf)
  if conf.cmd == cmdNone:
    rawMessage(conf, errGenerated, "command missing")

  graph.suggestMode = self.suggestMode
  return true

proc loadConfigsAndRunMainCommand*(self: NimProg, cache: IdentCache; conf: ConfigRef; graph: ModuleGraph): bool =
  ## Alias for loadConfigsAndProcessCmdLine, here for backwards compatibility
  loadConfigsAndProcessCmdLine(self, cache, conf, graph)

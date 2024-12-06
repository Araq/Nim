#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# This module handles the parsing of command line arguments.

# We do this here before the 'import' statement so 'defined' does not get
# confused with 'TGCMode.gcMarkAndSweep' etc.
template bootSwitch(name, expr, userString) =
  # Helper to build boot constants, for debugging you can 'echo' the else part.
  const name = if expr: " " & userString else: ""

bootSwitch(usedRelease, defined(release), "-d:release")
bootSwitch(usedDanger, defined(danger), "-d:danger")
# `useLinenoise` deprecated in favor of `nimUseLinenoise`, kept for backward compatibility
bootSwitch(useLinenoise, defined(nimUseLinenoise) or defined(useLinenoise), "-d:nimUseLinenoise")
bootSwitch(usedBoehm, defined(boehmgc), "--gc:boehm")
bootSwitch(usedMarkAndSweep, defined(gcmarkandsweep), "--gc:markAndSweep")
bootSwitch(usedGoGC, defined(gogc), "--gc:go")
bootSwitch(usedNoGC, defined(nogc), "--gc:none")

import std/[setutils, os, strutils, parseutils, parseopt, sequtils, strtabs, enumutils]
import
  msgs, options, nversion, condsyms, extccomp, platform,
  wordrecg, nimblecmd, lineinfos, pathutils

import std/pathnorm

from ast import setUseIc, eqTypeFlags, tfGcSafe, tfNoSideEffect

when defined(nimPreviewSlimSystem):
  import std/assertions

# but some have deps to imported modules. Yay.
bootSwitch(usedTinyC, hasTinyCBackend, "-d:tinyc")
bootSwitch(usedFFI, hasFFI, "-d:nimHasLibFFI")

type
  TCmdLinePass* = enum
    passCmd1,                 # first pass over the command line
    passCmd2,                 # second pass over the command line
    passPP                    # preprocessor called processCommand()

const
  HelpMessage = "Nim Compiler Version $1 [$2: $3]\n" &
      "Compiled at $4\n" &
      "Copyright (c) 2006-" & copyrightYear & " by Andreas Rumpf\n"

proc genFeatureDesc[T: enum](t: typedesc[T]): string {.compileTime.} =
  result = ""
  for f in T:
    if result.len > 0: result.add "|"
    result.add $f

const
  Usage = slurp"../doc/basicopt.txt".replace(" //", "   ")
  AdvancedUsage = slurp"../doc/advopt.txt".replace(" //", "   ") % [genFeatureDesc(Feature), genFeatureDesc(LegacyFeature)]

proc getCommandLineDesc(conf: ConfigRef): string =
  result = (HelpMessage % [VersionAsString, platform.OS[conf.target.hostOS].name,
                           CPU[conf.target.hostCPU].name, CompileDate]) &
                           Usage

proc helpOnError(conf: ConfigRef; pass: TCmdLinePass) =
  if pass == passCmd1:
    msgWriteln(conf, getCommandLineDesc(conf), {msgStdout})
    msgQuit(0)

proc writeAdvancedUsage(conf: ConfigRef; pass: TCmdLinePass) =
  if pass == passCmd1:
    msgWriteln(conf, (HelpMessage % [VersionAsString,
                                 platform.OS[conf.target.hostOS].name,
                                 CPU[conf.target.hostCPU].name, CompileDate]) &
                                 AdvancedUsage,
               {msgStdout})
    msgQuit(0)

proc writeFullhelp(conf: ConfigRef; pass: TCmdLinePass) =
  if pass == passCmd1:
    msgWriteln(conf, `%`(HelpMessage, [VersionAsString,
                                 platform.OS[conf.target.hostOS].name,
                                 CPU[conf.target.hostCPU].name, CompileDate]) &
                                 Usage & AdvancedUsage,
               {msgStdout})
    msgQuit(0)

proc writeVersionInfo(conf: ConfigRef; pass: TCmdLinePass) =
  if pass == passCmd1:
    msgWriteln(conf, `%`(HelpMessage, [VersionAsString,
                                 platform.OS[conf.target.hostOS].name,
                                 CPU[conf.target.hostCPU].name, CompileDate]),
               {msgStdout})

    const gitHash {.strdefine.} = gorge("git log -n 1 --format=%H").strip
      # xxx move this logic to std/private/gitutils
    when gitHash.len == 40:
      msgWriteln(conf, "git hash: " & gitHash, {msgStdout})

    msgWriteln(conf, "active boot switches:" & usedRelease & usedDanger &
      usedTinyC & useLinenoise &
      usedFFI & usedBoehm & usedMarkAndSweep & usedGoGC & usedNoGC,
               {msgStdout})
    msgQuit(0)

proc writeCommandLineUsage*(conf: ConfigRef) =
  msgWriteln(conf, getCommandLineDesc(conf), {msgStdout})

proc addPrefix(switch: string): string =
  if switch.len <= 1: result = "-" & switch
  else: result = "--" & switch

const
  errInvalidCmdLineOption = "invalid command line option: '$1'"
  errOnOrOffExpectedButXFound = "'on' or 'off' expected, but '$1' found"
  errOnOffOrListExpectedButXFound = "'on', 'off' or 'list' expected, but '$1' found"
  errOffHintsError = "'off', 'hint', 'error' or 'usages' expected, but '$1' found"

proc invalidCmdLineOption(conf: ConfigRef; pass: TCmdLinePass, switch: string, info: TLineInfo) =
  if switch == " ": localError(conf, info, errInvalidCmdLineOption % "-")
  else: localError(conf, info, errInvalidCmdLineOption % addPrefix(switch))

proc splitSwitch(conf: ConfigRef; switch: string, cmd, arg: var string, pass: TCmdLinePass,
                 info: TLineInfo) =
  cmd = ""
  var i = 0
  if i < switch.len and switch[i] == '-': inc(i)
  if i < switch.len and switch[i] == '-': inc(i)
  while i < switch.len:
    case switch[i]
    of 'a'..'z', 'A'..'Z', '0'..'9', '_', '.': cmd.add(switch[i])
    else: break
    inc(i)
  if i >= switch.len: arg = ""
  # cmd:arg => (cmd,arg)
  elif switch[i] in {':', '='}: arg = substr(switch, i + 1)
  # cmd[sub]:rest => (cmd,[sub]:rest)
  elif switch[i] == '[': arg = substr(switch, i)
  else: invalidCmdLineOption(conf, pass, switch, info)

template switchOn(arg: string): bool =
  # xxx use `switchOn` wherever appropriate
  case arg.normalize
  of "", "on": true
  of "off": false
  else:
    localError(conf, info, errOnOrOffExpectedButXFound % arg)
    false

proc processOnOffSwitch(conf: ConfigRef; op: TOptions, arg: string, pass: TCmdLinePass,
                        info: TLineInfo) =
  case arg.normalize
  of "", "on": conf.options.incl op
  of "off": conf.options.excl op
  else: localError(conf, info, errOnOrOffExpectedButXFound % arg)

proc processOnOffSwitchOrList(conf: ConfigRef; op: TOptions, arg: string, pass: TCmdLinePass,
                              info: TLineInfo): bool =
  result = false
  case arg.normalize
  of "on": conf.options.incl op
  of "off": conf.options.excl op
  of "list": result = true
  else: localError(conf, info, errOnOffOrListExpectedButXFound % arg)

proc processOnOffSwitchG(conf: ConfigRef; op: TGlobalOptions, arg: string, pass: TCmdLinePass,
                         info: TLineInfo) =
  case arg.normalize
  of "", "on": conf.globalOptions.incl op
  of "off": conf.globalOptions.excl op
  else: localError(conf, info, errOnOrOffExpectedButXFound % arg)

proc expectArg(conf: ConfigRef; switch, arg: string, pass: TCmdLinePass, info: TLineInfo) =
  if arg == "":
    localError(conf, info, "argument for command line option expected: '$1'" % addPrefix(switch))

proc expectNoArg(conf: ConfigRef; switch, arg: string, pass: TCmdLinePass, info: TLineInfo) =
  if arg != "":
    localError(conf, info, "invalid argument for command line option: '$1'" % addPrefix(switch))

proc processSpecificNote*(arg: string, state: TSpecialWord, pass: TCmdLinePass,
                         info: TLineInfo; orig: string; conf: ConfigRef) =
  var id = ""  # arg = key or [key] or key:val or [key]:val;  with val=on|off
  var i = 0
  var notes: set[TMsgKind] = {}
  var isBracket = false
  if i < arg.len and arg[i] == '[':
    isBracket = true
    inc(i)
  while i < arg.len and (arg[i] notin {':', '=', ']'}):
    id.add(arg[i])
    inc(i)
  if isBracket:
    if i < arg.len and arg[i] == ']': inc(i)
    else: invalidCmdLineOption(conf, pass, orig, info)

  if i == arg.len: discard
  elif i < arg.len and (arg[i] in {':', '='}): inc(i)
  else: invalidCmdLineOption(conf, pass, orig, info)

  let isSomeHint = state in {wHint, wHintAsError}
  template findNote(noteMin, noteMax, name) =
    # unfortunately, hintUser and warningUser clash, otherwise implementation would simplify a bit
    let x = findStr(noteMin, noteMax, id, errUnknown)
    if x != errUnknown: notes = {TNoteKind(x)}
    else:
      if isSomeHint:
        message(conf, info, hintUnknownHint, id)
      else:
        localError(conf, info, "unknown $#: $#" % [name, id])
  case id.normalize
  of "all": # other note groups would be easy to support via additional cases
    notes = if isSomeHint: {hintMin..hintMax} else: {warnMin..warnMax}
  elif isSomeHint: findNote(hintMin, hintMax, "hint")
  else: findNote(warnMin, warnMax, "warning")
  var val = substr(arg, i).normalize
  if val == "": val = "on"
  if val notin ["on", "off"]:
    # xxx in future work we should also allow users to have control over `foreignPackageNotes`
    # so that they can enable `hints|warnings|warningAsErrors` for all the code they depend on.
    localError(conf, info, errOnOrOffExpectedButXFound % arg)
  else:
    let isOn = val == "on"
    if isOn and id.normalize == "all":
      localError(conf, info, "only 'all:off' is supported")
    for n in notes:
      if n notin conf.cmdlineNotes or pass == passCmd1:
        if pass == passCmd1: incl(conf.cmdlineNotes, n)
        incl(conf.modifiedyNotes, n)
        if state in {wWarningAsError, wHintAsError}:
          conf.warningAsErrors[n] = isOn # xxx rename warningAsErrors to noteAsErrors
        else:
          conf.notes[n] = isOn
          conf.mainPackageNotes[n] = isOn
        if not isOn: excl(conf.foreignPackageNotes, n)

proc processCompile(conf: ConfigRef; filename: string) =
  var found = findFile(conf, filename)
  if found.isEmpty: found = AbsoluteFile filename
  extccomp.addExternalFileToCompile(conf, found)

const
  errNoneBoehmRefcExpectedButXFound = "'arc', 'orc', 'atomicArc', 'markAndSweep', 'boehm', 'go', 'none', 'regions', or 'refc' expected, but '$1' found"
  errNoneSpeedOrSizeExpectedButXFound = "'none', 'speed' or 'size' expected, but '$1' found"
  errGuiConsoleOrLibExpectedButXFound = "'gui', 'console', 'lib' or 'staticlib' expected, but '$1' found"
  errInvalidExceptionSystem = "'goto', 'setjmp', 'cpp' or 'quirky' expected, but '$1' found"
  errInvalidFeatureButXFound = Feature.toSeq.map(proc(val:Feature): string = "'$1'" % $val).join(", ") & " expected, but '$1' found"

template warningOptionNoop(switch: string) =
  warningDeprecated(conf, info, "'$#' is deprecated, now a noop" % switch)

template deprecatedAlias(oldName, newName: string) =
  warningDeprecated(conf, info, "'$#' is a deprecated alias for '$#'" % [oldName, newName])

proc testCompileOptionArg*(conf: ConfigRef; switch, arg: string, info: TLineInfo): bool =
  case switch.normalize
  of "gc", "mm":
    case arg.normalize
    of "boehm": result = conf.selectedGC == gcBoehm
    of "refc": result = conf.selectedGC == gcRefc
    of "markandsweep": result = conf.selectedGC == gcMarkAndSweep
    of "destructors", "arc": result = conf.selectedGC == gcArc
    of "orc": result = conf.selectedGC == gcOrc
    of "hooks": result = conf.selectedGC == gcHooks
    of "go": result = conf.selectedGC == gcGo
    of "none": result = conf.selectedGC == gcNone
    of "stack", "regions": result = conf.selectedGC == gcRegions
    of "atomicarc": result = conf.selectedGC == gcAtomicArc
    else:
      result = false
      localError(conf, info, errNoneBoehmRefcExpectedButXFound % arg)
  of "opt":
    case arg.normalize
    of "speed": result = contains(conf.options, optOptimizeSpeed)
    of "size": result = contains(conf.options, optOptimizeSize)
    of "none": result = conf.options * {optOptimizeSpeed, optOptimizeSize} == {}
    else:
      result = false
      localError(conf, info, errNoneSpeedOrSizeExpectedButXFound % arg)
  of "verbosity": result = $conf.verbosity == arg
  of "app":
    case arg.normalize
    of "gui": result = contains(conf.globalOptions, optGenGuiApp)
    of "console": result = not contains(conf.globalOptions, optGenGuiApp)
    of "lib": result = contains(conf.globalOptions, optGenDynLib) and
                      not contains(conf.globalOptions, optGenGuiApp)
    of "staticlib": result = contains(conf.globalOptions, optGenStaticLib) and
                      not contains(conf.globalOptions, optGenGuiApp)
    else:
      result = false
      localError(conf, info, errGuiConsoleOrLibExpectedButXFound % arg)
  of "dynliboverride":
    result = isDynlibOverride(conf, arg)
  of "exceptions":
    case arg.normalize
    of "cpp": result = conf.exc == excCpp
    of "setjmp": result = conf.exc == excSetjmp
    of "quirky": result = conf.exc == excQuirky
    of "goto": result = conf.exc == excGoto
    else:
      result = false
      localError(conf, info, errInvalidExceptionSystem % arg)
  of "experimental":
    try:
      result = conf.features.contains parseEnum[Feature](arg)
    except ValueError:
      result = false
      localError(conf, info, errInvalidFeatureButXFound % arg)
  else:
    result = false
    invalidCmdLineOption(conf, passCmd1, switch, info)

proc testCompileOption*(conf: ConfigRef; switch: string, info: TLineInfo): bool =
  case switch.normalize
  of "debuginfo": result = contains(conf.globalOptions, optCDebug)
  of "compileonly", "c": result = contains(conf.globalOptions, optCompileOnly)
  of "nolinking": result = contains(conf.globalOptions, optNoLinking)
  of "nomain": result = contains(conf.globalOptions, optNoMain)
  of "forcebuild", "f": result = contains(conf.globalOptions, optForceFullMake)
  of "warnings", "w": result = contains(conf.options, optWarns)
  of "hints": result = contains(conf.options, optHints)
  of "threadanalysis": result = contains(conf.globalOptions, optThreadAnalysis)
  of "stacktrace": result = contains(conf.options, optStackTrace)
  of "stacktracemsgs": result = contains(conf.options, optStackTraceMsgs)
  of "linetrace": result = contains(conf.options, optLineTrace)
  of "debugger": result = contains(conf.globalOptions, optCDebug)
  of "profiler": result = contains(conf.options, optProfiler)
  of "memtracker": result = contains(conf.options, optMemTracker)
  of "checks", "x": result = conf.options * ChecksOptions == ChecksOptions
  of "floatchecks":
    result = conf.options * {optNaNCheck, optInfCheck} == {optNaNCheck, optInfCheck}
  of "infchecks": result = contains(conf.options, optInfCheck)
  of "nanchecks": result = contains(conf.options, optNaNCheck)
  of "objchecks": result = contains(conf.options, optObjCheck)
  of "fieldchecks": result = contains(conf.options, optFieldCheck)
  of "rangechecks": result = contains(conf.options, optRangeCheck)
  of "boundchecks": result = contains(conf.options, optBoundsCheck)
  of "refchecks":
    warningDeprecated(conf, info, "refchecks is deprecated!")
    result = contains(conf.options, optRefCheck)
  of "overflowchecks": result = contains(conf.options, optOverflowCheck)
  of "staticboundchecks": result = contains(conf.options, optStaticBoundsCheck)
  of "stylechecks": result = contains(conf.options, optStyleCheck)
  of "linedir": result = contains(conf.options, optLineDir)
  of "assertions", "a": result = contains(conf.options, optAssert)
  of "run", "r": result = contains(conf.globalOptions, optRun)
  of "symbolfiles": result = conf.symbolFiles != disabledSf
  of "genscript": result = contains(conf.globalOptions, optGenScript)
  of "gencdeps": result = contains(conf.globalOptions, optGenCDeps)
  of "threads": result = contains(conf.globalOptions, optThreads)
  of "tlsemulation": result = contains(conf.globalOptions, optTlsEmulation)
  of "implicitstatic": result = contains(conf.options, optImplicitStatic)
  of "patterns", "trmacros":
    if switch.normalize == "patterns": deprecatedAlias(switch, "trmacros")
    result = contains(conf.options, optTrMacros)
  of "excessivestacktrace": result = contains(conf.globalOptions, optExcessiveStackTrace)
  of "nilseqs", "nilchecks", "taintmode":
    warningOptionNoop(switch)
    result = false
  of "panics": result = contains(conf.globalOptions, optPanics)
  of "jsbigint64": result = contains(conf.globalOptions, optJsBigInt64)
  else:
    result = false
    invalidCmdLineOption(conf, passCmd1, switch, info)

proc processPath(conf: ConfigRef; path: string, info: TLineInfo,
                 notRelativeToProj = false): AbsoluteDir =
  let p = if os.isAbsolute(path) or '$' in path:
            path
          elif notRelativeToProj:
            getCurrentDir() / path
          else:
            conf.projectPath.string / path
  try:
    result = AbsoluteDir pathSubs(conf, p, toFullPath(conf, info).splitFile().dir)
  except ValueError:
    localError(conf, info, "invalid path: " & p)
    result = AbsoluteDir p

proc processCfgPath(conf: ConfigRef; path: string, info: TLineInfo): AbsoluteDir =
  let path = if path.len > 0 and path[0] == '"': strutils.unescape(path)
             else: path
  let basedir = toFullPath(conf, info).splitFile().dir
  let p = if os.isAbsolute(path) or '$' in path:
            path
          else:
            basedir / path
  try:
    result = AbsoluteDir pathSubs(conf, p, basedir)
  except ValueError:
    localError(conf, info, "invalid path: " & p)
    result = AbsoluteDir p

const
  errInvalidNumber = "$1 is not a valid number"

proc makeAbsolute(s: string): AbsoluteFile =
  if isAbsolute(s):
    AbsoluteFile pathnorm.normalizePath(s)
  else:
    AbsoluteFile pathnorm.normalizePath(os.getCurrentDir() / s)

proc setTrackingInfo(conf: ConfigRef; dirty, file, line, column: string,
                     info: TLineInfo) =
  ## set tracking info, common code for track, trackDirty, & ideTrack
  var ln: int = 0
  var col: int = 0
  if parseUtils.parseInt(line, ln) <= 0:
    localError(conf, info, errInvalidNumber % line)
  if parseUtils.parseInt(column, col) <= 0:
    localError(conf, info, errInvalidNumber % column)

  let a = makeAbsolute(file)
  if dirty == "":
    conf.m.trackPos = newLineInfo(conf, a, ln, col)
  else:
    let dirtyOriginalIdx = fileInfoIdx(conf, a)
    if dirtyOriginalIdx.int32 >= 0:
      msgs.setDirtyFile(conf, dirtyOriginalIdx, makeAbsolute(dirty))
    conf.m.trackPos = newLineInfo(dirtyOriginalIdx, ln, col)

proc trackDirty(conf: ConfigRef; arg: string, info: TLineInfo) =
  var a = arg.split(',')
  if a.len != 4: localError(conf, info,
                            "DIRTY_BUFFER,ORIGINAL_FILE,LINE,COLUMN expected")
  setTrackingInfo(conf, a[0], a[1], a[2], a[3], info)

proc track(conf: ConfigRef; arg: string, info: TLineInfo) =
  var a = arg.split(',')
  if a.len != 3: localError(conf, info, "FILE,LINE,COLUMN expected")
  setTrackingInfo(conf, "", a[0], a[1], a[2], info)

proc trackIde(conf: ConfigRef; cmd: IdeCmd, arg: string, info: TLineInfo) =
  ## set the tracking info related to an ide cmd, supports optional dirty file
  var a = arg.split(',')
  case a.len
  of 4:
    setTrackingInfo(conf, a[0], a[1], a[2], a[3], info)
  of 3:
    setTrackingInfo(conf, "", a[0], a[1], a[2], info)
  else:
    localError(conf, info, "[DIRTY_BUFFER,]ORIGINAL_FILE,LINE,COLUMN expected")
  conf.ideCmd = cmd

proc dynlibOverride(conf: ConfigRef; switch, arg: string, pass: TCmdLinePass, info: TLineInfo) =
  if pass in {passCmd2, passPP}:
    expectArg(conf, switch, arg, pass, info)
    options.inclDynlibOverride(conf, arg)

template handleStdinOrCmdInput =
  conf.projectFull = conf.projectName.AbsoluteFile
  conf.projectPath = AbsoluteDir getCurrentDir()
  if conf.outDir.isEmpty:
    conf.outDir = getNimcacheDir(conf)

proc handleStdinInput*(conf: ConfigRef) =
  conf.projectName = "stdinfile"
  conf.projectIsStdin = true
  handleStdinOrCmdInput()

proc handleCmdInput*(conf: ConfigRef) =
  conf.projectName = "cmdfile"
  handleStdinOrCmdInput()

proc parseCommand*(command: string): Command =
  case command.normalize
  of "c", "cc", "compile", "compiletoc": cmdCompileToC
  of "cpp", "compiletocpp": cmdCompileToCpp
  of "objc", "compiletooc": cmdCompileToOC
  of "js", "compiletojs": cmdCompileToJS
  of "r": cmdCrun
  of "m": cmdM
  of "run": cmdTcc
  of "check": cmdCheck
  of "e": cmdNimscript
  of "doc0": cmdDoc0
  of "doc2", "doc": cmdDoc
  of "doc2tex": cmdDoc2tex
  of "rst2html": cmdRst2html
  of "md2tex": cmdMd2tex
  of "md2html": cmdMd2html
  of "rst2tex": cmdRst2tex
  of "jsondoc0": cmdJsondoc0
  of "jsondoc2", "jsondoc": cmdJsondoc
  of "ctags": cmdCtags
  of "buildindex": cmdBuildindex
  of "gendepend": cmdGendepend
  of "dump": cmdDump
  of "parse": cmdParse
  of "rod": cmdRod
  of "secret": cmdInteractive
  of "nop", "help": cmdNop
  of "jsonscript": cmdJsonscript
  else: cmdUnknown

proc setCmd*(conf: ConfigRef, cmd: Command) =
  ## sets cmd, backend so subsequent flags can query it (e.g. so --gc:arc can be ignored for backendJs)
  # Note that `--backend` can override the backend, so the logic here must remain reversible.
  conf.cmd = cmd
  case cmd
  of cmdCompileToC, cmdCrun, cmdTcc: conf.backend = backendC
  of cmdCompileToCpp: conf.backend = backendCpp
  of cmdCompileToOC: conf.backend = backendObjc
  of cmdCompileToJS: conf.backend = backendJs
  else: discard

proc setCommandEarly*(conf: ConfigRef, command: string) =
  conf.command = command
  setCmd(conf, command.parseCommand)
  # command early customizations
  # must be handled here to honor subsequent `--hint:x:on|off`
  case conf.cmd
  of cmdRst2html, cmdRst2tex, cmdMd2html, cmdMd2tex:
      # xxx see whether to add others: cmdGendepend, etc.
    conf.foreignPackageNotes = {hintSuccessX}
  else:
    conf.foreignPackageNotes = foreignPackageNotesDefault

proc specialDefine(conf: ConfigRef, key: string; pass: TCmdLinePass) =
  # Keep this syncronized with the default config/nim.cfg!
  if cmpIgnoreStyle(key, "nimQuirky") == 0:
    conf.exc = excQuirky
  elif cmpIgnoreStyle(key, "release") == 0 or cmpIgnoreStyle(key, "danger") == 0:
    if pass in {passCmd1, passPP}:
      conf.options.excl {optStackTrace, optLineTrace, optLineDir, optOptimizeSize}
      conf.globalOptions.excl {optExcessiveStackTrace, optCDebug}
      conf.options.incl optOptimizeSpeed
  if cmpIgnoreStyle(key, "danger") == 0 or cmpIgnoreStyle(key, "quick") == 0:
    if pass in {passCmd1, passPP}:
      conf.options.excl {optObjCheck, optFieldCheck, optRangeCheck, optBoundsCheck,
        optOverflowCheck, optAssert, optStackTrace, optLineTrace, optLineDir}
      conf.globalOptions.excl {optCDebug}

proc initOrcDefines*(conf: ConfigRef) =
  conf.selectedGC = gcOrc
  defineSymbol(conf.symbols, "gcorc")
  defineSymbol(conf.symbols, "gcdestructors")
  incl conf.globalOptions, optSeqDestructors
  incl conf.globalOptions, optTinyRtti
  defineSymbol(conf.symbols, "nimSeqsV2")
  defineSymbol(conf.symbols, "nimV2")
  if conf.exc == excNone and conf.backend != backendCpp:
    conf.exc = excGoto

proc registerArcOrc(pass: TCmdLinePass, conf: ConfigRef) =
  defineSymbol(conf.symbols, "gcdestructors")
  incl conf.globalOptions, optSeqDestructors
  incl conf.globalOptions, optTinyRtti
  if pass in {passCmd2, passPP}:
    defineSymbol(conf.symbols, "nimSeqsV2")
    defineSymbol(conf.symbols, "nimV2")
  if conf.exc == excNone and conf.backend != backendCpp:
    conf.exc = excGoto

proc unregisterArcOrc*(conf: ConfigRef) =
  undefSymbol(conf.symbols, "gcdestructors")
  undefSymbol(conf.symbols, "gcarc")
  undefSymbol(conf.symbols, "gcorc")
  undefSymbol(conf.symbols, "gcatomicarc")
  undefSymbol(conf.symbols, "nimSeqsV2")
  undefSymbol(conf.symbols, "nimV2")
  excl conf.globalOptions, optSeqDestructors
  excl conf.globalOptions, optTinyRtti

proc processMemoryManagementOption(switch, arg: string, pass: TCmdLinePass,
                info: TLineInfo; conf: ConfigRef) =
  if conf.backend == backendJs: return # for: bug #16033
  expectArg(conf, switch, arg, pass, info)
  if pass in {passCmd2, passPP}:
    case arg.normalize
    of "boehm":
      unregisterArcOrc(conf)
      conf.selectedGC = gcBoehm
      defineSymbol(conf.symbols, "boehmgc")
      incl conf.globalOptions, optTlsEmulation # Boehm GC doesn't scan the real TLS
    of "refc":
      unregisterArcOrc(conf)
      defineSymbol(conf.symbols, "gcrefc")
      conf.selectedGC = gcRefc
    of "markandsweep":
      unregisterArcOrc(conf)
      conf.selectedGC = gcMarkAndSweep
      defineSymbol(conf.symbols, "gcmarkandsweep")
    of "destructors", "arc":
      conf.selectedGC = gcArc
      defineSymbol(conf.symbols, "gcarc")
      registerArcOrc(pass, conf)
    of "orc":
      conf.selectedGC = gcOrc
      defineSymbol(conf.symbols, "gcorc")
      registerArcOrc(pass, conf)
    of "atomicarc":
      conf.selectedGC = gcAtomicArc
      defineSymbol(conf.symbols, "gcatomicarc")
      registerArcOrc(pass, conf)
    of "hooks":
      conf.selectedGC = gcHooks
      defineSymbol(conf.symbols, "gchooks")
      incl conf.globalOptions, optSeqDestructors
      processOnOffSwitchG(conf, {optSeqDestructors}, arg, pass, info)
      if pass in {passCmd2, passPP}:
        defineSymbol(conf.symbols, "nimSeqsV2")
    of "go":
      unregisterArcOrc(conf)
      conf.selectedGC = gcGo
      defineSymbol(conf.symbols, "gogc")
    of "none":
      unregisterArcOrc(conf)
      conf.selectedGC = gcNone
      defineSymbol(conf.symbols, "nogc")
    of "stack", "regions":
      unregisterArcOrc(conf)
      conf.selectedGC = gcRegions
      defineSymbol(conf.symbols, "gcregions")
    else: localError(conf, info, errNoneBoehmRefcExpectedButXFound % arg)

proc pathRelativeToConfig(arg: string, pass: TCmdLinePass, conf: ConfigRef): string =
  if pass == passPP and not isAbsolute(arg):
    assert isAbsolute(conf.currentConfigDir), "something is wrong with currentConfigDir"
    result = conf.currentConfigDir / arg
  else:
    result = arg

proc processSwitch*(switch, arg: string, pass: TCmdLinePass, info: TLineInfo;
                    conf: ConfigRef) =
  var key = ""
  var val = ""
  case switch.normalize
  of "eval":
    expectArg(conf, switch, arg, pass, info)
    conf.projectIsCmd = true
    conf.cmdInput = arg # can be empty (a nim file with empty content is valid too)
    if conf.cmd == cmdNone:
      conf.command = "e"
      conf.setCmd cmdNimscript # better than `cmdCrun` as a default
      conf.implicitCmd = true
  of "path", "p":
    expectArg(conf, switch, arg, pass, info)
    for path in nimbleSubs(conf, arg):
      addPath(conf, if pass == passPP: processCfgPath(conf, path, info)
                    else: processPath(conf, path, info), info)
  of "nimblepath":
    if pass in {passCmd2, passPP} and optNoNimblePath notin conf.globalOptions:
      expectArg(conf, switch, arg, pass, info)
      var path = processPath(conf, arg, info, notRelativeToProj=true)
      let nimbleDir = AbsoluteDir getEnv("NIMBLE_DIR")
      if not nimbleDir.isEmpty and pass == passPP:
        path = nimbleDir / RelativeDir"pkgs2"
        nimblePath(conf, path, info)
        path = nimbleDir / RelativeDir"pkgs"
      nimblePath(conf, path, info)
  of "nonimblepath":
    expectNoArg(conf, switch, arg, pass, info)
    disableNimblePath(conf)
  of "clearnimblepath":
    expectNoArg(conf, switch, arg, pass, info)
    clearNimblePath(conf)
  of "excludepath":
    expectArg(conf, switch, arg, pass, info)
    let path = processPath(conf, arg, info)
    conf.searchPaths.keepItIf(it != path)
    conf.lazyPaths.keepItIf(it != path)
  of "nimcache":
    expectArg(conf, switch, arg, pass, info)
    var arg = arg
    # refs bug #18674, otherwise `--os:windows` messes up with `--nimcache` set
    # in config nims files, e.g. via: `import os; switch("nimcache", "/tmp/somedir")`
    if conf.target.targetOS == osWindows and DirSep == '/': arg = arg.replace('\\', '/')
    conf.nimcacheDir = processPath(conf, pathRelativeToConfig(arg, pass, conf), info, notRelativeToProj=true)
  of "out", "o":
    expectArg(conf, switch, arg, pass, info)
    let f = splitFile(processPath(conf, arg, info, notRelativeToProj=true).string)
    conf.outFile = RelativeFile f.name & f.ext
    conf.outDir = toAbsoluteDir f.dir
  of "outdir":
    expectArg(conf, switch, arg, pass, info)
    conf.outDir = processPath(conf, arg, info, notRelativeToProj=true)
  of "usenimcache":
    processOnOffSwitchG(conf, {optUseNimcache}, arg, pass, info)
  of "docseesrcurl":
    expectArg(conf, switch, arg, pass, info)
    conf.docSeeSrcUrl = arg
  of "docroot":
    conf.docRoot = if arg.len == 0: docRootDefault else: arg
  of "backend", "b":
    let backend = parseEnum(arg.normalize, TBackend.default)
    if backend == TBackend.default: localError(conf, info, "invalid backend: '$1'" % arg)
    if backend == backendJs: # bug #21209
      conf.globalOptions.excl {optThreadAnalysis, optThreads}
      if optRun in conf.globalOptions:
        # for now, -r uses nodejs, so define nodejs
        defineSymbol(conf.symbols, "nodejs")
    conf.backend = backend
  of "doccmd": conf.docCmd = arg
  of "define", "d":
    expectArg(conf, switch, arg, pass, info)
    if {':', '='} in arg:
      splitSwitch(conf, arg, key, val, pass, info)
      specialDefine(conf, key, pass)
      defineSymbol(conf.symbols, key, val)
    else:
      specialDefine(conf, arg, pass)
      defineSymbol(conf.symbols, arg)
  of "undef", "u":
    expectArg(conf, switch, arg, pass, info)
    undefSymbol(conf.symbols, arg)
  of "compile":
    expectArg(conf, switch, arg, pass, info)
    if pass in {passCmd2, passPP}: processCompile(conf, arg)
  of "link":
    expectArg(conf, switch, arg, pass, info)
    if pass in {passCmd2, passPP}:
      addExternalFileToLink(conf, AbsoluteFile arg)
  of "debuginfo":
    processOnOffSwitchG(conf, {optCDebug}, arg, pass, info)
  of "embedsrc":
    processOnOffSwitchG(conf, {optEmbedOrigSrc}, arg, pass, info)
  of "compileonly", "c":
    processOnOffSwitchG(conf, {optCompileOnly}, arg, pass, info)
  of "nolinking":
    processOnOffSwitchG(conf, {optNoLinking}, arg, pass, info)
  of "nomain":
    processOnOffSwitchG(conf, {optNoMain}, arg, pass, info)
  of "forcebuild", "f":
    processOnOffSwitchG(conf, {optForceFullMake}, arg, pass, info)
  of "project":
    processOnOffSwitchG(conf, {optWholeProject, optGenIndex}, arg, pass, info)
  of "gc":
    warningDeprecated(conf, info, "`gc:option` is deprecated; use `mm:option` instead")
    processMemoryManagementOption(switch, arg, pass, info, conf)
  of "mm":
    processMemoryManagementOption(switch, arg, pass, info, conf)
  of "warnings", "w":
    if processOnOffSwitchOrList(conf, {optWarns}, arg, pass, info): listWarnings(conf)
  of "warning": processSpecificNote(arg, wWarning, pass, info, switch, conf)
  of "hint": processSpecificNote(arg, wHint, pass, info, switch, conf)
  of "warningaserror": processSpecificNote(arg, wWarningAsError, pass, info, switch, conf)
  of "hintaserror": processSpecificNote(arg, wHintAsError, pass, info, switch, conf)
  of "hints":
    if processOnOffSwitchOrList(conf, {optHints}, arg, pass, info): listHints(conf)
  of "threadanalysis":
    if conf.backend == backendJs: discard
    else: processOnOffSwitchG(conf, {optThreadAnalysis}, arg, pass, info)
  of "stacktrace": processOnOffSwitch(conf, {optStackTrace}, arg, pass, info)
  of "stacktracemsgs": processOnOffSwitch(conf, {optStackTraceMsgs}, arg, pass, info)
  of "excessivestacktrace": processOnOffSwitchG(conf, {optExcessiveStackTrace}, arg, pass, info)
  of "linetrace": processOnOffSwitch(conf, {optLineTrace}, arg, pass, info)
  of "debugger":
    case arg.normalize
    of "on", "native", "gdb":
      conf.globalOptions.incl optCDebug
      conf.options.incl optLineDir
      #defineSymbol(conf.symbols, "nimTypeNames") # type names are used in gdb pretty printing
    of "off":
      conf.globalOptions.excl optCDebug
    else:
      localError(conf, info, "expected native|gdb|on|off but found " & arg)
  of "g": # alias for --debugger:native
    conf.globalOptions.incl optCDebug
    conf.options.incl optLineDir
    #defineSymbol(conf.symbols, "nimTypeNames") # type names are used in gdb pretty printing
  of "profiler":
    processOnOffSwitch(conf, {optProfiler}, arg, pass, info)
    if optProfiler in conf.options: defineSymbol(conf.symbols, "profiler")
    else: undefSymbol(conf.symbols, "profiler")
  of "memtracker":
    processOnOffSwitch(conf, {optMemTracker}, arg, pass, info)
    if optMemTracker in conf.options: defineSymbol(conf.symbols, "memtracker")
    else: undefSymbol(conf.symbols, "memtracker")
  of "hotcodereloading":
    processOnOffSwitchG(conf, {optHotCodeReloading}, arg, pass, info)
    if conf.hcrOn:
      defineSymbol(conf.symbols, "hotcodereloading")
      defineSymbol(conf.symbols, "useNimRtl")
      # hardcoded linking with dynamic runtime for MSVC for smaller binaries
      # should do the same for all compilers (wherever applicable)
      if isVSCompatible(conf):
        extccomp.addCompileOptionCmd(conf, "/MD")
    else:
      undefSymbol(conf.symbols, "hotcodereloading")
      undefSymbol(conf.symbols, "useNimRtl")
  of "checks", "x": processOnOffSwitch(conf, ChecksOptions, arg, pass, info)
  of "floatchecks":
    processOnOffSwitch(conf, {optNaNCheck, optInfCheck}, arg, pass, info)
  of "infchecks": processOnOffSwitch(conf, {optInfCheck}, arg, pass, info)
  of "nanchecks": processOnOffSwitch(conf, {optNaNCheck}, arg, pass, info)
  of "objchecks": processOnOffSwitch(conf, {optObjCheck}, arg, pass, info)
  of "fieldchecks": processOnOffSwitch(conf, {optFieldCheck}, arg, pass, info)
  of "rangechecks": processOnOffSwitch(conf, {optRangeCheck}, arg, pass, info)
  of "boundchecks": processOnOffSwitch(conf, {optBoundsCheck}, arg, pass, info)
  of "refchecks":
    warningDeprecated(conf, info, "refchecks is deprecated!")
    processOnOffSwitch(conf, {optRefCheck}, arg, pass, info)
  of "overflowchecks": processOnOffSwitch(conf, {optOverflowCheck}, arg, pass, info)
  of "staticboundchecks": processOnOffSwitch(conf, {optStaticBoundsCheck}, arg, pass, info)
  of "stylechecks": processOnOffSwitch(conf, {optStyleCheck}, arg, pass, info)
  of "linedir": processOnOffSwitch(conf, {optLineDir}, arg, pass, info)
  of "assertions", "a": processOnOffSwitch(conf, {optAssert}, arg, pass, info)
  of "threads":
    if conf.backend == backendJs or conf.cmd == cmdNimscript: discard
    else: processOnOffSwitchG(conf, {optThreads}, arg, pass, info)
    #if optThreads in conf.globalOptions: conf.setNote(warnGcUnsafe)
  of "tlsemulation":
    processOnOffSwitchG(conf, {optTlsEmulation}, arg, pass, info)
    if optTlsEmulation in conf.globalOptions:
      conf.legacyFeatures.incl emitGenerics
  of "implicitstatic":
    processOnOffSwitch(conf, {optImplicitStatic}, arg, pass, info)
  of "patterns", "trmacros":
    if switch.normalize == "patterns": deprecatedAlias(switch, "trmacros")
    processOnOffSwitch(conf, {optTrMacros}, arg, pass, info)
  of "opt":
    expectArg(conf, switch, arg, pass, info)
    case arg.normalize
    of "speed":
      incl(conf.options, optOptimizeSpeed)
      excl(conf.options, optOptimizeSize)
    of "size":
      excl(conf.options, optOptimizeSpeed)
      incl(conf.options, optOptimizeSize)
    of "none":
      excl(conf.options, optOptimizeSpeed)
      excl(conf.options, optOptimizeSize)
    else: localError(conf, info, errNoneSpeedOrSizeExpectedButXFound % arg)
  of "app":
    expectArg(conf, switch, arg, pass, info)
    case arg.normalize
    of "gui":
      incl(conf.globalOptions, optGenGuiApp)
      defineSymbol(conf.symbols, "executable")
      defineSymbol(conf.symbols, "guiapp")
    of "console":
      excl(conf.globalOptions, optGenGuiApp)
      defineSymbol(conf.symbols, "executable")
      defineSymbol(conf.symbols, "consoleapp")
    of "lib":
      incl(conf.globalOptions, optGenDynLib)
      excl(conf.globalOptions, optGenGuiApp)
      defineSymbol(conf.symbols, "library")
      defineSymbol(conf.symbols, "dll")
    of "staticlib":
      incl(conf.globalOptions, optGenStaticLib)
      incl(conf.globalOptions, optNoMain)
      excl(conf.globalOptions, optGenGuiApp)
      defineSymbol(conf.symbols, "library")
      defineSymbol(conf.symbols, "staticlib")
    else: localError(conf, info, errGuiConsoleOrLibExpectedButXFound % arg)
  of "passc", "t":
    expectArg(conf, switch, arg, pass, info)
    if pass in {passCmd2, passPP}: extccomp.addCompileOptionCmd(conf, arg)
  of "passl", "l":
    expectArg(conf, switch, arg, pass, info)
    if pass in {passCmd2, passPP}: extccomp.addLinkOptionCmd(conf, arg)
  of "cincludes":
    expectArg(conf, switch, arg, pass, info)
    if pass in {passCmd2, passPP}: conf.cIncludes.add processPath(conf, arg, info)
  of "clibdir":
    expectArg(conf, switch, arg, pass, info)
    if pass in {passCmd2, passPP}: conf.cLibs.add processPath(conf, arg, info)
  of "clib":
    expectArg(conf, switch, arg, pass, info)
    if pass in {passCmd2, passPP}:
      conf.cLinkedLibs.add arg
  of "header":
    if conf != nil: conf.headerFile = arg
    incl(conf.globalOptions, optGenIndex)
  of "nimbasepattern":
    if conf != nil: conf.nimbasePattern = arg
  of "index":
    case arg.normalize
    of "", "on": conf.globalOptions.incl {optGenIndex}
    of "only": conf.globalOptions.incl {optGenIndexOnly, optGenIndex}
    of "off": conf.globalOptions.excl {optGenIndex, optGenIndexOnly}
    else: localError(conf, info, errOnOrOffExpectedButXFound % arg)
  of "noimportdoc":
    processOnOffSwitchG(conf, {optNoImportdoc}, arg, pass, info)
  of "import":
    expectArg(conf, switch, arg, pass, info)
    if pass in {passCmd2, passPP}:
      conf.implicitImports.add findModule(conf, arg, toFullPath(conf, info)).string
  of "include":
    expectArg(conf, switch, arg, pass, info)
    if pass in {passCmd2, passPP}:
      conf.implicitIncludes.add findModule(conf, arg, toFullPath(conf, info)).string
  of "listcmd":
    processOnOffSwitchG(conf, {optListCmd}, arg, pass, info)
  of "asm":
    processOnOffSwitchG(conf, {optProduceAsm}, arg, pass, info)
  of "genmapping":
    processOnOffSwitchG(conf, {optGenMapping}, arg, pass, info)
  of "os":
    expectArg(conf, switch, arg, pass, info)
    let theOS = platform.nameToOS(arg)
    if theOS == osNone:
      let osList = platform.listOSnames().join(", ")
      localError(conf, info, "unknown OS: '$1'. Available options are: $2" % [arg, $osList])
    else:
      setTarget(conf.target, theOS, conf.target.targetCPU)
  of "cpu":
    expectArg(conf, switch, arg, pass, info)
    let cpu = platform.nameToCPU(arg)
    if cpu == cpuNone:
      let cpuList = platform.listCPUnames().join(", ")
      localError(conf, info, "unknown CPU: '$1'. Available options are: $2" % [ arg, cpuList])
    else:
      setTarget(conf.target, conf.target.targetOS, cpu)
  of "run", "r":
    processOnOffSwitchG(conf, {optRun}, arg, pass, info)
    if conf.backend == backendJs:
      # for now, -r uses nodejs, so define nodejs
      defineSymbol(conf.symbols, "nodejs")
  of "maxloopiterationsvm":
    expectArg(conf, switch, arg, pass, info)
    var value: int = 10_000_000
    discard parseSaturatedNatural(arg, value)
    if not value > 0: localError(conf, info, "maxLoopIterationsVM must be a positive integer greater than zero")
    conf.maxLoopIterationsVM = value
  of "maxcalldepthvm":
    expectArg(conf, switch, arg, pass, info)
    var value: int = 2_000
    discard parseSaturatedNatural(arg, value)
    if value <= 0: localError(conf, info, "maxCallDepthVM must be a positive integer greater than zero")
    conf.maxCallDepthVM = value
  of "errormax":
    expectArg(conf, switch, arg, pass, info)
    # Note: `nim check` (etc) can overwrite this.
    # `0` is meaningless, give it a useful meaning as in clang's -ferror-limit
    # If user doesn't set this flag and the code doesn't either, it'd
    # have the same effect as errorMax = 1
    var value: int = 0
    discard parseSaturatedNatural(arg, value)
    conf.errorMax = if value == 0: high(int) else: value
  of "verbosity":
    expectArg(conf, switch, arg, pass, info)
    let verbosity = parseInt(arg)
    if verbosity notin 0..3:
      localError(conf, info, "invalid verbosity level: '$1'" % arg)
    conf.verbosity = verbosity
    var verb = NotesVerbosity[conf.verbosity]
    ## We override the default `verb` by explicitly modified (set/unset) notes.
    conf.notes = (conf.modifiedyNotes * conf.notes + verb) -
      (conf.modifiedyNotes * verb - conf.notes)
    conf.mainPackageNotes = conf.notes
  of "parallelbuild":
    expectArg(conf, switch, arg, pass, info)
    var value: int = 0
    discard parseSaturatedNatural(arg, value)
    conf.numberOfProcessors = value
  of "version", "v":
    expectNoArg(conf, switch, arg, pass, info)
    writeVersionInfo(conf, pass)
  of "advanced":
    expectNoArg(conf, switch, arg, pass, info)
    writeAdvancedUsage(conf, pass)
  of "fullhelp":
    expectNoArg(conf, switch, arg, pass, info)
    writeFullhelp(conf, pass)
  of "help", "h":
    expectNoArg(conf, switch, arg, pass, info)
    helpOnError(conf, pass)
  of "symbolfiles", "incremental", "ic":
    if switch.normalize == "symbolfiles": deprecatedAlias(switch, "incremental")
      # xxx maybe also ic, since not in help?
    if pass in {passCmd2, passPP}:
      case arg.normalize
      of "on": conf.symbolFiles = v2Sf
      of "off": conf.symbolFiles = disabledSf
      of "writeonly": conf.symbolFiles = writeOnlySf
      of "readonly": conf.symbolFiles = readOnlySf
      of "v2": conf.symbolFiles = v2Sf
      of "stress": conf.symbolFiles = stressTest
      else: localError(conf, info, "invalid option for --incremental: " & arg)
    setUseIc(conf.symbolFiles != disabledSf)
  of "skipcfg":
    processOnOffSwitchG(conf, {optSkipSystemConfigFile}, arg, pass, info)
  of "skipprojcfg":
    processOnOffSwitchG(conf, {optSkipProjConfigFile}, arg, pass, info)
  of "skipusercfg":
    processOnOffSwitchG(conf, {optSkipUserConfigFile}, arg, pass, info)
  of "skipparentcfg":
    processOnOffSwitchG(conf, {optSkipParentConfigFiles}, arg, pass, info)
  of "genscript", "gendeps":
    if switch.normalize == "gendeps": deprecatedAlias(switch, "genscript")
    processOnOffSwitchG(conf, {optGenScript}, arg, pass, info)
    processOnOffSwitchG(conf, {optCompileOnly}, arg, pass, info)
  of "gencdeps":
    processOnOffSwitchG(conf, {optGenCDeps}, arg, pass, info)
  of "colors": processOnOffSwitchG(conf, {optUseColors}, arg, pass, info)
  of "lib":
    expectArg(conf, switch, arg, pass, info)
    conf.libpath = processPath(conf, arg, info, notRelativeToProj=true)
  of "putenv":
    expectArg(conf, switch, arg, pass, info)
    splitSwitch(conf, arg, key, val, pass, info)
    os.putEnv(key, val)
  of "cc":
    if conf.backend != backendJs: # bug #19330
      expectArg(conf, switch, arg, pass, info)
      setCC(conf, arg, info)
  of "track":
    expectArg(conf, switch, arg, pass, info)
    track(conf, arg, info)
  of "trackdirty":
    expectArg(conf, switch, arg, pass, info)
    trackDirty(conf, arg, info)
  of "suggest":
    expectNoArg(conf, switch, arg, pass, info)
    conf.ideCmd = ideSug
  of "def":
    expectArg(conf, switch, arg, pass, info)
    trackIde(conf, ideDef, arg, info)
  of "context":
    expectNoArg(conf, switch, arg, pass, info)
    conf.ideCmd = ideCon
  of "usages":
    expectArg(conf, switch, arg, pass, info)
    trackIde(conf, ideUse, arg, info)
  of "defusages":
    expectArg(conf, switch, arg, pass, info)
    trackIde(conf, ideDus, arg, info)
  of "stdout":
    processOnOffSwitchG(conf, {optStdout}, arg, pass, info)
  of "filenames":
    case arg.normalize
    of "abs": conf.filenameOption = foAbs
    of "canonical": conf.filenameOption = foCanonical
    of "legacyrelproj": conf.filenameOption = foLegacyRelProj
    else: localError(conf, info, "expected: abs|canonical|legacyRelProj, got: $1" % arg)
  of "processing":
    incl(conf.notes, hintProcessing)
    incl(conf.mainPackageNotes, hintProcessing)
    case arg.normalize
    of "dots": conf.hintProcessingDots = true
    of "filenames": conf.hintProcessingDots = false
    of "off":
      excl(conf.notes, hintProcessing)
      excl(conf.mainPackageNotes, hintProcessing)
    else: localError(conf, info, "expected: dots|filenames|off, got: $1" % arg)
  of "unitsep":
    conf.unitSep = if switchOn(arg): "\31" else: ""
  of "listfullpaths":
    # xxx in future work, use `warningDeprecated`
    conf.filenameOption = if switchOn(arg): foAbs else: foCanonical
  of "spellsuggest":
    if arg.len == 0: conf.spellSuggestMax = spellSuggestSecretSauce
    elif arg == "auto": conf.spellSuggestMax = spellSuggestSecretSauce
    else: conf.spellSuggestMax = parseInt(arg)
  of "declaredlocs":
    processOnOffSwitchG(conf, {optDeclaredLocs}, arg, pass, info)
  of "dynliboverride":
    dynlibOverride(conf, switch, arg, pass, info)
  of "dynliboverrideall":
    processOnOffSwitchG(conf, {optDynlibOverrideAll}, arg, pass, info)
  of "experimental":
    if arg.len == 0:
      conf.features.incl oldExperimentalFeatures
    else:
      try:
        conf.features.incl parseEnum[Feature](arg)
      except ValueError:
        localError(conf, info, "unknown experimental feature")
  of "legacy":
    try:
      conf.legacyFeatures.incl parseEnum[LegacyFeature](arg)
    except ValueError:
      localError(conf, info, "unknown obsolete feature")
  of "nocppexceptions":
    expectNoArg(conf, switch, arg, pass, info)
    conf.exc = low(ExceptionSystem)
    defineSymbol(conf.symbols, "noCppExceptions")
  of "shownonexports":
    expectNoArg(conf, switch, arg, pass, info)
    showNonExportedFields(conf)
  of "exceptions":
    case arg.normalize
    of "cpp": conf.exc = excCpp
    of "setjmp": conf.exc = excSetjmp
    of "quirky": conf.exc = excQuirky
    of "goto": conf.exc = excGoto
    else: localError(conf, info, errInvalidExceptionSystem % arg)
  of "cppdefine":
    expectArg(conf, switch, arg, pass, info)
    if conf != nil:
      conf.cppDefine(arg)
  of "newruntime":
    warningDeprecated(conf, info, "newruntime is deprecated, use arc/orc instead!")
    expectNoArg(conf, switch, arg, pass, info)
    if pass in {passCmd2, passPP}:
      doAssert(conf != nil)
      incl(conf.features, destructor)
      incl(conf.globalOptions, optTinyRtti)
      incl(conf.globalOptions, optOwnedRefs)
      incl(conf.globalOptions, optSeqDestructors)
      defineSymbol(conf.symbols, "nimV2")
      conf.selectedGC = gcHooks
      defineSymbol(conf.symbols, "gchooks")
      defineSymbol(conf.symbols, "nimSeqsV2")
      defineSymbol(conf.symbols, "nimOwnedEnabled")
  of "seqsv2":
    processOnOffSwitchG(conf, {optSeqDestructors}, arg, pass, info)
    if pass in {passCmd2, passPP}:
      defineSymbol(conf.symbols, "nimSeqsV2")
  of "stylecheck":
    case arg.normalize
    of "off": conf.globalOptions = conf.globalOptions - {optStyleHint, optStyleError}
    of "hint": conf.globalOptions = conf.globalOptions + {optStyleHint} - {optStyleError}
    of "error": conf.globalOptions = conf.globalOptions + {optStyleError}
    of "usages": conf.globalOptions.incl optStyleUsages
    else: localError(conf, info, errOffHintsError % arg)
  of "showallmismatches":
    processOnOffSwitchG(conf, {optShowAllMismatches}, arg, pass, info)
  of "cppcompiletonamespace":
    if arg.len > 0:
      conf.cppCustomNamespace = arg
    else:
      conf.cppCustomNamespace = "Nim"
    defineSymbol(conf.symbols, "cppCompileToNamespace", conf.cppCustomNamespace)
  of "docinternal":
    processOnOffSwitchG(conf, {optDocInternal}, arg, pass, info)
  of "multimethods":
    processOnOffSwitchG(conf, {optMultiMethods}, arg, pass, info)
  of "expandmacro":
    expectArg(conf, switch, arg, pass, info)
    conf.macrosToExpand[arg] = "T"
  of "expandarc":
    expectArg(conf, switch, arg, pass, info)
    conf.arcToExpand[arg] = "T"
  of "benchmarkvm":
    processOnOffSwitchG(conf, {optBenchmarkVM}, arg, pass, info)
  of "profilevm":
    processOnOffSwitchG(conf, {optProfileVM}, arg, pass, info)
  of "sinkinference":
    processOnOffSwitch(conf, {optSinkInference}, arg, pass, info)
  of "cursorinference":
    # undocumented, for debugging purposes only:
    processOnOffSwitch(conf, {optCursorInference}, arg, pass, info)
  of "panics":
    processOnOffSwitchG(conf, {optPanics}, arg, pass, info)
    if optPanics in conf.globalOptions:
      defineSymbol(conf.symbols, "nimPanics")
  of "jsbigint64":
    processOnOffSwitchG(conf, {optJsBigInt64}, arg, pass, info)
  of "sourcemap": # xxx document in --fullhelp
    conf.globalOptions.incl optSourcemap
    conf.options.incl optLineDir
  of "deepcopy":
    processOnOffSwitchG(conf, {optEnableDeepCopy}, arg, pass, info)
  of "": # comes from "-" in for example: `nim c -r -` (gets stripped from -)
    handleStdinInput(conf)
  of "nilseqs", "nilchecks", "symbol", "taintmode", "cs", "deadcodeelim": warningOptionNoop(switch)
  of "nimmainprefix": conf.nimMainPrefix = arg
  else:
    if strutils.find(switch, '.') >= 0: options.setConfigVar(conf, switch, arg)
    else: invalidCmdLineOption(conf, pass, switch, info)

proc processCommand*(switch: string, pass: TCmdLinePass; config: ConfigRef) =
  var cmd = ""
  var arg = ""
  splitSwitch(config, switch, cmd, arg, pass, gCmdLineInfo)
  processSwitch(cmd, arg, pass, gCmdLineInfo, config)

proc processSwitch*(pass: TCmdLinePass; p: OptParser; config: ConfigRef) =
  # hint[X]:off is parsed as (p.key = "hint[X]", p.val = "off")
  # we transform it to (key = hint, val = [X]:off)
  var bracketLe = strutils.find(p.key, '[')
  if bracketLe >= 0:
    var key = substr(p.key, 0, bracketLe - 1)
    var val = substr(p.key, bracketLe) & ':' & p.val
    processSwitch(key, val, pass, gCmdLineInfo, config)
  else:
    processSwitch(p.key, p.val, pass, gCmdLineInfo, config)

proc processArgument*(pass: TCmdLinePass; p: OptParser;
                      argsCount: var int; config: ConfigRef): bool =
  if argsCount == 0 and config.implicitCmd:
    argsCount.inc
  if argsCount == 0:
    # nim filename.nims  is the same as "nim e filename.nims":
    if p.key.endsWith(".nims"):
      config.setCmd cmdNimscript
      incl(config.globalOptions, optWasNimscript)
      config.projectName = unixToNativePath(p.key)
      config.arguments = cmdLineRest(p)
      result = true
    elif pass != passCmd2:
      setCommandEarly(config, p.key)
      result = false
    else: result = false
  else:
    if pass == passCmd1: config.commandArgs.add p.key
    if argsCount == 1:
      if p.key.endsWith(".nims"):
        incl(config.globalOptions, optWasNimscript)
      # support UNIX style filenames everywhere for portable build scripts:
      if config.projectName.len == 0:
        config.projectName = unixToNativePath(p.key)
      config.arguments = cmdLineRest(p)
      result = true
    else:
      result = false
  inc argsCount

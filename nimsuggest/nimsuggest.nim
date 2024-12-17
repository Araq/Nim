#
#
#           The Nim Compiler
#        (c) Copyright 2017 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import compiler/renderer
import compiler/types
import compiler/trees
import compiler/wordrecg
import compiler/sempass2
import strformat
import algorithm
import tables
import times
import procmonitor

template tryImport(module) = import module

when compiles tryImport ../dist/checksums/src/checksums/sha1:
  import ../dist/checksums/src/checksums/sha1
else:
  import checksums/sha1

## Nimsuggest is a tool that helps to give editors IDE like capabilities.

when not defined(nimcore):
  {.error: "nimcore MUST be defined for Nim's core tooling".}

import strutils, os, parseopt, parseutils, sequtils, net, rdstdin, sexp
# Do NOT import suggest. It will lead to weird bugs with
# suggestionResultHook, because suggest.nim is included by sigmatch.
# So we import that one instead.
import compiler / [options, commands, modules,
  passes, passaux, msgs,
  sigmatch, ast,
  idents, modulegraphs, prefixmatches, lineinfos, cmdlinehelper,
  pathutils, condsyms, syntaxes, suggestsymdb]

when defined(nimPreviewSlimSystem):
  import std/typedthreads

when defined(windows):
  import winlean
else:
  import posix

const HighestSuggestProtocolVersion = 4
const DummyEof = "!EOF!"
const Usage = """
Nimsuggest - Tool to give every editor IDE like capabilities for Nim
Usage:
  nimsuggest [options] projectfile.nim

Options:
  --autobind              automatically binds into a free port
  --port:PORT             port, by default 6000
  --address:HOST          binds to that address, by default ""
  --stdin                 read commands from stdin and write results to
                          stdout instead of using sockets
  --clientProcessId:PID   shutdown nimsuggest in case this process dies
  --epc                   use emacs epc mode
  --debug                 enable debug output
  --log                   enable verbose logging to nimsuggest.log file
  --v1                    use version 1 of the protocol; for backwards compatibility
  --v2                    use version 2(default) of the protocol
  --v3                    use version 3 of the protocol
  --v4                    use version 4 of the protocol
  --info:X                information
    --info:nimVer           return the Nim compiler version that nimsuggest uses internally
    --info:protocolVer      return the newest protocol version that is supported
    --info:capabilities     return the capabilities supported by nimsuggest
  --refresh               perform automatic refreshes to keep the analysis precise
  --maxresults:N          limit the number of suggestions to N
  --tester                implies --stdin and outputs a line
                          '""" & DummyEof & """' for the tester
  --find                  attempts to find the project file of the current project
  --exceptionInlayHints:on|off
                          globally turn exception inlay hints on|off

The server then listens to the connection and takes line-based commands.

If --autobind is used, the binded port number will be printed to stdout.

In addition, all command line options of Nim that do not affect code generation
are supported.
"""
type
  Mode = enum mstdin, mtcp, mepc, mcmdsug, mcmdcon
  CachedMsg = object
    info: TLineInfo
    msg: string
    sev: Severity
  CachedMsgs = seq[CachedMsg]

var
  gPort = 6000.Port
  gAddress = "127.0.0.1"
  gMode: Mode
  gEmitEof: bool # whether we write '!EOF!' dummy lines
  gLogging = defined(logging)
  gRefresh: bool
  gAutoBind = false

  requests: Channel[string]
  results: Channel[Suggest]

proc executeNoHooksV3(cmd: IdeCmd, file: AbsoluteFile, dirtyfile: AbsoluteFile, line, col: int; tag: string,
  graph: ModuleGraph);

proc writelnToChannel(line: string) =
  results.send(Suggest(section: ideMsg, doc: line))

proc sugResultHook(s: Suggest) =
  results.send(s)

proc errorHook(conf: ConfigRef; info: TLineInfo; msg: string; sev: Severity) =
  results.send(Suggest(section: ideChk, filePath: toFullPath(conf, info),
    line: toLinenumber(info), column: toColumn(info), doc: msg,
    forth: $sev))

proc myLog(s: string) =
  if gLogging: log(s)

const
  seps = {':', ';', ' ', '\t'}
  Help = "usage: sug|con|def|use|dus|chk|mod|highlight|outline|known|project file.nim[;dirtyfile.nim]:line:col\n" &
         "type 'quit' to quit\n" &
         "type 'debug' to toggle debug mode on/off\n" &
         "type 'terse' to toggle terse mode on/off"
  #List of currently supported capabilities. So lang servers/ides can iterate over and check for what's enabled
  Capabilities = [
    "con", #current NimSuggest supports the `con` commmand
    "exceptionInlayHints",
    "unknownFile", #current NimSuggest can handle unknown files
  ]

proc parseQuoted(cmd: string; outp: var string; start: int): int =
  var i = start
  i += skipWhitespace(cmd, i)
  if i < cmd.len and cmd[i] == '"':
    i += parseUntil(cmd, outp, '"', i+1)+2
  else:
    i += parseUntil(cmd, outp, seps, i)
  result = i

proc sexp(s: IdeCmd|TSymKind|PrefixMatch): SexpNode = sexp($s)

proc sexp(s: Suggest): SexpNode =
  # If you change the order here, make sure to change it over in
  # nim-mode.el too.
  let qp = if s.qualifiedPath.len == 0: @[] else: s.qualifiedPath
  result = convertSexp([
    s.section,
    TSymKind s.symkind,
    qp.map(newSString),
    s.filePath,
    s.forth,
    s.line,
    s.column,
    s.doc,
    s.quality
  ])
  if s.section == ideSug:
    result.add convertSexp(s.prefix)
  if s.section in {ideOutline, ideExpand} and s.version == 3:
    result.add convertSexp(s.endLine.int)
    result.add convertSexp(s.endCol)

proc sexp(s: seq[Suggest]): SexpNode =
  result = newSList()
  for sug in s:
    result.add(sexp(sug))

proc listEpc(): SexpNode =
  # This function is called from Emacs to show available options.
  let
    argspecs = sexp("file line column dirtyfile".split(" ").map(newSSymbol))
    docstring = sexp("line starts at 1, column at 0, dirtyfile is optional")
  result = newSList()
  for command in ["sug", "con", "def", "use", "dus", "chk", "mod", "globalSymbols", "recompile", "saved", "chkFile", "declaration", "inlayHints"]:
    let
      cmd = sexp(command)
      methodDesc = newSList()
    methodDesc.add(cmd)
    methodDesc.add(argspecs)
    methodDesc.add(docstring)
    result.add(methodDesc)

proc findNode(n: PNode; trackPos: TLineInfo): PSym =
  #echo "checking node ", n.info
  result = nil
  if n.kind == nkSym:
    if isTracked(n.info, trackPos, n.sym.name.s.len): return n.sym
  else:
    for i in 0 ..< safeLen(n):
      let res = findNode(n[i], trackPos)
      if res != nil: return res

proc symFromInfo(graph: ModuleGraph; trackPos: TLineInfo): PSym =
  let m = graph.getModule(trackPos.fileIndex)
  if m != nil and m.ast != nil:
    result = findNode(m.ast, trackPos)
  else:
    result = nil

template benchmark(benchmarkName: untyped, code: untyped) =
  block:
    myLog "Started [" & benchmarkName & "]..."
    let t0 = epochTime()
    code
    let elapsed = epochTime() - t0
    let elapsedStr = elapsed.formatFloat(format = ffDecimal, precision = 3)
    myLog "CPU Time [" & benchmarkName & "] " & elapsedStr & "s"

proc clearInstCache(graph: ModuleGraph, projectFileIdx: FileIndex) =
  if projectFileIdx == InvalidFileIdx:
    graph.typeInstCache.clear()
    graph.procInstCache.clear()
    return
  var typeIdsToDelete = newSeq[ItemId]()
  for id in graph.typeInstCache.keys:
    if id.module == projectFileIdx.int:
      typeIdsToDelete.add id
  for id in typeIdsToDelete:
    graph.typeInstCache.del id
  var procIdsToDelete = newSeq[ItemId]()
  for id in graph.procInstCache.keys:
    if id.module == projectFileIdx.int:
      procIdsToDelete.add id
  for id in procIdsToDelete:
    graph.procInstCache.del id

  for tbl in mitems(graph.attachedOps):
    var attachedOpsToDelete = newSeq[ItemId]()
    for id in tbl.keys:
      if id.module == projectFileIdx.int and sfOverridden in resolveAttachedOp(graph, tbl[id]).flags:
        attachedOpsToDelete.add id
    for id in attachedOpsToDelete:
      tbl.del id

proc executeNoHooks(cmd: IdeCmd, file, dirtyfile: AbsoluteFile, line, col: int, tag: string,
             graph: ModuleGraph) =
  let conf = graph.config

  if conf.suggestVersion >= 3:
    let command = fmt "cmd = {cmd} {file}:{line}:{col}"
    benchmark command:
      executeNoHooksV3(cmd, file, dirtyfile, line, col, tag, graph)
    return

  myLog("cmd: " & $cmd & ", file: " & file.string &
        ", dirtyFile: " & dirtyfile.string &
        "[" & $line & ":" & $col & "]")
  conf.ideCmd = cmd
  if cmd == ideUse and conf.suggestVersion != 0:
    graph.resetAllModules()
  var isKnownFile = true
  let dirtyIdx = fileInfoIdx(conf, file, isKnownFile)

  if not dirtyfile.isEmpty: msgs.setDirtyFile(conf, dirtyIdx, dirtyfile)
  else: msgs.setDirtyFile(conf, dirtyIdx, AbsoluteFile"")

  conf.m.trackPos = newLineInfo(dirtyIdx, line, col)
  conf.m.trackPosAttached = false
  conf.errorCounter = 0
  if conf.suggestVersion == 1:
    graph.usageSym = nil
  if not isKnownFile:
    graph.clearInstCache(dirtyIdx)
    graph.compileProject(dirtyIdx)
  if conf.suggestVersion == 0 and conf.ideCmd in {ideUse, ideDus} and
      dirtyfile.isEmpty:
    discard "no need to recompile anything"
  else:
    let modIdx = graph.parentModule(dirtyIdx)
    graph.markDirty dirtyIdx
    graph.markClientsDirty dirtyIdx
    if conf.ideCmd != ideMod:
      if isKnownFile:
        graph.clearInstCache(modIdx)
        graph.compileProject(modIdx)
  if conf.ideCmd in {ideUse, ideDus}:
    let u = if conf.suggestVersion != 1: graph.symFromInfo(conf.m.trackPos) else: graph.usageSym
    if u != nil:
      listUsages(graph, u)
    else:
      localError(conf, conf.m.trackPos, "found no symbol at this position " & (conf $ conf.m.trackPos))

proc executeNoHooks(cmd: IdeCmd, file, dirtyfile: AbsoluteFile, line, col: int, graph: ModuleGraph) =
  executeNoHooks(cmd, file, dirtyfile, line, col, "", graph)

proc execute(cmd: IdeCmd, file, dirtyfile: AbsoluteFile, line, col: int; tag: string,
             graph: ModuleGraph) =
  if cmd == ideChk:
    graph.config.structuredErrorHook = errorHook
    graph.config.writelnHook = myLog
  else:
    graph.config.structuredErrorHook = nil
    graph.config.writelnHook = myLog
  executeNoHooks(cmd, file, dirtyfile, line, col, tag, graph)

proc executeEpc(cmd: IdeCmd, args: SexpNode;
                graph: ModuleGraph) =
  let
    file = AbsoluteFile args[0].getStr
    line = args[1].getNum
    column = args[2].getNum
  var dirtyfile = AbsoluteFile""
  if len(args) > 3:
    dirtyfile = AbsoluteFile args[3].getStr("")
  execute(cmd, file, dirtyfile, int(line), int(column), args[3].getStr, graph)

proc returnEpc(socket: Socket, uid: BiggestInt, s: SexpNode|string,
               returnSymbol = "return") =
  let response = $convertSexp([newSSymbol(returnSymbol), uid, s])
  socket.send(toHex(len(response), 6))
  socket.send(response)

template checkSanity(client, sizeHex, size, messageBuffer: typed) =
  if client.recv(sizeHex, 6) != 6:
    raise newException(ValueError, "didn't get all the hexbytes")
  if parseHex(sizeHex, size) == 0:
    raise newException(ValueError, "invalid size hex: " & $sizeHex)
  if client.recv(messageBuffer, size) != size:
    raise newException(ValueError, "didn't get all the bytes")

proc toStdout() {.gcsafe.} =
  while true:
    let res = results.recv()
    case res.section
    of ideNone: break
    of ideMsg: echo res.doc
    of ideKnown: echo res.quality == 1
    of ideProject: echo res.filePath
    else: echo res

proc toSocket(stdoutSocket: Socket) {.gcsafe.} =
  while true:
    let res = results.recv()
    case res.section
    of ideNone: break
    of ideMsg: stdoutSocket.send(res.doc & "\c\L")
    of ideKnown: stdoutSocket.send($(res.quality == 1) & "\c\L")
    of ideProject: stdoutSocket.send(res.filePath & "\c\L")
    else: stdoutSocket.send($res & "\c\L")

proc toEpc(client: Socket; uid: BiggestInt) {.gcsafe.} =
  var list = newSList()
  while true:
    let res = results.recv()
    case res.section
    of ideNone: break
    of ideMsg:
      list.add sexp(res.doc)
    of ideKnown:
      list.add sexp(res.quality == 1)
    of ideProject:
      list.add sexp(res.filePath)
    else:
      list.add sexp(res)
  returnEpc(client, uid, list)

template setVerbosity(level: typed) =
  gVerbosity = level
  conf.notes = NotesVerbosity[gVerbosity]

proc connectToNextFreePort(server: Socket, host: string): Port =
  server.bindAddr(Port(0), host)
  let (_, port) = server.getLocalAddr
  result = port

type
  ThreadParams = tuple[port: Port; address: string]

proc replStdinSingleCmd(line: string) =
  requests.send line
  toStdout()
  echo ""
  flushFile(stdout)

proc replStdin(x: ThreadParams) {.thread.} =
  if gEmitEof:
    echo DummyEof
    while true:
      let line = readLine(stdin)
      requests.send line
      if line == "quit": break
      toStdout()
      echo DummyEof
      flushFile(stdout)
  else:
    echo Help
    var line = ""
    while readLineFromStdin("> ", line):
      replStdinSingleCmd(line)
    requests.send "quit"

proc replCmdline(x: ThreadParams) {.thread.} =
  replStdinSingleCmd(x.address)
  requests.send "quit"

proc replTcp(x: ThreadParams) {.thread.} =
  var server = newSocket()
  if gAutoBind:
    let port = server.connectToNextFreePort(x.address)
    server.listen()
    echo port
    stdout.flushFile()
  else:
    server.bindAddr(x.port, x.address)
    server.listen()
  var inp = ""
  var stdoutSocket: Socket = Socket()
  while true:
    accept(server, stdoutSocket)

    stdoutSocket.readLine(inp)
    requests.send inp
    toSocket(stdoutSocket)
    stdoutSocket.send("\c\L")
    stdoutSocket.close()

proc argsToStr(x: SexpNode): string =
  if x.kind != SList: return x.getStr
  doAssert x.kind == SList
  doAssert x.len >= 4
  let file = x[0].getStr
  let line = x[1].getNum
  let col = x[2].getNum
  let dirty = x[3].getStr
  result = x[0].getStr.escape
  if dirty.len > 0:
    result.add ';'
    result.add dirty.escape
  result.add ':'
  result.addInt line
  result.add ':'
  result.addInt col

proc replEpc(x: ThreadParams) {.thread.} =
  var server = newSocket()
  let port = connectToNextFreePort(server, "localhost")
  server.listen()
  echo port
  stdout.flushFile()

  var client: Socket = Socket()
  # Wait for connection
  accept(server, client)
  while true:
    var
      sizeHex = ""
      size = 0
      messageBuffer = ""
    checkSanity(client, sizeHex, size, messageBuffer)
    let
      message = parseSexp($messageBuffer)
      epcApi = message[0].getSymbol
    case epcApi
    of "call":
      let
        uid = message[1].getNum
        cmd = message[2].getSymbol
        args = message[3]

      when false:
        x.ideCmd[] = parseIdeCmd(message[2].getSymbol)
        case x.ideCmd[]
        of ideSug, ideCon, ideDef, ideUse, ideDus, ideOutline, ideHighlight:
          setVerbosity(0)
        else: discard
      let fullCmd = cmd & " " & args.argsToStr
      myLog "MSG CMD: " & fullCmd
      requests.send(fullCmd)
      toEpc(client, uid)
    of "methods":
      returnEpc(client, message[1].getNum, listEpc())
    of "epc-error":
      # an unhandled exception forces down the whole process anyway, so we
      # use 'quit' here instead of 'raise'
      quit("received epc error: " & $messageBuffer)
    else:
      let errMessage = case epcApi
                       of "return", "return-error":
                         "no return expected"
                       else:
                         "unexpected call: " & epcApi
      quit errMessage

proc execCmd(cmd: string; graph: ModuleGraph; cachedMsgs: CachedMsgs) =
  let conf = graph.config

  template sentinel() =
    # send sentinel for the input reading thread:
    results.send(Suggest(section: ideNone))

  template toggle(sw) =
    if sw in conf.globalOptions:
      excl(conf.globalOptions, sw)
    else:
      incl(conf.globalOptions, sw)
    sentinel()
    return

  template err() =
    echo Help
    sentinel()
    return

  var opc = ""
  var i = parseIdent(cmd, opc, 0)
  case opc.normalize
  of "sug": conf.ideCmd = ideSug
  of "con": conf.ideCmd = ideCon
  of "def": conf.ideCmd = ideDef
  of "use": conf.ideCmd = ideUse
  of "dus": conf.ideCmd = ideDus
  of "mod": conf.ideCmd = ideMod
  of "chk": conf.ideCmd = ideChk
  of "highlight": conf.ideCmd = ideHighlight
  of "outline": conf.ideCmd = ideOutline
  of "quit":
    sentinel()
    quit()
  of "debug": toggle optIdeDebug
  of "terse": toggle optIdeTerse
  of "known": conf.ideCmd = ideKnown
  of "project": conf.ideCmd = ideProject
  of "changed": conf.ideCmd = ideChanged
  of "globalsymbols": conf.ideCmd = ideGlobalSymbols
  of "declaration": conf.ideCmd = ideDeclaration
  of "expand": conf.ideCmd = ideExpand
  of "chkfile": conf.ideCmd = ideChkFile
  of "recompile": conf.ideCmd = ideRecompile
  of "type": conf.ideCmd = ideType
  of "inlayhints":
    if conf.suggestVersion >= 4:
      conf.ideCmd = ideInlayHints
    else:
      err()
  else: err()
  var dirtyfile = ""
  var orig = ""
  i += skipWhitespace(cmd, i)
  if i < cmd.len and cmd[i] in {'0'..'9'}:
    orig = string conf.projectFull
  else:
    i = parseQuoted(cmd, orig, i)
    if i < cmd.len and cmd[i] == ';':
      i = parseQuoted(cmd, dirtyfile, i+1)
    i += skipWhile(cmd, seps, i)
  var line = 0
  var col = -1
  i += parseInt(cmd, line, i)
  i += skipWhile(cmd, seps, i)
  i += parseInt(cmd, col, i)
  let tag = substr(cmd, i)

  if conf.ideCmd == ideKnown:
    results.send(Suggest(section: ideKnown, quality: ord(fileInfoKnown(conf, AbsoluteFile orig))))
  elif conf.ideCmd == ideProject:
    results.send(Suggest(section: ideProject, filePath: string conf.projectFull))
  else:
    if conf.ideCmd == ideChk:
      for cm in cachedMsgs: errorHook(conf, cm.info, cm.msg, cm.sev)
    execute(conf.ideCmd, AbsoluteFile orig, AbsoluteFile dirtyfile, line, col, tag, graph)
  sentinel()

proc recompileFullProject(graph: ModuleGraph) =
  benchmark "Recompilation(clean)":
    graph.resetForBackend()
    graph.resetSystemArtifacts()
    graph.vm = nil
    graph.resetAllModules()
    GC_fullCollect()
    graph.compileProject()

proc mainThread(graph: ModuleGraph) =
  let conf = graph.config
  myLog "searchPaths: "
  for it in conf.searchPaths:
    myLog("  " & it.string)

  proc wrHook(line: string) {.closure.} =
    if gMode == mepc:
      if gLogging: log(line)
    else:
      writelnToChannel(line)

  conf.writelnHook = wrHook
  conf.suggestionResultHook = sugResultHook
  graph.doStopCompile = proc (): bool = requests.peek() > 0
  var idle = 0
  var cachedMsgs: CachedMsgs = @[]
  while true:
    let (hasData, req) = requests.tryRecv()
    if hasData:
      conf.writelnHook = wrHook
      conf.suggestionResultHook = sugResultHook
      execCmd(req, graph, cachedMsgs)
      idle = 0
    else:
      os.sleep 250
      idle += 1
    if idle == 20 and gRefresh and conf.suggestVersion < 3:
      # we use some nimsuggest activity to enable a lazy recompile:
      conf.ideCmd = ideChk
      conf.writelnHook = proc (s: string) = discard
      cachedMsgs.setLen 0
      conf.structuredErrorHook = proc (conf: ConfigRef; info: TLineInfo; msg: string; sev: Severity) =
        cachedMsgs.add(CachedMsg(info: info, msg: msg, sev: sev))
      conf.suggestionResultHook = proc (s: Suggest) = discard
      recompileFullProject(graph)

var
  inputThread: Thread[ThreadParams]

proc mainCommand(graph: ModuleGraph) =
  let conf = graph.config
  clearPasses(graph)
  registerPass graph, verbosePass
  registerPass graph, semPass
  conf.setCmd cmdIdeTools
  defineSymbol(conf.symbols, $conf.backend)
  wantMainModule(conf)

  if not fileExists(conf.projectFull):
    quit "cannot find file: " & conf.projectFull.string

  add(conf.searchPaths, conf.libpath)

  conf.setErrorMaxHighMaybe # honor --errorMax even if it may not make sense here
  # do not print errors, but log them
  conf.writelnHook = proc (msg: string) = discard

  if graph.config.suggestVersion >= 3:
    graph.config.structuredErrorHook = proc (conf: ConfigRef; info: TLineInfo; msg: string; sev: Severity) =
      let suggest = Suggest(section: ideChk, filePath: toFullPath(conf, info),
        line: toLinenumber(info), column: toColumn(info), doc: msg, forth: $sev)
      graph.suggestErrors.mgetOrPut(info.fileIndex, @[]).add suggest

  # compile the project before showing any input so that we already
  # can answer questions right away:
  benchmark "Initial compilation":
    compileProject(graph)

  open(requests)
  open(results)

  if graph.config.clientProcessId != 0:
    hookProcMonitor(graph.config.clientProcessId)

  case gMode
  of mstdin: createThread(inputThread, replStdin, (gPort, gAddress))
  of mtcp: createThread(inputThread, replTcp, (gPort, gAddress))
  of mepc: createThread(inputThread, replEpc, (gPort, gAddress))
  of mcmdsug: createThread(inputThread, replCmdline,
                            (gPort, "sug \"" & conf.projectFull.string & "\":" & gAddress))
  of mcmdcon: createThread(inputThread, replCmdline,
                            (gPort, "con \"" & conf.projectFull.string & "\":" & gAddress))
  mainThread(graph)
  joinThread(inputThread)
  close(requests)
  close(results)

proc processCmdLine*(pass: TCmdLinePass, cmd: string; conf: ConfigRef) =
  var p = parseopt.initOptParser(cmd)
  var findProject = false
  while true:
    parseopt.next(p)
    case p.kind
    of cmdEnd: break
    of cmdLongOption, cmdShortOption:
      case p.key.normalize
      of "help", "h":
        stdout.writeLine(Usage)
        quit()
      of "autobind":
        gMode = mtcp
        gAutoBind = true
      of "port":
        gPort = parseInt(p.val).Port
        gMode = mtcp
      of "address":
        gAddress = p.val
        gMode = mtcp
      of "stdin": gMode = mstdin
      of "cmdsug":
        gMode = mcmdsug
        gAddress = p.val
        incl(conf.globalOptions, optIdeDebug)
      of "cmdcon":
        gMode = mcmdcon
        gAddress = p.val
        incl(conf.globalOptions, optIdeDebug)
      of "epc":
        gMode = mepc
        conf.verbosity = 0          # Port number gotta be first.
      of "debug": incl(conf.globalOptions, optIdeDebug)
      of "v1": conf.suggestVersion = 1
      of "v2": conf.suggestVersion = 0
      of "v3": conf.suggestVersion = 3
      of "v4": conf.suggestVersion = 4
      of "info":
        case p.val.normalize
        of "protocolver":
          stdout.writeLine(HighestSuggestProtocolVersion)
          quit 0
        of "nimver":
          stdout.writeLine(system.NimVersion)
          quit 0
        of "capabilities":
          stdout.writeLine(Capabilities.toSeq.mapIt($it).join(" "))
          quit 0
        else:
          processSwitch(pass, p, conf)
      of "exceptioninlayhints":
        case p.val.normalize
        of "", "on": incl(conf.globalOptions, optIdeExceptionInlayHints)
        of "off": excl(conf.globalOptions, optIdeExceptionInlayHints)
        else: processSwitch(pass, p, conf)
      of "tester":
        gMode = mstdin
        gEmitEof = true
        gRefresh = false
      of "log": gLogging = true
      of "refresh":
        if p.val.len > 0:
          gRefresh = parseBool(p.val)
        else:
          gRefresh = true
      of "maxresults":
        conf.suggestMaxResults = parseInt(p.val)
      of "find":
        findProject = true
      of "clientprocessid":
        conf.clientProcessId = parseInt(p.val)
      else: processSwitch(pass, p, conf)
    of cmdArgument:
      let a = unixToNativePath(p.key)
      if dirExists(a) and not fileExists(a.addFileExt("nim")):
        conf.projectName = findProjectNimFile(conf, a)
        # don't make it worse, report the error the old way:
        if conf.projectName.len == 0: conf.projectName = a
      else:
        if findProject:
          conf.projectName = findProjectNimFile(conf, a.parentDir())
          if conf.projectName.len == 0:
            conf.projectName = a
        else:
          conf.projectName = a
      # if processArgument(pass, p, argsCount): break

proc handleCmdLine(cache: IdentCache; conf: ConfigRef) =
  let self = NimProg(
    suggestMode: true,
    processCmdLine: processCmdLine
  )
  self.initDefinesProg(conf, "nimsuggest")

  if paramCount() == 0:
    stdout.writeLine(Usage)
    return

  self.processCmdLineAndProjectPath(conf)

  if gMode != mstdin:
    conf.writelnHook = proc (msg: string) = discard
  conf.prefixDir = conf.getPrefixDir()
  #msgs.writelnHook = proc (line: string) = log(line)
  myLog("START " & conf.projectFull.string)

  var graph = newModuleGraph(cache, conf)
  if self.loadConfigsAndProcessCmdLine(cache, conf, graph):

    if conf.selectedGC == gcUnselected and
          conf.backend != backendJs:
      initOrcDefines(conf)
    mainCommand(graph)

# v3 start

proc recompilePartially(graph: ModuleGraph, projectFileIdx = InvalidFileIdx) =
  if projectFileIdx == InvalidFileIdx:
    myLog "Recompiling partially from root"
  else:
    myLog fmt "Recompiling partially starting from {graph.getModule(projectFileIdx)}"

  # inst caches are breaking incremental compilation when the cache caches stuff
  # from dirty buffer
  graph.clearInstCache(projectFileIdx)

  GC_fullCollect()

  try:
    benchmark "Recompilation":
      graph.compileProject(projectFileIdx)
  except Exception as e:
    myLog fmt "Failed to recompile partially with the following error:\n {e.msg} \n\n {e.getStackTrace()}"
    try:
      graph.recompileFullProject()
    except Exception as e:
      myLog fmt "Failed clean recompilation:\n {e.msg} \n\n {e.getStackTrace()}"

func deduplicateSymInfoPair[SymInfoPair](xs: seq[SymInfoPair]): seq[SymInfoPair] =
  # xs contains duplicate items and we want to filter them by range because the
  # sym may not match. This can happen when xs contains the same definition but
  # with different signature because suggestSym might be called multiple times
  # for the same symbol (e. g. including/excluding the pragma)
  result = newSeqOfCap[SymInfoPair](xs.len)
  for itm in xs.reversed:
    var found = false
    for res in result:
      if res.info.exactEquals(itm.info):
        found = true
        break
    if not found:
      result.add(itm)
  result.reverse()

func deduplicateSymInfoPair(xs: SuggestFileSymbolDatabase): SuggestFileSymbolDatabase =
  # xs contains duplicate items and we want to filter them by range because the
  # sym may not match. This can happen when xs contains the same definition but
  # with different signature because suggestSym might be called multiple times
  # for the same symbol (e. g. including/excluding the pragma)
  result = SuggestFileSymbolDatabase(
    lineInfo: newSeqOfCap[TinyLineInfo](xs.lineInfo.len),
    sym: newSeqOfCap[PSym](xs.sym.len),
    isDecl: newPackedBoolArray(),
    caughtExceptions: newSeqOfCap[seq[PType]](xs.caughtExceptions.len),
    caughtExceptionsSet: newPackedBoolArray(),
    fileIndex: xs.fileIndex,
    trackCaughtExceptions: xs.trackCaughtExceptions,
    isSorted: false
  )
  var i = xs.lineInfo.high
  while i >= 0:
    let itm = xs.lineInfo[i]
    var found = false
    for res in result.lineInfo:
      if res.exactEquals(itm):
        found = true
        break
    if not found:
      result.add(xs.getSymInfoPair(i))
    dec i
  result.reverse()

proc findSymData(graph: ModuleGraph, trackPos: TLineInfo):
    ref SymInfoPair =
  result = nil
  let db = graph.fileSymbols(trackPos.fileIndex).deduplicateSymInfoPair
  doAssert(db.fileIndex == trackPos.fileIndex)
  for i in db.lineInfo.low..db.lineInfo.high:
    if isTracked(db.lineInfo[i], TinyLineInfo(line: trackPos.line, col: trackPos.col), db.sym[i].name.s.len):
      var res = db.getSymInfoPair(i)
      new(result)
      result[] = res
      break

func isInRange*(current, startPos, endPos: TinyLineInfo, tokenLen: int): bool =
  result =
    (current.line > startPos.line or (current.line == startPos.line and current.col>=startPos.col)) and
    (current.line < endPos.line or (current.line == endPos.line and current.col <= endPos.col))

proc findSymDataInRange(graph: ModuleGraph, startPos, endPos: TLineInfo):
    seq[SymInfoPair] =
  result = newSeq[SymInfoPair]()
  let db = graph.fileSymbols(startPos.fileIndex).deduplicateSymInfoPair
  for i in db.lineInfo.low..db.lineInfo.high:
    if isInRange(db.lineInfo[i], TinyLineInfo(line: startPos.line, col: startPos.col), TinyLineInfo(line: endPos.line, col: endPos.col), db.sym[i].name.s.len):
      result.add(db.getSymInfoPair(i))

proc findSymData(graph: ModuleGraph, file: AbsoluteFile; line, col: int):
    ref SymInfoPair =
  let
    fileIdx = fileInfoIdx(graph.config, file)
    trackPos = newLineInfo(fileIdx, line, col)
  result = findSymData(graph, trackPos)

proc findSymDataInRange(graph: ModuleGraph, file: AbsoluteFile; startLine, startCol, endLine, endCol: int):
    seq[SymInfoPair] =
  let
    fileIdx = fileInfoIdx(graph.config, file)
    startPos = newLineInfo(fileIdx, startLine, startCol)
    endPos = newLineInfo(fileIdx, endLine, endCol)
  result = findSymDataInRange(graph, startPos, endPos)

proc markDirtyIfNeeded(graph: ModuleGraph, file: string, originalFileIdx: FileIndex) =
  let sha = $sha1.secureHashFile(file)
  if graph.config.m.fileInfos[originalFileIdx.int32].hash != sha or graph.config.ideCmd in {ideSug, ideCon}:
    myLog fmt "{file} changed compared to last compilation"
    graph.markDirty originalFileIdx
    graph.markClientsDirty originalFileIdx
  else:
    myLog fmt "No changes in file {file} compared to last compilation"

proc suggestResult(graph: ModuleGraph, sym: PSym, info: TLineInfo,
                   defaultSection = ideNone, endLine: uint16 = 0, endCol = 0) =
  let section = if defaultSection != ideNone:
                  defaultSection
                elif sym.info.exactEquals(info):
                  ideDef
                else:
                  ideUse
  let suggest = symToSuggest(graph, sym, isLocal=false, section,
                             info, 100, PrefixMatch.None, false, 0,
                             endLine = endLine, endCol = endCol)
  suggestResult(graph.config, suggest)

proc suggestInlayHintResultType(graph: ModuleGraph, sym: PSym, info: TLineInfo,
                   defaultSection = ideNone, endLine: uint16 = 0, endCol = 0) =
  let section = if defaultSection != ideNone:
                  defaultSection
                elif sym.info.exactEquals(info):
                  ideDef
                else:
                  ideUse
  var suggestDef = symToSuggest(graph, sym, isLocal=false, section,
                                info, 100, PrefixMatch.None, false, 0, true,
                                endLine = endLine, endCol = endCol)
  suggestDef.inlayHintInfo = suggestToSuggestInlayTypeHint(suggestDef)
  suggestDef.section = ideInlayHints
  if sym.kind == skForVar:
    suggestDef.inlayHintInfo.allowInsert = false
  suggestResult(graph.config, suggestDef)

proc suggestInlayHintResultException(graph: ModuleGraph, sym: PSym, info: TLineInfo,
                   defaultSection = ideNone, caughtExceptions: seq[PType], caughtExceptionsSet: bool, endLine: uint16 = 0, endCol = 0) =
  if not caughtExceptionsSet:
    return

  if sym.kind == skParam and sfEffectsDelayed in sym.flags:
    return

  var raisesList: seq[PType] = @[getEbase(graph, info)]

  let t = sym.typ
  if not isNil(t) and not isNil(t.n) and t.n.len > 0 and t.n[0].len > exceptionEffects:
    let effects = t.n[0]
    if effects.kind == nkEffectList and effects.len == effectListLen:
      let effs = effects[exceptionEffects]
      if not isNil(effs):
        raisesList = @[]
        for eff in items(effs):
          if not isNil(eff):
            raisesList.add(eff.typ)

  var propagatedExceptionList: seq[PType] = @[]
  for re in raisesList:
    var exceptionIsPropagated = true
    for ce in caughtExceptions:
      if isNil(ce) or safeInheritanceDiff(re, ce) <= 0:
        exceptionIsPropagated = false
        break
    if exceptionIsPropagated:
      propagatedExceptionList.add(re)

  if propagatedExceptionList.len == 0:
    return

  let section = if defaultSection != ideNone:
                  defaultSection
                elif sym.info.exactEquals(info):
                  ideDef
                else:
                  ideUse
  var suggestDef = symToSuggest(graph, sym, isLocal=false, section,
                                info, 100, PrefixMatch.None, false, 0, true,
                                endLine = endLine, endCol = endCol)
  suggestDef.inlayHintInfo = suggestToSuggestInlayExceptionHintLeft(suggestDef, propagatedExceptionList)
  suggestDef.section = ideInlayHints
  suggestResult(graph.config, suggestDef)
  suggestDef.inlayHintInfo = suggestToSuggestInlayExceptionHintRight(suggestDef, propagatedExceptionList)
  suggestResult(graph.config, suggestDef)

const
  # kinds for ideOutline and ideGlobalSymbols
  searchableSymKinds = {skField, skEnumField, skIterator, skMethod, skFunc, skProc, skConverter, skTemplate}

proc symbolEqual(left, right: PSym): bool =
  # More relaxed symbol comparison
  return left.info.exactEquals(right.info) and left.name == right.name

proc findDef(n: PNode, line: uint16, col: int16): PNode =
  result = nil
  if n.kind in {nkProcDef, nkIteratorDef, nkTemplateDef, nkMethodDef, nkMacroDef}:
    if n.info.line == line:
      return n
  else:
    for i in 0 ..< safeLen(n):
      let res = findDef(n[i], line, col)
      if res != nil: return res

proc findByTLineInfo(trackPos: TLineInfo, infoPairs: SuggestFileSymbolDatabase):
    ref SymInfoPair =
  result = nil
  if infoPairs.fileIndex == trackPos.fileIndex:
    for i in infoPairs.lineInfo.low..infoPairs.lineInfo.high:
      let s = infoPairs.getSymInfoPair(i)
      if s.info.exactEquals trackPos:
        new(result)
        result[] = s
        break

proc outlineNode(graph: ModuleGraph, n: PNode, endInfo: TLineInfo, infoPairs: SuggestFileSymbolDatabase): bool =
  result = false

  proc checkSymbol(sym: PSym, info: TLineInfo): bool =
    result = (sym.owner.kind in {skModule, skType} or sym.kind in {skProc, skMethod, skIterator, skTemplate, skType})

  if n.kind == nkSym and n.sym.checkSymbol(n.info):
    graph.suggestResult(n.sym, n.sym.info, ideOutline, endInfo.line, endInfo.col)
    return true
  elif n.kind == nkIdent:
    let symData = findByTLineInfo(n.info, infoPairs)
    if symData != nil and symData.sym.checkSymbol(symData.info):
       let sym = symData.sym
       graph.suggestResult(sym, sym.info, ideOutline, endInfo.line, endInfo.col)
       return true

proc handleIdentOrSym(graph: ModuleGraph, n: PNode, endInfo: TLineInfo, infoPairs: SuggestFileSymbolDatabase): bool =
  result = false
  for child in n:
    if child.kind in {nkIdent, nkSym}:
      if graph.outlineNode(child, endInfo, infoPairs):
        return true
    elif child.kind == nkPostfix:
      if graph.handleIdentOrSym(child, endInfo, infoPairs):
        return true

proc iterateOutlineNodes(graph: ModuleGraph, n: PNode, infoPairs: SuggestFileSymbolDatabase) =
  var matched = true
  if n.kind == nkIdent:
    let symData = findByTLineInfo(n.info, infoPairs)
    if symData != nil and symData.sym.kind == skEnumField and symData.info.exactEquals(symData.sym.info):
       let sym = symData.sym
       graph.suggestResult(sym, sym.info, ideOutline, n.endInfo.line, n.endInfo.col)
  elif (n.kind in {nkFuncDef, nkProcDef, nkTypeDef, nkMacroDef, nkTemplateDef, nkConverterDef, nkEnumFieldDef, nkConstDef}):
    matched = handleIdentOrSym(graph, n, n.endInfo, infoPairs)
  else:
    matched = false

  if n.kind != nkFormalParams:
    for child in n:
      graph.iterateOutlineNodes(child, infoPairs)

proc calculateExpandRange(n: PNode, info: TLineInfo): TLineInfo =
  if ((n.kind in {nkFuncDef, nkProcDef, nkIteratorDef, nkTemplateDef, nkMethodDef, nkConverterDef} and
          n.info.exactEquals(info)) or
         (n.kind in {nkCall, nkCommand} and n[0].info.exactEquals(info))):
    result = n.endInfo
  else:
    for child in n:
      result = child.calculateExpandRange(info)
      if result != unknownLineInfo:
        return result
    result = unknownLineInfo

proc executeNoHooksV3(cmd: IdeCmd, file: AbsoluteFile, dirtyfile: AbsoluteFile, line, col: int; tag: string,
    graph: ModuleGraph) =
  let conf = graph.config
  conf.writelnHook = proc (s: string) = discard
  conf.structuredErrorHook = proc (conf: ConfigRef; info: TLineInfo;
                                   msg: string; sev: Severity) =
    let suggest = Suggest(section: ideChk, filePath: toFullPath(conf, info),
      line: toLinenumber(info), column: toColumn(info), doc: msg, forth: $sev)
    graph.suggestErrors.mgetOrPut(info.fileIndex, @[]).add suggest

  conf.ideCmd = cmd

  myLog fmt "cmd: {cmd}, file: {file}[{line}:{col}], dirtyFile: {dirtyfile}, tag: {tag}"

  var fileIndex: FileIndex = default(FileIndex)

  if not (cmd in {ideRecompile, ideGlobalSymbols}):
    fileIndex = fileInfoIdx(conf, file)
    msgs.setDirtyFile(
      conf,
      fileIndex,
      if dirtyfile.isEmpty: AbsoluteFile"" else: dirtyfile)

    if not dirtyfile.isEmpty:
      graph.markDirtyIfNeeded(dirtyFile.string, fileInfoIdx(conf, file))

  # these commands require fully compiled project
  if cmd in {ideUse, ideDus, ideGlobalSymbols, ideChk, ideInlayHints} and graph.needsCompilation():
    graph.recompilePartially()
    # when doing incremental build for the project root we should make sure that
    # everything is unmarked as no longer beeing dirty in case there is no
    # longer reference to a particular module. E. g. A depends on B, B is marked
    # as dirty and A loses B import.
    graph.unmarkAllDirty()

  # these commands require partially compiled project
  elif cmd in {ideSug, ideCon, ideOutline, ideHighlight, ideDef, ideChkFile, ideType, ideDeclaration, ideExpand} and
       (graph.needsCompilation(fileIndex) or cmd in {ideSug, ideCon}):
    # for ideSug use v2 implementation
    if cmd in {ideSug, ideCon}:
      conf.m.trackPos = newLineInfo(fileIndex, line, col)
      conf.m.trackPosAttached = false
    else:
      conf.m.trackPos = default(TLineInfo)
      graph.recompilePartially(fileIndex)

  case cmd
  of ideDef:
    let s = graph.findSymData(file, line, col)
    if not s.isNil:
      graph.suggestResult(s.sym, s.sym.info)
  of ideType:
    let s = graph.findSymData(file, line, col)
    if not s.isNil:
      let typeSym = s.sym.typ.sym
      if typeSym != nil:
        graph.suggestResult(typeSym, typeSym.info, ideType)
      elif s.sym.typ.len != 0:
        let genericType = s.sym.typ[0].sym
        graph.suggestResult(genericType, genericType.info, ideType)
  of ideUse, ideDus:
    let symbol = graph.findSymData(file, line, col)
    if not symbol.isNil:
      var res: seq[SymInfoPair] = @[]
      for s in graph.suggestSymbolsIter:
        if s.sym.symbolEqual(symbol.sym):
          res.add(s)
      for s in res.deduplicateSymInfoPair():
        graph.suggestResult(s.sym, s.info)
  of ideHighlight:
    let sym = graph.findSymData(file, line, col)
    if not sym.isNil:
      let fs = graph.fileSymbols(fileIndex)
      var usages: seq[SymInfoPair] = @[]
      for i in fs.lineInfo.low..fs.lineInfo.high:
        if fs.sym[i] == sym.sym:
          usages.add(fs.getSymInfoPair(i))
      myLog fmt "Found {usages.len} usages in {file.string}"
      for s in usages:
        graph.suggestResult(s.sym, s.info)
  of ideRecompile:
    graph.recompileFullProject()
  of ideChanged:
    graph.markDirtyIfNeeded(file.string, fileIndex)
  of ideSug, ideCon:
    # ideSug/ideCon performs partial build of the file, thus mark it dirty for the
    # future calls.
    graph.markDirtyIfNeeded(file.string, fileIndex)
    graph.recompilePartially(fileIndex) 
    let m = graph.getModule fileIndex
    incl m.flags, sfDirty 
  of ideOutline:
    let n = parseFile(fileIndex, graph.cache, graph.config)
    graph.iterateOutlineNodes(n, graph.fileSymbols(fileIndex).deduplicateSymInfoPair)
  of ideChk:
    myLog fmt "Reporting errors for {graph.suggestErrors.len} file(s)"
    for sug in graph.suggestErrorsIter:
      suggestResult(graph.config, sug)
  of ideChkFile:
    let errors = graph.suggestErrors.getOrDefault(fileIndex, @[])
    myLog fmt "Reporting {errors.len} error(s) for {file.string}"
    for error in errors:
      suggestResult(graph.config, error)
  of ideGlobalSymbols:
    var
      counter = 0
      res: seq[SymInfoPair] = @[]

    for s in graph.suggestSymbolsIter:
      if (sfGlobal in s.sym.flags or s.sym.kind in searchableSymKinds) and
          s.sym.info == s.info:
        if contains(s.sym.name.s, file.string):
          inc counter
          res = res.filterIt(not it.info.exactEquals(s.info))
          res.add s
          # stop after first 1000 matches...
          if counter > 1000:
            break

    # ... then sort them by weight ...
    res.sort() do (left, right: SymInfoPair) -> int:
      let
        leftString = left.sym.name.s
        rightString = right.sym.name.s
        leftIndex = leftString.find(file.string)
        rightIndex = rightString.find(file.string)

      if leftIndex == rightIndex:
        result = cmp(toLowerAscii(leftString),
                     toLowerAscii(rightString))
      else:
        result = cmp(leftIndex, rightIndex)

    # ... and send first 100 results
    if res.len > 0:
      for i in 0 .. min(100, res.len - 1):
        let s = res[i]
        graph.suggestResult(s.sym, s.info)

  of ideDeclaration:
    let s = graph.findSymData(file, line, col)
    if not s.isNil:
      # find first mention of the symbol in the file containing the definition.
      # It is either the definition or the declaration.
      var first: SymInfoPair = default(SymInfoPair)
      let db = graph.fileSymbols(s.sym.info.fileIndex).deduplicateSymInfoPair
      for i in db.lineInfo.low..db.lineInfo.high:
        if s.sym.symbolEqual(db.sym[i]):
          first = db.getSymInfoPair(i)
          break

      if s.info.exactEquals(first.info):
        # we are on declaration, go to definition
        graph.suggestResult(first.sym, first.sym.info, ideDeclaration)
      else:
        # we are on definition or usage, look for declaration
        graph.suggestResult(first.sym, first.info, ideDeclaration)
  of ideExpand:
    var level: int = high(int)
    let index = skipWhitespace(tag, 0);
    let trimmed = substr(tag, index)
    if not (trimmed == "" or trimmed == "all"):
      discard parseInt(trimmed, level, 0)

    conf.expandPosition = newLineInfo(fileIndex, line, col)
    conf.expandLevels = level
    conf.expandProgress = false
    conf.expandNodeResult = ""

    graph.markDirty fileIndex
    graph.markClientsDirty fileIndex
    graph.recompilePartially()
    var suggest = Suggest()
    suggest.section = ideExpand
    suggest.version = 3
    suggest.line = line
    suggest.column = col
    suggest.doc = graph.config.expandNodeResult
    if suggest.doc != "":
      let
        n = parseFile(fileIndex, graph.cache, graph.config)
        endInfo = n.calculateExpandRange(conf.expandPosition)

      suggest.endLine = endInfo.line
      suggest.endCol = endInfo.col

    suggestResult(graph.config, suggest)

    graph.markDirty fileIndex
    graph.markClientsDirty fileIndex
  of ideInlayHints:
    myLog fmt "Executing inlayHints"
    var endLine = 0
    var endCol = -1
    var i = 0
    i += skipWhile(tag, seps, i)
    i += parseInt(tag, endLine, i)
    i += skipWhile(tag, seps, i)
    i += parseInt(tag, endCol, i)
    i += skipWhile(tag, seps, i)
    var typeHints = true
    var exceptionHints = false
    while i <= tag.high:
      var token: string = ""
      i += parseUntil(tag, token, seps, i)
      i += skipWhile(tag, seps, i)
      case token:
      of "+typeHints":
        typeHints = true
      of "-typeHints":
        typeHints = false
      of "+exceptionHints":
        exceptionHints = true
      of "-exceptionHints":
        exceptionHints = false
      else:
        myLog fmt "Discarding unknown inlay hint parameter {token}"

    let s = graph.findSymDataInRange(file, line, col, endLine, endCol)
    for q in s:
      if typeHints and q.sym.kind in {skLet, skVar, skForVar, skConst} and q.isDecl and not q.sym.hasUserSpecifiedType:
        graph.suggestInlayHintResultType(q.sym, q.info, ideInlayHints)
      if exceptionHints and q.sym.kind in {skProc, skFunc, skMethod, skVar, skLet, skParam} and not q.isDecl:
        graph.suggestInlayHintResultException(q.sym, q.info, ideInlayHints, caughtExceptions = q.caughtExceptions, caughtExceptionsSet = q.caughtExceptionsSet)
  else:
    myLog fmt "Discarding {cmd}"

# v3 end
when isMainModule:
  handleCmdLine(newIdentCache(), newConfigRef())
else:
  export Suggest
  export IdeCmd
  export AbsoluteFile
  type NimSuggest* = ref object
    graph: ModuleGraph
    idle: int
    cachedMsgs: CachedMsgs

  proc initNimSuggest*(project: string, nimPath: string = ""): NimSuggest =
    var retval: ModuleGraph
    proc mockCommand(graph: ModuleGraph) =
      retval = graph
      let conf = graph.config
      conf.setCmd cmdIdeTools
      defineSymbol(conf.symbols, $conf.backend)
      clearPasses(graph)
      registerPass graph, verbosePass
      registerPass graph, semPass

      wantMainModule(conf)

      if not fileExists(conf.projectFull):
        quit "cannot find file: " & conf.projectFull.string

      add(conf.searchPaths, conf.libpath)

      conf.setErrorMaxHighMaybe
      # do not print errors, but log them
      conf.writelnHook = myLog
      conf.structuredErrorHook = nil

      # compile the project before showing any input so that we already
      # can answer questions right away:
      compileProject(graph)


    proc mockCmdLine(pass: TCmdLinePass, cmd: string; conf: ConfigRef) =
      conf.suggestVersion = 0
      let a = unixToNativePath(project)
      if dirExists(a) and not fileExists(a.addFileExt("nim")):
        conf.projectName = findProjectNimFile(conf, a)
        # don't make it worse, report the error the old way:
        if conf.projectName.len == 0: conf.projectName = a
      else:
        conf.projectName = a
          # if processArgument(pass, p, argsCount): break
    let
      cache = newIdentCache()
      conf = newConfigRef()
      self = NimProg(
        suggestMode: true,
        processCmdLine: mockCmdLine
      )
    self.initDefinesProg(conf, "nimsuggest")

    self.processCmdLineAndProjectPath(conf)

    if gMode != mstdin:
      conf.writelnHook = proc (msg: string) = discard
    # Find Nim's prefix dir.
    if nimPath == "":
      conf.prefixDir = conf.getPrefixDir()
    else:
      conf.prefixDir = AbsoluteDir nimPath

    #msgs.writelnHook = proc (line: string) = log(line)
    myLog("START " & conf.projectFull.string)

    var graph = newModuleGraph(cache, conf)
    if self.loadConfigsAndProcessCmdLine(cache, conf, graph):
      mockCommand(graph)
    if gLogging:
      myLog("Search paths:")
      for it in conf.searchPaths:
        myLog(" " & it.string)

    retval.doStopCompile = proc (): bool = false
    return NimSuggest(graph: retval, idle: 0, cachedMsgs: @[])

  proc runCmd*(nimsuggest: NimSuggest, cmd: IdeCmd, file, dirtyfile: AbsoluteFile, line, col: int): seq[Suggest] =
    var retval: seq[Suggest] = @[]
    let conf = nimsuggest.graph.config
    conf.ideCmd = cmd
    conf.writelnHook = proc (line: string) =
      retval.add(Suggest(section: ideMsg, doc: line))
    conf.suggestionResultHook = proc (s: Suggest) =
      retval.add(s)
    conf.writelnHook = proc (s: string) =
      stderr.write s & "\n"
    if conf.ideCmd == ideKnown:
      retval.add(Suggest(section: ideKnown, quality: ord(fileInfoKnown(conf, file))))
    elif conf.ideCmd == ideProject:
      retval.add(Suggest(section: ideProject, filePath: string conf.projectFull))
    else:
      if conf.ideCmd == ideChk:
        for cm in nimsuggest.cachedMsgs: errorHook(conf, cm.info, cm.msg, cm.sev)
      if conf.ideCmd == ideChk:
        conf.structuredErrorHook = proc (conf: ConfigRef; info: TLineInfo; msg: string; sev: Severity) =
          retval.add(Suggest(section: ideChk, filePath: toFullPath(conf, info),
            line: toLinenumber(info), column: toColumn(info), doc: msg,
            forth: $sev))

      else:
        conf.structuredErrorHook = nil
      executeNoHooks(conf.ideCmd, file, dirtyfile, line, col, nimsuggest.graph)
    return retval

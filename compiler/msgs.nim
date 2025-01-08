#
#
#           The Nim Compiler
#        (c) Copyright 2013 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import
  std/[strutils, os, tables, terminal, macros, times],
  std/private/miscdollars,
  options, lineinfos, pathutils

import ropes except `%`

when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions]


type InstantiationInfo* = typeof(instantiationInfo())
template instLoc*(): InstantiationInfo = instantiationInfo(-2, fullPaths = true)

template toStdOrrKind(stdOrr): untyped =
  if stdOrr == stdout: stdOrrStdout else: stdOrrStderr

proc toLowerAscii(a: var string) {.inline.} =
  for c in mitems(a):
    if isUpperAscii(c): c = char(uint8(c) xor 0b0010_0000'u8)

proc flushDot*(conf: ConfigRef) =
  ## safe to call multiple times
  # xxx one edge case not yet handled is when `printf` is called at CT with `compiletimeFFI`.
  let stdOrr = if optStdout in conf.globalOptions: stdout else: stderr
  let stdOrrKind = toStdOrrKind(stdOrr)
  if stdOrrKind in conf.lastMsgWasDot:
    conf.lastMsgWasDot.excl stdOrrKind
    write(stdOrr, "\n")

proc toCChar*(c: char; result: var string) {.inline.} =
  case c
  of '\0'..'\x1F', '\x7F'..'\xFF':
    result.add '\\'
    result.add toOctal(c)
  of '\'', '\"', '\\', '?':
    result.add '\\'
    result.add c
  else:
    result.add c

proc makeCString*(s: string): Rope =
  result = newStringOfCap(int(s.len.toFloat * 1.1) + 1)
  result.add("\"")
  for i in 0..<s.len:
    # line wrapping of string litterals in cgen'd code was a bad idea, e.g. causes: bug #16265
    # It also makes reading c sources or grepping harder, for zero benefit.
    # const MaxLineLength = 64
    # if (i + 1) mod MaxLineLength == 0:
    #   res.add("\"\L\"")
    toCChar(s[i], result)
  result.add('\"')

proc newFileInfo(fullPath: AbsoluteFile, projPath: RelativeFile): TFileInfo =
  result = TFileInfo(fullPath: fullPath, projPath: projPath,
                    shortName: fullPath.extractFilename,
                    quotedFullName: fullPath.string.makeCString,
                    lines: @[]
  )
  result.quotedName = result.shortName.makeCString
  when defined(nimpretty):
    if not result.fullPath.isEmpty:
      try:
        result.fullContent = readFile(result.fullPath.string)
      except IOError:
        #rawMessage(errCannotOpenFile, result.fullPath)
        # XXX fixme
        result.fullContent = ""

when defined(nimpretty):
  proc fileSection*(conf: ConfigRef; fid: FileIndex; a, b: int): string =
    substr(conf.m.fileInfos[fid.int].fullContent, a, b)

proc canonicalCase(path: var string) {.inline.} =
  ## the idea is to only use this for checking whether a path is already in
  ## the table but otherwise keep the original case
  when FileSystemCaseSensitive: discard
  else: toLowerAscii(path)

proc fileInfoKnown*(conf: ConfigRef; filename: AbsoluteFile): bool =
  var
    canon: AbsoluteFile
  try:
    canon = canonicalizePath(conf, filename)
  except OSError:
    canon = filename
  canon.string.canonicalCase
  result = conf.m.filenameToIndexTbl.hasKey(canon.string)

proc fileInfoIdx*(conf: ConfigRef; filename: AbsoluteFile; isKnownFile: var bool): FileIndex =
  var
    canon: AbsoluteFile
    pseudoPath = false

  try:
    canon = canonicalizePath(conf, filename)
  except OSError:
    canon = filename
    # The compiler uses "filenames" such as `command line` or `stdin`
    # This flag indicates that we are working with such a path here
    pseudoPath = true

  var canon2 = canon.string
  canon2.canonicalCase

  if conf.m.filenameToIndexTbl.hasKey(canon2):
    isKnownFile = true
    result = conf.m.filenameToIndexTbl[canon2]
  else:
    isKnownFile = false
    result = conf.m.fileInfos.len.FileIndex
    conf.m.fileInfos.add(newFileInfo(canon, if pseudoPath: RelativeFile filename
                                            else: relativeTo(canon, conf.projectPath)))
    conf.m.filenameToIndexTbl[canon2] = result

proc fileInfoIdx*(conf: ConfigRef; filename: AbsoluteFile): FileIndex =
  var dummy: bool = false
  result = fileInfoIdx(conf, filename, dummy)

proc fileInfoIdx*(conf: ConfigRef; filename: RelativeFile; isKnownFile: var bool): FileIndex =
  fileInfoIdx(conf, AbsoluteFile expandFilename(filename.string), isKnownFile)

proc fileInfoIdx*(conf: ConfigRef; filename: RelativeFile): FileIndex =
  var dummy: bool = false
  fileInfoIdx(conf, AbsoluteFile expandFilename(filename.string), dummy)

proc newLineInfo*(fileInfoIdx: FileIndex, line, col: int): TLineInfo =
  result = TLineInfo(fileIndex: fileInfoIdx)
  if line < int high(uint16):
    result.line = uint16(line)
  else:
    result.line = high(uint16)
  if col < int high(int16):
    result.col = int16(col)
  else:
    result.col = -1

proc newLineInfo*(conf: ConfigRef; filename: AbsoluteFile, line, col: int): TLineInfo {.inline.} =
  result = newLineInfo(fileInfoIdx(conf, filename), line, col)

const gCmdLineInfo* = newLineInfo(commandLineIdx, 1, 1)

proc concat(strings: openArray[string]): string =
  var totalLen = 0
  for s in strings: totalLen += s.len
  result = newStringOfCap totalLen
  for s in strings: result.add s

proc suggestWriteln*(conf: ConfigRef; s: string) =
  if eStdOut in conf.m.errorOutputs:
    if isNil(conf.writelnHook):
      writeLine(stdout, s)
      flushFile(stdout)
    else:
      conf.writelnHook(s)

proc msgQuit*(x: int8) = quit x
proc msgQuit*(x: string) = quit x

proc suggestQuit*() =
  raise newException(ESuggestDone, "suggest done")

# this format is understood by many text editors: it is the same that
# Borland and Freepascal use
const
  KindFormat   = " [$1]"
  KindColor    = fgCyan
  ErrorTitle   = "Error: "
  ErrorColor   = fgRed
  WarningTitle = "Warning: "
  WarningColor = fgYellow
  HintTitle    = "Hint: "
  HintColor    = fgGreen
  # NOTE: currently line info line numbers start with 1,
  # but column numbers start with 0, however most editors expect
  # first column to be 1, so we need to +1 here
  ColOffset*   = 1
  commandLineDesc* = "command line"

proc getInfoContextLen*(conf: ConfigRef): int = return conf.m.msgContext.len
proc setInfoContextLen*(conf: ConfigRef; L: int) = setLen(conf.m.msgContext, L)

proc pushInfoContext*(conf: ConfigRef; info: TLineInfo; detail: string = "") =
  conf.m.msgContext.add((info, detail))

proc popInfoContext*(conf: ConfigRef) =
  setLen(conf.m.msgContext, conf.m.msgContext.len - 1)

proc getInfoContext*(conf: ConfigRef; index: int): TLineInfo =
  let i = if index < 0: conf.m.msgContext.len + index else: index
  if i >=% conf.m.msgContext.len: result = unknownLineInfo
  else: result = conf.m.msgContext[i].info

template toFilename*(conf: ConfigRef; fileIdx: FileIndex): string =
  if fileIdx.int32 < 0 or conf == nil:
    (if fileIdx == commandLineIdx: commandLineDesc else: "???")
  else:
    conf.m.fileInfos[fileIdx.int32].shortName

proc toProjPath*(conf: ConfigRef; fileIdx: FileIndex): string =
  if fileIdx.int32 < 0 or conf == nil:
    (if fileIdx == commandLineIdx: commandLineDesc else: "???")
  else: conf.m.fileInfos[fileIdx.int32].projPath.string

proc toFullPath*(conf: ConfigRef; fileIdx: FileIndex): string =
  if fileIdx.int32 < 0 or conf == nil:
    result = (if fileIdx == commandLineIdx: commandLineDesc else: "???")
  else:
    result = conf.m.fileInfos[fileIdx.int32].fullPath.string

proc setDirtyFile*(conf: ConfigRef; fileIdx: FileIndex; filename: AbsoluteFile) =
  assert fileIdx.int32 >= 0
  conf.m.fileInfos[fileIdx.int32].dirtyFile = filename
  setLen conf.m.fileInfos[fileIdx.int32].lines, 0

proc setHash*(conf: ConfigRef; fileIdx: FileIndex; hash: string) =
  assert fileIdx.int32 >= 0
  when defined(gcArc) or defined(gcOrc) or defined(gcAtomicArc):
    conf.m.fileInfos[fileIdx.int32].hash = hash
  else:
    shallowCopy(conf.m.fileInfos[fileIdx.int32].hash, hash)


proc getHash*(conf: ConfigRef; fileIdx: FileIndex): string =
  assert fileIdx.int32 >= 0
  when defined(gcArc) or defined(gcOrc) or defined(gcAtomicArc):
    result = conf.m.fileInfos[fileIdx.int32].hash
  else:
    shallowCopy(result, conf.m.fileInfos[fileIdx.int32].hash)

proc toFullPathConsiderDirty*(conf: ConfigRef; fileIdx: FileIndex): AbsoluteFile =
  if fileIdx.int32 < 0:
    result = AbsoluteFile(if fileIdx == commandLineIdx: commandLineDesc else: "???")
  elif not conf.m.fileInfos[fileIdx.int32].dirtyFile.isEmpty:
    result = conf.m.fileInfos[fileIdx.int32].dirtyFile
  else:
    result = conf.m.fileInfos[fileIdx.int32].fullPath

template toFilename*(conf: ConfigRef; info: TLineInfo): string =
  toFilename(conf, info.fileIndex)

template toProjPath*(conf: ConfigRef; info: TLineInfo): string =
  toProjPath(conf, info.fileIndex)

template toFullPath*(conf: ConfigRef; info: TLineInfo): string =
  toFullPath(conf, info.fileIndex)

template toFullPathConsiderDirty*(conf: ConfigRef; info: TLineInfo): string =
  string toFullPathConsiderDirty(conf, info.fileIndex)

proc toFilenameOption*(conf: ConfigRef, fileIdx: FileIndex, opt: FilenameOption): string =
  case opt
  of foAbs: result = toFullPath(conf, fileIdx)
  of foRelProject: result = toProjPath(conf, fileIdx)
  of foCanonical:
    let absPath = toFullPath(conf, fileIdx)
    result = canonicalImportAux(conf, absPath.AbsoluteFile)
  of foName: result = toProjPath(conf, fileIdx).lastPathPart
  of foLegacyRelProj:
    let
      absPath = toFullPath(conf, fileIdx)
      relPath = toProjPath(conf, fileIdx)
    result = if (relPath.len > absPath.len) or (relPath.count("..") > 2):
               absPath
             else:
               relPath
  of foStacktrace:
    if optExcessiveStackTrace in conf.globalOptions:
      result = toFilenameOption(conf, fileIdx, foAbs)
    else:
      result = toFilenameOption(conf, fileIdx, foName)

proc toMsgFilename*(conf: ConfigRef; fileIdx: FileIndex): string =
  toFilenameOption(conf, fileIdx, conf.filenameOption)

template toMsgFilename*(conf: ConfigRef; info: TLineInfo): string =
  toMsgFilename(conf, info.fileIndex)

proc toLinenumber*(info: TLineInfo): int {.inline.} =
  result = int info.line

proc toColumn*(info: TLineInfo): int {.inline.} =
  result = info.col

proc toFileLineCol(info: InstantiationInfo): string {.inline.} =
  result = ""
  result.toLocation(info.filename, info.line, info.column + ColOffset)

proc toFileLineCol*(conf: ConfigRef; info: TLineInfo): string {.inline.} =
  result = ""
  result.toLocation(toMsgFilename(conf, info), info.line.int, info.col.int + ColOffset)

proc `$`*(conf: ConfigRef; info: TLineInfo): string = toFileLineCol(conf, info)

proc `$`*(info: TLineInfo): string {.error.} = discard

proc `??`* (conf: ConfigRef; info: TLineInfo, filename: string): bool =
  # only for debugging purposes
  result = filename in toFilename(conf, info)

type
  MsgFlag* = enum  ## flags altering msgWriteln behavior
    msgStdout,     ## force writing to stdout, even stderr is default
    msgSkipHook    ## skip message hook even if it is present
    msgNoUnitSep  ## the message is a complete "paragraph".
  MsgFlags* = set[MsgFlag]

proc msgWriteln*(conf: ConfigRef; s: string, flags: MsgFlags = {}) =
  ## Writes given message string to stderr by default.
  ## If ``--stdout`` option is given, writes to stdout instead. If message hook
  ## is present, then it is used to output message rather than stderr/stdout.
  ## This behavior can be altered by given optional flags.

  ## This is used for 'nim dump' etc. where we don't have nimsuggest
  ## support.
  #if conf.cmd == cmdIdeTools and optCDebug notin gGlobalOptions: return
  let sep = if msgNoUnitSep notin flags: conf.unitSep else: ""
  if not isNil(conf.writelnHook) and msgSkipHook notin flags:
    conf.writelnHook(s & sep)
  elif optStdout in conf.globalOptions or msgStdout in flags:
    if eStdOut in conf.m.errorOutputs:
      flushDot(conf)
      write stdout, s
      writeLine(stdout, sep)
      flushFile(stdout)
  else:
    if eStdErr in conf.m.errorOutputs:
      flushDot(conf)
      write stderr, s
      writeLine(stderr, sep)
      # On Windows stderr is fully-buffered when piped, regardless of C std.
      when defined(windows):
        flushFile(stderr)

macro callIgnoringStyle(theProc: typed, first: typed,
                        args: varargs[typed]): untyped =
  let typForegroundColor = bindSym"ForegroundColor".getType
  let typBackgroundColor = bindSym"BackgroundColor".getType
  let typStyle = bindSym"Style".getType
  let typTerminalCmd = bindSym"TerminalCmd".getType
  result = newCall(theProc)
  if first.kind != nnkNilLit: result.add(first)
  for arg in children(args[0][1]):
    if arg.kind == nnkNilLit: continue
    let typ = arg.getType
    if typ.kind != nnkEnumTy or
       typ != typForegroundColor and
       typ != typBackgroundColor and
       typ != typStyle and
       typ != typTerminalCmd:
      result.add(arg)

macro callStyledWriteLineStderr(args: varargs[typed]): untyped =
  result = newCall(bindSym"styledWriteLine")
  result.add(bindSym"stderr")
  for arg in children(args[0][1]):
    result.add(arg)
  when false:
    # not needed because styledWriteLine already ends with resetAttributes
    result = newStmtList(result, newCall(bindSym"resetAttributes", bindSym"stderr"))

template callWritelnHook(args: varargs[string, `$`]) =
  conf.writelnHook concat(args)

proc msgWrite(conf: ConfigRef; s: string) =
  if conf.m.errorOutputs != {}:
    let stdOrr =
      if optStdout in conf.globalOptions:
        stdout
      else:
        stderr
    write(stdOrr, s)
    flushFile(stdOrr)
    conf.lastMsgWasDot.incl stdOrr.toStdOrrKind() # subsequent writes need `flushDot`

template styledMsgWriteln(args: varargs[typed]) =
  if not isNil(conf.writelnHook):
    callIgnoringStyle(callWritelnHook, nil, args)
  elif optStdout in conf.globalOptions:
    if eStdOut in conf.m.errorOutputs:
      flushDot(conf)
      callIgnoringStyle(writeLine, stdout, args)
      flushFile(stdout)
  elif eStdErr in conf.m.errorOutputs:
    flushDot(conf)
    if optUseColors in conf.globalOptions:
      callStyledWriteLineStderr(args)
    else:
      callIgnoringStyle(writeLine, stderr, args)
    # On Windows stderr is fully-buffered when piped, regardless of C std.
    when defined(windows):
      flushFile(stderr)

proc msgKindToString*(kind: TMsgKind): string = MsgKindToStr[kind]
  # later versions may provide translated error messages

proc getMessageStr(msg: TMsgKind, arg: string): string = msgKindToString(msg) % [arg]

type TErrorHandling* = enum doNothing, doAbort, doRaise

proc log*(s: string) =
  var f: File = default(File)
  if open(f, getHomeDir() / "nimsuggest.log", fmAppend):
    f.writeLine(s)
    close(f)

proc quit(conf: ConfigRef; msg: TMsgKind) {.gcsafe.} =
  if conf.isDefined("nimDebug"): quitOrRaise(conf, $msg)
  elif defined(debug) or msg == errInternal or conf.hasHint(hintStackTrace):
    {.gcsafe.}:
      if stackTraceAvailable() and isNil(conf.writelnHook):
        writeStackTrace()
      else:
        styledMsgWriteln(fgRed, """
No stack traceback available
To create a stacktrace, rerun compilation with './koch temp $1 <file>', see $2 for details""" %
          [conf.command, "intern.html#debugging-the-compiler".createDocLink], conf.unitSep)
  quit 1

proc handleError(conf: ConfigRef; msg: TMsgKind, eh: TErrorHandling, s: string, ignoreMsg: bool) =
  if msg in fatalMsgs:
    if conf.cmd == cmdIdeTools: log(s)
    if conf.cmd != cmdIdeTools or msg != errFatal:
      quit(conf, msg)
  if msg >= errMin and msg <= errMax or
      (msg in warnMin..hintMax and msg in conf.warningAsErrors and not ignoreMsg):
    inc(conf.errorCounter)
    conf.exitcode = 1'i8
    if conf.errorCounter >= conf.errorMax:
      # only really quit when we're not in the new 'nim check --def' mode:
      if conf.ideCmd == ideNone:
        when defined(nimsuggest):
          #we need to inform the user that something went wrong when initializing NimSuggest
          raiseRecoverableError(s)
        else:
          quit(conf, msg)
    elif eh == doAbort and conf.cmd != cmdIdeTools:
      quit(conf, msg)
    elif eh == doRaise:
      raiseRecoverableError(s)

proc `==`*(a, b: TLineInfo): bool =
  result = a.line == b.line and a.fileIndex == b.fileIndex

proc exactEquals*(a, b: TLineInfo): bool =
  result = a.fileIndex == b.fileIndex and a.line == b.line and a.col == b.col

proc writeContext(conf: ConfigRef; lastinfo: TLineInfo) =
  const instantiationFrom = "template/generic instantiation from here"
  const instantiationOfFrom = "template/generic instantiation of `$1` from here"
  var info = lastinfo
  for i in 0..<conf.m.msgContext.len:
    let context = conf.m.msgContext[i]
    if context.info != lastinfo and context.info != info:
      if conf.structuredErrorHook != nil:
        conf.structuredErrorHook(conf, context.info, instantiationFrom,
                                 Severity.Hint)
      else:
        let message =
          if context.detail == "":
            instantiationFrom
          else:
            instantiationOfFrom.format(context.detail)
        styledMsgWriteln(styleBright, conf.toFileLineCol(context.info), " ", resetStyle, message)
    info = context.info

proc ignoreMsgBecauseOfIdeTools(conf: ConfigRef; msg: TMsgKind): bool =
  msg >= errGenerated and conf.cmd == cmdIdeTools and optIdeDebug notin conf.globalOptions

proc addSourceLine(conf: ConfigRef; fileIdx: FileIndex, line: string) =
  conf.m.fileInfos[fileIdx.int32].lines.add line

proc numLines*(conf: ConfigRef, fileIdx: FileIndex): int =
  ## xxx there's an off by 1 error that should be fixed; if a file ends with "foo" or "foo\n"
  ## it will return same number of lines (ie, a trailing empty line is discounted)
  result = conf.m.fileInfos[fileIdx.int32].lines.len
  if result == 0:
    try:
      for line in lines(toFullPathConsiderDirty(conf, fileIdx).string):
        addSourceLine conf, fileIdx, line
    except IOError:
      discard
    result = conf.m.fileInfos[fileIdx.int32].lines.len

proc sourceLine*(conf: ConfigRef; i: TLineInfo): string =
  ## 1-based index (matches editor line numbers); 1st line is for i.line = 1
  ## last valid line is `numLines` inclusive
  if i.fileIndex.int32 < 0: return ""
  let num = numLines(conf, i.fileIndex)
  # can happen if the error points to EOF:
  if i.line.int > num: return ""

  result = conf.m.fileInfos[i.fileIndex.int32].lines[i.line.int-1]

proc getSurroundingSrc(conf: ConfigRef; info: TLineInfo): string =
  if conf.hasHint(hintSource) and info != unknownLineInfo:
    const indent = "  "
    result = "\n" & indent & $sourceLine(conf, info)
    if info.col >= 0:
      result.add "\n" & indent & spaces(info.col) & '^'
  else:
    result = ""

proc formatMsg*(conf: ConfigRef; info: TLineInfo, msg: TMsgKind, arg: string): string =
  let title = case msg
              of warnMin..warnMax: WarningTitle
              of hintMin..hintMax: HintTitle
              else: ErrorTitle
  conf.toFileLineCol(info) & " " & title & getMessageStr(msg, arg)

proc liMessage*(conf: ConfigRef; info: TLineInfo, msg: TMsgKind, arg: string,
               eh: TErrorHandling, info2: InstantiationInfo, isRaw = false,
               ignoreError = false) {.gcsafe, noinline.} =
  var
    title: string
    color: ForegroundColor
    ignoreMsg = false
    sev: Severity
  let errorOutputsOld = conf.m.errorOutputs
  if msg in fatalMsgs:
    # don't gag, refs bug #7080, bug #18278; this can happen with `{.fatal.}`
    # or inside a `tryConstExpr`.
    conf.m.errorOutputs = {eStdOut, eStdErr}

  let kind = if msg in warnMin..hintMax and msg != hintUserRaw: $msg else: "" # xxx not sure why hintUserRaw is special
  case msg
  of errMin..errMax:
    sev = Severity.Error
    writeContext(conf, info)
    title = ErrorTitle
    color = ErrorColor
    when false:
      # we try to filter error messages so that not two error message
      # in the same file and line are produced:
      # xxx `lastError` is only used in this disabled code; but could be useful to revive
      ignoreMsg = conf.m.lastError == info and info != unknownLineInfo and eh != doAbort
    if info != unknownLineInfo: conf.m.lastError = info
  of warnMin..warnMax:
    sev = Severity.Warning
    ignoreMsg = not conf.hasWarn(msg)
    if not ignoreMsg and msg in conf.warningAsErrors:
      title = ErrorTitle
      color = ErrorColor
    else:
      title = WarningTitle
      color = WarningColor
    if not ignoreMsg: writeContext(conf, info)
    inc(conf.warnCounter)
  of hintMin..hintMax:
    sev = Severity.Hint
    ignoreMsg = not conf.hasHint(msg)
    if not ignoreMsg and msg in conf.warningAsErrors:
      title = ErrorTitle
      color = ErrorColor
    else:
      title = HintTitle
      color = HintColor
    inc(conf.hintCounter)

  let s = if isRaw: arg else: getMessageStr(msg, arg)
  if not ignoreMsg:
    let loc = if info != unknownLineInfo: conf.toFileLineCol(info) & " " else: ""
    # we could also show `conf.cmdInput` here for `projectIsCmd`
    var kindmsg = if kind.len > 0: KindFormat % kind else: ""
    if conf.structuredErrorHook != nil:
      conf.structuredErrorHook(conf, info, s & kindmsg, sev)
    if not ignoreMsgBecauseOfIdeTools(conf, msg):
      if msg == hintProcessing and conf.hintProcessingDots:
        msgWrite(conf, ".")
      else:
        styledMsgWriteln(styleBright, loc, resetStyle, color, title, resetStyle, s, KindColor, kindmsg,
                         resetStyle, conf.getSurroundingSrc(info), conf.unitSep)
        if hintMsgOrigin in conf.mainPackageNotes:
          # xxx needs a bit of refactoring to honor `conf.filenameOption`
          styledMsgWriteln(styleBright, toFileLineCol(info2), resetStyle,
            " compiler msg initiated here", KindColor,
            KindFormat % $hintMsgOrigin,
            resetStyle, conf.unitSep)
  if not ignoreError:
    handleError(conf, msg, eh, s, ignoreMsg)
  if msg in fatalMsgs:
    # most likely would have died here but just in case, we restore state
    conf.m.errorOutputs = errorOutputsOld

template rawMessage*(conf: ConfigRef; msg: TMsgKind, args: openArray[string]) =
  let arg = msgKindToString(msg) % args
  liMessage(conf, unknownLineInfo, msg, arg, eh = doAbort, instLoc(), isRaw = true)

template rawMessage*(conf: ConfigRef; msg: TMsgKind, arg: string) =
  liMessage(conf, unknownLineInfo, msg, arg, eh = doAbort, instLoc())

template fatal*(conf: ConfigRef; info: TLineInfo, arg = "", msg = errFatal) =
  liMessage(conf, info, msg, arg, doAbort, instLoc())

template globalAssert*(conf: ConfigRef; cond: untyped, info: TLineInfo = unknownLineInfo, arg = "") =
  ## avoids boilerplate
  if not cond:
    var arg2 = "'$1' failed" % [astToStr(cond)]
    if arg.len > 0: arg2.add "; " & astToStr(arg) & ": " & arg
    liMessage(conf, info, errGenerated, arg2, doRaise, instLoc())

template globalError*(conf: ConfigRef; info: TLineInfo, msg: TMsgKind, arg = "") =
  ## `local` means compilation keeps going until errorMax is reached (via `doNothing`),
  ## `global` means it stops.
  liMessage(conf, info, msg, arg, doRaise, instLoc())

template globalError*(conf: ConfigRef; info: TLineInfo, arg: string) =
  liMessage(conf, info, errGenerated, arg, doRaise, instLoc())

template localError*(conf: ConfigRef; info: TLineInfo, msg: TMsgKind, arg = "") =
  liMessage(conf, info, msg, arg, doNothing, instLoc())

template localError*(conf: ConfigRef; info: TLineInfo, arg: string) =
  liMessage(conf, info, errGenerated, arg, doNothing, instLoc())

template message*(conf: ConfigRef; info: TLineInfo, msg: TMsgKind, arg = "") =
  liMessage(conf, info, msg, arg, doNothing, instLoc())

proc warningDeprecated*(conf: ConfigRef, info: TLineInfo = gCmdLineInfo, msg = "") {.inline.} =
  message(conf, info, warnDeprecated, msg)

proc internalErrorImpl(conf: ConfigRef; info: TLineInfo, errMsg: string, info2: InstantiationInfo) =
  if conf.cmd in {cmdIdeTools, cmdCheck} and conf.structuredErrorHook.isNil: return
  writeContext(conf, info)
  liMessage(conf, info, errInternal, errMsg, doAbort, info2)

template internalError*(conf: ConfigRef; info: TLineInfo, errMsg: string) =
  internalErrorImpl(conf, info, errMsg, instLoc())

template internalError*(conf: ConfigRef; errMsg: string) =
  internalErrorImpl(conf, unknownLineInfo, errMsg, instLoc())

template internalAssert*(conf: ConfigRef, e: bool) =
  # xxx merge with `globalAssert`
  if not e:
    const info2 = instLoc()
    let arg = info2.toFileLineCol
    internalErrorImpl(conf, unknownLineInfo, arg, info2)

template lintReport*(conf: ConfigRef; info: TLineInfo, beau, got: string, extraMsg = "") =
  let m = "'$1' should be: '$2'$3" % [got, beau, extraMsg]
  let msg = if optStyleError in conf.globalOptions: errGenerated else: hintName
  liMessage(conf, info, msg, m, doNothing, instLoc())

proc quotedFilename*(conf: ConfigRef; fi: FileIndex): Rope =
  if fi.int32 < 0:
    result = makeCString "???"
  elif optExcessiveStackTrace in conf.globalOptions:
    result = conf.m.fileInfos[fi.int32].quotedFullName
  else:
    result = conf.m.fileInfos[fi.int32].quotedName

proc quotedFilename*(conf: ConfigRef; i: TLineInfo): Rope =
  quotedFilename(conf, i.fileIndex)

template listMsg(title, r) =
  msgWriteln(conf, title, {msgNoUnitSep})
  for a in r: msgWriteln(conf, "  [$1] $2" % [if a in conf.notes: "x" else: " ", $a], {msgNoUnitSep})

proc listWarnings*(conf: ConfigRef) = listMsg("Warnings:", warnMin..warnMax)
proc listHints*(conf: ConfigRef) = listMsg("Hints:", hintMin..hintMax)

proc genSuccessX*(conf: ConfigRef) =
  let mem =
    when declared(system.getMaxMem): formatSize(getMaxMem()) & " peakmem"
    else: formatSize(getTotalMem()) & " totmem"
  let loc = $conf.linesCompiled
  var build = ""
  var flags = ""
  const debugModeHints = "none (DEBUG BUILD, `-d:release` generates faster code)"
  if conf.cmd in cmdBackends:
    if conf.backend != backendJs:
      build.add "mm: $#; " % $conf.selectedGC
      if optThreads in conf.globalOptions: build.add "threads: on; "
      build.add "opt: "
      if optOptimizeSpeed in conf.options: build.add "speed"
      elif optOptimizeSize in conf.options: build.add "size"
      else: build.add debugModeHints
        # pending https://github.com/timotheecour/Nim/issues/752, point to optimization.html
      if isDefined(conf, "danger"): flags.add " -d:danger"
      elif isDefined(conf, "release"): flags.add " -d:release"
    else:
      build.add "opt: "
      if isDefined(conf, "danger"):
        build.add "speed"
        flags.add " -d:danger"
      elif isDefined(conf, "release"):
        build.add "speed"
        flags.add " -d:release"
      else: build.add debugModeHints
    if flags.len > 0: build.add "; options:" & flags
  let sec = formatFloat(epochTime() - conf.lastCmdTime, ffDecimal, 3)
  let project = if conf.filenameOption == foAbs: $conf.projectFull else: $conf.projectName
    # xxx honor conf.filenameOption more accurately
  var output: string
  if optCompileOnly in conf.globalOptions and conf.cmd != cmdJsonscript:
    output = $conf.jsonBuildFile
  elif conf.outFile.isEmpty and conf.cmd notin {cmdJsonscript} + cmdDocLike + cmdBackends:
    # for some cmd we expect a valid absOutFile
    output = "unknownOutput"
  elif optStdout in conf.globalOptions:
    output = "stdout"
  else:
    output = $conf.absOutFile
  if conf.filenameOption != foAbs: output = output.AbsoluteFile.extractFilename
    # xxx honor filenameOption more accurately
  rawMessage(conf, hintSuccessX, [
    "build", build,
    "loc", loc,
    "sec", sec,
    "mem", mem,
    "project", project,
    "output", output,
    ])

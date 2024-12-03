#
#
#           The Nim Compiler
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# This module handles the reading of the config file.

import
  llstream, commands, msgs, lexer, ast,
  options, idents, wordrecg, lineinfos, pathutils, scriptconfig

import std/[os, strutils, strtabs]

when defined(nimPreviewSlimSystem):
  import std/syncio

# ---------------- configuration file parser -----------------------------
# we use Nim's lexer here to save space and work

proc ppGetTok(L: var Lexer, tok: var Token) =
  # simple filter
  rawGetTok(L, tok)
  while tok.tokType in {tkComment}: rawGetTok(L, tok)

proc parseExpr(L: var Lexer, tok: var Token; config: ConfigRef): bool
proc parseAtom(L: var Lexer, tok: var Token; config: ConfigRef): bool =
  if tok.tokType == tkParLe:
    ppGetTok(L, tok)
    result = parseExpr(L, tok, config)
    if tok.tokType == tkParRi: ppGetTok(L, tok)
    else: lexMessage(L, errGenerated, "expected closing ')'")
  elif tok.tokType == tkNot:
    ppGetTok(L, tok)
    result = not parseAtom(L, tok, config)
  else:
    result = isDefined(config, tok.ident.s)
    ppGetTok(L, tok)

proc parseAndExpr(L: var Lexer, tok: var Token; config: ConfigRef): bool =
  result = parseAtom(L, tok, config)
  while tok.tokType == tkAnd:
    ppGetTok(L, tok)          # skip "and"
    var b = parseAtom(L, tok, config)
    result = result and b

proc parseExpr(L: var Lexer, tok: var Token; config: ConfigRef): bool =
  result = parseAndExpr(L, tok, config)
  while tok.tokType == tkOr:
    ppGetTok(L, tok)          # skip "or"
    var b = parseAndExpr(L, tok, config)
    result = result or b

proc evalppIf(L: var Lexer, tok: var Token; config: ConfigRef): bool =
  ppGetTok(L, tok)            # skip 'if' or 'elif'
  result = parseExpr(L, tok, config)
  if tok.tokType == tkColon: ppGetTok(L, tok)
  else: lexMessage(L, errGenerated, "expected ':'")

#var condStack: seq[bool] = @[]

proc doEnd(L: var Lexer, tok: var Token; condStack: var seq[bool]) =
  if high(condStack) < 0: lexMessage(L, errGenerated, "expected @if")
  ppGetTok(L, tok)            # skip 'end'
  setLen(condStack, high(condStack))

type
  TJumpDest = enum
    jdEndif, jdElseEndif

proc jumpToDirective(L: var Lexer, tok: var Token, dest: TJumpDest; config: ConfigRef;
                     condStack: var seq[bool])
proc doElse(L: var Lexer, tok: var Token; config: ConfigRef; condStack: var seq[bool]) =
  if high(condStack) < 0: lexMessage(L, errGenerated, "expected @if")
  ppGetTok(L, tok)
  if tok.tokType == tkColon: ppGetTok(L, tok)
  if condStack[high(condStack)]: jumpToDirective(L, tok, jdEndif, config, condStack)

proc doElif(L: var Lexer, tok: var Token; config: ConfigRef; condStack: var seq[bool]) =
  if high(condStack) < 0: lexMessage(L, errGenerated, "expected @if")
  var res = evalppIf(L, tok, config)
  if condStack[high(condStack)] or not res: jumpToDirective(L, tok, jdElseEndif, config, condStack)
  else: condStack[high(condStack)] = true

proc jumpToDirective(L: var Lexer, tok: var Token, dest: TJumpDest; config: ConfigRef;
                     condStack: var seq[bool]) =
  var nestedIfs = 0
  while true:
    if tok.ident != nil and tok.ident.s == "@":
      ppGetTok(L, tok)
      case whichKeyword(tok.ident)
      of wIf:
        inc(nestedIfs)
      of wElse:
        if dest == jdElseEndif and nestedIfs == 0:
          doElse(L, tok, config, condStack)
          break
      of wElif:
        if dest == jdElseEndif and nestedIfs == 0:
          doElif(L, tok, config, condStack)
          break
      of wEnd:
        if nestedIfs == 0:
          doEnd(L, tok, condStack)
          break
        if nestedIfs > 0: dec(nestedIfs)
      else:
        discard
      ppGetTok(L, tok)
    elif tok.tokType == tkEof:
      lexMessage(L, errGenerated, "expected @end")
    else:
      ppGetTok(L, tok)

proc parseDirective(L: var Lexer, tok: var Token; config: ConfigRef; condStack: var seq[bool]) =
  ppGetTok(L, tok)            # skip @
  case whichKeyword(tok.ident)
  of wIf:
    setLen(condStack, condStack.len + 1)
    let res = evalppIf(L, tok, config)
    condStack[high(condStack)] = res
    if not res: jumpToDirective(L, tok, jdElseEndif, config, condStack)
  of wElif: doElif(L, tok, config, condStack)
  of wElse: doElse(L, tok, config, condStack)
  of wEnd: doEnd(L, tok, condStack)
  of wWrite:
    ppGetTok(L, tok)
    msgs.msgWriteln(config, strtabs.`%`($tok, config.configVars,
                                {useEnvironment, useKey}))
    ppGetTok(L, tok)
  else:
    case tok.ident.s.normalize
    of "putenv":
      ppGetTok(L, tok)
      var key = $tok
      ppGetTok(L, tok)
      os.putEnv(key, $tok)
      ppGetTok(L, tok)
    of "prependenv":
      ppGetTok(L, tok)
      var key = $tok
      ppGetTok(L, tok)
      os.putEnv(key, $tok & os.getEnv(key))
      ppGetTok(L, tok)
    of "appendenv":
      ppGetTok(L, tok)
      var key = $tok
      ppGetTok(L, tok)
      os.putEnv(key, os.getEnv(key) & $tok)
      ppGetTok(L, tok)
    else:
      lexMessage(L, errGenerated, "invalid directive: '$1'" % $tok)

proc confTok(L: var Lexer, tok: var Token; config: ConfigRef; condStack: var seq[bool]) =
  ppGetTok(L, tok)
  while tok.ident != nil and tok.ident.s == "@":
    parseDirective(L, tok, config, condStack)    # else: give the token to the parser

proc checkSymbol(L: Lexer, tok: Token) =
  if tok.tokType notin {tkSymbol..tkInt64Lit, tkStrLit..tkTripleStrLit}:
    lexMessage(L, errGenerated, "expected identifier, but got: " & $tok)

proc parseAssignment(L: var Lexer, tok: var Token;
                     config: ConfigRef; filename: AbsoluteFile; condStack: var seq[bool]) =
  if tok.ident != nil:
    if tok.ident.s == "-" or tok.ident.s == "--":
      confTok(L, tok, config, condStack)           # skip unnecessary prefix
  var info = getLineInfo(L, tok) # save for later in case of an error
  checkSymbol(L, tok)
  var s = $tok
  confTok(L, tok, config, condStack)             # skip symbol
  var val = ""
  while tok.tokType == tkDot:
    s.add('.')
    confTok(L, tok, config, condStack)
    checkSymbol(L, tok)
    s.add($tok)
    confTok(L, tok, config, condStack)
  if tok.tokType == tkBracketLe:
    # BUGFIX: val, not s!
    confTok(L, tok, config, condStack)
    checkSymbol(L, tok)
    val.add('[')
    val.add($tok)
    confTok(L, tok, config, condStack)
    if tok.tokType == tkBracketRi: confTok(L, tok, config, condStack)
    else: lexMessage(L, errGenerated, "expected closing ']'")
    val.add(']')
  let percent = tok.ident != nil and tok.ident.s == "%="
  if tok.tokType in {tkColon, tkEquals} or percent:
    if val.len > 0: val.add(':')
    confTok(L, tok, config, condStack)           # skip ':' or '=' or '%'
    checkSymbol(L, tok)
    val.add($tok)
    confTok(L, tok, config, condStack)           # skip symbol
    if tok.tokType in {tkColon, tkEquals}:
      val.add($tok) # add the :
      confTok(L, tok, config, condStack)           # skip symbol
      checkSymbol(L, tok)
      val.add($tok) # add the token after it
      confTok(L, tok, config, condStack)           # skip symbol
    while tok.ident != nil and tok.ident.s == "&":
      confTok(L, tok, config, condStack)
      checkSymbol(L, tok)
      val.add($tok)
      confTok(L, tok, config, condStack)
  config.currentConfigDir = parentDir(filename.string)
  if percent:
    processSwitch(s, strtabs.`%`(val, config.configVars,
                                {useEnvironment, useEmpty}), passPP, info, config)
  else:
    processSwitch(s, val, passPP, info, config)

proc readConfigFile*(filename: AbsoluteFile; cache: IdentCache;
                    config: ConfigRef): bool =
  var
    L: Lexer = default(Lexer)
    tok: Token
    stream: PLLStream
  stream = llStreamOpen(filename, fmRead)
  if stream != nil:
    openLexer(L, filename, stream, cache, config)
    tok = Token(tokType: tkEof)       # to avoid a pointless warning
    var condStack: seq[bool] = @[]
    confTok(L, tok, config, condStack)           # read in the first token
    while tok.tokType != tkEof: parseAssignment(L, tok, config, filename, condStack)
    if condStack.len > 0: lexMessage(L, errGenerated, "expected @end")
    closeLexer(L)
    return true
  else:
    result = false

proc getUserConfigPath*(filename: RelativeFile): AbsoluteFile =
  result = getConfigDir().AbsoluteDir / RelativeDir"nim" / filename

proc getSystemConfigPath*(conf: ConfigRef; filename: RelativeFile): AbsoluteFile =
  # try standard configuration file (installation did not distribute files
  # the UNIX way)
  let p = getPrefixDir(conf)
  result = p / RelativeDir"config" / filename
  when defined(unix):
    if not fileExists(result): result = p / RelativeDir"etc/nim" / filename
    if not fileExists(result): result = AbsoluteDir"/etc/nim" / filename

proc loadConfigs*(cfg: RelativeFile; cache: IdentCache; conf: ConfigRef; idgen: IdGenerator) =
  setDefaultLibpath(conf)
  template readConfigFile(path) =
    let configPath = path
    if readConfigFile(configPath, cache, conf):
      conf.configFiles.add(configPath)

  template runNimScriptIfExists(path: AbsoluteFile, isMain = false) =
    let p = path # eval once
    var s: PLLStream = nil
    if isMain and optWasNimscript in conf.globalOptions:
      if conf.projectIsStdin: s = stdin.llStreamOpen
      elif conf.projectIsCmd: s = llStreamOpen(conf.cmdInput)
    if s == nil and fileExists(p): s = llStreamOpen(p, fmRead)
    if s != nil:
      conf.configFiles.add(p)
      runNimScript(cache, p, idgen, freshDefines = false, conf, s)

  if optSkipSystemConfigFile notin conf.globalOptions:
    readConfigFile(getSystemConfigPath(conf, cfg))

    if cfg == DefaultConfig:
      runNimScriptIfExists(getSystemConfigPath(conf, DefaultConfigNims))

  if optSkipUserConfigFile notin conf.globalOptions:
    readConfigFile(getUserConfigPath(cfg))

    if cfg == DefaultConfig:
      runNimScriptIfExists(getUserConfigPath(DefaultConfigNims))

  let pd = if not conf.projectPath.isEmpty: conf.projectPath else: AbsoluteDir(getCurrentDir())
  if optSkipParentConfigFiles notin conf.globalOptions:
    for dir in parentDirs(pd.string, fromRoot=true, inclusive=false):
      readConfigFile(AbsoluteDir(dir) / cfg)

      if cfg == DefaultConfig:
        runNimScriptIfExists(AbsoluteDir(dir) / DefaultConfigNims)

  if optSkipProjConfigFile notin conf.globalOptions:
    readConfigFile(pd / cfg)
    if cfg == DefaultConfig:
      runNimScriptIfExists(pd / DefaultConfigNims)

    if conf.projectName.len != 0:
      # new project wide config file:
      var projectConfig = changeFileExt(conf.projectFull, "nimcfg")
      if not fileExists(projectConfig):
        projectConfig = changeFileExt(conf.projectFull, "nim.cfg")
      readConfigFile(projectConfig)


  let scriptFile = conf.projectFull.changeFileExt("nims")
  let scriptIsProj = scriptFile == conf.projectFull
  template showHintConf =
    for filename in conf.configFiles:
      # delayed to here so that `hintConf` is honored
      rawMessage(conf, hintConf, filename.string)
  if conf.cmd == cmdNimscript:
    showHintConf()
    conf.configFiles.setLen 0
  if conf.cmd notin {cmdIdeTools, cmdCheck, cmdDump}:
    if conf.cmd == cmdNimscript:
      runNimScriptIfExists(conf.projectFull, isMain = true)
    else:
      runNimScriptIfExists(scriptFile, isMain = true)
  else:
    if not scriptIsProj:
      runNimScriptIfExists(scriptFile, isMain = true)
    else:
      # 'nimsuggest foo.nims' means to just auto-complete the NimScript file
      # `nim check foo.nims' means to check the syntax of the NimScript file
      discard
  showHintConf()

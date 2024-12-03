#
#
#           The Nim Compiler
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Implements the dispatcher for the different parsers.

import
  llstream, ast, idents, lexer, options, msgs, parser,
  filters, filter_tmpl, renderer, lineinfos, pathutils

import std/strutils
when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions]

export Parser, parseAll, parseTopLevelStmt, checkFirstLineIndentation, closeParser

type
  FilterKind = enum
    filtNone = "none"
    filtTemplate = "stdtmpl"
    filtReplace = "replace"
    filtStrip = "strip"

proc utf8Bom(s: string): int =
  if s.len >= 3 and s[0] == '\xEF' and s[1] == '\xBB' and s[2] == '\xBF':
    3
  else:
    0

proc containsShebang(s: string, i: int): bool =
  if i+1 < s.len and s[i] == '#' and s[i+1] == '!':
    var j = i + 2
    while j < s.len and s[j] in Whitespace: inc(j)
    result = s[j] == '/'
  else:
    result = false

proc parsePipe(filename: AbsoluteFile, inputStream: PLLStream; cache: IdentCache;
               config: ConfigRef): PNode =
  result = newNode(nkEmpty)
  var s = llStreamOpen(filename, fmRead)
  if s != nil:
    var line = newStringOfCap(80)
    discard llStreamReadLine(s, line)
    var i = utf8Bom(line)
    var linenumber = 1
    if containsShebang(line, i):
      discard llStreamReadLine(s, line)
      i = 0
      inc linenumber
    if i+1 < line.len and line[i] == '#' and line[i+1] == '?':
      when defined(nimpretty):
        # XXX this is a bit hacky, but oh well...
        config.quitOrRaise "can't nimpretty a source code filter: " & $filename
      else:
        inc(i, 2)
        while i < line.len and line[i] in Whitespace: inc(i)
        var p: Parser = default(Parser)
        openParser(p, filename, llStreamOpen(substr(line, i)), cache, config)
        result = parseAll(p)
        closeParser(p)
    llStreamClose(s)

proc getFilter(ident: PIdent): FilterKind =
  result = filtNone
  for i in FilterKind:
    if cmpIgnoreStyle(ident.s, $i) == 0:
      return i

proc getCallee(conf: ConfigRef; n: PNode): PIdent =
  if n.kind in nkCallKinds and n[0].kind == nkIdent:
    result = n[0].ident
  elif n.kind == nkIdent:
    result = n.ident
  else:
    result = nil
    localError(conf, n.info, "invalid filter: " & renderTree(n))

proc applyFilter(p: var Parser, n: PNode, filename: AbsoluteFile,
                 stdin: PLLStream): PLLStream =
  var f = getFilter(getCallee(p.lex.config, n))
  result = case f
           of filtNone:
             stdin
           of filtTemplate:
             filterTmpl(p.lex.config, stdin, filename, n)
           of filtStrip:
             filterStrip(p.lex.config, stdin, filename, n)
           of filtReplace:
             filterReplace(p.lex.config, stdin, filename, n)
  if f != filtNone:
    assert p.lex.config != nil
    if p.lex.config.hasHint(hintCodeBegin):
      rawMessage(p.lex.config, hintCodeBegin, "")
      msgWriteln(p.lex.config, result.s)
      rawMessage(p.lex.config, hintCodeEnd, "")

proc evalPipe(p: var Parser, n: PNode, filename: AbsoluteFile,
              start: PLLStream): PLLStream =
  assert p.lex.config != nil
  result = start
  if n.kind == nkEmpty: return
  if n.kind == nkInfix and n[0].kind == nkIdent and n[0].ident.s == "|":
    for i in 1..2:
      if n[i].kind == nkInfix:
        result = evalPipe(p, n[i], filename, result)
      else:
        result = applyFilter(p, n[i], filename, result)
  elif n.kind == nkStmtList:
    result = evalPipe(p, n[0], filename, result)
  else:
    result = applyFilter(p, n, filename, result)

proc openParser*(p: var Parser, fileIdx: FileIndex, inputstream: PLLStream;
                  cache: IdentCache; config: ConfigRef) =
  assert config != nil
  let filename = toFullPathConsiderDirty(config, fileIdx)
  var pipe = parsePipe(filename, inputstream, cache, config)
  p.lex.config = config
  let s = if pipe != nil: evalPipe(p, pipe, filename, inputstream)
          else: inputstream
  parser.openParser(p, fileIdx, s, cache, config)

proc setupParser*(p: var Parser; fileIdx: FileIndex; cache: IdentCache;
                   config: ConfigRef): bool =
  let filename = toFullPathConsiderDirty(config, fileIdx)
  var f: File = default(File)
  if not open(f, filename.string):
    rawMessage(config, errGenerated, "cannot open file: " & filename.string)
    return false
  openParser(p, fileIdx, llStreamOpen(f), cache, config)
  result = true

proc parseFile*(fileIdx: FileIndex; cache: IdentCache; config: ConfigRef): PNode =
  var p: Parser = default(Parser)
  if setupParser(p, fileIdx, cache, config):
    result = parseAll(p)
    closeParser(p)
  else:
    result = nil

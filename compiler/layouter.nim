#
#
#           The Nim Compiler
#        (c) Copyright 2018 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Layouter for nimpretty. Still primitive but useful.
## TODO
## - Fix 'echo ()' vs 'echo()' difference!
## - Make indentations consistent.
## - Align 'if' and 'case' expressions properly.

import idents, lexer, lineinfos, llstream, options, msgs, strutils
from os import changeFileExt

const
  MaxLineLen = 80
  LineCommentColumn = 30

type
  SplitKind = enum
    splitComma, splitParLe, splitAnd, splitOr, splitIn, splitBinary

  Emitter* = object
    f: PLLStream
    config: ConfigRef
    fid: FileIndex
    lastTok: TTokType
    inquote: bool
    col, lastLineNumber, lineSpan, indentLevel: int
    content: string
    fixedUntil: int # marks where we must not go in the content
    altSplitPos: array[SplitKind, int] # alternative split positions

proc openEmitter*(em: var Emitter, config: ConfigRef, fileIdx: FileIndex) =
  let outfile = changeFileExt(config.toFullPath(fileIdx), ".pretty.nim")
  em.f = llStreamOpen(outfile, fmWrite)
  em.config = config
  em.fid = fileIdx
  em.lastTok = tkInvalid
  em.inquote = false
  em.col = 0
  em.content = newStringOfCap(16_000)
  if em.f == nil:
    rawMessage(config, errGenerated, "cannot open file: " & outfile)

proc closeEmitter*(em: var Emitter) =
  em.f.llStreamWrite em.content
  llStreamClose(em.f)

proc countNewlines(s: string): int =
  result = 0
  for i in 0..<s.len:
    if s[i] == '\L': inc result

proc calcCol(em: var Emitter; s: string) =
  var i = s.len-1
  em.col = 0
  while i >= 0 and s[i] != '\L':
    dec i
    inc em.col

template wr(x) =
  em.content.add x
  inc em.col, x.len

template goodCol(col): bool = col in 40..MaxLineLen

const splitters = {tkComma, tkSemicolon, tkParLe, tkParDotLe,
                   tkBracketLe, tkBracketLeColon, tkCurlyDotLe,
                   tkCurlyLe}

template rememberSplit(kind) =
  if goodCol(em.col):
    em.altSplitPos[kind] = em.content.len

proc softLinebreak(em: var Emitter, lit: string) =
  # XXX Use an algorithm that is outlined here:
  # https://llvm.org/devmtg/2013-04/jasper-slides.pdf
  # +2 because we blindly assume a comma or ' &' might follow
  if not em.inquote and em.col+lit.len+2 >= MaxLineLen:
    if em.lastTok in splitters:
      wr("\L")
      em.col = 0
      for i in 1..em.indentLevel+2: wr(" ")
    else:
      # search backwards for a good split position:
      for a in em.altSplitPos:
        if a > em.fixedUntil:
          let ws = "\L" & repeat(' ',em.indentLevel+2)
          em.col = em.content.len - a
          em.content.insert(ws, a)
          break

proc emitTok*(em: var Emitter; L: TLexer; tok: TToken) =

  template endsInWhite(em): bool =
    em.content.len > 0 and em.content[em.content.high] in {' ', '\L'}
  template endsInAlpha(em): bool =
    em.content.len > 0 and em.content[em.content.high] in SymChars+{'_'}

  proc emitComment(em: var Emitter; tok: TToken) =
    let lit = strip fileSection(em.config, em.fid, tok.commentOffsetA, tok.commentOffsetB)
    em.lineSpan = countNewlines(lit)
    if em.lineSpan > 0: calcCol(em, lit)
    if not endsInWhite(em):
      wr(" ")
      if em.lineSpan == 0 and max(em.col, LineCommentColumn) + lit.len <= MaxLineLen:
        for i in 1 .. LineCommentColumn - em.col: wr(" ")
    wr lit

  var preventComment = false
  if tok.tokType == tkComment and tok.line == em.lastLineNumber and tok.indent >= 0:
    # we have an inline comment so handle it before the indentation token:
    emitComment(em, tok)
    preventComment = true
    em.fixedUntil = em.content.high

  elif tok.indent >= 0:
    em.indentLevel = tok.indent
    # remove trailing whitespace:
    while em.content.len > 0 and em.content[em.content.high] == ' ':
      setLen(em.content, em.content.len-1)
    wr("\L")
    for i in 2..tok.line - em.lastLineNumber: wr("\L")
    em.col = 0
    for i in 1..tok.indent:
      wr(" ")
    em.fixedUntil = em.content.high

  case tok.tokType
  of tokKeywordLow..tokKeywordHigh:
    if endsInAlpha(em):
      wr(" ")
    elif not em.inquote and not endsInWhite(em):
      wr(" ")

    wr(TokTypeToStr[tok.tokType])

    case tok.tokType
    of tkAnd: rememberSplit(splitAnd)
    of tkOr: rememberSplit(splitOr)
    of tkIn, tkNotin:
      rememberSplit(splitIn)
      wr(" ")
    else: discard

  of tkColon:
    wr(TokTypeToStr[tok.tokType])
    wr(" ")
  of tkSemicolon, tkComma:
    wr(TokTypeToStr[tok.tokType])
    wr(" ")
    rememberSplit(splitComma)
  of tkParLe, tkParRi, tkBracketLe,
     tkBracketRi, tkCurlyLe, tkCurlyRi,
     tkBracketDotLe, tkBracketDotRi,
     tkCurlyDotLe, tkCurlyDotRi,
     tkParDotLe, tkParDotRi,
     tkColonColon, tkDot, tkBracketLeColon:
    wr(TokTypeToStr[tok.tokType])
    if tok.tokType in splitters:
      rememberSplit(splitParLe)
  of tkEquals:
    if not em.endsInWhite: wr(" ")
    wr(TokTypeToStr[tok.tokType])
    wr(" ")
  of tkOpr, tkDotDot:
    if not em.endsInWhite: wr(" ")
    wr(tok.ident.s)
    template isUnary(tok): bool =
      tok.strongSpaceB == 0 and tok.strongSpaceA > 0

    if not isUnary(tok) or em.lastTok in {tkOpr, tkDotDot}:
      wr(" ")
      rememberSplit(splitBinary)
  of tkAccent:
    wr(TokTypeToStr[tok.tokType])
    em.inquote = not em.inquote
  of tkComment:
    if not preventComment:
      emitComment(em, tok)
  of tkIntLit..tkStrLit, tkRStrLit, tkTripleStrLit, tkGStrLit, tkGTripleStrLit, tkCharLit:
    let lit = fileSection(em.config, em.fid, tok.offsetA, tok.offsetB)
    softLinebreak(em, lit)
    if endsInAlpha(em) and tok.tokType notin {tkGStrLit, tkGTripleStrLit}: wr(" ")
    em.lineSpan = countNewlines(lit)
    if em.lineSpan > 0: calcCol(em, lit)
    wr lit
  of tkEof: discard
  else:
    let lit = if tok.ident != nil: tok.ident.s else: tok.literal
    softLinebreak(em, lit)
    if endsInAlpha(em): wr(" ")
    wr lit

  em.lastTok = tok.tokType
  em.lastLineNumber = tok.line + em.lineSpan
  em.lineSpan = 0

proc starWasExportMarker*(em: var Emitter) =
  if em.content.endsWith(" * "):
    setLen(em.content, em.content.len-3)
    em.content.add("*")
    dec em.col, 2

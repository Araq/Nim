#
#
#           The Nim Compiler
#        (c) Copyright 2018 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Layouter for nimpretty.

import idents, lexer, ast, lineinfos, llstream, options, msgs, strutils, pathutils

const
  MinLineLen = 15

type
  SplitKind = enum
    splitComma, splitParLe, splitAnd, splitOr, splitIn, splitBinary

  SemicolonKind = enum
    detectSemicolonKind, useSemicolon, dontTouch

  LayoutToken* = enum
    ltSpaces,
    ltCrucialNewline, ## a semantically crucial newline (indentation!)
    ltSplittingNewline, ## newline used for splitting up long
                        ## expressions (like after a comma or a binary operator)
    ltTab,
    ltOptionalNewline, ## optional newline introduced by nimpretty
    ltComment, ltLit, ltKeyword, ltExportMarker, ltIdent,
    ltOther, ltOpr, ltSomeParLe, ltSomeParRi,
    ltBeginSection, ltEndSection

  Emitter* = object
    config: ConfigRef
    fid: FileIndex
    lastTok: TokType
    inquote, lastTokWasTerse: bool
    semicolons: SemicolonKind
    col, lastLineNumber, lineSpan, indentLevel, indWidth*, inSection: int
    keepIndents*: int
    doIndentMore*: int
    kinds*: seq[LayoutToken]
    tokens*: seq[string]
    indentStack: seq[int]
    fixedUntil: int # marks where we must not go in the content
    altSplitPos: array[SplitKind, int] # alternative split positions
    maxLineLen*: int

proc openEmitter*(em: var Emitter, cache: IdentCache;
                  config: ConfigRef, fileIdx: FileIndex) =
  let fullPath = AbsoluteFile config.toFullPath(fileIdx)
  if em.indWidth == 0:
    em.indWidth = getIndentWidth(fileIdx, llStreamOpen(fullPath, fmRead),
                                cache, config)
    if em.indWidth == 0: em.indWidth = 2
  em.config = config
  em.fid = fileIdx
  em.lastTok = tkInvalid
  em.inquote = false
  em.col = 0
  em.indentStack = newSeqOfCap[int](30)
  em.indentStack.add 0
  em.lastLineNumber = 1

proc computeMax(em: Emitter; pos: int): int =
  var p = pos
  var extraSpace = 0
  result = 0
  while p < em.tokens.len and em.kinds[p] != ltEndSection:
    var lhs = 0
    var lineLen = 0
    var foundTab = false
    while p < em.tokens.len and em.kinds[p] != ltEndSection:
      if em.kinds[p] in {ltCrucialNewline, ltSplittingNewline}:
        if foundTab and lineLen <= em.maxLineLen:
          result = max(result, lhs + extraSpace)
        inc p
        break
      if em.kinds[p] == ltTab:
        extraSpace = if em.kinds[p-1] == ltSpaces: 0 else: 1
        foundTab = true
      else:
        if not foundTab:
          inc lhs, em.tokens[p].len
        inc lineLen, em.tokens[p].len
      inc p

proc computeRhs(em: Emitter; pos: int): int =
  var p = pos
  result = 0
  while p < em.tokens.len and em.kinds[p] notin {ltCrucialNewline, ltSplittingNewline}:
    inc result, em.tokens[p].len
    inc p

proc isLongEnough(lineLen, startPos, endPos: int): bool =
  result = lineLen > MinLineLen and endPos > startPos + 4

proc findNewline(em: Emitter; p, lineLen: var int) =
  while p < em.tokens.len and em.kinds[p] notin {ltCrucialNewline, ltSplittingNewline}:
    inc lineLen, em.tokens[p].len
    inc p

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

proc optionalIsGood(em: var Emitter; pos, currentLen: int): bool =
  let ourIndent = em.tokens[pos].len
  var p = pos+1
  var lineLen = 0
  em.findNewline(p, lineLen)
  if p == pos+1: # optionalNewline followed by another newline
    result = false
  elif em.kinds[p-1] == ltComment and currentLen+lineLen < em.maxLineLen+MinLineLen:
    result = false
  elif p+1 < em.tokens.len and em.kinds[p+1] == ltSpaces and
      em.kinds[p-1] == ltOptionalNewline:
    if em.tokens[p+1].len == ourIndent:
      # concatenate lines with the same indententation
      var nlPos = p
      var lineLenTotal = lineLen
      inc p
      em.findNewline(p, lineLenTotal)
      if isLongEnough(lineLenTotal, nlPos, p):
        em.kinds[nlPos] = ltOptionalNewline
        if em.kinds[nlPos+1] == ltSpaces:
          # inhibit extra spaces when concatenating two lines
          em.tokens[nlPos+1] = if em.tokens[nlPos-2] == ",": " " else: ""
      result = true
    elif em.tokens[p+1].len < ourIndent:
      result = isLongEnough(lineLen, pos, p)
  elif em.kinds[pos+1] in {ltOther, ltSomeParLe, ltSomeParRi}: # note: pos+1, not p+1
    result = false
  else:
    result = isLongEnough(lineLen, pos, p)

proc lenOfNextTokens(em: Emitter; pos: int): int =
  result = 0
  for i in 1..<em.tokens.len-pos:
    if em.kinds[pos+i] in {ltCrucialNewline, ltSplittingNewline, ltOptionalNewline}: break
    inc result, em.tokens[pos+i].len

proc guidingInd(em: Emitter; pos: int): int =
  var i = pos - 1
  while i >= 0 and em.kinds[i] != ltSomeParLe:
    dec i
  while i+1 <= em.kinds.high and em.kinds[i] != ltSomeParRi:
    if em.kinds[i] == ltSplittingNewline and em.kinds[i+1] == ltSpaces:
      return em.tokens[i+1].len
    inc i
  result = -1

proc renderTokens*(em: var Emitter): string =
  ## Render Emitter tokens to a string of code
  template defaultCase() =
    content.add em.tokens[i]
    inc lineLen, em.tokens[i].len
  var content = newStringOfCap(16_000)
  var maxLhs = 0
  var lineLen = 0
  var lineBegin = 0
  var openPars = 0
  var i = 0
  while i <= em.tokens.high:
    when defined(debug):
      echo (token: em.tokens[i], kind: em.kinds[i])
    case em.kinds[i]
    of ltBeginSection:
      maxLhs = computeMax(em, lineBegin)
    of ltEndSection:
      maxLhs = 0
      lineBegin = i+1
    of ltTab:
      if i >= 2 and em.kinds[i-2] in {ltCrucialNewline, ltSplittingNewline} and
          em.kinds[i-1] in {ltCrucialNewline, ltSplittingNewline, ltSpaces}:
        # a previous section has ended
        maxLhs = 0

      if maxLhs == 0:
        if em.kinds[i-1] != ltSpaces:
          content.add em.tokens[i]
          inc lineLen, em.tokens[i].len
      else:
        # pick the shorter indentation token:
        var spaces = maxLhs - lineLen
        if spaces < em.tokens[i].len or computeRhs(em, i+1)+maxLhs <= em.maxLineLen+MinLineLen:
          if spaces <= 0 and content[^1] notin {' ', '\L'}: spaces = 1
          for j in 1..spaces: content.add ' '
          inc lineLen, spaces
        else:
          content.add em.tokens[i]
          inc lineLen, em.tokens[i].len
    of ltCrucialNewline, ltSplittingNewline:
      content.add em.tokens[i]
      lineLen = 0
      lineBegin = i+1
    of ltOptionalNewline:
      let totalLineLen = lineLen + lenOfNextTokens(em, i)
      if totalLineLen > em.maxLineLen and optionalIsGood(em, i, lineLen):
        if i-1 >= 0 and em.kinds[i-1] == ltSpaces:
          let spaces = em.tokens[i-1].len
          content.setLen(content.len - spaces)
        content.add "\L"
        let guide = if openPars > 0: guidingInd(em, i) else: -1
        if guide >= 0:
          content.add repeat(' ', guide)
          lineLen = guide
        else:
          content.add em.tokens[i]
          lineLen = em.tokens[i].len
        lineBegin = i+1
        if i+1 < em.kinds.len and em.kinds[i+1] == ltSpaces:
          # inhibit extra spaces at the start of a new line
          inc i
    of ltLit:
      let lineSpan = countNewlines(em.tokens[i])
      if lineSpan > 0:
        em.calcCol(em.tokens[i])
        lineLen = em.col
      else:
        inc lineLen, em.tokens[i].len
      content.add em.tokens[i]
    of ltSomeParLe:
      inc openPars
      defaultCase()
    of ltSomeParRi:
      doAssert openPars > 0
      dec openPars
      defaultCase()
    else:
      defaultCase()
    inc i

  return content

type
  FinalCheck = proc (content: string; origAst: PNode): bool {.nimcall.}

proc writeOut*(em: Emitter; content: string; origAst: PNode; check: FinalCheck) =
  ## Write to disk
  let outFile = em.config.absOutFile
  if fileExists(outFile) and readFile(outFile.string) == content:
    discard "do nothing, see #9499"
    return

  if check(content, origAst):
    var f = llStreamOpen(outFile, fmWrite)
    if f == nil:
      rawMessage(em.config, errGenerated, "cannot open file: " & outFile.string)
      return
    f.llStreamWrite content
    llStreamClose(f)

proc closeEmitter*(em: var Emitter; origAst: PNode; check: FinalCheck) =
  ## Renders emitter tokens and write to a file
  let content = renderTokens(em)
  em.writeOut(content, origAst, check)

proc wr(em: var Emitter; x: string; lt: LayoutToken) =
  em.tokens.add x
  em.kinds.add lt
  inc em.col, x.len
  assert em.tokens.len == em.kinds.len

proc wrNewline(em: var Emitter; kind = ltCrucialNewline) =
  em.tokens.add "\L"
  em.kinds.add kind
  em.col = 0

proc newlineWasSplitting*(em: var Emitter) =
  if em.kinds.len >= 3 and em.kinds[^3] == ltCrucialNewline:
    em.kinds[^3] = ltSplittingNewline

#[
Splitting newlines can occur:
- after commas, semicolon, '[', '('.
- after binary operators, '='.
- after ':' type

We only need parser support for the "after type" case.
]#

proc wrSpaces(em: var Emitter; spaces: int) =
  if spaces > 0:
    wr(em, strutils.repeat(' ', spaces), ltSpaces)

proc wrSpace(em: var Emitter) =
  wr(em, " ", ltSpaces)

proc wrTab(em: var Emitter) =
  wr(em, " ", ltTab)

proc beginSection*(em: var Emitter) =
  let pos = max(0, em.tokens.len-2)
  em.tokens.insert "", pos
  em.kinds.insert ltBeginSection, pos
  inc em.inSection

#wr(em, "", ltBeginSection)
proc endSection*(em: var Emitter) =
  em.tokens.insert "", em.tokens.len-2
  em.kinds.insert ltEndSection, em.kinds.len-2
  dec em.inSection

#wr(em, "", ltEndSection)

proc removeSpaces(em: var Emitter) =
  while em.kinds.len > 0 and em.kinds[^1] == ltSpaces:
    let tokenLen = em.tokens[^1].len
    setLen(em.tokens, em.tokens.len-1)
    setLen(em.kinds, em.kinds.len-1)
    dec em.col, tokenLen


const
  openPars = {tkParLe, tkParDotLe,
              tkBracketLe, tkBracketDotLe, tkBracketLeColon,
              tkCurlyDotLe, tkCurlyLe}
  closedPars = {tkParRi, tkParDotRi,
                tkBracketRi, tkBracketDotRi,
                tkCurlyDotRi, tkCurlyRi}

  splitters = openPars + {tkComma, tkSemiColon} # do not add 'tkColon' here!
  oprSet = {tkOpr, tkDiv, tkMod, tkShl, tkShr, tkIn, tkNotin, tkIs,
            tkIsnot, tkNot, tkOf, tkAs, tkFrom, tkDotDot, tkAnd, tkOr, tkXor}

template goodCol(col): bool = col >= em.maxLineLen div 2

template moreIndent(em): int =
  if em.doIndentMore > 0: em.indWidth*2 else: em.indWidth

template rememberSplit(kind) =
  if goodCol(em.col) and not em.inquote:
    let spaces = em.indentLevel+moreIndent(em)
    if spaces < em.col and spaces > 0:
      wr(em, strutils.repeat(' ', spaces), ltOptionalNewline)
    #em.altSplitPos[kind] = em.tokens.len

proc emitMultilineComment(em: var Emitter, lit: string, col: int; dontIndent: bool) =
  # re-align every line in the multi-line comment:
  var i = 0
  var lastIndent = if em.keepIndents > 0: em.indentLevel else: em.indentStack[^1]
  var b = 0
  var dontIndent = dontIndent
  var hasEmptyLine = false
  for commentLine in splitLines(lit):
    if i == 0 and (commentLine.endsWith("\\") or commentLine.endsWith("[")):
      dontIndent = true
      wr em, commentLine, ltComment
    elif dontIndent:
      if i > 0: wrNewline em
      wr em, commentLine, ltComment
    else:
      let stripped = commentLine.strip()
      if i == 0:
        if em.kinds.len > 0 and em.kinds[^1] != ltTab:
          wr(em, "", ltTab)
      elif stripped.len == 0:
        wrNewline em
        hasEmptyLine = true
      else:
        var a = 0
        while a < commentLine.len and commentLine[a] == ' ': inc a

        if a > lastIndent:
          b += em.indWidth
          lastIndent = a
        elif a < lastIndent:
          b -= em.indWidth
          lastIndent = a
        wrNewline em
        if not hasEmptyLine or col + b < 15:
          if col + b > 0:
            wr(em, repeat(' ', col+b), ltTab)
          else:
            wr(em, "", ltTab)
        else:
          wr(em, repeat(' ', a), ltSpaces)
      wr em, stripped, ltComment
    inc i

proc lastChar(s: string): char =
  result = if s.len > 0: s[s.high] else: '\0'

proc endsInWhite(em: Emitter): bool =
  var i = em.tokens.len-1
  while i >= 0 and em.kinds[i] in {ltBeginSection, ltEndSection}: dec(i)
  result = if i >= 0: em.kinds[i] in {ltSpaces, ltCrucialNewline, ltSplittingNewline, ltTab} else: true

proc endsInNewline(em: Emitter): bool =
  var i = em.tokens.len-1
  while i >= 0 and em.kinds[i] in {ltBeginSection, ltEndSection, ltSpaces}: dec(i)
  result = if i >= 0: em.kinds[i] in {ltCrucialNewline, ltSplittingNewline, ltTab} else: true

proc endsInAlpha(em: Emitter): bool =
  var i = em.tokens.len-1
  while i >= 0 and em.kinds[i] in {ltBeginSection, ltEndSection}: dec(i)
  result = if i >= 0: em.tokens[i].lastChar in SymChars+{'_'} else: false

proc emitComment(em: var Emitter; tok: Token; dontIndent: bool) =
  var col = em.col
  let lit = strip fileSection(em.config, em.fid, tok.commentOffsetA, tok.commentOffsetB)
  em.lineSpan = countNewlines(lit)
  if em.lineSpan > 0: calcCol(em, lit)
  if em.lineSpan == 0:
    if not endsInNewline(em):
      wrTab em
    wr em, lit, ltComment
  else:
    if not endsInWhite(em):
      wrTab em
      inc col
    emitMultilineComment(em, lit, col, dontIndent)

proc emitTok*(em: var Emitter; L: Lexer; tok: Token) =
  template wasExportMarker(em): bool =
    em.kinds.len > 0 and em.kinds[^1] == ltExportMarker

  if tok.tokType == tkComment and tok.literal.startsWith("#!nimpretty"):
    case tok.literal
    of "#!nimpretty off":
      inc em.keepIndents
      wrNewline em
      em.lastLineNumber = tok.line + 1
    of "#!nimpretty on":
      dec em.keepIndents
      em.lastLineNumber = tok.line
    wrNewline em
    wr em, tok.literal, ltComment
    em.col = 0
    em.lineSpan = 0
    return

  var preventComment = false
  if tok.tokType == tkComment and tok.line == em.lastLineNumber:
    # we have an inline comment so handle it before the indentation token:
    emitComment(em, tok, dontIndent = (em.inSection == 0))
    preventComment = true
    em.fixedUntil = em.tokens.high

  elif tok.indent >= 0:
    var newlineKind = ltCrucialNewline
    if em.keepIndents > 0:
      em.indentLevel = tok.indent
    elif (em.lastTok in (splitters + oprSet) and
        tok.tokType notin (closedPars - {tkBracketDotRi})):
      if tok.tokType in openPars and tok.indent > em.indentStack[^1]:
        while em.indentStack[^1] < tok.indent:
          em.indentStack.add(em.indentStack[^1] + em.indWidth)
      while em.indentStack[^1] > tok.indent:
        discard em.indentStack.pop()

      # aka: we are in an expression context:
      let alignment = max(tok.indent - em.indentStack[^1], 0)
      em.indentLevel = alignment + em.indentStack.high * em.indWidth
      newlineKind = ltSplittingNewline
    else:
      if tok.indent > em.indentStack[^1]:
        em.indentStack.add tok.indent
      else:
        # dedent?
        while em.indentStack.len > 1 and em.indentStack[^1] > tok.indent:
          discard em.indentStack.pop()
      em.indentLevel = em.indentStack.high * em.indWidth
    #[ we only correct the indentation if it is not in an expression context,
       so that code like

        const splitters = {tkComma, tkSemicolon, tkParLe, tkParDotLe,
                          tkBracketLe, tkBracketLeColon, tkCurlyDotLe,
                          tkCurlyLe}

       is not touched.
    ]#
    # remove trailing whitespace:
    removeSpaces em
    wrNewline em, newlineKind
    for i in 2..tok.line - em.lastLineNumber: wrNewline(em)
    wrSpaces em, em.indentLevel
    em.fixedUntil = em.tokens.high

  var lastTokWasTerse = false
  case tok.tokType
  of tokKeywordLow..tokKeywordHigh:
    if endsInAlpha(em):
      wrSpace em
    elif not em.inquote and not endsInWhite(em) and
        em.lastTok notin (openPars+{tkOpr, tkDotDot}) and not em.lastTokWasTerse:
      #and tok.tokType in oprSet
      wrSpace em

    if not em.inquote:
      wr(em, $tok.tokType, ltKeyword)
      if tok.tokType in {tkAnd, tkOr, tkIn, tkNotin}:
        rememberSplit(splitIn)
        wrSpace em
    else:
      # keywords in backticks are not normalized:
      wr(em, tok.ident.s, ltIdent)

  of tkColon:
    wr(em, $tok.tokType, ltOther)
    wrSpace em
  of tkSemiColon, tkComma:
    wr(em, $tok.tokType, ltOther)
    rememberSplit(splitComma)
    wrSpace em
  of openPars:
    if tsLeading in tok.spacing and not em.endsInWhite and
        (not em.wasExportMarker or tok.tokType == tkCurlyDotLe):
      wrSpace em
    wr(em, $tok.tokType, ltSomeParLe)
    if tok.tokType != tkCurlyDotLe:
      rememberSplit(splitParLe)
  of closedPars:
    wr(em, $tok.tokType, ltSomeParRi)
  of tkColonColon:
    wr(em, $tok.tokType, ltOther)
  of tkDot:
    lastTokWasTerse = true
    wr(em, $tok.tokType, ltOther)
  of tkEquals:
    if not em.inquote and not em.endsInWhite: wrSpace(em)
    wr(em, $tok.tokType, ltOther)
    if not em.inquote: wrSpace(em)
  of tkOpr, tkDotDot:
    if em.inquote or (tok.spacing == {} and
        tok.ident.s notin ["<", ">", "<=", ">=", "==", "!="]):
      # bug #9504: remember to not spacify a keyword:
      lastTokWasTerse = true
      # if not surrounded by whitespace, don't produce any whitespace either:
      wr(em, tok.ident.s, ltOpr)
    else:
      if not em.endsInWhite: wrSpace(em)
      wr(em, tok.ident.s, ltOpr)
      template isUnary(tok): bool =
        tok.spacing == {tsLeading}

      if not isUnary(tok):
        rememberSplit(splitBinary)
        wrSpace(em)
  of tkAccent:
    if not em.inquote and endsInAlpha(em): wrSpace(em)
    wr(em, $tok.tokType, ltOther)
    em.inquote = not em.inquote
  of tkComment:
    if not preventComment:
      emitComment(em, tok, dontIndent = false)
  of tkIntLit..tkStrLit, tkRStrLit, tkTripleStrLit, tkGStrLit, tkGTripleStrLit, tkCharLit:
    if not em.inquote:
      let lit = fileSection(em.config, em.fid, tok.offsetA, tok.offsetB)
      if endsInAlpha(em) and tok.tokType notin {tkGStrLit, tkGTripleStrLit}: wrSpace(em)
      em.lineSpan = countNewlines(lit)
      if em.lineSpan > 0: calcCol(em, lit)
      wr em, lit, ltLit
    else:
      if endsInAlpha(em): wrSpace(em)
      wr em, tok.literal, ltLit
  of tkEof: discard
  else:
    let lit = if tok.ident != nil: tok.ident.s else: tok.literal
    if endsInAlpha(em): wrSpace(em)
    wr em, lit, ltIdent

  em.lastTok = tok.tokType
  em.lastTokWasTerse = lastTokWasTerse
  em.lastLineNumber = tok.line + em.lineSpan
  em.lineSpan = 0

proc endsWith(em: Emitter; k: varargs[string]): bool =
  if em.tokens.len < k.len: return false
  for i in 0..high(k):
    if em.tokens[em.tokens.len - k.len + i] != k[i]: return false
  return true

proc rfind(em: Emitter, t: string): int =
  for i in 1..5:
    if em.tokens[^i] == t:
      return i

proc starWasExportMarker*(em: var Emitter) =
  if em.endsWith(" ", "*", " "):
    setLen(em.tokens, em.tokens.len-3)
    setLen(em.kinds, em.kinds.len-3)
    em.tokens.add("*")
    em.kinds.add ltExportMarker
    dec em.col, 2

proc commaWasSemicolon*(em: var Emitter) =
  if em.semicolons == detectSemicolonKind:
    em.semicolons = if em.rfind(";") > 0: useSemicolon else: dontTouch
  if em.semicolons == useSemicolon:
    let commaPos = em.rfind(",")
    if commaPos > 0:
      em.tokens[^commaPos] = ";"

proc curlyRiWasPragma*(em: var Emitter) =
  if em.endsWith("}"):
    em.tokens[^1] = ".}"
    inc em.col

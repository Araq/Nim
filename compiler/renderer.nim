#
#
#           The Nim Compiler
#        (c) Copyright 2013 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# This module implements the renderer of the standard Nim representation.

# 'import renderer' is so useful for debugging
# that Nim shouldn't produce a warning for that:
{.used.}

import
  lexer, options, idents, ast, msgs, lineinfos, wordrecg

import std/[strutils]

when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions, formatfloat]

type
  TRenderFlag* = enum
    renderNone, renderNoBody, renderNoComments, renderDocComments,
    renderNoPragmas, renderIds, renderNoProcDefs, renderSyms, renderRunnableExamples,
    renderIr, renderNonExportedFields, renderExpandUsing, renderNoPostfix

  TRenderFlags* = set[TRenderFlag]
  TRenderTok* = object
    kind*: TokType
    length*: int16
    sym*: PSym

  Section = enum
    GenericParams
    ObjectDef

  TRenderTokSeq* = seq[TRenderTok]
  TSrcGen* = object
    indent*: int
    lineLen*: int
    col: int
    pos*: int              # current position for iteration over the buffer
    idx*: int              # current token index for iteration over the buffer
    tokens*: TRenderTokSeq
    buf*: string
    pendingNL*: int        # negative if not active; else contains the
                           # indentation value
    pendingWhitespace: int
    comStack*: seq[PNode]  # comment stack
    flags*: TRenderFlags
    inside: set[Section] # Keeps track of contexts we are in
    checkAnon: bool        # we're in a context that can contain sfAnon
    inPragma: int
    when defined(nimpretty):
      pendingNewlineCount: int
    fid*: FileIndex
    config*: ConfigRef
    mangler: seq[PSym]

proc renderTree*(n: PNode, renderFlags: TRenderFlags = {}): string

# We render the source code in a two phases: The first
# determines how long the subtree will likely be, the second
# phase appends to a buffer that will be the output.

proc disamb(g: var TSrcGen; s: PSym): int =
  # we group by 's.name.s' to compute the stable name ID.
  result = 0
  for i in 0 ..< g.mangler.len:
    if s == g.mangler[i]: return result
    if s.name.s == g.mangler[i].name.s: inc result
  g.mangler.add s

proc isKeyword*(i: PIdent): bool =
  if (i.id >= ord(tokKeywordLow) - ord(tkSymbol)) and
      (i.id <= ord(tokKeywordHigh) - ord(tkSymbol)):
    result = true
  else:
    result = false

proc isExported(n: PNode): bool =
  ## Checks if an ident is exported.
  ## This is meant to be used with idents in nkIdentDefs.
  case n.kind
  of nkPostfix:
    n[0].ident.s == "*" and n[1].kind == nkIdent
  of nkPragmaExpr:
    n[0].isExported()
  else: false

proc renderDefinitionName*(s: PSym, noQuotes = false): string =
  ## Returns the definition name of the symbol.
  ##
  ## If noQuotes is false the symbol may be returned in backticks. This will
  ## happen if the name happens to be a keyword or the first character is not
  ## part of the SymStartChars set.
  let x = s.name.s
  if noQuotes or (x[0] in SymStartChars and not renderer.isKeyword(s.name)):
    result = x
  else:
    result = '`' & x & '`'

template inside(g: var TSrcGen, section: Section, body: untyped) =
  ## Runs `body` with `section` included in `g.inside`.
  ## Removes it at the end of the body if `g` wasn't inside it
  ## before the template.
  let wasntInSection = section notin g.inside
  g.inside.incl section
  body
  if wasntInSection:
    g.inside.excl section

template outside(g: var TSrcGen, section: Section, body: untyped) =
  ## Temporarily removes `section` from `g.inside`. Adds it back
  ## at the end of the body if `g` was inside it before the template
  let wasInSection = section in g.inside
  g.inside.excl section
  body
  if wasInSection:
    g.inside.incl section

const
  IndentWidth = 2
  longIndentWid = IndentWidth * 2
  MaxLineLen = 80
  LineCommentColumn = 30

when defined(nimpretty):
  proc minmaxLine(n: PNode): (int, int) =
    case n.kind
    of nkTripleStrLit:
      result = (n.info.line.int, n.info.line.int + countLines(n.strVal))
    of nkCommentStmt:
      result = (n.info.line.int, n.info.line.int + countLines(n.comment))
    else:
      result = (n.info.line.int, n.info.line.int)
    for i in 0..<n.safeLen:
      let (currMin, currMax) = minmaxLine(n[i])
      if currMin < result[0]: result[0] = currMin
      if currMax > result[1]: result[1] = currMax

  proc lineDiff(a, b: PNode): int =
    result = minmaxLine(b)[0] - minmaxLine(a)[1]

proc initSrcGen(renderFlags: TRenderFlags; config: ConfigRef): TSrcGen =
  result = TSrcGen(comStack: @[], tokens: @[], indent: 0,
                   lineLen: 0, pos: 0, idx: 0, buf: "",
                   flags: renderFlags, pendingNL: -1,
                   pendingWhitespace: -1, inside: {},
                   config: config
                   )

proc addTok(g: var TSrcGen, kind: TokType, s: string; sym: PSym = nil) =
  g.tokens.add TRenderTok(kind: kind, length: int16(s.len), sym: sym)
  g.buf.add(s)
  if kind != tkSpaces:
    inc g.col, s.len

proc addPendingNL(g: var TSrcGen) =
  if g.pendingNL >= 0:
    when defined(nimpretty):
      let newlines = repeat("\n", clamp(g.pendingNewlineCount, 1, 3))
    else:
      const newlines = "\n"
    addTok(g, tkSpaces, newlines & spaces(g.pendingNL))
    g.lineLen = g.pendingNL
    g.col = g.pendingNL
    g.pendingNL = - 1
    g.pendingWhitespace = -1
  elif g.pendingWhitespace >= 0:
    addTok(g, tkSpaces, spaces(g.pendingWhitespace))
    g.pendingWhitespace = -1

proc putNL(g: var TSrcGen, indent: int) =
  if g.pendingNL >= 0: addPendingNL(g)
  else:
    addTok(g, tkSpaces, "\n")
    g.col = 0

  g.pendingNL = indent
  g.lineLen = indent
  g.pendingWhitespace = -1

proc previousNL(g: TSrcGen): bool =
  result = g.pendingNL >= 0 or (g.tokens.len > 0 and
                                g.tokens[^1].kind == tkSpaces)

proc putNL(g: var TSrcGen) =
  putNL(g, g.indent)

proc optNL(g: var TSrcGen, indent: int) =
  g.pendingNL = indent
  g.lineLen = indent
  g.col = g.indent
  when defined(nimpretty): g.pendingNewlineCount = 0

proc optNL(g: var TSrcGen) =
  optNL(g, g.indent)

proc optNL(g: var TSrcGen; a, b: PNode) =
  g.pendingNL = g.indent
  g.lineLen = g.indent
  g.col = g.indent
  when defined(nimpretty): g.pendingNewlineCount = lineDiff(a, b)

proc indentNL(g: var TSrcGen) =
  inc(g.indent, IndentWidth)
  g.pendingNL = g.indent
  g.lineLen = g.indent

proc dedent(g: var TSrcGen) =
  dec(g.indent, IndentWidth)
  assert(g.indent >= 0)
  if g.pendingNL > IndentWidth:
    dec(g.pendingNL, IndentWidth)
    dec(g.lineLen, IndentWidth)

proc put(g: var TSrcGen, kind: TokType, s: string; sym: PSym = nil) =
  if kind != tkSpaces:
    addPendingNL(g)
    if s.len > 0 or kind in {tkHideableStart, tkHideableEnd}:
      addTok(g, kind, s, sym)
  else:
    g.pendingWhitespace = s.len
    inc g.col, s.len
  inc(g.lineLen, s.len)

proc putComment(g: var TSrcGen, s: string) =
  if s.len == 0: return
  var i = 0
  let hi = s.len - 1
  let isCode = (s.len >= 2) and (s[1] != ' ')
  let ind = g.col
  var com = "## "
  while i <= hi:
    case s[i]
    of '\0':
      break
    of '\r':
      put(g, tkComment, com)
      com = "## "
      inc(i)
      if i <= hi and s[i] == '\n': inc(i)
      optNL(g, ind)
    of '\n':
      put(g, tkComment, com)
      com = "## "
      inc(i)
      optNL(g, ind)
    of ' ', '\t':
      com.add(s[i])
      inc(i)
    else:
      # we may break the comment into a multi-line comment if the line
      # gets too long:
      # compute length of the following word:
      var j = i
      while j <= hi and s[j] > ' ': inc(j)
      if not isCode and (g.col + (j - i) > MaxLineLen):
        put(g, tkComment, com)
        optNL(g, ind)
        com = "## "
      while i <= hi and s[i] > ' ':
        com.add(s[i])
        inc(i)
  put(g, tkComment, com)
  optNL(g)

proc maxLineLength(s: string): int =
  result = 0
  if s.len == 0: return 0
  var i = 0
  let hi = s.len - 1
  var lineLen = 0
  while i <= hi:
    case s[i]
    of '\0':
      break
    of '\r':
      inc(i)
      if i <= hi and s[i] == '\n': inc(i)
      result = max(result, lineLen)
      lineLen = 0
    of '\n':
      inc(i)
      result = max(result, lineLen)
      lineLen = 0
    else:
      inc(lineLen)
      inc(i)

proc putRawStr(g: var TSrcGen, kind: TokType, s: string) =
  var i = 0
  let hi = s.len - 1
  var str = ""
  while i <= hi:
    case s[i]
    of '\r':
      put(g, kind, str)
      str = ""
      inc(i)
      if i <= hi and s[i] == '\n': inc(i)
      optNL(g, 0)
    of '\n':
      put(g, kind, str)
      str = ""
      inc(i)
      optNL(g, 0)
    else:
      str.add(s[i])
      inc(i)
  put(g, kind, str)

proc containsNL(s: string): bool =
  for i in 0..<s.len:
    case s[i]
    of '\r', '\n':
      return true
    else:
      discard
  result = false

proc pushCom(g: var TSrcGen, n: PNode) =
  setLen(g.comStack, g.comStack.len + 1)
  g.comStack[^1] = n

proc popAllComs(g: var TSrcGen) =
  setLen(g.comStack, 0)

const
  Space = " "

proc shouldRenderComment(g: TSrcGen): bool {.inline.} =
  (renderNoComments notin g.flags or renderDocComments in g.flags)

proc shouldRenderComment(g: TSrcGen, n: PNode): bool {.inline.} =
  shouldRenderComment(g) and n.comment.len > 0

proc gcom(g: var TSrcGen, n: PNode) =
  assert(n != nil)
  if shouldRenderComment(g, n):
    var oneSpaceAdded = 0
    if (g.pendingNL < 0) and (g.buf.len > 0) and (g.buf[^1] != ' '):
      put(g, tkSpaces, Space)
      oneSpaceAdded = 1
      # Before long comments we cannot make sure that a newline is generated,
      # because this might be wrong. But it is no problem in practice.
    if (g.pendingNL < 0) and (g.buf.len > 0) and
        (g.col < LineCommentColumn):
      var ml = maxLineLength(n.comment)
      if ml + LineCommentColumn <= MaxLineLen:
        put(g, tkSpaces, spaces(LineCommentColumn - g.col))
        dec g.col, oneSpaceAdded
    putComment(g, n.comment)  #assert(g.comStack[high(g.comStack)] = n);

proc gcoms(g: var TSrcGen) =
  for i in 0..high(g.comStack): gcom(g, g.comStack[i])
  popAllComs(g)

proc lsub(g: TSrcGen; n: PNode): int
proc litAux(g: TSrcGen; n: PNode, x: BiggestInt, size: int): string =
  proc skip(t: PType): PType =
    result = t
    while result != nil and result.kind in {tyGenericInst, tyRange, tyVar,
                          tyLent, tyDistinct, tyOrdinal, tyAlias, tySink}:
      result = skipModifier(result)

  result = ""
  let typ = n.typ.skip
  if typ != nil and typ.kind in {tyBool, tyEnum}:
    if sfPure in typ.sym.flags:
      result = typ.sym.name.s & '.'
    let enumfields = typ.n
    # we need a slow linear search because of enums with holes:
    for e in items(enumfields):
      if e.sym.position == x:
        result &= e.sym.name.s
        return

  if nfBase2 in n.flags: result = "0b" & toBin(x, size * 8)
  elif nfBase8 in n.flags:
    var y = if size < sizeof(BiggestInt): x and ((1.BiggestInt shl (size*8)) - 1)
            else: x
    result = "0o" & toOct(y, size * 3)
  elif nfBase16 in n.flags: result = "0x" & toHex(x, size * 2)
  else: result = $x

proc ulitAux(g: TSrcGen; n: PNode, x: BiggestInt, size: int): string =
  if nfBase2 in n.flags: result = "0b" & toBin(x, size * 8)
  elif nfBase8 in n.flags: result = "0o" & toOct(x, size * 3)
  elif nfBase16 in n.flags: result = "0x" & toHex(x, size * 2)
  else: result = $cast[BiggestUInt](x)

proc atom(g: TSrcGen; n: PNode): string =
  when defined(nimpretty):
    doAssert g.config != nil, "g.config not initialized!"
    let comment = if n.info.commentOffsetA < n.info.commentOffsetB:
                    " " & fileSection(g.config, g.fid, n.info.commentOffsetA, n.info.commentOffsetB)
                  else:
                    ""
    if n.info.offsetA <= n.info.offsetB:
      # for some constructed tokens this can not be the case and we're better
      # off to not mess with the offset then.
      return fileSection(g.config, g.fid, n.info.offsetA, n.info.offsetB) & comment
  var f: float32
  case n.kind
  of nkEmpty: result = ""
  of nkIdent: result = n.ident.s
  of nkSym: result = n.sym.name.s
  of nkClosedSymChoice, nkOpenSymChoice: result = n[0].sym.name.s
  of nkStrLit: result = ""; result.addQuoted(n.strVal)
  of nkRStrLit: result = "r\"" & replace(n.strVal, "\"", "\"\"") & '\"'
  of nkTripleStrLit: result = "\"\"\"" & n.strVal & "\"\"\""
  of nkCharLit:
    result = "\'"
    result.addEscapedChar(chr(int(n.intVal)));
    result.add '\''
  of nkIntLit: result = litAux(g, n, n.intVal, 4)
  of nkInt8Lit: result = litAux(g, n, n.intVal, 1) & "\'i8"
  of nkInt16Lit: result = litAux(g, n, n.intVal, 2) & "\'i16"
  of nkInt32Lit: result = litAux(g, n, n.intVal, 4) & "\'i32"
  of nkInt64Lit: result = litAux(g, n, n.intVal, 8) & "\'i64"
  of nkUIntLit: result = ulitAux(g, n, n.intVal, 4) & "\'u"
  of nkUInt8Lit: result = ulitAux(g, n, n.intVal, 1) & "\'u8"
  of nkUInt16Lit: result = ulitAux(g, n, n.intVal, 2) & "\'u16"
  of nkUInt32Lit: result = ulitAux(g, n, n.intVal, 4) & "\'u32"
  of nkUInt64Lit: result = ulitAux(g, n, n.intVal, 8) & "\'u64"
  of nkFloatLit:
    if n.flags * {nfBase2, nfBase8, nfBase16} == {}: result = $(n.floatVal)
    else: result = litAux(g, n, (cast[ptr int64](addr(n.floatVal)))[] , 8)
  of nkFloat32Lit:
    if n.flags * {nfBase2, nfBase8, nfBase16} == {}:
      result = $n.floatVal & "\'f32"
    else:
      f = n.floatVal.float32
      result = litAux(g, n, (cast[ptr int32](addr(f)))[], 4) & "\'f32"
  of nkFloat64Lit:
    if n.flags * {nfBase2, nfBase8, nfBase16} == {}:
      result = $n.floatVal & "\'f64"
    else:
      result = litAux(g, n, (cast[ptr int64](addr(n.floatVal)))[], 8) & "\'f64"
  of nkFloat128Lit:
    if n.flags * {nfBase2, nfBase8, nfBase16} == {}:
      result = $n.floatVal & "\'f128"
    else:
      result = litAux(g, n, (cast[ptr int64](addr(n.floatVal)))[], 8) & "\'f128"
  of nkNilLit: result = "nil"
  of nkType:
    if (n.typ != nil) and (n.typ.sym != nil): result = n.typ.sym.name.s
    else: result = "[type node]"
  else:
    internalError(g.config, "renderer.atom " & $n.kind)
    result = ""

proc lcomma(g: TSrcGen; n: PNode, start: int = 0, theEnd: int = - 1): int =
  assert(theEnd < 0)
  result = 0
  for i in start..n.len + theEnd:
    let param = n[i]
    if nfDefaultParam notin param.flags:
      inc(result, lsub(g, param))
      inc(result, 2)          # for ``, ``
  if result > 0:
    dec(result, 2)            # last does not get a comma!

proc lsons(g: TSrcGen; n: PNode, start: int = 0, theEnd: int = - 1): int =
  assert(theEnd < 0)
  result = 0
  for i in start..n.len + theEnd: inc(result, lsub(g, n[i]))

proc origUsingType(n: PNode): PSym {.inline.} =
  ## Returns the type that a parameter references. Check with referencesUsing first
  ## to check `n` is actually referencing a using node
  # If the node is untyped the typ field will be nil
  if n[0].sym.typ != nil:
    n[0].sym.typ.sym
  else: nil

proc referencesUsing(n: PNode): bool =
  ## Returns true if n references a using statement.
  ## e.g. proc foo(x) # x doesn't have type or def value so it references a using
  result = n.kind == nkIdentDefs and
           # Sometimes the node might not have been semmed (e.g. doc0) and will be nkIdent instead
           n[0].kind == nkSym and
           # Templates/macros can have parameters with no type (But their orig type will be nil)
           n.origUsingType != nil and
           n[1].kind == nkEmpty and n[2].kind == nkEmpty

proc lsub(g: TSrcGen; n: PNode): int =
  # computes the length of a tree
  result = 0
  if isNil(n): return 0
  if shouldRenderComment(g, n): return MaxLineLen + 1
  case n.kind
  of nkEmpty: result = 0
  of nkTripleStrLit:
    if containsNL(n.strVal): result = MaxLineLen + 1
    else: result = atom(g, n).len
  of succ(nkEmpty)..pred(nkTripleStrLit), succ(nkTripleStrLit)..nkNilLit:
    result = atom(g, n).len
  of nkCall, nkBracketExpr, nkCurlyExpr, nkConv, nkPattern, nkObjConstr:
    result = lsub(g, n[0]) + lcomma(g, n, 1) + 2
  of nkHiddenStdConv, nkHiddenSubConv, nkHiddenCallConv: result = lsub(g, n[1])
  of nkCast: result = lsub(g, n[0]) + lsub(g, n[1]) + len("cast[]()")
  of nkAddr: result = (if n.len>0: lsub(g, n[0]) + len("addr()") else: 4)
  of nkStaticExpr: result = lsub(g, n[0]) + len("static_")
  of nkHiddenAddr, nkHiddenDeref, nkStringToCString, nkCStringToString: result = lsub(g, n[0])
  of nkCommand: result = lsub(g, n[0]) + lcomma(g, n, 1) + 1
  of nkExprEqExpr, nkAsgn, nkFastAsgn: result = lsons(g, n) + 3
  of nkPar, nkCurly, nkBracket, nkClosure: result = lcomma(g, n) + 2
  of nkTupleConstr:
    # assume the trailing comma:
    result = lcomma(g, n) + 3
  of nkArgList: result = lcomma(g, n)
  of nkTableConstr:
    result = if n.len > 0: lcomma(g, n) + 2 else: len("{:}")
  of nkClosedSymChoice, nkOpenSymChoice:
    if n.len > 0: result += lsub(g, n[0])
  of nkOpenSym: result = lsub(g, n[0])
  of nkTupleTy: result = lcomma(g, n) + len("tuple[]")
  of nkTupleClassTy: result = len("tuple")
  of nkDotExpr: result = lsons(g, n) + 1
  of nkBind: result = lsons(g, n) + len("bind_")
  of nkBindStmt: result = lcomma(g, n) + len("bind_")
  of nkMixinStmt: result = lcomma(g, n) + len("mixin_")
  of nkCheckedFieldExpr: result = lsub(g, n[0])
  of nkLambda: result = lsons(g, n) + len("proc__=_")
  of nkDo: result = lsons(g, n) + len("do__:_")
  of nkConstDef, nkIdentDefs:
    result = lcomma(g, n, 0, - 3)
    if n.referencesUsing:
      result += lsub(g, newSymNode(n.origUsingType)) + 2
    else:
      if n[^2].kind != nkEmpty: result += lsub(g, n[^2]) + 2
      if n[^1].kind != nkEmpty: result += lsub(g, n[^1]) + 3
  of nkVarTuple:
    if n[^1].kind == nkEmpty:
      result = lcomma(g, n, 0, - 2) + len("()")
    else:
      result = lcomma(g, n, 0, - 3) + len("() = ") + lsub(g, lastSon(n))
  of nkChckRangeF: result = len("chckRangeF") + 2 + lcomma(g, n)
  of nkChckRange64: result = len("chckRange64") + 2 + lcomma(g, n)
  of nkChckRange: result = len("chckRange") + 2 + lcomma(g, n)
  of nkObjDownConv, nkObjUpConv:
    result = 2
    if n.len >= 1: result += lsub(g, n[0])
    result += lcomma(g, n, 1)
  of nkExprColonExpr: result = lsons(g, n) + 2
  of nkInfix: result = lsons(g, n) + 2
  of nkPrefix:
    result = lsons(g, n)+1+(if n.len > 0 and n[1].kind == nkInfix: 2 else: 0)
  of nkPostfix:
    if renderNoPostfix notin g.flags:
      result = lsons(g, n)
    else:
      result = lsub(g, n[1])
  of nkCallStrLit: result = lsons(g, n)
  of nkPragmaExpr: result = lsub(g, n[0]) + lcomma(g, n, 1)
  of nkRange: result = lsons(g, n) + 2
  of nkDerefExpr: result = lsub(g, n[0]) + 2
  of nkAccQuoted: result = lsons(g, n) + 2
  of nkIfExpr:
    result = lsub(g, n[0][0]) + lsub(g, n[0][1]) + lsons(g, n, 1) +
        len("if_:_")
  of nkElifExpr: result = lsons(g, n) + len("_elif_:_")
  of nkElseExpr: result = lsub(g, n[0]) + len("_else:_") # type descriptions
  of nkTypeOfExpr: result = (if n.len > 0: lsub(g, n[0]) else: 0)+len("typeof()")
  of nkRefTy: result = (if n.len > 0: lsub(g, n[0])+1 else: 0) + len("ref")
  of nkPtrTy: result = (if n.len > 0: lsub(g, n[0])+1 else: 0) + len("ptr")
  of nkVarTy, nkOutTy: result = (if n.len > 0: lsub(g, n[0])+1 else: 0) + len("var")
  of nkDistinctTy:
    result = len("distinct") + (if n.len > 0: lsub(g, n[0])+1 else: 0)
    if n.len > 1:
      result += (if n[1].kind == nkWith: len("_with_") else: len("_without_"))
      result += lcomma(g, n[1])
  of nkStaticTy: result = (if n.len > 0: lsub(g, n[0]) else: 0) +
                                                         len("static[]")
  of nkTypeDef: result = lsons(g, n) + 3
  of nkOfInherit: result = lsub(g, n[0]) + len("of_")
  of nkProcTy: result = lsons(g, n) + len("proc_")
  of nkIteratorTy: result = lsons(g, n) + len("iterator_")
  of nkSinkAsgn: result = lsons(g, n) + len("`=sink`(, )")
  of nkEnumTy:
    if n.len > 0:
      result = lsub(g, n[0]) + lcomma(g, n, 1) + len("enum_")
    else:
      result = len("enum")
  of nkEnumFieldDef: result = lsons(g, n) + 3
  of nkVarSection, nkLetSection:
    if n.len > 1: result = MaxLineLen + 1
    else: result = lsons(g, n) + len("var_")
  of nkUsingStmt:
    if n.len > 1: result = MaxLineLen + 1
    else: result = lsons(g, n) + len("using_")
  of nkReturnStmt:
    if n.len > 0 and n[0].kind == nkAsgn and renderIr notin g.flags:
      result = len("return_") + lsub(g, n[0][1])
    else:
      result = len("return_") + lsub(g, n[0])
  of nkRaiseStmt: result = lsub(g, n[0]) + len("raise_")
  of nkYieldStmt: result = lsub(g, n[0]) + len("yield_")
  of nkDiscardStmt: result = lsub(g, n[0]) + len("discard_")
  of nkBreakStmt: result = lsub(g, n[0]) + len("break_")
  of nkContinueStmt: result = lsub(g, n[0]) + len("continue_")
  of nkPragma: result = lcomma(g, n) + 4
  of nkCommentStmt: result = n.comment.len
  of nkOfBranch: result = lcomma(g, n, 0, - 2) + lsub(g, lastSon(n)) + len("of_:_")
  of nkImportAs: result = lsub(g, n[0]) + len("_as_") + lsub(g, n[1])
  of nkElifBranch: result = lsons(g, n) + len("elif_:_")
  of nkElse: result = lsub(g, n[0]) + len("else:_")
  of nkFinally: result = lsub(g, n[0]) + len("finally:_")
  of nkGenericParams: result = lcomma(g, n) + 2
  of nkFormalParams:
    result = lcomma(g, n, 1) + 2
    if n[0].kind != nkEmpty: result += lsub(g, n[0]) + 2
  of nkExceptBranch:
    result = lcomma(g, n, 0, -2) + lsub(g, lastSon(n)) + len("except_:_")
  of nkObjectTy:
    result = len("object_")
  else: result = MaxLineLen + 1

proc fits(g: TSrcGen, x: int): bool =
  result = x <= MaxLineLen

type
  TSubFlag = enum
    rfLongMode, rfInConstExpr
  TSubFlags = set[TSubFlag]
  TContext = tuple[spacing: int, flags: TSubFlags]

const
  emptyContext: TContext = (spacing: 0, flags: {})

proc initContext(): TContext =
  result = (spacing: 0, flags: {})

proc gsub(g: var TSrcGen, n: PNode, c: TContext, fromStmtList = false)
proc gsub(g: var TSrcGen, n: PNode, fromStmtList = false) =
  var c: TContext = initContext()
  gsub(g, n, c, fromStmtList = fromStmtList)

proc hasCom(n: PNode): bool =
  result = false
  if n.isNil: return false
  if n.comment.len > 0: return true
  case n.kind
  of nkEmpty..nkNilLit: discard
  else:
    for i in 0..<n.len:
      if hasCom(n[i]): return true

proc putWithSpace(g: var TSrcGen, kind: TokType, s: string) =
  put(g, kind, s)
  put(g, tkSpaces, Space)

proc isHideable(config: ConfigRef, n: PNode): bool =
  # xxx compare `ident` directly with `getIdent(cache, wRaises)`, but
  # this requires a `cache`.
  case n.kind
  of nkExprColonExpr:
    result = n[0].kind == nkIdent and
             n[0].ident.s.nimIdentNormalize in ["raises", "tags", "extern", "deprecated", "forbids", "stacktrace"]
  of nkIdent: result = n.ident.s in ["gcsafe", "deprecated"]
  else: result = false

proc gcommaAux(g: var TSrcGen, n: PNode, ind: int, start: int = 0,
               theEnd: int = - 1, separator = tkComma) =
  let inPragma = g.inPragma == 1 # just the top-level
  var inHideable = false
  for i in start..n.len + theEnd:
    let c = i < n.len + theEnd
    let sublen = lsub(g, n[i]) + ord(c)
    if not fits(g, g.lineLen + sublen) and (ind + sublen < MaxLineLen): optNL(g, ind)
    let oldLen = g.tokens.len
    if inPragma:
      if not inHideable and isHideable(g.config, n[i]):
        inHideable = true
        put(g, tkHideableStart, "")
      elif inHideable and not isHideable(g.config, n[i]):
        inHideable = false
        put(g, tkHideableEnd, "")
    gsub(g, n[i])
    if c:
      if g.tokens.len > oldLen:
        putWithSpace(g, separator, $separator)
      if shouldRenderComment(g) and hasCom(n[i]):
        gcoms(g)
        optNL(g, ind)
  if inHideable:
    put(g, tkHideableEnd, "")
    inHideable = false

proc gcomma(g: var TSrcGen, n: PNode, c: TContext, start: int = 0,
            theEnd: int = -1) =
  var ind: int
  if rfInConstExpr in c.flags:
    ind = g.indent + IndentWidth
  else:
    ind = g.lineLen
    if ind > MaxLineLen div 2: ind = g.indent + longIndentWid
  gcommaAux(g, n, ind, start, theEnd)

proc gcomma(g: var TSrcGen, n: PNode, start: int = 0, theEnd: int = - 1) =
  var ind = g.lineLen
  if ind > MaxLineLen div 2: ind = g.indent + longIndentWid
  gcommaAux(g, n, ind, start, theEnd)

proc gsemicolon(g: var TSrcGen, n: PNode, start: int = 0, theEnd: int = - 1) =
  var ind = g.lineLen
  if ind > MaxLineLen div 2: ind = g.indent + longIndentWid
  gcommaAux(g, n, ind, start, theEnd, tkSemiColon)

proc gsons(g: var TSrcGen, n: PNode, c: TContext, start: int = 0,
           theEnd: int = - 1) =
  for i in start..n.len + theEnd: gsub(g, n[i], c)

proc gsection(g: var TSrcGen, n: PNode, c: TContext, kind: TokType,
              k: string) =
  if n.len == 0: return # empty var sections are possible
  putWithSpace(g, kind, k)
  gcoms(g)
  indentNL(g)
  for i in 0..<n.len:
    optNL(g)
    gsub(g, n[i], c)
    gcoms(g)
  dedent(g)

proc longMode(g: TSrcGen; n: PNode, start: int = 0, theEnd: int = - 1): bool =
  result = shouldRenderComment(g, n)
  if not result:
    # check further
    for i in start..n.len + theEnd:
      if (lsub(g, n[i]) > MaxLineLen):
        result = true
        break

proc gstmts(g: var TSrcGen, n: PNode, c: TContext, doIndent=true) =
  if n.kind == nkEmpty: return
  if n.kind in {nkStmtList, nkStmtListExpr, nkStmtListType}:
    if doIndent: indentNL(g)
    for i in 0..<n.len:
      if i > 0:
        optNL(g, n[i-1], n[i])
      else:
        optNL(g)
      if n[i].kind in {nkStmtList, nkStmtListExpr, nkStmtListType}:
        gstmts(g, n[i], c, doIndent=false)
      else:
        gsub(g, n[i], fromStmtList = true)
      gcoms(g)
    if doIndent: dedent(g)
  else:
    indentNL(g)
    gsub(g, n)
    gcoms(g)
    dedent(g)
    optNL(g)


proc gcond(g: var TSrcGen, n: PNode) =
  if n.kind == nkStmtListExpr:
    put(g, tkParLe, "(")
  gsub(g, n)
  if n.kind == nkStmtListExpr:
    put(g, tkParRi, ")")

proc gif(g: var TSrcGen, n: PNode) =
  var c: TContext = initContext()
  gcond(g, n[0][0])
  putWithSpace(g, tkColon, ":")
  if longMode(g, n) or (lsub(g, n[0][1]) + g.lineLen > MaxLineLen):
    incl(c.flags, rfLongMode)
  gcoms(g)                    # a good place for comments
  gstmts(g, n[0][1], c)
  for i in 1..<n.len:
    optNL(g)
    gsub(g, n[i], c)

proc gwhile(g: var TSrcGen, n: PNode) =
  var c: TContext = initContext()
  putWithSpace(g, tkWhile, "while")
  gcond(g, n[0])
  putWithSpace(g, tkColon, ":")
  if longMode(g, n) or (lsub(g, n[1]) + g.lineLen > MaxLineLen):
    incl(c.flags, rfLongMode)
  gcoms(g)                    # a good place for comments
  gstmts(g, n[1], c)

proc gpattern(g: var TSrcGen, n: PNode) =
  var c: TContext = initContext()
  put(g, tkCurlyLe, "{")
  if longMode(g, n) or (lsub(g, n[0]) + g.lineLen > MaxLineLen):
    incl(c.flags, rfLongMode)
  gcoms(g)                    # a good place for comments
  gstmts(g, n, c)
  put(g, tkCurlyRi, "}")

proc gpragmaBlock(g: var TSrcGen, n: PNode) =
  var c: TContext = initContext()
  gsub(g, n[0])
  putWithSpace(g, tkColon, ":")
  if longMode(g, n) or (lsub(g, n[1]) + g.lineLen > MaxLineLen):
    incl(c.flags, rfLongMode)
  gcoms(g)                    # a good place for comments
  gstmts(g, n[1], c)

proc gtry(g: var TSrcGen, n: PNode) =
  var c: TContext = initContext()
  put(g, tkTry, "try")
  putWithSpace(g, tkColon, ":")
  if longMode(g, n) or (lsub(g, n[0]) + g.lineLen > MaxLineLen):
    incl(c.flags, rfLongMode)
  gcoms(g)                    # a good place for comments
  gstmts(g, n[0], c)
  gsons(g, n, c, 1)

proc gfor(g: var TSrcGen, n: PNode) =
  var c: TContext = initContext()
  putWithSpace(g, tkFor, "for")
  if longMode(g, n) or
      (lsub(g, n[^1]) + lsub(g, n[^2]) + 6 + g.lineLen > MaxLineLen):
    incl(c.flags, rfLongMode)
  gcomma(g, n, c, 0, - 3)
  put(g, tkSpaces, Space)
  putWithSpace(g, tkIn, "in")
  gsub(g, n[^2], c)
  putWithSpace(g, tkColon, ":")
  gcoms(g)
  gstmts(g, n[^1], c)

proc gcase(g: var TSrcGen, n: PNode) =
  var c: TContext = initContext()
  if n.len == 0: return
  var last = if n[^1].kind == nkElse: -2 else: -1
  if longMode(g, n, 0, last): incl(c.flags, rfLongMode)
  putWithSpace(g, tkCase, "case")
  gcond(g, n[0])
  gcoms(g)
  optNL(g)
  gsons(g, n, c, 1, last)
  if last == - 2:
    c = initContext()
    if longMode(g, n[^1]): incl(c.flags, rfLongMode)
    gsub(g, n[^1], c)

proc genSymSuffix(result: var string, s: PSym) {.inline.} =
  if sfGenSym in s.flags and s.name.id != ord(wUnderscore):
    result.add '_'
    result.addInt s.id

proc gproc(g: var TSrcGen, n: PNode) =
  var c: TContext = initContext()
  if n[namePos].kind == nkSym:
    let s = n[namePos].sym
    var ret = renderDefinitionName(s)
    ret.genSymSuffix(s)
    put(g, tkSymbol, ret)
  else:
    gsub(g, n[namePos])

  if n[patternPos].kind != nkEmpty:
    gpattern(g, n[patternPos])
  g.inside(GenericParams):
    if renderNoBody in g.flags and n[miscPos].kind != nkEmpty and
        n[miscPos][1].kind != nkEmpty:
      gsub(g, n[miscPos][1])
    else:
      gsub(g, n[genericParamsPos])
  gsub(g, n[paramsPos])
  if renderNoPragmas notin g.flags:
    gsub(g, n[pragmasPos])
  if renderNoBody notin g.flags:
    if n.len > bodyPos and n[bodyPos].kind != nkEmpty:
      put(g, tkSpaces, Space)
      putWithSpace(g, tkEquals, "=")
      indentNL(g)
      gcoms(g)
      dedent(g)
      c = initContext()
      gstmts(g, n[bodyPos], c)
      putNL(g)
    else:
      indentNL(g)
      gcoms(g)
      dedent(g)

proc gTypeClassTy(g: var TSrcGen, n: PNode) =
  var c: TContext = initContext()
  putWithSpace(g, tkConcept, "concept")
  gsons(g, n[0], c) # arglist
  gsub(g, n[1]) # pragmas
  gsub(g, n[2]) # of
  gcoms(g)
  indentNL(g)
  gcoms(g)
  gstmts(g, n[3], c)
  dedent(g)

proc gblock(g: var TSrcGen, n: PNode) =
  # you shouldn't simplify it to `n.len < 2`
  # because the following codes should be executed
  # even when block stmt has only one child for getting
  # better error messages.
  if n.len == 0:
    return

  var c: TContext = initContext()

  if n[0].kind != nkEmpty:
    putWithSpace(g, tkBlock, "block")
    gsub(g, n[0])
  else:
    put(g, tkBlock, "block")

  # block stmt should have two children
  if n.len == 1:
    return

  putWithSpace(g, tkColon, ":")

  if longMode(g, n) or (lsub(g, n[1]) + g.lineLen > MaxLineLen):
    incl(c.flags, rfLongMode)
  gcoms(g)
  gstmts(g, n[1], c)

proc gstaticStmt(g: var TSrcGen, n: PNode) =
  var c: TContext = initContext()
  putWithSpace(g, tkStatic, "static")
  putWithSpace(g, tkColon, ":")
  if longMode(g, n) or (lsub(g, n[0]) + g.lineLen > MaxLineLen):
    incl(c.flags, rfLongMode)
  gcoms(g)                    # a good place for comments
  gstmts(g, n[0], c)

proc gasm(g: var TSrcGen, n: PNode) =
  putWithSpace(g, tkAsm, "asm")
  gsub(g, n[0])
  gcoms(g)
  if n.len > 1:
    gsub(g, n[1])

proc gident(g: var TSrcGen, n: PNode) =
  if GenericParams in g.inside and n.kind == nkSym:
    if sfAnon in n.sym.flags or
      (n.typ != nil and tfImplicitTypeParam in n.typ.flags): return

  var t: TokType
  var s = atom(g, n)
  if s.len > 0 and s[0] in lexer.SymChars:
    if n.kind == nkIdent:
      if (n.ident.id < ord(tokKeywordLow) - ord(tkSymbol)) or
          (n.ident.id > ord(tokKeywordHigh) - ord(tkSymbol)):
        t = tkSymbol
      else:
        t = TokType(n.ident.id + ord(tkSymbol))
    else:
      t = tkSymbol
  else:
    t = tkOpr
  if renderIr in g.flags and n.kind == nkSym:
    let localId = disamb(g, n.sym)
    if localId != 0 and n.sym.magic == mNone:
      s.add '_'
      s.addInt localId
    if sfCursor in n.sym.flags:
      s.add "_cursor"
  elif n.kind == nkSym and (renderIds in g.flags or
      (sfGenSym in n.sym.flags and n.sym.name.id != ord(wUnderscore)) or
      n.sym.kind == skTemp):
    s.add '_'
    s.addInt n.sym.id
    when defined(debugMagics):
      s.add '_'
      s.add $n.sym.magic
  put(g, t, s, if n.kind == nkSym and renderSyms in g.flags: n.sym else: nil)

proc doParamsAux(g: var TSrcGen, params: PNode) =
  if params.len > 1:
    put(g, tkParLe, "(")
    gsemicolon(g, params, 1)
    put(g, tkParRi, ")")

  if params.len > 0 and params[0].kind != nkEmpty:
    put(g, tkSpaces, Space)
    putWithSpace(g, tkOpr, "->")
    gsub(g, params[0])

proc gsub(g: var TSrcGen; n: PNode; i: int) =
  if i < n.len:
    gsub(g, n[i])
  else:
    put(g, tkOpr, "<<" & $i & "th child missing for " & $n.kind & " >>")

type
  BracketKind = enum
    bkNone, bkBracket, bkBracketAsgn, bkCurly, bkCurlyAsgn

proc bracketKind*(g: TSrcGen, n: PNode): BracketKind =
  if renderIds notin g.flags:
    case n.kind
    of nkClosedSymChoice, nkOpenSymChoice:
      if n.len > 0: result = bracketKind(g, n[0])
      else: result = bkNone
    of nkSym:
      result = case n.sym.name.s
        of "[]": bkBracket
        of "[]=": bkBracketAsgn
        of "{}": bkCurly
        of "{}=": bkCurlyAsgn
        else: bkNone
    else: result = bkNone
  else:
    result = bkNone

proc skipHiddenNodes(n: PNode): PNode =
  result = n
  while result != nil:
    if result.kind in {nkHiddenStdConv, nkHiddenSubConv, nkHiddenCallConv, nkOpenSym} and result.len > 1:
      result = result[1]
    elif result.kind in {nkCheckedFieldExpr, nkHiddenAddr, nkHiddenDeref, nkStringToCString, nkCStringToString} and
        result.len > 0:
      result = result[0]
    else: break

proc accentedName(g: var TSrcGen, n: PNode) =
  # This is for cases where ident should've really been a `nkAccQuoted`, e.g. `:tmp`
  # or if user writes a macro with `ident":foo"`. It's unclear whether these should be legal.
  const backticksNeeded = OpChars + {'[', '{', '\''}
  if n == nil: return
  let ident = n.getPIdent
  if ident != nil and ident.s[0] in backticksNeeded:
    put(g, tkAccent, "`")
    gident(g, n)
    put(g, tkAccent, "`")
  else:
    gsub(g, n)

proc infixArgument(g: var TSrcGen, n: PNode, i: int) =
  if i < 1 or i > 2: return
  var needsParenthesis = false
  let nNext = n[i].skipHiddenNodes
  if nNext.kind == nkInfix:
    if nNext[0].kind in {nkSym, nkIdent} and n[0].kind in {nkSym, nkIdent}:
      let nextId = if nNext[0].kind == nkSym: nNext[0].sym.name else: nNext[0].ident
      let nnId = if n[0].kind == nkSym: n[0].sym.name else: n[0].ident
      if i == 1:
        if getPrecedence(nextId) < getPrecedence(nnId):
          needsParenthesis = true
      elif i == 2:
        if getPrecedence(nextId) <= getPrecedence(nnId):
          needsParenthesis = true
  if needsParenthesis:
    put(g, tkParLe, "(")
  gsub(g, n, i)
  if needsParenthesis:
    put(g, tkParRi, ")")

const postExprBlocks = {nkStmtList, nkStmtListExpr,
  nkOfBranch, nkElifBranch, nkElse,
  nkExceptBranch, nkFinally, nkDo}

proc postStatements(g: var TSrcGen, n: PNode, i: int, fromStmtList: bool) =
  var i = i
  if n[i].kind in {nkStmtList, nkStmtListExpr}:
    if fromStmtList:
      put(g, tkColon, ":")
    else:
      put(g, tkSpaces, Space)
      put(g, tkDo, "do")
      put(g, tkColon, ":")
  gsub(g, n, i)
  i.inc
  for j in i ..< n.len:
    if n[j].kind == nkDo:
      optNL(g)
    elif n[j].kind in {nkStmtList, nkStmtListExpr}:
      optNL(g)
      put(g, tkDo, "do")
      put(g, tkColon, ":")
    gsub(g, n, j)

proc isCustomLit(n: PNode): bool =
  if n.len == 2 and n[0].kind == nkRStrLit:
    let ident = n[1].getPIdent
    result = ident != nil and ident.s.startsWith('\'')
  else:
    result = false

proc gsub(g: var TSrcGen, n: PNode, c: TContext, fromStmtList = false) =
  if isNil(n): return
  var
    a: TContext = default(TContext)
  if shouldRenderComment(g, n): pushCom(g, n)
  case n.kind                 # atoms:
  of nkTripleStrLit: put(g, tkTripleStrLit, atom(g, n))
  of nkEmpty: discard
  of nkType: put(g, tkInvalid, atom(g, n))
  of nkSym, nkIdent: gident(g, n)
  of nkIntLit: put(g, tkIntLit, atom(g, n))
  of nkInt8Lit: put(g, tkInt8Lit, atom(g, n))
  of nkInt16Lit: put(g, tkInt16Lit, atom(g, n))
  of nkInt32Lit: put(g, tkInt32Lit, atom(g, n))
  of nkInt64Lit: put(g, tkInt64Lit, atom(g, n))
  of nkUIntLit: put(g, tkUIntLit, atom(g, n))
  of nkUInt8Lit: put(g, tkUInt8Lit, atom(g, n))
  of nkUInt16Lit: put(g, tkUInt16Lit, atom(g, n))
  of nkUInt32Lit: put(g, tkUInt32Lit, atom(g, n))
  of nkUInt64Lit: put(g, tkUInt64Lit, atom(g, n))
  of nkFloatLit: put(g, tkFloatLit, atom(g, n))
  of nkFloat32Lit: put(g, tkFloat32Lit, atom(g, n))
  of nkFloat64Lit: put(g, tkFloat64Lit, atom(g, n))
  of nkFloat128Lit: put(g, tkFloat128Lit, atom(g, n))
  of nkStrLit: put(g, tkStrLit, atom(g, n))
  of nkRStrLit: put(g, tkRStrLit, atom(g, n))
  of nkCharLit: put(g, tkCharLit, atom(g, n))
  of nkNilLit: put(g, tkNil, atom(g, n))    # complex expressions
  of nkCall, nkConv, nkDotCall, nkPattern, nkObjConstr:
    if n.len > 1 and n.lastSon.kind in postExprBlocks:
      accentedName(g, n[0])
      var i = 1
      while i < n.len and n[i].kind notin postExprBlocks: i.inc
      if i > 1:
        put(g, tkParLe, "(")
        gcomma(g, n, 1, i - 1 - n.len)
        put(g, tkParRi, ")")
      postStatements(g, n, i, fromStmtList)
    elif n.len >= 1:
      case bracketKind(g, n[0])
      of bkBracket:
        gsub(g, n, 1)
        put(g, tkBracketLe, "[")
        gcomma(g, n, 2)
        put(g, tkBracketRi, "]")
      of bkBracketAsgn:
        gsub(g, n, 1)
        put(g, tkBracketLe, "[")
        gcomma(g, n, 2, -2)
        put(g, tkBracketRi, "]")
        put(g, tkSpaces, Space)
        putWithSpace(g, tkEquals, "=")
        gsub(g, n, n.len - 1)
      of bkCurly:
        gsub(g, n, 1)
        put(g, tkCurlyLe, "{")
        gcomma(g, n, 2)
        put(g, tkCurlyRi, "}")
      of bkCurlyAsgn:
        gsub(g, n, 1)
        put(g, tkCurlyLe, "{")
        gcomma(g, n, 2, -2)
        put(g, tkCurlyRi, "}")
        put(g, tkSpaces, Space)
        putWithSpace(g, tkEquals, "=")
        gsub(g, n, n.len - 1)
      of bkNone:
        accentedName(g, n[0])
        put(g, tkParLe, "(")
        gcomma(g, n, 1)
        put(g, tkParRi, ")")
    else:
      put(g, tkParLe, "(")
      put(g, tkParRi, ")")
  of nkCallStrLit:
    if n.len > 0: accentedName(g, n[0])
    if n.len > 1 and n[1].kind == nkRStrLit:
      put(g, tkRStrLit, '\"' & replace(n[1].strVal, "\"", "\"\"") & '\"')
    else:
      gsub(g, n, 1)
  of nkHiddenStdConv, nkHiddenSubConv:
    if n.len >= 2:
      when false:
        # if {renderIds, renderIr} * g.flags != {}:
        put(g, tkSymbol, "(conv)")
        put(g, tkParLe, "(")
        gsub(g, n[1])
        put(g, tkParRi, ")")
      else:
        gsub(g, n[1])
    else:
      put(g, tkSymbol, "(wrong conv)")
  of nkHiddenCallConv:
    if {renderIds, renderIr} * g.flags != {}:
      accentedName(g, n[0])
      put(g, tkParLe, "(")
      gcomma(g, n, 1)
      put(g, tkParRi, ")")
    elif n.len >= 2:
      gsub(g, n[1])
    else:
      put(g, tkSymbol, "(wrong conv)")
  of nkCast:
    put(g, tkCast, "cast")
    if n.len > 0 and n[0].kind != nkEmpty:
      put(g, tkBracketLe, "[")
      gsub(g, n, 0)
      put(g, tkBracketRi, "]")
    put(g, tkParLe, "(")
    gsub(g, n, 1)
    put(g, tkParRi, ")")
  of nkAddr:
    put(g, tkAddr, "addr")
    if n.len > 0:
      put(g, tkParLe, "(")
      gsub(g, n[0])
      put(g, tkParRi, ")")
  of nkStaticExpr:
    put(g, tkStatic, "static")
    put(g, tkSpaces, Space)
    gsub(g, n, 0)
  of nkBracketExpr:
    gsub(g, n, 0)
    put(g, tkBracketLe, "[")
    gcomma(g, n, 1)
    put(g, tkBracketRi, "]")
  of nkCurlyExpr:
    gsub(g, n, 0)
    put(g, tkCurlyLe, "{")
    gcomma(g, n, 1)
    put(g, tkCurlyRi, "}")
  of nkPragmaExpr:
    gsub(g, n, 0)
    gcomma(g, n, 1)
  of nkCommand:
    accentedName(g, n[0])
    put(g, tkSpaces, Space)
    if n.len > 1 and n.lastSon.kind in postExprBlocks:
      var i = 1
      while i < n.len and n[i].kind notin postExprBlocks: i.inc
      if i > 1:
        gcomma(g, n, 1, i - 1 - n.len)
      postStatements(g, n, i, fromStmtList)
    else:
      gcomma(g, n, 1)
  of nkExprEqExpr, nkAsgn, nkFastAsgn:
    gsub(g, n, 0)
    put(g, tkSpaces, Space)
    putWithSpace(g, tkEquals, "=")
    gsub(g, n, 1)
  of nkSinkAsgn:
    put(g, tkSymbol, "`=sink`")
    put(g, tkParLe, "(")
    gcomma(g, n)
    put(g, tkParRi, ")")
  of nkChckRangeF:
    put(g, tkSymbol, "chckRangeF")
    put(g, tkParLe, "(")
    gcomma(g, n)
    put(g, tkParRi, ")")
  of nkChckRange64:
    put(g, tkSymbol, "chckRange64")
    put(g, tkParLe, "(")
    gcomma(g, n)
    put(g, tkParRi, ")")
  of nkChckRange:
    put(g, tkSymbol, "chckRange")
    put(g, tkParLe, "(")
    gcomma(g, n)
    put(g, tkParRi, ")")
  of nkObjDownConv, nkObjUpConv:
    let typ = if (n.typ != nil) and (n.typ.sym != nil): n.typ.sym.name.s else: ""
    put(g, tkParLe, typ & "(")
    if n.len >= 1: gsub(g, n[0])
    put(g, tkParRi, ")")
  of nkClosedSymChoice, nkOpenSymChoice:
    if renderIds in g.flags:
      put(g, tkParLe, "(")
      for i in 0..<n.len:
        if i > 0: put(g, tkOpr, "|")
        if n[i].kind == nkSym:
          let s = n[i].sym
          if s.owner != nil:
            put g, tkSymbol, n[i].sym.owner.name.s
            put g, tkOpr, "."
          put g, tkSymbol, n[i].sym.name.s
        else:
          gsub(g, n[i], c)
      put(g, tkParRi, if n.kind == nkOpenSymChoice: "|...)" else: ")")
    else:
      gsub(g, n, 0)
  of nkOpenSym: gsub(g, n, 0)
  of nkPar, nkClosure:
    put(g, tkParLe, "(")
    gcomma(g, n, c)
    put(g, tkParRi, ")")
  of nkTupleConstr:
    put(g, tkParLe, "(")
    gcomma(g, n, c)
    if n.len == 1 and n[0].kind != nkExprColonExpr: put(g, tkComma, ",")
    put(g, tkParRi, ")")
  of nkCurly:
    put(g, tkCurlyLe, "{")
    gcomma(g, n, c)
    put(g, tkCurlyRi, "}")
  of nkArgList:
    gcomma(g, n, c)
  of nkTableConstr:
    put(g, tkCurlyLe, "{")
    if n.len > 0: gcomma(g, n, c)
    else: put(g, tkColon, ":")
    put(g, tkCurlyRi, "}")
  of nkBracket:
    put(g, tkBracketLe, "[")
    gcomma(g, n, c)
    put(g, tkBracketRi, "]")
  of nkDotExpr:
    if isCustomLit(n):
      put(g, tkCustomLit, n[0].strVal)
      gsub(g, n, 1)
    else:
      for i in 0..<n.len-1:
        gsub(g, n, i)
      put(g, tkDot, ".")
      if n.len > 1:
        accentedName(g, n[^1])
  of nkBind:
    putWithSpace(g, tkBind, "bind")
    gsub(g, n, 0)
  of nkCheckedFieldExpr, nkHiddenAddr, nkHiddenDeref, nkStringToCString, nkCStringToString:
    if renderIds in g.flags:
      put(g, tkAddr, $n.kind)
      put(g, tkParLe, "(")
    gsub(g, n, 0)
    if renderIds in g.flags:
      put(g, tkParRi, ")")

  of nkLambda:
    putWithSpace(g, tkProc, "proc")
    gsub(g, n, paramsPos)
    gsub(g, n, pragmasPos)
    put(g, tkSpaces, Space)
    putWithSpace(g, tkEquals, "=")
    gsub(g, n, bodyPos)
  of nkDo:
    putWithSpace(g, tkDo, "do")
    if paramsPos < n.len:
      doParamsAux(g, n[paramsPos])
    gsub(g, n, pragmasPos)
    put(g, tkColon, ":")
    gsub(g, n, bodyPos)
  of nkIdentDefs:
    var exclFlags: TRenderFlags = {}
    if ObjectDef in g.inside:
      if not n[0].isExported() and renderNonExportedFields notin g.flags:
        # Skip if this is a property in a type and its not exported
        # (While also not allowing rendering of non exported fields)
        return
      # render postfix for object fields:
      exclFlags = g.flags * {renderNoPostfix}
    # We render the identDef without being inside the section incase we render something like
    # y: proc (x: string) # (We wouldn't want to check if x is exported)
    g.outside(ObjectDef):
      g.flags.excl(exclFlags)
      gcomma(g, n, 0, -3)
      g.flags.incl(exclFlags)
      if n.len >= 2 and n[^2].kind != nkEmpty:
        putWithSpace(g, tkColon, ":")
        gsub(g, n[^2], c)
      elif n.referencesUsing and renderExpandUsing in g.flags:
        putWithSpace(g, tkColon, ":")
        gsub(g, newSymNode(n.origUsingType), c)

      if n.len >= 1 and n[^1].kind != nkEmpty:
        put(g, tkSpaces, Space)
        putWithSpace(g, tkEquals, "=")
        gsub(g, n[^1], c)
  of nkConstDef:
    gcomma(g, n, 0, -3)
    if n.len >= 2 and n[^2].kind != nkEmpty:
      putWithSpace(g, tkColon, ":")
      gsub(g, n[^2], c)

    if n.len >= 1 and n[^1].kind != nkEmpty:
      put(g, tkSpaces, Space)
      putWithSpace(g, tkEquals, "=")
      gsub(g, n[^1], c)
  of nkVarTuple:
    if n[^1].kind == nkEmpty:
      put(g, tkParLe, "(")
      gcomma(g, n, 0, -2)
      put(g, tkParRi, ")")
    else:
      put(g, tkParLe, "(")
      gcomma(g, n, 0, -3)
      put(g, tkParRi, ")")
      put(g, tkSpaces, Space)
      putWithSpace(g, tkEquals, "=")
      gsub(g, lastSon(n), c)
  of nkExprColonExpr:
    gsub(g, n, 0)
    putWithSpace(g, tkColon, ":")
    gsub(g, n, 1)
  of nkInfix:
    if n.len < 3:
      var i = 0
      put(g, tkOpr, "Too few children for nkInfix")
      return
    let oldLineLen = g.lineLen # we cache this because lineLen gets updated below
    infixArgument(g, n, 1)
    put(g, tkSpaces, Space)
    gsub(g, n, 0)        # binary operator
    # e.g.: `n1 == n2` decompses as following sum:
    if n.len == 3 and not fits(g, oldLineLen + lsub(g, n[1]) + lsub(g, n[2]) + lsub(g, n[0]) + len("  ")):
      optNL(g, g.indent + longIndentWid)
    else:
      put(g, tkSpaces, Space)
    infixArgument(g, n, 2)
    if n.len > 3 and n.lastSon.kind in postExprBlocks:
      var i = 3
      while i < n.len and n[i].kind notin postExprBlocks: i.inc
      postStatements(g, n, i, fromStmtList)
  of nkPrefix:
    gsub(g, n, 0)
    if n.len > 1:
      let opr = if n[0].kind == nkIdent: n[0].ident
                elif n[0].kind == nkSym: n[0].sym.name
                elif n[0].kind in {nkOpenSymChoice, nkClosedSymChoice}: n[0][0].sym.name
                else: nil
      let nNext = skipHiddenNodes(n[1])
      if nNext.kind == nkPrefix or (opr != nil and renderer.isKeyword(opr)):
        put(g, tkSpaces, Space)
      if nNext.kind == nkInfix:
        put(g, tkParLe, "(")
        gsub(g, n[1])
        put(g, tkParRi, ")")
      else:
        gsub(g, n[1])
    if n.len > 2 and n.lastSon.kind in postExprBlocks:
      var i = 2
      while i < n.len and n[i].kind notin postExprBlocks: i.inc
      postStatements(g, n, i, fromStmtList)
  of nkPostfix:
    gsub(g, n, 1)
    if renderNoPostfix notin g.flags:
      gsub(g, n, 0)
  of nkRange:
    gsub(g, n, 0)
    put(g, tkDotDot, "..")
    gsub(g, n, 1)
  of nkDerefExpr:
    gsub(g, n, 0)
    put(g, tkOpr, "[]")
  of nkAccQuoted:
    put(g, tkAccent, "`")
    for i in 0..<n.len:
      proc isAlpha(n: PNode): bool =
        if n.kind in {nkIdent, nkSym}:
          let tmp = n.getPIdent.s
          result = tmp.len > 0 and tmp[0] in {'a'..'z', 'A'..'Z'}
        else:
          result = false
      var useSpace = false
      if i == 1 and n[0].kind == nkIdent and n[0].ident.s in ["=", "'"]:
        if not n[1].isAlpha: # handle `=destroy`, `'big'
          useSpace = true
      elif i == 1 and n[1].kind == nkIdent and n[1].ident.s == "=":
        if not n[0].isAlpha: # handle setters, e.g. `foo=`
          useSpace = true
      elif i > 0: useSpace = true
      if useSpace:  put(g, tkSpaces, Space)
      gsub(g, n[i])
    put(g, tkAccent, "`")
  of nkIfExpr:
    putWithSpace(g, tkIf, "if")
    if n.len > 0: gcond(g, n[0][0])
    putWithSpace(g, tkColon, ":")
    if n.len > 0: gsub(g, n[0], 1)
    gsons(g, n, emptyContext, 1)
  of nkElifExpr:
    putWithSpace(g, tkElif, " elif")
    gcond(g, n[0])
    putWithSpace(g, tkColon, ":")
    gsub(g, n, 1)
  of nkElseExpr:
    put(g, tkElse, " else")
    putWithSpace(g, tkColon, ":")
    gsub(g, n, 0)
  of nkTypeOfExpr:
    put(g, tkType, "typeof")
    put(g, tkParLe, "(")
    if n.len > 0: gsub(g, n[0])
    put(g, tkParRi, ")")
  of nkRefTy:
    if n.len > 0:
      putWithSpace(g, tkRef, "ref")
      gsub(g, n[0])
    else:
      put(g, tkRef, "ref")
  of nkPtrTy:
    if n.len > 0:
      putWithSpace(g, tkPtr, "ptr")
      gsub(g, n[0])
    else:
      put(g, tkPtr, "ptr")
  of nkVarTy:
    if n.len > 0:
      putWithSpace(g, tkVar, "var")
      gsub(g, n[0])
    else:
      put(g, tkVar, "var")
  of nkOutTy:
    if n.len > 0:
      putWithSpace(g, tkOut, "out")
      gsub(g, n[0])
    else:
      put(g, tkOut, "out")
  of nkDistinctTy:
    if n.len > 0:
      putWithSpace(g, tkDistinct, "distinct")
      gsub(g, n[0])
      if n.len > 1:
        if n[1].kind == nkWith:
          putWithSpace(g, tkSymbol, " with")
        else:
          putWithSpace(g, tkSymbol, " without")
        gcomma(g, n[1])
    else:
      put(g, tkDistinct, "distinct")
  of nkTypeDef:
    if n[0].kind == nkPragmaExpr:
      # generate pragma after generic
      gsub(g, n[0], 0)
      gsub(g, n, 1)
      gsub(g, n[0], 1)
    else:
      gsub(g, n, 0)
      gsub(g, n, 1)
    put(g, tkSpaces, Space)
    if n.len > 2 and n[2].kind != nkEmpty:
      putWithSpace(g, tkEquals, "=")
      gsub(g, n[2])
  of nkObjectTy:
    if n.len > 0:
      putWithSpace(g, tkObject, "object")
      g.inside(ObjectDef):
        gsub(g, n[0])
        gsub(g, n[1])
        gcoms(g)
        indentNL(g)
        gsub(g, n[2])
        dedent(g)
    else:
      put(g, tkObject, "object")
  of nkRecList:
    for i in 0..<n.len:
      optNL(g)
      gsub(g, n[i], c)
      gcoms(g)
  of nkOfInherit:
    putWithSpace(g, tkOf, "of")
    gsub(g, n, 0)
  of nkProcTy:
    if n.len > 0:
      putWithSpace(g, tkProc, "proc")
      gsub(g, n, 0)
      gsub(g, n, 1)
    else:
      put(g, tkProc, "proc")
  of nkIteratorTy:
    if n.len > 0:
      putWithSpace(g, tkIterator, "iterator")
      gsub(g, n, 0)
      gsub(g, n, 1)
    else:
      put(g, tkIterator, "iterator")
  of nkStaticTy:
    put(g, tkStatic, "static")
    put(g, tkBracketLe, "[")
    if n.len > 0:
      gsub(g, n[0])
    put(g, tkBracketRi, "]")
  of nkEnumTy:
    if n.len > 0:
      putWithSpace(g, tkEnum, "enum")
      gsub(g, n[0])
      gcoms(g)
      indentNL(g)
      gcommaAux(g, n, g.indent, 1)
      gcoms(g)                  # BUGFIX: comment for the last enum field
      dedent(g)
    else:
      put(g, tkEnum, "enum")
  of nkEnumFieldDef:
    gsub(g, n, 0)
    put(g, tkSpaces, Space)
    putWithSpace(g, tkEquals, "=")
    gsub(g, n, 1)
  of nkStmtList, nkStmtListExpr, nkStmtListType:
    if n.len == 1 and n[0].kind == nkDiscardStmt:
      put(g, tkParLe, "(")
      gsub(g, n[0])
      put(g, tkParRi, ")")
    else:
      gstmts(g, n, emptyContext)
  of nkIfStmt:
    putWithSpace(g, tkIf, "if")
    gif(g, n)
  of nkWhen, nkRecWhen:
    putWithSpace(g, tkWhen, "when")
    gif(g, n)
  of nkWhileStmt: gwhile(g, n)
  of nkPragmaBlock: gpragmaBlock(g, n)
  of nkCaseStmt, nkRecCase: gcase(g, n)
  of nkTryStmt, nkHiddenTryStmt: gtry(g, n)
  of nkForStmt, nkParForStmt: gfor(g, n)
  of nkBlockStmt, nkBlockExpr: gblock(g, n)
  of nkStaticStmt: gstaticStmt(g, n)
  of nkAsmStmt: gasm(g, n)
  of nkProcDef:
    if renderNoProcDefs notin g.flags: putWithSpace(g, tkProc, "proc")
    gproc(g, n)
  of nkFuncDef:
    if renderNoProcDefs notin g.flags: putWithSpace(g, tkFunc, "func")
    gproc(g, n)
  of nkConverterDef:
    if renderNoProcDefs notin g.flags: putWithSpace(g, tkConverter, "converter")
    gproc(g, n)
  of nkMethodDef:
    if renderNoProcDefs notin g.flags: putWithSpace(g, tkMethod, "method")
    gproc(g, n)
  of nkIteratorDef:
    if renderNoProcDefs notin g.flags: putWithSpace(g, tkIterator, "iterator")
    gproc(g, n)
  of nkMacroDef:
    if renderNoProcDefs notin g.flags: putWithSpace(g, tkMacro, "macro")
    gproc(g, n)
  of nkTemplateDef:
    if renderNoProcDefs notin g.flags: putWithSpace(g, tkTemplate, "template")
    gproc(g, n)
  of nkTypeSection:
    gsection(g, n, emptyContext, tkType, "type")
  of nkConstSection:
    a = initContext()
    incl(a.flags, rfInConstExpr)
    gsection(g, n, a, tkConst, "const")
  of nkVarSection, nkLetSection, nkUsingStmt:
    if n.len == 0: return
    if n.kind == nkVarSection: putWithSpace(g, tkVar, "var")
    elif n.kind == nkLetSection: putWithSpace(g, tkLet, "let")
    else: putWithSpace(g, tkUsing, "using")
    if n.len > 1:
      gcoms(g)
      indentNL(g)
      for i in 0..<n.len:
        optNL(g)
        gsub(g, n[i])
        gcoms(g)
      dedent(g)
    else:
      gsub(g, n[0])
  of nkReturnStmt:
    putWithSpace(g, tkReturn, "return")
    if n.len > 0 and n[0].kind == nkAsgn and renderIr notin g.flags:
      gsub(g, n[0], 1)
    else:
      gsub(g, n, 0)
  of nkRaiseStmt:
    putWithSpace(g, tkRaise, "raise")
    gsub(g, n, 0)
  of nkYieldStmt:
    putWithSpace(g, tkYield, "yield")
    gsub(g, n, 0)
  of nkDiscardStmt:
    putWithSpace(g, tkDiscard, "discard")
    gsub(g, n, 0)
  of nkBreakStmt:
    putWithSpace(g, tkBreak, "break")
    gsub(g, n, 0)
  of nkContinueStmt:
    putWithSpace(g, tkContinue, "continue")
    gsub(g, n, 0)
  of nkPragma:
    if g.inPragma <= 0:
      inc g.inPragma
      #if not previousNL(g):
      put(g, tkSpaces, Space)
      put(g, tkCurlyDotLe, "{.")
      gcomma(g, n, emptyContext)
      put(g, tkCurlyDotRi, ".}")
      dec g.inPragma
    else:
      gcomma(g, n, emptyContext)
  of nkImportStmt, nkExportStmt:
    if n.kind == nkImportStmt:
      putWithSpace(g, tkImport, "import")
    else:
      putWithSpace(g, tkExport, "export")
    gcoms(g)
    indentNL(g)
    gcommaAux(g, n, g.indent)
    dedent(g)
    putNL(g)
  of nkImportExceptStmt, nkExportExceptStmt:
    if n.kind == nkImportExceptStmt:
      putWithSpace(g, tkImport, "import")
    else:
      putWithSpace(g, tkExport, "export")
    gsub(g, n, 0)
    put(g, tkSpaces, Space)
    putWithSpace(g, tkExcept, "except")
    gcommaAux(g, n, g.indent, 1)
    gcoms(g)
    putNL(g)
  of nkFromStmt:
    putWithSpace(g, tkFrom, "from")
    gsub(g, n, 0)
    put(g, tkSpaces, Space)
    putWithSpace(g, tkImport, "import")
    gcomma(g, n, emptyContext, 1)
    putNL(g)
  of nkIncludeStmt:
    putWithSpace(g, tkInclude, "include")
    gcoms(g)
    indentNL(g)
    gcommaAux(g, n, g.indent)
    dedent(g)
    putNL(g)
  of nkCommentStmt:
    gcoms(g)
    optNL(g)
  of nkOfBranch:
    optNL(g)
    putWithSpace(g, tkOf, "of")
    gcomma(g, n, c, 0, - 2)
    putWithSpace(g, tkColon, ":")
    gcoms(g)
    gstmts(g, lastSon(n), c)
  of nkImportAs:
    gsub(g, n, 0)
    put(g, tkSpaces, Space)
    putWithSpace(g, tkAs, "as")
    gsub(g, n, 1)
  of nkBindStmt:
    putWithSpace(g, tkBind, "bind")
    gcomma(g, n, c)
  of nkMixinStmt:
    putWithSpace(g, tkMixin, "mixin")
    gcomma(g, n, c)
  of nkElifBranch:
    optNL(g)
    putWithSpace(g, tkElif, "elif")
    gsub(g, n, 0)
    putWithSpace(g, tkColon, ":")
    gcoms(g)
    gstmts(g, n[1], c)
  of nkElse:
    optNL(g)
    put(g, tkElse, "else")
    putWithSpace(g, tkColon, ":")
    gcoms(g)
    gstmts(g, n[0], c)
  of nkFinally, nkDefer:
    optNL(g)
    if n.kind == nkFinally:
      put(g, tkFinally, "finally")
    else:
      put(g, tkDefer, "defer")
    putWithSpace(g, tkColon, ":")
    gcoms(g)
    gstmts(g, n[0], c)
  of nkExceptBranch:
    optNL(g)
    if n.len != 1:
      putWithSpace(g, tkExcept, "except")
    else:
      put(g, tkExcept, "except")
    gcomma(g, n, 0, -2)
    putWithSpace(g, tkColon, ":")
    gcoms(g)
    gstmts(g, lastSon(n), c)
  of nkGenericParams:
    proc hasExplicitParams(gp: PNode): bool =
      for p in gp:
        if p.typ == nil or tfImplicitTypeParam notin p.typ.flags:
          return true
      return false

    if n.hasExplicitParams:
      put(g, tkBracketLe, "[")
      gsemicolon(g, n)
      put(g, tkBracketRi, "]")
  of nkFormalParams:
    put(g, tkParLe, "(")
    gsemicolon(g, n, 1)
    put(g, tkParRi, ")")
    if n.len > 0 and n[0].kind != nkEmpty:
      putWithSpace(g, tkColon, ":")
      gsub(g, n[0])
  of nkTupleTy:
    put(g, tkTuple, "tuple")
    put(g, tkBracketLe, "[")
    gcomma(g, n)
    put(g, tkBracketRi, "]")
  of nkTupleClassTy:
    put(g, tkTuple, "tuple")
  of nkComesFrom:
    put(g, tkParLe, "(ComesFrom|")
    gsub(g, n, 0)
    put(g, tkParRi, ")")
  of nkGotoState:
    var c: TContext = initContext()
    putWithSpace g, tkSymbol, "goto"
    gsons(g, n, c)
  of nkState:
    var c: TContext = initContext()
    putWithSpace g, tkSymbol, "state"
    gsub(g, n[0], c)
    putWithSpace(g, tkColon, ":")
    indentNL(g)
    gsons(g, n, c, 1)
    dedent(g)

  of nkBreakState:
    put(g, tkTuple, "breakstate")
    if renderIds in g.flags:
      gsons(g, n, c, 0)
  of nkTypeClassTy:
    gTypeClassTy(g, n)
  of nkError:
    putWithSpace(g, tkSymbol, "error")
    #gcomma(g, n, c)
    gsub(g, n[0], c)
  else:
    #nkNone, nkExplicitTypeListCall:
    internalError(g.config, n.info, "renderer.gsub(" & $n.kind & ')')

proc renderTree*(n: PNode, renderFlags: TRenderFlags = {}): string =
  if n == nil: return "<nil tree>"
  var g: TSrcGen = initSrcGen(renderFlags, newPartialConfigRef())
  # do not indent the initial statement list so that
  # writeFile("file.nim", repr n)
  # produces working Nim code:
  if n.kind in {nkStmtList, nkStmtListExpr, nkStmtListType}:
    gstmts(g, n, emptyContext, doIndent = false)
  else:
    gsub(g, n)
  result = g.buf

proc `$`*(n: PNode): string = n.renderTree

proc renderModule*(n: PNode, outfile: string,
                   renderFlags: TRenderFlags = {};
                   fid = FileIndex(-1);
                   conf: ConfigRef = nil) =
  var
    f: File = default(File)
    g: TSrcGen = initSrcGen(renderFlags, conf)
  g.fid = fid
  for i in 0..<n.len:
    gsub(g, n[i])
    optNL(g)
    case n[i].kind
    of nkTypeSection, nkConstSection, nkVarSection, nkLetSection,
       nkCommentStmt: putNL(g)
    else: discard
  gcoms(g)
  if open(f, outfile, fmWrite):
    write(f, g.buf)
    close(f)
  else:
    rawMessage(g.config, errGenerated, "cannot open file: " & outfile)

proc initTokRender*(n: PNode, renderFlags: TRenderFlags = {}): TSrcGen =
  result = initSrcGen(renderFlags, newPartialConfigRef())
  gsub(result, n)

proc getNextTok*(r: var TSrcGen, kind: var TokType, literal: var string) =
  if r.idx < r.tokens.len:
    kind = r.tokens[r.idx].kind
    let length = r.tokens[r.idx].length.int
    literal = substr(r.buf, r.pos, r.pos + length - 1)
    inc(r.pos, length)
    inc(r.idx)
  else:
    kind = tkEof

proc getTokSym*(r: TSrcGen): PSym =
  if r.idx > 0 and r.idx <= r.tokens.len:
    result = r.tokens[r.idx-1].sym
  else:
    result = nil

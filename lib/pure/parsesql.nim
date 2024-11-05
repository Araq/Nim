#
#
#            Nim's Runtime Library
#        (c) Copyright 2009 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## The `parsesql` module implements a high performance SQL file
## parser. It parses PostgreSQL syntax and the SQL ANSI standard.
##
## Unstable API.

import std/[strutils, lexbase]
import std/private/decode_helpers

when defined(nimPreviewSlimSystem):
  import std/assertions

# ------------------- scanner -------------------------------------------------

type
  TokKind = enum            ## enumeration of all SQL tokens
    tkInvalid,              ## invalid token
    tkEof,                  ## end of file reached
    tkIdentifier,           ## abc
    tkQuotedIdentifier,     ## "abc"
    tkStringConstant,       ## 'abc'
    tkEscapeConstant,       ## e'abc'
    tkDollarQuotedConstant, ## $tag$abc$tag$
    tkBitStringConstant,    ## B'00011'
    tkHexStringConstant,    ## x'00011'
    tkInteger,
    tkNumeric,
    tkOperator,             ## + - * / < > = ~ ! @ # % ^ & | ` ?
    tkSemicolon,            ## ';'
    tkColon,                ## ':'
    tkComma,                ## ','
    tkParLe,                ## '('
    tkParRi,                ## ')'
    tkBracketLe,            ## '['
    tkBracketRi,            ## ']'
    tkDot                   ## '.'

  Token = object    # a token
    kind: TokKind   # the type of the token
    literal: string # the parsed (string) literal

  SqlLexer* = object of BaseLexer ## the parser object.
    filename: string

const
  tokKindToStr: array[TokKind, string] = [
    "invalid", "[EOF]", "identifier", "quoted identifier", "string constant",
    "escape string constant", "dollar quoted constant", "bit string constant",
    "hex string constant", "integer constant", "numeric constant", "operator",
    ";", ":", ",", "(", ")", "[", "]", "."
  ]

  reservedKeywords = @[
    # statements
    "select", "from", "where", "group", "limit", "offset", "having",
    # functions
    "count",
  ]

proc close(L: var SqlLexer) =
  lexbase.close(L)

proc getColumn(L: SqlLexer): int =
  ## get the current column the parser has arrived at.
  result = getColNumber(L, L.bufpos)

proc getLine(L: SqlLexer): int =
  result = L.lineNumber

proc handleOctChar(c: var SqlLexer, xi: var int) =
  if c.buf[c.bufpos] in {'0'..'7'}:
    xi = (xi shl 3) or (ord(c.buf[c.bufpos]) - ord('0'))
    inc(c.bufpos)

proc getEscapedChar(c: var SqlLexer, tok: var Token) =
  inc(c.bufpos)
  case c.buf[c.bufpos]
  of 'n', 'N':
    add(tok.literal, '\L')
    inc(c.bufpos)
  of 'r', 'R', 'c', 'C':
    add(tok.literal, '\c')
    inc(c.bufpos)
  of 'l', 'L':
    add(tok.literal, '\L')
    inc(c.bufpos)
  of 'f', 'F':
    add(tok.literal, '\f')
    inc(c.bufpos)
  of 'e', 'E':
    add(tok.literal, '\e')
    inc(c.bufpos)
  of 'a', 'A':
    add(tok.literal, '\a')
    inc(c.bufpos)
  of 'b', 'B':
    add(tok.literal, '\b')
    inc(c.bufpos)
  of 'v', 'V':
    add(tok.literal, '\v')
    inc(c.bufpos)
  of 't', 'T':
    add(tok.literal, '\t')
    inc(c.bufpos)
  of '\'', '\"':
    add(tok.literal, c.buf[c.bufpos])
    inc(c.bufpos)
  of '\\':
    add(tok.literal, '\\')
    inc(c.bufpos)
  of 'x', 'X':
    inc(c.bufpos)
    var xi = 0
    if handleHexChar(c.buf[c.bufpos], xi):
      inc(c.bufpos)
      if handleHexChar(c.buf[c.bufpos], xi):
        inc(c.bufpos)
    add(tok.literal, chr(xi))
  of '0'..'7':
    var xi = 0
    handleOctChar(c, xi)
    handleOctChar(c, xi)
    handleOctChar(c, xi)
    if (xi <= 255): add(tok.literal, chr(xi))
    else: tok.kind = tkInvalid
  else: tok.kind = tkInvalid

proc handleCRLF(c: var SqlLexer, pos: int): int =
  case c.buf[pos]
  of '\c': result = lexbase.handleCR(c, pos)
  of '\L': result = lexbase.handleLF(c, pos)
  else: result = pos

proc skip(c: var SqlLexer) =
  var pos = c.bufpos
  var nested = 0
  while true:
    case c.buf[pos]
    of ' ', '\t':
      inc(pos)
    of '-':
      if c.buf[pos+1] == '-':
        while not (c.buf[pos] in {'\c', '\L', lexbase.EndOfFile}): inc(pos)
      else:
        break
    of '/':
      if c.buf[pos+1] == '*':
        inc(pos, 2)
        while true:
          case c.buf[pos]
          of '\0': break
          of '\c', '\L':
            pos = handleCRLF(c, pos)
          of '*':
            if c.buf[pos+1] == '/':
              inc(pos, 2)
              if nested <= 0: break
              dec(nested)
            else:
              inc(pos)
          of '/':
            if c.buf[pos+1] == '*':
              inc(pos, 2)
              inc(nested)
            else:
              inc(pos)
          else: inc(pos)
      else: break
    of '\c', '\L':
      pos = handleCRLF(c, pos)
    else:
      break # EndOfFile also leaves the loop
  c.bufpos = pos

proc getString(c: var SqlLexer, tok: var Token, kind: TokKind) =
  var pos = c.bufpos + 1
  tok.kind = kind
  block parseLoop:
    while true:
      while true:
        var ch = c.buf[pos]
        if ch == '\'':
          if c.buf[pos+1] == '\'':
            inc(pos, 2)
            add(tok.literal, '\'')
          else:
            inc(pos)
            break
        elif ch in {'\c', '\L', lexbase.EndOfFile}:
          tok.kind = tkInvalid
          break parseLoop
        elif (ch == '\\') and kind == tkEscapeConstant:
          c.bufpos = pos
          getEscapedChar(c, tok)
          pos = c.bufpos
        else:
          add(tok.literal, ch)
          inc(pos)
      c.bufpos = pos
      var line = c.lineNumber
      skip(c)
      if c.lineNumber > line:
        # a new line whitespace has been parsed, so we check if the string
        # continues after the whitespace:
        pos = c.bufpos
        if c.buf[pos] == '\'': inc(pos)
        else: break parseLoop
      else: break parseLoop
  c.bufpos = pos

proc getDollarString(c: var SqlLexer, tok: var Token) =
  var pos = c.bufpos + 1
  tok.kind = tkDollarQuotedConstant
  var tag = "$"
  while c.buf[pos] in IdentChars:
    add(tag, c.buf[pos])
    inc(pos)
  if c.buf[pos] == '$': inc(pos)
  else:
    tok.kind = tkInvalid
    return
  while true:
    case c.buf[pos]
    of '\c', '\L':
      pos = handleCRLF(c, pos)
      add(tok.literal, "\L")
    of '\0':
      tok.kind = tkInvalid
      break
    of '$':
      inc(pos)
      var tag2 = "$"
      while c.buf[pos] in IdentChars:
        add(tag2, c.buf[pos])
        inc(pos)
      if c.buf[pos] == '$': inc(pos)
      if tag2 == tag: break
      add(tok.literal, tag2)
      add(tok.literal, '$')
    else:
      add(tok.literal, c.buf[pos])
      inc(pos)
  c.bufpos = pos

proc getSymbol(c: var SqlLexer, tok: var Token) =
  var pos = c.bufpos
  while true:
    add(tok.literal, c.buf[pos])
    inc(pos)
    if c.buf[pos] notin {'a'..'z', 'A'..'Z', '0'..'9', '_', '$',
        '\128'..'\255'}:
      break
  c.bufpos = pos
  tok.kind = tkIdentifier

proc getQuotedIdentifier(c: var SqlLexer, tok: var Token, quote = '\"') =
  var pos = c.bufpos + 1
  tok.kind = tkQuotedIdentifier
  while true:
    var ch = c.buf[pos]
    if ch == quote:
      if c.buf[pos+1] == quote:
        inc(pos, 2)
        add(tok.literal, quote)
      else:
        inc(pos)
        break
    elif ch in {'\c', '\L', lexbase.EndOfFile}:
      tok.kind = tkInvalid
      break
    else:
      add(tok.literal, ch)
      inc(pos)
  c.bufpos = pos

proc getBitHexString(c: var SqlLexer, tok: var Token, validChars: set[char]) =
  var pos = c.bufpos + 1
  block parseLoop:
    while true:
      while true:
        var ch = c.buf[pos]
        if ch in validChars:
          add(tok.literal, ch)
          inc(pos)
        elif ch == '\'':
          inc(pos)
          break
        else:
          tok.kind = tkInvalid
          break parseLoop
      c.bufpos = pos
      var line = c.lineNumber
      skip(c)
      if c.lineNumber > line:
        # a new line whitespace has been parsed, so we check if the string
        # continues after the whitespace:
        pos = c.bufpos
        if c.buf[pos] == '\'': inc(pos)
        else: break parseLoop
      else: break parseLoop
  c.bufpos = pos

proc getNumeric(c: var SqlLexer, tok: var Token) =
  tok.kind = tkInteger
  var pos = c.bufpos
  while c.buf[pos] in Digits:
    add(tok.literal, c.buf[pos])
    inc(pos)
  if c.buf[pos] == '.':
    tok.kind = tkNumeric
    add(tok.literal, c.buf[pos])
    inc(pos)
    while c.buf[pos] in Digits:
      add(tok.literal, c.buf[pos])
      inc(pos)
  if c.buf[pos] in {'E', 'e'}:
    tok.kind = tkNumeric
    add(tok.literal, c.buf[pos])
    inc(pos)
    if c.buf[pos] == '+':
      inc(pos)
    elif c.buf[pos] == '-':
      add(tok.literal, c.buf[pos])
      inc(pos)
    if c.buf[pos] in Digits:
      while c.buf[pos] in Digits:
        add(tok.literal, c.buf[pos])
        inc(pos)
    else:
      tok.kind = tkInvalid
  c.bufpos = pos

proc getOperator(c: var SqlLexer, tok: var Token) =
  const operators = {'+', '-', '*', '/', '<', '>', '=', '~', '!', '@', '#', '%',
                     '^', '&', '|', '`', '?'}
  tok.kind = tkOperator
  var pos = c.bufpos
  var trailingPlusMinus = false
  while true:
    case c.buf[pos]
    of '-':
      if c.buf[pos] == '-': break
      if not trailingPlusMinus and c.buf[pos+1] notin operators and
           tok.literal.len > 0: break
    of '/':
      if c.buf[pos] == '*': break
    of '~', '!', '@', '#', '%', '^', '&', '|', '`', '?':
      trailingPlusMinus = true
    of '+':
      if not trailingPlusMinus and c.buf[pos+1] notin operators and
           tok.literal.len > 0: break
    of '*', '<', '>', '=': discard
    else: break
    add(tok.literal, c.buf[pos])
    inc(pos)
  c.bufpos = pos

proc getTok(c: var SqlLexer, tok: var Token) =
  tok.kind = tkInvalid
  setLen(tok.literal, 0)
  skip(c)
  case c.buf[c.bufpos]
  of ';':
    tok.kind = tkSemicolon
    inc(c.bufpos)
    add(tok.literal, ';')
  of ',':
    tok.kind = tkComma
    inc(c.bufpos)
    add(tok.literal, ',')
  of ':':
    tok.kind = tkColon
    inc(c.bufpos)
    add(tok.literal, ':')
  of 'e', 'E':
    if c.buf[c.bufpos + 1] == '\'':
      inc(c.bufpos)
      getString(c, tok, tkEscapeConstant)
    else:
      getSymbol(c, tok)
  of 'b', 'B':
    if c.buf[c.bufpos + 1] == '\'':
      tok.kind = tkBitStringConstant
      getBitHexString(c, tok, {'0'..'1'})
    else:
      getSymbol(c, tok)
  of 'x', 'X':
    if c.buf[c.bufpos + 1] == '\'':
      tok.kind = tkHexStringConstant
      getBitHexString(c, tok, {'a'..'f', 'A'..'F', '0'..'9'})
    else:
      getSymbol(c, tok)
  of '$': getDollarString(c, tok)
  of '[':
    tok.kind = tkBracketLe
    inc(c.bufpos)
    add(tok.literal, '[')
  of ']':
    tok.kind = tkBracketRi
    inc(c.bufpos)
    add(tok.literal, ']')
  of '(':
    tok.kind = tkParLe
    inc(c.bufpos)
    add(tok.literal, '(')
  of ')':
    tok.kind = tkParRi
    inc(c.bufpos)
    add(tok.literal, ')')
  of '.':
    if c.buf[c.bufpos + 1] in Digits:
      getNumeric(c, tok)
    else:
      tok.kind = tkDot
      inc(c.bufpos)
    add(tok.literal, '.')
  of '0'..'9': getNumeric(c, tok)
  of '\'': getString(c, tok, tkStringConstant)
  of '"': getQuotedIdentifier(c, tok, '"')
  of '`': getQuotedIdentifier(c, tok, '`')
  of lexbase.EndOfFile:
    tok.kind = tkEof
    tok.literal = "[EOF]"
  of 'a', 'c', 'd', 'f'..'w', 'y', 'z', 'A', 'C', 'D', 'F'..'W', 'Y', 'Z', '_',
     '\128'..'\255':
    getSymbol(c, tok)
  of '+', '-', '*', '/', '<', '>', '=', '~', '!', '@', '#', '%',
     '^', '&', '|', '?':
    getOperator(c, tok)
  else:
    add(tok.literal, c.buf[c.bufpos])
    inc(c.bufpos)

proc errorStr(L: SqlLexer, msg: string): string =
  result = "$1($2, $3) Error: $4" % [L.filename, $getLine(L), $getColumn(L), msg]


# ----------------------------- parser ----------------------------------------

# Operator/Element   Associativity  Description
# .                  left           table/column name separator
# ::                 left           PostgreSQL-style typecast
# [ ]                left           array element selection
# -                  right          unary minus
# ^                  left           exponentiation
# * / %              left           multiplication, division, modulo
# + -                left           addition, subtraction
# IS                                IS TRUE, IS FALSE, IS UNKNOWN, IS NULL
# ISNULL                            test for null
# NOTNULL                           test for not null
# (any other)        left           all other native and user-defined oprs
# IN                                set membership
# BETWEEN                           range containment
# OVERLAPS                          time interval overlap
# LIKE ILIKE SIMILAR                string pattern matching
# < >                               less than, greater than
# =                  right          equality, assignment
# NOT                right          logical negation
# AND                left           logical conjunction
# OR                 left           logical disjunction

type
  SqlNodeKind* = enum ## kind of SQL abstract syntax tree
    nkNone,
    nkIdent,
    nkQuotedIdent,
    nkStringLit,
    nkBitStringLit,
    nkHexStringLit,
    nkIntegerLit,
    nkNumericLit,
    nkPrimaryKey,
    nkForeignKey,
    nkNotNull,
    nkNull,

    nkStmtList,
    nkDot,
    nkDotDot,
    nkPrefix,
    nkInfix,
    nkCall,
    nkPrGroup,
    nkColumnReference,
    nkReferences,
    nkDefault,
    nkCheck,
    nkConstraint,
    nkUnique,
    nkIdentity,
    nkColumnDef,      ## name, datatype, constraints
    nkInsert,
    nkUpdate,
    nkDelete,
    nkSelect,
    nkSelectDistinct,
    nkSelectColumns,
    nkSelectPair,
    nkAsgn,
    nkFrom,
    nkFromItemPair,
    nkJoin,
    nkNaturalJoin,
    nkUsing,
    nkGroup,
    nkLimit,
    nkOffset,
    nkHaving,
    nkOrder,
    nkDesc,
    nkUnion,
    nkIntersect,
    nkExcept,
    nkColumnList,
    nkValueList,
    nkWhere,
    nkCreateTable,
    nkCreateTableIfNotExists,
    nkCreateType,
    nkCreateTypeIfNotExists,
    nkCreateIndex,
    nkCreateIndexIfNotExists,
    nkEnumDef

const
  LiteralNodes = {
    nkIdent, nkQuotedIdent, nkStringLit, nkBitStringLit, nkHexStringLit,
    nkIntegerLit, nkNumericLit
  }

type
  SqlParseError* = object of ValueError ## Invalid SQL encountered
  SqlNode* = ref SqlNodeObj ## an SQL abstract syntax tree node
  SqlNodeObj* = object      ## an SQL abstract syntax tree node
    case kind*: SqlNodeKind ## kind of syntax tree
    of LiteralNodes:
      strVal*: string       ## AST leaf: the identifier, numeric literal
                            ## string literal, etc.
    else:
      sons*: seq[SqlNode]   ## the node's children

  SqlParser* = object of SqlLexer ## SQL parser object
    tok: Token

proc newNode*(k: SqlNodeKind): SqlNode =
  when defined(js): # bug #14117
    case k
    of LiteralNodes:
      result = SqlNode(kind: k, strVal: "")
    else:
      result = SqlNode(kind: k, sons: @[])
  else:
    result = SqlNode(kind: k)

proc newNode*(k: SqlNodeKind, s: string): SqlNode =
  result = SqlNode(kind: k)
  result.strVal = s

proc newNode*(k: SqlNodeKind, sons: seq[SqlNode]): SqlNode =
  result = SqlNode(kind: k)
  result.sons = sons

proc len*(n: SqlNode): int =
  if n.kind in LiteralNodes:
    result = 0
  else:
    result = n.sons.len

proc `[]`*(n: SqlNode; i: int): SqlNode = n.sons[i]
proc `[]`*(n: SqlNode; i: BackwardsIndex): SqlNode = n.sons[n.len - int(i)]

proc add*(father, n: SqlNode) =
  add(father.sons, n)

proc getTok(p: var SqlParser) =
  getTok(p, p.tok)

proc sqlError(p: SqlParser, msg: string) =
  var e: ref SqlParseError
  new(e)
  e.msg = errorStr(p, msg)
  raise e

proc isKeyw(p: SqlParser, keyw: string): bool =
  result = p.tok.kind == tkIdentifier and
           cmpIgnoreCase(p.tok.literal, keyw) == 0

proc isOpr(p: SqlParser, opr: string): bool =
  result = p.tok.kind == tkOperator and
           cmpIgnoreCase(p.tok.literal, opr) == 0

proc optKeyw(p: var SqlParser, keyw: string) =
  if p.tok.kind == tkIdentifier and cmpIgnoreCase(p.tok.literal, keyw) == 0:
    getTok(p)

proc expectIdent(p: SqlParser) =
  if p.tok.kind != tkIdentifier and p.tok.kind != tkQuotedIdentifier:
    sqlError(p, "identifier expected")

proc expect(p: SqlParser, kind: TokKind) =
  if p.tok.kind != kind:
    sqlError(p, tokKindToStr[kind] & " expected")

proc eat(p: var SqlParser, kind: TokKind) =
  if p.tok.kind == kind:
    getTok(p)
  else:
    sqlError(p, tokKindToStr[kind] & " expected")

proc eat(p: var SqlParser, keyw: string) =
  if isKeyw(p, keyw):
    getTok(p)
  else:
    sqlError(p, keyw.toUpperAscii() & " expected")

proc opt(p: var SqlParser, kind: TokKind) =
  if p.tok.kind == kind: getTok(p)

proc parseDataType(p: var SqlParser): SqlNode =
  if isKeyw(p, "enum"):
    result = newNode(nkEnumDef)
    getTok(p)
    if p.tok.kind == tkParLe:
      getTok(p)
      result.add(newNode(nkStringLit, p.tok.literal))
      getTok(p)
      while p.tok.kind == tkComma:
        getTok(p)
        result.add(newNode(nkStringLit, p.tok.literal))
        getTok(p)
      eat(p, tkParRi)
  else:
    expectIdent(p)
    result = newNode(nkIdent, p.tok.literal)
    getTok(p)
    # ignore (12, 13) part:
    if p.tok.kind == tkParLe:
      getTok(p)
      expect(p, tkInteger)
      getTok(p)
      while p.tok.kind == tkComma:
        getTok(p)
        expect(p, tkInteger)
        getTok(p)
      eat(p, tkParRi)

proc getPrecedence(p: SqlParser): int =
  if isOpr(p, "*") or isOpr(p, "/") or isOpr(p, "%"):
    result = 6
  elif isOpr(p, "+") or isOpr(p, "-"):
    result = 5
  elif isOpr(p, "=") or isOpr(p, "<") or isOpr(p, ">") or isOpr(p, ">=") or
       isOpr(p, "<=") or isOpr(p, "<>") or isOpr(p, "!=") or isKeyw(p, "is") or
       isKeyw(p, "like") or isKeyw(p, "in"):
    result = 4
  elif isKeyw(p, "and"):
    result = 3
  elif isKeyw(p, "or"):
    result = 2
  elif isKeyw(p, "between"):
    result = 1
  elif p.tok.kind == tkOperator:
    # user-defined operator:
    result = 0
  else:
    result = - 1

proc parseExpr(p: var SqlParser): SqlNode {.gcsafe.}
proc parseSelect(p: var SqlParser): SqlNode {.gcsafe.}

proc identOrLiteral(p: var SqlParser): SqlNode =
  case p.tok.kind
  of tkQuotedIdentifier:
    result = newNode(nkQuotedIdent, p.tok.literal)
    getTok(p)
  of tkIdentifier:
    result = newNode(nkIdent, p.tok.literal)
    getTok(p)
  of tkStringConstant, tkEscapeConstant, tkDollarQuotedConstant:
    result = newNode(nkStringLit, p.tok.literal)
    getTok(p)
  of tkBitStringConstant:
    result = newNode(nkBitStringLit, p.tok.literal)
    getTok(p)
  of tkHexStringConstant:
    result = newNode(nkHexStringLit, p.tok.literal)
    getTok(p)
  of tkInteger:
    result = newNode(nkIntegerLit, p.tok.literal)
    getTok(p)
  of tkNumeric:
    result = newNode(nkNumericLit, p.tok.literal)
    getTok(p)
  of tkParLe:
    getTok(p)
    result = newNode(nkPrGroup)
    while true:
      result.add(parseExpr(p))
      if p.tok.kind != tkComma: break
      getTok(p)
    eat(p, tkParRi)
  else:
    if p.tok.literal == "*":
      result = newNode(nkIdent, p.tok.literal)
      getTok(p)
    else:
      sqlError(p, "expression expected")
      getTok(p) # we must consume a token here to prevent endless loops!

proc primary(p: var SqlParser): SqlNode =
  if (p.tok.kind == tkOperator and (p.tok.literal == "+" or p.tok.literal ==
      "-")) or isKeyw(p, "not"):
    result = newNode(nkPrefix)
    result.add(newNode(nkIdent, p.tok.literal))
    getTok(p)
    result.add(primary(p))
    return
  result = identOrLiteral(p)
  while true:
    case p.tok.kind
    of tkParLe:
      var a = result
      result = newNode(nkCall)
      result.add(a)
      getTok(p)
      while p.tok.kind != tkParRi:
        result.add(parseExpr(p))
        if p.tok.kind == tkComma: getTok(p)
        else: break
      eat(p, tkParRi)
    of tkDot:
      getTok(p)
      var a = result
      if p.tok.kind == tkDot:
        getTok(p)
        result = newNode(nkDotDot)
      else:
        result = newNode(nkDot)
      result.add(a)
      if isOpr(p, "*"):
        result.add(newNode(nkIdent, "*"))
      elif p.tok.kind in {tkIdentifier, tkQuotedIdentifier}:
        result.add(newNode(nkIdent, p.tok.literal))
      else:
        sqlError(p, "identifier expected")
      getTok(p)
    else: break

proc lowestExprAux(p: var SqlParser, v: var SqlNode, limit: int): int =
  var
    v2, node, opNode: SqlNode
  v = primary(p) # expand while operators have priorities higher than 'limit'
  var opPred = getPrecedence(p)
  result = opPred
  while opPred > limit:
    node = newNode(nkInfix)
    opNode = newNode(nkIdent, p.tok.literal.toLowerAscii())
    getTok(p)
    result = lowestExprAux(p, v2, opPred)
    node.add(opNode)
    node.add(v)
    node.add(v2)
    v = node
    opPred = getPrecedence(p)

proc parseExpr(p: var SqlParser): SqlNode =
  discard lowestExprAux(p, result, - 1)

proc parseTableName(p: var SqlParser): SqlNode =
  expectIdent(p)
  result = primary(p)

proc parseColumnReference(p: var SqlParser): SqlNode =
  result = parseTableName(p)
  if p.tok.kind == tkParLe:
    getTok(p)
    var a = result
    result = newNode(nkColumnReference)
    result.add(a)
    result.add(parseTableName(p))
    while p.tok.kind == tkComma:
      getTok(p)
      result.add(parseTableName(p))
    eat(p, tkParRi)

proc parseCheck(p: var SqlParser): SqlNode =
  getTok(p)
  result = newNode(nkCheck)
  result.add(parseExpr(p))

proc parseConstraint(p: var SqlParser): SqlNode =
  getTok(p)
  result = newNode(nkConstraint)
  expectIdent(p)
  result.add(newNode(nkIdent, p.tok.literal))
  getTok(p)
  optKeyw(p, "check")
  result.add(parseExpr(p))

proc parseParIdentList(p: var SqlParser, father: SqlNode) =
  eat(p, tkParLe)
  while true:
    expectIdent(p)
    father.add(newNode(nkIdent, p.tok.literal))
    getTok(p)
    if p.tok.kind != tkComma: break
    getTok(p)
  eat(p, tkParRi)

proc parseColumnConstraints(p: var SqlParser, result: SqlNode) =
  while true:
    if isKeyw(p, "default"):
      getTok(p)
      var n = newNode(nkDefault)
      n.add(parseExpr(p))
      result.add(n)
    elif isKeyw(p, "references"):
      getTok(p)
      var n = newNode(nkReferences)
      n.add(parseColumnReference(p))
      result.add(n)
    elif isKeyw(p, "not"):
      getTok(p)
      eat(p, "null")
      result.add(newNode(nkNotNull))
    elif isKeyw(p, "null"):
      getTok(p)
      result.add(newNode(nkNull))
    elif isKeyw(p, "identity"):
      getTok(p)
      result.add(newNode(nkIdentity))
    elif isKeyw(p, "primary"):
      getTok(p)
      eat(p, "key")
      result.add(newNode(nkPrimaryKey))
    elif isKeyw(p, "check"):
      result.add(parseCheck(p))
    elif isKeyw(p, "constraint"):
      result.add(parseConstraint(p))
    elif isKeyw(p, "unique"):
      getTok(p)
      result.add(newNode(nkUnique))
    else:
      break

proc parseColumnDef(p: var SqlParser): SqlNode =
  expectIdent(p)
  result = newNode(nkColumnDef)
  result.add(newNode(nkIdent, p.tok.literal))
  getTok(p)
  result.add(parseDataType(p))
  parseColumnConstraints(p, result)

proc parseIfNotExists(p: var SqlParser, k: SqlNodeKind): SqlNode =
  getTok(p)
  if isKeyw(p, "if"):
    getTok(p)
    eat(p, "not")
    eat(p, "exists")
    result = newNode(succ(k))
  else:
    result = newNode(k)

proc parseTableConstraint(p: var SqlParser): SqlNode =
  if isKeyw(p, "primary"):
    getTok(p)
    eat(p, "key")
    result = newNode(nkPrimaryKey)
    parseParIdentList(p, result)
  elif isKeyw(p, "foreign"):
    getTok(p)
    eat(p, "key")
    result = newNode(nkForeignKey)
    parseParIdentList(p, result)
    eat(p, "references")
    var m = newNode(nkReferences)
    m.add(parseColumnReference(p))
    result.add(m)
  elif isKeyw(p, "unique"):
    getTok(p)
    eat(p, "key")
    result = newNode(nkUnique)
    parseParIdentList(p, result)
  elif isKeyw(p, "check"):
    result = parseCheck(p)
  elif isKeyw(p, "constraint"):
    result = parseConstraint(p)
  else:
    sqlError(p, "column definition expected")

proc parseUnique(p: var SqlParser): SqlNode =
  result = parseExpr(p)
  if result.kind == nkCall: result.kind = nkUnique

proc parseTableDef(p: var SqlParser): SqlNode =
  result = parseIfNotExists(p, nkCreateTable)
  expectIdent(p)
  result.add(newNode(nkIdent, p.tok.literal))
  getTok(p)
  if p.tok.kind == tkParLe:
    getTok(p)
    while p.tok.kind != tkParRi:
      if isKeyw(p, "constraint"):
        result.add parseConstraint(p)
      elif isKeyw(p, "primary") or isKeyw(p, "foreign"):
        result.add parseTableConstraint(p)
      elif isKeyw(p, "unique"):
        result.add parseUnique(p)
      elif p.tok.kind == tkIdentifier or p.tok.kind == tkQuotedIdentifier:
        result.add(parseColumnDef(p))
      else:
        result.add(parseTableConstraint(p))
      if p.tok.kind != tkComma: break
      getTok(p)
    eat(p, tkParRi)
    # skip additional crap after 'create table (...) crap;'
    while p.tok.kind notin {tkSemicolon, tkEof}:
      getTok(p)

proc parseTypeDef(p: var SqlParser): SqlNode =
  result = parseIfNotExists(p, nkCreateType)
  expectIdent(p)
  result.add(newNode(nkIdent, p.tok.literal))
  getTok(p)
  eat(p, "as")
  result.add(parseDataType(p))

proc parseWhere(p: var SqlParser): SqlNode =
  getTok(p)
  result = newNode(nkWhere)
  result.add(parseExpr(p))

proc parseJoinType(p: var SqlParser): SqlNode =
  ## parse [ INNER ] JOIN | ( LEFT | RIGHT | FULL ) [ OUTER ] JOIN
  if isKeyw(p, "inner"):
    getTok(p)
    eat(p, "join")
    return newNode(nkIdent, "inner")
  elif isKeyw(p, "join"):
    getTok(p)
    return newNode(nkIdent, "")
  elif isKeyw(p, "left") or isKeyw(p, "full") or isKeyw(p, "right"):
    var joinType = newNode(nkIdent, p.tok.literal.toLowerAscii())
    getTok(p)
    optKeyw(p, "outer")
    eat(p, "join")
    return joinType
  else:
    sqlError(p, "join type expected")

proc parseFromItem(p: var SqlParser): SqlNode =
  result = newNode(nkFromItemPair)
  var expectAs = true
  if p.tok.kind == tkParLe:
    getTok(p)
    if isKeyw(p, "select"):
      result.add(parseSelect(p))
    else:
      result = parseFromItem(p)
      expectAs = false
    eat(p, tkParRi)
  else:
    result.add(parseExpr(p))
  if expectAs and isKeyw(p, "as"):
    getTok(p)
    result.add(parseExpr(p))
  while true:
    if isKeyw(p, "cross"):
      var join = newNode(nkJoin)
      join.add(newNode(nkIdent, "cross"))
      join.add(result)
      getTok(p)
      eat(p, "join")
      join.add(parseFromItem(p))
      result = join
    elif isKeyw(p, "natural"):
      var join = newNode(nkNaturalJoin)
      getTok(p)
      join.add(parseJoinType(p))
      join.add(result)
      join.add(parseFromItem(p))
      result = join
    elif isKeyw(p, "inner") or isKeyw(p, "join") or isKeyw(p, "left") or
        iskeyw(p, "full") or isKeyw(p, "right"):
      var join = newNode(nkJoin)
      join.add(parseJoinType(p))
      join.add(result)
      join.add(parseFromItem(p))
      if isKeyw(p, "on"):
        getTok(p)
        join.add(parseExpr(p))
      elif isKeyw(p, "using"):
        getTok(p)
        var n = newNode(nkUsing)
        parseParIdentList(p, n)
        join.add n
      else:
        sqlError(p, "ON or USING expected")
      result = join
    else:
      break

proc parseIndexDef(p: var SqlParser): SqlNode =
  result = parseIfNotExists(p, nkCreateIndex)
  if isKeyw(p, "primary"):
    getTok(p)
    eat(p, "key")
    result.add(newNode(nkPrimaryKey))
  else:
    expectIdent(p)
    result.add(newNode(nkIdent, p.tok.literal))
    getTok(p)
  eat(p, "on")
  expectIdent(p)
  result.add(newNode(nkIdent, p.tok.literal))
  getTok(p)
  eat(p, tkParLe)
  expectIdent(p)
  result.add(newNode(nkIdent, p.tok.literal))
  getTok(p)
  while p.tok.kind == tkComma:
    getTok(p)
    expectIdent(p)
    result.add(newNode(nkIdent, p.tok.literal))
    getTok(p)
  eat(p, tkParRi)

proc parseInsert(p: var SqlParser): SqlNode =
  getTok(p)
  eat(p, "into")
  expectIdent(p)
  result = newNode(nkInsert)
  result.add(newNode(nkIdent, p.tok.literal))
  getTok(p)
  if p.tok.kind == tkParLe:
    var n = newNode(nkColumnList)
    parseParIdentList(p, n)
    result.add n
  else:
    result.add(newNode(nkNone))
  if isKeyw(p, "default"):
    getTok(p)
    eat(p, "values")
    result.add(newNode(nkDefault))
  else:
    eat(p, "values")
    eat(p, tkParLe)
    var n = newNode(nkValueList)
    while true:
      n.add(parseExpr(p))
      if p.tok.kind != tkComma: break
      getTok(p)
    result.add(n)
    eat(p, tkParRi)

proc parseUpdate(p: var SqlParser): SqlNode =
  getTok(p)
  result = newNode(nkUpdate)
  result.add(primary(p))
  eat(p, "set")
  while true:
    var a = newNode(nkAsgn)
    expectIdent(p)
    a.add(newNode(nkIdent, p.tok.literal))
    getTok(p)
    if isOpr(p, "="): getTok(p)
    else: sqlError(p, "= expected")
    a.add(parseExpr(p))
    result.add(a)
    if p.tok.kind != tkComma: break
    getTok(p)
  if isKeyw(p, "where"):
    result.add(parseWhere(p))
  else:
    result.add(newNode(nkNone))

proc parseDelete(p: var SqlParser): SqlNode =
  getTok(p)
  if isOpr(p, "*"):
    getTok(p)
  result = newNode(nkDelete)
  eat(p, "from")
  result.add(primary(p))
  if isKeyw(p, "where"):
    result.add(parseWhere(p))
  else:
    result.add(newNode(nkNone))

proc parseSelect(p: var SqlParser): SqlNode =
  getTok(p)
  if isKeyw(p, "distinct"):
    getTok(p)
    result = newNode(nkSelectDistinct)
  elif isKeyw(p, "all"):
    getTok(p)
  result = newNode(nkSelect)
  var a = newNode(nkSelectColumns)
  while true:
    if isOpr(p, "*"):
      a.add(newNode(nkIdent, "*"))
      getTok(p)
    else:
      var pair = newNode(nkSelectPair)
      pair.add(parseExpr(p))
      a.add(pair)
      if isKeyw(p, "as"):
        getTok(p)
        pair.add(parseExpr(p))
    if p.tok.kind != tkComma: break
    getTok(p)
  result.add(a)
  if isKeyw(p, "from"):
    var f = newNode(nkFrom)
    while true:
      getTok(p)
      f.add(parseFromItem(p))
      if p.tok.kind != tkComma: break
    result.add(f)
  if isKeyw(p, "where"):
    result.add(parseWhere(p))
  if isKeyw(p, "group"):
    getTok(p)
    eat(p, "by")
    var g = newNode(nkGroup)
    while true:
      g.add(parseExpr(p))
      if p.tok.kind != tkComma: break
      getTok(p)
    result.add(g)
  if isKeyw(p, "order"):
    getTok(p)
    eat(p, "by")
    var n = newNode(nkOrder)
    while true:
      var e = parseExpr(p)
      if isKeyw(p, "asc"):
        getTok(p) # is default
      elif isKeyw(p, "desc"):
        getTok(p)
        var x = newNode(nkDesc)
        x.add(e)
        e = x
      n.add(e)
      if p.tok.kind != tkComma: break
      getTok(p)
    result.add(n)
  if isKeyw(p, "having"):
    var h = newNode(nkHaving)
    while true:
      getTok(p)
      h.add(parseExpr(p))
      if p.tok.kind != tkComma: break
    result.add(h)
  if isKeyw(p, "union"):
    result.add(newNode(nkUnion))
    getTok(p)
  elif isKeyw(p, "intersect"):
    result.add(newNode(nkIntersect))
    getTok(p)
  elif isKeyw(p, "except"):
    result.add(newNode(nkExcept))
    getTok(p)
  if isKeyw(p, "limit"):
    getTok(p)
    var l = newNode(nkLimit)
    l.add(parseExpr(p))
    result.add(l)
  if isKeyw(p, "offset"):
    getTok(p)
    var o = newNode(nkOffset)
    o.add(parseExpr(p))
    result.add(o)

proc parseStmt(p: var SqlParser; parent: SqlNode) =
  if isKeyw(p, "create"):
    getTok(p)
    optKeyw(p, "cached")
    optKeyw(p, "memory")
    optKeyw(p, "temp")
    optKeyw(p, "global")
    optKeyw(p, "local")
    optKeyw(p, "temporary")
    optKeyw(p, "unique")
    optKeyw(p, "hash")
    if isKeyw(p, "table"):
      parent.add parseTableDef(p)
    elif isKeyw(p, "type"):
      parent.add parseTypeDef(p)
    elif isKeyw(p, "index"):
      parent.add parseIndexDef(p)
    else:
      sqlError(p, "TABLE expected")
  elif isKeyw(p, "insert"):
    parent.add parseInsert(p)
  elif isKeyw(p, "update"):
    parent.add parseUpdate(p)
  elif isKeyw(p, "delete"):
    parent.add parseDelete(p)
  elif isKeyw(p, "select"):
    parent.add parseSelect(p)
  elif isKeyw(p, "begin"):
    getTok(p)
  else:
    sqlError(p, "SELECT, CREATE, UPDATE or DELETE expected")

proc parse(p: var SqlParser): SqlNode =
  ## parses the content of `p`'s input stream and returns the SQL AST.
  ## Syntax errors raise an `SqlParseError` exception.
  result = newNode(nkStmtList)
  while p.tok.kind != tkEof:
    parseStmt(p, result)
    if p.tok.kind == tkEof:
      break
    eat(p, tkSemicolon)

proc close(p: var SqlParser) =
  ## closes the parser `p`. The associated input stream is closed too.
  close(SqlLexer(p))

type
  SqlWriter = object
    indent: int
    upperCase: bool
    buffer: string

proc add(s: var SqlWriter, thing: char) =
  s.buffer.add(thing)

proc prepareAdd(s: var SqlWriter) {.inline.} =
  if s.buffer.len > 0 and s.buffer[^1] notin {' ', '\L', '(', '.'}:
    s.buffer.add(" ")

proc add(s: var SqlWriter, thing: string) =
  s.prepareAdd
  s.buffer.add(thing)

proc addKeyw(s: var SqlWriter, thing: string) =
  var keyw = thing
  if s.upperCase:
    keyw = keyw.toUpperAscii()
  s.add(keyw)

proc addIden(s: var SqlWriter, thing: string) =
  var iden = thing
  if iden.toLowerAscii() in reservedKeywords:
    iden = '"' & iden & '"'
  s.add(iden)

proc ra(n: SqlNode, s: var SqlWriter) {.gcsafe.}

proc rs(n: SqlNode, s: var SqlWriter, prefix = "(", suffix = ")", sep = ", ") =
  if n.len > 0:
    s.add(prefix)
    for i in 0 .. n.len-1:
      if i > 0: s.add(sep)
      ra(n.sons[i], s)
    s.add(suffix)

proc addMulti(s: var SqlWriter, n: SqlNode, sep = ',') =
  if n.len > 0:
    for i in 0 .. n.len-1:
      if i > 0: s.add(sep)
      ra(n.sons[i], s)

proc addMulti(s: var SqlWriter, n: SqlNode, sep = ',', prefix, suffix: char) =
  if n.len > 0:
    s.add(prefix)
    for i in 0 .. n.len-1:
      if i > 0: s.add(sep)
      ra(n.sons[i], s)
    s.add(suffix)

proc quoted(s: string): string =
  "\"" & replace(s, "\"", "\"\"") & "\""

func escape(result: var string; s: string) =
  result.add('\'')
  for c in items(s):
    case c
    of '\0'..'\31':
      result.add("\\x")
      result.add(toHex(ord(c), 2))
    of '\'': result.add("''")
    else: result.add(c)
  result.add('\'')

proc ra(n: SqlNode, s: var SqlWriter) =
  if n == nil: return
  case n.kind
  of nkNone: discard
  of nkIdent:
    if allCharsInSet(n.strVal, {'\33'..'\127'}):
      s.add(n.strVal)
    else:
      s.add(quoted(n.strVal))
  of nkQuotedIdent:
    s.add(quoted(n.strVal))
  of nkStringLit:
    s.prepareAdd
    s.buffer.escape(n.strVal)
  of nkBitStringLit:
    s.add("b'" & n.strVal & "'")
  of nkHexStringLit:
    s.add("x'" & n.strVal & "'")
  of nkIntegerLit, nkNumericLit:
    s.add(n.strVal)
  of nkPrimaryKey:
    s.addKeyw("primary key")
    rs(n, s)
  of nkForeignKey:
    s.addKeyw("foreign key")
    rs(n, s)
  of nkNotNull:
    s.addKeyw("not null")
  of nkNull:
    s.addKeyw("null")
  of nkDot:
    ra(n.sons[0], s)
    s.add('.')
    ra(n.sons[1], s)
  of nkDotDot:
    ra(n.sons[0], s)
    s.add(". .")
    ra(n.sons[1], s)
  of nkPrefix:
    ra(n.sons[0], s)
    s.add(' ')
    ra(n.sons[1], s)
  of nkInfix:
    ra(n.sons[1], s)
    s.add(' ')
    ra(n.sons[0], s)
    s.add(' ')
    ra(n.sons[2], s)
  of nkCall, nkColumnReference:
    ra(n.sons[0], s)
    s.add('(')
    for i in 1..n.len-1:
      if i > 1: s.add(',')
      ra(n.sons[i], s)
    s.add(')')
  of nkPrGroup:
    s.add('(')
    s.addMulti(n)
    s.add(')')
  of nkReferences:
    s.addKeyw("references")
    ra(n.sons[0], s)
  of nkDefault:
    s.addKeyw("default")
    ra(n.sons[0], s)
  of nkCheck:
    s.addKeyw("check")
    ra(n.sons[0], s)
  of nkConstraint:
    s.addKeyw("constraint")
    ra(n.sons[0], s)
    s.addKeyw("check")
    ra(n.sons[1], s)
  of nkUnique:
    s.addKeyw("unique")
    rs(n, s)
  of nkIdentity:
    s.addKeyw("identity")
  of nkColumnDef:
    rs(n, s, "", "", " ")
  of nkStmtList:
    for i in 0..n.len-1:
      ra(n.sons[i], s)
      s.add(';')
  of nkInsert:
    assert n.len == 3
    s.addKeyw("insert into")
    ra(n.sons[0], s)
    s.add(' ')
    ra(n.sons[1], s)
    if n.sons[2].kind == nkDefault:
      s.addKeyw("default values")
    else:
      ra(n.sons[2], s)
  of nkUpdate:
    s.addKeyw("update")
    ra(n.sons[0], s)
    s.addKeyw("set")
    var L = n.len
    for i in 1 .. L-2:
      if i > 1: s.add(", ")
      var it = n.sons[i]
      assert it.kind == nkAsgn
      ra(it, s)
    ra(n.sons[L-1], s)
  of nkDelete:
    s.addKeyw("delete from")
    ra(n.sons[0], s)
    ra(n.sons[1], s)
  of nkSelect, nkSelectDistinct:
    s.addKeyw("select")
    if n.kind == nkSelectDistinct:
      s.addKeyw("distinct")
    for i in 0 ..< n.len:
      ra(n.sons[i], s)
  of nkSelectColumns:
    for i, column in n.sons:
      if i > 0: s.add(',')
      ra(column, s)
  of nkSelectPair:
    ra(n.sons[0], s)
    if n.sons.len == 2:
      s.addKeyw("as")
      ra(n.sons[1], s)
  of nkFromItemPair:
    if n.sons[0].kind in {nkIdent, nkQuotedIdent}:
      ra(n.sons[0], s)
    else:
      assert n.sons[0].kind == nkSelect
      s.add('(')
      ra(n.sons[0], s)
      s.add(')')
    if n.sons.len == 2:
      s.addKeyw("as")
      ra(n.sons[1], s)
  of nkAsgn:
    ra(n.sons[0], s)
    s.add(" = ")
    ra(n.sons[1], s)
  of nkFrom:
    s.addKeyw("from")
    s.addMulti(n)
  of nkJoin, nkNaturalJoin:
    var joinType = n.sons[0].strVal
    if joinType == "":
      joinType = "join"
    else:
      joinType &= " " & "join"
    if n.kind == nkNaturalJoin:
      joinType = "natural " & joinType
    ra(n.sons[1], s)
    s.addKeyw(joinType)
    # If the right part of the join is not leaf, parenthesize it
    if n.sons[2].kind != nkFromItemPair:
      s.add('(')
      ra(n.sons[2], s)
      s.add(')')
    else:
      ra(n.sons[2], s)
    if n.sons.len > 3:
      if n.sons[3].kind != nkUsing:
        s.addKeyw("on")
      ra(n.sons[3], s)
  of nkUsing:
    s.addKeyw("using")
    rs(n, s)
  of nkGroup:
    s.addKeyw("group by")
    s.addMulti(n)
  of nkLimit:
    s.addKeyw("limit")
    s.addMulti(n)
  of nkOffset:
    s.addKeyw("offset")
    s.addMulti(n)
  of nkHaving:
    s.addKeyw("having")
    s.addMulti(n)
  of nkOrder:
    s.addKeyw("order by")
    s.addMulti(n)
  of nkDesc:
    ra(n.sons[0], s)
    s.addKeyw("desc")
  of nkUnion:
    s.addKeyw("union")
  of nkIntersect:
    s.addKeyw("intersect")
  of nkExcept:
    s.addKeyw("except")
  of nkColumnList:
    rs(n, s)
  of nkValueList:
    s.addKeyw("values")
    rs(n, s)
  of nkWhere:
    s.addKeyw("where")
    ra(n.sons[0], s)
  of nkCreateTable, nkCreateTableIfNotExists:
    s.addKeyw("create table")
    if n.kind == nkCreateTableIfNotExists:
      s.addKeyw("if not exists")
    ra(n.sons[0], s)
    s.add('(')
    for i in 1..n.len-1:
      if i > 1: s.add(',')
      ra(n.sons[i], s)
    s.add(");")
  of nkCreateType, nkCreateTypeIfNotExists:
    s.addKeyw("create type")
    if n.kind == nkCreateTypeIfNotExists:
      s.addKeyw("if not exists")
    ra(n.sons[0], s)
    s.addKeyw("as")
    ra(n.sons[1], s)
  of nkCreateIndex, nkCreateIndexIfNotExists:
    s.addKeyw("create index")
    if n.kind == nkCreateIndexIfNotExists:
      s.addKeyw("if not exists")
    ra(n.sons[0], s)
    s.addKeyw("on")
    ra(n.sons[1], s)
    s.add('(')
    for i in 2..n.len-1:
      if i > 2: s.add(", ")
      ra(n.sons[i], s)
    s.add(");")
  of nkEnumDef:
    s.addKeyw("enum")
    rs(n, s)

proc renderSql*(n: SqlNode, upperCase = false): string =
  ## Converts an SQL abstract syntax tree to its string representation.
  var s: SqlWriter
  s.buffer = ""
  s.upperCase = upperCase
  ra(n, s)
  return s.buffer

proc `$`*(n: SqlNode): string =
  ## an alias for `renderSql`.
  renderSql(n)

proc treeReprAux(s: SqlNode, level: int, result: var string) =
  result.add('\n')
  for i in 0 ..< level: result.add("  ")

  result.add($s.kind)
  if s.kind in LiteralNodes:
    result.add(' ')
    result.add(s.strVal)
  else:
    for son in s.sons:
      treeReprAux(son, level + 1, result)

proc treeRepr*(s: SqlNode): string =
  result = newStringOfCap(128)
  treeReprAux(s, 0, result)

import std/streams

proc open(L: var SqlLexer, input: Stream, filename: string) =
  lexbase.open(L, input)
  L.filename = filename

proc open(p: var SqlParser, input: Stream, filename: string) =
  ## opens the parser `p` and assigns the input stream `input` to it.
  ## `filename` is only used for error messages.
  open(SqlLexer(p), input, filename)
  p.tok.kind = tkInvalid
  p.tok.literal = ""
  getTok(p)

proc parseSql*(input: Stream, filename: string): SqlNode =
  ## parses the SQL from `input` into an AST and returns the AST.
  ## `filename` is only used for error messages.
  ## Syntax errors raise an `SqlParseError` exception.
  var p: SqlParser
  open(p, input, filename)
  try:
    result = parse(p)
  finally:
    close(p)

proc parseSql*(input: string, filename = ""): SqlNode =
  ## parses the SQL from `input` into an AST and returns the AST.
  ## `filename` is only used for error messages.
  ## Syntax errors raise an `SqlParseError` exception.
  parseSql(newStringStream(input), "")

#
#
#           The Nim Compiler
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# Algorithms for the abstract syntax tree: hash tables, lists
# and sets of nodes are supported. Efficiency is important as
# the data structures here are used in various places of the compiler.

import
  ast, astyaml, options, lineinfos, idents, rodutils,
  msgs

import std/[hashes, intsets]
import std/strutils except addf

export astyaml.treeToYaml, astyaml.typeToYaml, astyaml.symToYaml, astyaml.lineInfoToStr

when defined(nimPreviewSlimSystem):
  import std/assertions

proc hashNode*(p: RootRef): Hash

# these are for debugging only: They are not really deprecated, but I want
# the warning so that release versions do not contain debugging statements:
proc debug*(n: PSym; conf: ConfigRef = nil) {.exportc: "debugSym", deprecated.}
proc debug*(n: PType; conf: ConfigRef = nil) {.exportc: "debugType", deprecated.}
proc debug*(n: PNode; conf: ConfigRef = nil) {.exportc: "debugNode", deprecated.}

template debug*(x: PSym|PType|PNode) {.deprecated.} =
  when compiles(c.config):
    debug(c.config, x)
  elif compiles(c.graph.config):
    debug(c.graph.config, x)
  else:
    error()

template debug*(x: auto) {.deprecated.} =
  echo x

template mdbg*: bool {.deprecated.} =
  when compiles(c.graph):
    c.module.fileIdx == c.graph.config.projectMainIdx
  elif compiles(c.module):
    c.module.fileIdx == c.config.projectMainIdx
  elif compiles(c.c.module):
    c.c.module.fileIdx == c.c.config.projectMainIdx
  elif compiles(m.c.module):
    m.c.module.fileIdx == m.c.config.projectMainIdx
  elif compiles(cl.c.module):
    cl.c.module.fileIdx == cl.c.config.projectMainIdx
  elif compiles(p):
    when compiles(p.lex):
      p.lex.fileIdx == p.lex.config.projectMainIdx
    else:
      p.module.module.fileIdx == p.config.projectMainIdx
  elif compiles(m.module.fileIdx):
    m.module.fileIdx == m.config.projectMainIdx
  elif compiles(L.fileIdx):
    L.fileIdx == L.config.projectMainIdx
  else:
    error()

# ---------------------------------------------------------------------------

proc lookupInRecord*(n: PNode, field: PIdent): PSym
proc mustRehash*(length, counter: int): bool
proc nextTry*(h, maxHash: Hash): Hash {.inline.}

# ------------- table[int, int] ---------------------------------------------
const
  InvalidKey* = low(int)

type
  TIIPair*{.final.} = object
    key*, val*: int

  TIIPairSeq* = seq[TIIPair]
  TIITable*{.final.} = object # table[int, int]
    counter*: int
    data*: TIIPairSeq


proc initIITable*(x: var TIITable)
proc iiTableGet*(t: TIITable, key: int): int
proc iiTablePut*(t: var TIITable, key, val: int)

# implementation

proc skipConvCastAndClosure*(n: PNode): PNode =
  result = n
  while true:
    case result.kind
    of nkObjUpConv, nkObjDownConv, nkChckRange, nkChckRangeF, nkChckRange64,
       nkClosure:
      result = result[0]
    of nkHiddenStdConv, nkHiddenSubConv, nkConv, nkCast:
      result = result[1]
    else: break

proc sameValue*(a, b: PNode): bool =
  result = false
  case a.kind
  of nkCharLit..nkUInt64Lit:
    if b.kind in {nkCharLit..nkUInt64Lit}: result = getInt(a) == getInt(b)
  of nkFloatLit..nkFloat64Lit:
    if b.kind in {nkFloatLit..nkFloat64Lit}: result = a.floatVal == b.floatVal
  of nkStrLit..nkTripleStrLit:
    if b.kind in {nkStrLit..nkTripleStrLit}: result = a.strVal == b.strVal
  else:
    # don't raise an internal error for 'nim check':
    #InternalError(a.info, "SameValue")
    discard

proc leValue*(a, b: PNode): bool =
  # a <= b?
  result = false
  case a.kind
  of nkCharLit..nkUInt64Lit:
    if b.kind in {nkCharLit..nkUInt64Lit}: result = getInt(a) <= getInt(b)
  of nkFloatLit..nkFloat64Lit:
    if b.kind in {nkFloatLit..nkFloat64Lit}: result = a.floatVal <= b.floatVal
  of nkStrLit..nkTripleStrLit:
    if b.kind in {nkStrLit..nkTripleStrLit}: result = a.strVal <= b.strVal
  else:
    # don't raise an internal error for 'nim check':
    #InternalError(a.info, "leValue")
    discard

proc weakLeValue*(a, b: PNode): TImplication =
  if a.kind notin nkLiterals or b.kind notin nkLiterals:
    result = impUnknown
  else:
    result = if leValue(a, b): impYes else: impNo

proc lookupInRecord(n: PNode, field: PIdent): PSym =
  result = nil
  case n.kind
  of nkRecList:
    for i in 0..<n.len:
      result = lookupInRecord(n[i], field)
      if result != nil: return
  of nkRecCase:
    if (n[0].kind != nkSym): return nil
    result = lookupInRecord(n[0], field)
    if result != nil: return
    for i in 1..<n.len:
      case n[i].kind
      of nkOfBranch, nkElse:
        result = lookupInRecord(lastSon(n[i]), field)
        if result != nil: return
      else: return nil
  of nkSym:
    if n.sym.name.id == field.id: result = n.sym
  else: return nil

proc getModule*(s: PSym): PSym =
  result = s
  assert((result.kind == skModule) or (result.owner != result))
  while result != nil and result.kind != skModule: result = result.owner

proc fromSystem*(op: PSym): bool {.inline.} = sfSystemModule in getModule(op).flags
proc getSymFromList*(list: PNode, ident: PIdent, start: int = 0): PSym =
  for i in start..<list.len:
    if list[i].kind == nkSym:
      result = list[i].sym
      if result.name.id == ident.id: return
    else: return nil
  result = nil

proc sameIgnoreBacktickGensymInfo(a, b: string): bool =
  result = false
  if a[0] != b[0]: return false
  var alen = a.len - 1
  while alen > 0 and a[alen] != '`': dec(alen)
  if alen <= 0: alen = a.len

  var i = 1
  var j = 1
  while true:
    while i < alen and a[i] == '_': inc i
    while j < b.len and b[j] == '_': inc j
    var aa = if i < alen: toLowerAscii(a[i]) else: '\0'
    var bb = if j < b.len: toLowerAscii(b[j]) else: '\0'
    if aa != bb: return false

    # the characters are identical:
    if i >= alen:
      # both cursors at the end:
      if j >= b.len: return true
      # not yet at the end of 'b':
      return false
    elif j >= b.len:
      return false
    inc i
    inc j

proc getNamedParamFromList*(list: PNode, ident: PIdent): PSym =
  ## Named parameters are special because a named parameter can be
  ## gensym'ed and then they have '\`<number>' suffix that we need to
  ## ignore, see compiler / evaltempl.nim, snippet:
  ##   ```nim
  ##   result.add newIdentNode(getIdent(c.ic, x.name.s & "\`gensym" & $x.id),
  ##            if c.instLines: actual.info else: templ.info)
  ##   ```
  result = nil
  for i in 1..<list.len:
    let it = list[i].sym
    if it.name.id == ident.id or
        sameIgnoreBacktickGensymInfo(it.name.s, ident.s): return it

proc hashNode(p: RootRef): Hash =
  result = hash(cast[pointer](p))

proc mustRehash(length, counter: int): bool =
  assert(length > counter)
  result = (length * 2 < counter * 3) or (length - counter < 4)

import std/tables

const backrefStyle = "\e[90m"
const enumStyle = "\e[34m"
const numberStyle = "\e[33m"
const stringStyle = "\e[32m"
const resetStyle  = "\e[0m"

type
  DebugPrinter = object
    conf: ConfigRef
    visited: Table[pointer, int]
    renderSymType: bool
    indent: int
    currentLine: int
    firstItem: bool
    useColor: bool
    res: string

proc indentMore(this: var DebugPrinter) =
  this.indent += 2

proc indentLess(this: var DebugPrinter) =
  this.indent -= 2

proc newlineAndIndent(this: var DebugPrinter) =
  this.res.add "\n"
  this.currentLine += 1
  for i in 0..<this.indent:
    this.res.add ' '

proc openCurly(this: var DebugPrinter) =
  this.res.add "{"
  this.indentMore
  this.firstItem = true

proc closeCurly(this: var DebugPrinter) =
  this.indentLess
  this.newlineAndIndent
  this.res.add "}"

proc comma(this: var DebugPrinter) =
  this.res.add ", "

proc openBracket(this: var DebugPrinter) =
  this.res.add "["
  #this.indentMore

proc closeBracket(this: var DebugPrinter) =
  #this.indentLess
  this.res.add "]"

proc key(this: var DebugPrinter; key: string) =
  if not this.firstItem:
    this.res.add ","
  this.firstItem = false

  this.newlineAndIndent
  this.res.add "\""
  this.res.add key
  this.res.add "\": "

proc value(this: var DebugPrinter; value: string) =
  if this.useColor:
    this.res.add stringStyle
  this.res.add "\""
  this.res.add value
  this.res.add "\""
  if this.useColor:
    this.res.add resetStyle

proc value(this: var DebugPrinter; value: BiggestInt) =
  if this.useColor:
    this.res.add numberStyle
  this.res.addInt value
  if this.useColor:
    this.res.add resetStyle

proc value[T: enum](this: var DebugPrinter; value: T) =
  if this.useColor:
    this.res.add enumStyle
  this.res.add "\""
  this.res.add $value
  this.res.add "\""
  if this.useColor:
    this.res.add resetStyle

proc value[T: enum](this: var DebugPrinter; value: set[T]) =
  this.openBracket
  let high = card(value)-1
  var i = 0
  for v in value:
    this.value v
    if i != high:
      this.comma
    inc i
  this.closeBracket

template earlyExit(this: var DebugPrinter; n: PType | PNode | PSym) =
  if n == nil:
    this.res.add "null"
    return
  let index = this.visited.getOrDefault(cast[pointer](n), -1)
  if index < 0:
    this.visited[cast[pointer](n)] = this.currentLine
  else:
    if this.useColor:
      this.res.add backrefStyle
    this.res.add "<defined "
    this.res.addInt(this.currentLine - index)
    this.res.add " lines upwards>"
    if this.useColor:
      this.res.add resetStyle
    return

proc value(this: var DebugPrinter; value: PType)
proc value(this: var DebugPrinter; value: PNode)
proc value(this: var DebugPrinter; value: PSym) =
  earlyExit(this, value)

  this.openCurly
  this.key("kind")
  this.value(value.kind)
  this.key("name")
  this.value(value.name.s)
  this.key("id")
  this.value(value.id)
  if value.kind in {skField, skEnumField, skParam}:
    this.key("position")
    this.value(value.position)

  if card(value.flags) > 0:
    this.key("flags")
    this.value(value.flags)

  if this.renderSymType and value.typ != nil:
    this.key "typ"
    this.value(value.typ)

  this.closeCurly

proc value(this: var DebugPrinter; value: PType) =
  earlyExit(this, value)

  this.openCurly
  this.key "kind"
  this.value value.kind

  this.key "id"
  this.value value.id

  if value.sym != nil:
    this.key "sym"
    this.value value.sym
    #this.value value.sym.name.s

  if card(value.flags) > 0:
    this.key "flags"
    this.value value.flags

  if value.kind in IntegralTypes and value.n != nil:
    this.key "n"
    this.value value.n

  this.key "sons"
  this.openBracket
  for i, a in value.ikids:
    if i > 0: this.comma
    this.value a
  this.closeBracket

  if value.n != nil:
    this.key "n"
    this.value value.n

  this.closeCurly

proc value(this: var DebugPrinter; value: PNode) =
  earlyExit(this, value)

  this.openCurly
  this.key "kind"
  this.value  value.kind
  if value.comment.len > 0:
    this.key "comment"
    this.value  value.comment
  when defined(useNodeIds):
    this.key "id"
    this.value value.id
  if this.conf != nil:
    this.key "info"
    this.value $lineInfoToStr(this.conf, value.info)
  if value.flags != {}:
    this.key "flags"
    this.value value.flags

  if value.typ != nil:
    this.key "typ"
    this.value value.typ.kind
  else:
    this.key "typ"
    this.value "nil"

  case value.kind
  of nkCharLit..nkUInt64Lit:
    this.key "intVal"
    this.value value.intVal
  of nkFloatLit, nkFloat32Lit, nkFloat64Lit:
    this.key "floatVal"
    this.value value.floatVal.toStrMaxPrecision
  of nkStrLit..nkTripleStrLit:
    this.key "strVal"
    this.value value.strVal
  of nkSym:
    this.key "sym"
    this.value value.sym
    #this.value value.sym.name.s
  of nkIdent:
    if value.ident != nil:
      this.key "ident"
      this.value value.ident.s
  else:
    if this.renderSymType and value.typ != nil:
      this.key "typ"
      this.value value.typ
    if value.len > 0:
      this.key "sons"
      this.openBracket
      for i in 0..<value.len:
        this.value value[i]
        if i != value.len - 1:
          this.comma
      this.closeBracket

  this.closeCurly


proc debug(n: PSym; conf: ConfigRef) =
  var this = DebugPrinter(
    visited: initTable[pointer, int](),
    renderSymType: true,
    useColor: not defined(windows)
  )
  this.value(n)
  echo($this.res)

proc debug(n: PType; conf: ConfigRef) =
  var this = DebugPrinter(
    visited: initTable[pointer, int](),
    renderSymType: true,
    useColor: not defined(windows)
  )
  this.value(n)
  echo($this.res)

proc debug(n: PNode; conf: ConfigRef) =
  var this = DebugPrinter(
    visited: initTable[pointer, int](),
    renderSymType: false,
    useColor: not defined(windows)
  )
  this.value(n)
  echo($this.res)

proc nextTry(h, maxHash: Hash): Hash {.inline.} =
  result = ((5 * h) + 1) and maxHash
  # For any initial h in range(maxHash), repeating that maxHash times
  # generates each int in range(maxHash) exactly once (see any text on
  # random-number generation for proof).

proc objectSetContains*(t: TObjectSet, obj: RootRef): bool =
  # returns true whether n is in t
  var h: Hash = hashNode(obj) and high(t.data) # start with real hash value
  while t.data[h] != nil:
    if t.data[h] == obj:
      return true
    h = nextTry(h, high(t.data))
  result = false

proc objectSetRawInsert(data: var TObjectSeq, obj: RootRef) =
  var h: Hash = hashNode(obj) and high(data)
  while data[h] != nil:
    assert(data[h] != obj)
    h = nextTry(h, high(data))
  assert(data[h] == nil)
  data[h] = obj

proc objectSetEnlarge(t: var TObjectSet) =
  var n: TObjectSeq
  newSeq(n, t.data.len * GrowthFactor)
  for i in 0..high(t.data):
    if t.data[i] != nil: objectSetRawInsert(n, t.data[i])
  swap(t.data, n)

proc objectSetIncl*(t: var TObjectSet, obj: RootRef) =
  if mustRehash(t.data.len, t.counter): objectSetEnlarge(t)
  objectSetRawInsert(t.data, obj)
  inc(t.counter)

proc objectSetContainsOrIncl*(t: var TObjectSet, obj: RootRef): bool =
  # returns true if obj is already in the string table:
  var h: Hash = hashNode(obj) and high(t.data)
  while true:
    var it = t.data[h]
    if it == nil: break
    if it == obj:
      return true             # found it
    h = nextTry(h, high(t.data))
  if mustRehash(t.data.len, t.counter):
    objectSetEnlarge(t)
    objectSetRawInsert(t.data, obj)
  else:
    assert(t.data[h] == nil)
    t.data[h] = obj
  inc(t.counter)
  result = false

proc strTableContains*(t: TStrTable, n: PSym): bool =
  var h: Hash = n.name.h and high(t.data) # start with real hash value
  while t.data[h] != nil:
    if (t.data[h] == n):
      return true
    h = nextTry(h, high(t.data))
  result = false

proc strTableRawInsert(data: var seq[PSym], n: PSym) =
  var h: Hash = n.name.h and high(data)
  while data[h] != nil:
    if data[h] == n:
      # allowed for 'export' feature:
      #InternalError(n.info, "StrTableRawInsert: " & n.name.s)
      return
    h = nextTry(h, high(data))
  assert(data[h] == nil)
  data[h] = n

proc symTabReplaceRaw(data: var seq[PSym], prevSym: PSym, newSym: PSym) =
  assert prevSym.name.h == newSym.name.h
  var h: Hash = prevSym.name.h and high(data)
  while data[h] != nil:
    if data[h] == prevSym:
      data[h] = newSym
      return
    h = nextTry(h, high(data))
  assert false

proc symTabReplace*(t: var TStrTable, prevSym: PSym, newSym: PSym) =
  symTabReplaceRaw(t.data, prevSym, newSym)

proc strTableEnlarge(t: var TStrTable) =
  var n: seq[PSym]
  newSeq(n, t.data.len * GrowthFactor)
  for i in 0..high(t.data):
    if t.data[i] != nil: strTableRawInsert(n, t.data[i])
  swap(t.data, n)

proc strTableAdd*(t: var TStrTable, n: PSym) =
  if mustRehash(t.data.len, t.counter): strTableEnlarge(t)
  strTableRawInsert(t.data, n)
  inc(t.counter)

proc strTableInclReportConflict*(t: var TStrTable, n: PSym;
                                 onConflictKeepOld = false): PSym =
  # if `t` has a conflicting symbol (same identifier as `n`), return it
  # otherwise return `nil`. Incl `n` to `t` unless `onConflictKeepOld = true`
  # and a conflict was found.
  assert n.name != nil
  var h: Hash = n.name.h and high(t.data)
  var replaceSlot = -1
  while true:
    var it = t.data[h]
    if it == nil: break
    # Semantic checking can happen multiple times thanks to templates
    # and overloading: (var x=@[]; x).mapIt(it).
    # So it is possible the very same sym is added multiple
    # times to the symbol table which we allow here with the 'it == n' check.
    if it.name.id == n.name.id:
      if it == n: return nil
      replaceSlot = h
    h = nextTry(h, high(t.data))
  if replaceSlot >= 0:
    result = t.data[replaceSlot] # found it
    if not onConflictKeepOld:
      t.data[replaceSlot] = n # overwrite it with newer definition!
    return result # but return the old one
  elif mustRehash(t.data.len, t.counter):
    strTableEnlarge(t)
    strTableRawInsert(t.data, n)
  else:
    assert(t.data[h] == nil)
    t.data[h] = n
  inc(t.counter)
  result = nil

proc strTableIncl*(t: var TStrTable, n: PSym;
                   onConflictKeepOld = false): bool {.discardable.} =
  result = strTableInclReportConflict(t, n, onConflictKeepOld) != nil

proc strTableGet*(t: TStrTable, name: PIdent): PSym =
  var h: Hash = name.h and high(t.data)
  while true:
    result = t.data[h]
    if result == nil: break
    if result.name.id == name.id: break
    h = nextTry(h, high(t.data))


type
  TIdentIter* = object # iterator over all syms with same identifier
    h*: Hash           # current hash
    name*: PIdent

proc nextIdentIter*(ti: var TIdentIter, tab: TStrTable): PSym =
  # hot spots
  var h = ti.h and high(tab.data)
  var start = h
  var p {.cursor.} = tab.data[h]
  while p != nil:
    if p.name.id == ti.name.id: break
    h = nextTry(h, high(tab.data))
    if h == start:
      p = nil
      break
    p = tab.data[h]
  if p != nil:
    result = p # increase the count
  else:
    result = nil
  ti.h = nextTry(h, high(tab.data))

proc initIdentIter*(ti: var TIdentIter, tab: TStrTable, s: PIdent): PSym =
  ti.h = s.h
  ti.name = s
  if tab.counter == 0: result = nil
  else: result = nextIdentIter(ti, tab)

proc nextIdentExcluding*(ti: var TIdentIter, tab: TStrTable,
                         excluding: IntSet): PSym =
  var h: Hash = ti.h and high(tab.data)
  var start = h
  result = tab.data[h]
  while result != nil:
    if result.name.id == ti.name.id and not contains(excluding, result.id):
      break
    h = nextTry(h, high(tab.data))
    if h == start:
      result = nil
      break
    result = tab.data[h]
  ti.h = nextTry(h, high(tab.data))
  if result != nil and contains(excluding, result.id): result = nil

proc firstIdentExcluding*(ti: var TIdentIter, tab: TStrTable, s: PIdent,
                          excluding: IntSet): PSym =
  ti.h = s.h
  ti.name = s
  if tab.counter == 0: result = nil
  else: result = nextIdentExcluding(ti, tab, excluding)

type
  TTabIter* = object
    h: Hash

proc nextIter*(ti: var TTabIter, tab: TStrTable): PSym =
  # usage:
  # var
  #   i: TTabIter
  #   s: PSym
  # s = InitTabIter(i, table)
  # while s != nil:
  #   ...
  #   s = NextIter(i, table)
  #
  result = nil
  while (ti.h <= high(tab.data)):
    result = tab.data[ti.h]
    inc(ti.h)                 # ... and increment by one always
    if result != nil: break

proc initTabIter*(ti: var TTabIter, tab: TStrTable): PSym =
  ti.h = 0
  if tab.counter == 0:
    result = nil
  else:
    result = nextIter(ti, tab)

iterator items*(tab: TStrTable): PSym =
  var it: TTabIter = default(TTabIter)
  var s = initTabIter(it, tab)
  while s != nil:
    yield s
    s = nextIter(it, tab)

proc initIITable(x: var TIITable) =
  x.counter = 0
  newSeq(x.data, StartSize)
  for i in 0..<StartSize: x.data[i].key = InvalidKey

proc iiTableRawGet(t: TIITable, key: int): int =
  var h: Hash
  h = key and high(t.data)    # start with real hash value
  while t.data[h].key != InvalidKey:
    if t.data[h].key == key: return h
    h = nextTry(h, high(t.data))
  result = -1

proc iiTableGet(t: TIITable, key: int): int =
  var index = iiTableRawGet(t, key)
  if index >= 0: result = t.data[index].val
  else: result = InvalidKey

proc iiTableRawInsert(data: var TIIPairSeq, key, val: int) =
  var h: Hash
  h = key and high(data)
  while data[h].key != InvalidKey:
    assert(data[h].key != key)
    h = nextTry(h, high(data))
  assert(data[h].key == InvalidKey)
  data[h].key = key
  data[h].val = val

proc iiTablePut(t: var TIITable, key, val: int) =
  var index = iiTableRawGet(t, key)
  if index >= 0:
    assert(t.data[index].key != InvalidKey)
    t.data[index].val = val
  else:
    if mustRehash(t.data.len, t.counter):
      var n: TIIPairSeq
      newSeq(n, t.data.len * GrowthFactor)
      for i in 0..high(n): n[i].key = InvalidKey
      for i in 0..high(t.data):
        if t.data[i].key != InvalidKey:
          iiTableRawInsert(n, t.data[i].key, t.data[i].val)
      swap(t.data, n)
    iiTableRawInsert(t.data, key, val)
    inc(t.counter)

proc listSymbolNames*(symbols: openArray[PSym]): string =
  result = ""
  for sym in symbols:
    if result.len > 0:
      result.add ", "
    result.add sym.name.s

proc isDiscriminantField*(n: PNode): bool =
  if n.kind == nkCheckedFieldExpr: sfDiscriminant in n[0][1].sym.flags
  elif n.kind == nkDotExpr: sfDiscriminant in n[1].sym.flags
  else: false

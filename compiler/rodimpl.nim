#
#
#           The Nim Compiler
#        (c) Copyright 2018 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements the canonalization for the various caching mechanisms.

import strutils, os, intsets, tables, ropes, db_sqlite, msgs, options, types,
  renderer, rodutils, std / sha1, idents

var db: DbConn

proc getModuleId*(fullpath: string): int =
  if gSymbolFiles != v2Sf: return getID()
  let module = db.getRow(
    sql"select id, fullHash from modules where fullpath = ?", fullpath)
  let currentFullhash = $secureHashFile(fullpath)
  if module[0].len == 0:
    result = int db.insertID(sql"insert into modules(fullpath, interfHash, fullHash) values (?, ?)",
      fullpath, "", currentFullhash)
  else:
    result = parseInt(module[0])
    if currentFullhash == module[1]:
      # not changed, so use the cached AST (even if it might be wrong
      # due to its dependencies):
      doAssert(result != 0)
      result = -result
    else:
      db.exec(sql"update modules set fullHash = ? where id = ?", currentFullhash, module[0])
      db.exec(sql"delete from types where module = ?", module[0])
      db.exec(sql"delete from syms where module = ?", module[0])
      db.exec(sql"delete from toplevelstmts where module = ?", module[0])
      db.exec(sql"delete from statics where module = ?", module[0])

type
  TRodWriter = object
    module: PSym
    sstack: seq[PSym]          # a stack of symbols to process
    tstack: seq[PType]         # a stack of types to process
    tmarks, smarks: IntSet

  PRodWriter = var TRodWriter

proc initRodWriter(module: PSym): TRodWriter =
  result = TRodWriter(module: module, sstack: @[], tstack: @[],
    tmarks: initIntSet(), smarks: initIntSet())

when false:
  proc getDefines(): string =
    result = ""
    for d in definedSymbolNames():
      if result.len != 0: add(result, " ")
      add(result, d)

  proc addInclDep(w: PRodWriter, dep: string; info: TLineInfo) =
    let resolved = dep.findModule(info.toFullPath)
    encodeVInt(fileIdx(w, resolved), w.inclDeps)
    add(w.inclDeps, " ")
    encodeStr($secureHashFile(resolved), w.inclDeps)
    add(w.inclDeps, rodNL)

const
  rodNL = "\L"

proc pushType(w: PRodWriter, t: PType) =
  if not containsOrIncl(w.tmarks, t.id):
    w.tstack.add(t)

proc pushSym(w: PRodWriter, s: PSym) =
  if not containsOrIncl(w.smarks, s.id):
    w.sstack.add(s)

proc encodeNode(w: PRodWriter, fInfo: TLineInfo, n: PNode,
                result: var string) =
  if n == nil:
    # nil nodes have to be stored too:
    result.add("()")
    return
  result.add('(')
  encodeVInt(ord(n.kind), result)
  # we do not write comments for now
  # Line information takes easily 20% or more of the filesize! Therefore we
  # omit line information if it is the same as the parent's line information:
  if fInfo.fileIndex != n.info.fileIndex:
    result.add('?')
    encodeVInt(n.info.col, result)
    result.add(',')
    encodeVInt(n.info.line, result)
    result.add(',')
    encodeVInt(n.info.fileIndex, result)
  elif fInfo.line != n.info.line:
    result.add('?')
    encodeVInt(n.info.col, result)
    result.add(',')
    encodeVInt(n.info.line, result)
  elif fInfo.col != n.info.col:
    result.add('?')
    encodeVInt(n.info.col, result)
  # No need to output the file index, as this is the serialization of one
  # file.
  let f = n.flags * PersistentNodeFlags
  if f != {}:
    result.add('$')
    encodeVInt(cast[int32](f), result)
  if n.typ != nil:
    result.add('^')
    encodeVInt(n.typ.id, result)
    pushType(w, n.typ)
  case n.kind
  of nkCharLit..nkUInt64Lit:
    if n.intVal != 0:
      result.add('!')
      encodeVBiggestInt(n.intVal, result)
  of nkFloatLit..nkFloat64Lit:
    if n.floatVal != 0.0:
      result.add('!')
      encodeStr($n.floatVal, result)
  of nkStrLit..nkTripleStrLit:
    if n.strVal != "":
      result.add('!')
      encodeStr(n.strVal, result)
  of nkIdent:
    result.add('!')
    encodeStr(n.ident.s, result)
  of nkSym:
    result.add('!')
    encodeVInt(n.sym.id, result)
    pushSym(w, n.sym)
  else:
    for i in countup(0, sonsLen(n) - 1):
      encodeNode(w, n.info, n.sons[i], result)
  add(result, ')')

proc encodeLoc(w: PRodWriter, loc: TLoc, result: var string) =
  var oldLen = result.len
  result.add('<')
  if loc.k != low(loc.k): encodeVInt(ord(loc.k), result)
  if loc.storage != low(loc.storage):
    add(result, '*')
    encodeVInt(ord(loc.storage), result)
  if loc.flags != {}:
    add(result, '$')
    encodeVInt(cast[int32](loc.flags), result)
  if loc.lode != nil:
    add(result, '^')
    encodeNode(w, unknownLineInfo(), loc.lode, result)
    #encodeVInt(cast[int32](loc.t.id), result)
    #pushType(w, loc.t)
  if loc.r != nil:
    add(result, '!')
    encodeStr($loc.r, result)
  if oldLen + 1 == result.len:
    # no data was necessary, so remove the '<' again:
    setLen(result, oldLen)
  else:
    add(result, '>')

proc encodeType(w: PRodWriter, t: PType, result: var string) =
  if t == nil:
    # nil nodes have to be stored too:
    result.add("[]")
    return
  # we need no surrounding [] here because the type is in a line of its own
  if t.kind == tyForward: internalError("encodeType: tyForward")
  # for the new rodfile viewer we use a preceding [ so that the data section
  # can easily be disambiguated:
  add(result, '[')
  encodeVInt(ord(t.kind), result)
  add(result, '+')
  encodeVInt(t.id, result)
  if t.n != nil:
    encodeNode(w, w.module.info, t.n, result)
  if t.flags != {}:
    add(result, '$')
    encodeVInt(cast[int32](t.flags), result)
  if t.callConv != low(t.callConv):
    add(result, '?')
    encodeVInt(ord(t.callConv), result)
  if t.owner != nil:
    add(result, '*')
    encodeVInt(t.owner.id, result)
    pushSym(w, t.owner)
  if t.sym != nil:
    add(result, '&')
    encodeVInt(t.sym.id, result)
    pushSym(w, t.sym)
  if t.size != - 1:
    add(result, '/')
    encodeVBiggestInt(t.size, result)
  if t.align != 2:
    add(result, '=')
    encodeVInt(t.align, result)
  if t.lockLevel.ord != UnspecifiedLockLevel.ord:
    add(result, '\14')
    encodeVInt(t.lockLevel.int16, result)
  if t.destructor != nil and t.destructor.id != 0:
    add(result, '\15')
    encodeVInt(t.destructor.id, result)
    pushSym(w, t.destructor)
  if t.deepCopy != nil:
    add(result, '\16')
    encodeVInt(t.deepcopy.id, result)
    pushSym(w, t.deepcopy)
  if t.assignment != nil:
    add(result, '\17')
    encodeVInt(t.assignment.id, result)
    pushSym(w, t.assignment)
  if t.sink != nil:
    add(result, '\18')
    encodeVInt(t.sink.id, result)
    pushSym(w, t.sink)
  for i, s in items(t.methods):
    add(result, '\19')
    encodeVInt(i, result)
    add(result, '\20')
    encodeVInt(s.id, result)
    pushSym(w, s)
  encodeLoc(w, t.loc, result)
  for i in countup(0, sonsLen(t) - 1):
    if t.sons[i] == nil:
      add(result, "^()")
    else:
      add(result, '^')
      encodeVInt(t.sons[i].id, result)
      pushType(w, t.sons[i])

proc encodeLib(w: PRodWriter, lib: PLib, info: TLineInfo, result: var string) =
  add(result, '|')
  encodeVInt(ord(lib.kind), result)
  add(result, '|')
  encodeStr($lib.name, result)
  add(result, '|')
  encodeNode(w, info, lib.path, result)

proc encodeInstantiations(w: PRodWriter; s: seq[PInstantiation];
                          result: var string) =
  for t in s:
    result.add('\15')
    encodeVInt(t.sym.id, result)
    pushSym(w, t.sym)
    for tt in t.concreteTypes:
      result.add('\17')
      encodeVInt(tt.id, result)
      pushType(w, tt)
    result.add('\20')
    encodeVInt(t.compilesId, result)

proc encodeSym(w: PRodWriter, s: PSym, result: var string) =
  if s == nil:
    # nil nodes have to be stored too:
    result.add("{}")
    return
  # we need no surrounding {} here because the symbol is in a line of its own
  encodeVInt(ord(s.kind), result)
  result.add('+')
  encodeVInt(s.id, result)
  result.add('&')
  encodeStr(s.name.s, result)
  if s.typ != nil:
    result.add('^')
    encodeVInt(s.typ.id, result)
    pushType(w, s.typ)
  result.add('?')
  if s.info.col != -1'i16: encodeVInt(s.info.col, result)
  result.add(',')
  if s.info.line != -1'i16: encodeVInt(s.info.line, result)
  result.add(',')
  encodeVInt(s.info.fileIndex, result)
  if s.owner != nil:
    result.add('*')
    encodeVInt(s.owner.id, result)
    pushSym(w, s.owner)
  if s.flags != {}:
    result.add('$')
    encodeVInt(cast[int32](s.flags), result)
  if s.magic != mNone:
    result.add('@')
    encodeVInt(ord(s.magic), result)
  result.add('!')
  encodeVInt(cast[int32](s.options), result)
  if s.position != 0:
    result.add('%')
    encodeVInt(s.position, result)
  if s.offset != - 1:
    result.add('`')
    encodeVInt(s.offset, result)
  encodeLoc(w, s.loc, result)
  if s.annex != nil: encodeLib(w, s.annex, s.info, result)
  if s.constraint != nil:
    add(result, '#')
    encodeNode(w, unknownLineInfo(), s.constraint, result)
  case s.kind
  of skType, skGenericParam:
    for t in s.typeInstCache:
      result.add('\14')
      encodeVInt(t.id, result)
      pushType(w, t)
  of routineKinds:
    encodeInstantiations(w, s.procInstCache, result)
    if s.gcUnsafetyReason != nil:
      result.add('\16')
      encodeVInt(s.gcUnsafetyReason.id, result)
      pushSym(w, s.gcUnsafetyReason)
  of skModule, skPackage:
    encodeInstantiations(w, s.usedGenerics, result)
    # we don't serialize:
    #tab*: TStrTable         # interface table for modules
  of skLet, skVar, skField, skForVar:
    if s.guard != nil:
      result.add('\18')
      encodeVInt(s.guard.id, result)
      pushSym(w, s.guard)
    if s.bitsize != 0:
      result.add('\19')
      encodeVInt(s.bitsize, result)
  else: discard
  # lazy loading will soon reload the ast lazily, so the ast needs to be
  # the last entry of a symbol:
  if s.ast != nil:
    # we used to attempt to save space here by only storing a dummy AST if
    # it is not necessary, but Nim's heavy compile-time evaluation features
    # make that unfeasible nowadays:
    encodeNode(w, s.info, s.ast, result)

proc storeSym(w: PRodWriter; s: PSym) =
  var buf = newStringOfCap(160)
  encodeSym(w, s, buf)
  # XXX only store the name for exported symbols in order to speed up lookup
  # times once we enable the skStub logic.
  db.exec(sql"insert into syms(nimid, module, name, data) values (?, ?, ?, ?)",
    s.id, abs(w.module.id), s.name.s, buf)

proc storeType(w: PRodWriter; t: PType) =
  var buf = newStringOfCap(160)
  encodeType(w, t, buf)
  db.exec(sql"insert into types(nimid, module, data) values (?, ?, ?)",
    t.id, abs(w.module.id), buf)

var w = initRodWriter(nil)

proc storeNode*(module: PSym; n: PNode) =
  if gSymbolFiles != v2Sf: return
  w.module = module
  var buf = newStringOfCap(160)
  encodeNode(w, module.info, n, buf)
  db.exec(sql"insert into toplevelstmts(module, data) values (?, ?)",
    abs(module.id), buf)
  var i = 0
  while true:
    if i > 10_000:
      quit "loop never ends!"
    if w.sstack.len > 0:
      let s = w.sstack.pop()
      when false:
        echo "popped ", s.name.s, " ", s.id
      storeSym(w, s)
    elif w.tstack.len > 0:
      let t = w.tstack.pop()
      storeType(w, t)
      when false:
        echo "popped type ", typeToString(t), " ", t.id
    else:
      break
    inc i

# ---------------- decoder -----------------------------------
type
  TRodReader = object
    module: PSym
    #sstack: seq[(PSym, ptr PSym)]       # a stack of symbols to process
    #tstack: seq[(PType, ptr PType)]     # a stack of types to process

    #tmarks, smarks: IntSet
    syms: Table[int, PSym] ## XXX make this more efficients
    types: Table[int, PType]
    cache: IdentCache

  BlobReader = object
    s: string
    pos: int

  PRodReader = var TRodReader

proc initRodReader(cache: IdentCache): TRodReader =
  TRodReader(module: nil,
    syms: initTable[int, PSym](), types: initTable[int, PType](),
    cache: cache)

var gr = initRodReader(newIdentCache())

using
  r: PRodReader
  b: var BlobReader

proc loadSym(r; id: int, info: TLineInfo): PSym
proc loadType(r; id: int, info: TLineInfo): PType

proc decodeLineInfo(r; b; info: var TLineInfo) =
  if b.s[b.pos] == '?':
    inc(b.pos)
    if b.s[b.pos] == ',': info.col = -1'i16
    else: info.col = int16(decodeVInt(b.s, b.pos))
    if b.s[b.pos] == ',':
      inc(b.pos)
      if b.s[b.pos] == ',': info.line = -1'i16
      else: info.line = int16(decodeVInt(b.s, b.pos))
      if b.s[b.pos] == ',':
        inc(b.pos)
        info.fileIndex = int32(decodeVInt(b.s, b.pos))

proc skipNode(b) =
  assert b.s[b.pos] == '('
  var par = 0
  var pos = b.pos+1
  while true:
    case b.s[pos]
    of ')':
      if par == 0: break
      dec par
    of '(': inc par
    else: discard
    inc pos
  b.pos = pos+1 # skip ')'

proc decodeNodeLazyBody(r; b; fInfo: TLineInfo,
                        belongsTo: PSym): PNode =
  result = nil
  if b.s[b.pos] == '(':
    inc(b.pos)
    if b.s[b.pos] == ')':
      inc(b.pos)
      return                  # nil node
    result = newNodeI(TNodeKind(decodeVInt(b.s, b.pos)), fInfo)
    decodeLineInfo(r, b, result.info)
    if b.s[b.pos] == '$':
      inc(b.pos)
      result.flags = cast[TNodeFlags](int32(decodeVInt(b.s, b.pos)))
    if b.s[b.pos] == '^':
      inc(b.pos)
      var id = decodeVInt(b.s, b.pos)
      result.typ = loadType(r, id, result.info)
    case result.kind
    of nkCharLit..nkUInt64Lit:
      if b.s[b.pos] == '!':
        inc(b.pos)
        result.intVal = decodeVBiggestInt(b.s, b.pos)
    of nkFloatLit..nkFloat64Lit:
      if b.s[b.pos] == '!':
        inc(b.pos)
        var fl = decodeStr(b.s, b.pos)
        result.floatVal = parseFloat(fl)
    of nkStrLit..nkTripleStrLit:
      if b.s[b.pos] == '!':
        inc(b.pos)
        result.strVal = decodeStr(b.s, b.pos)
      else:
        result.strVal = ""
    of nkIdent:
      if b.s[b.pos] == '!':
        inc(b.pos)
        var fl = decodeStr(b.s, b.pos)
        result.ident = r.cache.getIdent(fl)
      else:
        internalError(result.info, "decodeNode: nkIdent")
    of nkSym:
      if b.s[b.pos] == '!':
        inc(b.pos)
        var id = decodeVInt(b.s, b.pos)
        result.sym = loadSym(r, id, result.info)
      else:
        internalError(result.info, "decodeNode: nkSym")
    else:
      var i = 0
      while b.s[b.pos] != ')':
        when false:
          if belongsTo != nil and i == bodyPos:
            addSonNilAllowed(result, nil)
            belongsTo.offset = b.pos
            skipNode(b)
          else:
            discard
        addSonNilAllowed(result, decodeNodeLazyBody(r, b, result.info, nil))
        inc i
    if b.s[b.pos] == ')': inc(b.pos)
    else: internalError(result.info, "decodeNode: ')' missing")
  else:
    internalError(fInfo, "decodeNode: '(' missing " & $b.pos)

proc decodeNode(r; b; fInfo: TLineInfo): PNode =
  result = decodeNodeLazyBody(r, b, fInfo, nil)

proc decodeLoc(r; b; loc: var TLoc, info: TLineInfo) =
  if b.s[b.pos] == '<':
    inc(b.pos)
    if b.s[b.pos] in {'0'..'9', 'a'..'z', 'A'..'Z'}:
      loc.k = TLocKind(decodeVInt(b.s, b.pos))
    else:
      loc.k = low(loc.k)
    if b.s[b.pos] == '*':
      inc(b.pos)
      loc.storage = TStorageLoc(decodeVInt(b.s, b.pos))
    else:
      loc.storage = low(loc.storage)
    if b.s[b.pos] == '$':
      inc(b.pos)
      loc.flags = cast[TLocFlags](int32(decodeVInt(b.s, b.pos)))
    else:
      loc.flags = {}
    if b.s[b.pos] == '^':
      inc(b.pos)
      loc.lode = decodeNode(r, b, info)
      # rrGetType(b, decodeVInt(b.s, b.pos), info)
    else:
      loc.lode = nil
    if b.s[b.pos] == '!':
      inc(b.pos)
      loc.r = rope(decodeStr(b.s, b.pos))
    else:
      loc.r = nil
    if b.s[b.pos] == '>': inc(b.pos)
    else: internalError(info, "decodeLoc " & b.s[b.pos])

proc loadBlob(query: SqlQuery; id: int): BlobReader =
  let blob = db.getValue(query, id)
  if blob.len == 0:
    internalError("symbolfiles: cannot find ID " & $ id)
  result = BlobReader(pos: 0)
  shallowCopy(result.s, blob)

proc loadType(r; id: int; info: TLineInfo): PType =
  result = r.types.getOrDefault(id)
  if result != nil: return result
  var b = loadBlob(sql"select data from types where nimid = ?", id)

  if b.s[b.pos] == '[':
    inc(b.pos)
    if b.s[b.pos] == ']':
      inc(b.pos)
      return                  # nil type
  new(result)
  result.kind = TTypeKind(decodeVInt(b.s, b.pos))
  if b.s[b.pos] == '+':
    inc(b.pos)
    result.id = decodeVInt(b.s, b.pos)
    setId(result.id)
    #if debugIds: registerID(result)
  else:
    internalError(info, "decodeType: no id")
  # here this also avoids endless recursion for recursive type
  r.types[result.id] = result
  if b.s[b.pos] == '(': result.n = decodeNode(r, b, unknownLineInfo())
  if b.s[b.pos] == '$':
    inc(b.pos)
    result.flags = cast[TTypeFlags](int32(decodeVInt(b.s, b.pos)))
  if b.s[b.pos] == '?':
    inc(b.pos)
    result.callConv = TCallingConvention(decodeVInt(b.s, b.pos))
  if b.s[b.pos] == '*':
    inc(b.pos)
    result.owner = loadSym(r, decodeVInt(b.s, b.pos), info)
  if b.s[b.pos] == '&':
    inc(b.pos)
    result.sym = loadSym(r, decodeVInt(b.s, b.pos), info)
  if b.s[b.pos] == '/':
    inc(b.pos)
    result.size = decodeVInt(b.s, b.pos)
  else:
    result.size = - 1
  if b.s[b.pos] == '=':
    inc(b.pos)
    result.align = decodeVInt(b.s, b.pos).int16
  else:
    result.align = 2

  if b.s[b.pos] == '\14':
    inc(b.pos)
    result.lockLevel = decodeVInt(b.s, b.pos).TLockLevel
  else:
    result.lockLevel = UnspecifiedLockLevel

  if b.s[b.pos] == '\15':
    inc(b.pos)
    result.destructor = loadSym(r, decodeVInt(b.s, b.pos), info)
  if b.s[b.pos] == '\16':
    inc(b.pos)
    result.deepCopy = loadSym(r, decodeVInt(b.s, b.pos), info)
  if b.s[b.pos] == '\17':
    inc(b.pos)
    result.assignment = loadSym(r, decodeVInt(b.s, b.pos), info)
  if b.s[b.pos] == '\18':
    inc(b.pos)
    result.sink = loadSym(r, decodeVInt(b.s, b.pos), info)
  while b.s[b.pos] == '\19':
    inc(b.pos)
    let x = decodeVInt(b.s, b.pos)
    doAssert b.s[b.pos] == '\20'
    inc(b.pos)
    let y = loadSym(r, decodeVInt(b.s, b.pos), info)
    result.methods.safeAdd((x, y))
  decodeLoc(r, b, result.loc, info)
  while b.s[b.pos] == '^':
    inc(b.pos)
    if b.s[b.pos] == '(':
      inc(b.pos)
      if b.s[b.pos] == ')': inc(b.pos)
      else: internalError(info, "decodeType ^(" & b.s[b.pos])
      rawAddSon(result, nil)
    else:
      var d = decodeVInt(b.s, b.pos)
      rawAddSon(result, loadType(r, d, info))

proc decodeLib(r; b; info: TLineInfo): PLib =
  result = nil
  if b.s[b.pos] == '|':
    new(result)
    inc(b.pos)
    result.kind = TLibKind(decodeVInt(b.s, b.pos))
    if b.s[b.pos] != '|': internalError("decodeLib: 1")
    inc(b.pos)
    result.name = rope(decodeStr(b.s, b.pos))
    if b.s[b.pos] != '|': internalError("decodeLib: 2")
    inc(b.pos)
    result.path = decodeNode(r, b, info)

proc decodeInstantiations(r; b; info: TLineInfo;
                          s: var seq[PInstantiation]) =
  while b.s[b.pos] == '\15':
    inc(b.pos)
    var ii: PInstantiation
    new ii
    ii.sym = loadSym(r, decodeVInt(b.s, b.pos), info)
    ii.concreteTypes = @[]
    while b.s[b.pos] == '\17':
      inc(b.pos)
      ii.concreteTypes.add loadType(r, decodeVInt(b.s, b.pos), info)
    if b.s[b.pos] == '\20':
      inc(b.pos)
      ii.compilesId = decodeVInt(b.s, b.pos)
    s.safeAdd ii

proc loadSym(r; id: int; info: TLineInfo): PSym =
  var
    id: int
    ident: PIdent
  result = r.syms.getOrDefault(id)
  if result != nil: return result
  var b = loadBlob(sql"select data from syms where nimid = ?", id)
  if b.s[b.pos] == '{':
    inc(b.pos)
    if b.s[b.pos] == '}':
      inc(b.pos)
      return                  # nil sym
  var k = TSymKind(decodeVInt(b.s, b.pos))
  if b.s[b.pos] == '+':
    inc(b.pos)
    id = decodeVInt(b.s, b.pos)
    setId(id)
  else:
    internalError(info, "decodeSym: no id")
  if b.s[b.pos] == '&':
    inc(b.pos)
    ident = r.cache.getIdent(decodeStr(b.s, b.pos))
  else:
    internalError(info, "decodeSym: no ident")
  #echo "decoding: {", ident.s
  new(result)
  result.id = id
  result.kind = k
  result.name = ident         # read the rest of the symbol description:
  r.syms[result.id] = result
  if b.s[b.pos] == '^':
    inc(b.pos)
    result.typ = loadType(r, decodeVInt(b.s, b.pos), info)
  decodeLineInfo(r, b, result.info)
  if b.s[b.pos] == '*':
    inc(b.pos)
    result.owner = loadSym(r, decodeVInt(b.s, b.pos), result.info)
  if b.s[b.pos] == '$':
    inc(b.pos)
    result.flags = cast[TSymFlags](int32(decodeVInt(b.s, b.pos)))
  if b.s[b.pos] == '@':
    inc(b.pos)
    result.magic = TMagic(decodeVInt(b.s, b.pos))
  if b.s[b.pos] == '!':
    inc(b.pos)
    result.options = cast[TOptions](int32(decodeVInt(b.s, b.pos)))
  else:
    result.options = r.module.options
  if b.s[b.pos] == '%':
    inc(b.pos)
    result.position = decodeVInt(b.s, b.pos)
  if b.s[b.pos] == '`':
    inc(b.pos)
    result.offset = decodeVInt(b.s, b.pos)
  else:
    result.offset = - 1
  decodeLoc(r, b, result.loc, result.info)
  result.annex = decodeLib(r, b, info)
  if b.s[b.pos] == '#':
    inc(b.pos)
    result.constraint = decodeNode(r, b, unknownLineInfo())
  case result.kind
  of skType, skGenericParam:
    while b.s[b.pos] == '\14':
      inc(b.pos)
      result.typeInstCache.safeAdd loadType(r, decodeVInt(b.s, b.pos), result.info)
  of routineKinds:
    decodeInstantiations(r, b, result.info, result.procInstCache)
    if b.s[b.pos] == '\16':
      inc(b.pos)
      result.gcUnsafetyReason = loadSym(r, decodeVInt(b.s, b.pos), result.info)
  of skModule, skPackage:
    decodeInstantiations(r, b, result.info, result.usedGenerics)
  of skLet, skVar, skField, skForVar:
    if b.s[b.pos] == '\18':
      inc(b.pos)
      result.guard = loadSym(r, decodeVInt(b.s, b.pos), result.info)
    if b.s[b.pos] == '\19':
      inc(b.pos)
      result.bitsize = decodeVInt(b.s, b.pos).int16
  else: discard

  if b.s[b.pos] == '(':
    #if result.kind in routineKinds:
    #  result.ast = decodeNodeLazyBody(b, result.info, result)
    #else:
    result.ast = decodeNode(r, b, result.info)

proc loadNode*(module: PSym; index: var int): PNode =
  if index == 0:
    index = parseInt db.getValue(
      sql"select min(id) from toplevelstmts where module = ?", abs module.id)
  var b = BlobReader(pos: 0)
  b.s = db.getValue(sql"select data from toplevelstmts where id = ?", index)
  if b.s.len == 0: return nil # end marker
  gr.module = module
  result = decodeNode(gr, b, module.info)

# --------------- Database model ---------------------------------------------

proc createDb() =
  db.exec(sql"""
    create table if not exists controlblock(
      idgen integer not null
    );
  """)

  db.exec(sql"""
    create table if not exists modules(
      id integer primary key,
      fullpath varchar(8000) not null,
      interfHash varchar(256) not null,
      fullHash varchar(256) not null,

      created timestamp not null default (DATETIME('now'))
    );""")
  db.exec(sql"""create unique index if not exists SymNameIx on modules(fullpath);""")

  db.exec(sql"""
    create table if not exists types(
      id integer primary key,
      nimid integer not null,
      module integer not null,
      data blob not null,
      foreign key (module) references module(id)
    );
  """)
  db.exec sql"create index TypeByModuleIdx on types(module);"
  db.exec sql"create index TypeByNimIdIdx on types(nimid);"

  db.exec(sql"""
    create table if not exists syms(
      id integer primary key,
      nimid integer not null,
      module integer not null,
      name varchar(256) not null,
      data blob not null,
      foreign key (module) references module(id)
    );
  """)
  db.exec sql"create index if not exists SymNameIx on syms(name);"
  db.exec sql"create index SymByNameAndModuleIdx on syms(name, module);"
  db.exec sql"create index SymByModuleIdx on syms(module);"
  db.exec sql"create index SymByNimIdIdx on syms(nimid);"


  db.exec(sql"""
    create table if not exists toplevelstmts(
      id integer primary key,
      module integer not null,
      data blob not null,
      foreign key (module) references module(id)
    );
  """)
  db.exec sql"create index TopLevelStmtByModuleIdx on toplevelstmts(module);"


  db.exec(sql"""
    create table if not exists statics(
      id integer primary key,
      module integer not null,
      data blob not null,
      foreign key (module) references module(id)
    );
  """)
  db.exec sql"create index StaticsByModuleIdx on toplevelstmts(module);"
  db.exec sql"insert into controlblock(idgen) values (0)"

proc setupModuleCache* =
  if gSymbolFiles != v2Sf: return
  let dbfile = getNimcacheDir() / "rodfiles.db"
  if not fileExists(dbfile):
    db = open(connection=dbfile, user="nim", password="",
              database="nim")
    createDb()
  else:
    db = open(connection=dbfile, user="nim", password="",
              database="nim")
  db.exec(sql"pragma journal_mode=off")
  db.exec(sql"pragma SYNCHRONOUS=off")
  db.exec(sql"pragma LOCKING_MODE=exclusive")
  idgen.setId(parseInt db.getValue(
    sql"select max(idgen) from controlblock"))

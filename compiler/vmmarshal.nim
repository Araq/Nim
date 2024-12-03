#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Implements marshaling for the VM.

import ast, astalgo, idents, types, msgs,
  options, lineinfos

import std/[streams, json, intsets, tables]

when defined(nimPreviewSlimSystem):
  import std/[assertions, formatfloat]

proc ptrToInt(x: PNode): int {.inline.} =
  result = cast[int](x) # don't skip alignment

proc getField(n: PNode; position: int): PSym =
  case n.kind
  of nkRecList:
    result = nil
    for i in 0..<n.len:
      result = getField(n[i], position)
      if result != nil: return
  of nkRecCase:
    result = getField(n[0], position)
    if result != nil: return
    for i in 1..<n.len:
      case n[i].kind
      of nkOfBranch, nkElse:
        result = getField(lastSon(n[i]), position)
        if result != nil: return
      else: discard
  of nkSym:
    if n.sym.position == position: result = n.sym
    else: result = nil
  else: result = nil

proc storeAny(s: var string; t: PType; a: PNode; stored: var IntSet; conf: ConfigRef)

proc storeObj(s: var string; typ: PType; x: PNode; stored: var IntSet; conf: ConfigRef) =
  assert x.kind == nkObjConstr
  let start = 1
  for i in start..<x.len:
    if i > start: s.add(", ")
    var it = x[i]
    if it.kind == nkExprColonExpr:
      if it[0].kind == nkSym:
        let field = it[0].sym
        s.add(escapeJson(field.name.s))
        s.add(": ")
        storeAny(s, field.typ, it[1], stored, conf)
    elif typ.n != nil:
      let field = getField(typ.n, i)
      s.add(escapeJson(field.name.s))
      s.add(": ")
      storeAny(s, field.typ, it, stored, conf)

proc storeAny(s: var string; t: PType; a: PNode; stored: var IntSet;
              conf: ConfigRef) =
  case t.kind
  of tyNone: assert false
  of tyBool: s.add($(a.intVal != 0))
  of tyChar:
    let ch = char(a.intVal)
    if ch < '\128':
      s.add(escapeJson($ch))
    else:
      s.add($int(ch))
  of tyArray, tySequence:
    if t.kind == tySequence and a.kind == nkNilLit: s.add("null")
    else:
      s.add("[")
      for i in 0..<a.len:
        if i > 0: s.add(", ")
        storeAny(s, t.elemType, a[i], stored, conf)
      s.add("]")
  of tyTuple:
    s.add("{")
    for i, ti in t.ikids:
      if i > 0: s.add(", ")
      s.add("\"Field" & $i)
      s.add("\": ")
      storeAny(s, ti, a[i].skipColon, stored, conf)
    s.add("}")
  of tyObject:
    s.add("{")
    storeObj(s, t, a, stored, conf)
    s.add("}")
  of tySet:
    s.add("[")
    for i in 0..<a.len:
      if i > 0: s.add(", ")
      if a[i].kind == nkRange:
        var x = copyNode(a[i][0])
        storeAny(s, t.elementType, x, stored, conf)
        inc x.intVal
        while x.intVal <= a[i][1].intVal:
          s.add(", ")
          storeAny(s, t.elementType, x, stored, conf)
          inc x.intVal
      else:
        storeAny(s, t.elementType, a[i], stored, conf)
    s.add("]")
  of tyRange, tyGenericInst, tyAlias, tySink:
    storeAny(s, t.skipModifier, a, stored, conf)
  of tyEnum:
    # we need a slow linear search because of enums with holes:
    for e in items(t.n):
      if e.sym.position == a.intVal:
        s.add e.sym.name.s.escapeJson
        break
  of tyPtr, tyRef:
    var x = a
    if isNil(x) or x.kind == nkNilLit: s.add("null")
    elif stored.containsOrIncl(x.ptrToInt):
      # already stored, so we simply write out the pointer as an int:
      s.add($x.ptrToInt)
    else:
      # else as a [value, key] pair:
      # (reversed order for convenient x[0] access!)
      s.add("[")
      s.add($x.ptrToInt)
      s.add(", ")
      storeAny(s, t.elementType, a, stored, conf)
      s.add("]")
  of tyString, tyCstring:
    if a.kind == nkNilLit: s.add("null")
    else: s.add(escapeJson(a.strVal))
  of tyInt..tyInt64, tyUInt..tyUInt64: s.add($a.intVal)
  of tyFloat..tyFloat128: s.add($a.floatVal)
  else:
    internalError conf, a.info, "cannot marshal at compile-time " & t.typeToString

proc storeAny*(s: var string; t: PType; a: PNode; conf: ConfigRef) =
  var stored = initIntSet()
  storeAny(s, t, a, stored, conf)

proc loadAny(p: var JsonParser, t: PType,
             tab: var Table[BiggestInt, PNode];
             cache: IdentCache;
             conf: ConfigRef;
             idgen: IdGenerator): PNode =
  case t.kind
  of tyNone:
    result = nil
    assert false
  of tyBool:
    case p.kind
    of jsonFalse: result = newIntNode(nkIntLit, 0)
    of jsonTrue: result = newIntNode(nkIntLit, 1)
    else: raiseParseErr(p, "'true' or 'false' expected for a bool")
    next(p)
  of tyChar:
    if p.kind == jsonString:
      var x = p.str
      result = nil
      if x.len == 1:
        result = newIntNode(nkIntLit, ord(x[0]))
        next(p)
        return
    elif p.kind == jsonInt:
      result = newIntNode(nkIntLit, getInt(p))
      next(p)
      return
    else:
      result = nil
    raiseParseErr(p, "string of length 1 expected for a char")
  of tyEnum:
    result = nil
    if p.kind == jsonString:
      for e in items(t.n):
        if e.sym.name.s == p.str:
          result = newIntNode(nkIntLit, e.sym.position)
          next(p)
          return
    raiseParseErr(p, "string expected for an enum")
  of tyArray:
    if p.kind != jsonArrayStart: raiseParseErr(p, "'[' expected for an array")
    next(p)
    result = newNode(nkBracket)
    while p.kind != jsonArrayEnd and p.kind != jsonEof:
      result.add loadAny(p, t.elemType, tab, cache, conf, idgen)
    if p.kind == jsonArrayEnd: next(p)
    else: raiseParseErr(p, "']' end of array expected")
  of tySequence:
    case p.kind
    of jsonNull:
      result = newNode(nkNilLit)
      next(p)
    of jsonArrayStart:
      next(p)
      result = newNode(nkBracket)
      while p.kind != jsonArrayEnd and p.kind != jsonEof:
        result.add loadAny(p, t.elemType, tab, cache, conf, idgen)
      if p.kind == jsonArrayEnd: next(p)
      else: raiseParseErr(p, "")
    else:
      result = nil
      raiseParseErr(p, "'[' expected for a seq")
  of tyTuple:
    if p.kind != jsonObjectStart: raiseParseErr(p, "'{' expected for an object")
    next(p)
    result = newNode(nkTupleConstr)
    var i = 0
    let tupleLen = t.kidsLen
    while p.kind != jsonObjectEnd and p.kind != jsonEof:
      if p.kind != jsonString:
        raiseParseErr(p, "string expected for a field name")
      next(p)
      if i >= tupleLen:
        raiseParseErr(p, "too many fields to tuple type " & typeToString(t))
      result.add loadAny(p, t[i], tab, cache, conf, idgen)
      inc i
    if p.kind == jsonObjectEnd: next(p)
    else: raiseParseErr(p, "'}' end of object expected")
  of tyObject:
    if p.kind != jsonObjectStart: raiseParseErr(p, "'{' expected for an object")
    next(p)
    result = newNode(nkObjConstr)
    result.sons = @[newNode(nkEmpty)]
    while p.kind != jsonObjectEnd and p.kind != jsonEof:
      if p.kind != jsonString:
        raiseParseErr(p, "string expected for a field name")
      let ident = getIdent(cache, p.str)
      let field = lookupInRecord(t.n, ident)
      if field.isNil:
        raiseParseErr(p, "unknown field for object of type " & typeToString(t))
      next(p)
      let pos = field.position + 1
      if pos >= result.len:
        setLen(result.sons, pos + 1)
      let fieldNode = newNode(nkExprColonExpr)
      fieldNode.add newSymNode(newSym(skField, ident, idgen, nil, unknownLineInfo))
      fieldNode.add loadAny(p, field.typ, tab, cache, conf, idgen)
      result[pos] = fieldNode
    if p.kind == jsonObjectEnd: next(p)
    else: raiseParseErr(p, "'}' end of object expected")
  of tySet:
    if p.kind != jsonArrayStart: raiseParseErr(p, "'[' expected for a set")
    next(p)
    result = newNode(nkCurly)
    while p.kind != jsonArrayEnd and p.kind != jsonEof:
      result.add loadAny(p, t.elementType, tab, cache, conf, idgen)
    if p.kind == jsonArrayEnd: next(p)
    else: raiseParseErr(p, "']' end of array expected")
  of tyPtr, tyRef:
    case p.kind
    of jsonNull:
      result = newNode(nkNilLit)
      next(p)
    of jsonInt:
      result = tab.getOrDefault(p.getInt)
      if result.isNil:
        raiseParseErr(p, "cannot load object with address " & $p.getInt)
      next(p)
    of jsonArrayStart:
      result = nil
      next(p)
      if p.kind == jsonInt:
        let idx = p.getInt
        next(p)
        result = loadAny(p, t.elementType, tab, cache, conf, idgen)
        tab[idx] = result
      else: raiseParseErr(p, "index for ref type expected")
      if p.kind == jsonArrayEnd: next(p)
      else: raiseParseErr(p, "']' end of ref-address pair expected")
    else:
      result = nil
      raiseParseErr(p, "int for pointer type expected")
  of tyString, tyCstring:
    case p.kind
    of jsonNull:
      result = newNode(nkNilLit)
      next(p)
    of jsonString:
      result = newStrNode(nkStrLit, p.str)
      next(p)
    else:
      result = nil
      raiseParseErr(p, "string expected")
  of tyInt..tyInt64, tyUInt..tyUInt64:
    if p.kind == jsonInt:
      result = newIntNode(nkIntLit, getInt(p))
      next(p)
      return
    else:
      result = nil
    raiseParseErr(p, "int expected")
  of tyFloat..tyFloat128:
    if p.kind == jsonFloat:
      result = newFloatNode(nkFloatLit, getFloat(p))
      next(p)
      return
    else:
      result = nil
    raiseParseErr(p, "float expected")
  of tyRange, tyGenericInst, tyAlias, tySink:
    result = loadAny(p, t.skipModifier, tab, cache, conf, idgen)
  else:
    result = nil
    internalError conf, "cannot marshal at compile-time " & t.typeToString

proc loadAny*(s: string; t: PType; cache: IdentCache; conf: ConfigRef; idgen: IdGenerator): PNode =
  var tab = initTable[BiggestInt, PNode]()
  var p: JsonParser = default(JsonParser)
  open(p, newStringStream(s), "unknown file")
  next(p)
  result = loadAny(p, t, tab, cache, conf, idgen)
  close(p)

#
#
#           The Nim Compiler
#        (c) Copyright 2018 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# included from cgen.nim

## This include file contains the logic to produce constant string
## and seq literals. The code here is responsible that
## ``const x = ["a", "b"]`` works without hidden runtime creation code.
## The price is that seqs and strings are not purely a library
## implementation.

template detectVersion(field, corename) =
  if m.g.field == 0:
    let core = getCompilerProc(m.g.graph, corename)
    if core == nil or core.kind != skConst:
      m.g.field = 1
    else:
      m.g.field = toInt(ast.getInt(core.astdef))
  result = m.g.field

proc detectStrVersion(m: BModule): int =
  detectVersion(strVersion, "nimStrVersion")

proc detectSeqVersion(m: BModule): int =
  detectVersion(seqVersion, "nimSeqVersion")

# ----- Version 1: GC'ed strings and seqs --------------------------------

proc genStringLiteralDataOnlyV1(m: BModule, s: string; result: var Rope) =
  cgsym(m, "TGenericSeq")
  let tmp = getTempName(m)
  result.add tmp
  var res = newBuilder("")
  res.addVarWithTypeAndInitializer(AlwaysConst, name = tmp):
    res.addSimpleStruct(m, name = "", baseType = ""):
      res.addField(name = "Sup", typ = "TGenericSeq")
      res.addArrayField(name = "data", elementType = "NIM_CHAR", len = s.len + 1)
  do:
    var strInit: StructInitializer
    res.addStructInitializer(strInit, kind = siOrderedStruct):
      res.addField(strInit, name = "Sup"):
        var seqInit: StructInitializer
        res.addStructInitializer(seqInit, kind = siOrderedStruct):
          res.addField(seqInit, name = "len"):
            res.addIntValue(s.len)
          res.addField(seqInit, name = "reserved"):
            res.add(cCast("NI", bitOr(cCast("NU", rope(s.len)), "NIM_STRLIT_FLAG")))
      res.addField(strInit, name = "data"):
        res.add(makeCString(s))
  m.s[cfsStrData].add(extract(res))

proc genStringLiteralV1(m: BModule; n: PNode; result: var Builder) =
  if s.isNil:
    result.add(cCast(ptrType(cgsymValue(m, "NimStringDesc")), "NIM_NIL"))
  else:
    let id = nodeTableTestOrSet(m.dataCache, n, m.labels)
    var name: string = ""
    if id == m.labels:
      # string literal not found in the cache:
      genStringLiteralDataOnlyV1(m, n.strVal, name)
    else:
      name = m.tmpBase & $id
    result.add(cCast(ptrType(cgsymValue(m, "NimStringDesc")), cAddr(name)))

# ------ Version 2: destructor based strings and seqs -----------------------

proc genStringLiteralDataOnlyV2(m: BModule, s: string; result: Rope; isConst: bool) =
  var res = newBuilder("")
  res.addVarWithTypeAndInitializer(
      if isConst: AlwaysConst else: Global,
      name = result):
    res.addSimpleStruct(m, name = "", baseType = ""):
      res.addField(name = "cap", typ = "NI")
      res.addArrayField(name = "data", elementType = "NIM_CHAR", len = s.len + 1)
  do:
    var structInit: StructInitializer
    res.addStructInitializer(structInit, kind = siOrderedStruct):
      res.addField(structInit, name = "cap"):
        res.add(bitOr(rope(s.len), "NIM_STRLIT_FLAG"))
      res.addField(structInit, name = "data"):
        res.add(makeCString(s))
  m.s[cfsStrData].add(extract(res))

proc genStringLiteralV2(m: BModule; n: PNode; isConst: bool; result: var Builder) =
  let id = nodeTableTestOrSet(m.dataCache, n, m.labels)
  var litName: string
  if id == m.labels:
    cgsym(m, "NimStrPayload")
    cgsym(m, "NimStringV2")
    # string literal not found in the cache:
    litName = getTempName(m)
    genStringLiteralDataOnlyV2(m, n.strVal, litName, isConst)
  else:
    litName = m.tmpBase & $id
  let tmp = getTempName(m)
  result.add tmp
  var res = newBuilder("")
  res.addVarWithInitializer(
      if isConst: AlwaysConst else: Global,
      name = tmp,
      typ = "NimStringV2"):
    var strInit: StructInitializer
    res.addStructInitializer(strInit, kind = siOrderedStruct):
      res.addField(strInit, name = "len"):
        res.addIntValue(n.strVal.len)
      res.addField(strInit, name = "p"):
        res.add(cCast(ptrType("NimStrPayload"), cAddr(litName)))
  m.s[cfsStrData].add(extract(res))

proc genStringLiteralV2Const(m: BModule; n: PNode; isConst: bool; result: var Builder) =
  let id = nodeTableTestOrSet(m.dataCache, n, m.labels)
  var pureLit: Rope
  if id == m.labels:
    pureLit = getTempName(m)
    cgsym(m, "NimStrPayload")
    cgsym(m, "NimStringV2")
    # string literal not found in the cache:
    genStringLiteralDataOnlyV2(m, n.strVal, pureLit, isConst)
  else:
    pureLit = m.tmpBase & rope(id)
  var strInit: StructInitializer
  result.addStructInitializer(strInit, kind = siOrderedStruct):
    result.addField(strInit, name = "len"):
      result.addIntValue(n.strVal.len)
    result.addField(strInit, name = "p"):
      result.add(cCast(ptrType("NimStrPayload"), cAddr(pureLit)))

# ------ Version selector ---------------------------------------------------

proc genStringLiteralDataOnly(m: BModule; s: string; info: TLineInfo;
                              isConst: bool; result: var Rope) =
  case detectStrVersion(m)
  of 0, 1: genStringLiteralDataOnlyV1(m, s, result)
  of 2:
    let tmp = getTempName(m)
    genStringLiteralDataOnlyV2(m, s, tmp, isConst)
    result.add tmp
  else:
    localError(m.config, info, "cannot determine how to produce code for string literal")

proc genNilStringLiteral(m: BModule; info: TLineInfo; result: var Builder) =
  result.add(cCast(ptrType(cgsymValue(m, "NimStringDesc")), "NIM_NIL"))

proc genStringLiteral(m: BModule; n: PNode; result: var Builder) =
  case detectStrVersion(m)
  of 0, 1: genStringLiteralV1(m, n, result)
  of 2: genStringLiteralV2(m, n, isConst = true, result)
  else:
    localError(m.config, n.info, "cannot determine how to produce code for string literal")

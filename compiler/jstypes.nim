#
#
#           The Nim Compiler
#        (c) Copyright 2013 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# included from jsgen.nim

## Type info generation for the JS backend.

proc rope(arg: Int128): Rope = rope($arg)

proc genTypeInfo(p: PProc, typ: PType): Rope
proc genObjectFields(p: PProc, typ: PType, n: PNode): Rope =
  var
    s, u: Rope
    field: PSym
    b: PNode
  result = ""
  case n.kind
  of nkRecList:
    if n.len == 1:
      result = genObjectFields(p, typ, n[0])
    else:
      s = ""
      for i in 0..<n.len:
        if i > 0: s.add(", \L")
        s.add(genObjectFields(p, typ, n[i]))
      result = ("{kind: 2, len: $1, offset: 0, " &
          "typ: null, name: null, sons: [$2]}") % [rope(n.len), s]
  of nkSym:
    field = n.sym
    s = genTypeInfo(p, field.typ)
    result = ("{kind: 1, offset: \"$1\", len: 0, " &
        "typ: $2, name: $3, sons: null}") %
                   [mangleName(p.module, field), s,
                    makeJSString(field.name.s)]
  of nkRecCase:
    if (n[0].kind != nkSym): internalError(p.config, n.info, "genObjectFields")
    field = n[0].sym
    s = genTypeInfo(p, field.typ)
    for i in 1..<n.len:
      b = n[i]           # branch
      u = ""
      case b.kind
      of nkOfBranch:
        if b.len < 2:
          internalError(p.config, b.info, "genObjectFields; nkOfBranch broken")
        for j in 0..<b.len - 1:
          if u != "": u.add(", ")
          if b[j].kind == nkRange:
            u.addf("[$1, $2]", [rope(getOrdValue(b[j][0])),
                                 rope(getOrdValue(b[j][1]))])
          else:
            u.add(rope(getOrdValue(b[j])))
      of nkElse:
        u = rope(lengthOrd(p.config, field.typ))
      else: internalError(p.config, n.info, "genObjectFields(nkRecCase)")
      if result != "": result.add(", \L")
      result.addf("[setConstr($1), $2]",
           [u, genObjectFields(p, typ, lastSon(b))])
    result = ("{kind: 3, offset: \"$1\", len: $3, " &
        "typ: $2, name: $4, sons: [$5]}") % [
        mangleName(p.module, field), s,
        rope(lengthOrd(p.config, field.typ)), makeJSString(field.name.s), result]
  else: internalError(p.config, n.info, "genObjectFields")

proc objHasTypeField(t: PType): bool {.inline.} =
  tfInheritable in t.flags or t.baseClass != nil

proc genObjectInfo(p: PProc, typ: PType, name: Rope) =
  let kind = if objHasTypeField(typ): tyObject else: tyTuple
  var s = ("var $1 = {size: 0, kind: $2, base: null, node: null, " &
           "finalizer: null};$n") % [name, rope(ord(kind))]
  prepend(p.g.typeInfo, s)
  p.g.typeInfo.addf("var NNI$1 = $2;$n",
       [rope(typ.id), genObjectFields(p, typ, typ.n)])
  p.g.typeInfo.addf("$1.node = NNI$2;$n", [name, rope(typ.id)])
  if (typ.kind == tyObject) and (typ.baseClass != nil):
    p.g.typeInfo.addf("$1.base = $2;$n",
         [name, genTypeInfo(p, typ.baseClass.skipTypes(skipPtrs))])

proc genTupleFields(p: PProc, typ: PType): Rope =
  var s: Rope = ""
  for i in 0..<typ.len:
    if i > 0: s.add(", \L")
    s.addf("{kind: 1, offset: \"Field$1\", len: 0, " &
           "typ: $2, name: \"Field$1\", sons: null}",
           [i.rope, genTypeInfo(p, typ[i])])
  result = ("{kind: 2, len: $1, offset: 0, " &
            "typ: null, name: null, sons: [$2]}") % [rope(typ.len), s]

proc genTupleInfo(p: PProc, typ: PType, name: Rope) =
  var s = ("var $1 = {size: 0, kind: $2, base: null, node: null, " &
           "finalizer: null};$n") % [name, rope(ord(typ.kind))]
  prepend(p.g.typeInfo, s)
  p.g.typeInfo.addf("var NNI$1 = $2;$n",
       [rope(typ.id), genTupleFields(p, typ)])
  p.g.typeInfo.addf("$1.node = NNI$2;$n", [name, rope(typ.id)])

proc genEnumInfo(p: PProc, typ: PType, name: Rope) =
  var s: Rope = ""
  for i in 0..<typ.n.len:
    if (typ.n[i].kind != nkSym): internalError(p.config, typ.n.info, "genEnumInfo")
    let field = typ.n[i].sym
    if i > 0: s.add(", \L")
    let extName = if field.ast == nil: field.name.s else: field.ast.strVal
    s.addf("\"$1\": {kind: 1, offset: $1, typ: $2, name: $3, len: 0, sons: null}",
         [rope(field.position), name, makeJSString(extName)])
  var n = ("var NNI$1 = {kind: 2, offset: 0, typ: null, " &
      "name: null, len: $2, sons: {$3}};$n") % [rope(typ.id), rope(typ.n.len), s]
  s = ("var $1 = {size: 0, kind: $2, base: null, node: null, " &
       "finalizer: null};$n") % [name, rope(ord(typ.kind))]
  prepend(p.g.typeInfo, s)
  p.g.typeInfo.add(n)
  p.g.typeInfo.addf("$1.node = NNI$2;$n", [name, rope(typ.id)])
  if typ.baseClass != nil:
    p.g.typeInfo.addf("$1.base = $2;$n",
         [name, genTypeInfo(p, typ.baseClass)])

proc genTypeInfo(p: PProc, typ: PType): Rope =
  let t = typ.skipTypes({tyGenericInst, tyDistinct, tyAlias, tySink, tyOwned})
  result = "NTI$1" % [rope(t.id)]
  if containsOrIncl(p.g.typeInfoGenerated, t.id): return
  case t.kind
  of tyDistinct:
    result = genTypeInfo(p, t.skipModifier)
  of tyPointer, tyProc, tyBool, tyChar, tyCstring, tyString, tyInt..tyUInt64:
    var s =
      "var $1 = {size: 0,kind: $2,base: null,node: null,finalizer: null};$n" %
      [result, rope(ord(t.kind))]
    prepend(p.g.typeInfo, s)
  of tyVar, tyLent, tyRef, tyPtr, tySequence, tyRange, tySet, tyOpenArray:
    var s =
      "var $1 = {size: 0, kind: $2, base: null, node: null, finalizer: null};$n" %
              [result, rope(ord(t.kind))]
    prepend(p.g.typeInfo, s)
    p.g.typeInfo.addf("$1.base = $2;$n",
         [result, genTypeInfo(p, t.elementType)])
  of tyArray:
    var s =
      "var $1 = {size: 0, kind: $2, base: null, node: null, finalizer: null};$n" %
              [result, rope(ord(t.kind))]
    prepend(p.g.typeInfo, s)
    p.g.typeInfo.addf("$1.base = $2;$n",
         [result, genTypeInfo(p, t.elementType)])
  of tyEnum: genEnumInfo(p, t, result)
  of tyObject: genObjectInfo(p, t, result)
  of tyTuple: genTupleInfo(p, t, result)
  of tyStatic:
    if t.n != nil: result = genTypeInfo(p, skipModifier t)
    else: internalError(p.config, "genTypeInfo(" & $t.kind & ')')
  else: internalError(p.config, "genTypeInfo(" & $t.kind & ')')

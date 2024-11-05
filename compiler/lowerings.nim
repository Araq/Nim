#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements common simple lowerings.

const
  genPrefix* = ":tmp"         # prefix for generated names

import ast, astalgo, types, idents, magicsys, msgs, options, modulegraphs,
  lineinfos

when defined(nimPreviewSlimSystem):
  import std/assertions

proc newDeref*(n: PNode): PNode {.inline.} =
  result = newNodeIT(nkHiddenDeref, n.info, n.typ.elementType)
  result.add n

proc newTupleAccess*(g: ModuleGraph; tup: PNode, i: int): PNode =
  if tup.kind == nkHiddenAddr:
    result = newNodeIT(nkHiddenAddr, tup.info, tup.typ.skipTypes(abstractInst+{tyPtr, tyVar, tyLent}))
    result.add newNodeIT(nkBracketExpr, tup.info, tup.typ.skipTypes(abstractInst+{tyPtr, tyVar, tyLent})[i])
    result[0].add tup[0]
    var lit = newNodeIT(nkIntLit, tup.info, getSysType(g, tup.info, tyInt))
    lit.intVal = i
    result[0].add lit
  else:
    result = newNodeIT(nkBracketExpr, tup.info, tup.typ.skipTypes(
                       abstractInst)[i])
    result.add copyTree(tup)
    var lit = newNodeIT(nkIntLit, tup.info, getSysType(g, tup.info, tyInt))
    lit.intVal = i
    result.add lit

proc addVar*(father, v: PNode) =
  var vpart = newNodeI(nkIdentDefs, v.info, 3)
  vpart[0] = v
  vpart[1] = newNodeI(nkEmpty, v.info)
  vpart[2] = vpart[1]
  father.add vpart

proc addVar*(father, v, value: PNode) =
  var vpart = newNodeI(nkIdentDefs, v.info, 3)
  vpart[0] = v
  vpart[1] = newNodeI(nkEmpty, v.info)
  vpart[2] = value
  father.add vpart

proc newAsgnStmt*(le, ri: PNode): PNode =
  result = newNodeI(nkAsgn, le.info, 2)
  result[0] = le
  result[1] = ri

proc newFastAsgnStmt*(le, ri: PNode): PNode =
  result = newNodeI(nkFastAsgn, le.info, 2)
  result[0] = le
  result[1] = ri

proc newFastMoveStmt*(g: ModuleGraph, le, ri: PNode): PNode =
  result = newNodeI(nkFastAsgn, le.info, 2)
  result[0] = le
  result[1] = newNodeIT(nkCall, ri.info, ri.typ)
  result[1].add newSymNode(getSysMagic(g, ri.info, "move", mMove))
  result[1].add ri

proc lowerTupleUnpacking*(g: ModuleGraph; n: PNode; idgen: IdGenerator; owner: PSym): PNode =
  assert n.kind == nkVarTuple
  let value = n.lastSon
  result = newNodeI(nkStmtList, n.info)

  var tempAsNode: PNode
  let avoidTemp = value.kind == nkSym
  if avoidTemp:
    tempAsNode = value
  else:
    var temp = newSym(skTemp, getIdent(g.cache, genPrefix), idgen,
                  owner, value.info, g.config.options)
    temp.typ = skipTypes(value.typ, abstractInst)
    incl(temp.flags, sfFromGeneric)
    tempAsNode = newSymNode(temp)

  var v = newNodeI(nkVarSection, value.info)
  if not avoidTemp:
    v.addVar(tempAsNode, value)
  result.add(v)

  for i in 0..<n.len-2:
    let val = newTupleAccess(g, tempAsNode, i)
    if n[i].kind == nkSym: v.addVar(n[i], val)
    else: result.add newAsgnStmt(n[i], val)

proc evalOnce*(g: ModuleGraph; value: PNode; idgen: IdGenerator; owner: PSym): PNode =
  ## Turns (value) into (let tmp = value; tmp) so that 'value' can be re-used
  ## freely, multiple times. This is frequently required and such a builtin would also be
  ## handy to have in macros.nim. The value that can be reused is 'result.lastSon'!
  result = newNodeIT(nkStmtListExpr, value.info, value.typ)
  var temp = newSym(skTemp, getIdent(g.cache, genPrefix), idgen,
                    owner, value.info, g.config.options)
  temp.typ = skipTypes(value.typ, abstractInst)
  incl(temp.flags, sfFromGeneric)

  var v = newNodeI(nkLetSection, value.info)
  let tempAsNode = newSymNode(temp)
  v.addVar(tempAsNode)
  result.add(v)
  result.add newAsgnStmt(tempAsNode, value)
  result.add tempAsNode

proc newTupleAccessRaw*(tup: PNode, i: int): PNode =
  result = newNodeI(nkBracketExpr, tup.info)
  result.add copyTree(tup)
  var lit = newNodeI(nkIntLit, tup.info)
  lit.intVal = i
  result.add lit

proc newTryFinally*(body, final: PNode): PNode =
  result = newTree(nkHiddenTryStmt, body, newTree(nkFinally, final))

proc lowerSwap*(g: ModuleGraph; n: PNode; idgen: IdGenerator; owner: PSym): PNode =
  result = newNodeI(nkStmtList, n.info)
  # note: cannot use 'skTemp' here cause we really need the copy for the VM :-(
  var temp = newSym(skVar, getIdent(g.cache, genPrefix), idgen, owner, n.info, owner.options)
  temp.typ = n[1].typ
  incl(temp.flags, sfFromGeneric)
  incl(temp.flags, sfGenSym)

  var v = newNodeI(nkVarSection, n.info)
  let tempAsNode = newSymNode(temp)

  var vpart = newNodeI(nkIdentDefs, v.info, 3)
  vpart[0] = tempAsNode
  vpart[1] = newNodeI(nkEmpty, v.info)
  vpart[2] = n[1]
  v.add vpart

  result.add(v)
  result.add newFastAsgnStmt(n[1], n[2])
  result.add newFastAsgnStmt(n[2], tempAsNode)

proc createObj*(g: ModuleGraph; idgen: IdGenerator; owner: PSym, info: TLineInfo; final=true): PType =
  result = newType(tyObject, idgen, owner)
  if final:
    rawAddSon(result, nil)
    incl result.flags, tfFinal
  else:
    rawAddSon(result, getCompilerProc(g, "RootObj").typ)
  result.n = newNodeI(nkRecList, info)
  let s = newSym(skType, getIdent(g.cache, "Env_" & toFilename(g.config, info) & "_" & $owner.name.s),
                  idgen, owner, info, owner.options)
  incl s.flags, sfAnon
  s.typ = result
  result.sym = s

template fieldCheck {.dirty.} =
  when false:
    if tfCheckedForDestructor in obj.flags:
      echo "missed field ", field.name.s
      writeStackTrace()

proc rawAddField*(obj: PType; field: PSym) =
  assert field.kind == skField
  field.position = obj.n.len
  obj.n.add newSymNode(field)
  propagateToOwner(obj, field.typ)
  fieldCheck()

proc rawIndirectAccess*(a: PNode; field: PSym; info: TLineInfo): PNode =
  # returns a[].field as a node
  assert field.kind == skField
  var deref = newNodeI(nkHiddenDeref, info)
  deref.typ() = a.typ.skipTypes(abstractInst)[0]
  deref.add a
  result = newNodeI(nkDotExpr, info)
  result.add deref
  result.add newSymNode(field)
  result.typ() = field.typ

proc rawDirectAccess*(obj, field: PSym): PNode =
  # returns a.field as a node
  assert field.kind == skField
  result = newNodeI(nkDotExpr, field.info)
  result.add newSymNode(obj)
  result.add newSymNode(field)
  result.typ() = field.typ

proc lookupInRecord(n: PNode, id: ItemId): PSym =
  result = nil
  case n.kind
  of nkRecList:
    for i in 0..<n.len:
      result = lookupInRecord(n[i], id)
      if result != nil: return
  of nkRecCase:
    if n[0].kind != nkSym: return
    result = lookupInRecord(n[0], id)
    if result != nil: return
    for i in 1..<n.len:
      case n[i].kind
      of nkOfBranch, nkElse:
        result = lookupInRecord(lastSon(n[i]), id)
        if result != nil: return
      else: discard
  of nkSym:
    if n.sym.itemId.module == id.module and n.sym.itemId.item == -abs(id.item): result = n.sym
  else: discard

proc addField*(obj: PType; s: PSym; cache: IdentCache; idgen: IdGenerator): PSym =
  # because of 'gensym' support, we have to mangle the name with its ID.
  # This is hacky but the clean solution is much more complex than it looks.
  var field = newSym(skField, getIdent(cache, s.name.s & $obj.n.len),
                     idgen, s.owner, s.info, s.options)
  field.itemId = ItemId(module: s.itemId.module, item: -s.itemId.item)
  let t = skipIntLit(s.typ, idgen)
  field.typ = t
  if s.kind in {skLet, skVar, skField, skForVar}:
    #field.bitsize = s.bitsize
    field.alignment = s.alignment
  assert t.kind != tyTyped
  propagateToOwner(obj, t)
  field.position = obj.n.len
  # sfNoInit flag for skField is used in closureiterator codegen
  field.flags = s.flags * {sfCursor, sfNoInit}
  obj.n.add newSymNode(field)
  fieldCheck()
  result = field

proc addUniqueField*(obj: PType; s: PSym; cache: IdentCache; idgen: IdGenerator): PSym {.discardable.} =
  result = lookupInRecord(obj.n, s.itemId)
  if result == nil:
    var field = newSym(skField, getIdent(cache, s.name.s & $obj.n.len), idgen,
                       s.owner, s.info, s.options)
    field.itemId = ItemId(module: s.itemId.module, item: -s.itemId.item)
    let t = skipIntLit(s.typ, idgen)
    field.typ = t
    assert t.kind != tyTyped
    propagateToOwner(obj, t)
    field.position = obj.n.len
    obj.n.add newSymNode(field)
    result = field

proc newDotExpr*(obj, b: PSym): PNode =
  result = newNodeI(nkDotExpr, obj.info)
  let field = lookupInRecord(obj.typ.n, b.itemId)
  assert field != nil, b.name.s
  result.add newSymNode(obj)
  result.add newSymNode(field)
  result.typ() = field.typ

proc indirectAccess*(a: PNode, b: ItemId, info: TLineInfo): PNode =
  # returns a[].b as a node
  var deref = newNodeI(nkHiddenDeref, info)
  deref.typ() = a.typ.skipTypes(abstractInst).elementType
  var t = deref.typ.skipTypes(abstractInst)
  var field: PSym
  while true:
    assert t.kind == tyObject
    field = lookupInRecord(t.n, b)
    if field != nil: break
    t = t.baseClass
    if t == nil: break
    t = t.skipTypes(skipPtrs)
  #if field == nil:
  #  echo "FIELD ", b
  #  debug deref.typ
  assert field != nil
  deref.add a
  result = newNodeI(nkDotExpr, info)
  result.add deref
  result.add newSymNode(field)
  result.typ() = field.typ

proc indirectAccess*(a: PNode, b: string, info: TLineInfo; cache: IdentCache): PNode =
  # returns a[].b as a node
  var deref = newNodeI(nkHiddenDeref, info)
  deref.typ() = a.typ.skipTypes(abstractInst).elementType
  var t = deref.typ.skipTypes(abstractInst)
  var field: PSym
  let bb = getIdent(cache, b)
  while true:
    assert t.kind == tyObject
    field = getSymFromList(t.n, bb)
    if field != nil: break
    t = t.baseClass
    if t == nil: break
    t = t.skipTypes(skipPtrs)
  #if field == nil:
  #  echo "FIELD ", b
  #  debug deref.typ
  assert field != nil
  deref.add a
  result = newNodeI(nkDotExpr, info)
  result.add deref
  result.add newSymNode(field)
  result.typ() = field.typ

proc getFieldFromObj*(t: PType; v: PSym): PSym =
  assert v.kind != skField
  var t = t
  while true:
    assert t.kind == tyObject
    result = lookupInRecord(t.n, v.itemId)
    if result != nil: break
    t = t.baseClass
    if t == nil: break
    t = t.skipTypes(skipPtrs)

proc indirectAccess*(a: PNode, b: PSym, info: TLineInfo): PNode =
  # returns a[].b as a node
  result = indirectAccess(a, b.itemId, info)

proc indirectAccess*(a, b: PSym, info: TLineInfo): PNode =
  result = indirectAccess(newSymNode(a), b, info)

proc genAddrOf*(n: PNode; idgen: IdGenerator; typeKind = tyPtr): PNode =
  result = newNodeI(nkAddr, n.info, 1)
  result[0] = n
  result.typ() = newType(typeKind, idgen, n.typ.owner)
  result.typ.rawAddSon(n.typ)

proc genDeref*(n: PNode; k = nkHiddenDeref): PNode =
  result = newNodeIT(k, n.info,
                     n.typ.skipTypes(abstractInst).elementType)
  result.add n

proc callCodegenProc*(g: ModuleGraph; name: string;
                      info: TLineInfo = unknownLineInfo;
                      arg1: PNode = nil, arg2: PNode = nil,
                      arg3: PNode = nil, optionalArgs: PNode = nil): PNode =
  result = newNodeI(nkCall, info)
  let sym = magicsys.getCompilerProc(g, name)
  if sym == nil:
    localError(g.config, info, "system module needs: " & name)
  else:
    result.add newSymNode(sym)
    if arg1 != nil: result.add arg1
    if arg2 != nil: result.add arg2
    if arg3 != nil: result.add arg3
    if optionalArgs != nil:
      for i in 1..<optionalArgs.len-2:
        result.add optionalArgs[i]
    result.typ() = sym.typ.returnType

proc newIntLit*(g: ModuleGraph; info: TLineInfo; value: BiggestInt): PNode =
  result = nkIntLit.newIntNode(value)
  result.typ() = getSysType(g, info, tyInt)

proc genHigh*(g: ModuleGraph; n: PNode): PNode =
  if skipTypes(n.typ, abstractVar).kind == tyArray:
    result = newIntLit(g, n.info, toInt64(lastOrd(g.config, skipTypes(n.typ, abstractVar))))
  else:
    result = newNodeI(nkCall, n.info, 2)
    result.typ() = getSysType(g, n.info, tyInt)
    result[0] = newSymNode(getSysMagic(g, n.info, "high", mHigh))
    result[1] = n

proc genLen*(g: ModuleGraph; n: PNode): PNode =
  if skipTypes(n.typ, abstractVar).kind == tyArray:
    result = newIntLit(g, n.info, toInt64(lastOrd(g.config, skipTypes(n.typ, abstractVar)) + 1))
  else:
    result = newNodeI(nkCall, n.info, 2)
    result.typ() = getSysType(g, n.info, tyInt)
    result[0] = newSymNode(getSysMagic(g, n.info, "len", mLengthSeq))
    result[1] = n


#
#
#           The Nim Compiler
#        (c) Copyright 2020 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# included from cgen.nim

## Code specialization instead of the old, incredibly slow 'genericReset'
## implementation.

proc specializeResetT(p: BProc, accessor: Rope, typ: PType)

proc specializeResetN(p: BProc, accessor: Rope, n: PNode;
                     typ: PType) =
  if n == nil: return
  case n.kind
  of nkRecList:
    for i in 0..<n.len:
      specializeResetN(p, accessor, n[i], typ)
  of nkRecCase:
    if (n[0].kind != nkSym): internalError(p.config, n.info, "specializeResetN")
    let disc = n[0].sym
    if disc.loc.snippet == "": fillObjectFields(p.module, typ)
    if disc.loc.t == nil:
      internalError(p.config, n.info, "specializeResetN()")
    let discField = dotField(accessor, disc.loc.snippet)
    p.s(cpsStmts).addSwitchStmt(discField):
      for i in 1..<n.len:
        let branch = n[i]
        assert branch.kind in {nkOfBranch, nkElse}
        var caseBuilder: SwitchCaseBuilder
        p.s(cpsStmts).addSwitchCase(caseBuilder):
          if branch.kind == nkOfBranch:
            genCaseRange(p, branch, caseBuilder)
          else:
            p.s(cpsStmts).addCaseElse(caseBuilder)
        do:
          specializeResetN(p, accessor, lastSon(branch), typ)
          p.s(cpsStmts).addBreak()
    specializeResetT(p, discField, disc.loc.t)
  of nkSym:
    let field = n.sym
    if field.typ.kind == tyVoid: return
    if field.loc.snippet == "": fillObjectFields(p.module, typ)
    if field.loc.t == nil:
      internalError(p.config, n.info, "specializeResetN()")
    specializeResetT(p, dotField(accessor, field.loc.snippet), field.loc.t)
  else: internalError(p.config, n.info, "specializeResetN()")

proc specializeResetT(p: BProc, accessor: Rope, typ: PType) =
  if typ == nil: return

  case typ.kind
  of tyGenericInst, tyGenericBody, tyTypeDesc, tyAlias, tyDistinct, tyInferred,
     tySink, tyOwned:
    specializeResetT(p, accessor, skipModifier(typ))
  of tyArray:
    let arraySize = lengthOrd(p.config, typ.indexType)
    var i: TLoc = getTemp(p, getSysType(p.module.g.graph, unknownLineInfo, tyInt))
    p.s(cpsStmts).addForRangeExclusive(i.snippet, cIntValue(0), cIntValue(arraySize)):
      specializeResetT(p, subscript(accessor, i.snippet), typ.elementType)
  of tyObject:
    var x = typ.baseClass
    if x != nil: x = x.skipTypes(skipPtrs)
    specializeResetT(p, accessor.parentObj(p.module), x)
    if typ.n != nil: specializeResetN(p, accessor, typ.n, typ)
  of tyTuple:
    let typ = getUniqueType(typ)
    for i, a in typ.ikids:
      specializeResetT(p, dotField(accessor, "Field" & $i), a)

  of tyString, tyRef, tySequence:
    p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "unsureAsgnRef"),
      cCast(ptrType(CPointer), cAddr(accessor)),
      NimNil)

  of tyProc:
    if typ.callConv == ccClosure:
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "unsureAsgnRef"),
        cCast(ptrType(CPointer), cAddr(dotField(accessor, "ClE_0"))),
        NimNil)
      p.s(cpsStmts).addFieldAssignment(accessor, "ClP_0", NimNil)
    else:
      p.s(cpsStmts).addAssignment(accessor, NimNil)
  of tyChar, tyBool, tyEnum, tyRange, tyInt..tyUInt64:
    p.s(cpsStmts).addAssignment(accessor, cIntValue(0))
  of tyCstring, tyPointer, tyPtr, tyVar, tyLent:
    p.s(cpsStmts).addAssignment(accessor, NimNil)
  of tySet:
    case mapSetType(p.config, typ)
    of ctArray:
      let t = getTypeDesc(p.module, typ)
      p.s(cpsStmts).addCallStmt(cgsymValue(p.module, "nimZeroMem"),
        accessor,
        cSizeof(t))
    of ctInt8, ctInt16, ctInt32, ctInt64:
      p.s(cpsStmts).addAssignment(accessor, cIntValue(0))
    else:
      raiseAssert "unexpected set type kind"
  of tyNone, tyEmpty, tyNil, tyUntyped, tyTyped, tyGenericInvocation,
      tyGenericParam, tyOrdinal, tyOpenArray, tyForward, tyVarargs,
      tyUncheckedArray, tyError, tyBuiltInTypeClass, tyUserTypeClass,
      tyUserTypeClassInst, tyCompositeTypeClass, tyAnd, tyOr, tyNot,
      tyAnything, tyStatic, tyFromExpr, tyConcept, tyVoid, tyIterable:
    discard

proc specializeReset(p: BProc, a: TLoc) =
  specializeResetT(p, rdLoc(a), a.t)

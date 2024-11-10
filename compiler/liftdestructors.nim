#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements lifting for type-bound operations
## (`=sink`, `=copy`, `=destroy`, `=deepCopy`, `=wasMoved`, `=dup`).

import modulegraphs, lineinfos, idents, ast, renderer, semdata,
  sighashes, lowerings, options, types, msgs, magicsys, ccgutils

import std/tables
from trees import isCaseObj

when defined(nimPreviewSlimSystem):
  import std/assertions

type
  TLiftCtx = object
    g: ModuleGraph
    info: TLineInfo # for construction
    kind: TTypeAttachedOp
    fn: PSym
    asgnForType: PType
    recurse: bool
    addMemReset: bool    # add wasMoved() call after destructor call
    canRaise: bool
    filterDiscriminator: PSym  # we generating destructor for case branch
    c: PContext # c can be nil, then we are called from lambdalifting!
    idgen: IdGenerator

template destructor*(t: PType): PSym = getAttachedOp(c.g, t, attachedDestructor)
template assignment*(t: PType): PSym = getAttachedOp(c.g, t, attachedAsgn)
template dup*(t: PType): PSym = getAttachedOp(c.g, t, attachedDup)
template asink*(t: PType): PSym = getAttachedOp(c.g, t, attachedSink)

proc fillBody(c: var TLiftCtx; t: PType; body, x, y: PNode)
proc produceSym(g: ModuleGraph; c: PContext; typ: PType; kind: TTypeAttachedOp;
              info: TLineInfo; idgen: IdGenerator; isDistinct = false): PSym

proc createTypeBoundOps*(g: ModuleGraph; c: PContext; orig: PType; info: TLineInfo;
                         idgen: IdGenerator)

proc at(a, i: PNode, elemType: PType): PNode =
  result = newNodeI(nkBracketExpr, a.info, 2)
  result[0] = a
  result[1] = i
  result.typ() = elemType

proc destructorOverridden(g: ModuleGraph; t: PType): bool =
  let op = getAttachedOp(g, t, attachedDestructor)
  op != nil and sfOverridden in op.flags

proc fillBodyTup(c: var TLiftCtx; t: PType; body, x, y: PNode) =
  for i, a in t.ikids:
    let lit = lowerings.newIntLit(c.g, x.info, i)
    let b = if c.kind == attachedTrace: y else: y.at(lit, a)
    fillBody(c, a, body, x.at(lit, a), b)

proc dotField(x: PNode, f: PSym): PNode =
  result = newNodeI(nkDotExpr, x.info, 2)
  if x.typ.skipTypes(abstractInst).kind == tyVar:
    result[0] = x.newDeref
  else:
    result[0] = x
  result[1] = newSymNode(f, x.info)
  result.typ() = f.typ

proc newAsgnStmt(le, ri: PNode): PNode =
  result = newNodeI(nkAsgn, le.info, 2)
  result[0] = le
  result[1] = ri

proc genBuiltin*(g: ModuleGraph; idgen: IdGenerator; magic: TMagic; name: string; i: PNode): PNode =
  result = newNodeI(nkCall, i.info)
  result.add createMagic(g, idgen, name, magic).newSymNode
  result.add i

proc genBuiltin(c: var TLiftCtx; magic: TMagic; name: string; i: PNode): PNode =
  result = genBuiltin(c.g, c.idgen, magic, name, i)

proc defaultOp(c: var TLiftCtx; t: PType; body, x, y: PNode) =
  if c.kind in {attachedAsgn, attachedDeepCopy, attachedSink, attachedDup}:
    body.add newAsgnStmt(x, y)
  elif c.kind == attachedDestructor and c.addMemReset:
    let call = genBuiltin(c, mDefault, "default", x)
    call.typ() = t
    body.add newAsgnStmt(x, call)
  elif c.kind == attachedWasMoved:
    body.add genBuiltin(c, mWasMoved, "`=wasMoved`", x)

proc genAddr(c: var TLiftCtx; x: PNode): PNode =
  if x.kind == nkHiddenDeref:
    checkSonsLen(x, 1, c.g.config)
    result = x[0]
  else:
    result = newNodeIT(nkHiddenAddr, x.info, makeVarType(x.typ.owner, x.typ, c.idgen))
    result.add x

proc genWhileLoop(c: var TLiftCtx; i, dest: PNode): PNode =
  result = newNodeI(nkWhileStmt, c.info, 2)
  let cmp = genBuiltin(c, mLtI, "<", i)
  cmp.add genLen(c.g, dest)
  cmp.typ() = getSysType(c.g, c.info, tyBool)
  result[0] = cmp
  result[1] = newNodeI(nkStmtList, c.info)

proc genIf(c: var TLiftCtx; cond, action: PNode): PNode =
  result = newTree(nkIfStmt, newTree(nkElifBranch, cond, action))

proc genContainerOf(c: var TLiftCtx; objType: PType, field, x: PSym): PNode =
  # generate: cast[ptr ObjType](cast[int](addr(x)) - offsetOf(objType.field))
  let intType = getSysType(c.g, unknownLineInfo, tyInt)

  let addrOf = newNodeIT(nkAddr, c.info, makePtrType(x.owner, x.typ, c.idgen))
  addrOf.add newDeref(newSymNode(x))
  let castExpr1 = newNodeIT(nkCast, c.info, intType)
  castExpr1.add newNodeIT(nkType, c.info, intType)
  castExpr1.add addrOf

  let dotExpr = newNodeIT(nkDotExpr, c.info, x.typ)
  dotExpr.add newNodeIT(nkType, c.info, objType)
  dotExpr.add newSymNode(field)

  let offsetOf = genBuiltin(c, mOffsetOf, "offsetof", dotExpr)
  offsetOf.typ() = intType

  let minusExpr = genBuiltin(c, mSubI, "-", castExpr1)
  minusExpr.typ() = intType
  minusExpr.add offsetOf

  let objPtr = makePtrType(objType.owner, objType, c.idgen)
  result = newNodeIT(nkCast, c.info, objPtr)
  result.add newNodeIT(nkType, c.info, objPtr)
  result.add minusExpr

proc destructorCall(c: var TLiftCtx; op: PSym; x: PNode): PNode =
  var destroy = newNodeIT(nkCall, x.info, op.typ.returnType)
  destroy.add(newSymNode(op))
  if op.typ.firstParamType.kind != tyVar:
    destroy.add x
  else:
    destroy.add genAddr(c, x)
  if sfNeverRaises notin op.flags:
    c.canRaise = true
  if c.addMemReset:
    result = newTree(nkStmtList, destroy, genBuiltin(c, mWasMoved,  "`=wasMoved`", x))
  else:
    result = destroy

proc genWasMovedCall(c: var TLiftCtx; op: PSym; x: PNode): PNode =
  result = newNodeIT(nkCall, x.info, op.typ.returnType)
  result.add(newSymNode(op))
  result.add genAddr(c, x)

proc fillBodyObj(c: var TLiftCtx; n, body, x, y: PNode; enforceDefaultOp: bool, enforceWasMoved = false) =
  case n.kind
  of nkSym:
    if c.filterDiscriminator != nil: return
    let f = n.sym
    let b = if c.kind == attachedTrace: y else: y.dotField(f)
    if (sfCursor in f.flags and c.g.config.selectedGC in {gcArc, gcAtomicArc, gcOrc, gcHooks}) or
        enforceDefaultOp:
      defaultOp(c, f.typ, body, x.dotField(f), b)
    else:
      if enforceWasMoved:
        body.add genBuiltin(c, mWasMoved, "`=wasMoved`", x.dotField(f))
      fillBody(c, f.typ, body, x.dotField(f), b)
  of nkNilLit: discard
  of nkRecCase:
    # XXX This is only correct for 'attachedSink'!
    var localEnforceDefaultOp = enforceDefaultOp
    if c.kind == attachedSink:
      # the value needs to be destroyed before we assign the selector
      # or the value is lost
      let prevKind = c.kind
      let prevAddMemReset = c.addMemReset
      c.kind = attachedDestructor
      c.addMemReset = true
      fillBodyObj(c, n, body, x, y, enforceDefaultOp = false)
      c.kind = prevKind
      c.addMemReset = prevAddMemReset
      localEnforceDefaultOp = true

    if c.kind != attachedDestructor:
      # copy the selector before case stmt, but destroy after case stmt
      fillBodyObj(c, n[0], body, x, y, enforceDefaultOp = false)

    let oldfilterDiscriminator = c.filterDiscriminator
    if c.filterDiscriminator == n[0].sym:
      c.filterDiscriminator = nil # we have found the case part, proceed as normal

    # we need to generate a case statement:
    var caseStmt = newNodeI(nkCaseStmt, c.info)
    # XXX generate 'if' that checks same branches
    # generate selector:
    var access = dotField(x, n[0].sym)
    caseStmt.add(access)
    var emptyBranches = 0
    # copy the branches over, but replace the fields with the for loop body:
    for i in 1..<n.len:
      var branch = copyTree(n[i])
      branch[^1] = newNodeI(nkStmtList, c.info)

      fillBodyObj(c, n[i].lastSon, branch[^1], x, y,
                  enforceDefaultOp = localEnforceDefaultOp, enforceWasMoved = c.kind == attachedAsgn)
      if branch[^1].len == 0: inc emptyBranches
      caseStmt.add(branch)
    if emptyBranches != n.len-1:
      body.add(caseStmt)

    if c.kind == attachedDestructor:
      # destructor for selector is done after case stmt
      fillBodyObj(c, n[0], body, x, y, enforceDefaultOp = false)
    c.filterDiscriminator = oldfilterDiscriminator
  of nkRecList:
    for t in items(n): fillBodyObj(c, t, body, x, y, enforceDefaultOp, enforceWasMoved)
  else:
    illFormedAstLocal(n, c.g.config)

proc fillBodyObjTImpl(c: var TLiftCtx; t: PType, body, x, y: PNode) =
  if t.baseClass != nil:
    let dest = newNodeIT(nkHiddenSubConv, c.info, t.baseClass)
    dest.add newNodeI(nkEmpty, c.info)
    dest.add x
    var src = y
    if c.kind in {attachedAsgn, attachedDeepCopy, attachedSink}:
      src = newNodeIT(nkHiddenSubConv, c.info, t.baseClass)
      src.add newNodeI(nkEmpty, c.info)
      src.add y

    fillBody(c, skipTypes(t.baseClass, abstractPtrs), body, dest, src)
  fillBodyObj(c, t.n, body, x, y, enforceDefaultOp = false)

proc fillBodyObjT(c: var TLiftCtx; t: PType, body, x, y: PNode) =
  var hasCase = isCaseObj(t.n)
  var obj = t
  while obj.baseClass != nil:
    obj = skipTypes(obj.baseClass, abstractPtrs)
    hasCase = hasCase or isCaseObj(obj.n)

  if hasCase and c.kind in {attachedAsgn, attachedDeepCopy}:
    # assignment for case objects is complex, we do:
    # =destroy(dest)
    # wasMoved(dest)
    # for every field:
    #   `=` dest.field, src.field
    # ^ this is what we used to do, but for 'result = result.sons[0]' it
    # destroys 'result' too early.
    # So this is what we really need to do:
    # let blob {.cursor.} = dest # remembers the old dest.kind
    # wasMoved(dest)
    # dest.kind = src.kind
    # for every field (dependent on dest.kind):
    #   `=` dest.field, src.field
    # =destroy(blob)
    var dummy = newSym(skTemp, getIdent(c.g.cache, lowerings.genPrefix), c.idgen, c.fn, c.info)
    dummy.typ = y.typ
    if ccgIntroducedPtr(c.g.config, dummy, y.typ):
      # Because of potential aliasing when the src param is passed by ref, we need to check for equality here,
      # because the wasMoved(dest) call would zero out src, if dest aliases src.
      var cond = newTree(nkCall, newSymNode(c.g.getSysMagic(c.info, "==", mEqRef)),
        newTreeIT(nkAddr, c.info, makePtrType(c.fn, x.typ, c.idgen), x), newTreeIT(nkAddr, c.info, makePtrType(c.fn, y.typ, c.idgen), y))
      cond.typ() = getSysType(c.g, x.info, tyBool)
      body.add genIf(c, cond, newTreeI(nkReturnStmt, c.info, newNodeI(nkEmpty, c.info)))
    var temp = newSym(skTemp, getIdent(c.g.cache, lowerings.genPrefix), c.idgen, c.fn, c.info)
    temp.typ = x.typ
    incl(temp.flags, sfFromGeneric)
    var v = newNodeI(nkVarSection, c.info)
    let blob = newSymNode(temp)
    v.addVar(blob, x)
    body.add v
    #body.add newAsgnStmt(blob, x)

    var wasMovedCall = newNodeI(nkCall, c.info)
    wasMovedCall.add(newSymNode(createMagic(c.g, c.idgen, "`=wasMoved`", mWasMoved)))
    wasMovedCall.add x # mWasMoved does not take the address
    body.add wasMovedCall

    fillBodyObjTImpl(c, t, body, x, y)
    when false:
      # does not work yet due to phase-ordering problems:
      assert t.destructor != nil
      body.add destructorCall(c.g, t.destructor, blob)
    let prevKind = c.kind
    c.kind = attachedDestructor
    fillBodyObjTImpl(c, t, body, blob, y)
    c.kind = prevKind

  else:
    fillBodyObjTImpl(c, t, body, x, y)

proc boolLit*(g: ModuleGraph; info: TLineInfo; value: bool): PNode =
  result = newIntLit(g, info, ord value)
  result.typ() = getSysType(g, info, tyBool)

proc getCycleParam(c: TLiftCtx): PNode =
  assert c.kind in {attachedAsgn, attachedDup}
  if c.fn.typ.len == 3 + ord(c.kind == attachedAsgn):
    result = c.fn.typ.n.lastSon
    assert result.kind == nkSym
    assert result.sym.name.s == "cyclic"
  else:
    result = boolLit(c.g, c.info, true)

proc newHookCall(c: var TLiftCtx; op: PSym; x, y: PNode): PNode =
  #if sfError in op.flags:
  #  localError(c.config, x.info, "usage of '$1' is a user-defined error" % op.name.s)
  result = newNodeI(nkCall, x.info)
  result.add newSymNode(op)
  if sfNeverRaises notin op.flags:
    c.canRaise = true
  if op.typ.firstParamType.kind == tyVar:
    result.add genAddr(c, x)
  else:
    result.add x
  if y != nil:
    result.add y
  if op.typ.signatureLen == 4:
    assert y != nil
    if c.fn.typ.signatureLen == 4:
      result.add getCycleParam(c)
    else:
      # assume the worst: A cycle is created:
      result.add boolLit(c.g, y.info, true)

proc newOpCall(c: var TLiftCtx; op: PSym; x: PNode): PNode =
  result = newNodeIT(nkCall, x.info, op.typ.returnType)
  result.add(newSymNode(op))
  result.add x
  if sfNeverRaises notin op.flags:
    c.canRaise = true

  if c.kind == attachedDup and op.typ.len == 3:
    assert x != nil
    if c.fn.typ.len == 3:
      result.add getCycleParam(c)
    else:
      # assume the worst: A cycle is created:
      result.add boolLit(c.g, x.info, true)

proc newDeepCopyCall(c: var TLiftCtx; op: PSym; x, y: PNode): PNode =
  result = newAsgnStmt(x, newOpCall(c, op, y))

proc newDupCall(c: var TLiftCtx; op: PSym; x, y: PNode): PNode =
  result = newAsgnStmt(x, newOpCall(c, op, y))

proc usesBuiltinArc(t: PType): bool =
  proc wrap(t: PType): bool {.nimcall.} = ast.isGCedMem(t)
  result = types.searchTypeFor(t, wrap)

proc useNoGc(c: TLiftCtx; t: PType): bool {.inline.} =
  result = optSeqDestructors in c.g.config.globalOptions and
    ({tfHasGCedMem, tfHasOwned} * t.flags != {} or usesBuiltinArc(t))

proc requiresDestructor(c: TLiftCtx; t: PType): bool {.inline.} =
  result = optSeqDestructors in c.g.config.globalOptions and
    containsGarbageCollectedRef(t)

proc instantiateGeneric(c: var TLiftCtx; op: PSym; t, typeInst: PType): PSym =
  if c.c != nil and typeInst != nil:
    result = c.c.instTypeBoundOp(c.c, op, typeInst, c.info, attachedAsgn, 1)
  else:
    localError(c.g.config, c.info,
      "cannot generate destructor for generic type: " & typeToString(t))
    result = nil

proc considerAsgnOrSink(c: var TLiftCtx; t: PType; body, x, y: PNode;
                        field: var PSym): bool =
  if optSeqDestructors in c.g.config.globalOptions:
    var op = field
    let destructorOverridden = destructorOverridden(c.g, t)
    if op != nil and op != c.fn and
        (sfOverridden in op.flags or destructorOverridden):
      if sfError in op.flags:
        incl c.fn.flags, sfError
      #else:
      #  markUsed(c.g.config, c.info, op, c.g.usageSym)
      onUse(c.info, op)
      body.add newHookCall(c, op, x, y)
      result = true
    elif op == nil and destructorOverridden:
      op = produceSym(c.g, c.c, t, c.kind, c.info, c.idgen)
      body.add newHookCall(c, op, x, y)
      result = true
    else:
      result = false
  elif tfHasAsgn in t.flags:
    var op: PSym
    if sameType(t, c.asgnForType):
      # generate recursive call:
      if c.recurse:
        op = c.fn
      else:
        c.recurse = true
        return false
    else:
      op = field
      if op == nil:
        op = produceSym(c.g, c.c, t, c.kind, c.info, c.idgen)
    if sfError in op.flags:
      incl c.fn.flags, sfError
    #else:
    #  markUsed(c.g.config, c.info, op, c.g.usageSym)
    onUse(c.info, op)
    # We also now do generic instantiations in the destructor lifting pass:
    if op.ast.isGenericRoutine:
      op = instantiateGeneric(c, op, t, t.typeInst)
      field = op
      #echo "trying to use ", op.ast
      #echo "for ", op.name.s, " "
      #debug(t)
      #return false
    assert op.ast[genericParamsPos].kind == nkEmpty
    body.add newHookCall(c, op, x, y)
    result = true
  else:
    result = false

proc addDestructorCall(c: var TLiftCtx; orig: PType; body, x: PNode) =
  let t = orig.skipTypes(abstractInst - {tyDistinct})
  var op = t.destructor

  if op != nil and sfOverridden in op.flags:
    if op.ast.isGenericRoutine:
      # patch generic destructor:
      op = instantiateGeneric(c, op, t, t.typeInst)
      setAttachedOp(c.g, c.idgen.module, t, attachedDestructor, op)

  if op == nil and (useNoGc(c, t) or requiresDestructor(c, t)):
    op = produceSym(c.g, c.c, t, attachedDestructor, c.info, c.idgen)
    doAssert op != nil
    doAssert op == t.destructor

  if op != nil:
    #markUsed(c.g.config, c.info, op, c.g.usageSym)
    onUse(c.info, op)
    body.add destructorCall(c, op, x)
  elif useNoGc(c, t):
    internalError(c.g.config, c.info,
      "type-bound operator could not be resolved")

proc considerUserDefinedOp(c: var TLiftCtx; t: PType; body, x, y: PNode): bool =
  case c.kind
  of attachedDestructor:
    var op = t.destructor
    if op != nil and sfOverridden in op.flags:

      if op.ast.isGenericRoutine:
        # patch generic destructor:
        op = instantiateGeneric(c, op, t, t.typeInst)
        setAttachedOp(c.g, c.idgen.module, t, attachedDestructor, op)

      #markUsed(c.g.config, c.info, op, c.g.usageSym)
      onUse(c.info, op)
      body.add destructorCall(c, op, x)
      result = true
    else:
      result = false
    #result = addDestructorCall(c, t, body, x)
  of attachedAsgn, attachedSink, attachedTrace:
    var op = getAttachedOp(c.g, t, c.kind)
    if op != nil and sfOverridden in op.flags:
      if op.ast.isGenericRoutine:
        # patch generic =trace:
        op = instantiateGeneric(c, op, t, t.typeInst)
        setAttachedOp(c.g, c.idgen.module, t, c.kind, op)

    result = considerAsgnOrSink(c, t, body, x, y, op)
    if op != nil:
      setAttachedOp(c.g, c.idgen.module, t, c.kind, op)

  of attachedDeepCopy:
    let op = getAttachedOp(c.g, t, attachedDeepCopy)
    if op != nil:
      #markUsed(c.g.config, c.info, op, c.g.usageSym)
      onUse(c.info, op)
      body.add newDeepCopyCall(c, op, x, y)
      result = true
    else:
      result = false

  of attachedWasMoved:
    var op = getAttachedOp(c.g, t, attachedWasMoved)
    if op != nil and sfOverridden in op.flags:

      if op.ast.isGenericRoutine:
        # patch generic destructor:
        op = instantiateGeneric(c, op, t, t.typeInst)
        setAttachedOp(c.g, c.idgen.module, t, attachedWasMoved, op)

      #markUsed(c.g.config, c.info, op, c.g.usageSym)
      onUse(c.info, op)
      body.add genWasMovedCall(c, op, x)
      result = true
    else:
      result = false

  of attachedDup:
    var op = getAttachedOp(c.g, t, attachedDup)
    if op != nil and sfOverridden in op.flags:

      if op.ast.isGenericRoutine:
        # patch generic destructor:
        op = instantiateGeneric(c, op, t, t.typeInst)
        setAttachedOp(c.g, c.idgen.module, t, attachedDup, op)

      #markUsed(c.g.config, c.info, op, c.g.usageSym)
      onUse(c.info, op)
      body.add newDupCall(c, op, x, y)
      result = true
    else:
      result = false

proc declareCounter(c: var TLiftCtx; body: PNode; first: BiggestInt): PNode =
  var temp = newSym(skTemp, getIdent(c.g.cache, lowerings.genPrefix), c.idgen, c.fn, c.info)
  temp.typ = getSysType(c.g, body.info, tyInt)
  incl(temp.flags, sfFromGeneric)

  var v = newNodeI(nkVarSection, c.info)
  result = newSymNode(temp)
  v.addVar(result, lowerings.newIntLit(c.g, body.info, first))
  body.add v

proc declareTempOf(c: var TLiftCtx; body: PNode; value: PNode): PNode =
  var temp = newSym(skTemp, getIdent(c.g.cache, lowerings.genPrefix), c.idgen, c.fn, c.info)
  temp.typ = value.typ
  incl(temp.flags, sfFromGeneric)

  var v = newNodeI(nkVarSection, c.info)
  result = newSymNode(temp)
  v.addVar(result, value)
  body.add v

proc addIncStmt(c: var TLiftCtx; body, i: PNode) =
  let incCall = genBuiltin(c, mInc, "inc", i)
  incCall.add lowerings.newIntLit(c.g, c.info, 1)
  body.add incCall

proc newSeqCall(c: var TLiftCtx; x, y: PNode): PNode =
  # don't call genAddr(c, x) here:
  result = genBuiltin(c, mNewSeq, "newSeq", x)
  let lenCall = genBuiltin(c, mLengthSeq, "len", y)
  lenCall.typ() = getSysType(c.g, x.info, tyInt)
  result.add lenCall

proc setLenStrCall(c: var TLiftCtx; x, y: PNode): PNode =
  let lenCall = genBuiltin(c, mLengthStr, "len", y)
  lenCall.typ() = getSysType(c.g, x.info, tyInt)
  result = genBuiltin(c, mSetLengthStr, "setLen", x) # genAddr(g, x))
  result.add lenCall

proc setLenSeqCall(c: var TLiftCtx; t: PType; x, y: PNode): PNode =
  let lenCall = genBuiltin(c, mLengthSeq, "len", y)
  lenCall.typ() = getSysType(c.g, x.info, tyInt)
  var op = getSysMagic(c.g, x.info, "setLen", mSetLengthSeq)
  op = instantiateGeneric(c, op, t, t)
  result = newTree(nkCall, newSymNode(op, x.info), x, lenCall)

proc forallElements(c: var TLiftCtx; t: PType; body, x, y: PNode) =
  let counterIdx = body.len
  let i = declareCounter(c, body, toInt64(firstOrd(c.g.config, t)))
  let whileLoop = genWhileLoop(c, i, x)
  let elemType = t.elementType
  let b = if c.kind == attachedTrace: y else: y.at(i, elemType)
  fillBody(c, elemType, whileLoop[1], x.at(i, elemType), b)
  if whileLoop[1].len > 0:
    addIncStmt(c, whileLoop[1], i)
    body.add whileLoop
  else:
    body.sons.setLen counterIdx

proc checkSelfAssignment(c: var TLiftCtx; t: PType; body, x, y: PNode) =
  var cond = callCodegenProc(c.g, "sameSeqPayload", c.info,
      newTreeIT(nkAddr, c.info, makePtrType(c.fn, x.typ, c.idgen), x),
      newTreeIT(nkAddr, c.info, makePtrType(c.fn, y.typ, c.idgen), y)
      )
  cond.typ() = getSysType(c.g, c.info, tyBool)
  body.add genIf(c, cond, newTreeI(nkReturnStmt, c.info, newNodeI(nkEmpty, c.info)))

proc fillSeqOp(c: var TLiftCtx; t: PType; body, x, y: PNode) =
  case c.kind
  of attachedDup:
    body.add setLenSeqCall(c, t, x, y)
    forallElements(c, t, body, x, y)
  of attachedAsgn, attachedDeepCopy:
    # we generate:
    # if x.p == y.p:
    #   return
    # setLen(dest, y.len)
    # var i = 0
    # while i < y.len: dest[i] = y[i]; inc(i)
    # This is usually more efficient than a destroy/create pair.
    checkSelfAssignment(c, t, body, x, y)
    body.add setLenSeqCall(c, t, x, y)
    forallElements(c, t, body, x, y)
  of attachedSink:
    let moveCall = genBuiltin(c, mMove, "move", x)
    moveCall.add y
    doAssert t.destructor != nil
    moveCall.add destructorCall(c, t.destructor, x)
    body.add moveCall
  of attachedDestructor:
    # destroy all elements:
    forallElements(c, t, body, x, y)
    body.add genBuiltin(c, mDestroy, "destroy", x)
  of attachedTrace:
    if canFormAcycle(c.g, t.elemType):
      # follow all elements:
      forallElements(c, t, body, x, y)
  of attachedWasMoved: body.add genBuiltin(c, mWasMoved, "`=wasMoved`", x)

proc useSeqOrStrOp(c: var TLiftCtx; t: PType; body, x, y: PNode) =
  createTypeBoundOps(c.g, c.c, t, body.info, c.idgen)
  # recursions are tricky, so we might need to forward the generated
  # operation here:
  var t = t
  if t.assignment == nil or t.destructor == nil or t.dup == nil:
    let h = sighashes.hashType(t,c.g.config, {CoType, CoConsiderOwned, CoDistinct})
    let canon = c.g.canonTypes.getOrDefault(h)
    if canon != nil: t = canon

  case c.kind
  of attachedAsgn, attachedDeepCopy:
    # XXX: replace these with assertions.
    if t.assignment == nil:
      return # protect from recursion
    body.add newHookCall(c, t.assignment, x, y)
  of attachedSink:
    # we always inline the move for better performance:
    let moveCall = genBuiltin(c, mMove, "move", x)
    moveCall.add y
    doAssert t.destructor != nil
    moveCall.add destructorCall(c, t.destructor, x)
    body.add moveCall
    # alternatively we could do this:
    when false:
      doAssert t.asink != nil
      body.add newHookCall(c, t.asink, x, y)
  of attachedDestructor:
    doAssert t.destructor != nil
    body.add destructorCall(c, t.destructor, x)
  of attachedTrace:
    if t.kind != tyString and canFormAcycle(c.g, t.elemType):
      let op = getAttachedOp(c.g, t, c.kind)
      if op == nil:
        return # protect from recursion
      body.add newHookCall(c, op, x, y)
  of attachedWasMoved: body.add genBuiltin(c, mWasMoved, "`=wasMoved`", x)
  of attachedDup:
    # XXX: replace these with assertions.
    let op = getAttachedOp(c.g, t, c.kind)
    if op == nil:
      return # protect from recursion
    body.add newDupCall(c, op, x, y)

proc fillStrOp(c: var TLiftCtx; t: PType; body, x, y: PNode) =
  case c.kind
  of attachedAsgn, attachedDeepCopy, attachedDup:
    body.add callCodegenProc(c.g, "nimAsgnStrV2", c.info, genAddr(c, x), y)
  of attachedSink:
    let moveCall = genBuiltin(c, mMove, "move", x)
    moveCall.add y
    doAssert t.destructor != nil
    moveCall.add destructorCall(c, t.destructor, x)
    body.add moveCall
  of attachedDestructor:
    body.add genBuiltin(c, mDestroy, "destroy", x)
  of attachedTrace:
    discard "strings are atomic and have no inner elements that are to trace"
  of attachedWasMoved: body.add genBuiltin(c, mWasMoved, "`=wasMoved`", x)

proc cyclicType*(g: ModuleGraph, t: PType): bool =
  case t.kind
  of tyRef: result = types.canFormAcycle(g, t.elementType)
  of tyProc: result = t.callConv == ccClosure
  else: result = false

proc atomicRefOp(c: var TLiftCtx; t: PType; body, x, y: PNode) =
  #[ bug #15753 is really subtle. Usually the classical write barrier for reference
  counting looks like this::

    incRef source  # increment first; this takes care of self-assignments1
    decRef dest
    dest[] = source

  However, 'decRef dest' might trigger a cycle collection and then the collector
  traverses the graph. It is crucial that when it follows the pointers the assignment
  'dest[] = source' already happened so that we don't do trial deletion on a wrong
  graph -- this causes premature freeing of objects! The correct barrier looks like
  this::

    let tmp = dest
    incRef source
    dest[] = source
    decRef tmp

  ]#
  var actions = newNodeI(nkStmtList, c.info)
  let elemType = t.elementType

  createTypeBoundOps(c.g, c.c, elemType, c.info, c.idgen)
  let isCyclic = c.g.config.selectedGC == gcOrc and types.canFormAcycle(c.g, elemType)

  let isInheritableAcyclicRef = c.g.config.selectedGC == gcOrc and
                      (not isPureObject(elemType)) and
                      tfAcyclic in skipTypes(elemType, abstractInst+{tyOwned}-{tyTypeDesc}).flags
  # dynamic Acyclic refs need to use dyn decRef

  let tmp =
    if isCyclic and c.kind in {attachedAsgn, attachedSink, attachedDup}:
      declareTempOf(c, body, x)
    else:
      x

  if isFinal(elemType):
    addDestructorCall(c, elemType, actions, genDeref(tmp, nkDerefExpr))
    var alignOf = genBuiltin(c, mAlignOf, "alignof", newNodeIT(nkType, c.info, elemType))
    alignOf.typ() = getSysType(c.g, c.info, tyInt)
    actions.add callCodegenProc(c.g, "nimRawDispose", c.info, tmp, alignOf)
  else:
    addDestructorCall(c, elemType, newNodeI(nkStmtList, c.info), genDeref(tmp, nkDerefExpr))
    actions.add callCodegenProc(c.g, "nimDestroyAndDispose", c.info, tmp)

  var cond: PNode
  if isCyclic:
    if isFinal(elemType):
      let typInfo = genBuiltin(c, mGetTypeInfoV2, "getTypeInfoV2", newNodeIT(nkType, x.info, elemType))
      typInfo.typ() = getSysType(c.g, c.info, tyPointer)
      cond = callCodegenProc(c.g, "nimDecRefIsLastCyclicStatic", c.info, tmp, typInfo)
    else:
      cond = callCodegenProc(c.g, "nimDecRefIsLastCyclicDyn", c.info, tmp)
  elif isInheritableAcyclicRef:
    cond = callCodegenProc(c.g, "nimDecRefIsLastDyn", c.info, x)
  else:
    cond = callCodegenProc(c.g, "nimDecRefIsLast", c.info, x)
  cond.typ() = getSysType(c.g, x.info, tyBool)

  case c.kind
  of attachedSink:
    if isCyclic:
      body.add newAsgnStmt(x, y)
      body.add genIf(c, cond, actions)
    else:
      body.add genIf(c, cond, actions)
      body.add newAsgnStmt(x, y)
  of attachedAsgn:
    if isCyclic:
      body.add genIf(c, y, callCodegenProc(c.g,
          "nimIncRefCyclic", c.info, y, getCycleParam(c)))
      body.add newAsgnStmt(x, y)
      body.add genIf(c, cond, actions)
    else:
      body.add genIf(c, y, callCodegenProc(c.g, "nimIncRef", c.info, y))
      body.add genIf(c, cond, actions)
      body.add newAsgnStmt(x, y)
  of attachedDestructor:
    body.add genIf(c, cond, actions)
  of attachedDeepCopy: assert(false, "cannot happen")
  of attachedTrace:
    if isCyclic:
      if isFinal(elemType):
        let typInfo = genBuiltin(c, mGetTypeInfoV2, "getTypeInfoV2", newNodeIT(nkType, x.info, elemType))
        typInfo.typ() = getSysType(c.g, c.info, tyPointer)
        body.add callCodegenProc(c.g, "nimTraceRef", c.info, genAddrOf(x, c.idgen), typInfo, y)
      else:
        # If the ref is polymorphic we have to account for this
        body.add callCodegenProc(c.g, "nimTraceRefDyn", c.info, genAddrOf(x, c.idgen), y)
      #echo "can follow ", elemType, " static ", isFinal(elemType)
  of attachedWasMoved: body.add genBuiltin(c, mWasMoved, "`=wasMoved`", x)
  of attachedDup:
    if isCyclic:
      body.add newAsgnStmt(x, y)
      body.add genIf(c, y, callCodegenProc(c.g,
          "nimIncRefCyclic", c.info, y, getCycleParam(c)))
    else:
      body.add newAsgnStmt(x, y)
      body.add genIf(c, y, callCodegenProc(c.g,
          "nimIncRef", c.info, y))

proc atomicClosureOp(c: var TLiftCtx; t: PType; body, x, y: PNode) =
  ## Closures are really like refs except they always use a virtual destructor
  ## and we need to do the refcounting only on the ref field which we call 'xenv':
  let xenv = genBuiltin(c, mAccessEnv, "accessEnv", x)
  xenv.typ() = getSysType(c.g, c.info, tyPointer)

  let isCyclic = c.g.config.selectedGC == gcOrc
  let tmp =
    if isCyclic and c.kind in {attachedAsgn, attachedSink, attachedDup}:
      declareTempOf(c, body, xenv)
    else:
      xenv

  var actions = newNodeI(nkStmtList, c.info)
  actions.add callCodegenProc(c.g, "nimDestroyAndDispose", c.info, tmp)

  let decRefProc =
    if isCyclic: "nimDecRefIsLastCyclicDyn"
    else: "nimDecRefIsLast"
  let cond = callCodegenProc(c.g, decRefProc, c.info, tmp)
  cond.typ() = getSysType(c.g, x.info, tyBool)

  case c.kind
  of attachedSink:
    if isCyclic:
      body.add newAsgnStmt(x, y)
      body.add genIf(c, cond, actions)
    else:
      body.add genIf(c, cond, actions)
      body.add newAsgnStmt(x, y)
  of attachedAsgn:
    let yenv = genBuiltin(c, mAccessEnv, "accessEnv", y)
    yenv.typ() = getSysType(c.g, c.info, tyPointer)
    if isCyclic:
      body.add genIf(c, yenv, callCodegenProc(c.g, "nimIncRefCyclic", c.info, yenv, getCycleParam(c)))
      body.add newAsgnStmt(x, y)
      body.add genIf(c, cond, actions)
    else:
      body.add genIf(c, yenv, callCodegenProc(c.g, "nimIncRef", c.info, yenv))

      body.add genIf(c, cond, actions)
      body.add newAsgnStmt(x, y)
  of attachedDup:
    let yenv = genBuiltin(c, mAccessEnv, "accessEnv", y)
    yenv.typ() = getSysType(c.g, c.info, tyPointer)
    if isCyclic:
      body.add newAsgnStmt(x, y)
      body.add genIf(c, yenv, callCodegenProc(c.g, "nimIncRefCyclic", c.info, yenv, getCycleParam(c)))
    else:
      body.add newAsgnStmt(x, y)
      body.add genIf(c, yenv, callCodegenProc(c.g, "nimIncRef", c.info, yenv))
  of attachedDestructor:
    body.add genIf(c, cond, actions)
  of attachedDeepCopy: assert(false, "cannot happen")
  of attachedTrace:
    body.add callCodegenProc(c.g, "nimTraceRefDyn", c.info, genAddrOf(xenv, c.idgen), y)
  of attachedWasMoved: body.add genBuiltin(c, mWasMoved, "`=wasMoved`", x)

proc weakrefOp(c: var TLiftCtx; t: PType; body, x, y: PNode) =
  case c.kind
  of attachedSink:
    # we 'nil' y out afterwards so we *need* to take over its reference
    # count value:
    body.add genIf(c, x, callCodegenProc(c.g, "nimDecWeakRef", c.info, x))
    body.add newAsgnStmt(x, y)
  of attachedAsgn:
    body.add genIf(c, y, callCodegenProc(c.g, "nimIncRef", c.info, y))
    body.add genIf(c, x, callCodegenProc(c.g, "nimDecWeakRef", c.info, x))
    body.add newAsgnStmt(x, y)
  of attachedDup:
    body.add newAsgnStmt(x, y)
    body.add genIf(c, y, callCodegenProc(c.g, "nimIncRef", c.info, y))
  of attachedDestructor:
    # it's better to prepend the destruction of weak refs in order to
    # prevent wrong "dangling refs exist" problems:
    var actions = newNodeI(nkStmtList, c.info)
    actions.add callCodegenProc(c.g, "nimDecWeakRef", c.info, x)
    let des = genIf(c, x, actions)
    if body.len == 0:
      body.add des
    else:
      body.sons.insert(des, 0)
  of attachedDeepCopy: assert(false, "cannot happen")
  of attachedTrace: discard
  of attachedWasMoved: body.add genBuiltin(c, mWasMoved, "`=wasMoved`", x)

proc ownedRefOp(c: var TLiftCtx; t: PType; body, x, y: PNode) =
  var actions = newNodeI(nkStmtList, c.info)

  let elemType = t.skipModifier
  #fillBody(c, elemType, actions, genDeref(x), genDeref(y))
  #var disposeCall = genBuiltin(c, mDispose, "dispose", x)

  if isFinal(elemType):
    addDestructorCall(c, elemType, actions, genDeref(x, nkDerefExpr))
    var alignOf = genBuiltin(c, mAlignOf, "alignof", newNodeIT(nkType, c.info, elemType))
    alignOf.typ() = getSysType(c.g, c.info, tyInt)
    actions.add callCodegenProc(c.g, "nimRawDispose", c.info, x, alignOf)
  else:
    addDestructorCall(c, elemType, newNodeI(nkStmtList, c.info), genDeref(x, nkDerefExpr))
    actions.add callCodegenProc(c.g, "nimDestroyAndDispose", c.info, x)

  case c.kind
  of attachedSink, attachedAsgn:
    body.add genIf(c, x, actions)
    body.add newAsgnStmt(x, y)
  of attachedDup:
    body.add newAsgnStmt(x, y)
  of attachedDestructor:
    body.add genIf(c, x, actions)
  of attachedDeepCopy: assert(false, "cannot happen")
  of attachedTrace: discard
  of attachedWasMoved: body.add genBuiltin(c, mWasMoved, "`=wasMoved`", x)

proc closureOp(c: var TLiftCtx; t: PType; body, x, y: PNode) =
  if c.kind == attachedDeepCopy:
    # a big problem is that we don't know the environment's type here, so we
    # have to go through some indirection; we delegate this to the codegen:
    let call = newNodeI(nkCall, c.info, 2)
    call.typ() = t
    call[0] = newSymNode(createMagic(c.g, c.idgen, "deepCopy", mDeepCopy))
    call[1] = y
    body.add newAsgnStmt(x, call)
  elif (optOwnedRefs in c.g.config.globalOptions and
      optRefCheck in c.g.config.options) or c.g.config.selectedGC in {gcArc, gcAtomicArc, gcOrc}:
    let xx = genBuiltin(c, mAccessEnv, "accessEnv", x)
    xx.typ() = getSysType(c.g, c.info, tyPointer)
    case c.kind
    of attachedSink:
      # we 'nil' y out afterwards so we *need* to take over its reference
      # count value:
      body.add genIf(c, xx, callCodegenProc(c.g, "nimDecWeakRef", c.info, xx))
      body.add newAsgnStmt(x, y)
    of attachedAsgn:
      let yy = genBuiltin(c, mAccessEnv, "accessEnv", y)
      yy.typ() = getSysType(c.g, c.info, tyPointer)
      body.add genIf(c, yy, callCodegenProc(c.g, "nimIncRef", c.info, yy))
      body.add genIf(c, xx, callCodegenProc(c.g, "nimDecWeakRef", c.info, xx))
      body.add newAsgnStmt(x, y)
    of attachedDup:
      let yy = genBuiltin(c, mAccessEnv, "accessEnv", y)
      yy.typ() = getSysType(c.g, c.info, tyPointer)
      body.add newAsgnStmt(x, y)
      body.add genIf(c, yy, callCodegenProc(c.g, "nimIncRef", c.info, yy))
    of attachedDestructor:
      let des = genIf(c, xx, callCodegenProc(c.g, "nimDecWeakRef", c.info, xx))
      if body.len == 0:
        body.add des
      else:
        body.sons.insert(des, 0)
    of attachedDeepCopy: assert(false, "cannot happen")
    of attachedTrace: discard
    of attachedWasMoved: body.add genBuiltin(c, mWasMoved, "`=wasMoved`", x)

proc ownedClosureOp(c: var TLiftCtx; t: PType; body, x, y: PNode) =
  let xx = genBuiltin(c, mAccessEnv, "accessEnv", x)
  xx.typ() = getSysType(c.g, c.info, tyPointer)
  var actions = newNodeI(nkStmtList, c.info)
  #discard addDestructorCall(c, elemType, newNodeI(nkStmtList, c.info), genDeref(xx))
  actions.add callCodegenProc(c.g, "nimDestroyAndDispose", c.info, xx)
  case c.kind
  of attachedSink, attachedAsgn:
    body.add genIf(c, xx, actions)
    body.add newAsgnStmt(x, y)
  of attachedDup:
    body.add newAsgnStmt(x, y)
  of attachedDestructor:
    body.add genIf(c, xx, actions)
  of attachedDeepCopy: assert(false, "cannot happen")
  of attachedTrace: discard
  of attachedWasMoved: body.add genBuiltin(c, mWasMoved, "`=wasMoved`", x)

proc fillBody(c: var TLiftCtx; t: PType; body, x, y: PNode) =
  case t.kind
  of tyNone, tyEmpty, tyVoid: discard
  of tyPointer, tySet, tyBool, tyChar, tyEnum, tyInt..tyUInt64, tyCstring,
      tyPtr, tyUncheckedArray, tyVar, tyLent:
    defaultOp(c, t, body, x, y)
  of tyRef:
    if c.g.config.selectedGC in {gcArc, gcOrc, gcAtomicArc}:
      atomicRefOp(c, t, body, x, y)
    elif (optOwnedRefs in c.g.config.globalOptions and
        optRefCheck in c.g.config.options):
      weakrefOp(c, t, body, x, y)
    else:
      defaultOp(c, t, body, x, y)
  of tyProc:
    if t.callConv == ccClosure:
      if c.g.config.selectedGC in {gcArc, gcOrc, gcAtomicArc}:
        atomicClosureOp(c, t, body, x, y)
      else:
        closureOp(c, t, body, x, y)
    else:
      defaultOp(c, t, body, x, y)
  of tyOwned:
    let base = t.skipTypes(abstractInstOwned)
    if optOwnedRefs in c.g.config.globalOptions:
      case base.kind
      of tyRef:
        ownedRefOp(c, base, body, x, y)
        return
      of tyProc:
        if base.callConv == ccClosure:
          ownedClosureOp(c, base, body, x, y)
          return
      else: discard
    defaultOp(c, base, body, x, y)
  of tyArray:
    if tfHasAsgn in t.flags or useNoGc(c, t):
      forallElements(c, t, body, x, y)
    else:
      defaultOp(c, t, body, x, y)
  of tySequence:
    if useNoGc(c, t):
      useSeqOrStrOp(c, t, body, x, y)
    elif optSeqDestructors in c.g.config.globalOptions:
      # note that tfHasAsgn is propagated so we need the check on
      # 'selectedGC' here to determine if we have the new runtime.
      discard considerUserDefinedOp(c, t, body, x, y)
    elif tfHasAsgn in t.flags:
      if c.kind in {attachedAsgn, attachedSink, attachedDeepCopy}:
        body.add newSeqCall(c, x, y)
      forallElements(c, t, body, x, y)
    else:
      defaultOp(c, t, body, x, y)
  of tyString:
    if useNoGc(c, t):
      useSeqOrStrOp(c, t, body, x, y)
    elif tfHasAsgn in t.flags:
      discard considerUserDefinedOp(c, t, body, x, y)
    else:
      defaultOp(c, t, body, x, y)
  of tyObject:
    if not considerUserDefinedOp(c, t, body, x, y):
      if t.sym != nil and sfImportc in t.sym.flags:
        case c.kind
        of {attachedAsgn, attachedSink, attachedDup}:
          body.add newAsgnStmt(x, y)
        of attachedWasMoved:
          body.add genBuiltin(c, mWasMoved, "`=wasMoved`", x)
        else:
          fillBodyObjT(c, t, body, x, y)
      else:
        if c.kind == attachedDup:
          var op2 = getAttachedOp(c.g, t, attachedAsgn)
          if op2 != nil and sfOverridden in op2.flags:
            #markUsed(c.g.config, c.info, op, c.g.usageSym)
            onUse(c.info, op2)
            body.add newHookCall(c, t.assignment, x, y)
          else:
            fillBodyObjT(c, t, body, x, y)
        else:
          fillBodyObjT(c, t, body, x, y)
  of tyDistinct:
    if not considerUserDefinedOp(c, t, body, x, y):
      fillBody(c, t.elementType, body, x, y)
  of tyTuple:
    fillBodyTup(c, t, body, x, y)
  of tyVarargs, tyOpenArray:
    if c.kind == attachedDestructor and (tfHasAsgn in t.flags or useNoGc(c, t)):
      forallElements(c, t, body, x, y)
    else:
      discard "cannot copy openArray"

  of tyFromExpr, tyError, tyBuiltInTypeClass, tyUserTypeClass,
     tyUserTypeClassInst, tyCompositeTypeClass, tyAnd, tyOr, tyNot, tyAnything,
     tyGenericParam, tyGenericBody, tyNil, tyUntyped, tyTyped,
     tyTypeDesc, tyGenericInvocation, tyForward, tyStatic:
    #internalError(c.g.config, c.info, "assignment requested for type: " & typeToString(t))
    discard
  of tyOrdinal, tyRange, tyInferred,
     tyGenericInst, tyAlias, tySink:
    fillBody(c, skipModifier(t), body, x, y)
  of tyConcept, tyIterable: raiseAssert "unreachable"

proc produceSymDistinctType(g: ModuleGraph; c: PContext; typ: PType;
                            kind: TTypeAttachedOp; info: TLineInfo;
                            idgen: IdGenerator): PSym =
  assert typ.kind == tyDistinct
  let baseType = typ.elementType
  if getAttachedOp(g, baseType, kind) == nil:
    # TODO: fixme `isDistinct` is a fix for #23552; remove it after
    # `-d:nimPreviewNonVarDestructor` becomes the default
    discard produceSym(g, c, baseType, kind, info, idgen, isDistinct = true)
  result = getAttachedOp(g, baseType, kind)
  setAttachedOp(g, idgen.module, typ, kind, result)

proc symDupPrototype(g: ModuleGraph; typ: PType; owner: PSym; kind: TTypeAttachedOp;
              info: TLineInfo; idgen: IdGenerator): PSym =
  let procname = getIdent(g.cache, AttachedOpToStr[kind])
  result = newSym(skProc, procname, idgen, owner, info)
  let res = newSym(skResult, getIdent(g.cache, "result"), idgen, result, info)
  let src = newSym(skParam, getIdent(g.cache, "src"),
                   idgen, result, info)
  res.typ = typ
  src.typ = typ

  result.typ = newType(tyProc, idgen, owner)
  result.typ.n = newNodeI(nkFormalParams, info)
  rawAddSon(result.typ, res.typ)
  result.typ.n.add newNodeI(nkEffectList, info)

  result.typ.addParam src

  if g.config.selectedGC == gcOrc and
    cyclicType(g, typ.skipTypes(abstractInst)):
    let cycleParam = newSym(skParam, getIdent(g.cache, "cyclic"),
                            idgen, result, info)
    cycleParam.typ = getSysType(g, info, tyBool)
    result.typ.addParam cycleParam

  var n = newNodeI(nkProcDef, info, bodyPos+2)
  for i in 0..<n.len: n[i] = newNodeI(nkEmpty, info)
  n[namePos] = newSymNode(result)
  n[paramsPos] = result.typ.n
  n[bodyPos] = newNodeI(nkStmtList, info)
  n[resultPos] = newSymNode(res)
  result.ast = n
  incl result.flags, sfFromGeneric
  incl result.flags, sfGeneratedOp

proc symPrototype(g: ModuleGraph; typ: PType; owner: PSym; kind: TTypeAttachedOp;
              info: TLineInfo; idgen: IdGenerator; isDiscriminant = false; isDistinct = false): PSym =
  if kind == attachedDup:
    return symDupPrototype(g, typ, owner, kind, info, idgen)

  let procname = getIdent(g.cache, AttachedOpToStr[kind])
  result = newSym(skProc, procname, idgen, owner, info)
  let dest = newSym(skParam, getIdent(g.cache, "dest"), idgen, result, info)
  let src = newSym(skParam, getIdent(g.cache, if kind == attachedTrace: "env" else: "src"),
                   idgen, result, info)

  if kind == attachedDestructor and g.config.selectedGC in {gcArc, gcOrc, gcAtomicArc} and
     ((g.config.isDefined("nimPreviewNonVarDestructor") and not isDiscriminant) or (typ.kind in {tyRef, tyString, tySequence} and not isDistinct)):
    dest.typ = typ
  else:
    dest.typ = makeVarType(typ.owner, typ, idgen)

  if kind == attachedTrace:
    src.typ = getSysType(g, info, tyPointer)
  else:
    src.typ = typ

  result.typ = newProcType(info, idgen, owner)
  result.typ.addParam dest
  if kind notin {attachedDestructor, attachedWasMoved}:
    result.typ.addParam src

  if kind == attachedAsgn and g.config.selectedGC == gcOrc and
      cyclicType(g, typ.skipTypes(abstractInst)):
    let cycleParam = newSym(skParam, getIdent(g.cache, "cyclic"),
                            idgen, result, info)
    cycleParam.typ = getSysType(g, info, tyBool)
    result.typ.addParam cycleParam

  var n = newNodeI(nkProcDef, info, bodyPos+1)
  for i in 0..<n.len: n[i] = newNodeI(nkEmpty, info)
  n[namePos] = newSymNode(result)
  n[paramsPos] = result.typ.n
  n[bodyPos] = newNodeI(nkStmtList, info)
  result.ast = n
  incl result.flags, sfFromGeneric
  incl result.flags, sfGeneratedOp
  if kind == attachedWasMoved:
    incl result.flags, sfNoSideEffect
    incl result.typ.flags, tfNoSideEffect

proc genTypeFieldCopy(c: var TLiftCtx; t: PType; body, x, y: PNode) =
  let xx = genBuiltin(c, mAccessTypeField, "accessTypeField", x)
  let yy = genBuiltin(c, mAccessTypeField, "accessTypeField", y)
  xx.typ() = getSysType(c.g, c.info, tyPointer)
  yy.typ() = xx.typ
  body.add newAsgnStmt(xx, yy)

proc produceSym(g: ModuleGraph; c: PContext; typ: PType; kind: TTypeAttachedOp;
              info: TLineInfo; idgen: IdGenerator; isDistinct = false): PSym =
  if typ.kind == tyDistinct:
    return produceSymDistinctType(g, c, typ, kind, info, idgen)

  result = getAttachedOp(g, typ, kind)
  if result == nil:
    result = symPrototype(g, typ, typ.owner, kind, info, idgen, isDistinct = isDistinct)

  var a = TLiftCtx(info: info, g: g, kind: kind, c: c, asgnForType: typ, idgen: idgen,
                   fn: result)

  let dest = if kind == attachedDup: result.ast[resultPos].sym else: result.typ.n[1].sym
  let d = if result.typ.firstParamType.kind == tyVar: newDeref(newSymNode(dest)) else: newSymNode(dest)
  let src = case kind
            of {attachedDestructor, attachedWasMoved}: newNodeIT(nkSym, info, getSysType(g, info, tyPointer))
            of attachedDup: newSymNode(result.typ.n[1].sym)
            else: newSymNode(result.typ.n[2].sym)

  # register this operation already:
  setAttachedOpPartial(g, idgen.module, typ, kind, result)

  if kind == attachedSink and destructorOverridden(g, typ):
    ## compiler can use a combination of `=destroy` and memCopy for sink op
    dest.flags.incl sfCursor
    let op = getAttachedOp(g, typ, attachedDestructor)
    result.ast[bodyPos].add newOpCall(a, op, if op.typ.firstParamType.kind == tyVar: d[0] else: d)
    result.ast[bodyPos].add newAsgnStmt(d, src)
  else:
    var tk: TTypeKind
    if g.config.selectedGC in {gcArc, gcOrc, gcHooks, gcAtomicArc}:
      tk = skipTypes(typ, {tyOrdinal, tyRange, tyInferred, tyGenericInst, tyStatic, tyAlias, tySink}).kind
    else:
      tk = tyNone # no special casing for strings and seqs
    case tk
    of tySequence:
      fillSeqOp(a, typ, result.ast[bodyPos], d, src)
    of tyString:
      fillStrOp(a, typ, result.ast[bodyPos], d, src)
    else:
      fillBody(a, typ, result.ast[bodyPos], d, src)
      if tk == tyObject and a.kind in {attachedAsgn, attachedSink, attachedDeepCopy, attachedDup} and not lacksMTypeField(typ):
        # bug #19205: Do not forget to also copy the hidden type field:
        genTypeFieldCopy(a, typ, result.ast[bodyPos], d, src)

  if not a.canRaise:
    incl result.flags, sfNeverRaises
    result.ast[pragmasPos] = newNodeI(nkPragma, info)
    result.ast[pragmasPos].add newTree(nkExprColonExpr,
        newIdentNode(g.cache.getIdent("raises"),  info), newNodeI(nkBracket, info))

  completePartialOp(g, idgen.module, typ, kind, result)


proc produceDestructorForDiscriminator*(g: ModuleGraph; typ: PType; field: PSym,
                                        info: TLineInfo; idgen: IdGenerator): PSym =
  assert(typ.skipTypes({tyAlias, tyGenericInst}).kind == tyObject)
  # discrimantor assignments needs pointers to destroy fields; alas, we cannot use non-var destructor here
  result = symPrototype(g, field.typ, typ.owner, attachedDestructor, info, idgen, isDiscriminant = true)
  var a = TLiftCtx(info: info, g: g, kind: attachedDestructor, asgnForType: typ, idgen: idgen,
                   fn: result)
  a.asgnForType = typ
  a.filterDiscriminator = field
  a.addMemReset = true
  let discrimantDest = result.typ.n[1].sym

  let dst = newSym(skVar, getIdent(g.cache, "dest"), idgen, result, info)
  dst.typ = makePtrType(typ.owner, typ, idgen)
  let dstSym = newSymNode(dst)
  let d = newDeref(dstSym)
  let v = newNodeI(nkVarSection, info)
  v.addVar(dstSym, genContainerOf(a, typ, field, discrimantDest))
  result.ast[bodyPos].add v
  let placeHolder = newNodeIT(nkSym, info, getSysType(g, info, tyPointer))
  fillBody(a, typ, result.ast[bodyPos], d, placeHolder)
  if not a.canRaise: incl result.flags, sfNeverRaises


template liftTypeBoundOps*(c: PContext; typ: PType; info: TLineInfo) =
  discard "now a nop"

proc patchBody(g: ModuleGraph; c: PContext; n: PNode; info: TLineInfo; idgen: IdGenerator) =
  if n.kind in nkCallKinds:
    if n[0].kind == nkSym and n[0].sym.magic == mDestroy:
      let t = n[1].typ.skipTypes(abstractVar)
      if getAttachedOp(g, t, attachedDestructor) == nil:
        discard produceSym(g, c, t, attachedDestructor, info, idgen)

      let op = getAttachedOp(g, t, attachedDestructor)
      if op != nil:
        if op.ast.isGenericRoutine:
          internalError(g.config, info, "resolved destructor is generic")
        if op.magic == mDestroy and t.kind != tyString:
          internalError(g.config, info, "patching mDestroy with mDestroy?")
        n[0] = newSymNode(op)
  for x in n: patchBody(g, c, x, info, idgen)

proc inst(g: ModuleGraph; c: PContext; t: PType; kind: TTypeAttachedOp; idgen: IdGenerator;
          info: TLineInfo) =
  let op = getAttachedOp(g, t, kind)
  if op != nil and op.ast != nil and op.ast.isGenericRoutine:
    if t.typeInst != nil:
      var a = TLiftCtx(info: info, g: g, kind: kind, c: c, idgen: idgen)
      let opInst = instantiateGeneric(a, op, t, t.typeInst)
      if opInst.ast != nil:
        patchBody(g, c, opInst.ast, info, a.idgen)
      setAttachedOp(g, idgen.module, t, kind, opInst)
    else:
      localError(g.config, info, "unresolved generic parameter")

proc isTrival*(s: PSym): bool {.inline.} =
  s == nil or (s.ast != nil and s.ast[bodyPos].len == 0)

proc createTypeBoundOps(g: ModuleGraph; c: PContext; orig: PType; info: TLineInfo;
                        idgen: IdGenerator) =
  ## In the semantic pass this is called in strategic places
  ## to ensure we lift assignment, destructors and moves properly.
  ## The later 'injectdestructors' pass depends on it.
  if orig == nil or {tfCheckedForDestructor, tfHasMeta} * orig.flags != {}: return
  incl orig.flags, tfCheckedForDestructor
  # for user defined generic destructors:
  let origRoot = genericRoot(orig)
  if origRoot != nil:
    incl origRoot.flags, tfGenericHasDestructor

  let skipped = orig.skipTypes({tyGenericInst, tyAlias, tySink})
  if isEmptyContainer(skipped) or skipped.kind == tyStatic: return

  let h = sighashes.hashType(skipped, g.config, {CoType, CoConsiderOwned, CoDistinct})
  var canon = g.canonTypes.getOrDefault(h)
  if canon == nil:
    g.canonTypes[h] = skipped
    canon = skipped

  # multiple cases are to distinguish here:
  # 1. we don't know yet if 'typ' has a nontrival destructor.
  # 2. we have a nop destructor. --> mDestroy
  # 3. we have a lifted destructor.
  # 4. We have a custom destructor.
  # 5. We have a (custom) generic destructor.

  # we do not generate '=trace' procs if we
  # have the cycle detection disabled, saves code size.
  let lastAttached = if g.config.selectedGC == gcOrc: attachedTrace
                     else: attachedSink

  # bug #15122: We need to produce all prototypes before entering the
  # mind boggling recursion. Hacks like these imply we should rewrite
  # this module.
  var generics: array[attachedWasMoved..attachedTrace, bool] = default(array[attachedWasMoved..attachedTrace, bool])
  for k in attachedWasMoved..lastAttached:
    generics[k] = getAttachedOp(g, canon, k) != nil
    if not generics[k]:
      setAttachedOp(g, idgen.module, canon, k,
          symPrototype(g, canon, canon.owner, k, info, idgen))

  # we generate the destructor first so that other operators can depend on it:
  for k in attachedWasMoved..lastAttached:
    if not generics[k]:
      discard produceSym(g, c, canon, k, info, idgen)
    else:
      inst(g, c, canon, k, idgen, info)
    if canon != orig:
      setAttachedOp(g, idgen.module, orig, k, getAttachedOp(g, canon, k))

  if not isTrival(getAttachedOp(g, orig, attachedDestructor)):
    #or not isTrival(orig.assignment) or
    # not isTrival(orig.sink):
    orig.flags.incl tfHasAsgn
    # ^ XXX Breaks IC!

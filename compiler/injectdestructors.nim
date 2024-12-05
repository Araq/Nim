#
#
#           The Nim Compiler
#        (c) Copyright 2017 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Injects destructor calls into Nim code as well as
## an optimizer that optimizes copies to moves. This is implemented as an
## AST to AST transformation so that every backend benefits from it.

## See doc/destructors.rst for a spec of the implemented rewrite rules

import
  ast, astalgo, msgs, renderer, magicsys, types, idents,
  options, lowerings, modulegraphs,
  lineinfos, parampatterns, sighashes, liftdestructors, optimizer,
  varpartitions, aliasanalysis, dfa, wordrecg

import std/[strtabs, tables, strutils, intsets]

when defined(nimPreviewSlimSystem):
  import std/assertions

from trees import exprStructuralEquivalent, getRoot, whichPragma

type
  Con = object
    owner: PSym
    when true:
      g: ControlFlowGraph
    graph: ModuleGraph
    inLoop, inSpawn, inLoopCond: int
    uninit: IntSet # set of uninit'ed vars
    idgen: IdGenerator
    body: PNode
    otherUsage: TLineInfo
    inUncheckedAssignSection: int
    inEnsureMove: int

  Scope = object # we do scope-based memory management.
    # a scope is comparable to an nkStmtListExpr like
    # (try: statements; dest = y(); finally: destructors(); dest)
    vars: seq[PSym]
    wasMoved: seq[PNode]
    final: seq[PNode] # finally section
    locals: seq[PSym]
    body: PNode
    needsTry: bool
    parent: ptr Scope

  ProcessMode = enum
    normal
    consumed
    sinkArg

const toDebug {.strdefine.} = ""
when toDebug.len > 0:
  var shouldDebug = false

template dbg(body) =
  when toDebug.len > 0:
    if shouldDebug:
      body

proc hasDestructor(c: Con; t: PType): bool {.inline.} =
  result = ast.hasDestructor(t)
  when toDebug.len > 0:
    # for more effective debugging
    if not result and c.graph.config.selectedGC in {gcArc, gcOrc, gcAtomicArc}:
      assert(not containsGarbageCollectedRef(t))

proc getTemp(c: var Con; s: var Scope; typ: PType; info: TLineInfo): PNode =
  let sym = newSym(skTemp, getIdent(c.graph.cache, ":tmpD"), c.idgen, c.owner, info)
  sym.typ = typ
  s.vars.add(sym)
  result = newSymNode(sym)

proc nestedScope(parent: var Scope; body: PNode): Scope =
  Scope(vars: @[], locals: @[], wasMoved: @[], final: @[], body: body, needsTry: false, parent: addr(parent))

proc p(n: PNode; c: var Con; s: var Scope; mode: ProcessMode; tmpFlags = {sfSingleUsedTemp}; inReturn = false): PNode

type
  MoveOrCopyFlag = enum
    IsDecl, IsExplicitSink, IsReturn

proc moveOrCopy(dest, ri: PNode; c: var Con; s: var Scope; flags: set[MoveOrCopyFlag] = {}): PNode

when false:
  var
    perfCounters: array[InstrKind, int]

  proc showCounters*() =
    for i in low(InstrKind)..high(InstrKind):
      echo "INSTR ", i, " ", perfCounters[i]

proc isLastReadImpl(n: PNode; c: var Con; scope: var Scope): bool =
  let root = parampatterns.exprRoot(n, allowCalls=false)
  if root == nil: return false

  var s = addr(scope)
  while s != nil:
    if s.locals.contains(root): break
    s = s.parent

  c.g = constructCfg(c.owner, if s != nil: s.body else: c.body, root)
  dbg:
    echo "\n### ", c.owner.name.s, ":\nCFG:"
    echoCfg(c.g)
    #echo c.body

  var j = 0
  while j < c.g.len:
    if c.g[j].kind == use and c.g[j].n == n: break
    inc j
  c.otherUsage = unknownLineInfo
  if j < c.g.len:
    var pcs = @[j+1]
    var marked = initIntSet()
    result = true
    while pcs.len > 0:
      var pc = pcs.pop()
      if not marked.contains(pc):
        let oldPc = pc
        while pc < c.g.len:
          dbg:
            echo "EXEC ", c.g[pc].kind, " ", pc, " ", n
          when false:
            inc perfCounters[c.g[pc].kind]
          case c.g[pc].kind
          of loop:
            let back = pc + c.g[pc].dest
            if not marked.containsOrIncl(back):
              pc = back
            else:
              break
          of goto:
            pc = pc + c.g[pc].dest
          of fork:
            if not marked.contains(pc+1):
              pcs.add pc + 1
            pc = pc + c.g[pc].dest
          of use:
            if c.g[pc].n.aliases(n) != no or n.aliases(c.g[pc].n) != no:
              c.otherUsage = c.g[pc].n.info
              return false
            inc pc
          of def:
            if c.g[pc].n.aliases(n) == yes:
              # the path leads to a redefinition of 's' --> sink 's'.
              break
            elif n.aliases(c.g[pc].n) != no:
              # only partially writes to 's' --> can't sink 's', so this def reads 's'
              # or maybe writes to 's' --> can't sink 's'
              c.otherUsage = c.g[pc].n.info
              return false
            inc pc
        marked.incl oldPc
  else:
    result = false

proc isLastRead(n: PNode; c: var Con; s: var Scope): bool =
  # bug #23354; an object type could have a non-trival assignements when it is passed to a sink parameter
  if not hasDestructor(c, n.typ) and (n.typ.kind != tyObject or isTrival(getAttachedOp(c.graph, n.typ, attachedAsgn))): return true

  let m = skipConvDfa(n)
  result = (m.kind == nkSym and sfSingleUsedTemp in m.sym.flags) or
      isLastReadImpl(n, c, s)

proc isFirstWrite(n: PNode; c: var Con): bool =
  let m = skipConvDfa(n)
  result = nfFirstWrite in m.flags

proc isCursor(n: PNode): bool =
  case n.kind
  of nkSym:
    sfCursor in n.sym.flags
  of nkDotExpr:
    isCursor(n[1])
  of nkCheckedFieldExpr:
    isCursor(n[0])
  else:
    false

template isUnpackedTuple(n: PNode): bool =
  ## we move out all elements of unpacked tuples,
  ## hence unpacked tuples themselves don't need to be destroyed
  ## except it's already a cursor
  (n.kind == nkSym and n.sym.kind == skTemp and
   n.sym.typ.kind == tyTuple and sfCursor notin n.sym.flags)

proc checkForErrorPragma(c: Con; t: PType; ri: PNode; opname: string; inferredFromCopy = false) =
  var m = "'" & opname & "' is not available for type <" & typeToString(t) & ">"
  if inferredFromCopy:
    m.add ", which is inferred from unavailable '=copy'"

  if (opname == "=" or opname == "=copy" or opname == "=dup") and ri != nil:
    m.add "; requires a copy because it's not the last read of '"
    m.add renderTree(ri)
    m.add '\''
    if c.otherUsage != unknownLineInfo:
       # ri.comment.startsWith('\n'):
      m.add "; another read is done here: "
      m.add c.graph.config $ c.otherUsage
      #m.add c.graph.config $ c.g[parseInt(ri.comment[1..^1])].n.info
    elif ri.kind == nkSym and ri.sym.kind == skParam and not isSinkType(ri.sym.typ):
      m.add "; try to make "
      m.add renderTree(ri)
      m.add " a 'sink' parameter"
  m.add "; routine: "
  m.add c.owner.name.s
  #m.add "\n\n"
  #m.add renderTree(c.body, {renderIds})
  localError(c.graph.config, ri.info, errGenerated, m)

proc makePtrType(c: var Con, baseType: PType): PType =
  result = newType(tyPtr, c.idgen, c.owner)
  addSonSkipIntLit(result, baseType, c.idgen)

proc genOp(c: var Con; op: PSym; dest: PNode): PNode =
  var addrExp: PNode
  if op.typ != nil and op.typ.signatureLen > 1 and op.typ.firstParamType.kind != tyVar:
    addrExp = dest
  else:
    addrExp = newNodeIT(nkHiddenAddr, dest.info, makePtrType(c, dest.typ))
    addrExp.add(dest)
  result = newTree(nkCall, newSymNode(op), addrExp)

proc genOp(c: var Con; t: PType; kind: TTypeAttachedOp; dest, ri: PNode): PNode =
  var op = getAttachedOp(c.graph, t, kind)
  if op == nil or op.ast.isGenericRoutine:
    # give up and find the canonical type instead:
    let h = sighashes.hashType(t, c.graph.config, {CoType, CoConsiderOwned, CoDistinct})
    let canon = c.graph.canonTypes.getOrDefault(h)
    if canon != nil:
      op = getAttachedOp(c.graph, canon, kind)
  if op == nil:
    #echo dest.typ.id
    globalError(c.graph.config, dest.info, "internal error: '" & AttachedOpToStr[kind] &
      "' operator not found for type " & typeToString(t))
  elif op.ast.isGenericRoutine:
    globalError(c.graph.config, dest.info, "internal error: '" & AttachedOpToStr[kind] &
      "' operator is generic")
  dbg:
    if kind == attachedDestructor:
      echo "destructor is ", op.id, " ", op.ast
  if sfError in op.flags: checkForErrorPragma(c, t, ri, AttachedOpToStr[kind])
  c.genOp(op, dest)

proc genDestroy(c: var Con; dest: PNode): PNode =
  let t = dest.typ.skipTypes({tyGenericInst, tyAlias, tySink})
  result = c.genOp(t, attachedDestructor, dest, nil)

proc canBeMoved(c: Con; t: PType): bool {.inline.} =
  let t = t.skipTypes({tyGenericInst, tyAlias, tySink})
  if optOwnedRefs in c.graph.config.globalOptions:
    result = t.kind != tyRef and getAttachedOp(c.graph, t, attachedSink) != nil
  else:
    result = getAttachedOp(c.graph, t, attachedSink) != nil

proc isNoInit(dest: PNode): bool {.inline.} =
  result = dest.kind == nkSym and sfNoInit in dest.sym.flags

proc deepAliases(dest, ri: PNode): bool =
  case ri.kind
  of nkCallKinds, nkStmtListExpr, nkBracket, nkTupleConstr, nkObjConstr,
     nkCast, nkConv, nkObjUpConv, nkObjDownConv:
    for r in ri:
      if deepAliases(dest, r): return true
    return false
  else:
    return aliases(dest, ri) != no

proc genSink(c: var Con; s: var Scope; dest, ri: PNode; flags: set[MoveOrCopyFlag] = {}): PNode =
  if (c.inLoopCond == 0 and (isUnpackedTuple(dest) or IsDecl in flags or
      (isAnalysableFieldAccess(dest, c.owner) and isFirstWrite(dest, c)))) or
      isNoInit(dest) or IsReturn in flags:
    # optimize sink call into a bitwise memcopy
    result = newTree(nkFastAsgn, dest, ri)
  else:
    let t = dest.typ.skipTypes({tyGenericInst, tyAlias, tySink})
    if getAttachedOp(c.graph, t, attachedSink) != nil:
      result = c.genOp(t, attachedSink, dest, ri)
      result.add ri
    else:
      # the default is to use combination of `=destroy(dest)` and
      # and copyMem(dest, source). This is efficient.
      if deepAliases(dest, ri):
        # consider: x = x + y, it is wrong to destroy the destination first!
        # tmp to support self assignments
        let tmp = c.getTemp(s, dest.typ, dest.info)
        result = newTree(nkStmtList, newTree(nkFastAsgn, tmp, dest), newTree(nkFastAsgn, dest, ri),
                         c.genDestroy(tmp))
      else:
        result = newTree(nkStmtList, c.genDestroy(dest), newTree(nkFastAsgn, dest, ri))

proc isCriticalLink(dest: PNode): bool {.inline.} =
  #[
  Lins's idea that only "critical" links can introduce a cycle. This is
  critical for the performance guarantees that we strive for: If you
  traverse a data structure, no tracing will be performed at all.
  ORC is about this promise: The GC only touches the memory that the
  mutator touches too.

  These constructs cannot possibly create cycles::

    local = ...

    new(x)
    dest = ObjectConstructor(field: noalias(dest))

  But since 'ObjectConstructor' is already moved into 'dest' all we really have
  to look for is assignments to local variables.
  ]#
  result = dest.kind != nkSym

proc finishCopy(c: var Con; result, dest: PNode; flags: set[MoveOrCopyFlag]; isFromSink: bool) =
  if c.graph.config.selectedGC == gcOrc and IsExplicitSink notin flags:
    # add cyclic flag, but not to sink calls, which IsExplicitSink generates
    let t = dest.typ.skipTypes(tyUserTypeClasses + {tyGenericInst, tyAlias, tySink, tyDistinct})
    if cyclicType(c.graph, t):
      result.add boolLit(c.graph, result.info, isFromSink or isCriticalLink(dest))

proc genMarkCyclic(c: var Con; result, dest: PNode) =
  if c.graph.config.selectedGC == gcOrc:
    let t = dest.typ.skipTypes({tyGenericInst, tyAlias, tySink, tyDistinct})
    if cyclicType(c.graph, t):
      if t.kind == tyRef:
        result.add callCodegenProc(c.graph, "nimMarkCyclic", dest.info, dest)
      else:
        let xenv = genBuiltin(c.graph, c.idgen, mAccessEnv, "accessEnv", dest)
        xenv.typ() = getSysType(c.graph, dest.info, tyPointer)
        result.add callCodegenProc(c.graph, "nimMarkCyclic", dest.info, xenv)

proc genCopyNoCheck(c: var Con; dest, ri: PNode; a: TTypeAttachedOp): PNode =
  let t = dest.typ.skipTypes({tyGenericInst, tyAlias, tySink})
  result = c.genOp(t, a, dest, ri)
  assert ri.typ != nil

proc genCopy(c: var Con; dest, ri: PNode; flags: set[MoveOrCopyFlag]): PNode =
  if c.inEnsureMove > 0:
    localError(c.graph.config, ri.info, errFailedMove, "cannot move '" & $ri &
                                                      "', which introduces an implicit copy")
  let t = dest.typ
  if tfHasOwned in t.flags and ri.kind != nkNilLit:
    # try to improve the error message here:
    if IsExplicitSink in flags:
      c.checkForErrorPragma(t, ri, "=sink")
    else:
      c.checkForErrorPragma(t, ri, "=copy")
  let a = if IsExplicitSink in flags: attachedSink else: attachedAsgn
  result = c.genCopyNoCheck(dest, ri, a)
  assert ri.typ != nil

proc genDiscriminantAsgn(c: var Con; s: var Scope; n: PNode): PNode =
  # discriminator is ordinal value that doesn't need sink destroy
  # but fields within active case branch might need destruction

  # tmp to support self assignments
  let tmp = c.getTemp(s, n[1].typ, n.info)

  result = newTree(nkStmtList)
  result.add newTree(nkFastAsgn, tmp, p(n[1], c, s, consumed))
  result.add p(n[0], c, s, normal)

  let le = p(n[0], c, s, normal)
  let leDotExpr = if le.kind == nkCheckedFieldExpr: le[0] else: le
  let objType = leDotExpr[0].typ

  if hasDestructor(c, objType):
    if getAttachedOp(c.graph, objType, attachedDestructor) != nil and
        sfOverridden in getAttachedOp(c.graph, objType, attachedDestructor).flags:
      localError(c.graph.config, n.info, errGenerated, """Assignment to discriminant for objects with user defined destructor is not supported, object must have default destructor.
It is best to factor out piece of object that needs custom destructor into separate object or not use discriminator assignment""")
      result.add newTree(nkFastAsgn, le, tmp)
      return

    # generate: if le != tmp: `=destroy`(le)
    if c.inUncheckedAssignSection != 0:
      let branchDestructor = produceDestructorForDiscriminator(c.graph, objType, leDotExpr[1].sym, n.info, c.idgen)
      let cond = newNodeIT(nkInfix, n.info, getSysType(c.graph, unknownLineInfo, tyBool))
      cond.add newSymNode(getMagicEqSymForType(c.graph, le.typ, n.info))
      cond.add le
      cond.add tmp
      let notExpr = newNodeIT(nkPrefix, n.info, getSysType(c.graph, unknownLineInfo, tyBool))
      notExpr.add newSymNode(createMagic(c.graph, c.idgen, "not", mNot))
      notExpr.add cond
      result.add newTree(nkIfStmt, newTree(nkElifBranch, notExpr, c.genOp(branchDestructor, le)))
  result.add newTree(nkFastAsgn, le, tmp)

proc genWasMoved(c: var Con, n: PNode): PNode =
  let typ = n.typ.skipTypes({tyGenericInst, tyAlias, tySink})
  let op = getAttachedOp(c.graph, n.typ, attachedWasMoved)
  if op != nil:
    if sfError in op.flags:
      c.checkForErrorPragma(n.typ, n, "=wasMoved")
    result = genOp(c, op, n)
  else:
    result = newNodeI(nkCall, n.info)
    result.add(newSymNode(createMagic(c.graph, c.idgen, "`=wasMoved`", mWasMoved)))
    result.add copyTree(n) #mWasMoved does not take the address
    #if n.kind != nkSym:
    #  message(c.graph.config, n.info, warnUser, "wasMoved(" & $n & ")")

proc genDefaultCall(t: PType; c: Con; info: TLineInfo): PNode =
  result = newNodeI(nkCall, info)
  result.add(newSymNode(createMagic(c.graph, c.idgen, "default", mDefault)))
  result.typ() = t

proc destructiveMoveVar(n: PNode; c: var Con; s: var Scope): PNode =
  # generate: (let tmp = v; reset(v); tmp)
  if (not hasDestructor(c, n.typ)) and c.inEnsureMove == 0:
    assert n.kind != nkSym or not hasDestructor(c, n.sym.typ) or
          (n.typ.kind == tyPtr and n.sym.typ.kind == tyRef)
      # bug #23505; transformed by `transf`: addr (deref ref) -> ptr
      # we know it's really a pointer; so here we assign it directly
    result = copyTree(n)
  else:
    result = newNodeIT(nkStmtListExpr, n.info, n.typ)

    var temp = newSym(skLet, getIdent(c.graph.cache, "blitTmp"), c.idgen, c.owner, n.info)
    temp.typ = n.typ
    var v = newNodeI(nkLetSection, n.info)
    let tempAsNode = newSymNode(temp)

    var vpart = newNodeI(nkIdentDefs, tempAsNode.info, 3)
    vpart[0] = tempAsNode
    vpart[1] = newNodeI(nkEmpty, tempAsNode.info)
    vpart[2] = n
    v.add(vpart)

    result.add v
    let nn = skipConv(n)
    if hasDestructor(c, n.typ):
      c.genMarkCyclic(result, nn)
    let wasMovedCall = c.genWasMoved(nn)
    result.add wasMovedCall
    result.add tempAsNode

proc isCapturedVar(n: PNode): bool =
  let root = getRoot(n)
  if root != nil: result = root.name.s[0] == ':'
  else: result = false

proc passCopyToSink(n: PNode; c: var Con; s: var Scope): PNode =
  result = newNodeIT(nkStmtListExpr, n.info, n.typ)
  let nTyp = n.typ.skipTypes(tyUserTypeClasses)
  let tmp = c.getTemp(s, nTyp, n.info)
  if hasDestructor(c, nTyp):
    let typ = nTyp.skipTypes({tyGenericInst, tyAlias, tySink})
    let op = getAttachedOp(c.graph, typ, attachedDup)
    if op != nil and tfHasOwned notin typ.flags:
      if sfError in op.flags:
        c.checkForErrorPragma(nTyp, n, "=dup")
      else:
        let copyOp = getAttachedOp(c.graph, typ, attachedAsgn)
        if copyOp != nil and sfError in copyOp.flags and
           sfOverridden notin op.flags:
          c.checkForErrorPragma(nTyp, n, "=dup", inferredFromCopy = true)

      let src = p(n, c, s, normal)
      var newCall = newTreeIT(nkCall, src.info, src.typ,
            newSymNode(op),
            src)
      c.finishCopy(newCall, n, {}, isFromSink = true)
      result.add newTreeI(nkFastAsgn,
          src.info, tmp,
          newCall
      )
    else:
      result.add c.genWasMoved(tmp)
      var m = c.genCopy(tmp, n, {})
      m.add p(n, c, s, normal)
      c.finishCopy(m, n, {}, isFromSink = true)
      result.add m
    if isLValue(n) and not isCapturedVar(n) and nTyp.skipTypes(abstractInst).kind != tyRef and c.inSpawn == 0:
      message(c.graph.config, n.info, hintPerformance,
        ("passing '$1' to a sink parameter introduces an implicit copy; " &
        "if possible, rearrange your program's control flow to prevent it") % $n)
    if c.inEnsureMove > 0:
      localError(c.graph.config, n.info, errFailedMove,
        ("cannot move '$1', passing '$1' to a sink parameter introduces an implicit copy") % $n)
  else:
    if c.graph.config.selectedGC in {gcArc, gcOrc, gcAtomicArc}:
      assert(not containsManagedMemory(nTyp))
    if nTyp.skipTypes(abstractInst).kind in {tyOpenArray, tyVarargs}:
      localError(c.graph.config, n.info, "cannot create an implicit openArray copy to be passed to a sink parameter")
    result.add newTree(nkAsgn, tmp, p(n, c, s, normal))
  # Since we know somebody will take over the produced copy, there is
  # no need to destroy it.
  result.add tmp

proc isDangerousSeq(t: PType): bool {.inline.} =
  let t = t.skipTypes(abstractInst)
  result = t.kind == tySequence and tfHasOwned notin t.elementType.flags

proc containsConstSeq(n: PNode): bool =
  if n.kind == nkBracket and n.len > 0 and n.typ != nil and isDangerousSeq(n.typ):
    return true
  result = false
  case n.kind
  of nkExprEqExpr, nkExprColonExpr, nkHiddenStdConv, nkHiddenSubConv, nkCast:
    result = containsConstSeq(n[1])
  of nkObjConstr, nkClosure:
    for i in 1..<n.len:
      if containsConstSeq(n[i]): return true
  of nkCurly, nkBracket, nkPar, nkTupleConstr:
    for son in n:
      if containsConstSeq(son): return true
  else: discard

proc ensureDestruction(arg, orig: PNode; c: var Con; s: var Scope): PNode =
  # it can happen that we need to destroy expression contructors
  # like [], (), closures explicitly in order to not leak them.
  if arg.typ != nil and hasDestructor(c, arg.typ):
    # produce temp creation for (fn, env). But we need to move 'env'?
    # This was already done in the sink parameter handling logic.
    result = newNodeIT(nkStmtListExpr, arg.info, arg.typ)
    let tmp = c.getTemp(s, arg.typ, arg.info)
    result.add c.genSink(s, tmp, arg, {IsDecl})
    result.add tmp
    s.final.add c.genDestroy(tmp)
  else:
    result = arg

proc cycleCheck(n: PNode; c: var Con) =
  if c.graph.config.selectedGC notin {gcArc, gcAtomicArc}: return
  var value = n[1]
  if value.kind == nkClosure:
    value = value[1]
  if value.kind == nkNilLit: return
  let destTyp = n[0].typ.skipTypes(abstractInst)
  if destTyp.kind != tyRef and not (destTyp.kind == tyProc and destTyp.callConv == ccClosure):
    return

  var x = n[0]
  var field: PNode = nil
  while true:
    if x.kind == nkDotExpr:
      field = x[1]
      if field.kind == nkSym and sfCursor in field.sym.flags: return
      x = x[0]
    elif x.kind in {nkBracketExpr, nkCheckedFieldExpr, nkDerefExpr, nkHiddenDeref}:
      x = x[0]
    else:
      break
    if exprStructuralEquivalent(x, value, strictSymEquality = true):
      let msg =
        if field != nil:
          "'$#' creates an uncollectable ref cycle; annotate '$#' with .cursor" % [$n, $field]
        else:
          "'$#' creates an uncollectable ref cycle" % [$n]
      message(c.graph.config, n.info, warnCycleCreated, msg)
      break

proc pVarTopLevel(v: PNode; c: var Con; s: var Scope; res: PNode) =
  # move the variable declaration to the top of the frame:
  s.vars.add v.sym
  if isUnpackedTuple(v):
    if c.inLoop > 0:
      # unpacked tuple needs reset at every loop iteration
      res.add newTree(nkFastAsgn, v, genDefaultCall(v.typ, c, v.info))
  elif sfThread notin v.sym.flags and sfCursor notin v.sym.flags:
    # do not destroy thread vars for now at all for consistency.
    if {sfGlobal, sfPure} <= v.sym.flags or sfGlobal in v.sym.flags and s.parent == nil:
      c.graph.globalDestructors.add c.genDestroy(v)
    else:
      s.final.add c.genDestroy(v)

proc processScope(c: var Con; s: var Scope; ret: PNode): PNode =
  result = newNodeI(nkStmtList, ret.info)
  if s.vars.len > 0:
    let varSection = newNodeI(nkVarSection, ret.info)
    for tmp in s.vars:
      varSection.add newTree(nkIdentDefs, newSymNode(tmp), newNodeI(nkEmpty, ret.info),
                                                           newNodeI(nkEmpty, ret.info))
    result.add varSection
  if s.wasMoved.len > 0 or s.final.len > 0:
    let finSection = newNodeI(nkStmtList, ret.info)
    for m in s.wasMoved: finSection.add m
    for i in countdown(s.final.high, 0): finSection.add s.final[i]
    if s.needsTry:
      result.add newTryFinally(ret, finSection)
    else:
      result.add ret
      result.add finSection
  else:
    result.add ret

  if s.parent != nil: s.parent[].needsTry = s.parent[].needsTry or s.needsTry

template processScopeExpr(c: var Con; s: var Scope; ret: PNode, processCall: untyped, tmpFlags: TSymFlags): PNode =
  assert not ret.typ.isEmptyType
  var result = newNodeIT(nkStmtListExpr, ret.info, ret.typ)
  # There is a possibility to do this check: s.wasMoved.len > 0 or s.final.len > 0
  # later and use it to eliminate the temporary when theres no need for it, but its
  # tricky because you would have to intercept moveOrCopy at a certain point
  let tmp = c.getTemp(s.parent[], ret.typ, ret.info)
  tmp.sym.flags = tmpFlags
  let cpy = if hasDestructor(c, ret.typ) and
                ret.typ.kind notin {tyOpenArray, tyVarargs}:
                # bug #23247 we don't own the data, so it's harmful to destroy it
              s.parent[].final.add c.genDestroy(tmp)
              moveOrCopy(tmp, ret, c, s, {IsDecl})
            else:
              newTree(nkFastAsgn, tmp, p(ret, c, s, normal))

  if s.vars.len > 0:
    let varSection = newNodeI(nkVarSection, ret.info)
    for tmp in s.vars:
      varSection.add newTree(nkIdentDefs, newSymNode(tmp), newNodeI(nkEmpty, ret.info),
                                                           newNodeI(nkEmpty, ret.info))
    result.add varSection
  let finSection = newNodeI(nkStmtList, ret.info)
  for m in s.wasMoved: finSection.add m
  for i in countdown(s.final.high, 0): finSection.add s.final[i]
  if s.needsTry:
    result.add newTryFinally(newTree(nkStmtListExpr, cpy, processCall(tmp, s.parent[])), finSection)
  else:
    result.add cpy
    result.add finSection
    result.add processCall(tmp, s.parent[])

  if s.parent != nil: s.parent[].needsTry = s.parent[].needsTry or s.needsTry

  result

template handleNestedTempl(n, processCall: untyped, willProduceStmt = false,
                           tmpFlags = {sfSingleUsedTemp}) =
  template maybeVoid(child, s): untyped =
    if isEmptyType(child.typ): p(child, c, s, normal)
    else: processCall(child, s)

  case n.kind
  of nkStmtList, nkStmtListExpr:
    # a statement list does not open a new scope
    if n.len == 0: return n
    result = copyNode(n)
    for i in 0..<n.len-1:
      result.add p(n[i], c, s, normal)
    result.add maybeVoid(n[^1], s)

  of nkCaseStmt:
    result = copyNode(n)
    result.add p(n[0], c, s, normal)
    for i in 1..<n.len:
      let it = n[i]
      assert it.kind in {nkOfBranch, nkElse}

      var branch = shallowCopy(it)
      for j in 0 ..< it.len-1:
        branch[j] = copyTree(it[j])
      var ofScope = nestedScope(s, it.lastSon)
      branch[^1] = if n.typ.isEmptyType or it[^1].typ.isEmptyType or willProduceStmt:
                     processScope(c, ofScope, maybeVoid(it[^1], ofScope))
                   else:
                     processScopeExpr(c, ofScope, it[^1], processCall, tmpFlags)
      result.add branch

  of nkWhileStmt:
    inc c.inLoop
    inc c.inLoopCond
    result = copyNode(n)
    result.add p(n[0], c, s, normal)
    dec c.inLoopCond
    var bodyScope = nestedScope(s, n[1])
    let bodyResult = p(n[1], c, bodyScope, normal)
    result.add processScope(c, bodyScope, bodyResult)
    dec c.inLoop

  of nkParForStmt:
    inc c.inLoop
    result = shallowCopy(n)
    let last = n.len-1
    for i in 0..<last-1:
      result[i] = n[i]
    result[last-1] = p(n[last-1], c, s, normal)
    var bodyScope = nestedScope(s, n[1])
    let bodyResult = p(n[last], c, bodyScope, normal)
    result[last] = processScope(c, bodyScope, bodyResult)
    dec c.inLoop

  of nkBlockStmt, nkBlockExpr:
    result = copyNode(n)
    result.add n[0]
    var bodyScope = nestedScope(s, n[1])
    result.add if n[1].typ.isEmptyType or willProduceStmt:
                 processScope(c, bodyScope, processCall(n[1], bodyScope))
               else:
                 processScopeExpr(c, bodyScope, n[1], processCall, tmpFlags)

  of nkIfStmt, nkIfExpr:
    result = copyNode(n)
    for i in 0..<n.len:
      let it = n[i]
      var branch = shallowCopy(it)
      var branchScope = nestedScope(s, it.lastSon)
      if it.kind in {nkElifBranch, nkElifExpr}:
        #Condition needs to be destroyed outside of the condition/branch scope
        branch[0] = p(it[0], c, s, normal)

      branch[^1] = if n.typ.isEmptyType or it[^1].typ.isEmptyType or willProduceStmt:
                     processScope(c, branchScope, maybeVoid(it[^1], branchScope))
                   else:
                     processScopeExpr(c, branchScope, it[^1], processCall, tmpFlags)
      result.add branch

  of nkTryStmt:
    result = copyNode(n)
    var tryScope = nestedScope(s, n[0])
    result.add if n[0].typ.isEmptyType or willProduceStmt:
                 processScope(c, tryScope, maybeVoid(n[0], tryScope))
               else:
                 processScopeExpr(c, tryScope, n[0], maybeVoid, tmpFlags)

    for i in 1..<n.len:
      let it = n[i]
      var branch = copyTree(it)
      var branchScope = nestedScope(s, it[^1])
      branch[^1] = if it[^1].typ.isEmptyType or willProduceStmt or it.kind == nkFinally:
                     processScope(c, branchScope, if it.kind == nkFinally: p(it[^1], c, branchScope, normal)
                                                  else: maybeVoid(it[^1], branchScope))
                   else:
                     processScopeExpr(c, branchScope, it[^1], processCall, tmpFlags)
      result.add branch

  of nkWhen: # This should be a "when nimvm" node.
    result = copyTree(n)
    result[1][0] = processCall(n[1][0], s)

  of nkPragmaBlock:
    var inUncheckedAssignSection = 0
    let pragmaList = n[0]
    for pi in pragmaList:
      if whichPragma(pi) == wCast:
        case whichPragma(pi[1])
        of wUncheckedAssign:
          inUncheckedAssignSection = 1
        else:
          discard
    result = shallowCopy(n)
    inc c.inUncheckedAssignSection, inUncheckedAssignSection
    for i in 0 ..< n.len-1:
      result[i] = p(n[i], c, s, normal)
    result[^1] = maybeVoid(n[^1], s)
    dec c.inUncheckedAssignSection, inUncheckedAssignSection

  else:
    result = nil
    assert(false)

proc pRaiseStmt(n: PNode, c: var Con; s: var Scope): PNode =
  if optOwnedRefs in c.graph.config.globalOptions and n[0].kind != nkEmpty:
    if n[0].kind in nkCallKinds:
      let call = p(n[0], c, s, normal)
      result = copyNode(n)
      result.add call
    else:
      let tmp = c.getTemp(s, n[0].typ, n.info)
      var m = c.genCopyNoCheck(tmp, n[0], attachedAsgn)
      m.add p(n[0], c, s, normal)
      c.finishCopy(m, n[0], {}, isFromSink = false)
      result = newTree(nkStmtList, c.genWasMoved(tmp), m)
      var toDisarm = n[0]
      if toDisarm.kind == nkStmtListExpr: toDisarm = toDisarm.lastSon
      if toDisarm.kind == nkSym and toDisarm.sym.owner == c.owner:
        result.add c.genWasMoved(toDisarm)
      result.add newTree(nkRaiseStmt, tmp)
  else:
    result = copyNode(n)
    if n[0].kind != nkEmpty:
      result.add p(n[0], c, s, sinkArg)
    else:
      result.add copyNode(n[0])
  s.needsTry = true

template isCustomDestructor(c: Con, t: PType): bool =
  hasDestructor(c, t) and
          getAttachedOp(c.graph, t, attachedDestructor) != nil and
          sfOverridden in getAttachedOp(c.graph, t, attachedDestructor).flags

proc hasCustomDestructor(c: Con, t: PType): bool =
  result = isCustomDestructor(c, t)
  var obj = t
  while obj.baseClass != nil:
    obj = skipTypes(obj.baseClass, abstractPtrs)
    result = result or isCustomDestructor(c, obj)

proc p(n: PNode; c: var Con; s: var Scope; mode: ProcessMode; tmpFlags = {sfSingleUsedTemp}; inReturn = false): PNode =
  if n.kind in {nkStmtList, nkStmtListExpr, nkBlockStmt, nkBlockExpr, nkIfStmt,
                nkIfExpr, nkCaseStmt, nkWhen, nkWhileStmt, nkParForStmt, nkTryStmt, nkPragmaBlock}:
    template process(child, s): untyped = p(child, c, s, mode)
    handleNestedTempl(n, process, tmpFlags = tmpFlags)
  elif mode == sinkArg:
    if n.containsConstSeq:
      # const sequences are not mutable and so we need to pass a copy to the
      # sink parameter (bug #11524). Note that the string implementation is
      # different and can deal with 'const string sunk into var'.
      result = passCopyToSink(n, c, s)
    elif n.kind in {nkBracket, nkObjConstr, nkTupleConstr, nkClosure, nkNilLit} +
         nkCallKinds + nkLiterals:
      result = p(n, c, s, consumed)
    elif ((n.kind == nkSym and isSinkParam(n.sym)) or isAnalysableFieldAccess(n, c.owner)) and
        isLastRead(n, c, s) and not (n.kind == nkSym and isCursor(n)):
      # Sinked params can be consumed only once. We need to reset the memory
      # to disable the destructor which we have not elided
      result = destructiveMoveVar(n, c, s)
    elif n.kind in {nkHiddenSubConv, nkHiddenStdConv, nkConv}:
      result = copyTree(n)
      if n.typ.skipTypes(abstractInst-{tyOwned}).kind != tyOwned and
          n[1].typ.skipTypes(abstractInst-{tyOwned}).kind == tyOwned:
        # allow conversions from owned to unowned via this little hack:
        let nTyp = n[1].typ
        n[1].typ() = n.typ
        result[1] = p(n[1], c, s, sinkArg)
        result[1].typ() = nTyp
      else:
        result[1] = p(n[1], c, s, sinkArg)
    elif n.kind in {nkObjDownConv, nkObjUpConv}:
      result = copyTree(n)
      result[0] = p(n[0], c, s, sinkArg)
    elif n.kind == nkCast and n.typ.skipTypes(abstractInst).kind in {tyString, tySequence}:
      result = copyTree(n)
      result[1] = p(n[1], c, s, sinkArg)
    elif n.typ == nil:
      # 'raise X' can be part of a 'case' expression. Deal with it here:
      result = p(n, c, s, normal)
    else:
      # copy objects that are not temporary but passed to a 'sink' parameter
      result = passCopyToSink(n, c, s)
  else:
    case n.kind
    of nkBracket, nkTupleConstr, nkClosure, nkCurly:
      # Let C(x) be the construction, 'x' the vector of arguments.
      # C(x) either owns 'x' or it doesn't.
      # If C(x) owns its data, we must consume C(x).
      # If it doesn't own the data, it's harmful to destroy it (double frees etc).
      # We have the freedom to choose whether it owns it or not so we are smart about it
      # and we say, "if passed to a sink we demand C(x) to own its data"
      # otherwise we say "C(x) is just some temporary storage, it doesn't own anything,
      # don't destroy it"
      # but if C(x) is a ref it MUST own its data since we must destroy it
      # so then we have no choice but to use 'sinkArg'.
      let m = if mode == normal: normal
              else: sinkArg

      result = copyTree(n)
      for i in ord(n.kind == nkClosure)..<n.len:
        if n[i].kind == nkExprColonExpr:
          result[i][1] = p(n[i][1], c, s, m)
        elif n[i].kind == nkRange:
          result[i][0] = p(n[i][0], c, s, m)
          result[i][1] = p(n[i][1], c, s, m)
        else:
          result[i] = p(n[i], c, s, m)
    of nkObjConstr:
      # see also the remark about `nkTupleConstr`.
      let t = n.typ.skipTypes(abstractInst)
      let isRefConstr = t.kind == tyRef
      let m = if isRefConstr: sinkArg
              elif mode == normal: normal
              else: sinkArg

      result = copyTree(n)
      for i in 1..<n.len:
        if n[i].kind == nkExprColonExpr:
          let field = lookupFieldAgain(t, n[i][0].sym)
          if field != nil and (sfCursor in field.flags or field.typ.kind in {tyOpenArray, tyVarargs}):
            # don't sink fields with openarray types
            result[i][1] = p(n[i][1], c, s, normal)
          else:
            result[i][1] = p(n[i][1], c, s, m)
        else:
          result[i] = p(n[i], c, s, m)
      if mode == normal and (isRefConstr or hasCustomDestructor(c, t)):
        result = ensureDestruction(result, n, c, s)
    of nkCallKinds:
      let inSpawn = c.inSpawn
      if n[0].kind == nkSym and n[0].sym.magic == mSpawn:
        c.inSpawn.inc
      elif c.inSpawn > 0:
        c.inSpawn.dec

      # bug #23907; skips tyGenericInst for generic callbacks
      let parameters = if n[0].typ != nil: n[0].typ.skipTypes(abstractInst) else: n[0].typ
      let L = if parameters != nil: parameters.signatureLen else: 0

      when false:
        var isDangerous = false
        if n[0].kind == nkSym and n[0].sym.magic in {mOr, mAnd}:
          inc c.inDangerousBranch
          isDangerous = true

      result = shallowCopy(n)

      if n[0].kind == nkSym and n[0].sym.magic == mEnsureMove:
        inc c.inEnsureMove
        result[1] = p(n[1], c, s, sinkArg)
        dec c.inEnsureMove
      else:
        for i in 1..<n.len:
          if i < L and isCompileTimeOnly(parameters[i]):
            result[i] = n[i]
          elif i < L and (isSinkTypeForParam(parameters[i]) or inSpawn > 0):
            result[i] = p(n[i], c, s, sinkArg)
          else:
            result[i] = p(n[i], c, s, normal)

      when false:
        if isDangerous:
          dec c.inDangerousBranch

      if n[0].kind == nkSym and n[0].sym.magic in {mNew, mNewFinalize}:
        result[0] = copyTree(n[0])
        if c.graph.config.selectedGC in {gcHooks, gcArc, gcAtomicArc, gcOrc}:
          let destroyOld = c.genDestroy(result[1])
          result = newTree(nkStmtList, destroyOld, result)
      else:
        result[0] = p(n[0], c, s, normal)
      if canRaise(n[0]): s.needsTry = true
      if mode == normal:
        if result.typ != nil and result.typ.kind notin {tyOpenArray, tyVarargs}:
          # Returns of openarray types shouldn't be destroyed
          # bug #19435; # bug #23247
          result = ensureDestruction(result, n, c, s)
    of nkDiscardStmt: # Small optimization
      result = shallowCopy(n)
      if n[0].kind != nkEmpty:
        result[0] = p(n[0], c, s, normal)
      else:
        result[0] = copyNode(n[0])
    of nkVarSection, nkLetSection:
      # transform; var x = y to  var x; x op y  where op is a move or copy
      result = newNodeI(nkStmtList, n.info)
      for it in n:
        var ri = it[^1]
        if it.kind == nkVarTuple and hasDestructor(c, ri.typ):
          for i in 0..<it.len-2:
            if it[i].kind == nkSym: s.locals.add it[i].sym
          let x = lowerTupleUnpacking(c.graph, it, c.idgen, c.owner)
          result.add p(x, c, s, consumed)
        elif it.kind == nkIdentDefs and hasDestructor(c, skipPragmaExpr(it[0]).typ):
          for j in 0..<it.len-2:
            let v = skipPragmaExpr(it[j])
            if v.kind == nkSym:
              if sfCompileTime in v.sym.flags: continue
              s.locals.add v.sym
              pVarTopLevel(v, c, s, result)
            if ri.kind != nkEmpty:
              result.add moveOrCopy(v, ri, c, s, if v.kind == nkSym: {IsDecl} else: {})
            elif ri.kind == nkEmpty and c.inLoop > 0:
              let skipInit = v.kind == nkDotExpr and # Closure var
                             sfNoInit in v[1].sym.flags
              if not skipInit:
                result.add moveOrCopy(v, genDefaultCall(v.typ, c, v.info), c, s, if v.kind == nkSym: {IsDecl} else: {})
        else: # keep the var but transform 'ri':
          var v = copyNode(n)
          var itCopy = copyNode(it)
          for j in 0..<it.len-1:
            itCopy.add it[j]
          var flags = {sfSingleUsedTemp}
          if it.kind == nkIdentDefs and it.len == 3 and it[0].kind == nkSym and
                                        sfGlobal in it[0].sym.flags:
            flags.incl sfGlobal
          itCopy.add p(it[^1], c, s, normal, tmpFlags = flags)
          v.add itCopy
          result.add v
    of nkAsgn, nkFastAsgn, nkSinkAsgn:
      if hasDestructor(c, n[0].typ) and n[1].kind notin {nkProcDef, nkDo, nkLambda}:
        if n[0].kind in {nkDotExpr, nkCheckedFieldExpr}:
          cycleCheck(n, c)
        assert n[1].kind notin {nkAsgn, nkFastAsgn, nkSinkAsgn}
        var flags = if n.kind == nkSinkAsgn: {IsExplicitSink} else: {}
        if inReturn:
          flags.incl(IsReturn)
        result = moveOrCopy(p(n[0], c, s, mode), n[1], c, s, flags)
      elif isDiscriminantField(n[0]):
        result = c.genDiscriminantAsgn(s, n)
      else:
        result = copyNode(n)
        result.add p(n[0], c, s, mode)
        result.add p(n[1], c, s, consumed)
    of nkRaiseStmt:
      result = pRaiseStmt(n, c, s)
    of nkWhileStmt:
      internalError(c.graph.config, n.info, "nkWhileStmt should have been handled earlier")
      result = n
    of nkNone..nkNilLit, nkTypeSection, nkProcDef, nkConverterDef,
       nkMethodDef, nkIteratorDef, nkMacroDef, nkTemplateDef, nkLambda, nkDo,
       nkFuncDef, nkConstSection, nkConstDef, nkIncludeStmt, nkImportStmt,
       nkExportStmt, nkPragma, nkCommentStmt, nkBreakState,
       nkTypeOfExpr, nkMixinStmt, nkBindStmt:
      result = n

    of nkStringToCString, nkCStringToString, nkChckRangeF, nkChckRange64, nkChckRange:
      result = shallowCopy(n)
      for i in 0 ..< n.len:
        result[i] = p(n[i], c, s, normal)
      if n.typ != nil and hasDestructor(c, n.typ):
        if mode == normal:
          result = ensureDestruction(result, n, c, s)

    of nkHiddenSubConv, nkHiddenStdConv, nkConv:
      # we have an "ownership invariance" for all constructors C(x).
      # See the comment for nkBracket construction. If the caller wants
      # to own 'C(x)', it really wants to own 'x' too. If it doesn't,
      # we need to destroy 'x' but the function call handling ensures that
      # already.
      result = copyTree(n)
      if n.typ.skipTypes(abstractInst-{tyOwned}).kind != tyOwned and
          n[1].typ.skipTypes(abstractInst-{tyOwned}).kind == tyOwned:
        # allow conversions from owned to unowned via this little hack:
        let nTyp = n[1].typ
        n[1].typ() = n.typ
        result[1] = p(n[1], c, s, mode)
        result[1].typ() = nTyp
      else:
        result[1] = p(n[1], c, s, mode)

    of nkObjDownConv, nkObjUpConv:
      result = copyTree(n)
      result[0] = p(n[0], c, s, mode)

    of nkDotExpr:
      result = shallowCopy(n)
      result[0] = p(n[0], c, s, normal)
      for i in 1 ..< n.len:
        result[i] = n[i]
      if mode == sinkArg and hasDestructor(c, n.typ):
        if isAnalysableFieldAccess(n, c.owner) and isLastRead(n, c, s):
          s.wasMoved.add c.genWasMoved(n)
        else:
          result = passCopyToSink(result, c, s)

    of nkBracketExpr, nkAddr, nkHiddenAddr, nkDerefExpr, nkHiddenDeref:
      result = shallowCopy(n)
      for i in 0 ..< n.len:
        result[i] = p(n[i], c, s, normal)
      if mode == sinkArg and hasDestructor(c, n.typ):
        if isAnalysableFieldAccess(n, c.owner) and isLastRead(n, c, s):
          # consider 'a[(g; destroy(g); 3)]', we want to say 'wasMoved(a[3])'
          # without the junk, hence 'c.genWasMoved(n)'
          # and not 'c.genWasMoved(result)':
          s.wasMoved.add c.genWasMoved(n)
        else:
          result = passCopyToSink(result, c, s)

    of nkDefer, nkRange:
      result = shallowCopy(n)
      for i in 0 ..< n.len:
        result[i] = p(n[i], c, s, normal)

    of nkBreakStmt:
      s.needsTry = true
      result = n
    of nkReturnStmt:
      result = shallowCopy(n)
      for i in 0..<n.len:
        result[i] = p(n[i], c, s, mode, inReturn=true)
      s.needsTry = true
    of nkCast:
      result = shallowCopy(n)
      result[0] = n[0]
      result[1] = p(n[1], c, s, mode)
    of nkCheckedFieldExpr:
      result = shallowCopy(n)
      result[0] = p(n[0], c, s, mode)
      for i in 1..<n.len:
        result[i] = n[i]
    of nkGotoState, nkState, nkAsmStmt:
      result = n
    else:
      result = nil
      internalError(c.graph.config, n.info, "cannot inject destructors to node kind: " & $n.kind)

proc sameLocation*(a, b: PNode): bool =
  proc sameConstant(a, b: PNode): bool =
    a.kind in nkLiterals and b.kind in nkLiterals and a.intVal == b.intVal

  const nkEndPoint = {nkSym, nkDotExpr, nkCheckedFieldExpr, nkBracketExpr}
  if a.kind in nkEndPoint and b.kind in nkEndPoint:
    if a.kind == b.kind:
      case a.kind
      of nkSym: a.sym == b.sym
      of nkDotExpr, nkCheckedFieldExpr: sameLocation(a[0], b[0]) and sameLocation(a[1], b[1])
      of nkBracketExpr: sameLocation(a[0], b[0]) and sameConstant(a[1], b[1])
      else: false
    else: false
  else:
    case a.kind
    of nkSym, nkDotExpr, nkCheckedFieldExpr, nkBracketExpr:
      # Reached an endpoint, flip to recurse the other side.
      sameLocation(b, a)
    of nkAddr, nkHiddenAddr, nkDerefExpr, nkHiddenDeref:
      # We don't need to check addr/deref levels or differentiate between the two,
      # since pointers don't have hooks :) (e.g: var p: ptr pointer; p[] = addr p)
      sameLocation(a[0], b)
    of nkObjDownConv, nkObjUpConv: sameLocation(a[0], b)
    of nkHiddenStdConv, nkHiddenSubConv: sameLocation(a[1], b)
    else: false

proc genFieldAccessSideEffects(c: var Con; s: var Scope; dest, ri: PNode; flags: set[MoveOrCopyFlag] = {}): PNode =
  # with side effects
  var temp = newSym(skLet, getIdent(c.graph.cache, "bracketTmp"), c.idgen, c.owner, ri[1].info)
  temp.typ = ri[1].typ
  var v = newNodeI(nkLetSection, ri[1].info)
  let tempAsNode = newSymNode(temp)

  var vpart = newNodeI(nkIdentDefs, tempAsNode.info, 3)
  vpart[0] = tempAsNode
  vpart[1] = newNodeI(nkEmpty, tempAsNode.info)
  vpart[2] = ri[1]
  v.add(vpart)

  var newAccess = copyNode(ri)
  newAccess.add ri[0]
  newAccess.add tempAsNode

  var snk = c.genSink(s, dest, newAccess, flags)
  result = newTree(nkStmtList, v, snk, c.genWasMoved(newAccess))

proc moveOrCopy(dest, ri: PNode; c: var Con; s: var Scope, flags: set[MoveOrCopyFlag] = {}): PNode =
  var ri = ri
  var isEnsureMove = 0
  if ri.kind in nkCallKinds and ri[0].kind == nkSym and ri[0].sym.magic == mEnsureMove:
    ri = ri[1]
    isEnsureMove = 1
  if sameLocation(dest, ri):
    # rule (self-assignment-removal):
    result = newNodeI(nkEmpty, dest.info)
  elif isCursor(dest) or dest.typ.kind in {tyOpenArray, tyVarargs}:
    # hoisted openArray parameters might end up here
    # openArray types don't have a lifted assignment operation (it's empty)
    # bug #22132
    case ri.kind:
    of nkStmtListExpr, nkBlockExpr, nkIfExpr, nkCaseStmt, nkTryStmt:
      template process(child, s): untyped = moveOrCopy(dest, child, c, s, flags)
      # We know the result will be a stmt so we use that fact to optimize
      handleNestedTempl(ri, process, willProduceStmt = true)
    else:
      result = newTree(nkFastAsgn, dest, p(ri, c, s, normal))
  else:
    let ri2 = if ri.kind == nkWhen: ri[1][0] else: ri
    case ri2.kind
    of nkCallKinds:
      result = c.genSink(s, dest, p(ri, c, s, consumed), flags)
    of nkBracketExpr:
      if isUnpackedTuple(ri[0]):
        # unpacking of tuple: take over the elements
        result = c.genSink(s, dest, p(ri, c, s, consumed), flags)
      elif isAnalysableFieldAccess(ri, c.owner) and isLastRead(ri, c, s):
        if aliases(dest, ri) == no:
          # Rule 3: `=sink`(x, z); wasMoved(z)
          if isAtom(ri[1]):
            var snk = c.genSink(s, dest, ri, flags)
            result = newTree(nkStmtList, snk, c.genWasMoved(ri))
          else:
            result = genFieldAccessSideEffects(c, s, dest, ri, flags)
        else:
          result = c.genSink(s, dest, destructiveMoveVar(ri, c, s), flags)
      else:
        inc c.inEnsureMove, isEnsureMove
        result = c.genCopy(dest, ri, flags)
        dec c.inEnsureMove, isEnsureMove
        result.add p(ri, c, s, consumed)
        c.finishCopy(result, dest, flags, isFromSink = false)
    of nkBracket:
      # array constructor
      if ri.len > 0 and isDangerousSeq(ri.typ):
        inc c.inEnsureMove, isEnsureMove
        result = c.genCopy(dest, ri, flags)
        dec c.inEnsureMove, isEnsureMove
        result.add p(ri, c, s, consumed)
        c.finishCopy(result, dest, flags, isFromSink = false)
      else:
        result = c.genSink(s, dest, p(ri, c, s, consumed), flags)
    of nkObjConstr, nkTupleConstr, nkClosure, nkCharLit..nkNilLit:
      result = c.genSink(s, dest, p(ri, c, s, consumed), flags)
    of nkSym:
      if isSinkParam(ri.sym) and isLastRead(ri, c, s):
        # Rule 3: `=sink`(x, z); wasMoved(z)
        let snk = c.genSink(s, dest, ri, flags)
        result = newTree(nkStmtList, snk, c.genWasMoved(ri))
      elif ri.sym.kind != skParam and
          isAnalysableFieldAccess(ri, c.owner) and
          isLastRead(ri, c, s) and canBeMoved(c, dest.typ):
        # Rule 3: `=sink`(x, z); wasMoved(z)
        let snk = c.genSink(s, dest, ri, flags)
        result = newTree(nkStmtList, snk, c.genWasMoved(ri))
      else:
        inc c.inEnsureMove, isEnsureMove
        result = c.genCopy(dest, ri, flags)
        dec c.inEnsureMove, isEnsureMove
        result.add p(ri, c, s, consumed)
        c.finishCopy(result, dest, flags, isFromSink = false)
    of nkHiddenSubConv, nkHiddenStdConv, nkConv, nkObjDownConv, nkObjUpConv, nkCast:
      result = c.genSink(s, dest, p(ri, c, s, sinkArg), flags)
    of nkStmtListExpr, nkBlockExpr, nkIfExpr, nkCaseStmt, nkTryStmt:
      template process(child, s): untyped = moveOrCopy(dest, child, c, s, flags)
      # We know the result will be a stmt so we use that fact to optimize
      handleNestedTempl(ri, process, willProduceStmt = true)
    of nkRaiseStmt:
      result = pRaiseStmt(ri, c, s)
    else:
      if isAnalysableFieldAccess(ri, c.owner) and isLastRead(ri, c, s) and
          canBeMoved(c, dest.typ):
        # Rule 3: `=sink`(x, z); wasMoved(z)
        let snk = c.genSink(s, dest, ri, flags)
        result = newTree(nkStmtList, snk, c.genWasMoved(ri))
      else:
        inc c.inEnsureMove, isEnsureMove
        result = c.genCopy(dest, ri, flags)
        dec c.inEnsureMove, isEnsureMove
        result.add p(ri, c, s, consumed)
        c.finishCopy(result, dest, flags, isFromSink = false)

when false:
  proc computeUninit(c: var Con) =
    if not c.uninitComputed:
      c.uninitComputed = true
      c.uninit = initIntSet()
      var init = initIntSet()
      discard initialized(c.g, pc = 0, init, c.uninit, int.high)

  proc injectDefaultCalls(n: PNode, c: var Con) =
    case n.kind
    of nkVarSection, nkLetSection:
      for it in n:
        if it.kind == nkIdentDefs and it[^1].kind == nkEmpty:
          computeUninit(c)
          for j in 0..<it.len-2:
            let v = skipPragmaExpr(it[j])
            doAssert v.kind == nkSym
            if c.uninit.contains(v.sym.id):
              it[^1] = genDefaultCall(v.sym.typ, c, v.info)
              break
    of nkNone..nkNilLit, nkTypeSection, nkProcDef, nkConverterDef, nkMethodDef,
        nkIteratorDef, nkMacroDef, nkTemplateDef, nkLambda, nkDo, nkFuncDef:
      discard
    else:
      for i in 0..<n.safeLen:
        injectDefaultCalls(n[i], c)

proc injectDestructorCalls*(g: ModuleGraph; idgen: IdGenerator; owner: PSym; n: PNode): PNode =
  when toDebug.len > 0:
    shouldDebug = toDebug == owner.name.s or toDebug == "always"
  if sfGeneratedOp in owner.flags or (owner.kind == skIterator and isInlineIterator(owner.typ)):
    return n
  var c = Con(owner: owner, graph: g, idgen: idgen, body: n, otherUsage: unknownLineInfo)

  if optCursorInference in g.config.options:
    computeCursors(owner, n, g)

  var scope = Scope(body: n)
  let body = p(n, c, scope, normal)

  if owner.kind in {skProc, skFunc, skMethod, skIterator, skConverter}:
    let params = owner.typ.n
    for i in 1..<params.len:
      let t = params[i].sym.typ
      if isSinkTypeForParam(t) and hasDestructor(c, t.skipTypes({tySink})):
        scope.final.add c.genDestroy(params[i])
  #if optNimV2 in c.graph.config.globalOptions:
  #  injectDefaultCalls(n, c)
  result = optimize processScope(c, scope, body)
  dbg:
    echo ">---------transformed-to--------->"
    echo renderTree(result, {renderIds})

  if g.config.arcToExpand.hasKey(owner.name.s):
    echo "--expandArc: ", owner.name.s
    echo renderTree(result, {renderIr, renderNoComments})
    echo "-- end of expandArc ------------------------"

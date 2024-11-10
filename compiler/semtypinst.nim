#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# This module does the instantiation of generic types.

import std / tables

import ast, astalgo, msgs, types, magicsys, semdata, renderer, options,
  lineinfos, modulegraphs, layeredtable

when defined(nimPreviewSlimSystem):
  import std/assertions

const tfInstClearedFlags = {tfHasMeta, tfUnresolved}

proc checkPartialConstructedType(conf: ConfigRef; info: TLineInfo, t: PType) =
  if t.kind in {tyVar, tyLent} and t.elementType.kind in {tyVar, tyLent}:
    localError(conf, info, "type 'var var' is not allowed")

proc checkConstructedType*(conf: ConfigRef; info: TLineInfo, typ: PType) =
  var t = typ.skipTypes({tyDistinct})
  if t.kind in tyTypeClasses: discard
  elif t.kind in {tyVar, tyLent} and t.elementType.kind in {tyVar, tyLent}:
    localError(conf, info, "type 'var var' is not allowed")
  elif computeSize(conf, t) == szIllegalRecursion or isTupleRecursive(t):
    localError(conf, info, "illegal recursion in type '" & typeToString(t) & "'")

proc searchInstTypes*(g: ModuleGraph; key: PType): PType =
  result = nil
  let genericTyp = key[0]
  if not (genericTyp.kind == tyGenericBody and
      genericTyp.sym != nil): return

  for inst in typeInstCacheItems(g, genericTyp.sym):
    if inst.id == key.id: return inst
    if inst.kidsLen < key.kidsLen:
      # XXX: This happens for prematurely cached
      # types such as Channel[empty]. Why?
      # See the notes for PActor in handleGenericInvocation
      # if this is return the same type gets cached more than it needs to
      continue
    if not sameFlags(inst, key):
      continue

    block matchType:
      for j in FirstGenericParamAt..<key.kidsLen:
        # XXX sameType is not really correct for nested generics?
        if not compareTypes(inst[j], key[j],
                            flags = {ExactGenericParams, PickyCAliases}):
          break matchType

      return inst

proc cacheTypeInst(c: PContext; inst: PType) =
  let gt = inst[0]
  let t = if gt.kind == tyGenericBody: gt.typeBodyImpl else: gt
  if t.kind in {tyStatic, tyError, tyGenericParam} + tyTypeClasses:
    return
  addToGenericCache(c, gt.sym, inst)

type
  TReplTypeVars* = object
    c*: PContext
    typeMap*: LayeredIdTable  # map PType to PType
    symMap*: SymMapping         # map PSym to PSym
    localCache*: TypeMapping     # local cache for remembering already replaced
                              # types during instantiation of meta types
                              # (they are not stored in the global cache)
    info*: TLineInfo
    allowMetaTypes*: bool     # allow types such as seq[Number]
                              # i.e. the result contains unresolved generics
    skipTypedesc*: bool       # whether we should skip typeDescs
    isReturnType*: bool
    owner*: PSym              # where this instantiation comes from
    recursionLimit: int

proc replaceTypeVarsTAux(cl: var TReplTypeVars, t: PType, isInstValue = false): PType
proc replaceTypeVarsS(cl: var TReplTypeVars, s: PSym, t: PType): PSym
proc replaceTypeVarsN*(cl: var TReplTypeVars, n: PNode; start=0; expectedType: PType = nil): PNode

proc newTypeMapLayer*(cl: var TReplTypeVars): LayeredIdTable =
  result = newTypeMapLayer(cl.typeMap)

template checkMetaInvariants(cl: TReplTypeVars, t: PType) = # noop code
  when false:
    if t != nil and tfHasMeta in t.flags and
       cl.allowMetaTypes == false:
      echo "UNEXPECTED META ", t.id, " ", instantiationInfo(-1)
      debug t
      writeStackTrace()

proc replaceTypeVarsT*(cl: var TReplTypeVars, t: PType, isInstValue = false): PType =
  result = replaceTypeVarsTAux(cl, t, isInstValue)
  checkMetaInvariants(cl, result)

proc prepareNode*(cl: var TReplTypeVars, n: PNode): PNode =
  ## instantiates a given generic expression, not a type node
  if n.kind == nkSym and n.sym.kind == skType and
      n.sym.typ != nil and n.sym.typ.kind == tyGenericBody:
    # generic body types are allowed as user expressions, see #24090
    return n
  let t = replaceTypeVarsT(cl, n.typ)
  if t != nil and t.kind == tyStatic and t.n != nil:
    return if tfUnresolved in t.flags: prepareNode(cl, t.n)
           else: t.n
  result = copyNode(n)
  result.typ() = t
  if result.kind == nkSym:
    result.sym =
      if n.typ != nil and n.typ == n.sym.typ:
        replaceTypeVarsS(cl, n.sym, result.typ)
      else:
        replaceTypeVarsS(cl, n.sym, replaceTypeVarsT(cl, n.sym.typ))
  # we need to avoid trying to instantiate nodes that can have uninstantiated
  # types, like generic proc symbols or raw generic type symbols
  case n.kind
  of nkSymChoices:
    # don't try to instantiate symchoice symbols, they can be
    # generic procs which the compiler will think are uninstantiated
    # because their type will contain uninstantiated params
    for i in 0..<n.len:
      result.add(n[i])
  of nkCallKinds:
    # don't try to instantiate call names since they may be generic proc syms
    # also bracket expressions can turn into calls with symchoice [] and
    # we need to not instantiate the Generic in Generic[int]
    # exception exists for the call name being a dot expression since
    # dot expressions need their LHS instantiated
    assert n.len != 0
    # avoid instantiating generic proc symbols, refine condition if needed:
    let ignoreFirst = n[0].kind notin {nkDotExpr, nkBracketExpr} + nkCallKinds
    let name = n[0].getPIdent
    let ignoreSecond = name != nil and name.s == "[]" and n.len > 1 and
      # generic type instantiation:
      ((n[1].typ != nil and n[1].typ.kind == tyTypeDesc) or
        # generic proc instantiation:
        (n[1].kind == nkSym and n[1].sym.isGenericRoutineStrict))
    if ignoreFirst:
      result.add(n[0])
    else:
      result.add(prepareNode(cl, n[0]))
    if n.len > 1:
      if ignoreSecond:
        result.add(n[1])
      else:
        result.add(prepareNode(cl, n[1]))
    for i in 2..<n.len:
      result.add(prepareNode(cl, n[i]))
  of nkBracketExpr:
    # don't instantiate Generic body type in expression like Generic[T]
    # exception exists for the call name being a dot expression since
    # dot expressions need their LHS instantiated
    assert n.len != 0
    let ignoreFirst = n[0].kind != nkDotExpr and
      # generic type instantiation:
      ((n[0].typ != nil and n[0].typ.kind == tyTypeDesc) or
        # generic proc instantiation:
        (n[0].kind == nkSym and n[0].sym.isGenericRoutineStrict))
    if ignoreFirst:
      result.add(n[0])
    else:
      result.add(prepareNode(cl, n[0]))
    for i in 1..<n.len:
      result.add(prepareNode(cl, n[i]))
  of nkDotExpr:
    # don't try to instantiate RHS of dot expression, it can outright be
    # undeclared, but definitely instantiate LHS
    assert n.len >= 2
    result.add(prepareNode(cl, n[0]))
    result.add(n[1])
    for i in 2..<n.len:
      result.add(prepareNode(cl, n[i]))
  else:
    for i in 0..<n.safeLen:
      result.add(prepareNode(cl, n[i]))

proc isTypeParam(n: PNode): bool =
  # XXX: generic params should use skGenericParam instead of skType
  return n.kind == nkSym and
         (n.sym.kind == skGenericParam or
           (n.sym.kind == skType and sfFromGeneric in n.sym.flags))

when false: # old workaround
  proc reResolveCallsWithTypedescParams(cl: var TReplTypeVars, n: PNode): PNode =
    # This is needed for tuninstantiatedgenericcalls
    # It's possible that a generic param will be used in a proc call to a
    # typedesc accepting proc. After generic param substitution, such procs
    # should be optionally instantiated with the correct type. In order to
    # perform this instantiation, we need to re-run the generateInstance path
    # in the compiler, but it's quite complicated to do so at the moment so we
    # resort to a mild hack; the head symbol of the call is temporary reset and
    # overload resolution is executed again (which may trigger generateInstance).
    if n.kind in nkCallKinds and sfFromGeneric in n[0].sym.flags:
      var needsFixing = false
      for i in 1..<n.safeLen:
        if isTypeParam(n[i]): needsFixing = true
      if needsFixing:
        n[0] = newSymNode(n[0].sym.owner)
        return cl.c.semOverloadedCall(cl.c, n, n, {skProc, skFunc}, {})

    for i in 0..<n.safeLen:
      n[i] = reResolveCallsWithTypedescParams(cl, n[i])

    return n

proc replaceObjBranches(cl: TReplTypeVars, n: PNode): PNode =
  result = n
  case n.kind
  of nkNone..nkNilLit:
    discard
  of nkRecWhen:
    var branch: PNode = nil              # the branch to take
    for i in 0..<n.len:
      var it = n[i]
      if it == nil: illFormedAst(n, cl.c.config)
      case it.kind
      of nkElifBranch:
        checkSonsLen(it, 2, cl.c.config)
        var cond = it[0]
        var e = cl.c.semConstExpr(cl.c, cond)
        if e.kind != nkIntLit:
          internalError(cl.c.config, e.info, "ReplaceTypeVarsN: when condition not a bool")
        if e.intVal != 0 and branch == nil: branch = it[1]
      of nkElse:
        checkSonsLen(it, 1, cl.c.config)
        if branch == nil: branch = it[0]
      else: illFormedAst(n, cl.c.config)
    if branch != nil:
      result = replaceObjBranches(cl, branch)
    else:
      result = newNodeI(nkRecList, n.info)
  else:
    for i in 0..<n.len:
      n[i] = replaceObjBranches(cl, n[i])

proc hasValuelessStatics(n: PNode): bool =
  # We should only attempt to call an expression that has no tyStatics
  # As those are unresolved generic parameters, which means in the following
  # The compiler attempts to do `T == 300` which errors since the typeclass `MyThing` lacks a parameter
  #[
    type MyThing[T: static int] = object
      when T == 300:
        a
    proc doThing(_: MyThing)
  ]#
  if n.safeLen == 0 and n.kind != nkEmpty: # Some empty nodes can get in here
    n.typ == nil or n.typ.kind == tyStatic
  else:
    for x in n:
      if hasValuelessStatics(x):
        return true
    false

proc replaceTypeVarsN(cl: var TReplTypeVars, n: PNode; start=0; expectedType: PType = nil): PNode =
  if n == nil: return
  result = copyNode(n)
  if n.typ != nil:
    if n.typ.kind == tyFromExpr:
      # type of node should not be evaluated as a static value
      n.typ.flags.incl tfNonConstExpr
    result.typ() = replaceTypeVarsT(cl, n.typ)
    checkMetaInvariants(cl, result.typ)
  case n.kind
  of nkNone..pred(nkSym), succ(nkSym)..nkNilLit:
    discard
  of nkOpenSymChoice, nkClosedSymChoice: result = n
  of nkSym:
    result.sym =
      if n.typ != nil and n.typ == n.sym.typ:
        replaceTypeVarsS(cl, n.sym, result.typ)
      else:
        replaceTypeVarsS(cl, n.sym, replaceTypeVarsT(cl, n.sym.typ))
    if result.sym.kind == skField and result.sym.ast != nil and
        (cl.owner == nil or result.sym.owner == cl.owner):
      # instantiate default value of object/tuple field
      cl.c.fitDefaultNode(cl.c, result.sym.ast, result.sym.typ)
      result.sym.typ = result.sym.ast.typ
    # sym type can be nil if was gensym created by macro, see #24048
    if result.sym.typ != nil and result.sym.typ.kind == tyVoid:
      # don't add the 'void' field
      result = newNodeI(nkRecList, n.info)
  of nkRecWhen:
    var branch: PNode = nil              # the branch to take
    for i in 0..<n.len:
      var it = n[i]
      if it == nil: illFormedAst(n, cl.c.config)
      case it.kind
      of nkElifBranch:
        checkSonsLen(it, 2, cl.c.config)
        var cond = prepareNode(cl, it[0])
        if not cond.hasValuelessStatics:
          var e = cl.c.semConstExpr(cl.c, cond)
          if e.kind != nkIntLit:
            internalError(cl.c.config, e.info, "ReplaceTypeVarsN: when condition not a bool")
          if e.intVal != 0 and branch == nil: branch = it[1]
      of nkElse:
        checkSonsLen(it, 1, cl.c.config)
        if branch == nil: branch = it[0]
      else: illFormedAst(n, cl.c.config)
    if branch != nil:
      result = replaceTypeVarsN(cl, branch)
    else:
      result = newNodeI(nkRecList, n.info)
  of nkStaticExpr:
    var n = prepareNode(cl, n)
    when false:
      n = reResolveCallsWithTypedescParams(cl, n)
    result = if cl.allowMetaTypes: n
             else: cl.c.semExpr(cl.c, n, {}, expectedType)
    if not cl.allowMetaTypes and expectedType != nil:
      assert result.kind notin nkCallKinds
  else:
    if n.len > 0:
      newSons(result, n.len)
      if start > 0:
        result[0] = n[0]
      for i in start..<n.len:
        result[i] = replaceTypeVarsN(cl, n[i])

proc replaceTypeVarsS(cl: var TReplTypeVars, s: PSym, t: PType): PSym =
  if s == nil: return nil
  # symbol is not our business:
  if cl.owner != nil and s.owner != cl.owner:
    return s

  # XXX: Bound symbols in default parameter expressions may reach here.
  # We cannot process them, because `sym.n` may point to a proc body with
  # cyclic references that will lead to an infinite recursion.
  # Perhaps we should not use a black-list here, but a whitelist instead
  # (e.g. skGenericParam and skType).
  # Note: `s.magic` may be `mType` in an example such as:
  # proc foo[T](a: T, b = myDefault(type(a)))
  if s.kind in routineKinds+{skLet, skConst, skVar} or s.magic != mNone:
    return s

  #result = PSym(idTableGet(cl.symMap, s))
  #if result == nil:
  #[

  We cannot naively check for symbol recursions, because otherwise
  object types A, B whould share their fields!

      import tables

      type
        Table[S, T] = object
          x: S
          y: T

        G[T] = object
          inodes: Table[int, T] # A
          rnodes: Table[T, int] # B

      var g: G[string]

  ]#
  result = copySym(s, cl.c.idgen)
  incl(result.flags, sfFromGeneric)
  #idTablePut(cl.symMap, s, result)
  setOwner(result, s.owner)
  result.typ = t
  if result.kind != skType:
    result.ast = replaceTypeVarsN(cl, s.ast)

proc lookupTypeVar(cl: var TReplTypeVars, t: PType): PType =
  if tfRetType in t.flags and t.kind == tyAnything:
    # don't bind `auto` return type to a previous binding of `auto`
    return nil
  result = cl.typeMap.lookup(t)
  if result == nil:
    if cl.allowMetaTypes or tfRetType in t.flags: return
    localError(cl.c.config, t.sym.info, "cannot instantiate: '" & typeToString(t) & "'")
    result = errorType(cl.c)
    # In order to prevent endless recursions, we must remember
    # this bad lookup and replace it with errorType everywhere.
    # These code paths are only active in "nim check"
    cl.typeMap.put(t, result)
  elif result.kind == tyGenericParam and not cl.allowMetaTypes:
    internalError(cl.c.config, cl.info, "substitution with generic parameter")

proc instCopyType*(cl: var TReplTypeVars, t: PType): PType =
  # XXX: relying on allowMetaTypes is a kludge
  if cl.allowMetaTypes:
    result = t.exactReplica
  else:
    result = copyType(t, cl.c.idgen, t.owner)
    copyTypeProps(cl.c.graph, cl.c.idgen.module, result, t)
    #cl.typeMap.topLayer.idTablePut(result, t)

  if cl.allowMetaTypes: return
  result.flags.incl tfFromGeneric
  if not (t.kind in tyMetaTypes or
         (t.kind == tyStatic and t.n == nil)):
    result.flags.excl tfInstClearedFlags
  else:
    result.flags.excl tfHasAsgn
  when false:
    if newDestructors:
      result.assignment = nil
      result.destructor = nil
      result.sink = nil

proc handleGenericInvocation(cl: var TReplTypeVars, t: PType): PType =
  # tyGenericInvocation[A, tyGenericInvocation[A, B]]
  # is difficult to handle:
  var body = t.genericHead
  if body.kind != tyGenericBody:
    internalError(cl.c.config, cl.info, "no generic body")
  var header = t
  # search for some instantiation here:
  if cl.allowMetaTypes:
    result = getOrDefault(cl.localCache, t.itemId)
  else:
    result = searchInstTypes(cl.c.graph, t)

  if result != nil and sameFlags(result, t):
    when defined(reportCacheHits):
      echo "Generic instantiation cached ", typeToString(result), " for ", typeToString(t)
    return
  for i in FirstGenericParamAt..<t.kidsLen:
    var x = t[i]
    if x.kind in {tyGenericParam}:
      x = lookupTypeVar(cl, x)
      if x != nil:
        if header == t: header = instCopyType(cl, t)
        header[i] = x
        propagateToOwner(header, x)
    else:
      propagateToOwner(header, x)

  if header != t:
    # search again after first pass:
    result = searchInstTypes(cl.c.graph, header)
    if result != nil and sameFlags(result, t):
      when defined(reportCacheHits):
        echo "Generic instantiation cached ", typeToString(result), " for ",
          typeToString(t), " header ", typeToString(header)
      return
  else:
    header = instCopyType(cl, t)

  result = newType(tyGenericInst, cl.c.idgen, t.genericHead.owner, son = header.genericHead)
  result.flags = header.flags
  # be careful not to propagate unnecessary flags here (don't use rawAddSon)
  # ugh need another pass for deeply recursive generic types (e.g. PActor)
  # we need to add the candidate here, before it's fully instantiated for
  # recursive instantions:
  if not cl.allowMetaTypes:
    cacheTypeInst(cl.c, result)
  else:
    cl.localCache[t.itemId] = result

  let oldSkipTypedesc = cl.skipTypedesc
  cl.skipTypedesc = true

  cl.typeMap = newTypeMapLayer(cl)

  for i in FirstGenericParamAt..<t.kidsLen:
    var x = replaceTypeVarsT(cl):
      if header[i].kind == tyGenericInst:
        t[i]
      else:
        header[i]
    assert x.kind != tyGenericInvocation
    header[i] = x
    propagateToOwner(header, x)
    cl.typeMap.put(body[i-1], x)

  for i in FirstGenericParamAt..<t.kidsLen:
    # if one of the params is not concrete, we cannot do anything
    # but we already raised an error!
    rawAddSon(result, header[i], propagateHasAsgn = false)

  if body.kind == tyError:
    return

  let bbody = last body
  var newbody = replaceTypeVarsT(cl, bbody, isInstValue = true)
  cl.skipTypedesc = oldSkipTypedesc
  newbody.flags = newbody.flags + (t.flags + body.flags - tfInstClearedFlags)
  result.flags = result.flags + newbody.flags - tfInstClearedFlags

  setToPreviousLayer(cl.typeMap)

  # This is actually wrong: tgeneric_closure fails with this line:
  #newbody.callConv = body.callConv
  # This type may be a generic alias and we want to resolve it here.
  # One step is enough, because the recursive nature of
  # handleGenericInvocation will handle the alias-to-alias-to-alias case
  if newbody.isGenericAlias: newbody = newbody.skipGenericAlias

  rawAddSon(result, newbody)
  checkPartialConstructedType(cl.c.config, cl.info, newbody)
  if not cl.allowMetaTypes:
    let dc = cl.c.graph.getAttachedOp(newbody, attachedDeepCopy)
    if dc != nil and sfFromGeneric notin dc.flags:
      # 'deepCopy' needs to be instantiated for
      # generics *when the type is constructed*:
      cl.c.graph.setAttachedOp(cl.c.module.position, newbody, attachedDeepCopy,
          cl.c.instTypeBoundOp(cl.c, dc, result, cl.info, attachedDeepCopy, 1))
    if newbody.typeInst == nil:
      # doAssert newbody.typeInst == nil
      newbody.typeInst = result
      if tfRefsAnonObj in newbody.flags and newbody.kind != tyGenericInst:
        # can come here for tyGenericInst too, see tests/metatype/ttypeor.nim
        # need to look into this issue later
        assert newbody.kind in {tyRef, tyPtr}
        if newbody.last.typeInst != nil:
          #internalError(cl.c.config, cl.info, "ref already has a 'typeInst' field")
          discard
        else:
          newbody.last.typeInst = result
    # DESTROY: adding object|opt for opt[topttree.Tree]
    # sigmatch: Formal opt[=destroy.T] real opt[topttree.Tree]
    # adding myseq for myseq[system.int]
    # sigmatch: Formal myseq[=destroy.T] real myseq[system.int]
    #echo "DESTROY: adding ", typeToString(newbody), " for ", typeToString(result, preferDesc)
    let mm = skipTypes(bbody, abstractPtrs)
    if tfFromGeneric notin mm.flags:
      # bug #5479, prevent endless recursions here:
      incl mm.flags, tfFromGeneric
      for col, meth in methodsForGeneric(cl.c.graph, mm):
        # we instantiate the known methods belonging to that type, this causes
        # them to be registered and that's enough, so we 'discard' the result.
        discard cl.c.instTypeBoundOp(cl.c, meth, result, cl.info,
          attachedAsgn, col)
      excl mm.flags, tfFromGeneric

proc eraseVoidParams*(t: PType) =
  # transform '(): void' into '()' because old parts of the compiler really
  # don't deal with '(): void':
  if t.returnType != nil and t.returnType.kind == tyVoid:
    t.setReturnType nil

  for i in FirstParamAt..<t.signatureLen:
    # don't touch any memory unless necessary
    if t[i].kind == tyVoid:
      var pos = i
      for j in i+1..<t.signatureLen:
        if t[j].kind != tyVoid:
          t[pos] = t[j]
          t.n[pos] = t.n[j]
          inc pos
      newSons t, pos
      setLen t.n.sons, pos
      break

proc skipIntLiteralParams*(t: PType; idgen: IdGenerator) =
  for i, p in t.ikids:
    if p == nil: continue
    let skipped = p.skipIntLit(idgen)
    if skipped != p:
      t[i] = skipped
      if i > 0: t.n[i].sym.typ = skipped

  # when the typeof operator is used on a static input
  # param, the results gets infected with static as well:
  if t.returnType != nil and t.returnType.kind == tyStatic:
    t.setReturnType t.returnType.skipModifier

proc propagateFieldFlags(t: PType, n: PNode) =
  # This is meant for objects and tuples
  # The type must be fully instantiated!
  if n.isNil:
    return
  #internalAssert n.kind != nkRecWhen
  case n.kind
  of nkSym:
    propagateToOwner(t, n.sym.typ)
  of nkRecList, nkRecCase, nkOfBranch, nkElse:
    for son in n:
      propagateFieldFlags(t, son)
  else: discard

proc replaceTypeVarsTAux(cl: var TReplTypeVars, t: PType, isInstValue = false): PType =
  template bailout =
    if (t.sym == nil) or (t.sym != nil and sfGeneratedType in t.sym.flags):
      # In the first case 't.sym' can be 'nil' if the type is a ref/ptr, see
      # issue https://github.com/nim-lang/Nim/issues/20416 for more details.
      # Fortunately for us this works for now because partial ref/ptr types are
      # not allowed in object construction, eg.
      #   type
      #     Container[T] = ...
      #     O = object
      #      val: ref Container
      #
      # In the second case only consider the recursion limit if the symbol is a
      # type with generic parameters that have not been explicitly supplied,
      # typechecking should terminate when generic parameters are explicitly
      # supplied.
      if cl.recursionLimit > 100:
        # bail out, see bug #2509. But note this caching is in general wrong,
        # look at this example where TwoVectors should not share the generic
        # instantiations (bug #3112):
        # type
        #   Vector[N: static[int]] = array[N, float64]
        #   TwoVectors[Na, Nb: static[int]] = (Vector[Na], Vector[Nb])
        result = getOrDefault(cl.localCache, t.itemId)
        if result != nil: return result
      inc cl.recursionLimit

  result = t
  if t == nil: return

  const lookupMetas = {tyStatic, tyGenericParam, tyConcept} + tyTypeClasses - {tyAnything}
  if t.kind in lookupMetas or
      (t.kind == tyAnything and tfRetType notin t.flags):
    let lookup = cl.typeMap.lookup(t)
    if lookup != nil: return lookup

  case t.kind
  of tyGenericInvocation:
    result = handleGenericInvocation(cl, t)
    if result.last.kind == tyUserTypeClass:
      result.kind = tyUserTypeClassInst

  of tyGenericBody:
    if cl.allowMetaTypes: return
    localError(
      cl.c.config,
      cl.info,
      "cannot instantiate: '" &
      typeToString(t, preferDesc) &
      "'; Maybe generic arguments are missing?")
    result = errorType(cl.c)
    #result = replaceTypeVarsT(cl, lastSon(t))

  of tyFromExpr:
    if cl.allowMetaTypes: return
    # This assert is triggered when a tyFromExpr was created in a cyclic
    # way. You should break the cycle at the point of creation by introducing
    # a call such as: `n.typ = makeTypeFromExpr(c, n.copyTree)`
    # Otherwise, the cycle will be fatal for the prepareNode call below
    assert t.n.typ != t
    var n = prepareNode(cl, t.n)
    if n.kind != nkEmpty:
      if tfNonConstExpr in t.flags:
        n = cl.c.semExprWithType(cl.c, n, flags = {efInTypeof})
      else:
        n = cl.c.semConstExpr(cl.c, n)
    if n.typ.kind == tyTypeDesc:
      # XXX: sometimes, chained typedescs enter here.
      # It may be worth investigating why this is happening,
      # because it may cause other bugs elsewhere.
      result = n.typ.skipTypes({tyTypeDesc})
      # result = n.typ.base
    elif tfNonConstExpr in t.flags:
      result = n.typ
    else:
      if n.typ.kind != tyStatic and n.kind != nkType:
        # XXX: In the future, semConstExpr should
        # return tyStatic values to let anyone make
        # use of this knowledge. The patching here
        # won't be necessary then.
        result = newTypeS(tyStatic, cl.c, son = n.typ)
        result.n = n
      else:
        result = n.typ

  of tyInt, tyFloat:
    result = skipIntLit(t, cl.c.idgen)

  of tyTypeDesc:
    let lookup = cl.typeMap.lookup(t)
    if lookup != nil:
      result = lookup
      if result.kind != tyTypeDesc:
        result = makeTypeDesc(cl.c, result)
      elif tfUnresolved in t.flags or cl.skipTypedesc:
        result = result.base
    elif t.elementType.kind != tyNone:
      result = makeTypeDesc(cl.c, replaceTypeVarsT(cl, t.elementType))

  of tyUserTypeClass:
    result = t
  
  of tyStatic:
    if cl.c.matchedConcept != nil:
      # allow concepts to not instantiate statics for now
      # they can't always infer them
      return
    if not containsGenericType(t) and (t.n == nil or t.n.kind in nkLiterals):
      # no need to instantiate
      return
    bailout()
    result = instCopyType(cl, t)
    cl.localCache[t.itemId] = result
    for i in FirstGenericParamAt..<result.kidsLen:
      var r = result[i]
      if r != nil:
        r = replaceTypeVarsT(cl, r)
        result[i] = r
        propagateToOwner(result, r)
    result.n = replaceTypeVarsN(cl, result.n)
    if not cl.allowMetaTypes and result.n != nil and
        result.base.kind != tyNone:
      result.n = cl.c.semConstExpr(cl.c, result.n)
      result.n.typ() = result.base

  of tyGenericInst, tyUserTypeClassInst:
    bailout()
    result = instCopyType(cl, t)
    cl.localCache[t.itemId] = result
    for i in FirstGenericParamAt..<result.kidsLen:
      result[i] = replaceTypeVarsT(cl, result[i])
    propagateToOwner(result, result.last)

  else:
    if containsGenericType(t) or
        # nominal types as direct generic instantiation values
        # are re-instantiated even if they don't contain generic fields
        (isInstValue and (t.kind in {tyDistinct, tyObject} or isRefPtrObject(t))):
      #if not cl.allowMetaTypes:
      bailout()
      result = instCopyType(cl, t)
      result.size = -1 # needs to be recomputed
      #if not cl.allowMetaTypes:
      cl.localCache[t.itemId] = result
      let propagateInstValue = isInstValue and isRefPtrObject(t)

      for i, resulti in result.ikids:
        if resulti != nil:
          if resulti.kind == tyGenericBody and not cl.allowMetaTypes:
            localError(cl.c.config, if t.sym != nil: t.sym.info else: cl.info,
              "cannot instantiate '" &
              typeToString(result[i], preferDesc) &
              "' inside of type definition: '" &
              t.owner.name.s & "'; Maybe generic arguments are missing?")
          var r = replaceTypeVarsT(cl, resulti, isInstValue = propagateInstValue)
          if result.kind == tyObject:
            # carefully coded to not skip the precious tyGenericInst:
            let r2 = r.skipTypes({tyAlias, tySink, tyOwned})
            if r2.kind in {tyPtr, tyRef}:
              r = skipTypes(r2, {tyPtr, tyRef})
          result[i] = r
          if result.kind != tyArray or i != 0:
            propagateToOwner(result, r)
      # bug #4677: Do not instantiate effect lists
      result.n = replaceTypeVarsN(cl, result.n, ord(result.kind==tyProc))
      case result.kind
      of tyArray:
        let idx = result.indexType
        internalAssert cl.c.config, idx.kind != tyStatic

      of tyObject, tyTuple:
        propagateFieldFlags(result, result.n)
        if result.kind == tyObject and cl.c.computeRequiresInit(cl.c, result):
          result.flags.incl tfRequiresInit

      of tyProc:
        eraseVoidParams(result)
        skipIntLiteralParams(result, cl.c.idgen)

      of tyRange:
        result.setIndexType result.indexType.skipTypes({tyStatic, tyDistinct})

      else: discard
    else:
      # If this type doesn't refer to a generic type we may still want to run it
      # trough replaceObjBranches in order to resolve any pending nkRecWhen nodes
      result = t

      # Slow path, we have some work to do
      if t.kind == tyRef and t.hasElementType and t.elementType.kind == tyObject and t.elementType.n != nil:
        discard replaceObjBranches(cl, t.elementType.n)

      elif result.n != nil and t.kind == tyObject:
        # Invalidate the type size as we may alter its structure
        result.size = -1
        result.n = replaceObjBranches(cl, result.n)

proc initTypeVars*(p: PContext, typeMap: LayeredIdTable, info: TLineInfo;
                   owner: PSym): TReplTypeVars =
  result = TReplTypeVars(symMap: initSymMapping(),
            localCache: initTypeMapping(), typeMap: typeMap,
            info: info, c: p, owner: owner)

proc replaceTypesInBody*(p: PContext, pt: LayeredIdTable, n: PNode;
                         owner: PSym, allowMetaTypes = false,
                         fromStaticExpr = false, expectedType: PType = nil): PNode =
  var typeMap = shallowCopy(pt) # use previous bindings without writing to them
  var cl = initTypeVars(p, typeMap, n.info, owner)
  cl.allowMetaTypes = allowMetaTypes
  pushInfoContext(p.config, n.info)
  result = replaceTypeVarsN(cl, n, expectedType = expectedType)
  popInfoContext(p.config)

proc prepareTypesInBody*(p: PContext, pt: LayeredIdTable, n: PNode;
                         owner: PSym = nil): PNode =
  var typeMap = shallowCopy(pt) # use previous bindings without writing to them
  var cl = initTypeVars(p, typeMap, n.info, owner)
  pushInfoContext(p.config, n.info)
  result = prepareNode(cl, n)
  popInfoContext(p.config)

when false:
  # deadcode
  proc replaceTypesForLambda*(p: PContext, pt: TIdTable, n: PNode;
                              original, new: PSym): PNode =
    var typeMap = initLayeredTypeMap(pt)
    var cl = initTypeVars(p, typeMap, n.info, original)
    idTablePut(cl.symMap, original, new)
    pushInfoContext(p.config, n.info)
    result = replaceTypeVarsN(cl, n)
    popInfoContext(p.config)

proc recomputeFieldPositions*(t: PType; obj: PNode; currPosition: var int) =
  if t != nil and t.baseClass != nil:
    let b = skipTypes(t.baseClass, skipPtrs)
    recomputeFieldPositions(b, b.n, currPosition)
  case obj.kind
  of nkRecList:
    for i in 0..<obj.len: recomputeFieldPositions(nil, obj[i], currPosition)
  of nkRecCase:
    recomputeFieldPositions(nil, obj[0], currPosition)
    for i in 1..<obj.len:
      recomputeFieldPositions(nil, lastSon(obj[i]), currPosition)
  of nkSym:
    obj.sym.position = currPosition
    inc currPosition
  else: discard "cannot happen"

proc generateTypeInstance*(p: PContext, pt: LayeredIdTable, info: TLineInfo,
                           t: PType): PType =
  # Given `t` like Foo[T]
  # pt: Table with type mappings: T -> int
  # Desired result: Foo[int]
  # proc (x: T = 0); T -> int ---->  proc (x: int = 0)
  var typeMap = shallowCopy(pt) # use previous bindings without writing to them
  var cl = initTypeVars(p, typeMap, info, nil)
  pushInfoContext(p.config, info)
  result = replaceTypeVarsT(cl, t)
  popInfoContext(p.config)
  let objType = result.skipTypes(abstractInst)
  if objType.kind == tyObject:
    var position = 0
    recomputeFieldPositions(objType, objType.n, position)

proc prepareMetatypeForSigmatch*(p: PContext, pt: LayeredIdTable, info: TLineInfo,
                                 t: PType): PType =
  var typeMap = shallowCopy(pt) # use previous bindings without writing to them
  var cl = initTypeVars(p, typeMap, info, nil)
  cl.allowMetaTypes = true
  pushInfoContext(p.config, info)
  result = replaceTypeVarsT(cl, t)
  popInfoContext(p.config)

template generateTypeInstance*(p: PContext, pt: LayeredIdTable, arg: PNode,
                               t: PType): untyped =
  generateTypeInstance(p, pt, arg.info, t)

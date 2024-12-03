#
#
#           The Nim Compiler
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# This module implements the instantiation of generic procs.
# included from sem.nim

proc addObjFieldsToLocalScope(c: PContext; n: PNode) =
  template rec(n) = addObjFieldsToLocalScope(c, n)
  case n.kind
  of nkRecList:
    for i in 0..<n.len:
      rec n[i]
  of nkRecCase:
    if n.len > 0: rec n[0]
    for i in 1..<n.len:
      if n[i].kind in {nkOfBranch, nkElse}: rec lastSon(n[i])
  of nkSym:
    let f = n.sym
    if f.kind == skField and fieldVisible(c, f):
      c.currentScope.symbols.strTableIncl(f, onConflictKeepOld=true)
      incl(f.flags, sfUsed)
      # it is not an error to shadow fields via parameters
  else: discard

proc pushProcCon*(c: PContext; owner: PSym) =
  c.p = PProcCon(owner: owner, next: c.p)

const
  errCannotInstantiateX = "cannot instantiate: '$1'"

iterator instantiateGenericParamList(c: PContext, n: PNode, pt: LayeredIdTable): PSym =
  internalAssert c.config, n.kind == nkGenericParams
  for a in n.items:
    internalAssert c.config, a.kind == nkSym
    var q = a.sym
    if q.typ.kind in {tyTypeDesc, tyGenericParam, tyStatic, tyConcept}+tyTypeClasses:
      let symKind = if q.typ.kind == tyStatic: skConst else: skType
      var s = newSym(symKind, q.name, c.idgen, getCurrOwner(c), q.info)
      s.flags.incl {sfUsed, sfFromGeneric}
      var t = lookup(pt, q.typ)
      if t == nil:
        if tfRetType in q.typ.flags:
          # keep the generic type and allow the return type to be bound
          # later by semAsgn in return type inference scenario
          t = q.typ
        else:
          if q.typ.kind != tyCompositeTypeClass:
            localError(c.config, a.info, errCannotInstantiateX % s.name.s)
          t = errorType(c)
      elif t.kind in {tyGenericParam, tyConcept, tyFromExpr} or
          # generic body types are accepted as typedesc arguments
          (t.kind == tyGenericBody and q.typ.kind != tyTypeDesc):
        localError(c.config, a.info, errCannotInstantiateX % q.name.s)
        t = errorType(c)
      elif isUnresolvedStatic(t) and (q.typ.kind == tyStatic or
            (q.typ.kind == tyGenericParam and
              q.typ.genericParamHasConstraints and
              q.typ.genericConstraint.kind == tyStatic)) and
          c.inGenericContext == 0 and c.matchedConcept == nil:
        # generic/concept type bodies will try to instantiate static values but
        # won't actually use them
        localError(c.config, a.info, errCannotInstantiateX % q.name.s)
        t = errorType(c)
      elif t.kind == tyGenericInvocation:
        #t = instGenericContainer(c, a, t)
        t = generateTypeInstance(c, pt, a, t)
        #t = ReplaceTypeVarsT(cl, t)
      s.typ = t
      if t.kind == tyStatic: s.ast = t.n
      yield s

proc sameInstantiation(a, b: TInstantiation): bool =
  if a.concreteTypes.len == b.concreteTypes.len:
    for i in 0..a.concreteTypes.high:
      if not compareTypes(a.concreteTypes[i], b.concreteTypes[i],
                          flags = {ExactTypeDescValues,
                                   ExactGcSafety,
                                   PickyCAliases}): return
    result = true
  else:
    result = false

proc genericCacheGet(g: ModuleGraph; genericSym: PSym, entry: TInstantiation;
                     id: CompilesId): PSym =
  result = nil
  for inst in procInstCacheItems(g, genericSym):
    if (inst.compilesId == 0 or inst.compilesId == id) and sameInstantiation(entry, inst[]):
      return inst.sym

when false:
  proc `$`(x: PSym): string =
    result = x.name.s & " " & " id " & $x.id

proc freshGenSyms(c: PContext; n: PNode, owner, orig: PSym, symMap: var SymMapping) =
  # we need to create a fresh set of gensym'ed symbols:
  #if n.kind == nkSym and sfGenSym in n.sym.flags:
  #  if n.sym.owner != orig:
  #    echo "symbol ", n.sym.name.s, " orig ", orig, " owner ", n.sym.owner
  if n.kind == nkSym and sfGenSym in n.sym.flags: # and
    #  (n.sym.owner == orig or n.sym.owner.kind in {skPackage}):
    let s = n.sym
    var x = idTableGet(symMap, s)
    if x != nil:
      n.sym = x
    elif s.owner == nil or s.owner.kind == skPackage:
      #echo "copied this ", s.name.s
      x = copySym(s, c.idgen)
      setOwner(x, owner)
      idTablePut(symMap, s, x)
      n.sym = x
  else:
    for i in 0..<n.safeLen: freshGenSyms(c, n[i], owner, orig, symMap)

proc addParamOrResult(c: PContext, param: PSym, kind: TSymKind)

proc instantiateBody(c: PContext, n, params: PNode, result, orig: PSym) =
  if n[bodyPos].kind != nkEmpty:
    let procParams = result.typ.n
    for i in 1..<procParams.len:
      addDecl(c, procParams[i].sym)
    maybeAddResult(c, result, result.ast)

    inc c.inGenericInst
    # add it here, so that recursive generic procs are possible:
    var b = n[bodyPos]
    var symMap = initSymMapping()
    if params != nil:
      for i in 1..<params.len:
        let param = params[i].sym
        if sfGenSym in param.flags:
          idTablePut(symMap, params[i].sym, result.typ.n[param.position+1].sym)
    freshGenSyms(c, b, result, orig, symMap)

    if sfBorrow notin orig.flags:
      # We do not want to generate a body for generic borrowed procs.
      # As body is a sym to the borrowed proc.
      let resultType = # todo probably refactor it into a function
        if result.kind == skMacro:
          sysTypeFromName(c.graph, n.info, "NimNode")
        elif not isInlineIterator(result.typ):
          result.typ.returnType
        else:
          nil
      b = semProcBody(c, b, resultType)
    result.ast[bodyPos] = hloBody(c, b)
    excl(result.flags, sfForward)
    trackProc(c, result, result.ast[bodyPos])
    dec c.inGenericInst

proc fixupInstantiatedSymbols(c: PContext, s: PSym) =
  for i in 0..<c.generics.len:
    if c.generics[i].genericSym.id == s.id:
      var oldPrc = c.generics[i].inst.sym
      pushProcCon(c, oldPrc)
      pushOwner(c, oldPrc)
      pushInfoContext(c.config, oldPrc.info)
      openScope(c)
      var n = oldPrc.ast
      n[bodyPos] = copyTree(getBody(c.graph, s))
      instantiateBody(c, n, oldPrc.typ.n, oldPrc, s)
      closeScope(c)
      popInfoContext(c.config)
      popOwner(c)
      popProcCon(c)

proc sideEffectsCheck(c: PContext, s: PSym) =
  when false:
    if {sfNoSideEffect, sfSideEffect} * s.flags ==
        {sfNoSideEffect, sfSideEffect}:
      localError(s.info, errXhasSideEffects, s.name.s)

proc instGenericContainer(c: PContext, info: TLineInfo, header: PType,
                          allowMetaTypes = false): PType =
  internalAssert c.config, header.kind == tyGenericInvocation

  var cl: TReplTypeVars = TReplTypeVars(symMap: initSymMapping(),
        localCache: initTypeMapping(), typeMap: LayeredIdTable(),
        info: info, c: c, allowMetaTypes: allowMetaTypes
      )

  cl.typeMap.topLayer = initTypeMapping()

  # We must add all generic params in scope, because the generic body
  # may include tyFromExpr nodes depending on these generic params.
  # XXX: This looks quite similar to the code in matchUserTypeClass,
  # perhaps the code can be extracted in a shared function.
  openScope(c)
  let genericTyp = header.base
  for i, genParam in genericBodyParams(genericTyp):
    var param: PSym

    template paramSym(kind): untyped =
      newSym(kind, genParam.sym.name, c.idgen, genericTyp.sym, genParam.sym.info)

    if genParam.kind == tyStatic:
      param = paramSym skConst
      param.ast = header[i+1].n
      param.typ = header[i+1]
    else:
      param = paramSym skType
      param.typ = makeTypeDesc(c, header[i+1])

    # this scope was not created by the user,
    # unused params shouldn't be reported.
    param.flags.incl sfUsed
    addDecl(c, param)

  result = replaceTypeVarsT(cl, header)
  closeScope(c)

proc referencesAnotherParam(n: PNode, p: PSym): bool =
  if n.kind == nkSym:
    return n.sym.kind == skParam and n.sym.owner == p
  else:
    for i in 0..<n.safeLen:
      if referencesAnotherParam(n[i], p): return true
    return false

proc instantiateProcType(c: PContext, pt: LayeredIdTable,
                         prc: PSym, info: TLineInfo) =
  # XXX: Instantiates a generic proc signature, while at the same
  # time adding the instantiated proc params into the current scope.
  # This is necessary, because the instantiation process may refer to
  # these params in situations like this:
  # proc foo[Container](a: Container, b: a.type.Item): typeof(b.x)
  #
  # Alas, doing this here is probably not enough, because another
  # proc signature could appear in the params:
  # proc foo[T](a: proc (x: T, b: typeof(x.y))
  #
  # The solution would be to move this logic into semtypinst, but
  # at this point semtypinst have to become part of sem, because it
  # will need to use openScope, addDecl, etc.
  #addDecl(c, prc)
  pushInfoContext(c.config, info)
  var typeMap = shallowCopy(pt) # use previous bindings without writing to them
  var cl = initTypeVars(c, typeMap, info, nil)
  var result = instCopyType(cl, prc.typ)
  let originalParams = result.n
  result.n = originalParams.shallowCopy
  for i, resulti in paramTypes(result):
    # twrong_field_caching requires these 'resetIdTable' calls:
    if i > FirstParamAt:
      resetIdTable(cl.symMap)
      resetIdTable(cl.localCache)

    # take a note of the original type. If't a free type or static parameter
    # we'll need to keep it unbound for the `fitNode` operation below...
    var typeToFit = resulti

    let needsStaticSkipping = resulti.kind == tyFromExpr
    let needsTypeDescSkipping = resulti.kind == tyTypeDesc and tfUnresolved in resulti.flags
    if resulti.kind == tyFromExpr:
      resulti.flags.incl tfNonConstExpr
    result[i] = replaceTypeVarsT(cl, resulti)
    if needsStaticSkipping:
      result[i] = result[i].skipTypes({tyStatic})
    if needsTypeDescSkipping:
      result[i] = result[i].skipTypes({tyTypeDesc})
      typeToFit = result[i]

    # ...otherwise, we use the instantiated type in `fitNode`
    if (typeToFit.kind != tyTypeDesc or typeToFit.base.kind != tyNone) and
       (typeToFit.kind != tyStatic):
      typeToFit = result[i]

    internalAssert c.config, originalParams[i].kind == nkSym
    let oldParam = originalParams[i].sym
    let param = copySym(oldParam, c.idgen)
    setOwner(param, prc)
    param.typ = result[i]

    # The default value is instantiated and fitted against the final
    # concrete param type. We avoid calling `replaceTypeVarsN` on the
    # call head symbol, because this leads to infinite recursion.
    if oldParam.ast != nil:
      var def = oldParam.ast.copyTree
      if def.typ.kind == tyFromExpr:
        def.typ.flags.incl tfNonConstExpr
      if not isIntLit(def.typ):
        def = prepareNode(cl, def)

      # allow symchoice since node will be fit later
      # although expectedType should cover it
      def = semExprWithType(c, def, {efAllowSymChoice}, typeToFit)
      if def.referencesAnotherParam(getCurrOwner(c)):
        def.flags.incl nfDefaultRefsParam

      var converted = indexTypesMatch(c, typeToFit, def.typ, def)
      if converted == nil:
        # The default value doesn't match the final instantiated type.
        # As an example of this, see:
        # https://github.com/nim-lang/Nim/issues/1201
        # We are replacing the default value with an error node in case
        # the user calls an explicit instantiation of the proc (this is
        # the only way the default value might be inserted).
        param.ast = errorNode(c, def)
        # we know the node is empty, we need the actual type for error message
        param.ast.typ() = def.typ
      else:
        param.ast = fitNodePostMatch(c, typeToFit, converted)
      param.typ = result[i]

    result.n[i] = newSymNode(param)
    propagateToOwner(result, result[i])
    addDecl(c, param)

  resetIdTable(cl.symMap)
  resetIdTable(cl.localCache)
  cl.isReturnType = true
  result.setReturnType replaceTypeVarsT(cl, result.returnType)
  cl.isReturnType = false
  result.n[0] = originalParams[0].copyTree
  if result[0] != nil:
    propagateToOwner(result, result[0])

  eraseVoidParams(result)
  skipIntLiteralParams(result, c.idgen)

  prc.typ = result
  popInfoContext(c.config)

proc instantiateOnlyProcType(c: PContext, pt: LayeredIdTable, prc: PSym, info: TLineInfo): PType =
  # instantiates only the type of a given proc symbol
  # used by sigmatch for explicit generics
  # wouldn't be needed if sigmatch could handle complex cases,
  # examples are in texplicitgenerics
  # might be buggy, see rest of generateInstance if problems occur
  let fakeSym = copySym(prc, c.idgen)
  incl(fakeSym.flags, sfFromGeneric)
  fakeSym.instantiatedFrom = prc
  openScope(c)
  for s in instantiateGenericParamList(c, prc.ast[genericParamsPos], pt):
    addDecl(c, s)
  instantiateProcType(c, pt, fakeSym, info)
  closeScope(c)
  result = fakeSym.typ

proc fillMixinScope(c: PContext) =
  var p = c.p
  while p != nil:
    for bnd in p.localBindStmts:
      for n in bnd:
        addSym(c.currentScope, n.sym)
    p = p.next

proc getLocalPassC(c: PContext, s: PSym): string =
  when defined(nimsuggest): return ""
  if s.ast == nil or s.ast.len == 0: return ""
  result = ""
  template extractPassc(p: PNode) =
    if p.kind == nkPragma and p[0][0].ident == c.cache.getIdent"localpassc":
      return p[0][1].strVal
  extractPassc(s.ast[0]) #it is set via appendToModule in pragmas (fast access)
  for n in s.ast:
    for p in n:
      extractPassc(p)

proc generateInstance(c: PContext, fn: PSym, pt: LayeredIdTable,
                      info: TLineInfo): PSym =
  ## Generates a new instance of a generic procedure.
  ## The `pt` parameter is a type-unsafe mapping table used to link generic
  ## parameters to their concrete types within the generic instance.
  # no need to instantiate generic templates/macros:
  internalAssert c.config, fn.kind notin {skMacro, skTemplate}
  # generates an instantiated proc
  if c.instCounter > 50:
    globalError(c.config, info, "generic instantiation too nested")
  inc c.instCounter
  let currentTypeofContext = c.inTypeofContext
  c.inTypeofContext = 0
  defer:
    dec c.instCounter
    c.inTypeofContext = currentTypeofContext
  # careful! we copy the whole AST including the possibly nil body!
  var n = copyTree(fn.ast)
  # NOTE: for access of private fields within generics from a different module
  # we set the friend module:
  let producer = getModule(fn)
  c.friendModules.add(producer)
  let oldMatchedConcept = c.matchedConcept
  c.matchedConcept = nil
  let oldScope = c.currentScope
  while not isTopLevel(c): c.currentScope = c.currentScope.parent
  result = copySym(fn, c.idgen)
  incl(result.flags, sfFromGeneric)
  result.instantiatedFrom = fn
  if sfGlobal in result.flags and c.config.symbolFiles != disabledSf:
    let passc = getLocalPassC(c, producer)
    if passc != "": #pass the local compiler options to the consumer module too
      extccomp.addLocalCompileOption(c.config, passc, toFullPathConsiderDirty(c.config, c.module.info.fileIndex))
    setOwner(result, c.module)
  else:
    setOwner(result, fn)
  result.ast = n
  pushOwner(c, result)

  # mixin scope:
  openScope(c)
  fillMixinScope(c)

  openScope(c)
  let gp = n[genericParamsPos]
  if gp.kind != nkGenericParams:
    # bug #22137
    globalError(c.config, info, "generic instantiation too nested")
  n[namePos] = newSymNode(result)
  pushInfoContext(c.config, info, fn.detailedInfo)
  var entry = TInstantiation.new
  entry.sym = result
  # we need to compare both the generic types and the concrete types:
  # generic[void](), generic[int]()
  # see ttypeor.nim test.
  var i = 0
  newSeq(entry.concreteTypes, fn.typ.paramsLen+gp.len)
  # let param instantiation know we are in a concept for unresolved statics:
  c.matchedConcept = oldMatchedConcept
  for s in instantiateGenericParamList(c, gp, pt):
    addDecl(c, s)
    entry.concreteTypes[i] = s.typ
    inc i
  c.matchedConcept = nil
  pushProcCon(c, result)
  instantiateProcType(c, pt, result, info)
  for _, param in paramTypes(result.typ):
    entry.concreteTypes[i] = param
    inc i
  #echo "INSTAN ", fn.name.s, " ", typeToString(result.typ), " ", entry.concreteTypes.len
  if tfTriggersCompileTime in result.typ.flags:
    incl(result.flags, sfCompileTime)
  n[genericParamsPos] = c.graph.emptyNode
  var oldPrc = genericCacheGet(c.graph, fn, entry[], c.compilesContextId)
  if oldPrc == nil:
    # we MUST not add potentially wrong instantiations to the caching mechanism.
    # This means recursive instantiations behave differently when in
    # a ``compiles`` context but this is the lesser evil. See
    # bug #1055 (tevilcompiles).
    #if c.compilesContextId == 0:
    entry.compilesId = c.compilesContextId
    addToGenericProcCache(c, fn, entry)
    c.generics.add(makeInstPair(fn, entry))
    # bug #12985 bug #22913
    # TODO: use the context of the declaration of generic functions instead
    # TODO: consider fixing options as well
    let otherPragmas = c.optionStack[^1].otherPragmas
    c.optionStack[^1].otherPragmas = nil
    if n[pragmasPos].kind != nkEmpty:
      pragma(c, result, n[pragmasPos], allRoutinePragmas)
    if isNil(n[bodyPos]):
      n[bodyPos] = copyTree(getBody(c.graph, fn))
    instantiateBody(c, n, fn.typ.n, result, fn)
    c.optionStack[^1].otherPragmas = otherPragmas
    sideEffectsCheck(c, result)
    if result.magic notin {mSlice, mTypeOf}:
      # 'toOpenArray' is special and it is allowed to return 'openArray':
      paramsTypeCheck(c, result.typ)
    #echo "INSTAN ", fn.name.s, " ", typeToString(result.typ), " <-- NEW PROC!", " ", entry.concreteTypes.len
  else:
    #echo "INSTAN ", fn.name.s, " ", typeToString(result.typ), " <-- CACHED! ", typeToString(oldPrc.typ), " ", entry.concreteTypes.len
    result = oldPrc
  popProcCon(c)
  popInfoContext(c.config)
  closeScope(c)           # close scope for parameters
  closeScope(c)           # close scope for 'mixin' declarations
  popOwner(c)
  c.currentScope = oldScope
  discard c.friendModules.pop()
  c.matchedConcept = oldMatchedConcept
  if result.kind == skMethod: finishMethod(c, result)

  # inform IC of the generic
  #addGeneric(c.ic, result, entry.concreteTypes)

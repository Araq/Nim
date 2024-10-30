#
#
#           The Nim Compiler
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# this module does the semantic checking of type declarations
# included from sem.nim

const
  errStringOrIdentNodeExpected = "string or ident node expected"
  errStringLiteralExpected = "string literal expected"
  errIntLiteralExpected = "integer literal expected"
  errWrongNumberOfVariables = "wrong number of variables"
  errDuplicateAliasInEnumX = "duplicate value in enum '$1'"
  errOverflowInEnumX = "The enum '$1' exceeds its maximum value ($2)"
  errOrdinalTypeExpected = "ordinal type expected; given: $1"
  errSetTooBig = "set is too large; use `std/sets` for ordinal types with more than 2^16 elements"
  errBaseTypeMustBeOrdinal = "base type of a set must be an ordinal"
  errInheritanceOnlyWithNonFinalObjects = "inheritance only works with non-final objects"
  errXExpectsOneTypeParam = "'$1' expects one type parameter"
  errArrayExpectsTwoTypeParams = "array expects two type parameters"
  errInvalidVisibilityX = "invalid visibility: '$1'"
  errXCannotBeAssignedTo = "'$1' cannot be assigned to"
  errIteratorNotAllowed = "iterators can only be defined at the module's top level"
  errXNeedsReturnType = "$1 needs a return type"
  errNoReturnTypeDeclared = "no return type declared"
  errTIsNotAConcreteType = "'$1' is not a concrete type"
  errTypeExpected = "type expected"
  errXOnlyAtModuleScope = "'$1' is only allowed at top level"
  errDuplicateCaseLabel = "duplicate case label"
  errMacroBodyDependsOnGenericTypes = "the macro body cannot be compiled, " &
    "because the parameter '$1' has a generic type"
  errIllegalRecursionInTypeX = "illegal recursion in type '$1'"
  errNoGenericParamsAllowedForX = "no generic parameters allowed for $1"
  errInOutFlagNotExtern = "the '$1' modifier can be used only with imported types"

proc newOrPrevType(kind: TTypeKind, prev: PType, c: PContext, son: sink PType): PType =
  if prev == nil or prev.kind == tyGenericBody:
    result = newTypeS(kind, c, son)
  else:
    result = prev
    result.setSon(son)
    if result.kind == tyForward: result.kind = kind
  #if kind == tyError: result.flags.incl tfCheckedForDestructor

proc newOrPrevType(kind: TTypeKind, prev: PType, c: PContext): PType =
  if prev == nil or prev.kind == tyGenericBody:
    result = newTypeS(kind, c)
  else:
    result = prev
    if result.kind == tyForward: result.kind = kind

proc newConstraint(c: PContext, k: TTypeKind): PType =
  result = newTypeS(tyBuiltInTypeClass, c)
  result.flags.incl tfCheckedForDestructor
  result.addSonSkipIntLit(newTypeS(k, c), c.idgen)

proc semEnum(c: PContext, n: PNode, prev: PType): PType =
  if n.len == 0: return newConstraint(c, tyEnum)
  elif n.len == 1:
    # don't create an empty tyEnum; fixes #3052
    return errorType(c)
  var
    counter, x: BiggestInt = 0
    e: PSym = nil
    base: PType = nil
    identToReplace: ptr PNode = nil
    counterSet = initPackedSet[BiggestInt]()
  counter = 0
  base = nil
  result = newOrPrevType(tyEnum, prev, c)
  result.n = newNodeI(nkEnumTy, n.info)
  checkMinSonsLen(n, 1, c.config)
  if n[0].kind != nkEmpty:
    base = semTypeNode(c, n[0][0], nil)
    if base.kind != tyEnum:
      localError(c.config, n[0].info, "inheritance only works with an enum")
    counter = toInt64(lastOrd(c.config, base)) + 1
  rawAddSon(result, base)
  let isPure = result.sym != nil and sfPure in result.sym.flags
  var symbols: TStrTable = initStrTable()
  var hasNull = false
  var needsReorder = false
  for i in 1..<n.len:
    if n[i].kind == nkEmpty: continue
    var useAutoCounter = false
    case n[i].kind
    of nkEnumFieldDef:
      if n[i][0].kind == nkPragmaExpr:
        e = newSymS(skEnumField, n[i][0][0], c)
        identToReplace = addr n[i][0][0]
        pragma(c, e, n[i][0][1], enumFieldPragmas)
      else:
        e = newSymS(skEnumField, n[i][0], c)
        identToReplace = addr n[i][0]
      var v = semConstExpr(c, n[i][1])
      var strVal: PNode = nil
      case skipTypes(v.typ, abstractInst-{tyTypeDesc}).kind
      of tyTuple:
        if v.len == 2:
          strVal = v[1] # second tuple part is the string value
          if skipTypes(strVal.typ, abstractInst).kind in {tyString, tyCstring}:
            if not isOrdinalType(v[0].typ, allowEnumWithHoles=true):
              localError(c.config, v[0].info, errOrdinalTypeExpected % typeToString(v[0].typ, preferDesc))
            x = toInt64(getOrdValue(v[0])) # first tuple part is the ordinal
            n[i][1][0] = newIntTypeNode(x, getSysType(c.graph, unknownLineInfo, tyInt))
          else:
            localError(c.config, strVal.info, errStringLiteralExpected)
        else:
          localError(c.config, v.info, errWrongNumberOfVariables)
      of tyString, tyCstring:
        strVal = v
        x = counter
        useAutoCounter = true
      else:
        if isOrdinalType(v.typ, allowEnumWithHoles=true):
          x = toInt64(getOrdValue(v))
          n[i][1] = newIntTypeNode(x, getSysType(c.graph, unknownLineInfo, tyInt))
        else:
          localError(c.config, v.info, errOrdinalTypeExpected % typeToString(v.typ, preferDesc))
      if i != 1:
        if x != counter:
          needsReorder = true
          incl(result.flags, tfEnumHasHoles)
      e.ast = strVal # might be nil
      counter = x
    of nkSym:
      e = n[i].sym
      useAutoCounter = true
    of nkIdent, nkAccQuoted:
      e = newSymS(skEnumField, n[i], c)
      identToReplace = addr n[i]
      useAutoCounter = true
    of nkPragmaExpr:
      e = newSymS(skEnumField, n[i][0], c)
      pragma(c, e, n[i][1], enumFieldPragmas)
      identToReplace = addr n[i][0]
      useAutoCounter = true
    else:
      illFormedAst(n[i], c.config)

    if useAutoCounter:
      while counter in counterSet and counter != high(typeof(counter)):
        inc counter
      counterSet.incl counter
    elif counterSet.containsOrIncl(counter):
      localError(c.config, n[i].info, errDuplicateAliasInEnumX % e.name.s)

    e.typ = result
    e.position = int(counter)
    let symNode = newSymNode(e)
    if identToReplace != nil and c.config.cmd notin cmdDocLike:
      # A hack to produce documentation for enum fields.
      identToReplace[] = symNode
    if e.position == 0: hasNull = true
    if result.sym != nil and sfExported in result.sym.flags:
      e.flags.incl {sfUsed, sfExported}

    result.n.add symNode
    styleCheckDef(c, e)
    onDef(e.info, e)
    suggestSym(c.graph, e.info, e, c.graph.usageSym)
    if sfGenSym notin e.flags:
      if not isPure:
        addInterfaceOverloadableSymAt(c, c.currentScope, e)
      else:
        declarePureEnumField(c, e)
    if (let conflict = strTableInclReportConflict(symbols, e); conflict != nil):
      wrongRedefinition(c, e.info, e.name.s, conflict.info)
    if counter == high(typeof(counter)):
      if i > 1 and result.n[i-2].sym.position == high(int):
        localError(c.config, n[i].info, errOverflowInEnumX % [e.name.s, $high(typeof(counter))])
    else:
      inc(counter)

  if needsReorder:
    result.n.sons.sort(
      proc (x, y: PNode): int =
        result = cmp(x.sym.position, y.sym.position)
    )

  if isPure and sfExported in result.sym.flags:
    addPureEnum(c, LazySym(sym: result.sym))
  if tfNotNil in e.typ.flags and not hasNull:
    result.flags.incl tfRequiresInit
  setToStringProc(c.graph, result, genEnumToStrProc(result, n.info, c.graph, c.idgen))

proc semSet(c: PContext, n: PNode, prev: PType): PType =
  result = newOrPrevType(tySet, prev, c)
  if n.len == 2 and n[1].kind != nkEmpty:
    var base = semTypeNode(c, n[1], nil)
    addSonSkipIntLit(result, base, c.idgen)
    if base.kind in {tyGenericInst, tyAlias, tySink}: base = skipModifier(base)
    if base.kind notin {tyGenericParam, tyGenericInvocation}:
      if base.kind == tyForward:
        c.skipTypes.add n
      elif not isOrdinalType(base, allowEnumWithHoles = true):
        localError(c.config, n.info, errOrdinalTypeExpected % typeToString(base, preferDesc))
      elif lengthOrd(c.config, base) > MaxSetElements:
        localError(c.config, n.info, errSetTooBig)
  else:
    localError(c.config, n.info, errXExpectsOneTypeParam % "set")
    addSonSkipIntLit(result, errorType(c), c.idgen)

proc semContainerArg(c: PContext; n: PNode, kindStr: string; result: PType) =
  if n.len == 2:
    var base = semTypeNode(c, n[1], nil)
    if base.kind == tyVoid:
      localError(c.config, n.info, errTIsNotAConcreteType % typeToString(base))
    addSonSkipIntLit(result, base, c.idgen)
  else:
    localError(c.config, n.info, errXExpectsOneTypeParam % kindStr)
    addSonSkipIntLit(result, errorType(c), c.idgen)

proc semContainer(c: PContext, n: PNode, kind: TTypeKind, kindStr: string,
                  prev: PType): PType =
  result = newOrPrevType(kind, prev, c)
  semContainerArg(c, n, kindStr, result)

proc semVarargs(c: PContext, n: PNode, prev: PType): PType =
  result = newOrPrevType(tyVarargs, prev, c)
  if n.len == 2 or n.len == 3:
    var base = semTypeNode(c, n[1], nil)
    addSonSkipIntLit(result, base, c.idgen)
    if n.len == 3:
      result.n = newIdentNode(considerQuotedIdent(c, n[2]), n[2].info)
  else:
    localError(c.config, n.info, errXExpectsOneTypeParam % "varargs")
    addSonSkipIntLit(result, errorType(c), c.idgen)

proc semVarOutType(c: PContext, n: PNode, prev: PType; flags: TTypeFlags): PType =
  if n.len == 1:
    result = newOrPrevType(tyVar, prev, c)
    result.flags = flags
    var base = semTypeNode(c, n[0], nil)
    if base.kind == tyTypeDesc and not isSelf(base):
      base = base[0]
    if base.kind == tyVar:
      localError(c.config, n.info, "type 'var var' is not allowed")
      base = base[0]
    addSonSkipIntLit(result, base, c.idgen)
  else:
    result = newConstraint(c, tyVar)

proc isRecursiveType(t: PType, cycleDetector: var IntSet): bool =
  if t == nil:
    return false
  if cycleDetector.containsOrIncl(t.id):
    return true
  case t.kind
  of tyAlias, tyGenericInst, tyDistinct:
    return isRecursiveType(t.skipModifier, cycleDetector)
  else:
    return false

proc annotateClosureConv(n: PNode) =
  case n.kind
  of {nkNone..nkNilLit}:
    discard
  of nkTupleConstr:
    if n.typ.kind == tyProc and n.typ.callConv == ccClosure and
        n[0].typ.kind == tyProc and n[0].typ.callConv != ccClosure:
      # restores `transf.generateThunk`
      n[0] = newTreeIT(nkHiddenSubConv, n[0].info, n.typ,
                       newNodeI(nkEmpty, n[0].info), n[0])
      n.transitionSonsKind(nkClosure)
      n.flags.incl nfTransf
  else:
    for i in 0..<n.len:
      annotateClosureConv(n[i])

proc fitDefaultNode(c: PContext, n: PNode): PType =
  inc c.inStaticContext
  let expectedType = if n[^2].kind != nkEmpty: semTypeNode(c, n[^2], nil) else: nil
  n[^1] = semConstExpr(c, n[^1], expectedType = expectedType)
  let oldType = n[^1].typ
  n[^1].flags.incl nfSem
  if n[^2].kind != nkEmpty:
    if expectedType != nil and oldType != expectedType:
      n[^1] = fitNodeConsiderViewType(c, expectedType, n[^1], n[^1].info)
      changeType(c, n[^1], expectedType, true) # infer types for default fields value
        # bug #22926; be cautious that it uses `semConstExpr` to
        # evaulate the default fields; it's only natural to use
        # `changeType` to infer types for constant values
        # that's also the reason why we don't use `semExpr` to check
        # the type since two overlapping error messages might be produced
    annotateClosureConv(n)
    result = n[^1].typ
  else:
    result = n[^1].typ
  # xxx any troubles related to defaults fields, consult `semConst` for a potential answer
  if n[^1].kind != nkNilLit:
    typeAllowedCheck(c, n.info, result, skConst, {taProcContextIsNotMacro, taIsDefaultField})
  dec c.inStaticContext

proc isRecursiveType*(t: PType): bool =
  # handle simple recusive types before typeFinalPass
  var cycleDetector = initIntSet()
  isRecursiveType(t, cycleDetector)

proc addSonSkipIntLitChecked(c: PContext; father, son: PType; it: PNode, id: IdGenerator) =
  let s = son.skipIntLit(id)
  father.add(s)
  if isRecursiveType(s):
    localError(c.config, it.info, "illegal recursion in type '" & typeToString(s) & "'")
  else:
    propagateToOwner(father, s)

proc semDistinct(c: PContext, n: PNode, prev: PType): PType =
  if n.len == 0: return newConstraint(c, tyDistinct)
  result = newOrPrevType(tyDistinct, prev, c)
  addSonSkipIntLitChecked(c, result, semTypeNode(c, n[0], nil), n[0], c.idgen)
  if n.len > 1: result.n = n[1]

proc semRangeAux(c: PContext, n: PNode, prev: PType): PType =
  assert isRange(n)
  checkSonsLen(n, 3, c.config)
  result = newOrPrevType(tyRange, prev, c)
  result.n = newNodeI(nkRange, n.info)
  # always create a 'valid' range type, but overwrite it later
  # because 'semExprWithType' can raise an exception. See bug #6895.
  addSonSkipIntLit(result, errorType(c), c.idgen)

  if (n[1].kind == nkEmpty) or (n[2].kind == nkEmpty):
    localError(c.config, n.info, "range is empty")

  var range: array[2, PNode]
  # XXX this is still a hard compilation in a generic context, this can
  # result in unresolved generic parameters being treated like real types
  range[0] = semExprWithType(c, n[1], {efDetermineType})
  range[1] = semExprWithType(c, n[2], {efDetermineType})

  var rangeT: array[2, PType] = default(array[2, PType])
  for i in 0..1:
    rangeT[i] = range[i].typ.skipTypes({tyStatic}).skipIntLit(c.idgen)

  let hasUnknownTypes = c.inGenericContext > 0 and
    (rangeT[0].kind == tyFromExpr or rangeT[1].kind == tyFromExpr)

  if not hasUnknownTypes:
    if not sameType(rangeT[0].skipTypes({tyRange}), rangeT[1].skipTypes({tyRange})):
      typeMismatch(c.config, n.info, rangeT[0], rangeT[1], n)

    elif not isOrdinalType(rangeT[0]) and rangeT[0].kind notin {tyFloat..tyFloat128} or
        rangeT[0].kind == tyBool:
      localError(c.config, n.info, "ordinal or float type expected, but got " & typeToString(rangeT[0]))
    elif enumHasHoles(rangeT[0]):
      localError(c.config, n.info, "enum '$1' has holes" % typeToString(rangeT[0]))

  for i in 0..1:
    if hasUnresolvedArgs(c, range[i]):
      result.n.add makeStaticExpr(c, range[i])
      result.flags.incl tfUnresolved
    else:
      result.n.add semConstExpr(c, range[i])

    if result.n[i].kind in {nkFloatLit..nkFloat64Lit} and result.n[i].floatVal.isNaN:
      localError(c.config, n.info, "NaN is not a valid range " & (if i == 0: "start" else: "end"))

  if weakLeValue(result.n[0], result.n[1]) == impNo:
    localError(c.config, n.info, "range is empty")

  result[0] = rangeT[0]

proc semRange(c: PContext, n: PNode, prev: PType): PType =
  result = nil
  if n.len == 2:
    if isRange(n[1]):
      result = semRangeAux(c, n[1], prev)
      if not isDefined(c.config, "nimPreviewRangeDefault"):
        let n = result.n
        if n[0].kind in {nkCharLit..nkUInt64Lit} and n[0].intVal > 0:
          incl(result.flags, tfRequiresInit)
        elif n[1].kind in {nkCharLit..nkUInt64Lit} and n[1].intVal < 0:
          incl(result.flags, tfRequiresInit)
        elif n[0].kind in {nkFloatLit..nkFloat64Lit} and
            n[0].floatVal > 0.0:
          incl(result.flags, tfRequiresInit)
        elif n[1].kind in {nkFloatLit..nkFloat64Lit} and
            n[1].floatVal < 0.0:
          incl(result.flags, tfRequiresInit)
    else:
      if n[1].kind == nkInfix and considerQuotedIdent(c, n[1][0]).s == "..<":
        localError(c.config, n[0].info, "range types need to be constructed with '..', '..<' is not supported")
      else:
        localError(c.config, n[0].info, "expected range")
      result = newOrPrevType(tyError, prev, c)
  else:
    localError(c.config, n.info, errXExpectsOneTypeParam % "range")
    result = newOrPrevType(tyError, prev, c)

proc semArrayIndexConst(c: PContext, e: PNode, info: TLineInfo): PType =
  let x = semConstExpr(c, e)
  if x.kind in {nkIntLit..nkUInt64Lit}:
    result = makeRangeType(c, 0, x.intVal-1, info,
                        x.typ.skipTypes({tyTypeDesc}))
  else:
    result = x.typ.skipTypes({tyTypeDesc})

proc semArrayIndex(c: PContext, n: PNode): PType =
  if isRange(n):
    result = semRangeAux(c, n, nil)
  elif n.kind == nkInfix and n[0].kind == nkIdent and n[0].ident.s == "..<":
    result = errorType(c)
  else:
    # XXX this is still a hard compilation in a generic context, this can
    # result in unresolved generic parameters being treated like real types
    let e = semExprWithType(c, n, {efDetermineType})
    if e.typ.kind == tyFromExpr:
      result = makeRangeWithStaticExpr(c, e.typ.n)
    elif e.kind in {nkIntLit..nkUInt64Lit}:
      if e.intVal < 0:
        localError(c.config, n.info,
          "Array length can't be negative, but was " & $e.intVal)
      result = makeRangeType(c, 0, e.intVal-1, n.info, e.typ)
    elif e.kind == nkSym and (e.typ.kind == tyStatic or e.typ.kind == tyTypeDesc):
      if e.typ.kind == tyStatic:
        if e.sym.ast != nil:
          return semArrayIndex(c, e.sym.ast)
        if e.typ.skipModifier.kind != tyGenericParam and not isOrdinalType(e.typ.skipModifier):
          let info = if n.safeLen > 1: n[1].info else: n.info
          localError(c.config, info, errOrdinalTypeExpected % typeToString(e.typ, preferDesc))
        result = makeRangeWithStaticExpr(c, e)
        if c.inGenericContext > 0: result.flags.incl tfUnresolved
      else:
        result = e.typ.skipTypes({tyTypeDesc})
        result.flags.incl tfImplicitStatic
    elif e.kind in (nkCallKinds + {nkBracketExpr}) and hasUnresolvedArgs(c, e):
      if not isOrdinalType(e.typ.skipTypes({tyStatic, tyAlias, tyGenericInst, tySink})):
        localError(c.config, n[1].info, errOrdinalTypeExpected % typeToString(e.typ, preferDesc))
      # This is an int returning call, depending on an
      # yet unknown generic param (see tuninstantiatedgenericcalls).
      # We are going to construct a range type that will be
      # properly filled-out in semtypinst (see how tyStaticExpr
      # is handled there).
      result = makeRangeWithStaticExpr(c, e)
    elif e.kind == nkIdent:
      result = e.typ.skipTypes({tyTypeDesc})
    else:
      result = semArrayIndexConst(c, e, n.info)
        #localError(c.config, n[1].info, errConstExprExpected)

proc semArray(c: PContext, n: PNode, prev: PType): PType =
  var base: PType
  if n.len == 3:
    # 3 = length(array indx base)
    let indx = semArrayIndex(c, n[1])
    var indxB = indx
    if indxB.kind in {tyGenericInst, tyAlias, tySink}: indxB = skipModifier(indxB)
    if indxB.kind notin {tyGenericParam, tyStatic, tyFromExpr} and
        tfUnresolved notin indxB.flags:
      if not isOrdinalType(indxB):
        localError(c.config, n[1].info, errOrdinalTypeExpected % typeToString(indxB, preferDesc))
      elif enumHasHoles(indxB):
        localError(c.config, n[1].info, "enum '$1' has holes" %
                   typeToString(indxB.skipTypes({tyRange})))
      elif indxB.kind != tyRange and
          lengthOrd(c.config, indxB) > high(uint16).int:
        # assume range type is intentional
        localError(c.config, n[1].info,
          "index type '$1' for array is too large" % typeToString(indxB))
    base = semTypeNode(c, n[2], nil)
    # ensure we only construct a tyArray when there was no error (bug #3048):
    # bug #6682: Do not propagate initialization requirements etc for the
    # index type:
    result = newOrPrevType(tyArray, prev, c, indx)
    addSonSkipIntLit(result, base, c.idgen)
  else:
    localError(c.config, n.info, errArrayExpectsTwoTypeParams)
    result = newOrPrevType(tyError, prev, c)

proc semIterableType(c: PContext, n: PNode, prev: PType): PType =
  result = newOrPrevType(tyIterable, prev, c)
  if n.len == 2:
    let base = semTypeNode(c, n[1], nil)
    addSonSkipIntLit(result, base, c.idgen)
  else:
    localError(c.config, n.info, errXExpectsOneTypeParam % "iterable")
    result = newOrPrevType(tyError, prev, c)

proc semOrdinal(c: PContext, n: PNode, prev: PType): PType =
  result = newOrPrevType(tyOrdinal, prev, c)
  if n.len == 2:
    var base = semTypeNode(c, n[1], nil)
    if base.kind != tyGenericParam:
      if not isOrdinalType(base):
        localError(c.config, n[1].info, errOrdinalTypeExpected % typeToString(base, preferDesc))
    addSonSkipIntLit(result, base, c.idgen)
  else:
    localError(c.config, n.info, errXExpectsOneTypeParam % "ordinal")
    result = newOrPrevType(tyError, prev, c)

proc semAnonTuple(c: PContext, n: PNode, prev: PType): PType =
  if n.len == 0:
    localError(c.config, n.info, errTypeExpected)
  result = newOrPrevType(tyTuple, prev, c)
  for it in n:
    let t = semTypeNode(c, it, nil)
    addSonSkipIntLitChecked(c, result, t, it, c.idgen)

proc firstRange(config: ConfigRef, t: PType): PNode =
  if t.skipModifier().kind in tyFloat..tyFloat64:
    result = newFloatNode(nkFloatLit, firstFloat(t))
  else:
    result = newIntNode(nkIntLit, firstOrd(config, t))
  result.typ() = t

proc semTuple(c: PContext, n: PNode, prev: PType): PType =
  var typ: PType
  result = newOrPrevType(tyTuple, prev, c)
  result.n = newNodeI(nkRecList, n.info)
  var check = initIntSet()
  var counter = 0
  for i in ord(n.kind == nkBracketExpr)..<n.len:
    var a = n[i]
    if (a.kind != nkIdentDefs): illFormedAst(a, c.config)
    checkMinSonsLen(a, 3, c.config)
    var hasDefaultField = a[^1].kind != nkEmpty
    if hasDefaultField:
      typ = fitDefaultNode(c, a)
    elif a[^2].kind != nkEmpty:
      typ = semTypeNode(c, a[^2], nil)
      if c.graph.config.isDefined("nimPreviewRangeDefault") and typ.skipTypes(abstractInst).kind == tyRange:
        a[^1] = firstRange(c.config, typ)
        hasDefaultField = true
    else:
      localError(c.config, a.info, errTypeExpected)
      typ = errorType(c)
    for j in 0..<a.len - 2:
      var field = newSymG(skField, a[j], c)
      field.typ = typ
      field.position = counter
      inc(counter)
      if containsOrIncl(check, field.name.id):
        localError(c.config, a[j].info, "attempt to redefine: '" & field.name.s & "'")
      else:
        let fSym = newSymNode(field)
        if hasDefaultField:
          fSym.sym.ast = a[^1]
          fSym.sym.ast.flags.incl nfSkipFieldChecking
        result.n.add fSym
        addSonSkipIntLit(result, typ, c.idgen)
      styleCheckDef(c, a[j].info, field)
      onDef(field.info, field)
  if result.n.len == 0: result.n = nil
  if isTupleRecursive(result):
    localError(c.config, n.info, errIllegalRecursionInTypeX % typeToString(result))

proc semIdentVis(c: PContext, kind: TSymKind, n: PNode,
                 allowed: TSymFlags): PSym =
  # identifier with visibility
  if n.kind == nkPostfix:
    if n.len == 2:
      # for gensym'ed identifiers the identifier may already have been
      # transformed to a symbol and we need to use that here:
      result = newSymG(kind, n[1], c)
      var v = considerQuotedIdent(c, n[0])
      if sfExported in allowed and v.id == ord(wStar):
        incl(result.flags, sfExported)
      else:
        if not (sfExported in allowed):
          localError(c.config, n[0].info, errXOnlyAtModuleScope % "export")
        else:
          localError(c.config, n[0].info, errInvalidVisibilityX % renderTree(n[0]))
    else:
      result = nil
      illFormedAst(n, c.config)
  else:
    result = newSymG(kind, n, c)

proc semIdentWithPragma(c: PContext, kind: TSymKind, n: PNode,
                        allowed: TSymFlags, fromTopLevel = false): PSym =
  if n.kind == nkPragmaExpr:
    checkSonsLen(n, 2, c.config)
    result = semIdentVis(c, kind, n[0], allowed)
    case kind
    of skType:
      # process pragmas later, because result.typ has not been set yet
      discard
    of skField: pragma(c, result, n[1], fieldPragmas)
    of skVar:   pragma(c, result, n[1], varPragmas)
    of skLet:   pragma(c, result, n[1], letPragmas)
    of skConst: pragma(c, result, n[1], constPragmas)
    else: discard
  else:
    result = semIdentVis(c, kind, n, allowed)
    let invalidPragmasForPush = if fromTopLevel and sfWasGenSym notin result.flags:
      {}
    else:
      {wExportc, wExportCpp, wDynlib}
    case kind
    of skField: implicitPragmas(c, result, n.info, fieldPragmas)
    of skVar:   implicitPragmas(c, result, n.info, varPragmas-invalidPragmasForPush)
    of skLet:   implicitPragmas(c, result, n.info, letPragmas-invalidPragmasForPush)
    of skConst: implicitPragmas(c, result, n.info, constPragmas-invalidPragmasForPush)
    else: discard

proc checkForOverlap(c: PContext, t: PNode, currentEx, branchIndex: int) =
  let ex = t[branchIndex][currentEx].skipConv
  for i in 1..branchIndex:
    for j in 0..<t[i].len - 1:
      if i == branchIndex and j == currentEx: break
      if overlap(t[i][j].skipConv, ex):
        localError(c.config, ex.info, errDuplicateCaseLabel)

proc semBranchRange(c: PContext, n, a, b: PNode, covered: var Int128): PNode =
  checkMinSonsLen(n, 1, c.config)
  let ac = semConstExpr(c, a)
  let bc = semConstExpr(c, b)
  if ac.kind in {nkStrLit..nkTripleStrLit} or bc.kind in {nkStrLit..nkTripleStrLit}:
    localError(c.config, b.info, "range of string is invalid")
  var at = fitNode(c, n[0].typ, ac, ac.info).skipConvTakeType
  var bt = fitNode(c, n[0].typ, bc, bc.info).skipConvTakeType
  # the calls to fitNode may introduce calls to converters
  # mirrored with semCaseBranch for single elements
  if at.kind in {nkHiddenCallConv, nkHiddenStdConv, nkHiddenSubConv}:
    at = semConstExpr(c, at)
  if bt.kind in {nkHiddenCallConv, nkHiddenStdConv, nkHiddenSubConv}:
    bt = semConstExpr(c, bt)
  result = newNodeI(nkRange, a.info)
  result.add(at)
  result.add(bt)
  if emptyRange(ac, bc): localError(c.config, b.info, "range is empty")
  else: covered = covered + getOrdValue(bc) + 1 - getOrdValue(ac)

proc semCaseBranchRange(c: PContext, t, b: PNode,
                        covered: var Int128): PNode =
  checkSonsLen(b, 3, c.config)
  result = semBranchRange(c, t, b[1], b[2], covered)

proc semCaseBranchSetElem(c: PContext, n, b: PNode,
                          covered: var Int128): PNode =
  if isRange(b):
    checkSonsLen(b, 3, c.config)
    result = semBranchRange(c, n, b[1], b[2], covered)
  elif b.kind == nkRange:
    checkSonsLen(b, 2, c.config)
    result = semBranchRange(c, n, b[0], b[1], covered)
  else:
    result = fitNode(c, n[0].typ, b, b.info)
    inc(covered)

proc semCaseBranch(c: PContext, n, branch: PNode, branchIndex: int,
                   covered: var Int128) =
  let lastIndex = branch.len - 2
  for i in 0..lastIndex:
    var b = branch[i]
    if b.kind == nkRange:
      branch[i] = b
      # same check as in semBranchRange for exhaustiveness
      covered = covered + getOrdValue(b[1]) + 1 - getOrdValue(b[0])
    elif isRange(b):
      branch[i] = semCaseBranchRange(c, n, b, covered)
    else:
      # constant sets and arrays are allowed:
      # set expected type to selector type for type inference
      # even if it can be a different type like a set or array
      var r = semConstExpr(c, b, expectedType = n[0].typ)
      if r.kind in {nkCurly, nkBracket} and r.len == 0 and branch.len == 2:
        # discarding ``{}`` and ``[]`` branches silently
        delSon(branch, 0)
        return
      elif r.kind notin {nkCurly, nkBracket} or r.len == 0:
        checkMinSonsLen(n, 1, c.config)
        var tmp = fitNode(c, n[0].typ, r, r.info)
        # the call to fitNode may introduce a call to a converter
        # mirrored with semBranchRange
        if tmp.kind in {nkHiddenCallConv, nkHiddenStdConv, nkHiddenSubConv}:
          tmp = semConstExpr(c, tmp)
        branch[i] = skipConv(tmp)
        inc(covered)
      else:
        if r.kind == nkCurly:
          r = deduplicate(c.config, r)

        # first element is special and will overwrite: branch[i]:
        branch[i] = semCaseBranchSetElem(c, n, r[0], covered)

        # other elements have to be added to ``branch``
        for j in 1..<r.len:
          branch.add(semCaseBranchSetElem(c, n, r[j], covered))
          # caution! last son of branch must be the actions to execute:
          swap(branch[^2], branch[^1])
    checkForOverlap(c, n, i, branchIndex)

  # Elements added above needs to be checked for overlaps.
  for i in lastIndex.succ..<branch.len - 1:
    checkForOverlap(c, n, i, branchIndex)

proc toCover(c: PContext, t: PType): Int128 =
  let t2 = skipTypes(t, abstractVarRange-{tyTypeDesc})
  if t2.kind == tyEnum and enumHasHoles(t2):
    result = toInt128(t2.n.len)
  else:
    # <----
    let t = skipTypes(t, abstractVar-{tyTypeDesc})
    # XXX: hack incoming. lengthOrd is incorrect for 64bit integer
    # types because it doesn't uset Int128 yet.  This entire branching
    # should be removed as soon as lengthOrd uses int128.
    if t.kind in {tyInt64, tyUInt64}:
      result = toInt128(1) shl 64
    elif t.kind in {tyInt, tyUInt}:
      result = toInt128(1) shl (c.config.target.intSize * 8)
    else:
      result = lengthOrd(c.config, t)

proc semRecordNodeAux(c: PContext, n: PNode, check: var IntSet, pos: var int,
                      father: PNode, rectype: PType, hasCaseFields = false)

proc getIntSetOfType(c: PContext, t: PType): IntSet =
  result = initIntSet()
  if t.enumHasHoles:
    let t = t.skipTypes(abstractRange)
    for field in t.n.sons:
      result.incl(field.sym.position)
  else:
    assert(lengthOrd(c.config, t) <= BiggestInt(MaxSetElements))
    for i in toInt64(firstOrd(c.config, t))..toInt64(lastOrd(c.config, t)):
      result.incl(i.int)

iterator processBranchVals(b: PNode): int =
  assert b.kind in {nkOfBranch, nkElifBranch, nkElse}
  if b.kind == nkOfBranch:
    for i in 0..<b.len-1:
      if b[i].kind in {nkIntLit, nkCharLit}:
        yield b[i].intVal.int
      elif b[i].kind == nkRange:
        for i in b[i][0].intVal..b[i][1].intVal:
          yield i.int

proc renderAsType(vals: IntSet, t: PType): string =
  result = "{"
  let t = t.skipTypes(abstractRange)
  var enumSymOffset = 0
  var i = 0
  for val in vals:
    if result.len > 1:
      result &= ", "
    case t.kind:
    of tyEnum, tyBool:
      while t.n[enumSymOffset].sym.position < val: inc(enumSymOffset)
      result &= t.n[enumSymOffset].sym.name.s
    of tyChar:
      result.addQuoted(char(val))
    else:
      if i == 64:
        result &= "omitted $1 values..." % $(vals.len - i)
        break
      else:
        result &= $val
    inc(i)
  result &= "}"

proc formatMissingEnums(c: PContext, n: PNode): string =
  var coveredCases = initIntSet()
  for i in 1..<n.len:
    for val in processBranchVals(n[i]):
      coveredCases.incl val
  result = (c.getIntSetOfType(n[0].typ) - coveredCases).renderAsType(n[0].typ)

proc semRecordCase(c: PContext, n: PNode, check: var IntSet, pos: var int,
                   father: PNode, rectype: PType) =
  var a = copyNode(n)
  checkMinSonsLen(n, 2, c.config)
  semRecordNodeAux(c, n[0], check, pos, a, rectype, hasCaseFields = true)
  if a[0].kind != nkSym:
    internalError(c.config, "semRecordCase: discriminant is no symbol")
    return
  incl(a[0].sym.flags, sfDiscriminant)
  var covered = toInt128(0)
  var chckCovered = false
  var typ = skipTypes(a[0].typ, abstractVar-{tyTypeDesc})
  const shouldChckCovered = {tyInt..tyInt64, tyChar, tyEnum, tyUInt..tyUInt32, tyBool}
  case typ.kind
  of shouldChckCovered:
    chckCovered = true
  of tyFloat..tyFloat128, tyError:
    discard
  of tyRange:
    if skipTypes(typ.elementType, abstractInst).kind in shouldChckCovered:
      chckCovered = true
  of tyForward:
    errorUndeclaredIdentifier(c, n[0].info, typ.sym.name.s)
  elif not isOrdinalType(typ):
    localError(c.config, n[0].info, "selector must be of an ordinal type, float")
  if firstOrd(c.config, typ) != 0:
    localError(c.config, n.info, "low(" & $a[0].sym.name.s &
                                     ") must be 0 for discriminant")
  elif lengthOrd(c.config, typ) > 0x00007FFF:
    localError(c.config, n.info, "len($1) must be less than 32768" % a[0].sym.name.s)

  for i in 1..<n.len:
    var b = copyTree(n[i])
    a.add b
    case n[i].kind
    of nkOfBranch:
      checkMinSonsLen(b, 2, c.config)
      semCaseBranch(c, a, b, i, covered)
    of nkElse:
      checkSonsLen(b, 1, c.config)
      if chckCovered and covered == toCover(c, a[0].typ):
        message(c.config, b.info, warnUnreachableElse)
      chckCovered = false
    else: illFormedAst(n, c.config)
    delSon(b, b.len - 1)
    semRecordNodeAux(c, lastSon(n[i]), check, pos, b, rectype, hasCaseFields = true)
  if chckCovered and covered != toCover(c, a[0].typ):
    if a[0].typ.skipTypes(abstractRange).kind == tyEnum:
      localError(c.config, a.info, "not all cases are covered; missing: $1" %
                 formatMissingEnums(c, a))
    else:
      localError(c.config, a.info, "not all cases are covered")
  father.add a

proc semRecordNodeAux(c: PContext, n: PNode, check: var IntSet, pos: var int,
                      father: PNode, rectype: PType, hasCaseFields: bool) =
  if n == nil: return
  case n.kind
  of nkRecWhen:
    var a = copyTree(n)
    var branch: PNode = nil   # the branch to take
    var cannotResolve = false # no branch should be taken
    for i in 0..<a.len:
      var it = a[i]
      if it == nil: illFormedAst(n, c.config)
      var idx = 1
      case it.kind
      of nkElifBranch:
        checkSonsLen(it, 2, c.config)
        if c.inGenericContext == 0:
          var e = semConstBoolExpr(c, it[0])
          if e.kind != nkIntLit: discard "don't report followup error"
          elif e.intVal != 0 and branch == nil: branch = it[1]
        else:
          # XXX this is still a hard compilation in a generic context, this can
          # result in unresolved generic parameters being treated like real types
          let e = semExprWithType(c, it[0], {efDetermineType})
          if e.typ.kind == tyFromExpr:
            it[0] = makeStaticExpr(c, e)
            cannotResolve = true
          else:
            it[0] = forceBool(c, e)
            let val = getConstExpr(c.module, it[0], c.idgen, c.graph)
            if val == nil or val.kind != nkIntLit:
              cannotResolve = true
            elif not cannotResolve and val.intVal != 0 and branch == nil:
              branch = it[1]
      of nkElse:
        checkSonsLen(it, 1, c.config)
        if branch == nil and not cannotResolve: branch = it[0]
        idx = 0
      else: illFormedAst(n, c.config)
      if c.inGenericContext > 0 and cannotResolve:
        # use a new check intset here for each branch:
        var newCheck: IntSet = check
        var newPos = pos
        var newf = newNodeI(nkRecList, n.info)
        semRecordNodeAux(c, it[idx], newCheck, newPos, newf, rectype, hasCaseFields)
        it[idx] = if newf.len == 1: newf[0] else: newf
    if branch != nil:
      semRecordNodeAux(c, branch, check, pos, father, rectype, hasCaseFields)
    elif cannotResolve:
      father.add a
    elif father.kind in {nkElse, nkOfBranch}:
      father.add newNodeI(nkRecList, n.info)
  of nkRecCase:
    semRecordCase(c, n, check, pos, father, rectype)
  of nkNilLit:
    if father.kind != nkRecList: father.add newNodeI(nkRecList, n.info)
  of nkRecList:
    # attempt to keep the nesting at a sane level:
    var a = if father.kind == nkRecList: father else: copyNode(n)
    for i in 0..<n.len:
      semRecordNodeAux(c, n[i], check, pos, a, rectype, hasCaseFields)
    if a != father: father.add a
  of nkIdentDefs:
    checkMinSonsLen(n, 3, c.config)
    var a: PNode
    if father.kind != nkRecList and n.len >= 4: a = newNodeI(nkRecList, n.info)
    else: a = newNodeI(nkEmpty, n.info)
    var typ: PType
    var hasDefaultField = n[^1].kind != nkEmpty
    if hasDefaultField:
      typ = fitDefaultNode(c, n)
      propagateToOwner(rectype, typ)
    elif n[^2].kind == nkEmpty:
      localError(c.config, n.info, errTypeExpected)
      typ = errorType(c)
    else:
      typ = semTypeNode(c, n[^2], nil)
      if c.graph.config.isDefined("nimPreviewRangeDefault") and typ.skipTypes(abstractInst).kind == tyRange:
        n[^1] = firstRange(c.config, typ)
        hasDefaultField = true
      propagateToOwner(rectype, typ)
    var fieldOwner = if c.inGenericContext > 0: c.getCurrOwner
                     else: rectype.sym
    for i in 0..<n.len-2:
      var f = semIdentWithPragma(c, skField, n[i], {sfExported})
      let info = if n[i].kind == nkPostfix:
                   n[i][1].info
                 else:
                   n[i].info
      suggestSym(c.graph, info, f, c.graph.usageSym)
      f.typ = typ
      f.position = pos
      f.options = c.config.options
      if fieldOwner != nil and
         {sfImportc, sfExportc} * fieldOwner.flags != {} and
         not hasCaseFields and f.loc.snippet == "":
        f.loc.snippet = rope(f.name.s)
        f.flags.incl {sfImportc, sfExportc} * fieldOwner.flags
      inc(pos)
      if containsOrIncl(check, f.name.id):
        localError(c.config, info, "attempt to redefine: '" & f.name.s & "'")
      let fSym = newSymNode(f)
      if hasDefaultField:
        fSym.sym.ast = n[^1]
        fSym.sym.ast.flags.incl nfSkipFieldChecking
      if a.kind == nkEmpty: father.add fSym
      else: a.add fSym
      styleCheckDef(c, f)
      onDef(f.info, f)
    if a.kind != nkEmpty: father.add a
  of nkSym:
    # This branch only valid during generic object
    # inherited from generic/partial specialized parent second check.
    # There is no branch validity check here
    if containsOrIncl(check, n.sym.name.id):
      localError(c.config, n.info, "attempt to redefine: '" & n.sym.name.s & "'")
    father.add n
  of nkEmpty:
    if father.kind in {nkElse, nkOfBranch}:
      father.add n
  else: illFormedAst(n, c.config)

proc addInheritedFieldsAux(c: PContext, check: var IntSet, pos: var int,
                           n: PNode) =
  case n.kind
  of nkRecCase:
    if (n[0].kind != nkSym): internalError(c.config, n.info, "addInheritedFieldsAux")
    addInheritedFieldsAux(c, check, pos, n[0])
    for i in 1..<n.len:
      case n[i].kind
      of nkOfBranch, nkElse:
        addInheritedFieldsAux(c, check, pos, lastSon(n[i]))
      else: internalError(c.config, n.info, "addInheritedFieldsAux(record case branch)")
  of nkRecList, nkRecWhen, nkElifBranch, nkElse:
    for i in int(n.kind == nkElifBranch)..<n.len:
      addInheritedFieldsAux(c, check, pos, n[i])
  of nkSym:
    incl(check, n.sym.name.id)
    inc(pos)
  else: internalError(c.config, n.info, "addInheritedFieldsAux()")

proc skipGenericInvocation(t: PType): PType {.inline.} =
  result = t
  if result.kind == tyGenericInvocation:
    result = result[0]
  while result.kind in {tyGenericInst, tyGenericBody, tyRef, tyPtr, tyAlias, tySink, tyOwned}:
    result = skipModifier(result)

proc tryAddInheritedFields(c: PContext, check: var IntSet, pos: var int,
                        obj: PType, n: PNode, isPartial = false, innerObj: PType = nil): bool =
  if ((not isPartial) and (obj.kind notin {tyObject, tyGenericParam} or tfFinal in obj.flags)) or
    (innerObj != nil and obj.sym.id == innerObj.sym.id):
    localError(c.config, n.info, "Cannot inherit from: '" & $obj & "'")
    result = false
  elif obj.kind == tyObject:
    result = true
    if (obj.len > 0) and (obj[0] != nil):
      result = result and tryAddInheritedFields(c, check, pos, obj[0].skipGenericInvocation, n, false, obj)
    addInheritedFieldsAux(c, check, pos, obj.n)
  else:
    result = true

proc semObjectNode(c: PContext, n: PNode, prev: PType; flags: TTypeFlags): PType =
  result = nil
  if n.len == 0:
    return newConstraint(c, tyObject)
  var check = initIntSet()
  var pos = 0
  var base, realBase: PType = nil
  # n[0] contains the pragmas (if any). We process these later...
  checkSonsLen(n, 3, c.config)
  if n[1].kind != nkEmpty:
    realBase = semTypeNode(c, n[1][0], nil)
    base = skipTypesOrNil(realBase, skipPtrs)
    if base.isNil:
      localError(c.config, n.info, "cannot inherit from a type that is not an object type")
    else:
      var concreteBase = skipGenericInvocation(base)
      if concreteBase.kind in {tyObject, tyGenericParam,
        tyGenericInvocation} and tfFinal notin concreteBase.flags:
        # we only check fields duplication of object inherited from
        # concrete object. If inheriting from generic object or partial
        # specialized object, there will be second check after instantiation
        # located in semGeneric.
        if concreteBase.kind == tyObject:
          if concreteBase.sym != nil and concreteBase.sym.magic == mException and
              sfSystemModule notin c.module.flags:
            message(c.config, n.info, warnInheritFromException, "")
          if not tryAddInheritedFields(c, check, pos, concreteBase, n):
            return newType(tyError, c.idgen, result.owner)

      elif concreteBase.kind == tyForward:
        c.skipTypes.add n #we retry in the final pass
      else:
        if concreteBase.kind != tyError:
          localError(c.config, n[1].info, "inheritance only works with non-final objects; " &
             "for " & typeToString(realBase) & " to be inheritable it must be " &
             "'object of RootObj' instead of 'object'")
        base = nil
        realBase = nil
  if n.kind != nkObjectTy: internalError(c.config, n.info, "semObjectNode")
  result = newOrPrevType(tyObject, prev, c)
  rawAddSon(result, realBase)
  if realBase == nil and tfInheritable in flags:
    result.flags.incl tfInheritable
  if tfAcyclic in flags: result.flags.incl tfAcyclic
  if result.n.isNil:
    result.n = newNodeI(nkRecList, n.info)
  else:
    # partial object so add things to the check
    if not tryAddInheritedFields(c, check, pos, result, n, isPartial = true):
      return newType(tyError, c.idgen, result.owner)

  semRecordNodeAux(c, n[2], check, pos, result.n, result)
  if n[0].kind != nkEmpty:
    # dummy symbol for `pragma`:
    var s = newSymS(skType, newIdentNode(getIdent(c.cache, "dummy"), n.info), c)
    s.typ = result
    pragma(c, s, n[0], typePragmas)
  if base == nil and tfInheritable notin result.flags:
    incl(result.flags, tfFinal)
  if c.inGenericContext == 0 and computeRequiresInit(c, result):
    result.flags.incl tfRequiresInit

proc semAnyRef(c: PContext; n: PNode; kind: TTypeKind; prev: PType): PType =
  if n.len < 1:
    result = newConstraint(c, kind)
  else:
    let isCall = int ord(n.kind in nkCallKinds+{nkBracketExpr})
    let n = if n[0].kind == nkBracket: n[0] else: n
    checkMinSonsLen(n, 1, c.config)
    let body = n.lastSon
    var t = if prev != nil and prev.kind != tyGenericBody and body.kind == nkObjectTy:
              semObjectNode(c, body, nil, prev.flags)
            else:
              semTypeNode(c, body, nil)
    if t.kind == tyTypeDesc and tfUnresolved notin t.flags:
      t = t.base
    if t.kind == tyVoid:
      localError(c.config, n.info, "type '$1 void' is not allowed" % kind.toHumanStr)
    result = newOrPrevType(kind, prev, c)
    var isNilable = false
    var wrapperKind = tyNone
    # check every except the last is an object:
    for i in isCall..<n.len-1:
      let ni = n[i]
      # echo "semAnyRef ", "n: ", n, "i: ", i, "ni: ", ni
      if ni.kind == nkNilLit:
        isNilable = true
      else:
        let region = semTypeNode(c, ni, nil)
        if region.kind in {tyOwned, tySink}:
          wrapperKind = region.kind
        elif region.skipTypes({tyGenericInst, tyAlias, tySink}).kind notin {
              tyError, tyObject}:
          message c.config, n[i].info, errGenerated, "region needs to be an object type"
          addSonSkipIntLit(result, region, c.idgen)
        else:
          message(c.config, n.info, warnDeprecated, "region for pointer types is deprecated")
          addSonSkipIntLit(result, region, c.idgen)
    addSonSkipIntLit(result, t, c.idgen)
    if tfPartial in result.flags:
      if result.elementType.kind == tyObject: incl(result.elementType.flags, tfPartial)
    # if not isNilable: result.flags.incl tfNotNil
    case wrapperKind
    of tyOwned:
      if optOwnedRefs in c.config.globalOptions:
        let t = newTypeS(tyOwned, c, result)
        t.flags.incl tfHasOwned
        result = t
    of tySink:
      let t = newTypeS(tySink, c, result)
      result = t
    else: discard
    if result.kind == tyRef and c.config.selectedGC in {gcArc, gcOrc, gcAtomicArc}:
      result.flags.incl tfHasAsgn

proc findEnforcedStaticType(t: PType): PType =
  # This handles types such as `static[T] and Foo`,
  # which are subset of `static[T]`, hence they could
  # be treated in the same way
  result = nil
  if t == nil: return nil
  if t.kind == tyStatic: return t
  if t.kind == tyAnd:
    for s in t.kids:
      let t = findEnforcedStaticType(s)
      if t != nil: return t

proc addParamOrResult(c: PContext, param: PSym, kind: TSymKind) =
  if kind == skMacro:
    let staticType = findEnforcedStaticType(param.typ)
    if staticType != nil:
      var a = copySym(param, c.idgen)
      a.typ = staticType.base
      addDecl(c, a)
      #elif param.typ != nil and param.typ.kind == tyTypeDesc:
      #  addDecl(c, param)
    else:
      # within a macro, every param has the type NimNode!
      let nn = getSysSym(c.graph, param.info, "NimNode")
      var a = copySym(param, c.idgen)
      a.typ = nn.typ
      addDecl(c, a)
  else:
    if sfGenSym in param.flags:
      # bug #XXX, fix the gensym'ed parameters owner:
      if param.owner == nil:
        setOwner(param, getCurrOwner(c))
    else: addDecl(c, param)

template shouldHaveMeta(t) =
  internalAssert c.config, tfHasMeta in t.flags
  # result.lastSon.flags.incl tfHasMeta

proc addImplicitGeneric(c: PContext; typeClass: PType, typId: PIdent;
                        info: TLineInfo; genericParams: PNode;
                        paramName: string): PType =
  if genericParams == nil:
    # This happens with anonymous proc types appearing in signatures
    # XXX: we need to lift these earlier
    return
  let finalTypId = if typId != nil: typId
                    else: getIdent(c.cache, paramName & ":type")
  # is this a bindOnce type class already present in the param list?
  for i in 0..<genericParams.len:
    if genericParams[i].sym.name.id == finalTypId.id:
      return genericParams[i].typ

  let owner = if typeClass.sym != nil: typeClass.sym
              else: getCurrOwner(c)
  var s = newSym(skType, finalTypId, c.idgen, owner, info)
  if sfExplain in owner.flags: s.flags.incl sfExplain
  if typId == nil: s.flags.incl(sfAnon)
  s.linkTo(typeClass)
  typeClass.flags.incl tfImplicitTypeParam
  s.position = genericParams.len
  genericParams.add newSymNode(s)
  result = typeClass
  addDecl(c, s)

proc liftParamType(c: PContext, procKind: TSymKind, genericParams: PNode,
                   paramType: PType, paramName: string,
                   info: TLineInfo, anon = false): PType =
  if paramType == nil: return # (e.g. proc return type)

  template recurse(typ: PType, anonFlag = false): untyped =
    liftParamType(c, procKind, genericParams, typ, paramName, info, anonFlag)

  var paramTypId = if not anon and paramType.sym != nil: paramType.sym.name
                   else: nil

  case paramType.kind
  of tyAnything:
    result = addImplicitGeneric(c, newTypeS(tyGenericParam, c), nil, info, genericParams, paramName)

  of tyStatic:
    if paramType.base.kind != tyNone and paramType.n != nil:
      # this is a concrete static value
      return
    if tfUnresolved in paramType.flags: return # already lifted

    let lifted = recurse(paramType.base)
    let base = (if lifted != nil: lifted else: paramType.base)
    if base.isMetaType and procKind == skMacro:
      localError(c.config, info, errMacroBodyDependsOnGenericTypes % paramName)
    result = addImplicitGeneric(c, newTypeS(tyStatic, c, base),
        paramTypId, info, genericParams, paramName)
    if result != nil: result.flags.incl({tfHasStatic, tfUnresolved})

  of tyTypeDesc:
    if tfUnresolved notin paramType.flags:
      # naked typedescs are not bindOnce types
      if paramType.base.kind == tyNone and paramTypId != nil and
          (paramTypId.id == getIdent(c.cache, "typedesc").id or
          paramTypId.id == getIdent(c.cache, "type").id):
        # XXX Why doesn't this check for tyTypeDesc instead?
        paramTypId = nil
      let t = newTypeS(tyTypeDesc, c, paramType.base)
      incl t.flags, tfCheckedForDestructor
      result = addImplicitGeneric(c, t, paramTypId, info, genericParams, paramName)
    else:
      result = nil
  of tyDistinct:
    if paramType.len == 1:
      # disable the bindOnce behavior for the type class
      result = recurse(paramType.base, true)
    else:
      result = nil
  of tyTuple:
    result = nil
    for i in 0..<paramType.len:
      let t = recurse(paramType[i])
      if t != nil:
        paramType[i] = t
        result = paramType

  of tyAlias, tyOwned:
    result = recurse(paramType.base)

  of tySequence, tySet, tyArray, tyOpenArray,
     tyVar, tyLent, tyPtr, tyRef, tyProc, tySink:
    # XXX: this is a bit strange, but proc(s: seq)
    # produces tySequence(tyGenericParam, tyNone).
    # This also seems to be true when creating aliases
    # like: type myseq = distinct seq.
    # Maybe there is another better place to associate
    # the seq type class with the seq identifier.
    if paramType.kind == tySequence and paramType.elementType.kind == tyNone:
      let typ = newTypeS(tyBuiltInTypeClass, c,
                         newTypeS(paramType.kind, c))
      result = addImplicitGeneric(c, typ, paramTypId, info, genericParams, paramName)
    else:
      result = nil
      for i in 0..<paramType.len:
        if paramType[i] == paramType:
          globalError(c.config, info, errIllegalRecursionInTypeX % typeToString(paramType))
        var lifted = recurse(paramType[i])
        if lifted != nil:
          paramType[i] = lifted
          result = paramType

  of tyGenericBody:
    result = newTypeS(tyGenericInvocation, c)
    result.rawAddSon(paramType)

    for i in 0..<paramType.len - 1:
      if paramType[i].kind == tyStatic:
        var staticCopy = paramType[i].exactReplica
        staticCopy.flags.incl tfInferrableStatic
        result.rawAddSon staticCopy
      else:
        result.rawAddSon newTypeS(tyAnything, c)

    if paramType.typeBodyImpl.kind == tyUserTypeClass:
      result.kind = tyUserTypeClassInst
      result.rawAddSon paramType.typeBodyImpl
      return addImplicitGeneric(c, result, paramTypId, info, genericParams, paramName)

    let x = instGenericContainer(c, paramType.sym.info, result,
                                  allowMetaTypes = true)
    result = newTypeS(tyCompositeTypeClass, c)
    result.rawAddSon paramType
    result.rawAddSon x
    result = addImplicitGeneric(c, result, paramTypId, info, genericParams, paramName)

  of tyGenericInst:
    result = nil
    if paramType.skipModifier.kind == tyUserTypeClass:
      var cp = copyType(paramType, c.idgen, getCurrOwner(c))
      copyTypeProps(c.graph, c.idgen.module, cp, paramType)

      cp.kind = tyUserTypeClassInst
      return addImplicitGeneric(c, cp, paramTypId, info, genericParams, paramName)

    for i in 1..<paramType.len-1:
      var lifted = recurse(paramType[i])
      if lifted != nil:
        paramType[i] = lifted
        result = paramType
        result.last.shouldHaveMeta

    let liftBody = recurse(paramType.skipModifier, true)
    if liftBody != nil:
      result = liftBody
      result.flags.incl tfHasMeta
      #result.shouldHaveMeta

  of tyGenericInvocation:
    result = nil
    for i in 1..<paramType.len:
      #if paramType[i].kind != tyTypeDesc:
      let lifted = recurse(paramType[i])
      if lifted != nil: paramType[i] = lifted

    let body = paramType.base
    if body.kind in {tyForward, tyError}:
      # this may happen for proc type appearing in a type section
      # before one of its param types
      return

    if body.last.kind == tyUserTypeClass:
      let expanded = instGenericContainer(c, info, paramType,
                                          allowMetaTypes = true)
      result = recurse(expanded, true)

  of tyUserTypeClasses, tyBuiltInTypeClass, tyCompositeTypeClass,
     tyAnd, tyOr, tyNot, tyConcept:
    result = addImplicitGeneric(c,
        copyType(paramType, c.idgen, getCurrOwner(c)), paramTypId,
        info, genericParams, paramName)

  of tyGenericParam:
    result = nil
    markUsed(c, paramType.sym.info, paramType.sym)
    onUse(paramType.sym.info, paramType.sym)
    if tfWildcard in paramType.flags:
      paramType.flags.excl tfWildcard
      paramType.sym.transitionGenericParamToType()

  else: result = nil

proc semParamType(c: PContext, n: PNode, constraint: var PNode): PType =
  ## Semchecks the type of parameters.
  if n.kind == nkCurlyExpr:
    result = semTypeNode(c, n[0], nil)
    constraint = semNodeKindConstraints(n, c.config, 1)
  elif n.kind == nkCall and
      n[0].kind in {nkIdent, nkSym, nkOpenSymChoice, nkClosedSymChoice, nkOpenSym} and
      considerQuotedIdent(c, n[0]).s == "{}":
    result = semTypeNode(c, n[1], nil)
    constraint = semNodeKindConstraints(n, c.config, 2)
  else:
    result = semTypeNode(c, n, nil)

proc newProcType(c: PContext; info: TLineInfo; prev: PType = nil): PType =
  result = newOrPrevType(tyProc, prev, c)
  result.callConv = lastOptionEntry(c).defaultCC
  result.n = newNodeI(nkFormalParams, info)
  rawAddSon(result, nil) # return type
  # result.n[0] used to be `nkType`, but now it's `nkEffectList` because
  # the effects are now stored in there too ... this is a bit hacky, but as
  # usual we desperately try to save memory:
  result.n.add newNodeI(nkEffectList, info)

proc isMagic(sym: PSym): bool =
  if sym.ast == nil: return false
  let nPragmas = sym.ast[pragmasPos]
  return hasPragma(nPragmas, wMagic)

proc semProcTypeNode(c: PContext, n, genericParams: PNode,
                     prev: PType, kind: TSymKind; isType=false): PType =
  # for historical reasons (code grows) this is invoked for parameter
  # lists too and then 'isType' is false.
  checkMinSonsLen(n, 1, c.config)
  result = newProcType(c, n.info, prev)
  var check = initIntSet()
  var counter = 0
  template isCurrentlyGeneric: bool =
    # genericParams might update as implicit generic params are added
    genericParams != nil and genericParams.len > 0

  for i in 1..<n.len:
    var a = n[i]
    if a.kind != nkIdentDefs:
      # for some generic instantiations the passed ':env' parameter
      # for closures has already been produced (see bug #898). We simply
      # skip this parameter here. It'll then be re-generated in another LL
      # pass over this instantiation:
      if a.kind == nkSym and sfFromGeneric in a.sym.flags: continue
      illFormedAst(a, c.config)

    checkMinSonsLen(a, 3, c.config)
    var
      typ: PType = nil
      def: PNode = nil
      constraint: PNode = nil
      hasType = a[^2].kind != nkEmpty
      hasDefault = a[^1].kind != nkEmpty

    if hasType:
      let isGeneric = isCurrentlyGeneric()
      inc c.inGenericContext, ord(isGeneric)
      typ = semParamType(c, a[^2], constraint)
      dec c.inGenericContext, ord(isGeneric)
      # TODO: Disallow typed/untyped in procs in the compiler/stdlib
      if kind in {skProc, skFunc} and (typ.kind == tyTyped or typ.kind == tyUntyped):
        if not isMagic(getCurrOwner(c)):
          localError(c.config, a[^2].info, "'" & typ.sym.name.s & "' is only allowed in templates and macros or magic procs")


    if hasDefault:
      def = a[^1]
      if a.len > 3:
        var msg = ""
        for j in 0 ..< a.len - 2:
          if msg.len != 0: msg.add(", ")
          msg.add($a[j])
        msg.add(" all have default value '")
        msg.add(def.renderTree)
        msg.add("', this may be unintentional, " &
          "either use ';' (semicolon) or explicitly write each default value")
        message(c.config, a.info, warnImplicitDefaultValue, msg)
      block determineType:
        var canBeVoid = false
        if kind == skTemplate:
          if typ != nil and typ.kind == tyUntyped:
            # don't do any typechecking or assign a type for
            # `untyped` parameter default value
            break determineType
          elif hasUnresolvedArgs(c, def):
            # template default value depends on other parameter
            # don't do any typechecking
            def.typ() = makeTypeFromExpr(c, def.copyTree)
            break determineType
          elif typ != nil and typ.kind == tyTyped:
            canBeVoid = true
        let isGeneric = isCurrentlyGeneric()
        inc c.inGenericContext, ord(isGeneric)
        if canBeVoid:
          def = semExpr(c, def, {efDetermineType, efAllowSymChoice}, typ)
        else:
          def = semExprWithType(c, def, {efDetermineType, efAllowSymChoice}, typ)
        dec c.inGenericContext, ord(isGeneric)
        if def.referencesAnotherParam(getCurrOwner(c)):
          def.flags.incl nfDefaultRefsParam

      if typ == nil:
        typ = def.typ
        if isEmptyContainer(typ):
          localError(c.config, a.info, "cannot infer the type of parameter '" & $a[0] & "'")

        if typ.kind == tyTypeDesc:
          # consider a proc such as:
          # proc takesType(T = int)
          # a naive analysis may conclude that the proc type is type[int]
          # which will prevent other types from matching - clearly a very
          # surprising behavior. We must instead fix the expected type of
          # the proc to be the unbound typedesc type:
          typ = newTypeS(tyTypeDesc, c, newTypeS(tyNone, c))
          typ.flags.incl tfCheckedForDestructor

      elif def.typ != nil and def.typ.kind != tyFromExpr: # def.typ can be void
        # if def.typ != nil and def.typ.kind != tyNone:
        # example code that triggers it:
        # proc sort[T](cmp: proc(a, b: T): int = cmp)
        if not containsGenericType(typ):
          # check type compatibility between def.typ and typ:
          def = fitNode(c, typ, def, def.info)
        elif typ.kind == tyStatic:
          def = semConstExpr(c, def)
          def = fitNode(c, typ, def, def.info)

    if not hasType and not hasDefault:
      if isType: localError(c.config, a.info, "':' expected")
      if kind in {skTemplate, skMacro}:
        typ = newTypeS(tyUntyped, c)
    elif skipTypes(typ, {tyGenericInst, tyAlias, tySink}).kind == tyVoid:
      continue

    for j in 0..<a.len-2:
      var arg = newSymG(skParam, if a[j].kind == nkPragmaExpr: a[j][0] else: a[j], c)
      if arg.name.id == ord(wUnderscore):
        arg.flags.incl(sfGenSym)
      elif containsOrIncl(check, arg.name.id):
        localError(c.config, a[j].info, "attempt to redefine: '" & arg.name.s & "'")
      if a[j].kind == nkPragmaExpr:
        pragma(c, arg, a[j][1], paramPragmas)
      if not hasType and not hasDefault and kind notin {skTemplate, skMacro}:
        let param = strTableGet(c.signatures, arg.name)
        if param != nil: typ = param.typ
        else:
          localError(c.config, a.info, "parameter '$1' requires a type" % arg.name.s)
          typ = errorType(c)
      var nameForLift = arg.name.s
      if sfGenSym in arg.flags:
        nameForLift.add("`gensym" & $arg.id)
      let lifted = liftParamType(c, kind, genericParams, typ,
                                 nameForLift, arg.info)
      let finalType = if lifted != nil: lifted else: typ.skipIntLit(c.idgen)
      arg.typ = finalType
      arg.position = counter
      if constraint != nil:
        #only replace the constraint when it has been set as arg could contain codegenDecl
        arg.constraint = constraint
      inc(counter)
      if def != nil and def.kind != nkEmpty:
        arg.ast = copyTree(def)
      result.n.add newSymNode(arg)
      rawAddSon(result, finalType)
      addParamOrResult(c, arg, kind)
      styleCheckDef(c, a[j].info, arg)
      onDef(a[j].info, arg)
      a[j] = newSymNode(arg)

  var r: PType = nil
  if n[0].kind != nkEmpty:
    let isGeneric = isCurrentlyGeneric()
    inc c.inGenericContext, ord(isGeneric)
    r = semTypeNode(c, n[0], nil)
    dec c.inGenericContext, ord(isGeneric)

  if r != nil and kind in {skMacro, skTemplate} and r.kind == tyTyped:
    # XXX: To implement the proposed change in the warning, just
    # delete this entire if block. The rest is (at least at time of
    # writing this comment) already implemented.
    let info = n[0].info
    const msg = "`typed` will change its meaning in future versions of Nim. " &
                "`void` or no return type declaration at all has the same " &
                "meaning as the current meaning of `typed` as return type " &
                "declaration."
    message(c.config, info, warnDeprecated, msg)
    r = nil

  if r != nil:
    # turn explicit 'void' return type into 'nil' because the rest of the
    # compiler only checks for 'nil':
    if skipTypes(r, {tyGenericInst, tyAlias, tySink}).kind != tyVoid:
      if kind notin {skMacro, skTemplate} and r.kind in {tyTyped, tyUntyped}:
        localError(c.config, n[0].info, "return type '" & typeToString(r) &
            "' is only valid for macros and templates")
      # 'auto' as a return type does not imply a generic:
      elif r.kind == tyAnything:
        r = copyType(r, c.idgen, r.owner)
        r.flags.incl tfRetType
      elif r.kind == tyStatic:
        # type allowed should forbid this type
        discard
      else:
        if r.sym == nil or sfAnon notin r.sym.flags:
          let lifted = liftParamType(c, kind, genericParams, r, "result",
                                     n[0].info)
          if lifted != nil:
            r = lifted
            #if r.kind != tyGenericParam:
            #echo "came here for ", typeToString(r)
            r.flags.incl tfRetType
        r = skipIntLit(r, c.idgen)
        if kind == skIterator:
          # see tchainediterators
          # in cases like iterator foo(it: iterator): typeof(it)
          # we don't need to change the return type to iter[T]
          result.flags.incl tfIterator
          # XXX Would be nice if we could get rid of this
      result[0] = r
      let oldFlags = result.flags
      propagateToOwner(result, r)
      if oldFlags != result.flags:
        # XXX This rather hacky way keeps 'tflatmap' compiling:
        if tfHasMeta notin oldFlags:
          result.flags.excl tfHasMeta
      result.n.typ() = r

  if isCurrentlyGeneric():
    for n in genericParams:
      if {sfUsed, sfAnon} * n.sym.flags == {}:
        result.flags.incl tfUnresolved

      if tfWildcard in n.sym.typ.flags:
        n.sym.transitionGenericParamToType()
        n.sym.typ.flags.excl tfWildcard

proc semStmtListType(c: PContext, n: PNode, prev: PType): PType =
  checkMinSonsLen(n, 1, c.config)
  for i in 0..<n.len - 1:
    n[i] = semStmt(c, n[i], {})
  if n.len > 0:
    result = semTypeNode(c, n[^1], prev)
    n.typ() = result
    n[^1].typ() = result
  else:
    result = nil

proc semBlockType(c: PContext, n: PNode, prev: PType): PType =
  inc(c.p.nestedBlockCounter)
  let oldBreakInLoop = c.p.breakInLoop
  c.p.breakInLoop = false
  checkSonsLen(n, 2, c.config)
  openScope(c)
  if n[0].kind notin {nkEmpty, nkSym}:
    addDecl(c, newSymS(skLabel, n[0], c))
  result = semStmtListType(c, n[1], prev)
  n[1].typ() = result
  n.typ() = result
  closeScope(c)
  c.p.breakInLoop = oldBreakInLoop
  dec(c.p.nestedBlockCounter)

proc semGenericParamInInvocation(c: PContext, n: PNode): PType =
  result = semTypeNode(c, n, nil)
  n.typ() = makeTypeDesc(c, result)

proc trySemObjectTypeForInheritedGenericInst(c: PContext, n: PNode, t: PType): bool =
  var
    check = initIntSet()
    pos = 0
  let
    realBase = t.baseClass
    base = skipTypesOrNil(realBase, skipPtrs)
  result = true
  if base.isNil:
    localError(c.config, n.info, errIllegalRecursionInTypeX % "object")
  else:
    let concreteBase = skipGenericInvocation(base)
    if concreteBase.kind == tyObject and tfFinal notin concreteBase.flags:
      if not tryAddInheritedFields(c, check, pos, concreteBase, n):
        return false
    else:
      if concreteBase.kind != tyError:
        localError(c.config, n.info, errInheritanceOnlyWithNonFinalObjects)
  var newf = newNodeI(nkRecList, n.info)
  semRecordNodeAux(c, t.n, check, pos, newf, t)

proc containsGenericInvocationWithForward(n: PNode): bool =
  if n.kind == nkSym and n.sym.ast != nil and n.sym.ast.len > 1 and n.sym.ast[2].kind == nkObjectTy:
    for p in n.sym.ast[2][^1]:
      if p.kind == nkIdentDefs and p[1].typ != nil and p[1].typ.kind == tyGenericInvocation and
        p[1][0].kind == nkSym and p[1][0].typ.kind == tyForward:
          return true
  return false

proc semGeneric(c: PContext, n: PNode, s: PSym, prev: PType): PType =
  if s.typ == nil:
    localError(c.config, n.info, "cannot instantiate the '$1' $2" %
               [s.name.s, s.kind.toHumanStr])
    return newOrPrevType(tyError, prev, c)

  var t = s.typ.skipTypes({tyAlias})
  if t.kind == tyCompositeTypeClass and t.base.kind == tyGenericBody:
    t = t.base
  result = newOrPrevType(tyGenericInvocation, prev, c)
  addSonSkipIntLit(result, t, c.idgen)

  template addToResult(typ, skip) =

    if typ.isNil:
      internalAssert c.config, false
      rawAddSon(result, typ)
    else:
      if skip:
        addSonSkipIntLit(result, typ, c.idgen)
      else:
        rawAddSon(result, makeRangeWithStaticExpr(c, typ.n))

  if t.kind == tyForward:
    for i in 1..<n.len:
      var elem = semGenericParamInInvocation(c, n[i])
      addToResult(elem, true)
    return
  elif t.kind != tyGenericBody:
    # we likely got code of the form TypeA[TypeB] where TypeA is
    # not generic.
    localError(c.config, n.info, errNoGenericParamsAllowedForX % s.name.s)
    return newOrPrevType(tyError, prev, c)
  else:
    var m = newCandidate(c, t)
    m.isNoCall = true
    matches(c, n, copyTree(n), m)

    if m.state != csMatch:
      var err = "cannot instantiate "
      err.addTypeHeader(c.config, t)
      err.add "\ngot: <$1>\nbut expected: <$2>" % [describeArgs(c, n), describeArgs(c, t.n, 0)]
      localError(c.config, n.info, errGenerated, err)
      return newOrPrevType(tyError, prev, c)

    var isConcrete = true
    let rType = m.call[0].typ
    let mIndex = if rType != nil: rType.len - 1 else: -1
    for i in 1..<m.call.len:
      var typ = m.call[i].typ
      # is this a 'typedesc' *parameter*? If so, use the typedesc type,
      # unstripped.
      if m.call[i].kind == nkSym and m.call[i].sym.kind == skParam and
          typ.kind == tyTypeDesc and containsGenericType(typ):
        isConcrete = false
        addToResult(typ, true)
      else:
        typ = typ.skipTypes({tyTypeDesc})
        if containsGenericType(typ): isConcrete = false
        var skip = true
        if mIndex >= i - 1 and tfImplicitStatic in rType[i - 1].flags and isIntLit(typ):
          skip = false
        addToResult(typ, skip)

    if isConcrete:
      if s.ast == nil and s.typ.kind != tyCompositeTypeClass:
        # XXX: What kind of error is this? is it still relevant?
        localError(c.config, n.info, errCannotInstantiateX % s.name.s)
        result = newOrPrevType(tyError, prev, c)
      elif containsGenericInvocationWithForward(n[0]):
        c.skipTypes.add n #fixes 1500
      else:
        result = instGenericContainer(c, n.info, result,
                                      allowMetaTypes = false)

  # special check for generic object with
  # generic/partial specialized parent
  let tx = result.skipTypes(abstractPtrs, 50)
  if tx.isNil or isTupleRecursive(tx):
    localError(c.config, n.info, "illegal recursion in type '$1'" % typeToString(result[0]))
    return errorType(c)
  if tx != result and tx.kind == tyObject:
    if tx[0] != nil:
      if not trySemObjectTypeForInheritedGenericInst(c, n, tx):
        return newOrPrevType(tyError, prev, c)
    var position = 0
    recomputeFieldPositions(tx, tx.n, position)

proc maybeAliasType(c: PContext; typeExpr, prev: PType): PType =
  if prev != nil and (prev.kind == tyGenericBody or
      typeExpr.kind in {tyObject, tyEnum, tyDistinct, tyForward, tyGenericBody}):
    result = newTypeS(tyAlias, c)
    result.rawAddSon typeExpr
    result.sym = prev.sym
    if prev.kind != tyGenericBody:
      assignType(prev, result)
  else:
    result = nil

proc fixupTypeOf(c: PContext, prev: PType, typExpr: PNode) =
  if prev != nil:
    let result = newTypeS(tyAlias, c)
    result.rawAddSon typExpr.typ
    result.sym = prev.sym
    if prev.kind != tyGenericBody:
      assignType(prev, result)

proc semTypeExpr(c: PContext, n: PNode; prev: PType): PType =
  var n = semExprWithType(c, n, {efDetermineType})
  if n.typ.kind == tyTypeDesc:
    result = n.typ.base
    # fix types constructed by macros/template:
    if prev != nil and prev.kind != tyGenericBody and prev.sym != nil:
      if result.sym.isNil:
        # Behold! you're witnessing enormous power yielded
        # by macros. Only macros can summon unnamed types
        # and cast spell upon AST. Here we need to give
        # it a name taken from left hand side's node
        result.sym = prev.sym
        result.sym.typ = result
      else:
        # Less powerful routine like template do not have
        # the ability to produce unnamed types. But still
        # it has wild power to push a type a bit too far.
        # So we need to hold it back using alias and prevent
        # unnecessary new type creation
        let alias = maybeAliasType(c, result, prev)
        if alias != nil: result = alias
  elif n.typ.kind == tyFromExpr and c.inGenericContext > 0:
    # sometimes not possible to distinguish type from value in generic body,
    # for example `T.Foo`, so both are handled under `tyFromExpr`
    result = n.typ
  else:
    localError(c.config, n.info, "expected type, but got: " & n.renderTree)
    result = errorType(c)

proc freshType(c: PContext; res, prev: PType): PType {.inline.} =
  if prev.isNil or prev.kind == tyGenericBody:
    result = copyType(res, c.idgen, res.owner)
    copyTypeProps(c.graph, c.idgen.module, result, res)
  else:
    result = res

template modifierTypeKindOfNode(n: PNode): TTypeKind =
  case n.kind
  of nkVarTy: tyVar
  of nkRefTy: tyRef
  of nkPtrTy: tyPtr
  of nkStaticTy: tyStatic
  of nkTypeOfExpr: tyTypeDesc
  else: tyNone

proc semTypeClass(c: PContext, n: PNode, prev: PType): PType =
  # if n.len == 0: return newConstraint(c, tyTypeClass)
  if isNewStyleConcept(n):
    result = newOrPrevType(tyConcept, prev, c)
    result.flags.incl tfCheckedForDestructor
    result.n = semConceptDeclaration(c, n)
    return result

  let
    pragmas = n[1]
    inherited = n[2]

  var owner = getCurrOwner(c)
  var candidateTypeSlot = newTypeS(tyAlias, c, c.errorType)
  result = newOrPrevType(tyUserTypeClass, prev, c, son = candidateTypeSlot)
  result.flags.incl tfCheckedForDestructor
  result.n = n

  if inherited.kind != nkEmpty:
    for n in inherited.sons:
      let typ = semTypeNode(c, n, nil)
      result.add(typ)

  openScope(c)
  for param in n[0]:
    var
      dummyName: PNode
      dummyType: PType

    let modifier = param.modifierTypeKindOfNode

    if modifier != tyNone:
      dummyName = param[0]
      dummyType = c.makeTypeWithModifier(modifier, candidateTypeSlot)
      # if modifier == tyRef:
        # dummyType.flags.incl tfNotNil
      if modifier == tyTypeDesc:
        dummyType.flags.incl tfConceptMatchedTypeSym
        dummyType.flags.incl tfCheckedForDestructor
    else:
      dummyName = param
      dummyType = candidateTypeSlot

    # this can be true for 'nim check' on incomplete concepts,
    # see bug #8230
    if dummyName.kind == nkEmpty: continue

    internalAssert c.config, dummyName.kind == nkIdent
    var dummyParam = newSym(if modifier == tyTypeDesc: skType else: skVar,
                            dummyName.ident, c.idgen, owner, param.info)
    dummyParam.typ = dummyType
    incl dummyParam.flags, sfUsed
    addDecl(c, dummyParam)

  result.n[3] = semConceptBody(c, n[3])
  closeScope(c)

proc applyTypeSectionPragmas(c: PContext; pragmas, operand: PNode): PNode =
  result = nil
  for p in pragmas:
    let key = if p.kind in nkPragmaCallKinds and p.len >= 1: p[0] else: p
    if p.kind == nkEmpty or whichPragma(p) != wInvalid:
      discard "builtin pragma"
    else:
      trySuggestPragmas(c, key)
      let ident =
        if key.kind in nkIdentKinds:
          considerQuotedIdent(c, key)
        else:
          nil
      if ident != nil and strTableGet(c.userPragmas, ident) != nil:
        discard "User-defined pragma"
      else:
        let sym = qualifiedLookUp(c, key, {})
        # XXX: What to do here if amb is true?
        if sym != nil and sfCustomPragma in sym.flags:
          discard "Custom user pragma"
        else:
          # we transform ``(arg1, arg2: T) {.m, rest.}`` into ``m((arg1, arg2: T) {.rest.})`` and
          # let the semantic checker deal with it:
          var x = newNodeI(nkCall, key.info)
          x.add(key)
          if p.kind in nkPragmaCallKinds and p.len > 1:
            # pass pragma arguments to the macro too:
            for i in 1 ..< p.len:
              x.add(p[i])
          # Also pass the node the pragma has been applied to
          x.add(operand.copyTreeWithoutNode(p))
          # recursion assures that this works for multiple macro annotations too:
          var r = semOverloadedCall(c, x, x, {skMacro, skTemplate}, {efNoUndeclared})
          if r != nil:
            doAssert r[0].kind == nkSym
            let m = r[0].sym
            case m.kind
            of skMacro: return semMacroExpr(c, r, r, m, {efNoSemCheck})
            of skTemplate: return semTemplateExpr(c, r, m, {efNoSemCheck})
            else: doAssert(false, "cannot happen")

proc semProcTypeWithScope(c: PContext, n: PNode,
                          prev: PType, kind: TSymKind): PType =
  checkSonsLen(n, 2, c.config)

  if n[1].kind != nkEmpty and n[1].len > 0:
    let macroEval = applyTypeSectionPragmas(c, n[1], n)
    if macroEval != nil:
      return semTypeNode(c, macroEval, prev)

  openScope(c)
  result = semProcTypeNode(c, n[0], nil, prev, kind, isType=true)
  # start with 'ccClosure', but of course pragmas can overwrite this:
  result.callConv = ccClosure
  # dummy symbol for `pragma`:
  var s = newSymS(kind, newIdentNode(getIdent(c.cache, "dummy"), n.info), c)
  s.typ = result
  if n[1].kind != nkEmpty and n[1].len > 0:
    pragma(c, s, n[1], procTypePragmas)
    when useEffectSystem: setEffectsForProcType(c.graph, result, n[1])
  elif c.optionStack.len > 0:
    # we construct a fake 'nkProcDef' for the 'mergePragmas' inside 'implicitPragmas'...
    s.ast = newTree(nkProcDef, newNodeI(nkEmpty, n.info), newNodeI(nkEmpty, n.info),
        newNodeI(nkEmpty, n.info), newNodeI(nkEmpty, n.info), newNodeI(nkEmpty, n.info))
    implicitPragmas(c, s, n.info, {wTags, wRaises})
    when useEffectSystem: setEffectsForProcType(c.graph, result, s.ast[pragmasPos])
  closeScope(c)

proc symFromExpectedTypeNode(c: PContext, n: PNode): PSym =
  if n.kind == nkType:
    result = symFromType(c, n.typ, n.info)
  else:
    localError(c.config, n.info, errTypeExpected)
    result = errorSym(c, n)

proc semStaticType(c: PContext, childNode: PNode, prev: PType): PType =
  result = newOrPrevType(tyStatic, prev, c)
  var base = semTypeNode(c, childNode, nil).skipTypes({tyTypeDesc, tyAlias})
  result.rawAddSon(base)
  result.flags.incl tfHasStatic

proc semTypeOf(c: PContext; n: PNode; prev: PType): PType =
  openScope(c)
  inc c.inTypeofContext
  defer: dec c.inTypeofContext # compiles can raise an exception
  let t = semExprWithType(c, n, {efInTypeof})
  closeScope(c)
  fixupTypeOf(c, prev, t)
  result = t.typ
  if result.kind == tyFromExpr:
    result.flags.incl tfNonConstExpr

proc semTypeOf2(c: PContext; n: PNode; prev: PType): PType =
  openScope(c)
  var m = BiggestInt 1 # typeOfIter
  if n.len == 3:
    let mode = semConstExpr(c, n[2])
    if mode.kind != nkIntLit:
      localError(c.config, n.info, "typeof: cannot evaluate 'mode' parameter at compile-time")
    else:
      m = mode.intVal
  inc c.inTypeofContext
  defer: dec c.inTypeofContext # compiles can raise an exception
  let t = semExprWithType(c, n[1], if m == 1: {efInTypeof} else: {})
  closeScope(c)
  fixupTypeOf(c, prev, t)
  result = t.typ
  if result.kind == tyFromExpr:
    result.flags.incl tfNonConstExpr

proc semTypeIdent(c: PContext, n: PNode): PSym =
  if n.kind == nkSym:
    result = getGenSym(c, n.sym)
  else:
    result = pickSym(c, n, {skType, skGenericParam, skParam})
    if result.isNil:
      result = qualifiedLookUp(c, n, {checkAmbiguity, checkUndeclared})
    if result != nil:
      markUsed(c, n.info, result)
      onUse(n.info, result)

      # alias syntax, see semSym for skTemplate, skMacro
      if result.kind in {skTemplate, skMacro} and sfNoalias notin result.flags:
        let t = semTypeExpr(c, n, nil)
        result = symFromType(c, t, n.info)

      if result.kind == skParam and result.typ.kind == tyTypeDesc:
        # This is a typedesc param. is it already bound?
        # it's not bound when it's used multiple times in the
        # proc signature for example
        if c.inGenericInst > 0:
          let bound = result.typ.elementType.sym
          if bound != nil: return bound
          return result
        if result.typ.sym == nil:
          localError(c.config, n.info, errTypeExpected)
          return errorSym(c, n)
        result = result.typ.sym.copySym(c.idgen)
        result.typ = exactReplica(result.typ)
        result.typ.flags.incl tfUnresolved

      if result.kind == skGenericParam:
        if result.typ.kind == tyGenericParam and result.typ.len == 0 and
           tfWildcard in result.typ.flags:
          # collapse the wild-card param to a type
          result.transitionGenericParamToType()
          result.typ.flags.excl tfWildcard
          return
        else:
          localError(c.config, n.info, errTypeExpected)
          return errorSym(c, n)
      if result.kind != skType and result.magic notin {mStatic, mType, mTypeOf}:
        # this implements the wanted ``var v: V, x: V`` feature ...
        var ov: TOverloadIter = default(TOverloadIter)
        var amb = initOverloadIter(ov, c, n)
        while amb != nil and amb.kind != skType:
          amb = nextOverloadIter(ov, c, n)
        if amb != nil: result = amb
        else:
          if result.kind != skError: localError(c.config, n.info, errTypeExpected)
          return errorSym(c, n)
      if result.typ.kind != tyGenericParam:
        # XXX get rid of this hack!
        var oldInfo = n.info
        when defined(useNodeIds):
          let oldId = n.id
        reset(n[])
        when defined(useNodeIds):
          n.id = oldId
        n.transitionNoneToSym()
        n.sym = result
        n.info = oldInfo
        n.typ() = result.typ
    else:
      localError(c.config, n.info, "identifier expected")
      result = errorSym(c, n)

proc semTypeNode(c: PContext, n: PNode, prev: PType): PType =
  result = nil
  inc c.inTypeContext

  if c.config.cmd == cmdIdeTools: suggestExpr(c, n)
  case n.kind
  of nkEmpty: result = n.typ
  of nkTypeOfExpr:
    # for ``typeof(countup(1,3))``, see ``tests/ttoseq``.
    checkSonsLen(n, 1, c.config)
    result = semTypeOf(c, n[0], prev)
    if result.kind == tyTypeDesc: result.flags.incl tfExplicit
  of nkPar:
    if n.len == 1: result = semTypeNode(c, n[0], prev)
    else:
      result = semAnonTuple(c, n, prev)
  of nkTupleConstr: result = semAnonTuple(c, n, prev)
  of nkCallKinds:
    let x = n[0]
    let ident = x.getPIdent
    if ident != nil and ident.s == "[]":
      let b = newNodeI(nkBracketExpr, n.info)
      for i in 1..<n.len: b.add(n[i])
      result = semTypeNode(c, b, prev)
    elif ident != nil and ident.id == ord(wDotDot):
      result = semRangeAux(c, n, prev)
    elif n[0].kind == nkNilLit and n.len == 2:
      result = semTypeNode(c, n[1], prev)
      if result.skipTypes({tyGenericInst, tyAlias, tySink, tyOwned}).kind in NilableTypes+GenericTypes:
        if tfNotNil in result.flags:
          result = freshType(c, result, prev)
          result.flags.excl(tfNotNil)
      else:
        localError(c.config, n.info, errGenerated, "invalid type")
    elif n[0].kind notin nkIdentKinds:
      result = semTypeExpr(c, n, prev)
    else:
      let op = considerQuotedIdent(c, n[0])
      if op.id == ord(wAnd) or op.id == ord(wOr) or op.s == "|":
        checkSonsLen(n, 3, c.config)
        var
          t1 = semTypeNode(c, n[1], nil)
          t2 = semTypeNode(c, n[2], nil)
        if t1 == nil:
          localError(c.config, n[1].info, errTypeExpected)
          result = newOrPrevType(tyError, prev, c)
        elif t2 == nil:
          localError(c.config, n[2].info, errTypeExpected)
          result = newOrPrevType(tyError, prev, c)
        else:
          result = if op.id == ord(wAnd): makeAndType(c, t1, t2)
                   else: makeOrType(c, t1, t2)
      elif op.id == ord(wNot):
        case n.len
        of 3:
          result = semTypeNode(c, n[1], prev)
          if result.kind == tyTypeDesc and tfUnresolved notin result.flags:
            result = result.base
          if n[2].kind != nkNilLit:
            localError(c.config, n.info,
              "Invalid syntax. When used with a type, 'not' can be followed only by 'nil'")
          if notnil notin c.features and strictNotNil notin c.features:
            localError(c.config, n.info,
              "enable the 'not nil' annotation with {.experimental: \"notnil\".} or " &
              "  the `strict not nil` annotation with {.experimental: \"strictNotNil\".} " &
              "  the \"notnil\" one is going to be deprecated, so please use \"strictNotNil\"")
          let resolvedType = result.skipTypes({tyGenericInst, tyAlias, tySink, tyOwned})
          case resolvedType.kind
          of tyGenericParam, tyTypeDesc, tyFromExpr:
            # XXX: This is a really inappropraite hack, but it solves
            # https://github.com/nim-lang/Nim/issues/4907 for now.
            #
            # A proper solution is to introduce a new type kind such
            # as `tyNotNil[tyRef[SomeGenericParam]]`. This will allow
            # semtypinst to replace the generic param correctly in
            # situations like the following:
            #
            # type Foo[T] = object
            #   bar: ref T not nil
            #   baz: ref T
            #
            # The root of the problem is that `T` here must have a specific
            # ID that is bound to a concrete type during instantiation.
            # The use of `freshType` below breaks this. Another hack would
            # be to reuse the same ID for the not nil type, but this will
            # fail if the `T` parameter is referenced multiple times as in
            # the example above.
            #
            # I suggest revisiting this once the language decides on whether
            # `not nil` should be the default. We can then map nilable refs
            # to other types such as `Option[T]`.
            result = makeTypeFromExpr(c, newTree(nkStmtListType, n.copyTree))
          of NilableTypes + {tyGenericInvocation, tyForward}:
            result = freshType(c, result, prev)
            result.flags.incl(tfNotNil)
          else:
            localError(c.config, n.info, errGenerated, "invalid type")
        of 2:
          let negated = semTypeNode(c, n[1], prev)
          result = makeNotType(c, negated)
        else:
          localError(c.config, n.info, errGenerated, "invalid type")
      elif op.id == ord(wPtr):
        result = semAnyRef(c, n, tyPtr, prev)
      elif op.id == ord(wRef):
        result = semAnyRef(c, n, tyRef, prev)
      elif op.id == ord(wType):
        checkSonsLen(n, 2, c.config)
        result = semTypeOf(c, n[1], prev)
      elif op.s == "typeof" and (
          (n[0].kind == nkSym and n[0].sym.magic == mTypeOf) or
          (n[0].kind == nkOpenSym and n[0][0].sym.magic == mTypeOf)):
        result = semTypeOf2(c, n, prev)
      elif op.s == "owned" and optOwnedRefs notin c.config.globalOptions and n.len == 2:
        result = semTypeExpr(c, n[1], prev)
      else:
        result = semTypeExpr(c, n, prev)
  of nkWhenStmt:
    var whenResult = semWhen(c, n, false)
    if whenResult.kind == nkStmtList: whenResult.transitionSonsKind(nkStmtListType)
    if whenResult.kind == nkWhenStmt:
      result = whenResult.typ
    else:
      result = semTypeNode(c, whenResult, prev)
  of nkBracketExpr:
    checkMinSonsLen(n, 2, c.config)
    var head = n[0]
    var s = if head.kind notin nkCallKinds: semTypeIdent(c, head)
            else: symFromExpectedTypeNode(c, semExpr(c, head))
    case s.magic
    of mArray: result = semArray(c, n, prev)
    of mOpenArray: result = semContainer(c, n, tyOpenArray, "openarray", prev)
    of mUncheckedArray: result = semContainer(c, n, tyUncheckedArray, "UncheckedArray", prev)
    of mRange: result = semRange(c, n, prev)
    of mSet: result = semSet(c, n, prev)
    of mOrdinal: result = semOrdinal(c, n, prev)
    of mIterableType: result = semIterableType(c, n, prev)
    of mSeq:
      result = semContainer(c, n, tySequence, "seq", prev)
      if optSeqDestructors in c.config.globalOptions:
        incl result.flags, tfHasAsgn
    of mVarargs: result = semVarargs(c, n, prev)
    of mTypeDesc, mType, mTypeOf:
      result = makeTypeDesc(c, semTypeNode(c, n[1], nil))
      result.flags.incl tfExplicit
    of mStatic:
      result = semStaticType(c, n[1], prev)
    of mExpr:
      result = semTypeNode(c, n[0], nil)
      if result != nil:
        let old = result
        result = copyType(result, c.idgen, getCurrOwner(c))
        copyTypeProps(c.graph, c.idgen.module, result, old)
        for i in 1..<n.len:
          result.rawAddSon(semTypeNode(c, n[i], nil))
    of mDistinct:
      result = newOrPrevType(tyDistinct, prev, c)
      addSonSkipIntLit(result, semTypeNode(c, n[1], nil), c.idgen)
    of mVar:
      result = newOrPrevType(tyVar, prev, c)
      var base = semTypeNode(c, n[1], nil)
      if base.kind in {tyVar, tyLent}:
        localError(c.config, n.info, "type 'var var' is not allowed")
        base = base[0]
      addSonSkipIntLit(result, base, c.idgen)
    of mRef: result = semAnyRef(c, n, tyRef, prev)
    of mPtr: result = semAnyRef(c, n, tyPtr, prev)
    of mTuple: result = semTuple(c, n, prev)
    of mBuiltinType:
      case s.name.s
      of "lent": result = semAnyRef(c, n, tyLent, prev)
      of "sink": result = semAnyRef(c, n, tySink, prev)
      of "owned": result = semAnyRef(c, n, tyOwned, prev)
      else: result = semGeneric(c, n, s, prev)
    else: result = semGeneric(c, n, s, prev)
  of nkDotExpr:
    let typeExpr = semExpr(c, n)
    if typeExpr.typ.isNil:
      localError(c.config, n.info, "object constructor needs an object type;" &
          " for named arguments use '=' instead of ':'")
      result = errorType(c)
    elif typeExpr.typ.kind == tyFromExpr:
      result = typeExpr.typ
    elif typeExpr.typ.kind != tyTypeDesc:
      localError(c.config, n.info, errTypeExpected)
      result = errorType(c)
    else:
      result = typeExpr.typ.base
      if result.isMetaType and
         result.kind != tyUserTypeClass:
           # the dot expression may refer to a concept type in
           # a different module. allow a normal alias then.
        let preprocessed = semGenericStmt(c, n)
        result = makeTypeFromExpr(c, preprocessed.copyTree)
      else:
        let alias = maybeAliasType(c, result, prev)
        if alias != nil: result = alias
  of nkIdent, nkAccQuoted:
    var s = semTypeIdent(c, n)
    if s.typ == nil:
      if s.kind != skError: localError(c.config, n.info, errTypeExpected)
      result = newOrPrevType(tyError, prev, c)
    elif s.kind == skParam and s.typ.kind == tyTypeDesc:
      internalAssert c.config, s.typ.base.kind != tyNone
      result = s.typ.base
    elif prev == nil:
      result = s.typ
    else:
      let alias = maybeAliasType(c, s.typ, prev)
      if alias != nil:
        result = alias
      elif prev.kind == tyGenericBody:
        result = s.typ
      else:
        assignType(prev, s.typ)
        # bugfix: keep the fresh id for aliases to integral types:
        if s.typ.kind notin {tyBool, tyChar, tyInt..tyInt64, tyFloat..tyFloat128,
                             tyUInt..tyUInt64}:
          prev.itemId = s.typ.itemId
        result = prev
  of nkSym:
    let s = getGenSym(c, n.sym)
    if s.typ != nil and (s.kind == skType or s.typ.kind == tyTypeDesc):
      var t =
        if s.kind == skType:
          s.typ
        else:
          internalAssert c.config, s.typ.base.kind != tyNone
          s.typ.base
      let alias = maybeAliasType(c, t, prev)
      if alias != nil:
        result = alias
      elif prev == nil or prev.kind == tyGenericBody:
        result = t
      else:
        assignType(prev, t)
        result = prev
      markUsed(c, n.info, n.sym)
      onUse(n.info, n.sym)
    else:
      if s.kind != skError:
        if s.typ == nil:
          localError(c.config, n.info, "type expected, but symbol '$1' has no type." % [s.name.s])
        else:
          localError(c.config, n.info, "type expected, but got symbol '$1' of kind '$2'" %
            [s.name.s, s.kind.toHumanStr])
      result = newOrPrevType(tyError, prev, c)
  of nkObjectTy: result = semObjectNode(c, n, prev, {})
  of nkTupleTy: result = semTuple(c, n, prev)
  of nkTupleClassTy: result = newConstraint(c, tyTuple)
  of nkTypeClassTy: result = semTypeClass(c, n, prev)
  of nkRefTy: result = semAnyRef(c, n, tyRef, prev)
  of nkPtrTy: result = semAnyRef(c, n, tyPtr, prev)
  of nkVarTy: result = semVarOutType(c, n, prev, {})
  of nkOutTy: result = semVarOutType(c, n, prev, {tfIsOutParam})
  of nkDistinctTy: result = semDistinct(c, n, prev)
  of nkStaticTy: result = semStaticType(c, n[0], prev)
  of nkProcTy, nkIteratorTy:
    if n.len == 0 or n[0].kind == nkEmpty:
      # 0 length or empty param list with possible pragmas imply typeclass
      result = newTypeS(tyBuiltInTypeClass, c)
      let child = newTypeS(tyProc, c)
      if n.kind == nkIteratorTy:
        child.flags.incl tfIterator
      if n.len > 0 and n[1].kind != nkEmpty and n[1].len > 0:
        # typeclass with pragma
        let symKind = if n.kind == nkIteratorTy: skIterator else: skProc
        # dummy symbol for `pragma`:
        var s = newSymS(symKind, newIdentNode(getIdent(c.cache, "dummy"), n.info), c)
        s.typ = child
        # for now only call convention pragmas supported in proc typeclass
        pragma(c, s, n[1], {FirstCallConv..LastCallConv})
      result.addSonSkipIntLit(child, c.idgen)
    else:
      let symKind = if n.kind == nkIteratorTy: skIterator else: skProc
      result = semProcTypeWithScope(c, n, prev, symKind)
      if result == nil:
        localError(c.config, n.info, "type expected, but got: " & renderTree(n))
        result = newOrPrevType(tyError, prev, c)

      if n.kind == nkIteratorTy and result.kind == tyProc:
        result.flags.incl(tfIterator)
      if result.callConv == ccClosure and c.config.selectedGC in {gcArc, gcOrc, gcAtomicArc}:
        result.flags.incl tfHasAsgn
  of nkEnumTy: result = semEnum(c, n, prev)
  of nkType: result = n.typ
  of nkStmtListType: result = semStmtListType(c, n, prev)
  of nkBlockType: result = semBlockType(c, n, prev)
  of nkOpenSym: result = semTypeNode(c, n[0], prev)
  else:
    result = semTypeExpr(c, n, prev)
    when false:
      localError(c.config, n.info, "type expected, but got: " & renderTree(n))
      result = newOrPrevType(tyError, prev, c)
  n.typ() = result
  dec c.inTypeContext

proc setMagicType(conf: ConfigRef; m: PSym, kind: TTypeKind, size: int) =
  # source : https://en.wikipedia.org/wiki/Data_structure_alignment#x86
  m.typ.kind = kind
  m.typ.size = size
  # this usually works for most basic types
  # Assuming that since ARM, ARM64  don't support unaligned access
  # data is aligned to type size
  m.typ.align = size.int16

  # FIXME: proper support for clongdouble should be added.
  # long double size can be 8, 10, 12, 16 bytes depending on platform & compiler
  if kind in {tyFloat64, tyFloat, tyInt, tyUInt, tyInt64, tyUInt64} and size == 8:
    m.typ.align = int16(conf.floatInt64Align)

proc setMagicIntegral(conf: ConfigRef; m: PSym, kind: TTypeKind, size: int) =
  setMagicType(conf, m, kind, size)
  incl m.typ.flags, tfCheckedForDestructor

proc processMagicType(c: PContext, m: PSym) =
  case m.magic
  of mInt: setMagicIntegral(c.config, m, tyInt, c.config.target.intSize)
  of mInt8: setMagicIntegral(c.config, m, tyInt8, 1)
  of mInt16: setMagicIntegral(c.config, m, tyInt16, 2)
  of mInt32: setMagicIntegral(c.config, m, tyInt32, 4)
  of mInt64: setMagicIntegral(c.config, m, tyInt64, 8)
  of mUInt: setMagicIntegral(c.config, m, tyUInt, c.config.target.intSize)
  of mUInt8: setMagicIntegral(c.config, m, tyUInt8, 1)
  of mUInt16: setMagicIntegral(c.config, m, tyUInt16, 2)
  of mUInt32: setMagicIntegral(c.config, m, tyUInt32, 4)
  of mUInt64: setMagicIntegral(c.config, m, tyUInt64, 8)
  of mFloat: setMagicIntegral(c.config, m, tyFloat, c.config.target.floatSize)
  of mFloat32: setMagicIntegral(c.config, m, tyFloat32, 4)
  of mFloat64: setMagicIntegral(c.config, m, tyFloat64, 8)
  of mFloat128: setMagicIntegral(c.config, m, tyFloat128, 16)
  of mBool: setMagicIntegral(c.config, m, tyBool, 1)
  of mChar: setMagicIntegral(c.config, m, tyChar, 1)
  of mString:
    setMagicType(c.config, m, tyString, szUncomputedSize)
    rawAddSon(m.typ, getSysType(c.graph, m.info, tyChar))
    if optSeqDestructors in c.config.globalOptions:
      incl m.typ.flags, tfHasAsgn
  of mCstring:
    setMagicIntegral(c.config, m, tyCstring, c.config.target.ptrSize)
    rawAddSon(m.typ, getSysType(c.graph, m.info, tyChar))
  of mPointer: setMagicIntegral(c.config, m, tyPointer, c.config.target.ptrSize)
  of mNil: setMagicType(c.config, m, tyNil, c.config.target.ptrSize)
  of mExpr:
    if m.name.s == "auto":
      setMagicIntegral(c.config, m, tyAnything, 0)
    else:
      setMagicIntegral(c.config, m, tyUntyped, 0)
  of mStmt:
    setMagicIntegral(c.config, m, tyTyped, 0)
  of mTypeDesc, mType:
    setMagicIntegral(c.config, m, tyTypeDesc, 0)
    rawAddSon(m.typ, newTypeS(tyNone, c))
  of mStatic:
    setMagicType(c.config, m, tyStatic, 0)
    rawAddSon(m.typ, newTypeS(tyNone, c))
  of mVoidType:
    setMagicIntegral(c.config, m, tyVoid, 0)
  of mArray:
    setMagicType(c.config, m, tyArray, szUncomputedSize)
  of mOpenArray:
    setMagicType(c.config, m, tyOpenArray, szUncomputedSize)
  of mVarargs:
    setMagicType(c.config, m, tyVarargs, szUncomputedSize)
  of mRange:
    setMagicIntegral(c.config, m, tyRange, szUncomputedSize)
    rawAddSon(m.typ, newTypeS(tyNone, c))
  of mSet:
    setMagicIntegral(c.config, m, tySet, szUncomputedSize)
  of mUncheckedArray:
    setMagicIntegral(c.config, m, tyUncheckedArray, szUncomputedSize)
  of mSeq:
    setMagicType(c.config, m, tySequence, szUncomputedSize)
    if optSeqDestructors in c.config.globalOptions:
      incl m.typ.flags, tfHasAsgn
    if defined(nimsuggest) or c.config.cmd == cmdCheck: # bug #18985
      discard
    else:
      assert c.graph.sysTypes[tySequence] == nil
    c.graph.sysTypes[tySequence] = m.typ
  of mOrdinal:
    setMagicIntegral(c.config, m, tyOrdinal, szUncomputedSize)
    rawAddSon(m.typ, newTypeS(tyNone, c))
  of mIterableType:
    setMagicIntegral(c.config, m, tyIterable, 0)
    rawAddSon(m.typ, newTypeS(tyNone, c))
  of mPNimrodNode:
    incl m.typ.flags, tfTriggersCompileTime
    incl m.typ.flags, tfCheckedForDestructor
  of mException: discard
  of mBuiltinType:
    case m.name.s
    of "lent": setMagicType(c.config, m, tyLent, c.config.target.ptrSize)
    of "sink": setMagicType(c.config, m, tySink, szUncomputedSize)
    of "owned":
      setMagicType(c.config, m, tyOwned, c.config.target.ptrSize)
      incl m.typ.flags, tfHasOwned
    else: localError(c.config, m.info, errTypeExpected)
  else: localError(c.config, m.info, errTypeExpected)

proc semGenericConstraints(c: PContext, x: PType): PType =
  result = newTypeS(tyGenericParam, c, x)

proc semGenericParamList(c: PContext, n: PNode, father: PType = nil): PNode =

  template addSym(result: PNode, s: PSym): untyped =
    if father != nil: addSonSkipIntLit(father, s.typ, c.idgen)
    if sfGenSym notin s.flags: addDecl(c, s)
    result.add newSymNode(s)

  result = copyNode(n)
  if n.kind != nkGenericParams:
    illFormedAst(n, c.config)
    return
  for i in 0..<n.len:
    var a = n[i]
    case a.kind
    of nkSym: result.addSym(a.sym)
    of nkIdentDefs:
      var def = a[^1]
      let constraint = a[^2]
      var typ: PType = nil

      if constraint.kind != nkEmpty:
        typ = semTypeNode(c, constraint, nil)
        if typ.kind != tyStatic or typ.len == 0:
          if typ.kind == tyTypeDesc:
            if typ.elementType.kind == tyNone:
              typ = newTypeS(tyTypeDesc, c, newTypeS(tyNone, c))
              incl typ.flags, tfCheckedForDestructor
          else:
            typ = semGenericConstraints(c, typ)

      if def.kind != nkEmpty:
        def = semConstExpr(c, def)
        if typ == nil:
          if def.typ.kind != tyTypeDesc:
            typ = newTypeS(tyStatic, c, def.typ)
        else:
          # the following line fixes ``TV2*[T:SomeNumber=TR] = array[0..1, T]``
          # from manyloc/named_argument_bug/triengine:
          def.typ() = def.typ.skipTypes({tyTypeDesc})
          if not containsGenericType(def.typ):
            def = fitNode(c, typ, def, def.info)

      if typ == nil:
        typ = newTypeS(tyGenericParam, c)
        if father == nil: typ.flags.incl tfWildcard

      typ.flags.incl tfGenericTypeParam

      for j in 0..<a.len-2:
        var finalType: PType
        if j == 0:
          finalType = typ
        else:
          finalType = copyType(typ, c.idgen, typ.owner)
          copyTypeProps(c.graph, c.idgen.module, finalType, typ)
        # it's important the we create an unique
        # type for each generic param. the index
        # of the parameter will be stored in the
        # attached symbol.
        var paramName = a[j]
        var covarianceFlag = tfUnresolved

        if paramName.safeLen == 2:
          if not nimEnableCovariance or paramName[0].ident.s == "in":
            if father == nil or sfImportc notin father.sym.flags:
              localError(c.config, paramName.info, errInOutFlagNotExtern % $paramName[0])
          covarianceFlag = if paramName[0].ident.s == "in": tfContravariant
                          else: tfCovariant
          if father != nil: father.flags.incl tfCovariant
          paramName = paramName[1]

        var s = if finalType.kind == tyStatic or tfWildcard in typ.flags:
            newSymG(skGenericParam, paramName, c).linkTo(finalType)
          else:
            newSymG(skType, paramName, c).linkTo(finalType)

        if covarianceFlag != tfUnresolved: s.typ.flags.incl(covarianceFlag)
        if def.kind != nkEmpty: s.ast = def
        s.position = result.len
        result.addSym(s)
    else:
      illFormedAst(n, c.config)

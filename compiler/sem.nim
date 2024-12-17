#
#
#           The Nim Compiler
#        (c) Copyright 2013 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# This module implements the semantic checking pass.

import
  ast, options, astalgo, trees,
  wordrecg, ropes, msgs, idents, renderer, types, platform,
  magicsys, nversion, nimsets, semfold, modulepaths, importer,
  procfind, lookups, pragmas, semdata, semtypinst, sigmatch,
  transf, vmdef, vm, aliases, cgmeth, lambdalifting,
  evaltempl, patterns, parampatterns, sempass2, linter, semmacrosanity,
  lowerings, plugins/active, lineinfos, int128,
  isolation_check, typeallowed, modulegraphs, enumtostr, concepts, astmsgs,
  extccomp, layeredtable

import vtables
import std/[strtabs, math, tables, intsets, strutils, packedsets]

when not defined(leanCompiler):
  import spawn

when defined(nimPreviewSlimSystem):
  import std/[
    formatfloat,
    assertions,
  ]

# implementation

proc semExpr(c: PContext, n: PNode, flags: TExprFlags = {}, expectedType: PType = nil): PNode
proc semExprWithType(c: PContext, n: PNode, flags: TExprFlags = {}, expectedType: PType = nil): PNode
proc semExprNoType(c: PContext, n: PNode): PNode
proc semExprNoDeref(c: PContext, n: PNode, flags: TExprFlags = {}): PNode
proc semProcBody(c: PContext, n: PNode; expectedType: PType = nil): PNode

proc fitNode(c: PContext, formal: PType, arg: PNode; info: TLineInfo): PNode
proc changeType(c: PContext; n: PNode, newType: PType, check: bool)

proc semTypeNode(c: PContext, n: PNode, prev: PType): PType
proc semStmt(c: PContext, n: PNode; flags: TExprFlags): PNode
proc semOpAux(c: PContext, n: PNode)
proc semParamList(c: PContext, n, genericParams: PNode, s: PSym)
proc addParams(c: PContext, n: PNode, kind: TSymKind)
proc maybeAddResult(c: PContext, s: PSym, n: PNode)
proc tryExpr(c: PContext, n: PNode, flags: TExprFlags = {}): PNode
proc activate(c: PContext, n: PNode)
proc semQuoteAst(c: PContext, n: PNode): PNode
proc finishMethod(c: PContext, s: PSym)
proc evalAtCompileTime(c: PContext, n: PNode): PNode
proc indexTypesMatch(c: PContext, f, a: PType, arg: PNode): PNode
proc semStaticExpr(c: PContext, n: PNode; expectedType: PType = nil): PNode
proc semStaticType(c: PContext, childNode: PNode, prev: PType): PType
proc semTypeOf(c: PContext; n: PNode): PNode
proc computeRequiresInit(c: PContext, t: PType): bool
proc defaultConstructionError(c: PContext, t: PType, info: TLineInfo)
proc hasUnresolvedArgs(c: PContext, n: PNode): bool
proc isArrayConstr(n: PNode): bool {.inline.} =
  result = n.kind == nkBracket and
    n.typ.skipTypes(abstractInst).kind == tyArray

template semIdeForTemplateOrGenericCheck(conf, n, requiresCheck) =
  # we check quickly if the node is where the cursor is
  when defined(nimsuggest):
    if n.info.fileIndex == conf.m.trackPos.fileIndex and n.info.line == conf.m.trackPos.line:
      requiresCheck = true

template semIdeForTemplateOrGeneric(c: PContext; n: PNode;
                                    requiresCheck: bool) =
  # use only for idetools support; this is pretty slow so generics and
  # templates perform some quick check whether the cursor is actually in
  # the generic or template.
  when defined(nimsuggest):
    if c.config.cmd == cmdIdeTools and requiresCheck:
      #if optIdeDebug in gGlobalOptions:
      #  echo "passing to safeSemExpr: ", renderTree(n)
      discard safeSemExpr(c, n)

proc fitNodePostMatch(c: PContext, formal: PType, arg: PNode): PNode =
  let x = arg.skipConv
  if (x.kind == nkCurly and formal.kind == tySet and formal.base.kind != tyGenericParam) or
    (x.kind in {nkPar, nkTupleConstr}) and formal.kind notin {tyUntyped, tyBuiltInTypeClass, tyAnything}:
    changeType(c, x, formal, check=true)
  result = arg
  result = skipHiddenSubConv(result, c.graph, c.idgen)
  # mark inserted converter as used:
  var a = result
  if a.kind == nkHiddenDeref: a = a[0]
  if a.kind == nkHiddenCallConv and a[0].kind == nkSym:
    markUsed(c, a.info, a[0].sym)


proc fitNode(c: PContext, formal: PType, arg: PNode; info: TLineInfo): PNode =
  if arg.typ.isNil:
    localError(c.config, arg.info, "expression has no type: " &
               renderTree(arg, {renderNoComments}))
    # error correction:
    result = copyTree(arg)
    result.typ() = formal
  elif arg.kind in nkSymChoices and formal.skipTypes(abstractInst).kind == tyEnum:
    # Pick the right 'sym' from the sym choice by looking at 'formal' type:
    result = nil
    for ch in arg:
      if sameType(ch.typ, formal):
        return ch
    typeMismatch(c.config, info, formal, arg.typ, arg)
  else:
    result = indexTypesMatch(c, formal, arg.typ, arg)
    if result == nil:
      typeMismatch(c.config, info, formal, arg.typ, arg)
      # error correction:
      result = copyTree(arg)
      result.typ() = formal
    else:
      result = fitNodePostMatch(c, formal, result)

proc fitNodeConsiderViewType(c: PContext, formal: PType, arg: PNode; info: TLineInfo): PNode =
  let a = fitNode(c, formal, arg, info)
  if formal.kind in {tyVar, tyLent}:
    #classifyViewType(formal) != noView:
    result = newNodeIT(nkHiddenAddr, a.info, formal)
    result.add a
    formal.flags.incl tfVarIsPtr
  else:
   result = a

proc inferWithMetatype(c: PContext, formal: PType,
                       arg: PNode, coerceDistincts = false): PNode

template commonTypeBegin*(): PType = PType(kind: tyUntyped)

proc commonType*(c: PContext; x, y: PType): PType =
  # new type relation that is used for array constructors,
  # if expressions, etc.:
  if x == nil: return x
  if y == nil: return y
  var a = skipTypes(x, {tyGenericInst, tyAlias, tySink})
  var b = skipTypes(y, {tyGenericInst, tyAlias, tySink})
  result = x
  if a.kind in {tyUntyped, tyNil}: result = y
  elif b.kind in {tyUntyped, tyNil}: result = x
  elif a.kind == tyTyped: result = a
  elif b.kind == tyTyped: result = b
  elif a.kind == tyTypeDesc:
    # turn any concrete typedesc into the abstract typedesc type
    if not a.hasElementType: result = a
    else:
      result = newType(tyTypeDesc, c.idgen, a.owner)
      rawAddSon(result, newType(tyNone, c.idgen, a.owner))
  elif b.kind in {tyArray, tySet, tySequence} and
      a.kind == b.kind:
    # check for seq[empty] vs. seq[int]
    let idx = ord(b.kind == tyArray)
    if a[idx].kind == tyEmpty: return y
  elif a.kind == tyTuple and b.kind == tyTuple and sameTupleLengths(a, b):
    var nt: PType = nil
    for i, aa, bb in tupleTypePairs(a, b):
      let aEmpty = isEmptyContainer(aa)
      let bEmpty = isEmptyContainer(bb)
      if aEmpty != bEmpty:
        if nt.isNil:
          nt = copyType(a, c.idgen, a.owner)
          copyTypeProps(c.graph, c.idgen.module, nt, a)

        nt[i] = if aEmpty: bb else: aa
    if not nt.isNil: result = nt
    #elif b[idx].kind == tyEmpty: return x
  elif a.kind == tyRange and b.kind == tyRange:
    # consider:  (range[0..3], range[0..4]) here. We should make that
    # range[0..4]. But then why is (range[0..4], 6) not range[0..6]?
    # But then why is (2,4) not range[2..4]? But I think this would break
    # too much code. So ... it's the same range or the base type. This means
    #  typeof(if b: 0 else 1) == int and not range[0..1]. For now. In the long
    # run people expect ranges to work properly within a tuple.
    if not sameType(a, b):
      result = skipTypes(a, {tyRange}).skipIntLit(c.idgen)
    when false:
      if a.kind != tyRange and b.kind == tyRange:
        # XXX This really needs a better solution, but a proper fix now breaks
        # code.
        result = a #.skipIntLit
      elif a.kind == tyRange and b.kind != tyRange:
        result = b #.skipIntLit
      elif a.kind in IntegralTypes and a.n != nil:
        result = a #.skipIntLit
  elif a.kind == tyProc and b.kind == tyProc:
    if a.callConv == ccClosure and b.callConv != ccClosure:
      result = x
    elif compatibleEffects(a, b) != efCompat or
        (b.flags * {tfNoSideEffect, tfGcSafe}) < (a.flags * {tfNoSideEffect, tfGcSafe}):
      result = y
  else:
    var k = tyNone
    if a.kind in {tyRef, tyPtr}:
      k = a.kind
      if b.kind != a.kind: return x
      # bug #7601, array construction of ptr generic
      a = a.elementType.skipTypes({tyGenericInst})
      b = b.elementType.skipTypes({tyGenericInst})
    if a.kind == tyObject and b.kind == tyObject:
      result = commonSuperclass(a, b)
      # this will trigger an error later:
      if result.isNil or result == a: return x
      if result == b: return y
      # bug #7906, tyRef/tyPtr + tyGenericInst of ref/ptr object ->
      # ill-formed AST, no need for additional tyRef/tyPtr
      if k != tyNone and x.kind != tyGenericInst:
        let r = result
        result = newType(k, c.idgen, r.owner)
        result.addSonSkipIntLit(r, c.idgen)

const shouldChckCovered = {tyInt..tyInt64, tyChar, tyEnum, tyUInt..tyUInt64, tyBool}
proc shouldCheckCaseCovered(caseTyp: PType): bool =
  result = false
  case caseTyp.kind
  of shouldChckCovered:
    result = true
  of tyRange:
    if skipTypes(caseTyp[0], abstractInst).kind in shouldChckCovered:
      result = true
  else:
    discard

proc endsInNoReturn(n: PNode): bool

proc commonType*(c: PContext; x: PType, y: PNode): PType =
  # ignore exception raising branches in case/if expressions
  if endsInNoReturn(y): return x
  commonType(c, x, y.typ)

proc newSymS(kind: TSymKind, n: PNode, c: PContext): PSym =
  result = newSym(kind, considerQuotedIdent(c, n), c.idgen, getCurrOwner(c), n.info)
  when defined(nimsuggest):
    suggestDecl(c, n, result)

proc newSymG*(kind: TSymKind, n: PNode, c: PContext): PSym =
  # like newSymS, but considers gensym'ed symbols
  if n.kind == nkSym:
    # and sfGenSym in n.sym.flags:
    result = n.sym
    if result.kind notin {kind, skTemp}:
      localError(c.config, n.info, "cannot use symbol of kind '$1' as a '$2'" %
        [result.kind.toHumanStr, kind.toHumanStr])
    when false:
      if sfGenSym in result.flags and result.kind notin {skTemplate, skMacro, skParam}:
        # declarative context, so produce a fresh gensym:
        result = copySym(result)
        result.ast = n.sym.ast
        put(c.p, n.sym, result)
    # when there is a nested proc inside a template, semtmpl
    # will assign a wrong owner during the first pass over the
    # template; we must fix it here: see #909
    setOwner(result, getCurrOwner(c))
  else:
    result = newSym(kind, considerQuotedIdent(c, n), c.idgen, getCurrOwner(c), n.info)
    if find(result.name.s, '`') >= 0:
      result.flags.incl sfWasGenSym
  #if kind in {skForVar, skLet, skVar} and result.owner.kind == skModule:
  #  incl(result.flags, sfGlobal)
  when defined(nimsuggest):
    suggestDecl(c, n, result)

proc semIdentVis(c: PContext, kind: TSymKind, n: PNode,
                 allowed: TSymFlags): PSym
  # identifier with visibility
proc semIdentWithPragma(c: PContext, kind: TSymKind, n: PNode,
                        allowed: TSymFlags, fromTopLevel = false): PSym

proc typeAllowedCheck(c: PContext; info: TLineInfo; typ: PType; kind: TSymKind;
                      flags: TTypeAllowedFlags = {}) =
  let t = typeAllowed(typ, kind, c, flags)
  if t != nil:
    var err: string
    if t == typ:
      err = "invalid type: '$1' for $2" % [typeToString(typ), toHumanStr(kind)]
      if kind in {skVar, skLet, skConst} and taIsTemplateOrMacro in flags:
        err &= ". Did you mean to call the $1 with '()'?" % [toHumanStr(typ.owner.kind)]
    else:
      err = "invalid type: '$1' in this context: '$2' for $3" % [typeToString(t),
              typeToString(typ), toHumanStr(kind)]
    localError(c.config, info, err)

proc paramsTypeCheck(c: PContext, typ: PType) {.inline.} =
  typeAllowedCheck(c, typ.n.info, typ, skProc)

proc expectMacroOrTemplateCall(c: PContext, n: PNode): PSym
proc semDirectOp(c: PContext, n: PNode, flags: TExprFlags; expectedType: PType = nil): PNode
proc semWhen(c: PContext, n: PNode, semCheck: bool = true): PNode
proc semTemplateExpr(c: PContext, n: PNode, s: PSym,
                     flags: TExprFlags = {}; expectedType: PType = nil): PNode
proc semMacroExpr(c: PContext, n, nOrig: PNode, sym: PSym,
                  flags: TExprFlags = {}; expectedType: PType = nil): PNode

when false:
  proc createEvalContext(c: PContext, mode: TEvalMode): PEvalContext =
    result = newEvalContext(c.module, mode)
    result.getType = proc (n: PNode): PNode =
      result = tryExpr(c, n)
      if result == nil:
        result = newSymNode(errorSym(c, n))
      elif result.typ == nil:
        result = newSymNode(getSysSym"void")
      else:
        result.typ = makeTypeDesc(c, result.typ)

    result.handleIsOperator = proc (n: PNode): PNode =
      result = isOpImpl(c, n)

proc hasCycle(n: PNode): bool =
  result = false
  incl n.flags, nfNone
  for i in 0..<n.safeLen:
    if nfNone in n[i].flags or hasCycle(n[i]):
      result = true
      break
  excl n.flags, nfNone

proc fixupTypeAfterEval(c: PContext, evaluated, eOrig: PNode): PNode =
  # recompute the types as 'eval' isn't guaranteed to construct types nor
  # that the types are sound:
  when true:
    if eOrig.typ.kind in {tyUntyped, tyTyped, tyTypeDesc}:
      result = semExprWithType(c, evaluated)
    else:
      result = evaluated
      let expectedType = eOrig.typ.skipTypes({tyStatic})
      if hasCycle(result):
        result = localErrorNode(c, eOrig, "the resulting AST is cyclic and cannot be processed further")
      else:
        semmacrosanity.annotateType(result, expectedType, c.config)
  else:
    result = semExprWithType(c, evaluated)
    #result = fitNode(c, e.typ, result) inlined with special case:
    let arg = result
    result = indexTypesMatch(c, eOrig.typ, arg.typ, arg)
    if result == nil:
      result = arg
      # for 'tcnstseq' we support [] to become 'seq'
      if eOrig.typ.skipTypes(abstractInst).kind == tySequence and
         isArrayConstr(arg):
        arg.typ = eOrig.typ

proc tryConstExpr(c: PContext, n: PNode; expectedType: PType = nil): PNode =
  var e = semExprWithType(c, n, expectedType = expectedType)
  if e == nil: return

  result = getConstExpr(c.module, e, c.idgen, c.graph)
  if result != nil: return

  let oldErrorCount = c.config.errorCounter
  let oldErrorMax = c.config.errorMax
  let oldErrorOutputs = c.config.m.errorOutputs

  c.config.m.errorOutputs = {}
  c.config.errorMax = high(int) # `setErrorMaxHighMaybe` not appropriate here

  when defined(nimsuggest):
    # Remove the error hook so nimsuggest doesn't report errors there
    let tempHook = c.graph.config.structuredErrorHook
    c.graph.config.structuredErrorHook = nil

  try:
    result = evalConstExpr(c.module, c.idgen, c.graph, e)
    if result == nil or result.kind == nkEmpty:
      result = nil
    else:
      result = fixupTypeAfterEval(c, result, e)

  except ERecoverableError:
    result = nil

  when defined(nimsuggest):
    # Restore the error hook
    c.graph.config.structuredErrorHook = tempHook

  c.config.errorCounter = oldErrorCount
  c.config.errorMax = oldErrorMax
  c.config.m.errorOutputs = oldErrorOutputs

const
  errConstExprExpected = "constant expression expected"

proc semConstExpr(c: PContext, n: PNode; expectedType: PType = nil): PNode =
  var e = semExprWithType(c, n, expectedType = expectedType)
  if e == nil:
    localError(c.config, n.info, errConstExprExpected)
    return n
  if e.kind in nkSymChoices and e[0].typ.skipTypes(abstractInst).kind == tyEnum:
    return e
  result = getConstExpr(c.module, e, c.idgen, c.graph)
  if result == nil:
    #if e.kind == nkEmpty: globalError(n.info, errConstExprExpected)
    result = evalConstExpr(c.module, c.idgen, c.graph, e)
    if result == nil or result.kind == nkEmpty:
      if e.info != n.info:
        pushInfoContext(c.config, n.info)
        localError(c.config, e.info, errConstExprExpected)
        popInfoContext(c.config)
      else:
        localError(c.config, e.info, errConstExprExpected)
      # error correction:
      result = e
    else:
      result = fixupTypeAfterEval(c, result, e)

proc semExprFlagDispatched(c: PContext, n: PNode, flags: TExprFlags; expectedType: PType = nil): PNode =
  if efNeedStatic in flags:
    if efPreferNilResult in flags:
      return tryConstExpr(c, n, expectedType)
    else:
      return semConstExpr(c, n, expectedType)
  else:
    result = semExprWithType(c, n, flags, expectedType)
    if efPreferStatic in flags:
      var evaluated = getConstExpr(c.module, result, c.idgen, c.graph)
      if evaluated != nil: return evaluated
      evaluated = evalAtCompileTime(c, result)
      if evaluated != nil: return evaluated

proc semGenericStmt(c: PContext, n: PNode): PNode

include hlo, seminst, semcall

proc resetSemFlag(n: PNode) =
  if n != nil:
    excl n.flags, nfSem
    for i in 0..<n.safeLen:
      resetSemFlag(n[i])

proc semAfterMacroCall(c: PContext, call, macroResult: PNode,
                       s: PSym, flags: TExprFlags; expectedType: PType = nil): PNode =
  ## Semantically check the output of a macro.
  ## This involves processes such as re-checking the macro output for type
  ## coherence, making sure that variables declared with 'let' aren't
  ## reassigned, and binding the unbound identifiers that the macro output
  ## contains.
  inc(c.config.evalTemplateCounter)
  if c.config.evalTemplateCounter > evalTemplateLimit:
    globalError(c.config, s.info, "template instantiation too nested")
  c.friendModules.add(s.owner.getModule)
  result = macroResult
  resetSemFlag result
  if s.typ.returnType == nil:
    result = semStmt(c, result, flags)
  else:
    var retType = s.typ.returnType
    if retType.kind == tyTypeDesc and tfUnresolved in retType.flags and
        retType.hasElementType:
      # bug #11941: template fails(T: type X, v: auto): T
      # does not mean we expect a tyTypeDesc.
      retType = retType.skipModifier
    case retType.kind
    of tyUntyped, tyAnything:
      # Not expecting a type here allows templates like in ``tmodulealias.in``.
      result = semExpr(c, result, flags, expectedType)
    of tyTyped:
      # More restrictive version.
      result = semExprWithType(c, result, flags, expectedType)
    of tyTypeDesc:
      if result.kind == nkStmtList: result.transitionSonsKind(nkStmtListType)
      var typ = semTypeNode(c, result, nil)
      if typ == nil:
        localError(c.config, result.info, "expression has no type: " &
                   renderTree(result, {renderNoComments}))
        result = newSymNode(errorSym(c, result))
      else:
        result.typ() = makeTypeDesc(c, typ)
      #result = symNodeFromType(c, typ, n.info)
    else:
      if s.ast[genericParamsPos] != nil and retType.isMetaType:
        # The return type may depend on the Macro arguments
        # e.g. template foo(T: typedesc): seq[T]
        # We will instantiate the return type here, because
        # we now know the supplied arguments
        var paramTypes = initLayeredTypeMap()
        for param, value in genericParamsInMacroCall(s, call):
          var givenType = value.typ
          # the sym nodes used for the supplied generic arguments for
          # templates and macros leave type nil so regular sem can handle it
          # in this case, get the type directly from the sym
          if givenType == nil and value.kind == nkSym and value.sym.typ != nil:
            givenType = value.sym.typ
          put(paramTypes, param.typ, givenType)

        retType = generateTypeInstance(c, paramTypes,
                                       macroResult.info, retType)

      if retType.kind == tyVoid:
        result = semStmt(c, result, flags)
      else:
        result = semExpr(c, result, flags)
        result = fitNode(c, retType, result, result.info)
      #globalError(s.info, errInvalidParamKindX, typeToString(s.typ.returnType))
  dec(c.config.evalTemplateCounter)
  discard c.friendModules.pop()

const
  errMissingGenericParamsForTemplate = "'$1' has unspecified generic parameters"

proc semMacroExpr(c: PContext, n, nOrig: PNode, sym: PSym,
                  flags: TExprFlags = {}; expectedType: PType = nil): PNode =
  rememberExpansion(c, nOrig.info, sym)
  pushInfoContext(c.config, nOrig.info, sym.detailedInfo)

  let info = getCallLineInfo(n)
  markUsed(c, info, sym)
  onUse(info, sym)
  if sym == c.p.owner:
    globalError(c.config, info, "recursive dependency: '$1'" % sym.name.s)

  let genericParams = sym.ast[genericParamsPos].len
  let suppliedParams = max(n.safeLen - 1, 0)

  if suppliedParams < genericParams:
    globalError(c.config, info, errMissingGenericParamsForTemplate % n.renderTree)

  #if c.evalContext == nil:
  #  c.evalContext = c.createEvalContext(emStatic)
  result = evalMacroCall(c.module, c.idgen, c.graph, c.templInstCounter, n, nOrig, sym)
  if efNoSemCheck notin flags:
    result = semAfterMacroCall(c, n, result, sym, flags, expectedType)
  if c.config.macrosToExpand.hasKey(sym.name.s):
    message(c.config, nOrig.info, hintExpandMacro, renderTree(result))
  result = wrapInComesFrom(nOrig.info, sym, result)
  popInfoContext(c.config)

proc forceBool(c: PContext, n: PNode): PNode =
  result = fitNode(c, getSysType(c.graph, n.info, tyBool), n, n.info)
  if result == nil: result = n

proc semConstBoolExpr(c: PContext, n: PNode): PNode =
  result = forceBool(c, semConstExpr(c, n, getSysType(c.graph, n.info, tyBool)))
  if result.kind != nkIntLit:
    localError(c.config, n.info, errConstExprExpected)
proc semConceptBody(c: PContext, n: PNode): PNode

include semtypes

proc setGenericParamsMisc(c: PContext; n: PNode) =
  ## used by call defs (procs, templates, macros, ...) to analyse their generic
  ## params, and store the originals in miscPos for better error reporting.
  let orig = n[genericParamsPos]

  doAssert orig.kind in {nkEmpty, nkGenericParams}

  if n[genericParamsPos].kind == nkEmpty:
    n[genericParamsPos] = newNodeI(nkGenericParams, n.info)
  else:
    # we keep the original params around for better error messages, see
    # issue https://github.com/nim-lang/Nim/issues/1713
    n[genericParamsPos] = semGenericParamList(c, orig)

  if n[miscPos].kind == nkEmpty:
    n[miscPos] = newTree(nkBracket, c.graph.emptyNode, orig)
  else:
    n[miscPos][1] = orig

proc caseBranchMatchesExpr(branch, matched: PNode): bool =
  result = false
  for i in 0 ..< branch.len-1:
    if branch[i].kind == nkRange:
      if overlap(branch[i], matched): return true
    elif exprStructuralEquivalent(branch[i], matched):
      return true

proc pickCaseBranchIndex(caseExpr, matched: PNode): int =
  result = 0
  let endsWithElse = caseExpr[^1].kind == nkElse
  for i in 1..<caseExpr.len - endsWithElse.int:
    if caseExpr[i].caseBranchMatchesExpr(matched):
      return i
  if endsWithElse:
    return caseExpr.len - 1

proc defaultFieldsForTheUninitialized(c: PContext, recNode: PNode, checkDefault: bool): seq[PNode]
proc defaultNodeField(c: PContext, a: PNode, aTyp: PType, checkDefault: bool): PNode
proc defaultNodeField(c: PContext, a: PNode, checkDefault: bool): PNode

const defaultFieldsSkipTypes = {tyGenericInst, tyAlias, tySink}

proc defaultFieldsForTuple(c: PContext, recNode: PNode, hasDefault: var bool, checkDefault: bool): seq[PNode] =
  result = @[]
  case recNode.kind
  of nkRecList:
    for field in recNode:
      result.add defaultFieldsForTuple(c, field, hasDefault, checkDefault)
  of nkSym:
    let field = recNode.sym
    let recType = recNode.typ.skipTypes(defaultFieldsSkipTypes)
    if field.ast != nil: #Try to use default value
      hasDefault = true
      result.add newTree(nkExprColonExpr, recNode, field.ast)
    else:
      if recType.kind in {tyObject, tyArray, tyTuple}:
        let asgnExpr = defaultNodeField(c, recNode, recNode.typ, checkDefault)
        if asgnExpr != nil:
          hasDefault = true
          asgnExpr.flags.incl nfSkipFieldChecking
          result.add newTree(nkExprColonExpr, recNode, asgnExpr)
          return

      let asgnType = newType(tyTypeDesc, c.idgen, recNode.typ.owner)
      rawAddSon(asgnType, recNode.typ)
      let asgnExpr = newTree(nkCall,
                      newSymNode(getSysMagic(c.graph, recNode.info, "zeroDefault", mZeroDefault)),
                      newNodeIT(nkType, recNode.info, asgnType)
                    )
      asgnExpr.flags.incl nfSkipFieldChecking
      asgnExpr.typ() = recNode.typ
      result.add newTree(nkExprColonExpr, recNode, asgnExpr)
  else:
    raiseAssert "unreachable"

proc defaultFieldsForTheUninitialized(c: PContext, recNode: PNode, checkDefault: bool): seq[PNode] =
  result = @[]
  case recNode.kind
  of nkRecList:
    for field in recNode:
      result.add defaultFieldsForTheUninitialized(c, field, checkDefault)
  of nkRecCase:
    let discriminator = recNode[0]
    var selectedBranch: int
    var defaultValue = discriminator.sym.ast
    if defaultValue == nil:
      # None of the branches were explicitly selected by the user and no value
      # was given to the discrimator. We can assume that it will be initialized
      # to zero and this will select a particular branch as a result:
      if checkDefault: # don't add defaults when checking whether a case branch has default fields
        return
      defaultValue = newIntNode(nkIntLit#[c.graph]#, 0)
      defaultValue.typ() = discriminator.typ
    selectedBranch = recNode.pickCaseBranchIndex defaultValue
    defaultValue.flags.incl nfSkipFieldChecking
    result.add newTree(nkExprColonExpr, discriminator, defaultValue)
    result.add defaultFieldsForTheUninitialized(c, recNode[selectedBranch][^1], checkDefault)
  of nkSym:
    let field = recNode.sym
    let recType = recNode.typ.skipTypes(defaultFieldsSkipTypes)
    if field.ast != nil: #Try to use default value
      result.add newTree(nkExprColonExpr, recNode, field.ast)
    elif recType.kind in {tyObject, tyArray, tyTuple}:
      let asgnExpr = defaultNodeField(c, recNode, recNode.typ, checkDefault)
      if asgnExpr != nil:
        asgnExpr.typ() = recNode.typ
        asgnExpr.flags.incl nfSkipFieldChecking
        result.add newTree(nkExprColonExpr, recNode, asgnExpr)
  else:
    raiseAssert "unreachable"

proc defaultNodeField(c: PContext, a: PNode, aTyp: PType, checkDefault: bool): PNode =
  let aTypSkip = aTyp.skipTypes(defaultFieldsSkipTypes)
  case aTypSkip.kind
  of tyObject:
    let child = defaultFieldsForTheUninitialized(c, aTypSkip.n, checkDefault)
    if child.len > 0:
      var asgnExpr = newTree(nkObjConstr, newNodeIT(nkType, a.info, aTyp))
      asgnExpr.typ() = aTyp
      asgnExpr.sons.add child
      result = semExpr(c, asgnExpr)
    else:
      result = nil
  of tyArray:
    let child = defaultNodeField(c, a, aTypSkip[1], checkDefault)

    if child != nil:
      let node = newNode(nkIntLit)
      node.intVal = toInt64(lengthOrd(c.graph.config, aTypSkip))
      let typeNode = newNode(nkType)
      typeNode.typ() = makeTypeDesc(c, aTypSkip[1])
      result = semExpr(c, newTree(nkCall, newTree(nkBracketExpr, newSymNode(getSysSym(c.graph, a.info, "arrayWithDefault"), a.info), typeNode),
              node
                ))
      result.typ() = aTyp
    else:
      result = nil
  of tyTuple:
    var hasDefault = false
    if aTypSkip.n != nil:
      let children = defaultFieldsForTuple(c, aTypSkip.n, hasDefault, checkDefault)
      if hasDefault and children.len > 0:
        result = newNodeI(nkTupleConstr, a.info)
        result.typ() = aTyp
        result.sons.add children
        result = semExpr(c, result)
      else:
        result = nil
    else:
      result = nil
  of tyRange:
    if c.graph.config.isDefined("nimPreviewRangeDefault"):
      result = firstRange(c.config, aTypSkip)
    else:
      result = nil
  else:
    result = nil

proc defaultNodeField(c: PContext, a: PNode, checkDefault: bool): PNode =
  result = defaultNodeField(c, a, a.typ, checkDefault)

include semtempl, semgnrc, semstmts, semexprs

proc addCodeForGenerics(c: PContext, n: PNode) =
  for i in c.lastGenericIdx..<c.generics.len:
    var prc = c.generics[i].inst.sym
    if prc.kind in {skProc, skFunc, skMethod, skConverter} and prc.magic == mNone:
      if prc.ast == nil or prc.ast[bodyPos] == nil:
        internalError(c.config, prc.info, "no code for " & prc.name.s)
      else:
        n.add prc.ast
  c.lastGenericIdx = c.generics.len

proc preparePContext*(graph: ModuleGraph; module: PSym; idgen: IdGenerator): PContext =
  result = newContext(graph, module)
  result.idgen = idgen
  result.enforceVoidContext = newType(tyTyped, idgen, nil)
  result.voidType = newType(tyVoid, idgen, nil)

  if result.p != nil: internalError(graph.config, module.info, "sem.preparePContext")
  result.semConstExpr = semConstExpr
  result.semExpr = semExpr
  result.semExprWithType = semExprWithType
  result.semTryExpr = tryExpr
  result.semTryConstExpr = tryConstExpr
  result.computeRequiresInit = computeRequiresInit
  result.semOperand = semOperand
  result.semConstBoolExpr = semConstBoolExpr
  result.semOverloadedCall = semOverloadedCall
  result.semInferredLambda = semInferredLambda
  result.semGenerateInstance = generateInstance
  result.instantiateOnlyProcType = instantiateOnlyProcType
  result.fitDefaultNode = fitDefaultNode
  result.semTypeNode = semTypeNode
  result.instTypeBoundOp = sigmatch.instTypeBoundOp
  result.hasUnresolvedArgs = hasUnresolvedArgs
  result.templInstCounter = new int

  pushProcCon(result, module)
  pushOwner(result, result.module)

  result.moduleScope = openScope(result)
  result.moduleScope.addSym(module) # a module knows itself

  if sfSystemModule in module.flags:
    graph.systemModule = module
  result.topLevelScope = openScope(result)

proc isImportSystemStmt(g: ModuleGraph; n: PNode): bool =
  if g.systemModule == nil: return false
  var n = n
  if n.kind == nkStmtList:
    for i in 0..<n.len-1:
      if n[i].kind notin {nkCommentStmt, nkEmpty}:
        n = n[i]
        break
  case n.kind
  of nkImportStmt:
    result = false
    for x in n:
      if x.kind == nkIdent:
        let f = checkModuleName(g.config, x, false)
        if f == g.systemModule.info.fileIndex:
          return true
  of nkImportExceptStmt, nkFromStmt:
    result = false
    if n[0].kind == nkIdent:
      let f = checkModuleName(g.config, n[0], false)
      if f == g.systemModule.info.fileIndex:
        return true
  else: result = false

proc isEmptyTree(n: PNode): bool =
  case n.kind
  of nkStmtList:
    for it in n:
      if not isEmptyTree(it): return false
    result = true
  of nkEmpty, nkCommentStmt: result = true
  else: result = false

proc semStmtAndGenerateGenerics(c: PContext, n: PNode): PNode =
  if c.topStmts == 0 and not isImportSystemStmt(c.graph, n):
    if sfSystemModule notin c.module.flags and not isEmptyTree(n):
      assert c.graph.systemModule != nil
      c.moduleScope.addSym c.graph.systemModule # import the "System" identifier
      importAllSymbols(c, c.graph.systemModule)
      inc c.topStmts
  else:
    inc c.topStmts
  if sfNoForward in c.module.flags:
    result = semAllTypeSections(c, n)
  else:
    result = n
  result = semStmt(c, result, {})
  when false:
    # Code generators are lazy now and can deal with undeclared procs, so these
    # steps are not required anymore and actually harmful for the upcoming
    # destructor support.
    # BUGFIX: process newly generated generics here, not at the end!
    if c.lastGenericIdx < c.generics.len:
      var a = newNodeI(nkStmtList, n.info)
      addCodeForGenerics(c, a)
      if a.len > 0:
        # a generic has been added to `a`:
        if result.kind != nkEmpty: a.add result
        result = a
  result = hloStmt(c, result)
  if c.config.cmd == cmdInteractive and not isEmptyType(result.typ):
    result = buildEchoStmt(c, result)
  if c.config.cmd == cmdIdeTools:
    appendToModule(c.module, result)
  trackStmt(c, c.module, result, isTopLevel = true)
  if optMultiMethods notin c.config.globalOptions and
      c.config.selectedGC in {gcArc, gcOrc, gcAtomicArc} and
      Feature.vtables in c.config.features:
    sortVTableDispatchers(c.graph)

    if sfMainModule in c.module.flags:
      collectVTableDispatchers(c.graph)

proc recoverContext(c: PContext) =
  # clean up in case of a semantic error: We clean up the stacks, etc. This is
  # faster than wrapping every stack operation in a 'try finally' block and
  # requires far less code.
  c.currentScope = c.topLevelScope
  while getCurrOwner(c).kind != skModule: popOwner(c)
  while c.p != nil and c.p.owner.kind != skModule: c.p = c.p.next

proc semWithPContext*(c: PContext, n: PNode): PNode =
  # no need for an expensive 'try' if we stop after the first error anyway:
  if c.config.errorMax <= 1:
    result = semStmtAndGenerateGenerics(c, n)
  else:
    let oldContextLen = msgs.getInfoContextLen(c.config)
    let oldInGenericInst = c.inGenericInst
    try:
      result = semStmtAndGenerateGenerics(c, n)
    except ERecoverableError, ESuggestDone:
      recoverContext(c)
      c.inGenericInst = oldInGenericInst
      msgs.setInfoContextLen(c.config, oldContextLen)
      if getCurrentException() of ESuggestDone:
        c.suggestionsMade = true
        result = nil
      else:
        result = newNodeI(nkEmpty, n.info)
      #if c.config.cmd == cmdIdeTools: findSuggest(c, n)
  storeRodNode(c, result)


proc reportUnusedModules(c: PContext) =
  if c.config.cmd == cmdM: return
  for (s, info) in c.unusedImports:
    if sfUsed notin s.flags:
      message(c.config, info, warnUnusedImportX, s.name.s)

proc closePContext*(graph: ModuleGraph; c: PContext, n: PNode): PNode =
  if c.config.cmd == cmdIdeTools and not c.suggestionsMade:
    suggestSentinel(c)
  closeScope(c)         # close module's scope
  rawCloseScope(c)      # imported symbols; don't check for unused ones!
  reportUnusedModules(c)
  result = newNode(nkStmtList)
  if n != nil:
    internalError(c.config, n.info, "n is not nil") #result := n;
  addCodeForGenerics(c, result)
  if c.module.ast != nil:
    result.add(c.module.ast)
  popOwner(c)
  popProcCon(c)
  sealRodFile(c)

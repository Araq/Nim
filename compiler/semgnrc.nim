#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# This implements the first pass over the generic body; it resolves some
# symbols. Thus for generics there is a two-phase symbol lookup just like
# in C++.
# A problem is that it cannot be detected if the symbol is introduced
# as in ``var x = ...`` or used because macros/templates can hide this!
# So we have to eval templates/macros right here so that symbol
# lookup can be accurate.

# included from sem.nim

proc getIdentNode(c: PContext; n: PNode): PNode =
  case n.kind
  of nkPostfix: result = getIdentNode(c, n[1])
  of nkPragmaExpr: result = getIdentNode(c, n[0])
  of nkIdent, nkAccQuoted, nkSym: result = n
  else:
    illFormedAst(n, c.config)
    result = n

type
  GenericCtx = object
    toMixin, toBind: IntSet
    cursorInBody: bool # only for nimsuggest
    bracketExpr: PNode

  TSemGenericFlag = enum
    withinBind,
    withinTypeDesc,
    withinMixin,
    withinConcept

  TSemGenericFlags = set[TSemGenericFlag]

proc semGenericStmt(c: PContext, n: PNode,
                    flags: TSemGenericFlags, ctx: var GenericCtx): PNode

proc semGenericStmtScope(c: PContext, n: PNode,
                         flags: TSemGenericFlags,
                         ctx: var GenericCtx): PNode =
  openScope(c)
  result = semGenericStmt(c, n, flags, ctx)
  closeScope(c)

template isMixedIn(sym): bool =
  let s = sym
  s.name.id in ctx.toMixin or (withinConcept in flags and
                               s.magic == mNone and
                               s.kind in OverloadableSyms)

template canOpenSym(s): bool =
  {withinMixin, withinConcept} * flags == {withinMixin} and s.id notin ctx.toBind

proc semGenericStmtSymbol(c: PContext, n: PNode, s: PSym,
                          ctx: var GenericCtx; flags: TSemGenericFlags,
                          isAmbiguous: bool,
                          fromDotExpr=false): PNode =
  result = nil
  semIdeForTemplateOrGenericCheck(c.config, n, ctx.cursorInBody)
  incl(s.flags, sfUsed)
  template maybeDotChoice(c: PContext, n: PNode, s: PSym, fromDotExpr: bool) =
    if fromDotExpr:
      result = symChoice(c, n, s, scForceOpen)
      if result.kind == nkOpenSymChoice and result.len == 1:
        result.transitionSonsKind(nkClosedSymChoice)
    else:
      result = symChoice(c, n, s, scOpen)
      if canOpenSym(s):
        if openSym in c.features:
          if result.kind == nkSym:
            result = newOpenSym(result)
          else:
            result.typ() = nil
        else:
          result.flags.incl nfDisabledOpenSym
          result.typ() = nil
  case s.kind
  of skUnknown:
    # Introduced in this pass! Leave it as an identifier.
    result = n
  of skProc, skFunc, skMethod, skIterator, skConverter, skModule, skEnumField:
    maybeDotChoice(c, n, s, fromDotExpr)
  of skTemplate, skMacro:
    # alias syntax, see semSym for skTemplate, skMacro
    if sfNoalias notin s.flags and not fromDotExpr:
      onUse(n.info, s)
      case s.kind
      of skTemplate: result = semTemplateExpr(c, n, s, {efNoSemCheck})
      of skMacro: result = semMacroExpr(c, n, n, s, {efNoSemCheck})
      else: discard # unreachable
      c.friendModules.add(s.owner.getModule)
      result = semGenericStmt(c, result, {}, ctx)
      discard c.friendModules.pop()
    else:
      maybeDotChoice(c, n, s, fromDotExpr)
  of skGenericParam:
    if s.typ != nil and s.typ.kind == tyStatic:
      if s.typ.n != nil:
        result = s.typ.n
      elif c.inGenericContext > 0 and withinConcept notin flags:
        # don't leave generic param as identifier node in generic type,
        # sigmatch will try to instantiate generic type AST without all params
        # fine to give a symbol node a generic type here since
        # we are in a generic context and `prepareNode` will be called
        result = newSymNodeTypeDesc(s, c.idgen, n.info)
        if canOpenSym(result.sym):
          if openSym in c.features:
            result = newOpenSym(result)
          else:
            result.flags.incl nfDisabledOpenSym
            result.typ() = nil
      else:
        result = n
    else:
      result = newSymNodeTypeDesc(s, c.idgen, n.info)
      if canOpenSym(result.sym):
        if openSym in c.features:
          result = newOpenSym(result)
        else:
          result.flags.incl nfDisabledOpenSym
          result.typ() = nil
    onUse(n.info, s)
  of skParam:
    result = n
    onUse(n.info, s)
  of skType:
    if (s.typ != nil) and
       (s.typ.flags * {tfGenericTypeParam, tfImplicitTypeParam} == {}):
      if isAmbiguous:
        # ambiguous types should be symchoices since lookup behaves
        # differently for them in regular expressions
        maybeDotChoice(c, n, s, fromDotExpr)
        return
      result = newSymNodeTypeDesc(s, c.idgen, n.info)
      if canOpenSym(result.sym):
        if openSym in c.features:
          result = newOpenSym(result)
        else:
          result.flags.incl nfDisabledOpenSym
          result.typ() = nil
    elif c.inGenericContext > 0 and withinConcept notin flags:
      # don't leave generic param as identifier node in generic type,
      # sigmatch will try to instantiate generic type AST without all params
      # fine to give a symbol node a generic type here since
      # we are in a generic context and `prepareNode` will be called
      result = newSymNodeTypeDesc(s, c.idgen, n.info)
      if canOpenSym(result.sym):
        if openSym in c.features:
          result = newOpenSym(result)
        else:
          result.flags.incl nfDisabledOpenSym
          result.typ() = nil
    else:
      result = n
    onUse(n.info, s)
  else:
    result = newSymNode(s, n.info)
    if canOpenSym(result.sym):
      if openSym in c.features:
        result = newOpenSym(result)
      else:
        result.flags.incl nfDisabledOpenSym
        result.typ() = nil
    onUse(n.info, s)

proc lookup(c: PContext, n: PNode, flags: TSemGenericFlags,
            ctx: var GenericCtx): PNode =
  result = n
  let ident = considerQuotedIdent(c, n)
  var amb = false
  var s = searchInScopes(c, ident, amb)
  if s == nil:
    s = strTableGet(c.pureEnumFields, ident)
    #if s != nil and contains(c.ambiguousSymbols, s.id):
    #  s = nil
  if s == nil:
    if ident.id notin ctx.toMixin and withinMixin notin flags:
      errorUndeclaredIdentifier(c, n.info, ident.s)
  else:
    if withinBind in flags or s.id in ctx.toBind:
      result = symChoice(c, n, s, scClosed)
    elif s.isMixedIn:
      result = symChoice(c, n, s, scForceOpen)
    else:
      result = semGenericStmtSymbol(c, n, s, ctx, flags, amb)
  # else: leave as nkIdent

proc newDot(n, b: PNode): PNode =
  result = newNodeI(nkDotExpr, n.info)
  result.add(n[0])
  result.add(b)

proc fuzzyLookup(c: PContext, n: PNode, flags: TSemGenericFlags,
                 ctx: var GenericCtx; isMacro: var bool;
                 inCall = false): PNode =
  assert n.kind == nkDotExpr
  semIdeForTemplateOrGenericCheck(c.config, n, ctx.cursorInBody)

  let luf = if withinMixin notin flags: {checkUndeclared, checkModule} else: {checkModule}

  c.isAmbiguous = false
  var s = qualifiedLookUp(c, n, luf)
  if s != nil:
    isMacro = s.kind in {skTemplate, skMacro}
    result = semGenericStmtSymbol(c, n, s, ctx, flags, c.isAmbiguous)
  else:
    n[0] = semGenericStmt(c, n[0], flags, ctx)
    result = n
    let n = n[1]
    let ident = considerQuotedIdent(c, n)
    # could be type conversion if like a.T and not a.T()
    let symKinds = if inCall: routineKinds else: routineKinds+{skType}
    var candidates = selectFromScopesElseAll(c, ident, symKinds)
    if candidates.len > 0:
      let s = candidates[0] # XXX take into account the other candidates!
      isMacro = s.kind in {skTemplate, skMacro}
      if withinBind in flags or s.id in ctx.toBind:
        if s.kind == skType: # don't put types in sym choice
          var ambig = false
          if candidates.len > 1:
            let s2 = searchInScopes(c, ident, ambig)
          result = newDot(result, semGenericStmtSymbol(c, n, s, ctx, flags,
            isAmbiguous = ambig, fromDotExpr = true))
        else:
          result = newDot(result, symChoice(c, n, s, scClosed))
      elif s.isMixedIn:
        result = newDot(result, symChoice(c, n, s, scForceOpen))
      else:
        var ambig = false
        if s.kind == skType and candidates.len > 1:
          discard searchInScopes(c, ident, ambig)
        let syms = semGenericStmtSymbol(c, n, s, ctx, flags,
          isAmbiguous = ambig, fromDotExpr = true)
        result = newDot(result, syms)

proc addTempDecl(c: PContext; n: PNode; kind: TSymKind) =
  let s = newSymS(skUnknown, getIdentNode(c, n), c)
  addPrelimDecl(c, s)
  styleCheckDef(c, n.info, s, kind)
  onDef(n.info, s)

proc addTempDeclToIdents(c: PContext; n: PNode; kind: TSymKind; inCall: bool) =
  case n.kind 
  of nkIdent:
    if inCall:
      addTempDecl(c, n, kind)
  of nkCallKinds:
    for s in n:
      addTempDeclToIdents(c, s, kind, true)  
  else:
    for s in n:
      addTempDeclToIdents(c, s, kind, inCall)

proc semGenericStmt(c: PContext, n: PNode,
                    flags: TSemGenericFlags, ctx: var GenericCtx): PNode =
  result = n

  when defined(nimsuggest):
    if withinTypeDesc in flags: inc c.inTypeContext

  #if conf.cmd == cmdIdeTools: suggestStmt(c, n)
  semIdeForTemplateOrGenericCheck(c.config, n, ctx.cursorInBody)

  case n.kind
  of nkIdent, nkAccQuoted:
    result = lookup(c, n, flags, ctx)
    if result != nil and result.kind == nkSym:
      assert result.sym != nil
      markUsed(c, n.info, result.sym)
  of nkDotExpr:
    #let luf = if withinMixin notin flags: {checkUndeclared} else: {}
    #var s = qualifiedLookUp(c, n, luf)
    #if s != nil: result = semGenericStmtSymbol(c, n, s)
    # XXX for example: ``result.add`` -- ``add`` needs to be looked up here...
    var dummy: bool = false
    result = fuzzyLookup(c, n, flags, ctx, dummy)
  of nkSym:
    let a = n.sym
    let b = getGenSym(c, a)
    if b != a: n.sym = b
  of nkEmpty, succ(nkSym)..nkNilLit, nkComesFrom:
    # see tests/compile/tgensymgeneric.nim:
    # We need to open the gensym'ed symbol again so that the instantiation
    # creates a fresh copy; but this is wrong the very first reason for gensym
    # is that scope rules cannot be used! So simply removing 'sfGenSym' does
    # not work. Copying the symbol does not work either because we're already
    # the owner of the symbol! What we need to do is to copy the symbol
    # in the generic instantiation process...
    discard
  of nkBind:
    result = semGenericStmt(c, n[0], flags+{withinBind}, ctx)
  of nkMixinStmt:
    result = semMixinStmt(c, n, ctx.toMixin)
  of nkBindStmt:
    result = semBindStmt(c, n, ctx.toBind)
  of nkCall, nkHiddenCallConv, nkInfix, nkPrefix, nkCommand, nkCallStrLit:
    # check if it is an expression macro:
    checkMinSonsLen(n, 1, c.config)
    let fn = n[0]
    c.isAmbiguous = false
    var s = qualifiedLookUp(c, fn, {})
    let ambig = c.isAmbiguous
    if s == nil and
        {withinMixin, withinConcept}*flags == {} and
        fn.kind in {nkIdent, nkAccQuoted} and
        considerQuotedIdent(c, fn).id notin ctx.toMixin:
      errorUndeclaredIdentifier(c, n.info, fn.renderTree)

    var first = int ord(withinConcept in flags)
    var mixinContext = false
    if s != nil:
      incl(s.flags, sfUsed)
      mixinContext = s.magic in {mDefined, mDeclared, mDeclaredInScope, mCompiles, mAstToStr}
      let whichChoice = if s.id in ctx.toBind: scClosed
                        elif s.isMixedIn: scForceOpen
                        else: scOpen
      let sc = symChoice(c, fn, s, whichChoice)
      case s.kind
      of skMacro, skTemplate:
        # unambiguous macros/templates are expanded if all params are untyped
        if sfAllUntyped in s.flags and sc.safeLen <= 1:
          onUse(fn.info, s)
          case s.kind
          of skMacro: result = semMacroExpr(c, n, n, s, {efNoSemCheck})
          of skTemplate: result = semTemplateExpr(c, n, s, {efNoSemCheck})
          else: discard # unreachable
          c.friendModules.add(s.owner.getModule)
          result = semGenericStmt(c, result, flags, ctx)
          discard c.friendModules.pop()
        else:
          n[0] = sc
          result = n
        # BUGFIX: we must not return here, we need to do first phase of
        # symbol lookup. Also since templates and macros can do scope injections
        # we need to put the ``c`` in ``t(c)`` in a mixin context to prevent
        # the famous "undeclared identifier: it" bug:
        mixinContext = true
      of skUnknown, skParam:
        # Leave it as an identifier.
        discard
      of skProc, skFunc, skMethod, skIterator, skConverter, skModule:
        result[0] = sc
        first = 1
        # We're not interested in the example code during this pass so let's
        # skip it
        if s.magic == mRunnableExamples:
          first = result.safeLen # see trunnableexamples.fun3
      of skGenericParam:
        result[0] = newSymNodeTypeDesc(s, c.idgen, fn.info)
        onUse(fn.info, s)
        first = 1
      of skType:
        # bad hack for generics:
        if (s.typ != nil) and (s.typ.kind != tyGenericParam):
          if ambig:
            # ambiguous types should be symchoices since lookup behaves
            # differently for them in regular expressions
            result[0] = sc
          else:
            result[0] = newSymNodeTypeDesc(s, c.idgen, fn.info)
          onUse(fn.info, s)
          first = 1
      else:
        result[0] = newSymNode(s, fn.info)
        onUse(fn.info, s)
        first = 1
    elif fn.kind == nkDotExpr:
      result[0] = fuzzyLookup(c, fn, flags, ctx, mixinContext, inCall = true)
      first = 1
    # Consider 'when declared(globalsSlot): ThreadVarSetValue(globalsSlot, ...)'
    # in threads.nim: the subtle preprocessing here binds 'globalsSlot' which
    # is not exported and yet the generic 'threadProcWrapper' works correctly.
    let flags = if mixinContext: flags+{withinMixin} else: flags
    for i in first..<result.safeLen:
      result[i] = semGenericStmt(c, result[i], flags, ctx)
  of nkCurlyExpr:
    result = newNodeI(nkCall, n.info)
    result.add newIdentNode(getIdent(c.cache, "{}"), n.info)
    for i in 0..<n.len: result.add(n[i])
    result = semGenericStmt(c, result, flags, ctx)
  of nkBracketExpr:
    result = newNodeI(nkCall, n.info)
    result.add newIdentNode(getIdent(c.cache, "[]"), n.info)
    for i in 0..<n.len: result.add(n[i])
    result = semGenericStmt(c, result, flags, ctx)
  of nkAsgn, nkFastAsgn, nkSinkAsgn:
    checkSonsLen(n, 2, c.config)
    let a = n[0]
    let b = n[1]

    let k = a.kind
    case k
    of nkCurlyExpr:
      result = newNodeI(nkCall, n.info)
      result.add newIdentNode(getIdent(c.cache, "{}="), n.info)
      for i in 0..<a.len: result.add(a[i])
      result.add(b)
      result = semGenericStmt(c, result, flags, ctx)
    of nkBracketExpr:
      result = newNodeI(nkCall, n.info)
      result.add newIdentNode(getIdent(c.cache, "[]="), n.info)
      for i in 0..<a.len: result.add(a[i])
      result.add(b)
      result = semGenericStmt(c, result, flags, ctx)
    else:
      for i in 0..<n.len:
        result[i] = semGenericStmt(c, n[i], flags, ctx)
  of nkIfStmt:
    for i in 0..<n.len:
      n[i] = semGenericStmtScope(c, n[i], flags, ctx)
  of nkWhenStmt:
    for i in 0..<n.len:
      # bug #8603: conditions of 'when' statements are not
      # in a 'mixin' context:
      let it = n[i]
      if it.kind in {nkElifExpr, nkElifBranch}:
        n[i][0] = semGenericStmt(c, it[0], flags, ctx)
        n[i][1] = semGenericStmt(c, it[1], flags+{withinMixin}, ctx)
      else:
        n[i] = semGenericStmt(c, it, flags+{withinMixin}, ctx)
  of nkWhileStmt:
    openScope(c)
    for i in 0..<n.len:
      n[i] = semGenericStmt(c, n[i], flags, ctx)
    closeScope(c)
  of nkCaseStmt:
    openScope(c)
    n[0] = semGenericStmt(c, n[0], flags, ctx)
    for i in 1..<n.len:
      var a = n[i]
      checkMinSonsLen(a, 1, c.config)
      for j in 0..<a.len-1:
        a[j] = semGenericStmt(c, a[j], flags+{withinMixin}, ctx)
        addTempDeclToIdents(c, a[j], skVar, false)

      a[^1] = semGenericStmtScope(c, a[^1], flags, ctx)
    closeScope(c)
  of nkForStmt, nkParForStmt:
    openScope(c)
    n[^2] = semGenericStmt(c, n[^2], flags, ctx)
    for i in 0..<n.len - 2:
      if (n[i].kind == nkVarTuple):
        for s in n[i]:
          if (s.kind == nkIdent):
            addTempDecl(c,s,skForVar)
      else:
        addTempDecl(c, n[i], skForVar)
    openScope(c)
    n[^1] = semGenericStmt(c, n[^1], flags, ctx)
    closeScope(c)
    closeScope(c)
  of nkBlockStmt, nkBlockExpr, nkBlockType:
    checkSonsLen(n, 2, c.config)
    openScope(c)
    if n[0].kind != nkEmpty:
      addTempDecl(c, n[0], skLabel)
    n[1] = semGenericStmt(c, n[1], flags, ctx)
    closeScope(c)
  of nkTryStmt, nkHiddenTryStmt:
    checkMinSonsLen(n, 2, c.config)
    n[0] = semGenericStmtScope(c, n[0], flags, ctx)
    for i in 1..<n.len:
      var a = n[i]
      checkMinSonsLen(a, 1, c.config)
      openScope(c)
      for j in 0..<a.len-1:
        if a[j].isInfixAs():
          addTempDecl(c, getIdentNode(c, a[j][2]), skLet)
          a[j][1] = semGenericStmt(c, a[j][1], flags+{withinTypeDesc}, ctx)
        else:
          a[j] = semGenericStmt(c, a[j], flags+{withinTypeDesc}, ctx)
      a[^1] = semGenericStmtScope(c, a[^1], flags, ctx)
      closeScope(c)

  of nkVarSection, nkLetSection, nkConstSection:
    let varKind =
      case n.kind
      of nkVarSection: skVar
      of nkLetSection: skLet
      else: skConst
    for i in 0..<n.len:
      var a = n[i]
      case a.kind:
      of nkCommentStmt: continue
      of nkIdentDefs, nkVarTuple, nkConstDef:
        checkMinSonsLen(a, 3, c.config)
        a[^2] = semGenericStmt(c, a[^2], flags+{withinTypeDesc}, ctx)
        a[^1] = semGenericStmt(c, a[^1], flags, ctx)
        for j in 0..<a.len-2:
          addTempDecl(c, getIdentNode(c, a[j]), varKind)
      else:
        illFormedAst(a, c.config)
  of nkGenericParams:
    for i in 0..<n.len:
      var a = n[i]
      if (a.kind != nkIdentDefs): illFormedAst(a, c.config)
      checkMinSonsLen(a, 3, c.config)
      a[^2] = semGenericStmt(c, a[^2], flags+{withinTypeDesc}, ctx)
      # do not perform symbol lookup for default expressions
      for j in 0..<a.len-2:
        addTempDecl(c, getIdentNode(c, a[j]), skType)
  of nkTypeSection:
    for i in 0..<n.len:
      var a = n[i]
      if a.kind == nkCommentStmt: continue
      if (a.kind != nkTypeDef): illFormedAst(a, c.config)
      checkSonsLen(a, 3, c.config)
      addTempDecl(c, getIdentNode(c, a[0]), skType)
    for i in 0..<n.len:
      var a = n[i]
      if a.kind == nkCommentStmt: continue
      if (a.kind != nkTypeDef): illFormedAst(a, c.config)
      checkSonsLen(a, 3, c.config)
      if a[1].kind != nkEmpty:
        openScope(c)
        a[1] = semGenericStmt(c, a[1], flags, ctx)
        a[2] = semGenericStmt(c, a[2], flags+{withinTypeDesc}, ctx)
        closeScope(c)
      else:
        a[2] = semGenericStmt(c, a[2], flags+{withinTypeDesc}, ctx)
  of nkEnumTy:
    if n.len > 0:
      if n[0].kind != nkEmpty:
        n[0] = semGenericStmt(c, n[0], flags+{withinTypeDesc}, ctx)
      for i in 1..<n.len:
        var a: PNode = nil
        case n[i].kind
        of nkEnumFieldDef: a = n[i][0]
        of nkIdent: a = n[i]
        else: illFormedAst(n, c.config)
        addDecl(c, newSymS(skUnknown, getIdentNode(c, a), c))
  of nkTupleTy:
    for i in 0..<n.len:
      var a = n[i]
      case a.kind:
      of nkCommentStmt, nkNilLit, nkSym, nkEmpty: continue
      of nkIdentDefs:
        checkMinSonsLen(a, 3, c.config)
        a[^2] = semGenericStmt(c, a[^2], flags+{withinTypeDesc}, ctx)
        a[^1] = semGenericStmt(c, a[^1], flags, ctx)
        for j in 0..<a.len-2:
          addTempDecl(c, getIdentNode(c, a[j]), skField)
      else:
        illFormedAst(a, c.config)
  of nkObjectTy:
    if n.len > 0:
      openScope(c)
      for i in 0..<n.len:
        result[i] = semGenericStmt(c, n[i], flags, ctx)
      closeScope(c)
  of nkRecList:
    for i in 0..<n.len:
      var a = n[i]
      case a.kind:
      of nkCommentStmt, nkNilLit, nkSym, nkEmpty: continue
      of nkIdentDefs:
        checkMinSonsLen(a, 3, c.config)
        a[^2] = semGenericStmt(c, a[^2], flags+{withinTypeDesc}, ctx)
        a[^1] = semGenericStmt(c, a[^1], flags, ctx)
        for j in 0..<a.len-2:
          addTempDecl(c, getIdentNode(c, a[j]), skField)
      of nkRecCase, nkRecWhen:
        n[i] = semGenericStmt(c, a, flags, ctx)
      else:
        illFormedAst(a, c.config)
  of nkRecCase:
    checkSonsLen(n[0], 3, c.config)
    n[0][^2] = semGenericStmt(c, n[0][^2], flags+{withinTypeDesc}, ctx)
    n[0][^1] = semGenericStmt(c, n[0][^1], flags, ctx)
    addTempDecl(c, getIdentNode(c, n[0][0]), skField)
    for i in 1..<n.len:
      n[i] = semGenericStmt(c, n[i], flags, ctx)
  of nkFormalParams:
    checkMinSonsLen(n, 1, c.config)
    for i in 1..<n.len:
      var a = n[i]
      if (a.kind != nkIdentDefs): illFormedAst(a, c.config)
      checkMinSonsLen(a, 3, c.config)
      a[^2] = semGenericStmt(c, a[^2], flags+{withinTypeDesc}, ctx)
      a[^1] = semGenericStmt(c, a[^1], flags, ctx)
      for j in 0..<a.len-2:
        addTempDecl(c, getIdentNode(c, a[j]), skParam)
    # XXX: last change was moving this down here, search for "1.." to keep
    #      going from this file onward
    if n[0].kind != nkEmpty:
      n[0] = semGenericStmt(c, n[0], flags+{withinTypeDesc}, ctx)
  of nkProcDef, nkMethodDef, nkConverterDef, nkMacroDef, nkTemplateDef,
     nkFuncDef, nkIteratorDef, nkLambdaKinds:
    checkSonsLen(n, bodyPos + 1, c.config)
    if n[namePos].kind != nkEmpty:
      addTempDecl(c, getIdentNode(c, n[0]), skProc)
    openScope(c)
    n[genericParamsPos] = semGenericStmt(c, n[genericParamsPos],
                                              flags, ctx)
    if n[paramsPos].kind != nkEmpty:
      if n[paramsPos][0].kind != nkEmpty:
        addPrelimDecl(c, newSym(skUnknown, getIdent(c.cache, "result"), c.idgen, nil, n.info))
      n[paramsPos] = semGenericStmt(c, n[paramsPos], flags, ctx)
    n[pragmasPos] = semGenericStmt(c, n[pragmasPos], flags, ctx)
    var body: PNode
    if n[namePos].kind == nkSym:
      let s = n[namePos].sym
      if sfGenSym in s.flags and s.ast == nil:
        body = n[bodyPos]
      else:
        body = getBody(c.graph, s)
    else: body = n[bodyPos]
    let bodyFlags = if n.kind == nkTemplateDef: flags + {withinMixin} else: flags
    n[bodyPos] = semGenericStmtScope(c, body, bodyFlags, ctx)
    closeScope(c)
  of nkPragmaExpr:
    result[1] = semGenericStmt(c, n[1], flags, ctx)
  of nkPragma:
    for i in 0 ..< n.len:
      let x = n[i]
      let prag = whichPragma(x)
      if x.kind in nkPragmaCallKinds:
        # process each child individually to prevent untyped macros/templates
        # from instantiating
        # if pragma is language-level pragma, skip name node:
        let start = ord(prag != wInvalid)
        for j in start ..< x.len:
          # treat as mixin context for user pragmas & macro args
          x[j] = semGenericStmt(c, x[j], flags+{withinMixin}, ctx)
      elif prag == wInvalid:
        # only sem if not a language-level pragma 
        # treat as mixin context for user pragmas & macro args
        result[i] = semGenericStmt(c, x, flags+{withinMixin}, ctx)
  of nkExprColonExpr, nkExprEqExpr:
    checkMinSonsLen(n, 2, c.config)
    result[1] = semGenericStmt(c, n[1], flags, ctx)
  of nkObjConstr:
    for i in 0..<n.len:
      result[i] = semGenericStmt(c, n[i], flags, ctx)
    if result[0].kind == nkSym:
      let fmoduleId = getModule(result[0].sym).id
      var isVisable = false
      for module in c.friendModules:
        if module.id == fmoduleId:
          isVisable = true
          break
      if isVisable:
        for i in 1..<result.len:
          if result[i].kind == nkExprColonExpr:
            result[i][1].flags.incl nfSkipFieldChecking
  else:
    for i in 0..<n.len:
      result[i] = semGenericStmt(c, n[i], flags, ctx)

  when defined(nimsuggest):
    if withinTypeDesc in flags: dec c.inTypeContext

proc semGenericStmt(c: PContext, n: PNode): PNode =
  var ctx = GenericCtx(
    toMixin: initIntSet(),
    toBind: initIntSet()
  )
  result = semGenericStmt(c, n, {}, ctx)
  semIdeForTemplateOrGeneric(c, result, ctx.cursorInBody)

proc semConceptBody(c: PContext, n: PNode): PNode =
  var ctx = GenericCtx(
    toMixin: initIntSet(),
    toBind: initIntSet()
  )
  result = semGenericStmt(c, n, {withinConcept}, ctx)
  semIdeForTemplateOrGeneric(c, result, ctx.cursorInBody)


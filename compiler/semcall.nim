#
#
#           The Nim Compiler
#        (c) Copyright 2013 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements semantic checking for calls.
# included from sem.nim

from std/algorithm import sort


proc sameMethodDispatcher(a, b: PSym): bool =
  result = false
  if a.kind == skMethod and b.kind == skMethod:
    var aa = lastSon(a.ast)
    var bb = lastSon(b.ast)
    if aa.kind == nkSym and bb.kind == nkSym:
      if aa.sym == bb.sym:
        result = true
    else:
      discard
      # generics have no dispatcher yet, so we need to compare the method
      # names; however, the names are equal anyway because otherwise we
      # wouldn't even consider them to be overloaded. But even this does
      # not work reliably! See tmultim6 for an example:
      # method collide[T](a: TThing, b: TUnit[T]) is instantiated and not
      # method collide[T](a: TUnit[T], b: TThing)! This means we need to
      # *instantiate* every candidate! However, we don't keep more than 2-3
      # candidates around so we cannot implement that for now. So in order
      # to avoid subtle problems, the call remains ambiguous and needs to
      # be disambiguated by the programmer; this way the right generic is
      # instantiated.

proc determineType(c: PContext, s: PSym)

proc initCandidateSymbols(c: PContext, headSymbol: PNode,
                          initialBinding: PNode,
                          filter: TSymKinds,
                          best, alt: var TCandidate,
                          o: var TOverloadIter,
                          diagnostics: bool): seq[tuple[s: PSym, scope: int]] =
  ## puts all overloads into a seq and prepares best+alt
  result = @[]
  var symx = initOverloadIter(o, c, headSymbol)
  while symx != nil:
    if symx.kind in filter:
      result.add((symx, o.lastOverloadScope))
    elif symx.kind == skGenericParam:
      #[
        This code handles looking up a generic parameter when it's a static callable.
        For instance:
          proc name[T: static proc()]() = T()
          name[proc() = echo"hello"]()
      ]#
      for paramSym in searchInScopesAllCandidatesFilterBy(c, symx.name, {skConst}):
        let paramTyp = paramSym.typ
        if paramTyp.n.kind == nkSym and paramTyp.n.sym.kind in filter:
          result.add((paramTyp.n.sym, o.lastOverloadScope))

    symx = nextOverloadIter(o, c, headSymbol)
  if result.len > 0:
    best = initCandidate(c, result[0].s, initialBinding,
                  result[0].scope, diagnostics)
    alt = initCandidate(c, result[0].s, initialBinding,
                  result[0].scope, diagnostics)
    best.state = csNoMatch

proc isAttachableRoutineTo(prc: PSym, arg: PType): bool =
  result = false
  if arg.owner != prc.owner: return false
  for i in 1 ..< prc.typ.len:
    if prc.typ.n[i].kind == nkSym and prc.typ.n[i].sym.ast != nil:
      # has default value, parameter is not considered in type attachment
      continue
    let t = nominalRoot(prc.typ[i])
    if t != nil and t.itemId == arg.itemId:
      # parameter `i` is a nominal type in this module
      # attachable if the nominal root `t` has the same id as `arg`
      return true

proc addTypeBoundSymbols(graph: ModuleGraph, arg: PType, name: PIdent,
                         filter: TSymKinds, marker: var IntSet,
                         syms: var seq[tuple[s: PSym, scope: int]]) =
  # add type bound ops for `name` based on the argument type `arg`
  if arg != nil:
    # argument must be typed first, meaning arguments always
    # matching `untyped` are ignored
    let t = nominalRoot(arg)
    if t != nil and t.owner.kind == skModule:
      # search module for routines attachable to `t`
      let module = t.owner
      var iter = default(ModuleIter)
      var s = initModuleIter(iter, graph, module, name)
      while s != nil:
        if s.kind in filter and s.isAttachableRoutineTo(t) and
            not containsOrIncl(marker, s.id):
          # least priority scope, less than explicit imports:
          syms.add((s, -2))
        s = nextModuleIter(iter, graph)

proc pickBestCandidate(c: PContext, headSymbol: PNode,
                       n, orig: PNode,
                       initialBinding: PNode,
                       filter: TSymKinds,
                       best, alt: var TCandidate,
                       errors: var CandidateErrors,
                       diagnosticsFlag: bool,
                       errorsEnabled: bool, flags: TExprFlags) =
  # `matches` may find new symbols, so keep track of count
  var symCount = c.currentScope.symbols.counter

  var o: TOverloadIter = default(TOverloadIter)
  # https://github.com/nim-lang/Nim/issues/21272
  # prevent mutation during iteration by storing them in a seq
  # luckily `initCandidateSymbols` does just that
  var syms = initCandidateSymbols(c, headSymbol, initialBinding, filter,
                                  best, alt, o, diagnosticsFlag)
  if len(syms) == 0:
    return
  let allowTypeBoundOps = typeBoundOps in c.features and
    # qualified or bound symbols cannot refer to type bound ops
    headSymbol.kind in {nkIdent, nkAccQuoted, nkOpenSymChoice, nkOpenSym}
  var symMarker = initIntSet()
  for s in syms:
    symMarker.incl(s.s.id)
  # current overload being considered
  var sym = syms[0].s
  let name = sym.name
  var scope = syms[0].scope

  if allowTypeBoundOps:
    for a in 1 ..< n.len:
      # for every already typed argument, add type bound ops
      let arg = n[a]
      addTypeBoundSymbols(c.graph, arg.typ, name, filter, symMarker, syms)

  # starts at 1 because 0 is already done with setup, only needs checking
  var nextSymIndex = 1
  var z: TCandidate # current candidate
  while true:
    determineType(c, sym)
    z = initCandidate(c, sym, initialBinding, scope, diagnosticsFlag)

    # this is kinda backwards as without a check here the described
    # problems in recalc would not happen, but instead it 100%
    # does check forever in some cases
    if c.currentScope.symbols.counter == symCount:
      # may introduce new symbols with caveats described in recalc branch
      matches(c, n, orig, z)

      if allowTypeBoundOps:
        # this match may have given some arguments new types,
        # in which case add their type bound ops as well
        # type bound ops of arguments always matching `untyped` are not considered
        for x in z.newlyTypedOperands:
          let arg = n[x]
          addTypeBoundSymbols(c.graph, arg.typ, name, filter, symMarker, syms)

      if z.state == csMatch:
        # little hack so that iterators are preferred over everything else:
        if sym.kind == skIterator:
          if not (efWantIterator notin flags and efWantIterable in flags):
            inc(z.exactMatches, 200)
          else:
            dec(z.exactMatches, 200)
        case best.state
        of csEmpty, csNoMatch: best = z
        of csMatch:
          var cmp = cmpCandidates(best, z)
          if cmp < 0: best = z   # x is better than the best so far
          elif cmp == 0: alt = z # x is as good as the best so far
      elif errorsEnabled or z.diagnosticsEnabled:
        errors.add(CandidateError(
          sym: sym,
          firstMismatch: z.firstMismatch,
          diagnostics: z.diagnostics))
    else:
      # this branch feels like a ticking timebomb
      # one of two bad things could happen
      # 1) new symbols are discovered but the loop ends before we recalc
      # 2) new symbols are discovered and resemmed forever
      # not 100% sure if these are possible though as they would rely
      #  on somehow introducing a new overload during overload resolution

      # Symbol table has been modified. Restart and pre-calculate all syms
      # before any further candidate init and compare. SLOW, but rare case.
      syms = initCandidateSymbols(c, headSymbol, initialBinding, filter,
                                  best, alt, o, diagnosticsFlag)
      symMarker = initIntSet()
      for s in syms:
        symMarker.incl(s.s.id)
      if allowTypeBoundOps:
        for a in 1 ..< n.len:
          # for every already typed argument, add type bound ops
          let arg = n[a]
          addTypeBoundSymbols(c.graph, arg.typ, name, filter, symMarker, syms)
      # reset counter because syms may be in a new order
      symCount = c.currentScope.symbols.counter
      nextSymIndex = 0

      # just in case, should be impossible though
      if syms.len == 0:
        break

    if nextSymIndex > high(syms):
      # we have reached the end
      break

    # advance to next sym
    sym = syms[nextSymIndex].s
    scope = syms[nextSymIndex].scope
    inc(nextSymIndex)


proc effectProblem(f, a: PType; result: var string; c: PContext) =
  if f.kind == tyProc and a.kind == tyProc:
    if tfThread in f.flags and tfThread notin a.flags:
      result.add "\n  This expression is not GC-safe. Annotate the " &
          "proc with {.gcsafe.} to get extended error information."
    elif tfNoSideEffect in f.flags and tfNoSideEffect notin a.flags:
      result.add "\n  This expression can have side effects. Annotate the " &
          "proc with {.noSideEffect.} to get extended error information."
    else:
      case compatibleEffects(f, a)
      of efCompat: discard
      of efRaisesDiffer:
        result.add "\n  The `.raises` requirements differ."
      of efRaisesUnknown:
        result.add "\n  The `.raises` requirements differ. Annotate the " &
            "proc with {.raises: [].} to get extended error information."
      of efTagsDiffer:
        result.add "\n  The `.tags` requirements differ."
      of efTagsUnknown:
        result.add "\n  The `.tags` requirements differ. Annotate the " &
            "proc with {.tags: [].} to get extended error information."
      of efEffectsDelayed:
        result.add "\n  The `.effectsOf` annotations differ."
      of efTagsIllegal:
        result.add "\n  The `.forbids` requirements caught an illegal tag."
      when defined(drnim):
        if not c.graph.compatibleProps(c.graph, f, a):
          result.add "\n  The `.requires` or `.ensures` properties are incompatible."

proc renderNotLValue(n: PNode): string =
  result = $n
  let n = if n.kind == nkHiddenDeref: n[0] else: n
  if n.kind == nkHiddenCallConv and n.len > 1:
    result = $n[0] & "(" & result & ")"
  elif n.kind in {nkHiddenStdConv, nkHiddenSubConv} and n.len == 2:
    result = typeToString(n.typ.skipTypes(abstractVar)) & "(" & result & ")"

proc presentFailedCandidates(c: PContext, n: PNode, errors: CandidateErrors):
                            (TPreferedDesc, string) =
  var prefer = preferName
  # to avoid confusing errors like:
  #   got (SslPtr, SocketHandle)
  #   but expected one of:
  #   openssl.SSL_set_fd(ssl: SslPtr, fd: SocketHandle): cint
  # we do a pre-analysis. If all types produce the same string, we will add
  # module information.
  let proto = describeArgs(c, n, 1, preferName)
  for err in errors:
    var errProto = ""
    let n = err.sym.typ.n
    for i in 1..<n.len:
      var p = n[i]
      if p.kind == nkSym:
        errProto.add(typeToString(p.sym.typ, preferName))
        if i != n.len-1: errProto.add(", ")
      # else: ignore internal error as we're already in error handling mode
    if errProto == proto:
      prefer = preferModuleInfo
      break

  # we pretend procs are attached to the type of the first
  # argument in order to remove plenty of candidates. This is
  # comparable to what C# does and C# is doing fine.
  var filterOnlyFirst = false
  if optShowAllMismatches notin c.config.globalOptions and verboseTypeMismatch in c.config.legacyFeatures:
    for err in errors:
      if err.firstMismatch.arg > 1:
        filterOnlyFirst = true
        break

  var maybeWrongSpace = false

  var candidatesAll: seq[string] = @[]
  var candidates = ""
  var skipped = 0
  for err in errors:
    candidates.setLen 0
    if filterOnlyFirst and err.firstMismatch.arg == 1:
      inc skipped
      continue

    if verboseTypeMismatch notin c.config.legacyFeatures:
      candidates.add "[" & $err.firstMismatch.arg & "] "

    if err.sym.kind in routineKinds and err.sym.ast != nil:
      candidates.add(renderTree(err.sym.ast,
            {renderNoBody, renderNoComments, renderNoPragmas}))
    else:
      candidates.add(getProcHeader(c.config, err.sym, prefer))
    candidates.addDeclaredLocMaybe(c.config, err.sym)
    candidates.add("\n")
    const genericParamMismatches = {kGenericParamTypeMismatch, kExtraGenericParam, kMissingGenericParam}
    let isGenericMismatch = err.firstMismatch.kind in genericParamMismatches
    var argList = n
    if isGenericMismatch and n[0].kind == nkBracketExpr:
      argList = n[0]
    let nArg =
      if err.firstMismatch.arg < argList.len:
        argList[err.firstMismatch.arg]
      else:
        nil
    let nameParam = if err.firstMismatch.formal != nil: err.firstMismatch.formal.name.s else: ""
    if n.len > 1:
      if verboseTypeMismatch notin c.config.legacyFeatures:
        case err.firstMismatch.kind
        of kUnknownNamedParam:
          if nArg == nil:
            candidates.add("  unknown named parameter")
          else:
            candidates.add("  unknown named parameter: " & $nArg[0])
          candidates.add "\n"
        of kAlreadyGiven:
          candidates.add("  named param already provided: " & $nArg[0])
          candidates.add "\n"
        of kPositionalAlreadyGiven:
          candidates.add("  positional param was already given as named param")
          candidates.add "\n"
        of kExtraArg:
          candidates.add("  extra argument given")
          candidates.add "\n"
        of kMissingParam:
          candidates.add("  missing parameter: " & nameParam)
          candidates.add "\n"
        of kExtraGenericParam:
          candidates.add("  extra generic param given")
          candidates.add "\n"
        of kMissingGenericParam:
          candidates.add("  missing generic parameter: " & nameParam)
          candidates.add "\n"
        of kVarNeeded:
          doAssert nArg != nil
          doAssert err.firstMismatch.formal != nil
          candidates.add "  expression '"
          candidates.add renderNotLValue(nArg)
          candidates.add "' is immutable, not 'var'"
          candidates.add "\n"
        of kTypeMismatch:
          doAssert nArg != nil
          if nArg.kind in nkSymChoices:
            candidates.add ambiguousIdentifierMsg(nArg, indent = 2)
          let wanted = err.firstMismatch.formal.typ
          doAssert err.firstMismatch.formal != nil
          doAssert wanted != nil
          let got = nArg.typ
          if got != nil and got.kind == tyProc and wanted.kind == tyProc:
            # These are proc mismatches so,
            # add the extra explict detail of the mismatch
            candidates.add "  expression '"
            candidates.add renderTree(nArg)
            candidates.add "' is of type: "
            candidates.addTypeDeclVerboseMaybe(c.config, got)
            candidates.addPragmaAndCallConvMismatch(wanted, got, c.config)
            effectProblem(wanted, got, candidates, c)
            candidates.add "\n"
        of kGenericParamTypeMismatch:
          let pos = err.firstMismatch.arg
          doAssert n[0].kind == nkBracketExpr and pos < n[0].len
          let arg = n[0][pos]
          doAssert arg != nil
          var wanted = err.firstMismatch.formal.typ
          if wanted.kind == tyGenericParam and wanted.genericParamHasConstraints:
            wanted = wanted.genericConstraint
          let got = arg.typ.skipTypes({tyTypeDesc})
          doAssert err.firstMismatch.formal != nil
          doAssert wanted != nil
          doAssert got != nil
          candidates.add "  generic parameter mismatch, expected "
          candidates.addTypeDeclVerboseMaybe(c.config, wanted)
          candidates.add " but got '"
          candidates.add renderTree(arg)
          candidates.add "' of type: "
          candidates.addTypeDeclVerboseMaybe(c.config, got)
          if nArg.kind in nkSymChoices:
            candidates.add "\n"
            candidates.add ambiguousIdentifierMsg(nArg, indent = 2)
          if got != nil and got.kind == tyProc and wanted.kind == tyProc:
            # These are proc mismatches so,
            # add the extra explict detail of the mismatch
            candidates.addPragmaAndCallConvMismatch(wanted, got, c.config)
          if got != nil:
            effectProblem(wanted, got, candidates, c)
          candidates.add "\n"
        of kUnknown: discard "do not break 'nim check'"
      else:
        candidates.add("  first type mismatch at position: " & $err.firstMismatch.arg)
        if err.firstMismatch.kind in genericParamMismatches:
          candidates.add(" in generic parameters")
        # candidates.add "\n  reason: " & $err.firstMismatch.kind # for debugging
        case err.firstMismatch.kind
        of kUnknownNamedParam:
          if nArg == nil:
            candidates.add("\n  unknown named parameter")
          else:
            candidates.add("\n  unknown named parameter: " & $nArg[0])
        of kAlreadyGiven: candidates.add("\n  named param already provided: " & $nArg[0])
        of kPositionalAlreadyGiven: candidates.add("\n  positional param was already given as named param")
        of kExtraArg: candidates.add("\n  extra argument given")
        of kMissingParam: candidates.add("\n  missing parameter: " & nameParam)
        of kExtraGenericParam:
          candidates.add("\n  extra generic param given")
        of kMissingGenericParam:
          candidates.add("\n  missing generic parameter: " & nameParam)
        of kTypeMismatch, kGenericParamTypeMismatch, kVarNeeded:
          doAssert nArg != nil
          var wanted = err.firstMismatch.formal.typ
          if isGenericMismatch and wanted.kind == tyGenericParam and
              wanted.genericParamHasConstraints:
            wanted = wanted.genericConstraint
          doAssert err.firstMismatch.formal != nil
          candidates.add("\n  required type for " & nameParam &  ": ")
          candidates.addTypeDeclVerboseMaybe(c.config, wanted)
          candidates.add "\n  but expression '"
          if err.firstMismatch.kind == kVarNeeded:
            candidates.add renderNotLValue(nArg)
            candidates.add "' is immutable, not 'var'"
          else:
            candidates.add renderTree(nArg)
            candidates.add "' is of type: "
            var got = nArg.typ
            if isGenericMismatch: got = got.skipTypes({tyTypeDesc})
            candidates.addTypeDeclVerboseMaybe(c.config, got)
            if nArg.kind in nkSymChoices:
              candidates.add "\n"
              candidates.add ambiguousIdentifierMsg(nArg, indent = 2)
            doAssert wanted != nil
            if got != nil:
              if got.kind == tyProc and wanted.kind == tyProc:
                # These are proc mismatches so,
                # add the extra explict detail of the mismatch
                candidates.addPragmaAndCallConvMismatch(wanted, got, c.config)
              effectProblem(wanted, got, candidates, c)

        of kUnknown: discard "do not break 'nim check'"
        candidates.add "\n"
      if err.firstMismatch.arg == 1 and nArg != nil and
          nArg.kind == nkTupleConstr and n.kind == nkCommand:
        maybeWrongSpace = true
    for diag in err.diagnostics:
      candidates.add(diag & "\n")
    candidatesAll.add candidates
  candidatesAll.sort # fix #13538
  candidates = join(candidatesAll)
  if skipped > 0:
    candidates.add($skipped & " other mismatching symbols have been " &
        "suppressed; compile with --showAllMismatches:on to see them\n")
  if maybeWrongSpace:
    candidates.add("maybe misplaced space between " & renderTree(n[0]) & " and '(' \n")

  result = (prefer, candidates)

const
  errTypeMismatch = "type mismatch: got <"
  errButExpected = "but expected one of:"
  errExpectedPosition = "Expected one of (first mismatch at [position]):"
  errUndeclaredField = "undeclared field: '$1'"
  errUndeclaredRoutine = "attempting to call undeclared routine: '$1'"
  errBadRoutine = "attempting to call routine: '$1'$2"
  errAmbiguousCallXYZ = "ambiguous call; both $1 and $2 match for: $3"

proc describeParamList(c: PContext, n: PNode, startIdx = 1; prefer = preferName): string =
  result = "Expression: " & $n
  for i in startIdx..<n.len:
    result.add "\n  [" & $i & "] " & renderTree(n[i]) & ": "
    result.add describeArg(c, n, i, startIdx, prefer)
  result.add "\n"

template legacynotFoundError(c: PContext, n: PNode, errors: CandidateErrors) =
  let (prefer, candidates) = presentFailedCandidates(c, n, errors)
  var result = errTypeMismatch
  result.add(describeArgs(c, n, 1, prefer))
  result.add('>')
  if candidates != "":
    result.add("\n" & errButExpected & "\n" & candidates)
  localError(c.config, n.info, result & "\nexpression: " & $n)

proc notFoundError*(c: PContext, n: PNode, errors: CandidateErrors) =
  # Gives a detailed error message; this is separated from semOverloadedCall,
  # as semOverloadedCall is already pretty slow (and we need this information
  # only in case of an error).
  if c.config.m.errorOutputs == {}:
    # fail fast:
    globalError(c.config, n.info, "type mismatch")
    return
  # see getMsgDiagnostic:
  if nfExplicitCall notin n.flags and {nfDotField, nfDotSetter} * n.flags != {}:
    let ident = considerQuotedIdent(c, n[0], n).s
    let sym = n[1].typ.typSym
    var typeHint = ""
    if sym == nil:
      discard
    else:
      typeHint = " for type " & getProcHeader(c.config, sym)
    localError(c.config, n.info, errUndeclaredField % ident & typeHint)
    return
  if errors.len == 0:
    if n[0].kind in nkIdentKinds:
      let ident = considerQuotedIdent(c, n[0], n).s
      localError(c.config, n.info, errUndeclaredRoutine % ident)
    else:
      localError(c.config, n.info, "expression '$1' cannot be called" % n[0].renderTree)
    return

  if verboseTypeMismatch in c.config.legacyFeatures:
    legacynotFoundError(c, n, errors)
  else:
    let (prefer, candidates) = presentFailedCandidates(c, n, errors)
    var result = "type mismatch\n"
    result.add describeParamList(c, n, 1, prefer)
    if candidates != "":
      result.add("\n" & errExpectedPosition & "\n" & candidates)
    localError(c.config, n.info, result)

proc getMsgDiagnostic(c: PContext, flags: TExprFlags, n, f: PNode): string =
  result = ""
  if c.compilesContextId > 0:
    # we avoid running more diagnostic when inside a `compiles(expr)`, to
    # errors while running diagnostic (see test D20180828T234921), and
    # also avoid slowdowns in evaluating `compiles(expr)`.
    discard
  else:
    var o: TOverloadIter = default(TOverloadIter)
    var sym = initOverloadIter(o, c, f)
    while sym != nil:
      result &= "\n  found $1" % [getSymRepr(c.config, sym)]
      sym = nextOverloadIter(o, c, f)

  let ident = considerQuotedIdent(c, f, n).s
  if nfExplicitCall notin n.flags and {nfDotField, nfDotSetter} * n.flags != {}:
    let sym = n[1].typ.typSym
    var typeHint = ""
    if sym == nil:
      # Perhaps we're in a `compiles(foo.bar)` expression, or
      # in a concept, e.g.:
      #   ExplainedConcept {.explain.} = concept x
      #     x.foo is int
      # We could use: `(c.config $ n[1].info)` to get more context.
      discard
    else:
      typeHint = " for type " & getProcHeader(c.config, sym)
    let suffix = if result.len > 0: " " & result else: ""
    result = errUndeclaredField % ident & typeHint & suffix
  else:
    if result.len == 0: result = errUndeclaredRoutine % ident
    else: result = errBadRoutine % [ident, result]

proc resolveOverloads(c: PContext, n, orig: PNode,
                      filter: TSymKinds, flags: TExprFlags,
                      errors: var CandidateErrors,
                      errorsEnabled: bool): TCandidate =
  result = default(TCandidate)
  var initialBinding: PNode
  var alt: TCandidate = default(TCandidate)
  var f = n[0]
  if f.kind == nkBracketExpr:
    # fill in the bindings:
    semOpAux(c, f)
    initialBinding = f
    f = f[0]
  else:
    initialBinding = nil

  pickBestCandidate(c, f, n, orig, initialBinding,
                    filter, result, alt, errors, efExplain in flags,
                    errorsEnabled, flags)

  var dummyErrors: CandidateErrors = @[]
  template pickSpecialOp(headSymbol) =
    pickBestCandidate(c, headSymbol, n, orig, initialBinding,
                      filter, result, alt, dummyErrors, efExplain in flags,
                      false, flags)

  let overloadsState = result.state
  if overloadsState != csMatch:
    if nfDotField in n.flags:
      internalAssert c.config, f.kind == nkIdent and n.len >= 2

      # leave the op head symbol empty,
      # we are going to try multiple variants
      n.sons[0..1] = [nil, n[1], f]
      orig.sons[0..1] = [nil, orig[1], f]

      template tryOp(x) =
        let op = newIdentNode(getIdent(c.cache, x), n.info)
        n[0] = op
        orig[0] = op
        pickSpecialOp(op)

      if nfExplicitCall in n.flags:
        tryOp ".()"

      if result.state in {csEmpty, csNoMatch}:
        tryOp "."

    elif nfDotSetter in n.flags and f.kind == nkIdent and n.len == 3:
      # we need to strip away the trailing '=' here:
      let calleeName = newIdentNode(getIdent(c.cache, f.ident.s[0..^2]), n.info)
      let callOp = newIdentNode(getIdent(c.cache, ".="), n.info)
      n.sons[0..1] = [callOp, n[1], calleeName]
      orig.sons[0..1] = [callOp, orig[1], calleeName]
      pickSpecialOp(callOp)

    if overloadsState == csEmpty and result.state == csEmpty:
      if efNoUndeclared notin flags: # for tests/pragmas/tcustom_pragma.nim
        result.state = csNoMatch
        if c.inGenericContext > 0 and nfExprCall in n.flags:
          # untyped expression calls end up here, see #24099
          return
        # xxx adapt/use errorUndeclaredIdentifierHint(c, n, f.ident)
        localError(c.config, n.info, getMsgDiagnostic(c, flags, n, f))
      return
    elif result.state != csMatch:
      if nfExprCall in n.flags:
        localError(c.config, n.info, "expression '$1' cannot be called" %
                   renderTree(n, {renderNoComments}))
      else:
        if {nfDotField, nfDotSetter} * n.flags != {}:
          # clean up the inserted ops
          n.sons.delete(2)
          n[0] = f
      return
  if alt.state == csMatch and cmpCandidates(result, alt) == 0 and
      not sameMethodDispatcher(result.calleeSym, alt.calleeSym):
    internalAssert c.config, result.state == csMatch
    #writeMatches(result)
    #writeMatches(alt)
    if c.config.m.errorOutputs == {}:
      # quick error message for performance of 'compiles' built-in:
      globalError(c.config, n.info, errGenerated, "ambiguous call")
    elif c.config.errorCounter == 0:
      # don't cascade errors
      var args = "("
      for i in 1..<n.len:
        if i > 1: args.add(", ")
        args.add(typeToString(n[i].typ))
      args.add(")")

      localError(c.config, n.info, errAmbiguousCallXYZ % [
        getProcHeader(c.config, result.calleeSym),
        getProcHeader(c.config, alt.calleeSym),
        args])

proc bracketNotFoundError(c: PContext; n: PNode; flags: TExprFlags) =
  var errors: CandidateErrors = @[]
  let headSymbol = n[0]
  block:
    # we build a closed symchoice of all `[]` overloads for their errors,
    # except add a custom error for the magics which always match
    var choice = newNodeIT(nkClosedSymChoice, headSymbol.info, newTypeS(tyNone, c))
    var o: TOverloadIter = default(TOverloadIter)
    var symx = initOverloadIter(o, c, headSymbol)
    while symx != nil:
      if symx.kind in routineKinds:
        if symx.magic in {mArrGet, mArrPut}:
          errors.add(CandidateError(sym: symx,
                                    firstMismatch: MismatchInfo(),
                                    diagnostics: @[],
                                    enabled: false))
        else:
          choice.add newSymNode(symx, headSymbol.info)
      symx = nextOverloadIter(o, c, headSymbol)
    n[0] = choice
  # copied from semOverloadedCallAnalyzeEffects, might be overkill:
  const baseFilter = {skProc, skFunc, skMethod, skConverter, skMacro, skTemplate}
  let filter =
    if flags*{efInTypeof, efWantIterator, efWantIterable} != {}:
      baseFilter + {skIterator}
    else: baseFilter
  # this will add the errors:
  var r = resolveOverloads(c, n, n, filter, flags, errors, true)
  if errors.len == 0:
    localError(c.config, n.info, "could not resolve: " & $n)
  else:
    notFoundError(c, n, errors)

proc instGenericConvertersArg*(c: PContext, a: PNode, x: TCandidate) =
  let a = if a.kind == nkHiddenDeref: a[0] else: a
  if a.kind == nkHiddenCallConv and a[0].kind == nkSym:
    let s = a[0].sym
    if s.isGenericRoutineStrict:
      let finalCallee = generateInstance(c, s, x.bindings, a.info)
      a[0].sym = finalCallee
      a[0].typ() = finalCallee.typ
      #a.typ = finalCallee.typ.returnType

proc instGenericConvertersSons*(c: PContext, n: PNode, x: TCandidate) =
  assert n.kind in nkCallKinds
  if x.genericConverter:
    for i in 1..<n.len:
      instGenericConvertersArg(c, n[i], x)

proc markConvertersUsed*(c: PContext, n: PNode) =
  assert n.kind in nkCallKinds
  for i in 1..<n.len:
    var a = n[i]
    if a == nil: continue
    if a.kind == nkHiddenDeref: a = a[0]
    if a.kind == nkHiddenCallConv and a[0].kind == nkSym:
      markUsed(c, a.info, a[0].sym)

proc indexTypesMatch(c: PContext, f, a: PType, arg: PNode): PNode =
  var m = newCandidate(c, f)
  result = paramTypesMatch(m, f, a, arg, nil)
  if m.genericConverter and result != nil:
    instGenericConvertersArg(c, result, m)

proc inferWithMetatype(c: PContext, formal: PType,
                       arg: PNode, coerceDistincts = false): PNode =
  var m = newCandidate(c, formal)
  m.coerceDistincts = coerceDistincts
  result = paramTypesMatch(m, formal, arg.typ, arg, nil)
  if m.genericConverter and result != nil:
    instGenericConvertersArg(c, result, m)
  if result != nil:
    # This almost exactly replicates the steps taken by the compiler during
    # param matching. It performs an embarrassing amount of back-and-forth
    # type jugling, but it's the price to pay for consistency and correctness
    result.typ() = generateTypeInstance(c, m.bindings, arg.info,
                                      formal.skipTypes({tyCompositeTypeClass}))
  else:
    typeMismatch(c.config, arg.info, formal, arg.typ, arg)
    # error correction:
    result = copyTree(arg)
    result.typ() = formal

proc updateDefaultParams(c: PContext, call: PNode) =
  # In generic procs, the default parameter may be unique for each
  # instantiation (see tlateboundgenericparams).
  # After a call is resolved, we need to re-assign any default value
  # that was used during sigmatch. sigmatch is responsible for marking
  # the default params with `nfDefaultParam` and `instantiateProcType`
  # computes correctly the default values for each instantiation.
  let calleeParams = call[0].sym.typ.n
  for i in 1..<call.len:
    if nfDefaultParam in call[i].flags:
      let formal = calleeParams[i].sym
      let def = formal.ast
      if nfDefaultRefsParam in def.flags: call.flags.incl nfDefaultRefsParam
      # mirrored with sigmatch:
      if def.kind == nkEmpty:
        # The default param value is set to empty in `instantiateProcType`
        # when the type of the default expression doesn't match the type
        # of the instantiated proc param:
        pushInfoContext(c.config, call.info, call[0].sym.detailedInfo)
        typeMismatch(c.config, def.info, formal.typ, def.typ, formal.ast)
        popInfoContext(c.config)
        def.typ() = errorType(c)
      call[i] = def

proc getCallLineInfo(n: PNode): TLineInfo =
  case n.kind
  of nkAccQuoted, nkBracketExpr, nkCall, nkCallStrLit, nkCommand:
    if len(n) > 0:
      return getCallLineInfo(n[0])
  of nkDotExpr:
    if len(n) > 1:
      return getCallLineInfo(n[1])
  else:
    discard
  result = n.info

proc inheritBindings(c: PContext, x: var TCandidate, expectedType: PType) =
  ## Helper proc to inherit bound generic parameters from expectedType into x.
  ## Does nothing if 'inferGenericTypes' isn't in c.features.
  if inferGenericTypes notin c.features: return
  if expectedType == nil or x.callee.returnType == nil: return # required for inference

  var
    flatUnbound: seq[PType] = @[]
    flatBound: seq[PType] = @[]
  # seq[(result type, expected type)]
  var typeStack = newSeq[(PType, PType)]()

  template stackPut(a, b) =
    ## skips types and puts the skipped version on stack
    # It might make sense to skip here one by one. It's not part of the main
    #  type reduction because the right side normally won't be skipped
    const toSkip = {tyVar, tyLent, tyStatic, tyCompositeTypeClass, tySink}
    let
      x = a.skipTypes(toSkip)
      y = if a.kind notin toSkip: b
          else: b.skipTypes(toSkip)
    typeStack.add((x, y))

  stackPut(x.callee.returnType, expectedType)

  while typeStack.len() > 0:
    let (t, u) = typeStack.pop()
    if t == u or t == nil or u == nil or t.kind == tyAnything or u.kind == tyAnything:
      continue
    case t.kind
    of ConcreteTypes, tyGenericInvocation, tyUncheckedArray:
      # XXX This logic makes no sense for `tyUncheckedArray`
      # nested, add all the types to stack
      let
        startIdx = if u.kind in ConcreteTypes: 0 else: 1
        endIdx = min(u.kidsLen() - startIdx, t.kidsLen())

      for i in startIdx ..< endIdx:
        # early exit with current impl
        if t[i] == nil or u[i] == nil: return
        stackPut(t[i], u[i])
    of tyGenericParam:
      let prebound = x.bindings.lookup(t)
      if prebound != nil:
        continue # Skip param, already bound

      # fully reduced generic param, bind it
      if t notin flatUnbound:
        flatUnbound.add(t)
        flatBound.add(u)
    else:
      discard
  # update bindings
  for i in 0 ..< flatUnbound.len():
    x.bindings.put(flatUnbound[i], flatBound[i])

proc semResolvedCall(c: PContext, x: var TCandidate,
                     n: PNode, flags: TExprFlags;
                     expectedType: PType = nil): PNode =
  assert x.state == csMatch
  var finalCallee = x.calleeSym
  let info = getCallLineInfo(n)
  markUsed(c, info, finalCallee)
  onUse(info, finalCallee)
  assert finalCallee.ast != nil
  if x.matchedErrorType:
    result = x.call
    result[0] = newSymNode(finalCallee, getCallLineInfo(result[0]))
    if containsGenericType(result.typ):
      result.typ() = newTypeS(tyError, c)
      incl result.typ.flags, tfCheckedForDestructor
    return
  let gp = finalCallee.ast[genericParamsPos]
  if gp.isGenericParams:
    if x.calleeSym.kind notin {skMacro, skTemplate}:
      if x.calleeSym.magic in {mArrGet, mArrPut}:
        finalCallee = x.calleeSym
      else:
        c.inheritBindings(x, expectedType)
        finalCallee = generateInstance(c, x.calleeSym, x.bindings, n.info)
    else:
      # For macros and templates, the resolved generic params
      # are added as normal params.
      c.inheritBindings(x, expectedType)
      for s in instantiateGenericParamList(c, gp, x.bindings):
        case s.kind
        of skConst:
          if not s.astdef.isNil:
            x.call.add s.astdef
          else:
            x.call.add c.graph.emptyNode
        of skType:
          var tn = newSymNode(s, n.info)
          # this node will be used in template substitution,
          # pretend this is an untyped node and let regular sem handle the type
          # to prevent problems where a generic parameter is treated as a value
          tn.typ() = nil
          x.call.add tn
        else:
          internalAssert c.config, false

  result = x.call
  instGenericConvertersSons(c, result, x)
  markConvertersUsed(c, result)
  result[0] = newSymNode(finalCallee, getCallLineInfo(result[0]))
  if finalCallee.magic notin {mArrGet, mArrPut}:
    result.typ() = finalCallee.typ.returnType
  updateDefaultParams(c, result)

proc canDeref(n: PNode): bool {.inline.} =
  result = n.len >= 2 and (let t = n[1].typ;
    t != nil and t.skipTypes({tyGenericInst, tyAlias, tySink}).kind in {tyPtr, tyRef})

proc tryDeref(n: PNode): PNode =
  result = newNodeI(nkHiddenDeref, n.info)
  result.typ() = n.typ.skipTypes(abstractInst)[0]
  result.add n

proc semOverloadedCall(c: PContext, n, nOrig: PNode,
                       filter: TSymKinds, flags: TExprFlags;
                       expectedType: PType = nil): PNode =
  var errors: CandidateErrors = @[] # if efExplain in flags: @[] else: nil
  var r = resolveOverloads(c, n, nOrig, filter, flags, errors, efExplain in flags)
  if r.state == csMatch:
    # this may be triggered, when the explain pragma is used
    if errors.len > 0:
      let (_, candidates) = presentFailedCandidates(c, n, errors)
      message(c.config, n.info, hintUserRaw,
              "Non-matching candidates for " & renderTree(n) & "\n" &
              candidates)
    result = semResolvedCall(c, r, n, flags, expectedType)
  else:
    if c.inGenericContext > 0 and c.matchedConcept == nil:
      result = semGenericStmt(c, n)
      result.typ() = makeTypeFromExpr(c, result.copyTree)
    elif efExplain notin flags:
      # repeat the overload resolution,
      # this time enabling all the diagnostic output (this should fail again)
      result = semOverloadedCall(c, n, nOrig, filter, flags + {efExplain})
    elif efNoUndeclared notin flags:
      result = nil
      notFoundError(c, n, errors)
    else:
      result = nil

proc explicitGenericInstError(c: PContext; n: PNode): PNode =
  localError(c.config, getCallLineInfo(n), errCannotInstantiateX % renderTree(n))
  result = n

proc explicitGenericSym(c: PContext, n: PNode, s: PSym, errors: var CandidateErrors, doError: bool): PNode =
  if s.kind in {skTemplate, skMacro}:
    internalError c.config, n.info, "cannot get explicitly instantiated symbol of " &
      (if s.kind == skTemplate: "template" else: "macro")
  # binding has to stay 'nil' for this to work!
  var m = newCandidate(c, s, nil)
  matchGenericParams(m, n, s)
  if m.state != csMatch:
    # state is csMatch only if *all* generic params were matched,
    # including implicit parameters
    if doError:
      errors.add(CandidateError(
        sym: s,
        firstMismatch: m.firstMismatch,
        diagnostics: m.diagnostics))
    return nil
  var newInst = generateInstance(c, s, m.bindings, n.info)
  newInst.typ.flags.excl tfUnresolved
  let info = getCallLineInfo(n)
  markUsed(c, info, s)
  onUse(info, s)
  result = newSymNode(newInst, info)

proc setGenericParams(c: PContext, n, expectedParams: PNode) =
  ## sems generic params in subscript expression
  for i in 1..<n.len:
    let
      constraint =
        if expectedParams != nil and i <= expectedParams.len:
          expectedParams[i - 1].typ
        else:
          nil
      e = semExprWithType(c, n[i], expectedType = constraint)
    if e.typ == nil:
      n[i].typ() = errorType(c)
    else:
      n[i].typ() = e.typ.skipTypes({tyTypeDesc})

proc explicitGenericInstantiation(c: PContext, n: PNode, s: PSym, doError: bool): PNode =
  assert n.kind == nkBracketExpr
  setGenericParams(c, n, s.ast[genericParamsPos])
  var s = s
  var a = n[0]
  var errors: CandidateErrors = @[]
  if a.kind == nkSym:
    # common case; check the only candidate has the right
    # number of generic type parameters:
    result = explicitGenericSym(c, n, s, errors, doError)
    if result == nil:
      if c.inGenericContext > 0:
        # same as in semOverloadedCall, make expression untyped,
        # may have failed match due to unresolved types
        result = semGenericStmt(c, n)
        result.typ() = makeTypeFromExpr(c, result.copyTree)
      elif doError:
        notFoundError(c, n, errors)
  elif a.kind in {nkClosedSymChoice, nkOpenSymChoice}:
    # choose the generic proc with the proper number of type parameters.
    result = newNodeI(a.kind, getCallLineInfo(n))
    for i in 0..<a.len:
      var candidate = a[i].sym
      if candidate.kind in {skProc, skMethod, skConverter,
                            skFunc, skIterator}:
        let x = explicitGenericSym(c, n, candidate, errors, doError)
        if x != nil: result.add(x)
        elif c.inGenericContext > 0:
          # same as in semOverloadedCall, make expression untyped,
          # may have failed match due to unresolved types
          # any failing match stops building the symchoice for correctness,
          # can also make it untyped from the start
          result = semGenericStmt(c, n)
          result.typ() = makeTypeFromExpr(c, result.copyTree)
          return
    # get rid of nkClosedSymChoice if not ambiguous:
    if result.len == 0:
      result = nil
      if doError:
        notFoundError(c, n, errors)
  else:
    # probably unreachable: we are trying to instantiate `a` which is not
    # a sym/symchoice
    if doError:
      result = explicitGenericInstError(c, n)
    else:
      result = nil

proc searchForBorrowProc(c: PContext, startScope: PScope, fn: PSym): tuple[s: PSym, state: TBorrowState] =
  # Searches for the fn in the symbol table. If the parameter lists are suitable
  # for borrowing the sym in the symbol table is returned, else nil.
  # New approach: generate fn(x, y, z) where x, y, z have the proper types
  # and use the overloading resolution mechanism:
  const desiredTypes = abstractVar + {tyCompositeTypeClass} - {tyTypeDesc, tyDistinct}

  template getType(isDistinct: bool; t: PType):untyped =
    if isDistinct: t.baseOfDistinct(c.graph, c.idgen) else: t

  result = default(tuple[s: PSym, state: TBorrowState])
  var call = newNodeI(nkCall, fn.info)
  var hasDistinct = false
  var isDistinct: bool
  var x: PType
  var t: PType
  call.add(newIdentNode(fn.name, fn.info))
  for i in 1..<fn.typ.n.len:
    let param = fn.typ.n[i]
    #[.
      # We only want the type not any modifiers such as `ptr`, `var`, `ref` ...
      # tyCompositeTypeClass is here for
      # when using something like:
      type Foo[T] = distinct int
      proc `$`(f: Foo): string {.borrow.}
      # We want to skip the `Foo` to get `int`
    ]#
    t = skipTypes(param.typ, desiredTypes)
    isDistinct = t.kind == tyDistinct or param.typ.kind == tyDistinct
    if t.kind == tyGenericInvocation and t.genericHead.last.kind == tyDistinct:
      result.state = bsGeneric
      return
    if isDistinct: hasDistinct = true
    if param.typ.kind == tyVar:
      x = newTypeS(param.typ.kind, c)
      x.addSonSkipIntLit(getType(isDistinct, t), c.idgen)
    else:
      x = getType(isDistinct, t)
    var s = copySym(param.sym, c.idgen)
    s.typ = x
    s.info = param.info
    call.add(newSymNode(s))
  if hasDistinct:
    let filter = if fn.kind in {skProc, skFunc}: {skProc, skFunc} else: {fn.kind}
    var resolved = semOverloadedCall(c, call, call, filter, {})
    if resolved != nil:
      result.s = resolved[0].sym
      result.state = bsMatch
      if not compareTypes(result.s.typ.returnType, fn.typ.returnType, dcEqIgnoreDistinct, {IgnoreFlags}):
        result.state = bsReturnNotMatch
      elif result.s.magic in {mArrPut, mArrGet}:
        # cannot borrow these magics for now
        result.state = bsNotSupported
  else:
    result.state = bsNoDistinct

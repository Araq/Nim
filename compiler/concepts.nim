#
#
#           The Nim Compiler
#        (c) Copyright 2020 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## New styled concepts for Nim. See https://github.com/nim-lang/RFCs/issues/168
## for details. Note this is a first implementation and only the "Concept matching"
## section has been implemented.

import ast, semdata, lookups, lineinfos, idents, msgs, renderer, types, layeredtable

import std/intsets

when defined(nimPreviewSlimSystem):
  import std/assertions

const
  logBindings = false

## Code dealing with Concept declarations
## --------------------------------------

proc declareSelf(c: PContext; info: TLineInfo) =
  ## Adds the magical 'Self' symbols to the current scope.
  let ow = getCurrOwner(c)
  let s = newSym(skType, getIdent(c.cache, "Self"), c.idgen, ow, info)
  s.typ = newType(tyTypeDesc, c.idgen, ow)
  s.typ.flags.incl {tfUnresolved, tfPacked}
  s.typ.add newType(tyEmpty, c.idgen, ow)
  addDecl(c, s, info)

proc semConceptDecl(c: PContext; n: PNode): PNode =
  ## Recursive helper for semantic checking for the concept declaration.
  ## Currently we only support (possibly empty) lists of statements
  ## containing 'proc' declarations and the like.
  case n.kind
  of nkStmtList, nkStmtListExpr:
    result = shallowCopy(n)
    for i in 0..<n.len:
      result[i] = semConceptDecl(c, n[i])
  of nkProcDef..nkIteratorDef, nkFuncDef:
    result = c.semExpr(c, n, {efWantStmt})
  of nkTypeClassTy:
    result = shallowCopy(n)
    for i in 0..<n.len-1:
      result[i] = n[i]
    result[^1] = semConceptDecl(c, n[^1])
  of nkCommentStmt:
    result = n
  else:
    localError(c.config, n.info, "unexpected construct in the new-styled concept: " & renderTree(n))
    result = n

proc semConceptDeclaration*(c: PContext; n: PNode): PNode =
  ## Semantic checking for the concept declaration. Runs
  ## when we process the concept itself, not its matching process.
  assert n.kind == nkTypeClassTy
  inc c.inConceptDecl
  openScope(c)
  declareSelf(c, n.info)
  result = semConceptDecl(c, n)
  rawCloseScope(c)
  dec c.inConceptDecl

## Concept matching
## ----------------

type
  MatchCon = object ## Context we pass around during concept matching.
    inferred: seq[(PType, PType)] ## we need a seq here so that we can easily undo inferences \
      ## that turned out to be wrong.
    marker: IntSet ## Some protection against wild runaway recursions.
    potentialImplementation: PType ## the concrete type that might match the concept we try to match.
    magic: TMagic  ## mArrGet and mArrPut is wrong in system.nim and
                   ## cannot be fixed that easily.
                   ## Thus we special case it here.
    concpt: PType  ## current concept being evaluated
    strict = true  ## flag for `Self` and `each` and other scenareos were strict matching is off

proc existingBinding(m: MatchCon; key: PType): PType =
  ## checks if we bound the type variable 'key' already to some
  ## concrete type.
  for i in 0..<m.inferred.len:
    if m.inferred[i][0] == key: return m.inferred[i][1]
  return nil

proc conceptMatchNode(c: PContext; n: PNode; m: var MatchCon): bool

proc matchType(c: PContext; fo, ao: PType; m: var MatchCon): bool

proc matchReturnType(c: PContext; f, a: PType; m: var MatchCon): bool

proc defSignatureType(n: PNode): PType = n[0].sym.typ

proc conceptBody(n: PType): PNode = n.n.lastSon

proc isEach(t: PType): bool = t.kind == tyGenericInvocation and t.genericHead.sym.name.s == "TypeEach"

proc acceptsAllTypes(t: PType): bool=
  result = false
  if t.kind == tyAnything:
    result = true
  elif t.kind == tyGenericParam:
    if tfImplicitTypeParam in t.flags:
      result = true
    if not(t.hasElementType) or t.elementType.kind == tyNone:
      result = true

iterator travStmts(n: PNode): PNode {. closure .} =
  if n.kind in {nkStmtList, nkStmtListExpr}:
    for i in 0..<n.len:
      for sn in travStmts(n[i]):
        yield sn
  else:
    yield n

proc matchKids(c: PContext; f, a: PType; m: var MatchCon, start=0): bool=
  result = true
  for i in start..<f.kidsLen - ord(f.kind == tyGenericInst):
    if not matchType(c, f[i], a[i], m): return false

iterator traverseTyOr(t: PType): PType {. closure .}=
  for i in t.kids:
    case i.kind:
    of tyGenericParam:
      if i.hasElementType:
        for s in traverseTyOr(i.elementType):
          yield s
      else:
        yield i
    else:
      yield i

proc matchConceptToImpl(c: PContext, f, potentialImpl: PType; m: var MatchCon): bool =
  assert not(potentialImpl.reduceToBase.kind == tyConcept)
  if m.concpt.size == szIllegalRecursion:
    result = false
  var efPot = potentialImpl
  if potentialImpl.isSelf:
    if m.concpt.n == f.n:
      return true
    efPot = m.potentialImplementation
  
  let oldLen = m.inferred.len
  let oldPotentialImplementation = m.potentialImplementation
  m.potentialImplementation = efPot
  m.concpt.size = szIllegalRecursion
  let oldConcept = m.concpt
  m.concpt = f
  result = conceptMatchNode(c, f.conceptBody, m)
  m.potentialImplementation = oldPotentialImplementation
  m.concpt = oldConcept
  m.concpt.size = szUnknownSize
  if not result:
    m.inferred.setLen oldLen

proc cmpConceptDefs(c: PContext, fn, an: PNode, m: var MatchCon): bool=
  if an.kind notin {nkProcDef, nkFuncDef} and fn.kind != an.kind:
    return false
  if fn[namePos].sym.name != an[namePos].sym.name:
    return false
  if fn.len > an.len:
    return false
  let
    ft = fn.defSignatureType
    at = an.defSignatureType
  
  for i in 1 ..< ft.n.len:
    let oldLen = m.inferred.len
    if not matchType(c, ft.n[i].typ, at.n[i].typ, m):
      m.inferred.setLen oldLen
      return false
  result = true
  let oldLen = m.inferred.len
  if not matchReturnType(c, ft.returnType, at.returnType, m):
    m.inferred.setLen oldLen
    result = false

proc conceptsMatch(c: PContext, fc, ac: PType; m: var MatchCon): bool=
  # XXX: In the future this may need extra parameters to carry info for container types
  result = fc.n == ac.n
  if result:
    # This will have to take generic parameters into account at some point for container types
    return
  let
    fn = fc.conceptBody
    an = ac.conceptBody
  for fdef in fn:
    result = false
    for ndef in an:
      result = cmpConceptDefs(c, fdef, ndef, m)
      if result:
        break
    if not result:
      break

proc matchImplicitDef(c: PContext; fn, an: PNode; aConpt: PNode, m: var MatchCon): bool=
  let
    ft = fn.defSignatureType
    at = an.defSignatureType
  if fn.kind != an.kind:
    return false
  if fn.len > an.len:
    return false
  
  result = true
  for i in 1 ..< ft.n.len:
    var aType = at.n[i].typ
    if aType.reduceToBase.isSelf:
      # Self in `an` is always legal here
      continue
    var fType = ft.n[i].typ
    if fType.reduceToBase.isSelf:
      if fType.kind in {tyVar, tySink, tyLent, tyOwned} and aType.kind == fType.kind:
        aType = aType.elementType
        fType = m.potentialImplementation.skipTypes({tyVar, tySink, tyLent, tyOwned})
      else:
        fType = m.potentialImplementation
      if aType.kind == tyConcept and conceptsMatch(c, aType, m.concpt, m):
        return true
    let oldLen = m.inferred.len
    if not matchType(c, aType, fType, m):
      m.inferred.setLen oldLen
      return false

proc matchCodependentConcept(c: PContext; n: PNode; m: var MatchCon): bool =
  result = false
  let sig = n.defSignatureType.n
  for i in 1 ..< sig.len:
    let paramType = sig[i].typ
    if paramType.kind == tyGenericParam:
      # this may have to be changed to only parameters of the concept
      # generic parameters of the proc that are bound by concepts are subject to substitution
      continue
    if paramType.reduceToBase.kind == tyConcept:
      for aDef in travStmts(paramType.reduceToBase.conceptBody):
        if n[namePos].sym.name == aDef[namePos].sym.name:
          let oldStrict = m.strict
          m.strict = false
          result = matchImplicitDef(c, n, aDef, sig[i], m)
          m.strict = oldStrict

proc matchType(c: PContext; fo, ao: PType; m: var MatchCon): bool =
  ## The heart of the concept matching process. 'f' is the formal parameter of some
  ## routine inside the concept that we're looking for. 'a' is the formal parameter
  ## of a routine that might match.
  const
    ignorableForArgType = {tyVar, tySink, tyLent, tyOwned, tyGenericInst, tyAlias, tyInferred}
  
  template notStrict(body: untyped)=
    let oldStrict = m.strict
    m.strict = false
    body
    m.strict = oldStrict
  
  var
    a = ao
    f = fo
  
  if isEach(f):
    notStrict:
      return matchType(c, f.last, a, m)
  
  case a.kind
  of tyGenericParam:
    # I forget how bindings can end up here but they did once
    let binding = m.existingBinding(a)
    if binding != nil:
      a = binding
  of tyAnything:
    if m.strict:
      return true
  of tyNot:
    if m.strict:
      if f.kind == tyNot:
        return matchType(c, f.elementType, a.elementType, m)
      else:
        let oldLen = m.inferred.len
        result = not matchType(c, f, a.elementType, m)
        m.inferred.setLen oldLen
        return
  of tyCompositeTypeClass, tyGenericInst, tyConcept:
    let
      aBase = a.reduceToBase
      fBase = f.reduceToBase
    if aBase.kind == tyConcept:
      if fBase.kind == tyConcept:
        return conceptsMatch(c, fBase, aBase, m)
      else:
        return matchConceptToImpl(c, a, f, m)
  else:
    discard
  
  case f.kind
  of tyAlias:
    result = matchType(c, f.skipModifier, a, m)
  of tyTypeDesc:
    if isSelf(f):
      #let oldLen = m.inferred.len
      notStrict:
        result = matchType(c, a, m.potentialImplementation, m)
      #echo "self is? ", result, " ", a.kind, " ", a, " ", m.potentialImplementation, " ", m.potentialImplementation.kind
      #m.inferred.setLen oldLen
      #echo "A for ", result, " to ", typeToString(a), " to ", typeToString(m.potentialImplementation)
    else:
      result = false
      if a.kind == tyTypeDesc:
        if not(a.hasElementType) or a.elementType.kind == tyNone:
          result = true
        elif f.hasElementType:
          result = matchType(c, f.elementType, a.elementType, m)
  of tyGenericInvocation:
    result = false
    if f.genericHead.elementType.kind == tyConcept:
      result = matchType(c, f.genericHead.elementType, a, m)
    elif a.kind == tyGenericInst and a.genericHead.kind == tyGenericBody:
      if sameType(f.genericHead, a.genericHead) and f.kidsLen == a.kidsLen-1:
        result = matchKids(c, f, a, m, start=FirstGenericParamAt)
  of tyGenericParam:
    let ak = a.skipTypes({tyVar, tySink, tyLent, tyOwned})
    if ak.kind in {tyTypeDesc, tyStatic} and not isSelf(ak):
      result = false
    else:
      let old = existingBinding(m, f)
      if old == nil:
        if f.hasElementType and f.elementType.kind != tyNone:
          # also check the generic's constraints:
          let oldLen = m.inferred.len
          notStrict:
            # XXX: this should only be not strict for the current concept's parameters NOT the proc's
            result = matchType(c, f.elementType, a, m)
          m.inferred.setLen oldLen
          if result:
            when logBindings: echo "A adding ", f, " ", ak
            m.inferred.add((f, ak))
        elif m.magic == mArrGet and ak.kind in {tyArray, tyOpenArray, tySequence, tyVarargs, tyCstring, tyString}:
          when logBindings: echo "B adding ", f, " ", last ak
          m.inferred.add((f, last ak))
          result = true
        else:
          if tfImplicitTypeParam in f.flags:
            # this is another way of representing tyAnything?
            result = not(m.strict) or a.acceptsAllTypes
          else:
            when logBindings: echo "C adding ", f, " ", ak
            m.inferred.add((f, ak))
            #echo "binding ", typeToString(ak), " to ", typeToString(f)
            result = true
      elif not m.marker.containsOrIncl(old.id):
        notStrict:
          result = matchType(c, old, ak, m)
        if m.magic == mArrPut and ak.kind == tyGenericParam:
          result = true
      else:
        result = false
    #echo "B for ", result, " to ", typeToString(a), " to ", typeToString(m.potentialImplementation)
  of tyVar, tySink, tyLent, tyOwned:
    # modifiers in the concept must be there in the actual implementation
    # too but not vice versa.
    if a.kind == f.kind:
      result = matchType(c, f.elementType, a.elementType, m)
    elif m.magic == mArrPut:
      result = matchType(c, f.elementType, a, m)
    else:
      result = false
  of tyEnum, tyObject, tyDistinct:
    result = sameType(f, a)
  of tyEmpty, tyString, tyCstring, tyPointer, tyNil, tyUntyped, tyTyped, tyVoid:
    result = a.skipTypes(ignorableForArgType).kind == f.kind
  of tyBool, tyChar, tyInt..tyUInt64:
    let ak = a.skipTypes(ignorableForArgType)
    result = ak.kind == f.kind or ak.kind == tyOrdinal or
       (ak.kind == tyGenericParam and ak.hasElementType and ak.elementType.kind == tyOrdinal)
  of tyGenericBody:
    var ak = a
    if a.kind == tyGenericBody:
      ak = last(a)
    result = matchType(c, last(f), ak, m)
  of tyCompositeTypeClass:
    if a.kind == tyCompositeTypeClass:
      result = matchKids(c, f, a, m)
    else:
      result = matchType(c, last(f), a, m)
  of tyArray, tyTuple, tyVarargs, tyOpenArray, tyRange, tySequence, tyRef, tyPtr,
     tyGenericInst:
    # ^ XXX Rewrite this logic, it's more complex than it needs to be.
    if f.kind == tyArray and f.kidsLen == 3 and a.kind == tyArray:
      # XXX: this is a work-around!
      # system.nim creates these for the magic array typeclass
      result = true
    else:
      result = false
      let ak = a.skipTypes(ignorableForArgType - {f.kind})
      if ak.kind == f.kind and f.kidsLen == ak.kidsLen:
        result = matchKids(c, f, ak, m)
  of tyOr:
    result = false
    if m.strict:
      let oldLen = m.inferred.len
      if a.kind in {tyOr, tyGenericParam}:
        result = true
        for ff in traverseTyOr(f):
          result = false
          for aa in traverseTyOr(a):
            let oldLenB = m.inferred.len
            let r = matchType(c, ff, aa, m)
            if r:
              result = true
              break
            m.inferred.setLen oldLenB
          if not result:
            break
    else:
      let oldLen = m.inferred.len
      if a.kind == tyOr:
        # say the concept requires 'int|float|string' if the potentialImplementation
        # says 'int|string' that is good enough.
        var covered = 0
        for ff in f.kids:
          for aa in a.kids:
            let oldLenB = m.inferred.len
            let r = matchType(c, ff, aa, m)
            if r:
              inc covered
              break
            m.inferred.setLen oldLenB

        result = covered >= a.kidsLen
        if not result:
          m.inferred.setLen oldLen
      else:
        result = false
        for ff in f.kids:
          result = matchType(c, ff, a, m)
          if result: break # and remember the binding!
          m.inferred.setLen oldLen
  of tyNot:
    result = false
    if not m.strict:
      if a.kind == tyNot:
        result = matchType(c, f.elementType, a.elementType, m)
      else:
        let oldLen = m.inferred.len
        result = not matchType(c, f.elementType, a, m)
        m.inferred.setLen oldLen
  of tyConcept:
    # TODO: conceptsMatch's current logic is wrong rn, I think. fix with a test
    result = a.kind == tyConcept and conceptsMatch(c, f, a, m)
    if not (result or m.strict):  
      # this is for `each` parameters and generic parameters. Can search for a candidate iff
      # the concept (f) is a constraint and not a requirement
      result = matchConceptToImpl(c, f, a, m)
  of tyOrdinal:
    result = isOrdinalType(a, allowEnumWithHoles = false) or a.kind == tyGenericParam
  of tyAnything:
    result = not(m.strict) or a.acceptsAllTypes
  of tyStatic:
    result = false
    var scomp = f.base
    if scomp.kind == tyGenericParam:
      if f.base.kidsLen > 0:
        scomp = scomp.base
    if a.kind == tyStatic:
      result = matchType(c, scomp, a.base, m)
    else:
      result = matchType(c, scomp, a, m)
  else:
    result = false

proc matchReturnType(c: PContext; f, a: PType; m: var MatchCon): bool =
  ## Like 'matchType' but with extra logic dealing with proc return types
  ## which can be nil or the 'void' type.
  if f.isEmptyType:
    result = a.isEmptyType
  elif a == nil:
    result = false
  else:
    result = matchType(c, f, a, m)

proc matchSym(c: PContext; candidate: PSym, n: PNode; m: var MatchCon): bool =
  ## Checks if 'candidate' matches 'n' from the concept body. 'n' is a nkProcDef
  ## or similar.

  # watch out: only add bindings after a completely successful match.
  let oldLen = m.inferred.len

  let can = candidate.typ.n
  let con = defSignatureType(n).n

  if can.len < con.len:
    # too few arguments, cannot be a match:
    return false

  let common = min(can.len, con.len)
  for i in 1 ..< common:
    if not matchType(c, con[i].typ, can[i].typ, m):
      m.inferred.setLen oldLen
      return false

  if not matchReturnType(c, n.defSignatureType.returnType, candidate.typ.returnType, m):
    m.inferred.setLen oldLen
    return false

  # all other parameters have to be optional parameters:
  for i in common ..< can.len:
    assert can[i].kind == nkSym
    if can[i].sym.ast == nil:
      # has too many arguments one of which is not optional:
      m.inferred.setLen oldLen
      return false

  return true

proc matchSyms(c: PContext, n: PNode; kinds: set[TSymKind]; m: var MatchCon): bool =
  ## Walk the current scope, extract candidates which the same name as 'n[namePos]',
  ## 'n' is the nkProcDef or similar from the concept that we try to match.
  result = false
  var candidates = searchScopes(c, n[namePos].sym.name, kinds)
  searchImportsAll(c, n[namePos].sym.name, kinds, candidates)
  for candidate in candidates:
    #echo "considering ", typeToString(candidate.typ), " ", candidate.magic
    m.magic = candidate.magic
    if matchSym(c, candidate, n, m):
      result = true
      break
  if not result:
    # as a last resort we can assume that any inner concepts (not Self) are implemented
    result = matchCodependentConcept(c, n, m)

proc conceptMatchNode(c: PContext; n: PNode; m: var MatchCon): bool =
  ## Traverse the concept's AST ('n') and see if every declaration inside 'n'
  ## can be matched with the current scope.
  result = false
  for sn in travStmts(n):
    result = case sn.kind
      of nkProcDef, nkFuncDef:
        # procs match any of: proc, template, macro, func, method, converter.
        # The others are more specific.
        # XXX: Enforce .noSideEffect for 'nkFuncDef'? But then what are the use cases...
        const filter = {skProc, skTemplate, skMacro, skFunc, skMethod, skConverter}
        matchSyms(c, sn, filter, m)
      of nkTemplateDef:
        matchSyms(c, sn, {skTemplate}, m)
      of nkMacroDef:
        matchSyms(c, sn, {skMacro}, m)
      of nkConverterDef:
        matchSyms(c, sn, {skConverter}, m)
      of nkMethodDef:
        matchSyms(c, sn, {skMethod}, m)
      of nkIteratorDef:
        matchSyms(c, sn, {skIterator}, m)
      of nkCommentStmt:
        true
      else:
        false # error was reported earlier.
    if not result:
      return

proc conceptMatch*(c: PContext; concpt, arg: PType; bindings: var LayeredIdTable; invocation: PType): bool =
  ## Entry point from sigmatch. 'concpt' is the concept we try to match (here still a PType but
  ## we extract its AST via 'concpt.n.lastSon'). 'arg' is the type that might fulfill the
  ## concept's requirements. If so, we return true and fill the 'bindings' with pairs of
  ## (typeVar, instance) pairs. ('typeVar' is usually simply written as a generic 'T'.)
  ## 'invocation' can be nil for atomic concepts. For non-atomic concepts, it contains the
  ## `C[S, T]` parent type that we look for. We need this because we need to store bindings
  ## for 'S' and 'T' inside 'bindings' on a successful match. It is very important that
  ## we do not add any bindings at all on an unsuccessful match!
  var m = MatchCon(inferred: @[], potentialImplementation: arg, concpt: concpt)
  result = conceptMatchNode(c, concpt.conceptBody, m)
  if result:
    for (a, b) in m.inferred:
      if b.kind == tyGenericParam:
        var dest = b
        while true:
          dest = existingBinding(m, dest)
          if dest == nil or dest.kind != tyGenericParam: break
        if dest != nil:
          bindings.put(a, dest)
          when logBindings: echo "A bind ", a, " ", dest
      else:
        bindings.put(a, b)
        when logBindings: echo "B bind ", a, " ", b
    # we have a match, so bind 'arg' itself to 'concpt':
    bindings.put(concpt, arg)
    # invocation != nil means we have a non-atomic concept:
    if invocation != nil and arg.kind == tyGenericInst and invocation.kidsLen == arg.kidsLen-1:
      # bind even more generic parameters
      assert invocation.kind == tyGenericInvocation
      for i in FirstGenericParamAt ..< invocation.kidsLen:
        bindings.put(invocation[i], arg[i])

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

import ast, astalgo, semdata, lookups, lineinfos, idents, msgs, renderer, types, layeredtable

import std/intsets

when defined(nimPreviewSlimSystem):
  import std/assertions

const
  logBindings = when defined(debugConcepts): true else: false

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
  MatchFlags* = enum
    mfDontBind  # Do not bind generic parameters
    mfCheckGeneric  # formal <- formal comparison as opposed to formal <- operand
  
  MatchCon = object ## Context we pass around during concept matching.
    bindings: LayeredIdTable
    marker: IntSet ## Some protection against wild runaway recursions.
    potentialImplementation: PType ## the concrete type that might match the concept we try to match.
    magic: TMagic  ## mArrGet and mArrPut is wrong in system.nim and
                   ## cannot be fixed that easily.
                   ## Thus we special case it here.
    concpt: PType  ## current concept being evaluated
    depthCount = 0
    flags: set[MatchFlags]
    
  MatchKind = enum
    mkNoMatch, mkSubset, mkSame

const
  asymmetricConceptParamMods = {tyVar, tySink, tyLent, tyOwned, tyAlias, tyInferred} # param modifiers that to not have to match implementation -> concept
  bindableTypes = {tyGenericParam, tyOr, tyTypeDesc}

proc conceptMatchNode(c: PContext; n: PNode; m: var MatchCon): bool

proc matchType(c: PContext; fo, ao: PType; m: var MatchCon): bool

proc matchReturnType(c: PContext; f, a: PType; m: var MatchCon): bool

proc processConcept(c: PContext; concpt, invocation: PType, bindings: var LayeredIdTable; m: var MatchCon): bool

proc existingBinding(m: MatchCon; key: PType): PType =
  ## checks if we bound the type variable 'key' already to some
  ## concrete type.
  result = m.bindings.lookup(key)
  if result == nil:
    result = key

const
    ignorableForArgType = {tyVar, tySink, tyLent, tyOwned, tyAlias, tyInferred}

proc unrollGenericParam(param: PType): PType =
  result = param.skipTypes(ignorableForArgType)
  while result.kind in {tyGenericParam, tyTypeDesc} and result.hasElementType and result.elementType.kind != tyNone:
    result = result.elementType

proc bindParam(c: PContext, m: var MatchCon; key, v: PType): bool {. discardable .} =
  if v.kind == tyTypeDesc:
    return false
  var value = unrollGenericParam(v)
  if value.kind == tyGenericParam:
    value = existingBinding(m, value)
    if value.kind == tyGenericParam:
      if value.hasElementType:
        value = value.elementType
      else:
        return true
  if value.kind == tyStatic:
    return false

  if m.magic in {mArrPut, mArrGet} and value.kind in arrPutGetMagicApplies:
    value = value.last
  
  let old = existingBinding(m, key)
  if old != key:
    # check previously bound value
    if not matchType(c, old, value, m):
      return false
  elif key.hasElementType and key.elementType.kind != tyNone:
    # check constaint
    if matchType(c, unrollGenericParam(key), value, m) == false:
      return false
  
  when logBindings: echo "bind table adding '", key, "', ", value
  assert value != nil
  assert value.kind != tyVoid
  m.bindings.put(key, value)
  return true

proc defSignatureType(n: PNode): PType = n[0].sym.typ

proc conceptBody*(n: PType): PNode = n.n.lastSon

proc acceptsAllTypes(t: PType): bool=
  result = false
  if t.kind == tyAnything:
    result = true
  elif t.kind == tyGenericParam:
    if tfImplicitTypeParam in t.flags:
      result = true
    if not t.hasElementType or t.elementType.kind == tyNone:
      result = true

proc procDefSignature(s: PSym): PNode {. deprecated .} = 
  var nc = s.ast.copyNode()
  for i in 0 .. 5:
    nc.add s.ast[i]
  nc

proc matchKids(c: PContext; f, a: PType; m: var MatchCon, start=0): bool=
  result = true
  for i in start ..< f.kidsLen - ord(f.kind in {tyGenericInst, tyGenericInvocation}):
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
  let concpt = f.reduceToBase
  if m.depthCount > 0:
    # concepts that are more then 2 levels deep are treated like
    # tyAnything to stop dependencies from getting out of control
    return true
  var efPot = potentialImpl
  if potentialImpl.isSelf:
    if m.concpt.n == concpt.n:
      return true
    efPot = m.potentialImplementation
  
  var oldBindings = m.bindings
  m.bindings = newTypeMapLayer(m.bindings)
  let oldPotentialImplementation = m.potentialImplementation
  m.potentialImplementation = efPot
  let oldConcept = m.concpt
  m.concpt = concpt
  
  var invocation: PType = nil
  if f.kind == tyGenericInvocation:
    invocation = f
  inc m.depthCount
  result = processConcept(c, concpt, invocation, oldBindings, m)
  dec m.depthCount
  m.potentialImplementation = oldPotentialImplementation
  m.concpt = oldConcept

proc cmpConceptDefs(c: PContext, fn, an: PNode, m: var MatchCon): bool=
  if fn.kind != an.kind:
    return false
  if fn[namePos].sym.name != an[namePos].sym.name:
    return false
  let
    ft = fn.defSignatureType
    at = an.defSignatureType
  if ft.len != at.len:
    return false
  
  for i in 1 ..< ft.n.len:
    m.bindings = m.bindings.newTypeMapLayer()
    
    let aType = at.n[i].typ
    let fType = ft.n[i].typ
    
    if aType.isSelf and fType.isSelf:
      continue
    
    if not matchType(c, fType, aType, m):
      m.bindings.setToPreviousLayer()
      return false
  result = true
  if not matchReturnType(c, ft.returnType, at.returnType, m):
    m.bindings.setToPreviousLayer()
    result = false

proc conceptsMatch(c: PContext, fc, ac: PType; m: var MatchCon): MatchKind =
  # XXX: In the future this may need extra parameters to carry info for container types
  if fc.n == ac.n:
    # This will have to take generic parameters into account at some point
    return mkSame
  let
    fn = fc.conceptBody
    an = ac.conceptBody
    sameLen = fc.len == ac.len
  var match = false
  for fdef in fn:
    var cmpResult = false
    for ia, ndef in an:
      match = cmpConceptDefs(c, fdef, ndef, m)
      if match:
        break
    if not match:
      return mkNoMatch
  return mkSubset

proc matchType(c: PContext; fo, ao: PType; m: var MatchCon): bool =
  ## The heart of the concept matching process. 'f' is the formal parameter of some
  ## routine inside the concept that we're looking for. 'a' is the formal parameter
  ## of a routine that might match.
  
  var
    a = ao
    f = fo
  
  if a.kind in bindableTypes:
    a = existingBinding(m, ao)
    if a == ao and a.kind == tyGenericParam and a.hasElementType and a.elementType.kind != tyNone:
      a = a.elementType
  
  if f.isConcept:
    if a.acceptsAllTypes:
      return false
    if a.isConcept:
      # if f is a subset of a then any match to a will also match f. Not the other way around
      return conceptsMatch(c, a.reduceToBase, f.reduceToBase, m) >= mkSubset
    else:
      return matchConceptToImpl(c, f.reduceToBase, a, m)
  
  result = false

  case f.kind
  of tyAlias:
    result = matchType(c, f.skipModifier, a, m)
  of tyTypeDesc:
    if isSelf(f):
      let ua = a.skipTypes(asymmetricConceptParamMods)
      if m.magic in {mArrPut, mArrGet}:
        if m.potentialImplementation.reduceToBase.kind in arrPutGetMagicApplies:
          bindParam(c, m, a, last m.potentialImplementation)
          result = true
      #elif ua.isConcept:
      #  result = matchType(c, m.concpt, ua, m)
      else:
        result = matchType(c, a.skipTypes(ignorableForArgType), m.potentialImplementation, m)
    else:
      if a.kind == tyTypeDesc:
        if not(a.hasElementType) or a.elementType.kind == tyNone:
          result = true
        elif f.hasElementType:
          result = matchType(c, f.elementType, a.elementType, m)
  of tyVar, tySink, tyLent, tyOwned:
    # modifiers in the concept must be there in the actual implementation
    # too but not vice versa.
    if a.kind == f.kind:
      result = matchType(c, f.elementType, a.elementType, m)
    elif m.magic == mArrPut:
      result = matchType(c, f.elementType, a, m)
  of tyEnum, tyObject, tyDistinct:
    if a.kind in ignorableForArgType:
      result = matchType(c, f, a.skipTypes(ignorableForArgType), m)
    else:
      result = sameType(f, a)
  of tyEmpty, tyString, tyCstring, tyPointer, tyNil, tyUntyped, tyTyped, tyVoid:
    result = a.skipTypes(ignorableForArgType).kind == f.kind
  of tyBool, tyChar, tyInt..tyUInt64:
    let ak = a.skipTypes(ignorableForArgType)
    result = ak.kind == f.kind or ak.kind == tyOrdinal or
      (ak.kind == tyGenericParam and ak.hasElementType and ak.elementType.kind == tyOrdinal)
  of tyArray, tyTuple, tyVarargs, tyOpenArray, tyRange, tySequence, tyRef, tyPtr:
    if f.kind == tyArray and f.kidsLen == 3 and a.kind == tyArray:
      # XXX: this is a work-around!
      # system.nim creates these for the magic array typeclass
      result = true
    else:
      let ak = a.skipTypes(ignorableForArgType - {f.kind})
      if ak.kind == f.kind and f.kidsLen == ak.kidsLen:
        result = matchKids(c, f, ak, m)
  of tyGenericInvocation, tyGenericInst:
    result = false
    let ea = a.skipTypes(ignorableForArgType)
    if ea.kind in {tyGenericInst, tyGenericInvocation}:
      var
        k1 = f.kidsLen - ord(f.kind == tyGenericInst)
        k2 = ea.kidsLen - ord(ea.kind == tyGenericInst)
      if sameType(f.genericHead, ea.genericHead) and k1 == k2:
        for i in 1 ..< k2:
          if not matchType(c, f[i], ea[i], m):
            break
        result = true
  of tyOrdinal:
    result = isOrdinalType(a, allowEnumWithHoles = false) or a.kind == tyGenericParam
  of tyStatic:
    var scomp = f.base
    if scomp.kind == tyGenericParam:
      if f.base.kidsLen > 0:
        scomp = scomp.base
    if a.kind == tyStatic:
      result = matchType(c, scomp, a.base, m)
    else:
      result = matchType(c, scomp, a, m)
  of tyGenericParam:
    if a.acceptsAllTypes:
      result = f.acceptsAllTypes
    else:
      result = bindParam(c, m, f, a)
  of tyAnything:
    result = true
  of tyNot:
    if a.kind == tyNot:
      result = matchType(c, f.elementType, a.elementType, m)
    else:
      m.bindings = m.bindings.newTypeMapLayer()
      result = not matchType(c, f.elementType, a, m)
      m.bindings.setToPreviousLayer()
  of tyAnd:
    m.bindings = m.bindings.newTypeMapLayer()
    result = true
    for ff in traverseTyOr(f):
      let r = matchType(c, ff, a, m)
      if not r:
        m.bindings.setToPreviousLayer()
        result = false
        break
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
  of tyBuiltInTypeClass:
    let target = f.genericHead.kind
    result = a.skipTypes(ignorableForArgType).reduceToBase.kind == target
  of tyOr:
    if a.kind == tyOr:
      var covered = 0
      for ff in traverseTyOr(f):
        for aa in traverseTyOr(a):
          m.bindings = m.bindings.newTypeMapLayer()
          let r = matchType(c, ff, aa, m)
          if r:
            inc covered
            break
          m.bindings.setToPreviousLayer()

      result = covered >= a.kidsLen
    else:
      for ff in f.kids:
        m.bindings = m.bindings.newTypeMapLayer()
        result = matchType(c, ff, a, m)
        if result: break # and remember the binding!
        m.bindings.setToPreviousLayer()
  else:
    result = false
  if result and ao.kind == tyGenericParam:
    let bf = if f.isSelf: m.potentialImplementation else: f
    if bindParam(c, m, ao, bf):
      when logBindings: echo " ^ reverse binding"

proc checkConstraint(c: PContext; f, a: PType; m: var MatchCon): bool =
  result = matchType(c, f, a, m) or matchType(c, a, f, m)

proc matchReturnType(c: PContext; f, a: PType; m: var MatchCon): bool =
  ## Like 'matchType' but with extra logic dealing with proc return types
  ## which can be nil or the 'void' type.
  if f.isEmptyType:
    result = a.isEmptyType
  elif a == nil:
    result = false
  else:
    result = checkConstraint(c, f, a, m)

proc matchSym(c: PContext; candidate: PSym, n: PNode; m: var MatchCon): bool =
  ## Checks if 'candidate' matches 'n' from the concept body. 'n' is a nkProcDef
  ## or similar.

  # watch out: only add bindings after a completely successful match.
  m.bindings = m.bindings.newTypeMapLayer()

  let can = candidate.typ.n
  let con = defSignatureType(n).n
  if can.len < con.len:
    # too few arguments, cannot be a match:
    return false
  
  if can.len > con.len:
    # too many arguments (not optional)
    for i in con.len ..< can.len:
      if can[i].sym.ast == nil:
        return false
  
  when defined(debugConcepts):
    echo "considering: ", renderTree(candidate.procDefSignature), " ", candidate.magic
  
  let common = min(can.len, con.len)
  for i in 1 ..< common:
    if not checkConstraint(c, con[i].typ, can[i].typ, m):
      m.bindings.setToPreviousLayer()
      return false
  
  if not matchReturnType(c, n.defSignatureType.returnType, candidate.typ.returnType, m):
    m.bindings.setToPreviousLayer()
    return false

  # all other parameters have to be optional parameters:
  for i in common ..< can.len:
    assert can[i].kind == nkSym
    if can[i].sym.ast == nil:
      # has too many arguments one of which is not optional:
      m.bindings.setToPreviousLayer()
      return false

  return true

proc matchSyms(c: PContext, n: PNode; kinds: set[TSymKind]; m: var MatchCon): bool =
  ## Walk the current scope, extract candidates which the same name as 'n[namePos]',
  ## 'n' is the nkProcDef or similar from the concept that we try to match.
  result = false
  var candidates = searchScopes(c, n[namePos].sym.name, kinds)
  searchImportsAll(c, n[namePos].sym.name, kinds, candidates)
  for candidate in candidates:
    m.magic = candidate.magic
    if matchSym(c, candidate, n, m):
      result = true
      break

proc conceptMatchNode(c: PContext; n: PNode; m: var MatchCon): bool =
  ## Traverse the concept's AST ('n') and see if every declaration inside 'n'
  ## can be matched with the current scope.
  case n.kind
  of nkStmtList, nkStmtListExpr:
    for i in 0..<n.len:
      if not conceptMatchNode(c, n[i], m):
        return false
    return true
  of nkProcDef, nkFuncDef:
    # procs match any of: proc, template, macro, func, method, converter.
    # The others are more specific.
    # XXX: Enforce .noSideEffect for 'nkFuncDef'? But then what are the use cases...
    const filter = {skProc, skTemplate, skMacro, skFunc, skMethod, skConverter}
    result = matchSyms(c, n, filter, m)
  of nkTemplateDef:
    result = matchSyms(c, n, {skTemplate}, m)
  of nkMacroDef:
    result = matchSyms(c, n, {skMacro}, m)
  of nkConverterDef:
    result = matchSyms(c, n, {skConverter}, m)
  of nkMethodDef:
    result = matchSyms(c, n, {skMethod}, m)
  of nkIteratorDef:
    result = matchSyms(c, n, {skIterator}, m)
  of nkCommentStmt:
    result = true
  else:
    # error was reported earlier.
    result = false

proc fixBindings(bindings: var LayeredIdTable; concpt: PType; invocation: PType; m: var MatchCon) =
  # invocation != nil means we have a non-atomic concept:
  if invocation != nil and invocation.kind == tyGenericInvocation:
    assert concpt.sym.typ.kind == tyGenericBody
    
    for i in 0 .. concpt.sym.typ.len - 1:
      let thisSym = concpt.sym.typ[i]
      if lookup(bindings, thisSym) != nil:
        # dont trust the bindings over existing ones
        continue
      let found = m.bindings.lookup(thisSym)
      if found != nil:
        when logBindings: echo "Invocation bind: ", thisSym, " ", found
        bindings.put(thisSym, found)
    
    # bind even more generic parameters
    let genBody = invocation.base
    assert genBody.kind == tyGenericBody
    for i in FirstGenericParamAt ..< invocation.kidsLen:
      let bpram = genBody[i - 1]
      if lookup(bindings, invocation[i]) != nil:
        # dont trust the bindings over existing ones
        continue
      let boundV = lookup(bindings, bpram)
      when logBindings: echo "generic body bind: '", invocation[i], "' '", boundV, "'"
      if boundV != nil:
        bindings.put(invocation[i], boundV)
  bindings.put(concpt, m.potentialImplementation)

proc processConcept(c: PContext; concpt, invocation: PType, bindings: var LayeredIdTable; m: var MatchCon): bool =
  m.bindings = m.bindings.newTypeMapLayer()
  if invocation != nil and invocation.kind == tyGenericInst:
    let genericBody = invocation.base
    for i in 1..<invocation.kidsLen-1:
      # instGenericContainer can bind `tyVoid`
      if invocation[i].kind != tyVoid:
        bindParam(c, m, genericBody[i-1], invocation[i])
  result = conceptMatchNode(c, concpt.conceptBody, m)
  if result and mfDontBind notin m.flags:
    fixBindings(bindings, concpt, invocation, m)

proc conceptMatch*(c: PContext; concpt, arg: PType; bindings: var LayeredIdTable; invocation: PType, flags: set[MatchFlags] = {}): bool =
  ## Entry point from sigmatch. 'concpt' is the concept we try to match (here still a PType but
  ## we extract its AST via 'concpt.n.lastSon'). 'arg' is the type that might fulfill the
  ## concept's requirements. If so, we return true and fill the 'bindings' with pairs of
  ## (typeVar, instance) pairs. ('typeVar' is usually simply written as a generic 'T'.)
  ## 'invocation' can be nil for atomic concepts. For non-atomic concepts, it contains the
  ## `C[S, T]` parent type that we look for. We need this because we need to store bindings
  ## for 'S' and 'T' inside 'bindings' on a successful match. It is very important that
  ## we do not add any bindings at all on an unsuccessful match!
  var m = MatchCon(bindings: bindings, potentialImplementation: arg, concpt: concpt, flags: flags)
  if arg.isConcept:
    result = conceptsMatch(c, concpt.reduceToBase, arg.reduceToBase, m) >= mkSubset
  elif arg.acceptsAllTypes:
    # XXX: I think this is wrong, or at least partially wrong. Can still test ambiguous types
    result = false
  elif mfCheckGeneric in m.flags:
    # prioritize concepts the least. Specifically if the arg is not a catch all as per above
    result = true
  else:
    result = processConcept(c, concpt, invocation, bindings, m)

  

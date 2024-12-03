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
    concpt: PType

proc existingBinding(m: MatchCon; key: PType): PType =
  ## checks if we bound the type variable 'key' already to some
  ## concrete type.
  for i in 0..<m.inferred.len:
    if m.inferred[i][0] == key: return m.inferred[i][1]
  return nil

proc conceptMatchNode(c: PContext; n: PNode; m: var MatchCon): bool

proc matchType(c: PContext; f, a: PType; m: var MatchCon): bool

proc matchKids(c: PContext; f, a: PType; m: var MatchCon, start=0): bool=
  result = true
  for i in start..<f.kidsLen - ord(f.kind == tyGenericInst):
    if not matchType(c, f[i], a[i], m): return false

proc matchType(c: PContext; f, a: PType; m: var MatchCon): bool =
  ## The heart of the concept matching process. 'f' is the formal parameter of some
  ## routine inside the concept that we're looking for. 'a' is the formal parameter
  ## of a routine that might match.
  const
    ignorableForArgType = {tyVar, tySink, tyLent, tyOwned, tyGenericInst, tyAlias, tyInferred}
  case f.kind
  of tyAlias:
    result = matchType(c, f.skipModifier, a, m)
  of tyTypeDesc:
    if isSelf(f):
      #let oldLen = m.inferred.len
      result = matchType(c, a, m.potentialImplementation, m)
      #echo "self is? ", result, " ", a.kind, " ", a, " ", m.potentialImplementation, " ", m.potentialImplementation.kind
      #m.inferred.setLen oldLen
      #echo "A for ", result, " to ", typeToString(a), " to ", typeToString(m.potentialImplementation)
    else:
      if a.kind == tyTypeDesc and f.hasElementType == a.hasElementType:
        if f.hasElementType:
          result = matchType(c, f.elementType, a.elementType, m)
        else:
          result = true # both lack it
      else:
        result = false

  of tyGenericInvocation:
    result = false
    if a.kind == tyGenericInst and a.genericHead.kind == tyGenericBody:
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
          result = matchType(c, f.elementType, a, m)
          m.inferred.setLen oldLen
          if result:
            when logBindings: echo "A adding ", f, " ", ak
            m.inferred.add((f, ak))
        elif m.magic == mArrGet and ak.kind in {tyArray, tyOpenArray, tySequence, tyVarargs, tyCstring, tyString}:
          when logBindings: echo "B adding ", f, " ", lastSon ak
          m.inferred.add((f, last ak))
          result = true
        else:
          when logBindings: echo "C adding ", f, " ", ak
          m.inferred.add((f, ak))
          #echo "binding ", typeToString(ak), " to ", typeToString(f)
          result = true
      elif not m.marker.containsOrIncl(old.id):
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
  of tyConcept:
    if a.kind == tyConcept and f.n == a.n:
      result = true
    elif m.concpt.size == szIllegalRecursion:
      result = false
    else:
      let oldLen = m.inferred.len
      let oldPotentialImplementation = m.potentialImplementation
      m.potentialImplementation = a
      m.concpt.size = szIllegalRecursion
      let oldConcept = m.concpt
      m.concpt = f
      result = conceptMatchNode(c, f.n.lastSon, m)
      m.potentialImplementation = oldPotentialImplementation
      m.concpt = oldConcept
      m.concpt.size = szUnknownSize
      if not result:
        m.inferred.setLen oldLen
  of tyGenericBody:
    var ak = a
    if a.kind == tyGenericBody:
      ak = last(a)
    result = matchType(c, last(f), ak, m)
  of tyCompositeTypeClass:
    var ak = if a.kind == tyCompositeTypeClass: a.last else: a
    result = matchType(c, last(f), ak, m)
  of tyArray, tyTuple, tyVarargs, tyOpenArray, tyRange, tySequence, tyRef, tyPtr,
     tyGenericInst:
    # ^ XXX Rewrite this logic, it's more complex than it needs to be.
    if f.kind == tyArray and f.kidsLen == 3:
      # XXX: this is a work-around!
      # system.nim creates these for the magic array typeclass
      result = true
    else:
      result = false
      let ak = a.skipTypes(ignorableForArgType - {f.kind})
      if ak.kind == f.kind and f.kidsLen == ak.kidsLen:
        result = matchKids(c, f, ak, m)
  of tyOr:
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
    if a.kind == tyNot:
      result = matchType(c, f.elementType, a.elementType, m)
    else:
      let oldLen = m.inferred.len
      result = not matchType(c, f.elementType, a, m)
      m.inferred.setLen oldLen
  of tyAnything:
    result = true
  of tyOrdinal:
    result = isOrdinalType(a, allowEnumWithHoles = false) or a.kind == tyGenericParam
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
  let con = n[0].sym.typ.n

  if can.len < con.len:
    # too few arguments, cannot be a match:
    return false

  let common = min(can.len, con.len)
  for i in 1 ..< common:
    if not matchType(c, con[i].typ, can[i].typ, m):
      m.inferred.setLen oldLen
      return false

  if not matchReturnType(c, n[0].sym.typ.returnType, candidate.typ.returnType, m):
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
  var candidates = searchScopes(c, n[namePos].sym.name, kinds)
  searchImportsAll(c, n[namePos].sym.name, kinds, candidates)
  for candidate in candidates:
    #echo "considering ", typeToString(candidate.typ), " ", candidate.magic
    m.magic = candidate.magic
    if matchSym(c, candidate, n, m): return true
  result = false

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
  result = conceptMatchNode(c, concpt.n.lastSon, m)
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

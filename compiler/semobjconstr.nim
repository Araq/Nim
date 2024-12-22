#
#
#           The Nim Compiler
#        (c) Copyright 2015 Nim Contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements Nim's object construction rules.

# included from sem.nim

from std/sugar import dup

type
  ObjConstrContext = object
    typ: PType               # The constructed type
    initExpr: PNode          # The init expression (nkObjConstr)
    needsFullInit: bool      # A `requiresInit` derived type will
                             # set this to true while visiting
                             # parent types.
    missingFields: seq[PSym] # Fields that the user failed to specify
    checkDefault: bool       # Checking defaults

  InitStatus = enum # This indicates the result of object construction
    initUnknown
    initFull     # All  of the fields have been initialized
    initPartial  # Some of the fields have been initialized
    initNone     # None of the fields have been initialized
    initConflict # Fields from different branches have been initialized


proc semConstructFields(c: PContext, n: PNode, constrCtx: var ObjConstrContext,
                        flags: TExprFlags): tuple[status: InitStatus, defaults: seq[PNode]]

proc mergeInitStatus(existing: var InitStatus, newStatus: InitStatus) =
  case newStatus
  of initConflict:
    existing = newStatus
  of initPartial:
    if existing in {initUnknown, initFull, initNone}:
      existing = initPartial
  of initNone:
    if existing == initUnknown:
      existing = initNone
    elif existing == initFull:
      existing = initPartial
  of initFull:
    if existing == initUnknown:
      existing = initFull
    elif existing == initNone:
      existing = initPartial
  of initUnknown:
    discard

proc invalidObjConstr(c: PContext, n: PNode) =
  if n.kind == nkInfix and n[0].kind == nkIdent and n[0].ident.s[0] == ':':
    localError(c.config, n.info, "incorrect object construction syntax; use a space after the colon")
  else:
    localError(c.config, n.info, "incorrect object construction syntax")

proc locateFieldInInitExpr(c: PContext, field: PSym, initExpr: PNode): PNode =
  # Returns the assignment nkExprColonExpr node or nil
  result = nil
  let fieldId = field.name.id
  for i in 1..<initExpr.len:
    let assignment = initExpr[i]
    if assignment.kind != nkExprColonExpr:
      invalidObjConstr(c, assignment)
    elif fieldId == considerQuotedIdent(c, assignment[0]).id:
      return assignment

proc semConstrField(c: PContext, flags: TExprFlags,
                    field: PSym, initExpr: PNode): PNode =
  let assignment = locateFieldInInitExpr(c, field, initExpr)
  if assignment != nil:
    if nfSem in assignment.flags: return assignment[1]
    if nfSkipFieldChecking in assignment[1].flags:
      discard
    elif not fieldVisible(c, field):
      localError(c.config, assignment[0].info,
        "the field '$1' is not accessible." % [field.name.s])
      return

    var initValue = semExprFlagDispatched(c, assignment[1], flags, field.typ)
    if initValue != nil:
      initValue = fitNodeConsiderViewType(c, field.typ, initValue, assignment.info)
    initValue.flags.incl nfSkipFieldChecking
    assignment[0] = newSymNode(field)
    assignment[1] = initValue
    assignment.flags.incl nfSem
    result = initValue
  else:
    result = nil

proc branchVals(c: PContext, caseNode: PNode, caseIdx: int,
                isStmtBranch: bool): IntSet =
  if caseNode[caseIdx].kind == nkOfBranch:
    result = initIntSet()
    for val in processBranchVals(caseNode[caseIdx]):
      result.incl(val)
  else:
    result = c.getIntSetOfType(caseNode[0].typ)
    for i in 1..<caseNode.len-1:
      for val in processBranchVals(caseNode[i]):
        result.excl(val)

proc findUsefulCaseContext(c: PContext, discrimator: PNode): (PNode, int) =
  result = (nil, 0)
  for i in countdown(c.p.caseContext.high, 0):
    let
      (caseNode, index) = c.p.caseContext[i]
      skipped = caseNode[0].skipHidden
    if skipped.kind == nkSym and skipped.sym == discrimator.sym:
      return (caseNode, index)

proc pickCaseBranch(caseExpr, matched: PNode): PNode =
  # XXX: Perhaps this proc already exists somewhere
  let endsWithElse = caseExpr[^1].kind == nkElse
  for i in 1..<caseExpr.len - int(endsWithElse):
    if caseExpr[i].caseBranchMatchesExpr(matched):
      return caseExpr[i]

  if endsWithElse:
    result = caseExpr[^1]
  else:
    result = nil

iterator directFieldsInRecList(recList: PNode): PNode =
  # XXX: We can remove this case by making all nkOfBranch nodes
  # regular. Currently, they try to avoid using nkRecList if they
  # include only a single field
  if recList.kind == nkSym:
    yield recList
  else:
    doAssert recList.kind == nkRecList
    for field in recList:
      if field.kind == nkSym:
        yield field

template quoteStr(s: string): string = "'" & s & "'"

proc fieldsPresentInInitExpr(c: PContext, fieldsRecList, initExpr: PNode): string =
  result = ""
  for field in directFieldsInRecList(fieldsRecList):
    if locateFieldInInitExpr(c, field.sym, initExpr) != nil:
      if result.len != 0: result.add ", "
      result.add field.sym.name.s.quoteStr

proc locateFieldInDefaults(sym: PSym, defaults: seq[PNode]): bool =
  result = false
  for d in defaults:
    if sym.id == d[0].sym.id:
      return true

proc collectMissingFields(c: PContext, fieldsRecList: PNode,
                          constrCtx: var ObjConstrContext, defaults: seq[PNode]
                          ): seq[PSym] =
  result = @[]
  for r in directFieldsInRecList(fieldsRecList):
    let assignment = locateFieldInInitExpr(c, r.sym, constrCtx.initExpr)
    if assignment == nil and not locateFieldInDefaults(r.sym, defaults):
      if constrCtx.needsFullInit or
        sfRequiresInit in r.sym.flags or
          r.sym.typ.requiresInit:
        constrCtx.missingFields.add r.sym
      else:
        result.add r.sym

proc collectMissingCaseFields(c: PContext, branchNode: PNode,
                          constrCtx: var ObjConstrContext, defaults: seq[PNode]): seq[PSym] =
  if branchNode != nil:
    let fieldsRecList = branchNode[^1]
    result = collectMissingFields(c, fieldsRecList, constrCtx, defaults)
  else:
    result = @[]

proc collectOrAddMissingCaseFields(c: PContext, branchNode: PNode,
                          constrCtx: var ObjConstrContext, defaults: var seq[PNode]) =
  let res = collectMissingCaseFields(c, branchNode, constrCtx, defaults)
  for sym in res:
    let asgnType = newType(tyTypeDesc, c.idgen, sym.typ.owner)
    let recTyp = sym.typ.skipTypes(defaultFieldsSkipTypes)
    rawAddSon(asgnType, recTyp)
    let asgnExpr = newTree(nkCall,
          newSymNode(getSysMagic(c.graph, constrCtx.initExpr.info, "zeroDefault", mZeroDefault)),
          newNodeIT(nkType, constrCtx.initExpr.info, asgnType)
        )
    asgnExpr.flags.incl nfSkipFieldChecking
    asgnExpr.typ() = recTyp
    defaults.add newTree(nkExprColonExpr, newSymNode(sym), asgnExpr)

proc collectBranchFields(c: PContext, n: PNode, discriminatorVal: PNode,
                          constrCtx: var ObjConstrContext, flags: TExprFlags) =
  # All bets are off. If any of the branches has a mandatory
  # fields we must produce an error:
  for i in 1..<n.len:
    let branchNode = n[i]
    if branchNode != nil:
      let oldCheckDefault = constrCtx.checkDefault
      constrCtx.checkDefault = true
      let (_, defaults) = semConstructFields(c, branchNode[^1], constrCtx, flags)
      constrCtx.checkDefault = oldCheckDefault
      if len(defaults) > 0:
        localError(c.config, discriminatorVal.info, "branch initialization " &
                    "with a runtime discriminator is not supported " &
                    "for a branch whose fields have default values.")
    discard collectMissingCaseFields(c, n[i], constrCtx, @[])

proc semConstructFields(c: PContext, n: PNode, constrCtx: var ObjConstrContext,
                        flags: TExprFlags): tuple[status: InitStatus, defaults: seq[PNode]] =
  result = (initUnknown, @[])
  case n.kind
  of nkRecList:
    for field in n:
      let (subSt, subDf) = semConstructFields(c, field, constrCtx, flags)
      result.status.mergeInitStatus subSt
      result.defaults.add subDf
  of nkRecCase:
    template fieldsPresentInBranch(branchIdx: int): string =
      let branch = n[branchIdx]
      let fields = branch[^1]
      fieldsPresentInInitExpr(c, fields, constrCtx.initExpr)

    let discriminator = n[0]
    internalAssert c.config, discriminator.kind == nkSym
    var selectedBranch = -1

    for i in 1..<n.len:
      let innerRecords = n[i][^1]
      let (status, _) = semConstructFields(c, innerRecords, constrCtx, flags) # todo
      if status notin {initNone, initUnknown}:
        result.status.mergeInitStatus status
        if selectedBranch != -1:
          let prevFields = fieldsPresentInBranch(selectedBranch)
          let currentFields = fieldsPresentInBranch(i)
          localError(c.config, constrCtx.initExpr.info,
            ("The fields '$1' and '$2' cannot be initialized together, " &
            "because they are from conflicting branches in the case object.") %
            [prevFields, currentFields])
          result.status = initConflict
        else:
          selectedBranch = i

    if selectedBranch != -1:
      template badDiscriminatorError =
        if c.inUncheckedAssignSection == 0:
          let fields = fieldsPresentInBranch(selectedBranch)
          localError(c.config, constrCtx.initExpr.info,
            ("cannot prove that it's safe to initialize $1 with " &
            "the runtime value for the discriminator '$2' ") %
            [fields, discriminator.sym.name.s])
        mergeInitStatus(result.status, initNone)

      template wrongBranchError(i) =
        if c.inUncheckedAssignSection == 0:
          let fields = fieldsPresentInBranch(i)
          localError(c.config, constrCtx.initExpr.info,
            ("a case selecting discriminator '$1' with value '$2' " &
            "appears in the object construction, but the field(s) $3 " &
            "are in conflict with this value.") %
            [discriminator.sym.name.s, discriminatorVal.renderTree, fields])

      template valuesInConflictError(valsDiff) =
        localError(c.config, discriminatorVal.info, ("possible values " &
          "$2 are in conflict with discriminator values for " &
          "selected object branch $1.") % [$selectedBranch,
          valsDiff.renderAsType(n[0].typ)])

      let branchNode = n[selectedBranch]
      let flags = {efPreferStatic, efPreferNilResult}
      var discriminatorVal = semConstrField(c, flags,
                                            discriminator.sym,
                                            constrCtx.initExpr)
      if discriminatorVal != nil:
        discriminatorVal = discriminatorVal.skipHidden
        if discriminatorVal.kind notin nkLiterals and (
            not isOrdinalType(discriminatorVal.typ, true) or
            lengthOrd(c.config, discriminatorVal.typ) > MaxSetElements or
            lengthOrd(c.config, n[0].typ) > MaxSetElements):
          localError(c.config, discriminatorVal.info,
            "branch initialization with a runtime discriminator only " &
            "supports ordinal types with 2^16 elements or less.")

      if discriminatorVal == nil:
        badDiscriminatorError()
      elif discriminatorVal.kind == nkSym:
        let (ctorCase, ctorIdx) = findUsefulCaseContext(c, discriminatorVal)
        if ctorCase == nil:
          if discriminatorVal.typ.kind == tyRange:
            let rangeVals = c.getIntSetOfType(discriminatorVal.typ)
            let recBranchVals = branchVals(c, n, selectedBranch, false)
            let diff = rangeVals - recBranchVals
            if diff.len != 0:
              valuesInConflictError(diff)
          else:
            badDiscriminatorError()
        elif discriminatorVal.sym.kind notin {skLet, skParam} or
            discriminatorVal.sym.typ.kind in {tyVar}:
          if c.inUncheckedAssignSection == 0:
            localError(c.config, discriminatorVal.info,
              "runtime discriminator must be immutable if branch fields are " &
              "initialized, a 'let' binding is required.")
        elif ctorCase[ctorIdx].kind == nkElifBranch:
          localError(c.config, discriminatorVal.info, "branch initialization " &
            "with a runtime discriminator is not supported inside of an " &
            "`elif` branch.")
        else:
          var
            ctorBranchVals = branchVals(c, ctorCase, ctorIdx, true)
            recBranchVals = branchVals(c, n, selectedBranch, false)
            branchValsDiff = ctorBranchVals - recBranchVals
          if branchValsDiff.len != 0:
            valuesInConflictError(branchValsDiff)
      else:
        var failedBranch = -1
        if branchNode.kind != nkElse:
          if not branchNode.caseBranchMatchesExpr(discriminatorVal):
            failedBranch = selectedBranch
        else:
          # With an else clause, check that all other branches don't match:
          for i in 1..<n.len - 1:
            if n[i].caseBranchMatchesExpr(discriminatorVal):
              failedBranch = i
              break
        if failedBranch != -1:
          if discriminatorVal.typ.kind == tyRange:
            let rangeVals = c.getIntSetOfType(discriminatorVal.typ)
            let recBranchVals = branchVals(c, n, selectedBranch, false)
            let diff = rangeVals - recBranchVals
            if diff.len != 0:
              valuesInConflictError(diff)
          else:
            wrongBranchError(failedBranch)

      let (_, defaults) = semConstructFields(c, branchNode[^1], constrCtx, flags)
      result.defaults.add defaults

      # When a branch is selected with a partial match, some of the fields
      # that were not initialized may be mandatory. We must check for this:
      if result.status == initPartial:
        collectOrAddMissingCaseFields(c, branchNode, constrCtx, result.defaults)
    else:
      result.status = initNone
      let discriminatorVal = semConstrField(c, flags + {efPreferStatic},
                                            discriminator.sym,
                                            constrCtx.initExpr)
      if discriminatorVal == nil:
        if discriminator.sym.ast != nil:
          # branch is selected by the default field value of discriminator
          let discriminatorDefaultVal = discriminator.sym.ast
          result.status = initUnknown
          result.defaults.add newTree(nkExprColonExpr, n[0], discriminatorDefaultVal)
          if discriminatorDefaultVal.kind == nkIntLit:
            let matchedBranch = n.pickCaseBranch discriminatorDefaultVal
            if matchedBranch != nil:
              let (_, defaults) = semConstructFields(c, matchedBranch[^1], constrCtx, flags)
              result.defaults.add defaults
              collectOrAddMissingCaseFields(c, matchedBranch, constrCtx, result.defaults)
          else:
            collectBranchFields(c, n, discriminatorDefaultVal, constrCtx, flags)
        else:
          # None of the branches were explicitly selected by the user and no
          # value was given to the discrimator. We can assume that it will be
          # initialized to zero and this will select a particular branch as
          # a result:
          let defaultValue = newIntLit(c.graph, constrCtx.initExpr.info, 0)
          let matchedBranch = n.pickCaseBranch defaultValue
          discard collectMissingCaseFields(c, matchedBranch, constrCtx, @[])
      else:
        result.status = initPartial
        if discriminatorVal.kind == nkIntLit:
          # When the discriminator is a compile-time value, we also know
          # which branch will be selected:
          let matchedBranch = n.pickCaseBranch discriminatorVal
          if matchedBranch != nil:
            let (_, defaults) = semConstructFields(c, matchedBranch[^1], constrCtx, flags)
            result.defaults.add defaults
            collectOrAddMissingCaseFields(c, matchedBranch, constrCtx, result.defaults)
        else:
          collectBranchFields(c, n, discriminatorVal, constrCtx, flags)

  of nkSym:
    let field = n.sym
    let e = semConstrField(c, flags, field, constrCtx.initExpr)
    if e != nil:
      result.status = initFull
    elif field.ast != nil:
      if efIgnoreDefaults notin flags:
        result.status = initUnknown
        result.defaults.add newTree(nkExprColonExpr, n, field.ast)
      else:
        result.status = initNone
    else:
      if {efWantNoDefaults, efIgnoreDefaults} * flags == {}: # cannot compute defaults at the typeRightPass
        let defaultExpr = defaultNodeField(c, n, constrCtx.checkDefault)
        if defaultExpr != nil:
          result.status = initUnknown
          result.defaults.add newTree(nkExprColonExpr, n, defaultExpr)
        else:
          result.status = initNone
      else:
        result.status = initNone
  else:
    internalAssert c.config, false

proc semConstructTypeAux(c: PContext,
                         constrCtx: var ObjConstrContext,
                         flags: TExprFlags): tuple[status: InitStatus, defaults: seq[PNode]] =
  result = (initUnknown, @[])
  var t = constrCtx.typ
  while true:
    let (status, defaults) = semConstructFields(c, t.n, constrCtx, flags)
    result.status.mergeInitStatus status
    result.defaults.add defaults
    if status in {initPartial, initNone, initUnknown}:
      discard collectMissingFields(c, t.n, constrCtx, result.defaults)
    let base = t.baseClass
    if base == nil or base.id == t.id or
        base.kind in {tyRef, tyPtr} and base.elementType.id == t.id:
      break
    t = skipTypes(base, skipPtrs)
    if t.kind != tyObject:
      # XXX: This is not supposed to happen, but apparently
      # there are some issues in semtypinst. Luckily, it
      # seems to affect only `computeRequiresInit`.
      return
    constrCtx.needsFullInit = constrCtx.needsFullInit or
                              tfNeedsFullInit in t.flags

proc initConstrContext(t: PType, initExpr: PNode): ObjConstrContext =
  ObjConstrContext(typ: t, initExpr: initExpr,
                   needsFullInit: tfNeedsFullInit in t.flags)

proc computeRequiresInit(c: PContext, t: PType): bool =
  assert t.kind == tyObject
  var constrCtx = initConstrContext(t, newNode(nkObjConstr))
  let initResult = semConstructTypeAux(c, constrCtx, {efWantNoDefaults})
  constrCtx.missingFields.len > 0

proc defaultConstructionError(c: PContext, t: PType, info: TLineInfo) =
  var objType = t
  while objType.kind notin {tyObject, tyDistinct}:
    objType = objType.last
    assert objType != nil
  if objType.kind == tyObject:
    var constrCtx = initConstrContext(objType, newNodeI(nkObjConstr, info))
    let initResult = semConstructTypeAux(c, constrCtx, {efIgnoreDefaults})
    if constrCtx.missingFields.len > 0:
      localError(c.config, info,
        "The $1 type doesn't have a default value. The following fields must be initialized: $2." % [typeToString(t), listSymbolNames(constrCtx.missingFields)])
  elif objType.kind == tyDistinct:
    localError(c.config, info,
      "The $1 distinct type doesn't have a default value." % typeToString(t))
  else:
    assert false, "Must not enter here."

proc semObjConstr(c: PContext, n: PNode, flags: TExprFlags; expectedType: PType = nil): PNode =
  var t = semTypeNode(c, n[0], nil)
  result = newNodeIT(nkObjConstr, n.info, t)
  for i in 0..<n.len:
    result.add n[i]

  if t == nil:
    return localErrorNode(c, result, "object constructor needs an object type")

  when false:
    # attempted type inference for generic object types,
    # doesn't work since n[0] isn't set and seems underspecified
    if t.skipTypes({tyGenericInst,
        tyAlias, tySink, tyOwned, tyRef}).kind != tyObject and
        expectedType != nil and expectedType.skipTypes({tyGenericInst,
        tyAlias, tySink, tyOwned, tyRef}).kind == tyObject:
      t = expectedType

  t = skipTypes(t, {tyGenericInst, tyAlias, tySink, tyOwned})
  if t.kind == tyRef:
    t = skipTypes(t.elementType, {tyGenericInst, tyAlias, tySink, tyOwned})
    if optOwnedRefs in c.config.globalOptions:
      result.typ() = makeVarType(c, result.typ, tyOwned)
      # we have to watch out, there are also 'owned proc' types that can be used
      # multiple times as long as they don't have closures.
      result.typ.flags.incl tfHasOwned
  if t.kind != tyObject:
    return localErrorNode(c, result, if t.kind != tyGenericBody:
      "object constructor needs an object type".dup(addTypeNodeDeclaredLoc(c.config, t))
      else: "cannot instantiate: '" &
        typeToString(t, preferDesc) &
        "'; the object's generic parameters cannot be inferred and must be explicitly given"
      )

  # Check if the object is fully initialized by recursively testing each
  # field (if this is a case object, initialized fields in two different
  # branches will be reported as an error):
  var constrCtx = initConstrContext(t, result)
  let (initResult, defaults) = semConstructTypeAux(c, constrCtx, flags)
  var hasError = false # needed to split error detect/report for better msgs

  # It's possible that the object was not fully initialized while
  # specifying a .requiresInit. pragma:
  if constrCtx.missingFields.len > 0:
    hasError = true
    localError(c.config, result.info,
      "The $1 type requires the following fields to be initialized: $2." %
      [t.sym.name.s, listSymbolNames(constrCtx.missingFields)])

  # Since we were traversing the object fields, it's possible that
  # not all of the fields specified in the constructor was visited.
  # We'll check for such fields here:
  for i in 1..<result.len:
    let field = result[i]
    if nfSem notin field.flags:
      if field.kind != nkExprColonExpr:
        invalidObjConstr(c, field)
        hasError = true
        continue
      let id = considerQuotedIdent(c, field[0])
      # This node was not processed. There are two possible reasons:
      # 1) It was shadowed by a field with the same name on the left
      for j in 1..<i:
        let prevId = considerQuotedIdent(c, result[j][0])
        if prevId.id == id.id:
          localError(c.config, field[0].info, errFieldInitTwice % id.s)
          hasError = true
          break
      # 2) No such field exists in the constructed type
      let msg = errUndeclaredField % id.s & " for type " & getProcHeader(c.config, t.sym)
      localError(c.config, field.info, msg)
      hasError = true
      break

  result.sons.add defaults

  if initResult == initFull:
    incl result.flags, nfAllFieldsSet

  # wrap in an error see #17437
  if hasError: result = errorNode(c, result)

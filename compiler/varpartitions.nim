#
#
#           The Nim Compiler
#        (c) Copyright 2020 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Partition variables into different graphs. Used for
## Nim's write tracking, borrow checking and also for the
## cursor inference.
## The algorithm is a reinvention / variation of Steensgaard's
## algorithm.
## The used data structure is "union find" with path compression.

## We perform two passes over the AST:
## - Pass one (``computeLiveRanges``): collect livetimes of local
##   variables and whether they are potentially re-assigned.
## - Pass two (``traverse``): combine local variables to abstract "graphs".
##   Strict func checking: Ensure that graphs that are connected to
##   const parameters are not mutated.
##   Cursor inference: Ensure that potential cursors are not
##     borrowed from locations that are connected to a graph
##     that is mutated during the liveness of the cursor.
##     (We track all possible mutations of a graph.)
##
## See https://nim-lang.github.io/Nim/manual_experimental.html#view-types-algorithm
## for a high-level description of how borrow checking works.

import ast, types, lineinfos, options, msgs, renderer, typeallowed, modulegraphs
from trees import getMagic, isNoSideEffectPragma, stupidStmtListExpr
from isolation_check import canAlias

when defined(nimPreviewSlimSystem):
  import std/assertions

type
  AbstractTime = distinct int

const
  MaxTime = AbstractTime high(int)
  MinTime = AbstractTime(-1)

proc `<=`(a, b: AbstractTime): bool {.borrow.}
proc `<`(a, b: AbstractTime): bool {.borrow.}

proc inc(x: var AbstractTime; diff = 1) {.borrow.}
proc dec(x: var AbstractTime; diff = 1) {.borrow.}

proc `$`(x: AbstractTime): string {.borrow.}

type
  SubgraphFlag = enum
    isMutated, # graph might be mutated
    isMutatedDirectly, # graph is mutated directly by a non-var parameter.
    isMutatedByVarParam, # graph is mutated by a var parameter.
    connectsConstParam # graph is connected to a non-var parameter.

  VarFlag = enum
    ownsData,
    preventCursor,
    isReassigned,
    isConditionallyReassigned,
    viewDoesMutate,
    viewBorrowsFromConst

  VarIndexKind = enum
    isEmptyRoot,
    dependsOn,
    isRootOf

  Connection = object
    case kind: VarIndexKind
    of isEmptyRoot: discard
    of dependsOn: parent: int
    of isRootOf: graphIndex: int

  VarIndex = object
    con: Connection
    flags: set[VarFlag]
    sym: PSym
    reassignedTo: int
    aliveStart, aliveEnd: AbstractTime # the range for which the variable is alive.
    borrowsFrom: seq[int] # indexes into Partitions.s

  MutationInfo* = object
    param: PSym
    mutatedHere, connectedVia: TLineInfo
    flags: set[SubgraphFlag]
    maxMutation, minConnection: AbstractTime
    mutations: seq[AbstractTime]

  Goal* = enum
    constParameters,
    borrowChecking,
    cursorInference

  Partitions* = object
    abstractTime: AbstractTime
    defers: seq[PNode]
    processDefer: bool
    s: seq[VarIndex]
    graphs: seq[MutationInfo]
    goals: set[Goal]
    unanalysableMutation: bool
    inAsgnSource, inConstructor, inNoSideEffectSection: int
    inConditional, inLoop: int
    inConvHasDestructor: int
    owner: PSym
    g: ModuleGraph

proc mutationAfterConnection(g: MutationInfo): bool {.inline.} =
  #echo g.maxMutation.int, " ", g.minConnection.int, " ", g.param
  g.maxMutation > g.minConnection

proc `$`*(config: ConfigRef; g: MutationInfo): string =
  result = ""
  if g.flags * {isMutated, connectsConstParam} == {isMutated, connectsConstParam}:
    result.add "\nan object reachable from '"
    result.add g.param.name.s
    result.add "' is potentially mutated"
    if g.mutatedHere != unknownLineInfo:
      result.add "\n"
      result.add config $ g.mutatedHere
      result.add " the mutation is here"
    if g.connectedVia != unknownLineInfo:
      result.add "\n"
      result.add config $ g.connectedVia
      result.add " is the statement that connected the mutation to the parameter"

proc hasSideEffect*(c: var Partitions; info: var MutationInfo): bool =
  for g in mitems c.graphs:
    if g.flags * {isMutated, connectsConstParam} == {isMutated, connectsConstParam} and
        (mutationAfterConnection(g) or isMutatedDirectly in g.flags):
      info = g
      return true
  return false

template isConstParam(a): bool = a.kind == skParam and a.typ.kind notin {tyVar, tySink}

proc variableId(c: Partitions; x: PSym): int =
  for i in 0 ..< c.s.len:
    if c.s[i].sym == x: return i
  return -1

proc registerResult(c: var Partitions; n: PNode) =
  if n.kind == nkSym:
    c.s.add VarIndex(con: Connection(kind: isEmptyRoot), sym: n.sym, reassignedTo: 0,
                      aliveStart: MaxTime, aliveEnd: c.abstractTime)

proc registerParam(c: var Partitions; n: PNode) =
  assert n.kind == nkSym
  if isConstParam(n.sym):
    c.s.add VarIndex(con: Connection(kind: isRootOf, graphIndex: c.graphs.len),
                      sym: n.sym, reassignedTo: 0,
                      aliveStart: c.abstractTime, aliveEnd: c.abstractTime)
    c.graphs.add MutationInfo(param: n.sym, mutatedHere: unknownLineInfo,
                          connectedVia: unknownLineInfo, flags: {connectsConstParam},
                          maxMutation: MinTime, minConnection: MaxTime,
                          mutations: @[])
  else:
    c.s.add VarIndex(con: Connection(kind: isEmptyRoot), sym: n.sym, reassignedTo: 0,
                     aliveStart: c.abstractTime, aliveEnd: c.abstractTime)

proc registerVariable(c: var Partitions; n: PNode) =
  if n.kind == nkSym and variableId(c, n.sym) < 0:
    c.s.add VarIndex(con: Connection(kind: isEmptyRoot), sym: n.sym, reassignedTo: 0,
                     aliveStart: c.abstractTime, aliveEnd: c.abstractTime)

proc root(v: var Partitions; start: int): int =
  result = start
  var depth = 0
  while v.s[result].con.kind == dependsOn:
    result = v.s[result].con.parent
    inc depth
  if depth > 0:
    # path compression:
    var it = start
    while v.s[it].con.kind == dependsOn:
      let next = v.s[it].con.parent
      v.s[it].con = Connection(kind: dependsOn, parent: result)
      it = next

proc potentialMutation(v: var Partitions; s: PSym; level: int; info: TLineInfo) =
  let id = variableId(v, s)
  if id >= 0:
    let r = root(v, id)
    let flags = if s.kind == skParam:
                  if isConstParam(s):
                    {isMutated, isMutatedDirectly}
                  elif s.typ.kind == tyVar and level <= 1:
                    # varParam[i] = v is different from varParam[i][] = v
                    {isMutatedByVarParam}
                  else:
                    {isMutated}
                else:
                  {isMutated}

    case v.s[r].con.kind
    of isEmptyRoot:
      v.s[r].con = Connection(kind: isRootOf, graphIndex: v.graphs.len)
      v.graphs.add MutationInfo(param: if isConstParam(s): s else: nil, mutatedHere: info,
                            connectedVia: unknownLineInfo, flags: flags,
                            maxMutation: v.abstractTime, minConnection: MaxTime,
                            mutations: @[v.abstractTime])
    of isRootOf:
      let g = addr v.graphs[v.s[r].con.graphIndex]
      if g.param == nil and isConstParam(s):
        g.param = s
      if v.abstractTime > g.maxMutation:
        g.mutatedHere = info
        g.maxMutation = v.abstractTime
      g.flags.incl flags
      g.mutations.add v.abstractTime
    else:
      assert false, "cannot happen"
  else:
    v.unanalysableMutation = true

proc connect(v: var Partitions; a, b: PSym; info: TLineInfo) =
  let aid = variableId(v, a)
  if aid < 0:
    return
  let bid = variableId(v, b)
  if bid < 0:
    return

  let ra = root(v, aid)
  let rb = root(v, bid)
  if ra != rb:
    var param = PSym(nil)
    if isConstParam(a): param = a
    elif isConstParam(b): param = b

    let paramFlags =
      if param != nil:
        {connectsConstParam}
      else:
        {}

    # for now we always make 'rb' the slave and 'ra' the master:
    var rbFlags: set[SubgraphFlag] = {}
    var mutatedHere = unknownLineInfo
    var mut = AbstractTime 0
    var con = v.abstractTime
    var gb: ptr MutationInfo = nil
    if v.s[rb].con.kind == isRootOf:
      gb = addr v.graphs[v.s[rb].con.graphIndex]
      if param == nil: param = gb.param
      mutatedHere = gb.mutatedHere
      rbFlags = gb.flags
      mut = gb.maxMutation
      con = min(con, gb.minConnection)

    v.s[rb].con = Connection(kind: dependsOn, parent: ra)
    case v.s[ra].con.kind
    of isEmptyRoot:
      v.s[ra].con = Connection(kind: isRootOf, graphIndex: v.graphs.len)
      v.graphs.add MutationInfo(param: param, mutatedHere: mutatedHere,
                            connectedVia: info, flags: paramFlags + rbFlags,
                            maxMutation: mut, minConnection: con,
                            mutations: if gb != nil: gb.mutations else: @[])
    of isRootOf:
      var g = addr v.graphs[v.s[ra].con.graphIndex]
      if g.param == nil: g.param = param
      if g.mutatedHere == unknownLineInfo: g.mutatedHere = mutatedHere
      g.minConnection = min(g.minConnection, con)
      g.connectedVia = info
      g.flags.incl paramFlags + rbFlags
      if gb != nil:
        g.mutations.add gb.mutations
    else:
      assert false, "cannot happen"

proc borrowFromConstExpr(n: PNode): bool =
  case n.kind
  of nkCharLit..nkNilLit:
    result = true
  of nkExprEqExpr, nkExprColonExpr, nkHiddenStdConv, nkHiddenSubConv,
      nkCast, nkObjUpConv, nkObjDownConv:
    result = borrowFromConstExpr(n.lastSon)
  of nkCurly, nkBracket, nkPar, nkTupleConstr, nkObjConstr, nkClosure, nkRange:
    result = true
    for i in ord(n.kind == nkObjConstr)..<n.len:
      if not borrowFromConstExpr(n[i]): return false
  of nkCallKinds:
    if getMagic(n) == mArrToSeq:
      result = true
      for i in 1..<n.len:
        if not borrowFromConstExpr(n[i]): return false
    else:
      result = false
  else: result = false

proc pathExpr(node: PNode; owner: PSym): PNode =
  #[ From the spec:

  - ``source`` itself is a path expression.
  - Container access like ``e[i]`` is a path expression.
  - Tuple access ``e[0]`` is a path expression.
  - Object field access ``e.field`` is a path expression.
  - ``system.toOpenArray(e, ...)`` is a path expression.
  - Pointer dereference ``e[]`` is a path expression.
  - An address ``addr e``, ``unsafeAddr e`` is a path expression.
  - A type conversion ``T(e)`` is a path expression.
  - A cast expression ``cast[T](e)`` is a path expression.
  - ``f(e, ...)`` is a path expression if ``f``'s return type is a view type.
    Because the view can only have been borrowed from ``e``, we then know
    that owner of ``f(e, ...)`` is ``e``.

  Returns the owner of the path expression. Returns ``nil``
  if it is not a valid path expression.
  ]#
  var n = node
  result = nil
  while true:
    case n.kind
    of nkSym:
      case n.sym.kind
      of skParam, skTemp, skResult, skForVar:
        if n.sym.owner == owner: result = n
      of skVar:
        if n.sym.owner == owner or sfThread in n.sym.flags: result = n
      of skLet, skConst:
        if n.sym.owner == owner or {sfThread, sfGlobal} * n.sym.flags != {}:
          result = n
      else:
        discard
      break
    of nkDotExpr, nkDerefExpr, nkBracketExpr, nkHiddenDeref,
        nkCheckedFieldExpr, nkAddr, nkHiddenAddr:
      n = n[0]
    of nkHiddenStdConv, nkHiddenSubConv, nkConv,  nkCast,
        nkObjUpConv, nkObjDownConv:
      n = n.lastSon
    of nkStmtList, nkStmtListExpr:
      if n.len > 0 and stupidStmtListExpr(n):
        n = n.lastSon
      else:
        break
    of nkCallKinds:
      if n.len > 1:
        if (n.typ != nil and classifyViewType(n.typ) != noView) or getMagic(n) == mSlice:
          n = n[1]
        else:
          break
      else:
        break
    else:
      break
  # borrowFromConstExpr(n) is correct here because we need 'node'
  # stripped off the path suffixes:
  if result == nil and borrowFromConstExpr(n):
    result = n

const
  RootEscapes = 1000 # in 'p(r)' we don't know what p does to our poor root.
                     # so we assume a high level of indirections

proc allRoots(n: PNode; result: var seq[(PSym, int)]; level: int) =
  case n.kind
  of nkSym:
    if n.sym.kind in {skParam, skVar, skTemp, skLet, skResult, skForVar}:
      result.add((n.sym, level))

  of nkDerefExpr, nkHiddenDeref:
    allRoots(n[0], result, level+1)
  of nkBracketExpr, nkDotExpr, nkCheckedFieldExpr, nkAddr, nkHiddenAddr:
    allRoots(n[0], result, level)

  of nkExprEqExpr, nkExprColonExpr, nkHiddenStdConv, nkHiddenSubConv, nkConv,
      nkStmtList, nkStmtListExpr, nkBlockStmt, nkBlockExpr, nkCast,
      nkObjUpConv, nkObjDownConv:
    if n.len > 0:
      allRoots(n.lastSon, result, level)
  of nkCaseStmt, nkObjConstr:
    for i in 1..<n.len:
      allRoots(n[i].lastSon, result, level)
  of nkIfStmt, nkIfExpr:
    for i in 0..<n.len:
      allRoots(n[i].lastSon, result, level)
  of nkBracket, nkTupleConstr, nkPar:
    for i in 0..<n.len:
      allRoots(n[i], result, level-1)

  of nkCallKinds:
    if n.typ != nil and n.typ.kind in {tyVar, tyLent}:
      if n.len > 1:
        # XXX We really need the unwritten RFC here and distinguish between
        #   proc `[]`(x: var Container): var T # resizes the container
        # and
        #   proc `[]`(x: Container): var T # only allows for slot mutation
        allRoots(n[1], result, RootEscapes)
    else:
      let m = getMagic(n)
      case m
      of mNone:
        if n[0].typ.isNil: return
        var typ = n[0].typ
        if typ != nil:
          typ = skipTypes(typ, abstractInst)
          if typ.kind != tyProc: typ = nil

        for i in 1 ..< n.len:
          let it = n[i]
          if typ != nil and i < typ.n.len:
            assert(typ.n[i].kind == nkSym)
            let paramType = typ.n[i].typ
            if not paramType.isCompileTimeOnly and not typ.returnType.isEmptyType and
                canAlias(paramType, typ.returnType):
              allRoots(it, result, RootEscapes)
          else:
            allRoots(it, result, RootEscapes)

      of mSlice:
        allRoots(n[1], result, level+1)
      else:
        discard "harmless operation"
  else:
    discard "nothing to do"

proc destMightOwn(c: var Partitions; dest: var VarIndex; n: PNode) =
  ## Analyse if 'n' is an expression that owns the data, if so mark 'dest'
  ## with 'ownsData'.
  case n.kind
  of nkEmpty, nkCharLit..nkNilLit:
    # primitive literals including the empty are harmless:
    discard

  of nkExprEqExpr, nkExprColonExpr, nkHiddenStdConv, nkHiddenSubConv, nkCast:
    destMightOwn(c, dest, n[1])

  of nkConv:
    if hasDestructor(n.typ):
      inc c.inConvHasDestructor
      destMightOwn(c, dest, n[1])
      dec c.inConvHasDestructor
    else:
      destMightOwn(c, dest, n[1])

  of nkIfStmt, nkIfExpr:
    for i in 0..<n.len:
      inc c.inConditional
      destMightOwn(c, dest, n[i].lastSon)
      dec c.inConditional

  of nkCaseStmt:
    for i in 1..<n.len:
      inc c.inConditional
      destMightOwn(c, dest, n[i].lastSon)
      dec c.inConditional

  of nkStmtList, nkStmtListExpr:
    if n.len > 0:
      destMightOwn(c, dest, n[^1])

  of nkClosure:
    for i in 1..<n.len:
      destMightOwn(c, dest, n[i])
    # you must destroy a closure:
    dest.flags.incl ownsData

  of nkObjConstr:
    for i in 1..<n.len:
      destMightOwn(c, dest, n[i])
    if hasDestructor(n.typ):
      # you must destroy a ref object:
      dest.flags.incl ownsData

  of nkCurly, nkBracket, nkPar, nkTupleConstr:
    inc c.inConstructor
    for son in n:
      destMightOwn(c, dest, son)
    dec c.inConstructor
    if n.typ.skipTypes(abstractInst).kind == tySequence:
      # you must destroy a sequence:
      dest.flags.incl ownsData

  of nkSym:
    if n.sym.kind in {skVar, skResult, skTemp, skLet, skForVar, skParam}:
      if n.sym.flags * {sfThread, sfGlobal} != {}:
        # aliasing a global is inherently dangerous:
        dest.flags.incl ownsData
      else:
        # otherwise it's just a dependency, nothing to worry about:
        connect(c, dest.sym, n.sym, n.info)
        # but a construct like ``[symbol]`` is dangerous:
        if c.inConstructor > 0: dest.flags.incl ownsData

  of nkDotExpr, nkBracketExpr, nkHiddenDeref, nkDerefExpr,
      nkObjUpConv, nkObjDownConv, nkCheckedFieldExpr, nkAddr, nkHiddenAddr:
    destMightOwn(c, dest, n[0])

  of nkCallKinds:
    if n.typ != nil:
      if hasDestructor(n.typ) or c.inConvHasDestructor > 0:
        # calls do construct, what we construct must be destroyed,
        # so dest cannot be a cursor:
        dest.flags.incl ownsData
      elif n.typ.kind in {tyLent, tyVar} and n.len > 1:
        # we know the result is derived from the first argument:
        var roots: seq[(PSym, int)] = @[]
        allRoots(n[1], roots, RootEscapes)
        if roots.len == 0 and c.inConditional > 0:
          # when in a conditional expression,
          # to ensure that the first argument isn't outlived
          # by the lvalue, we need find the root, otherwise
          # it is probably a local temporary
          # (e.g. a return value from a call),
          # we should prevent cursorfication
          dest.flags.incl preventCursor
        else:
          for r in roots:
            connect(c, dest.sym, r[0], n[1].info)

      else:
        let magic = if n[0].kind == nkSym: n[0].sym.magic else: mNone
        # this list is subtle, we try to answer the question if after 'dest = f(src)'
        # there is a connection betwen 'src' and 'dest' so that mutations to 'src'
        # also reflect 'dest':
        if magic in {mNone, mMove, mSlice,
            mAppendStrCh, mAppendStrStr, mAppendSeqElem,
            mArrToSeq, mOpenArrayToSeq}:
          for i in 1..<n.len:
            # we always have to assume a 'select(...)' like mechanism.
            # But at least we do filter out simple POD types from the
            # list of dependencies via the 'hasDestructor' check for
            # the root's symbol.
            if hasDestructor(n[i].typ.skipTypes({tyVar, tySink, tyLent, tyGenericInst, tyAlias})):
              destMightOwn(c, dest, n[i])

  else:
    # something we cannot handle:
    dest.flags.incl preventCursor

proc noCursor(c: var Partitions, s: PSym) =
  let vid = variableId(c, s)
  if vid >= 0:
    c.s[vid].flags.incl preventCursor

proc pretendOwnsData(c: var Partitions, s: PSym) =
  let vid = variableId(c, s)
  if vid >= 0:
    c.s[vid].flags.incl ownsData

const
  explainCursors = false

proc isConstSym(s: PSym): bool =
  result = s.kind in {skConst, skLet} or isConstParam(s)

proc toString(n: PNode): string =
  if n.kind == nkEmpty: result = "<empty>"
  else: result = $n

proc borrowFrom(c: var Partitions; dest: PSym; src: PNode) =
  const
    url = "see https://nim-lang.github.io/Nim/manual_experimental.html#view-types-algorithm-path-expressions for details"

  let s = pathExpr(src, c.owner)
  if s == nil:
    localError(c.g.config, src.info, "cannot borrow from " & src.toString & ", it is not a path expression; " & url)
  elif s.kind == nkSym:
    if dest.kind == skResult:
      if s.sym.kind != skParam or s.sym.position != 0:
        localError(c.g.config, src.info, "'result' must borrow from the first parameter")

    let vid = variableId(c, dest)
    if vid >= 0:
      var sourceIdx = variableId(c, s.sym)
      if sourceIdx < 0:
        sourceIdx = c.s.len
        c.s.add VarIndex(con: Connection(kind: isEmptyRoot), sym: s.sym, reassignedTo: 0,
                        aliveStart: MinTime, aliveEnd: MaxTime)

      c.s[vid].borrowsFrom.add sourceIdx
      if isConstSym(s.sym):
        c.s[vid].flags.incl viewBorrowsFromConst
  else:
    let vid = variableId(c, dest)
    if vid >= 0:
      c.s[vid].flags.incl viewBorrowsFromConst
    #discard "a valid borrow location that is a deeply constant expression so we have nothing to track"


proc borrowingCall(c: var Partitions; destType: PType; n: PNode; i: int) =
  let v = pathExpr(n[i], c.owner)
  if v != nil and v.kind == nkSym:
    when false:
      let isView = directViewType(destType) == immutableView
      if n[0].kind == nkSym and n[0].sym.name.s == "[]=":
        localError(c.g.config, n[i].info, "attempt to mutate an immutable view")

    for j in i+1..<n.len:
      if getMagic(n[j]) == mSlice:
        borrowFrom(c, v.sym, n[j])
  else:
    localError(c.g.config, n[i].info, "cannot determine the target of the borrow")

proc borrowingAsgn(c: var Partitions; dest, src: PNode) =
  proc mutableParameter(n: PNode): bool {.inline.} =
    result = n.kind == nkSym and n.sym.kind == skParam and n.sym.typ.kind == tyVar

  if dest.kind == nkSym:
    if directViewType(dest.typ) != noView:
      borrowFrom(c, dest.sym, src)
  else:
    let viewOrigin = pathExpr(dest, c.owner)
    if viewOrigin != nil and viewOrigin.kind == nkSym:
      let viewSym = viewOrigin.sym
      let directView = directViewType(dest[0].typ) # check something like result[first] = toOpenArray(s, first, last-1)
                                                   # so we don't need to iterate the original type
      let originSymbolView = directViewType(viewSym.typ) # find the original symbol which preserves the view type
                                                    #  var foo: var Object = a
                                                    #  foo.id = 777 # the type of foo is no view, so we need
                                                    #  to check the original symbol
      let viewSets = {directView, originSymbolView}

      if viewSets * {mutableView, immutableView} != {}:
        # we do not borrow, but we use the view to mutate the borrowed
        # location:
        let vid = variableId(c, viewSym)
        if vid >= 0:
          c.s[vid].flags.incl viewDoesMutate
      #[of immutableView:
        if dest.kind == nkBracketExpr and dest[0].kind == nkHiddenDeref and
            mutableParameter(dest[0][0]):
          discard "remains a mutable location anyhow"
        else:
          localError(c.g.config, dest.info, "attempt to mutate a borrowed location from an immutable view")
          ]#
      else:
        discard "nothing to do"

proc containsPointer(t: PType): bool =
  proc wrap(t: PType): bool {.nimcall.} = t.kind in {tyRef, tyPtr}
  result = types.searchTypeFor(t, wrap)

proc deps(c: var Partitions; dest, src: PNode) =
  if borrowChecking in c.goals:
    borrowingAsgn(c, dest, src)

  var targets: seq[(PSym, int)] = @[]
  var sources: seq[(PSym, int)] = @[]
  allRoots(dest, targets, 0)
  allRoots(src, sources, 0)

  let destIsComplex = containsPointer(dest.typ)

  for t in targets:
    if dest.kind != nkSym and c.inNoSideEffectSection == 0:
      potentialMutation(c, t[0], t[1], dest.info)

    if destIsComplex:
      for s in sources:
        connect(c, t[0], s[0], dest.info)

  if cursorInference in c.goals and src.kind != nkEmpty:
    let d = pathExpr(dest, c.owner)
    if d != nil and d.kind == nkSym:
      let vid = variableId(c, d.sym)
      if vid >= 0:
        destMightOwn(c, c.s[vid], src)
        for source in sources:
          let s = source[0]
          if s == d.sym:
            discard "assignments like: it = it.next are fine"
          elif {sfGlobal, sfThread} * s.flags != {} or hasDisabledAsgn(c.g, s.typ):
            # do not borrow from a global variable or from something with a
            # disabled assignment operator.
            c.s[vid].flags.incl preventCursor
            when explainCursors: echo "A not a cursor: ", d.sym, " ", s
          else:
            let srcid = variableId(c, s)
            if srcid >= 0:
              if s.kind notin {skResult, skParam} and (
                  c.s[srcid].aliveEnd < c.s[vid].aliveEnd):
                # you cannot borrow from a local that lives shorter than 'vid':
                when explainCursors: echo "B not a cursor ", d.sym, " ", c.s[srcid].aliveEnd, " ", c.s[vid].aliveEnd
                c.s[vid].flags.incl preventCursor
              elif {isReassigned, preventCursor} * c.s[srcid].flags != {}:
                # you cannot borrow from something that is re-assigned:
                when explainCursors: echo "C not a cursor ", d.sym, " ", c.s[srcid].flags, " reassignedTo ", c.s[srcid].reassignedTo
                c.s[vid].flags.incl preventCursor
              elif c.s[srcid].reassignedTo != 0 and c.s[srcid].reassignedTo != d.sym.id:
                when explainCursors: echo "D not a cursor ", d.sym, " reassignedTo ", c.s[srcid].reassignedTo
                c.s[vid].flags.incl preventCursor


proc potentialMutationViaArg(c: var Partitions; n: PNode; callee: PType) =
  if constParameters in c.goals and tfNoSideEffect in callee.flags:
    discard "we know there are no hidden mutations through an immutable parameter"
  elif c.inNoSideEffectSection == 0 and containsPointer(n.typ):
    var roots: seq[(PSym, int)] = @[]
    allRoots(n, roots, RootEscapes)
    for r in roots: potentialMutation(c, r[0], r[1], n.info)

proc traverse(c: var Partitions; n: PNode) =
  inc c.abstractTime
  case n.kind
  of nkLetSection, nkVarSection:
    for child in n:
      let last = lastSon(child)
      traverse(c, last)
      if child.kind == nkVarTuple and last.kind in {nkPar, nkTupleConstr}:
        if child.len-2 != last.len: return
        for i in 0..<child.len-2:
          #registerVariable(c, child[i])
          deps(c, child[i], last[i])
      else:
        for i in 0..<child.len-2:
          #registerVariable(c, child[i])
          deps(c, child[i], last)
  of nkAsgn, nkFastAsgn, nkSinkAsgn:
    traverse(c, n[0])
    inc c.inAsgnSource
    traverse(c, n[1])
    dec c.inAsgnSource
    deps(c, n[0], n[1])
  of nkSym:
    dec c.abstractTime

  of nodesToIgnoreSet:
    dec c.abstractTime
    discard "do not follow the construct"
  of nkCallKinds:
    for child in n: traverse(c, child)

    let parameters = n[0].typ
    let L = if parameters != nil: parameters.signatureLen else: 0
    let m = getMagic(n)

    if m == mEnsureMove and n[1].kind == nkSym:
      # we know that it must be moved so it cannot be a cursor
      noCursor(c, n[1].sym)

    for i in 1..<n.len:
      let it = n[i]
      if i < L:
        let paramType = parameters[i].skipTypes({tyGenericInst, tyAlias})
        if not paramType.isCompileTimeOnly and paramType.kind in {tyVar, tySink, tyOwned}:
          var roots: seq[(PSym, int)] = @[]
          allRoots(it, roots, RootEscapes)
          if paramType.kind == tyVar:
            if c.inNoSideEffectSection == 0:
              for r in roots: potentialMutation(c, r[0], r[1], it.info)
            for r in roots: noCursor(c, r[0])

            if borrowChecking in c.goals:
              # a call like 'result.add toOpenArray()' can also be a borrow
              # operation. We know 'paramType' is a tyVar and we really care if
              # 'paramType[0]' is still a view type, this is not a typo!
              if directViewType(paramType[0]) == noView and classifyViewType(paramType[0]) != noView:
                borrowingCall(c, paramType[0], n, i)
        elif m == mNone:
          potentialMutationViaArg(c, n[i], parameters)

  of nkAddr, nkHiddenAddr:
    traverse(c, n[0])
    when false:
      # XXX investigate if this is required, it doesn't look
      # like it is!
      var roots: seq[(PSym, int)]
      allRoots(n[0], roots, RootEscapes)
      for r in roots:
        potentialMutation(c, r[0], r[1], it.info)

  of nkTupleConstr, nkBracket:
    for child in n: traverse(c, child)
    if c.inAsgnSource > 0:
      for i in 0..<n.len:
        if n[i].kind == nkSym:
          # we assume constructions with cursors are better without
          # the cursors because it's likely we can move then, see
          # test arc/topt_no_cursor.nim
          pretendOwnsData(c, n[i].sym)

  of nkObjConstr:
    for child in n: traverse(c, child)
    if c.inAsgnSource > 0:
      for i in 1..<n.len:
        let it = n[i].skipColon
        if it.kind == nkSym:
          # we assume constructions with cursors are better without
          # the cursors because it's likely we can move then, see
          # test arc/topt_no_cursor.nim
          pretendOwnsData(c, it.sym)

  of nkPragmaBlock:
    let pragmaList = n[0]
    var enforceNoSideEffects = 0
    for i in 0..<pragmaList.len:
      if isNoSideEffectPragma(pragmaList[i]):
        enforceNoSideEffects = 1
        break

    inc c.inNoSideEffectSection, enforceNoSideEffects
    traverse(c, n.lastSon)
    dec c.inNoSideEffectSection, enforceNoSideEffects
  of nkWhileStmt, nkForStmt, nkParForStmt:
    for child in n: traverse(c, child)
    # analyse loops twice so that 'abstractTime' suffices to detect cases
    # like:
    #   while cond:
    #     mutate(graph)
    #     connect(graph, cursorVar)
    for child in n: traverse(c, child)

    if n.kind == nkWhileStmt:
      traverse(c, n[0])
      # variables in while condition has longer alive time than local variables
      # in the while loop body
  of nkDefer:
    if c.processDefer:
      for child in n: traverse(c, child)
  else:
    for child in n: traverse(c, child)

proc markAsReassigned(c: var Partitions; vid: int) {.inline.} =
  c.s[vid].flags.incl isReassigned
  if c.inConditional > 0 and c.inLoop > 0:
    # bug #17033: live ranges with loops and conditionals are too
    # complex for our current analysis, so we prevent the cursorfication.
    c.s[vid].flags.incl isConditionallyReassigned

proc computeLiveRanges(c: var Partitions; n: PNode) =
  # first pass: Compute live ranges for locals.
  # **Watch out!** We must traverse the tree like 'traverse' does
  # so that the 'c.abstractTime' is consistent.
  inc c.abstractTime
  case n.kind
  of nkLetSection, nkVarSection:
    for child in n:
      let last = lastSon(child)
      computeLiveRanges(c, last)
      if child.kind == nkVarTuple and last.kind in {nkPar, nkTupleConstr}:
        if child.len-2 != last.len: return
        for i in 0..<child.len-2:
          registerVariable(c, child[i])
          #deps(c, child[i], last[i])
      else:
        for i in 0..<child.len-2:
          registerVariable(c, child[i])
          #deps(c, child[i], last)

        if c.inLoop > 0 and child[0].kind == nkSym: # bug #22787
          let vid = variableId(c, child[0].sym)
          if child[^1].kind != nkEmpty:
            markAsReassigned(c, vid)
  of nkAsgn, nkFastAsgn, nkSinkAsgn:
    computeLiveRanges(c, n[0])
    computeLiveRanges(c, n[1])
    if n[0].kind == nkSym:
      let vid = variableId(c, n[0].sym)
      if vid >= 0:
        if n[1].kind == nkSym and (c.s[vid].reassignedTo == 0 or c.s[vid].reassignedTo == n[1].sym.id):
          c.s[vid].reassignedTo = n[1].sym.id
          if c.inConditional > 0 and c.inLoop > 0:
            # bug #22200: live ranges with loops and conditionals are too
            # complex for our current analysis, so we prevent the cursorfication.
            c.s[vid].flags.incl isConditionallyReassigned
        else:
          markAsReassigned(c, vid)

  of nkSym:
    dec c.abstractTime
    if n.sym.kind in {skVar, skResult, skTemp, skLet, skForVar, skParam}:
      let id = variableId(c, n.sym)
      if id >= 0:
        c.s[id].aliveEnd = max(c.s[id].aliveEnd, c.abstractTime)
        if n.sym.kind == skResult:
          c.s[id].aliveStart = min(c.s[id].aliveStart, c.abstractTime)

  of nodesToIgnoreSet:
    dec c.abstractTime
    discard "do not follow the construct"
  of nkCallKinds:
    for child in n: computeLiveRanges(c, child)

    let parameters = n[0].typ
    let L = if parameters != nil: parameters.signatureLen else: 0

    for i in 1..<n.len:
      let it = n[i]
      if it.kind == nkSym and i < L:
        let paramType = parameters[i].skipTypes({tyGenericInst, tyAlias})
        if not paramType.isCompileTimeOnly and paramType.kind == tyVar:
          let vid = variableId(c, it.sym)
          if vid >= 0:
            markAsReassigned(c, vid)

  of nkAddr, nkHiddenAddr:
    computeLiveRanges(c, n[0])
    if n[0].kind == nkSym:
      let vid = variableId(c, n[0].sym)
      if vid >= 0:
        c.s[vid].flags.incl preventCursor

  of nkPragmaBlock:
    computeLiveRanges(c, n.lastSon)
  of nkWhileStmt, nkForStmt, nkParForStmt:
    for child in n: computeLiveRanges(c, child)
    # analyse loops twice so that 'abstractTime' suffices to detect cases
    # like:
    #   while cond:
    #     mutate(graph)
    #     connect(graph, cursorVar)
    inc c.inLoop
    for child in n: computeLiveRanges(c, child)
    dec c.inLoop

    if n.kind == nkWhileStmt:
      computeLiveRanges(c, n[0])
      # variables in while condition has longer alive time than local variables
      # in the while loop body
  of nkElifBranch, nkElifExpr, nkElse, nkOfBranch:
    inc c.inConditional
    for child in n: computeLiveRanges(c, child)
    dec c.inConditional
  of nkDefer:
    if c.processDefer:
      for child in n: computeLiveRanges(c, child)
    else:
      c.defers.add n
  else:
    for child in n: computeLiveRanges(c, child)

proc computeGraphPartitions*(s: PSym; n: PNode; g: ModuleGraph; goals: set[Goal]): Partitions =
  result = Partitions(owner: s, g: g, goals: goals)
  if s.kind notin {skModule, skMacro}:
    let params = s.typ.n
    for i in 1..<params.len:
      registerParam(result, params[i])
    if resultPos < s.ast.safeLen:
      registerResult(result, s.ast[resultPos])

  computeLiveRanges(result, n)
  result.processDefer = true
  for i in countdown(len(result.defers)-1, 0):
    computeLiveRanges(result, result.defers[i])
  result.processDefer = false
  # restart the timer for the second pass:
  result.abstractTime = AbstractTime 0
  traverse(result, n)
  result.processDefer = true
  for i in countdown(len(result.defers)-1, 0):
    traverse(result, result.defers[i])
  result.processDefer = false

proc dangerousMutation(g: MutationInfo; v: VarIndex): bool =
  #echo "range ", v.aliveStart, " .. ", v.aliveEnd, " ", v.sym
  if {isMutated, isMutatedByVarParam} * g.flags != {}:
    for m in g.mutations:
      #echo "mutation ", m
      if m in v.aliveStart..v.aliveEnd:
        return true
  return false

proc cannotBorrow(config: ConfigRef; s: PSym; g: MutationInfo) =
  var m = "cannot borrow " & s.name.s &
    "; what it borrows from is potentially mutated"

  if g.mutatedHere != unknownLineInfo:
    m.add "\n"
    m.add config $ g.mutatedHere
    m.add " the mutation is here"
  if g.connectedVia != unknownLineInfo:
    m.add "\n"
    m.add config $ g.connectedVia
    m.add " is the statement that connected the mutation to the parameter"
  localError(config, s.info, m)

proc checkBorrowedLocations*(par: var Partitions; body: PNode; config: ConfigRef) =
  for i in 0 ..< par.s.len:
    let v = par.s[i].sym
    if v.kind != skParam and classifyViewType(v.typ) != noView:
      let rid = root(par, i)
      if rid >= 0:
        var constViolation = false
        for b in par.s[rid].borrowsFrom:
          let sid = root(par, b)
          if sid >= 0:
            if par.s[sid].con.kind == isRootOf and dangerousMutation(par.graphs[par.s[sid].con.graphIndex], par.s[i]):
              cannotBorrow(config, v, par.graphs[par.s[sid].con.graphIndex])
            if par.s[sid].sym.kind != skParam and par.s[sid].aliveEnd < par.s[rid].aliveEnd:
              localError(config, v.info, "'" & v.name.s & "' borrows from location '" & par.s[sid].sym.name.s &
                "' which does not live long enough")
            if viewDoesMutate in par.s[rid].flags and isConstSym(par.s[sid].sym):
              localError(config, v.info, "'" & v.name.s & "' borrows from the immutable location '" &
                par.s[sid].sym.name.s & "' and attempts to mutate it")
              constViolation = true
        if {viewDoesMutate, viewBorrowsFromConst} * par.s[rid].flags == {viewDoesMutate, viewBorrowsFromConst} and
            not constViolation:
          # we do not track the constant expressions we allow to borrow from so
          # we can only produce a more generic error message:
          localError(config, v.info, "'" & v.name.s &
              "' borrows from an immutable location and attempts to mutate it")

      #if par.s[rid].con.kind == isRootOf and dangerousMutation(par.graphs[par.s[rid].con.graphIndex], par.s[i]):
      #  cannotBorrow(config, s, par.graphs[par.s[rid].con.graphIndex])

proc computeCursors*(s: PSym; n: PNode; g: ModuleGraph) =
  var par = computeGraphPartitions(s, n, g, {cursorInference})
  for i in 0 ..< par.s.len:
    let v = addr(par.s[i])
    if v.flags * {ownsData, preventCursor, isConditionallyReassigned} == {} and
        v.sym.kind notin {skParam, skResult} and
        v.sym.flags * {sfThread, sfGlobal} == {} and hasDestructor(v.sym.typ) and
        v.sym.typ.skipTypes({tyGenericInst, tyAlias}).kind != tyOwned and
        (getAttachedOp(g, v.sym.typ, attachedAsgn) == nil or
        sfError notin getAttachedOp(g, v.sym.typ, attachedAsgn).flags):
      let rid = root(par, i)
      if par.s[rid].con.kind == isRootOf and dangerousMutation(par.graphs[par.s[rid].con.graphIndex], par.s[i]):
        discard "cannot cursor into a graph that is mutated"
      else:
        v.sym.flags.incl sfCursor
        when false:
          echo "this is now a cursor ", v.sym, " ", par.s[rid].flags, " ", g.config $ v.sym.info

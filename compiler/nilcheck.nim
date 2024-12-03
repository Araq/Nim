#
#
#           The Nim Compiler
#        (c) Copyright 2017 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import ast, renderer, msgs, options, lineinfos, idents, treetab
import std/[intsets, tables, sequtils, strutils, sets, strformat, hashes]

when defined(nimPreviewSlimSystem):
  import std/assertions

# IMPORTANT: notes not up to date, i'll update this comment again
#
# notes:
#
# Env: int => nilability
# a = b
#   nilability a <- nilability b
# deref a
#   if Nil error is nil
#   if MaybeNil error might be nil, hint add if isNil
#   if Safe fine
# fun(arg: A)
#   nilability arg <- for ref MaybeNil, for not nil or others Safe
# map is env?
# a or b
#   each one forks a different env
#   result = union(envL, envR)
# a and b
#   b forks a's env
# if a: code
#   result = union(previousEnv after not a, env after code)
# if a: b else: c
#   result = union(env after b, env after c)
# result = b
#   nilability result <- nilability b, if return type is not nil and result not safe, error
# return b
#   as result = b
# try: a except: b finally: c
#   in b and c env is union of all possible try first n lines, after union of a and b and c
#   keep in mind canRaise and finally
# case a: of b: c
#   similar to if
# call(arg)
#   if it returns ref, assume it's MaybeNil: hint that one can add not nil to the return type
# call(var arg) # zahary comment
#   if arg is ref, assume it's MaybeNil after call
# loop
#   union of env for 0, 1, 2 iterations as Herb Sutter's paper
#   why 2?
# return
#   if something: stop (break return etc)
#   is equivalent to if something: .. else: remain
# new(ref)
#   ref becomes Safe
# objConstr(a: b)
#   returns safe
# each check returns its nilability and map

type
  SeqOfDistinct[T, U] = distinct seq[U]

# TODO use distinct base type instead of int?
func `[]`[T, U](a: SeqOfDistinct[T, U], index: T): U =
  (seq[U])(a)[index.int]

proc `[]=`[T, U](a: var SeqOfDistinct[T, U], index: T, value: U) =
  ((seq[U])(a))[index.int] = value

func `[]`[T, U](a: var SeqOfDistinct[T, U], index: T): var U =
  (seq[U])(a)[index.int]

func len[T, U](a: SeqOfDistinct[T, U]): T =
  (seq[U])(a).len.T

func low[T, U](a: SeqOfDistinct[T, U]): T =
  (seq[U])(a).low.T

func high[T, U](a: SeqOfDistinct[T, U]): T =
  (seq[U])(a).high.T

proc setLen[T, U](a: var SeqOfDistinct[T, U], length: T) =
  ((seq[U])(a)).setLen(length.Natural)


proc newSeqOfDistinct[T, U](length: T = 0.T): SeqOfDistinct[T, U] =
  (SeqOfDistinct[T, U])(newSeq[U](length.int))

func newSeqOfDistinct[T, U](length: int = 0): SeqOfDistinct[T, U] =
  # newSeqOfDistinct(length.T)
  # ? newSeqOfDistinct[T, U](length.T)
  (SeqOfDistinct[T, U])(newSeq[U](length))

iterator items[T, U](a: SeqOfDistinct[T, U]): U =
  for element in (seq[U])(a):
    yield element

iterator pairs[T, U](a: SeqOfDistinct[T, U]): (T, U) =
  for i, element in (seq[U])(a):
    yield (i.T, element)

func `$`[T, U](a: SeqOfDistinct[T, U]): string =
  $((seq[U])(a))

proc add*[T, U](a: var SeqOfDistinct[T, U], value: U) =
  ((seq[U])(a)).add(value)

type
  ## a hashed representation of a node: should be equal for structurally equal nodes
  Symbol = distinct int

  ## the index of an expression in the pre-indexed sequence of those
  ExprIndex = distinct int16

  ## the set index
  SetIndex = distinct int

  ## transition kind:
  ##   what was the reason for changing the nilability of an expression
  ##   useful for error messages and showing why an expression is being detected as nil / maybe nil
  TransitionKind = enum TArg, TAssign, TType, TNil, TVarArg, TResult, TSafe, TPotentialAlias, TDependant

  ## keep history for each transition
  History = object
    info: TLineInfo ## the location
    nilability: Nilability ## the nilability
    kind: TransitionKind ## what kind of transition was that
    node: PNode ## the node of the expression

  ## the context for the checker: an instance for each procedure
  NilCheckerContext = ref object
    # abstractTime: AbstractTime
    # partitions: Partitions
    # symbolGraphs: Table[Symbol, ]
    symbolIndices: Table[Symbol, ExprIndex] ## index for each symbol
    expressions: SeqOfDistinct[ExprIndex, PNode] ## a sequence of pre-indexed expressions
    dependants: SeqOfDistinct[ExprIndex, IntSet] ## expr indices for expressions which are compound and based on others
    warningLocations: HashSet[TLineInfo] ## warning locations to check we don't warn twice for stuff like warnings in for loops
    idgen: IdGenerator ## id generator
    config: ConfigRef ## the config of the compiler

  ## a map that is containing the current nilability for usually a branch
  ## and is pointing optionally to a parent map: they make a stack of maps
  NilMap = ref object
    expressions:  SeqOfDistinct[ExprIndex, Nilability] ## the expressions with the same order as in NilCheckerContext
    history:  SeqOfDistinct[ExprIndex, seq[History]] ## history for each of them
    # what about gc and refs?
    setIndices: SeqOfDistinct[ExprIndex, SetIndex] ## set indices for each expression
    sets:     SeqOfDistinct[SetIndex, IntSet] ## disjoint sets with the aliased expressions
    parent:   NilMap ## the parent map

  ## Nilability : if a value is nilable.
  ## we have maybe nil and nil, so we can differentiate between
  ## cases where we know for sure a value is nil and not
  ## otherwise we can have Safe, MaybeNil
  ## Parent: is because we just use a sequence with the same length
  ## instead of a table, and we need to check if something was initialized
  ## at all: if Parent is set, then you need to check the parent nilability
  ## if the parent is nil, then for now we return MaybeNil
  ## unreachable is the result of add(Safe, Nil) and others
  ## it is a result of no states left, so it's usually e.g. in unreachable else branches?
  Nilability* = enum Parent, Safe, MaybeNil, Nil, Unreachable

  ## check
  Check = object
    nilability: Nilability
    map: NilMap
    elements: seq[(PNode, Nilability)]


# useful to have known resultId so we can set it in the beginning and on return
const resultId: Symbol = (-1).Symbol
const resultExprIndex: ExprIndex = 0.ExprIndex
const noSymbol = (-2).Symbol

func `<`*(a: ExprIndex, b: ExprIndex): bool =
  a.int16 < b.int16

func `<=`*(a: ExprIndex, b: ExprIndex): bool =
  a.int16 <= b.int16

func `>`*(a: ExprIndex, b: ExprIndex): bool =
  a.int16 > b.int16

func `>=`*(a: ExprIndex, b: ExprIndex): bool =
  a.int16 >= b.int16

func `==`*(a: ExprIndex, b: ExprIndex): bool =
  a.int16 == b.int16

func `$`*(a: ExprIndex): string =
  $(a.int16)

func `+`*(a: ExprIndex, b: ExprIndex): ExprIndex =
  (a.int16 + b.int16).ExprIndex

# TODO overflowing / < 0?
func `-`*(a: ExprIndex, b: ExprIndex): ExprIndex =
  (a.int16 - b.int16).ExprIndex

func `$`*(a: SetIndex): string =
  $(a.int)

func `==`*(a: SetIndex, b: SetIndex): bool =
  a.int == b.int

func `+`*(a: SetIndex, b: SetIndex): SetIndex =
  (a.int + b.int).SetIndex

# TODO over / under limit?
func `-`*(a: SetIndex, b: SetIndex): SetIndex =
  (a.int - b.int).SetIndex

proc check(n: PNode, ctx: NilCheckerContext, map: NilMap): Check
proc checkCondition(n: PNode, ctx: NilCheckerContext, map: NilMap, reverse: bool, base: bool): NilMap

# the NilMap structure

proc newNilMap(parent: NilMap = nil, count: int = -1): NilMap =
  var expressionsCount = 0
  if count != -1:
    expressionsCount = count
  elif not parent.isNil:
    expressionsCount = parent.expressions.len.int
  result = NilMap(
    expressions: newSeqOfDistinct[ExprIndex, Nilability](expressionsCount),
    history: newSeqOfDistinct[ExprIndex, seq[History]](expressionsCount),
    setIndices: newSeqOfDistinct[ExprIndex, SetIndex](expressionsCount),
    parent: parent)
  if parent.isNil:
    for i, expr in result.expressions:
      result.setIndices[i] = i.SetIndex
      var newSet = initIntSet()
      newSet.incl(i.int)
      result.sets.add(newSet)
  else:
    for i, exprs in parent.sets:
      result.sets.add(exprs)
    for i, index in parent.setIndices:
      result.setIndices[i] = index
    # result.sets = parent.sets
  # if not parent.isNil:
  #   # optimize []?
  #   result.expressions = parent.expressions
  #   result.history = parent.history
  #   result.sets = parent.sets
  # result.base = if parent.isNil: result else: parent.base

proc `[]`(map: NilMap, index: ExprIndex): Nilability =
  if index < 0.ExprIndex or index >= map.expressions.len:
    return MaybeNil
  var now = map
  while not now.isNil:
    if now.expressions[index] != Parent:
      return now.expressions[index]
    now = now.parent
  return MaybeNil

proc history(map: NilMap, index: ExprIndex): seq[History] =
  if index < map.expressions.len:
    map.history[index]
  else:
    @[]


# helpers for debugging

# import macros

# echo-s only when nilDebugInfo is defined
# macro aecho*(a: varargs[untyped]): untyped =
#   var e = nnkCall.newTree(ident"echo")
#   for b in a:
#     e.add(b)
#   result = quote:
#     when defined(nilDebugInfo):
#       `e`

# end of helpers for debugging


proc symbol(n: PNode): Symbol
func `$`(map: NilMap): string
proc reverseDirect(map: NilMap): NilMap
proc checkBranch(n: PNode, ctx: NilCheckerContext, map: NilMap): Check
proc hasUnstructuredControlFlowJump(n: PNode): bool

proc symbol(n: PNode): Symbol =
  ## returns a Symbol for each expression
  ## the goal is to get an unique Symbol
  ## but we have to ensure hashTree does it as we expect
  case n.kind:
  of nkIdent:
    # TODO ensure no idents get passed to symbol
    result = noSymbol
  of nkSym:
    if n.sym.kind == skResult: # credit to disruptek for showing me that
      result = resultId
    else:
      result = n.sym.id.Symbol
  of nkHiddenAddr, nkAddr:
    result = symbol(n[0])
  else:
    result = hashTree(n).Symbol
  # echo "symbol ", n, " ", n.kind, " ", result.int

func `$`(map: NilMap): string =
  result = ""
  var now = map
  var stack: seq[NilMap] = @[]
  while not now.isNil:
    stack.add(now)
    now = now.parent
  result.add("### start\n")
  for i in 0 .. stack.len - 1:
    now = stack[i]
    result.add("  ###\n")
    for index, value in now.expressions:
      result.add(&"    {index} {value}\n")
  result.add "### end\n"

proc namedMapDebugInfo(ctx: NilCheckerContext, map: NilMap): string =
  result = ""
  var now = map
  var stack: seq[NilMap] = @[]
  while not now.isNil:
    stack.add(now)
    now = now.parent
  result.add("### start\n")
  for i in 0 .. stack.len - 1:
    now = stack[i]
    result.add("  ###\n")
    for index, value in now.expressions:
      let name = ctx.expressions[index]
      result.add(&"    {name} {index} {value}\n")
  result.add("### end\n")

proc namedSetsDebugInfo(ctx: NilCheckerContext, map: NilMap): string =
  result = "### sets "
  for index, setIndex in map.setIndices:
    var aliasSet = map.sets[setIndex]
    result.add("{")
    let expressions = aliasSet.mapIt($ctx.expressions[it.ExprIndex])
    result.add(join(expressions, ", "))
    result.add("} ")
  result.add("\n")

proc namedMapAndSetsDebugInfo(ctx: NilCheckerContext, map: NilMap): string =
  result = namedMapDebugInfo(ctx, map) & namedSetsDebugInfo(ctx, map)



const noExprIndex = (-1).ExprIndex
const noSetIndex = (-1).SetIndex

proc `==`(a: Symbol, b: Symbol): bool =
  a.int == b.int

func `$`(a: Symbol): string =
  $(a.int)

template isConstBracket(n: PNode): bool =
  n.kind == nkBracketExpr and n[1].kind in nkLiterals

proc index(ctx: NilCheckerContext, n: PNode): ExprIndex =
  # echo "n ", n, " ", n.kind
  let a = symbol(n)
  if ctx.symbolIndices.hasKey(a):
    return ctx.symbolIndices[a]
  else:
    #for a, e in ctx.expressions:
    #  echo a, " ", e
    #echo n.kind
    # internalError(ctx.config, n.info, "expected " & $a & " " & $n & " to have a index")
    return noExprIndex
    #
  #ctx.symbolIndices[symbol(n)]


proc aliasSet(ctx: NilCheckerContext, map: NilMap, n: PNode): IntSet =
  result = map.sets[map.setIndices[ctx.index(n)]]

proc aliasSet(ctx: NilCheckerContext, map: NilMap, index: ExprIndex): IntSet =
  result = map.sets[map.setIndices[index]]



proc store(map: NilMap, ctx: NilCheckerContext, index: ExprIndex, value: Nilability, kind: TransitionKind, info: TLineInfo, node: PNode = nil) =
  if index == noExprIndex:
    return
  map.expressions[index] = value
  map.history[index].add(History(info: info, kind: kind, node: node, nilability: value))
  #echo node, " ", index, " ", value
  #echo ctx.namedMapAndSetsDebugInfo(map)
  #for a, b in map.sets:
  #  echo a, " ", b
  # echo map

  var exprAliases = aliasSet(ctx, map, index)
  for a in exprAliases:
    if a.ExprIndex != index:
      #echo "alias ", a, " ", index
      map.expressions[a.ExprIndex] = value
      if value == Safe:
        map.history[a.ExprIndex] = @[]
      else:
        map.history[a.ExprIndex].add(History(info: info, kind: TPotentialAlias, node: node, nilability: value))

proc moveOut(ctx: NilCheckerContext, map: NilMap, target: PNode) =
  #echo "move out ", target
  var targetIndex = ctx.index(target)
  var targetSetIndex = map.setIndices[targetIndex]
  if targetSetIndex != noSetIndex:
    var targetSet = map.sets[targetSetIndex]
    if targetSet.len > 1:
      var other: ExprIndex = default(ExprIndex)

      for element in targetSet:
        if element.ExprIndex != targetIndex:
          other = element.ExprIndex
          break
          # map.sets[element].excl(targetIndex)
      map.sets[map.setIndices[other]].excl(targetIndex.int)
      var newSet = initIntSet()
      newSet.incl(targetIndex.int)
      map.sets.add(newSet)
      map.setIndices[targetIndex] = map.sets.len - 1.SetIndex

proc moveOutDependants(ctx: NilCheckerContext, map: NilMap, node: PNode) =
  let index = ctx.index(node)
  for dependant in ctx.dependants[index]:
    moveOut(ctx, map, ctx.expressions[dependant.ExprIndex])

proc storeDependants(ctx: NilCheckerContext, map: NilMap, node: PNode, value: Nilability) =
  let index = ctx.index(node)
  for dependant in ctx.dependants[index]:
    map.store(ctx, dependant.ExprIndex, value, TDependant, node.info, node)

proc move(ctx: NilCheckerContext, map: NilMap, target: PNode, assigned: PNode) =
  #echo "move ", target, " ", assigned
  var targetIndex = ctx.index(target)
  var assignedIndex: ExprIndex
  var targetSetIndex = map.setIndices[targetIndex]
  var assignedSetIndex: SetIndex
  if assigned.kind == nkSym:
    assignedIndex = ctx.index(assigned)
    assignedSetIndex = map.setIndices[assignedIndex]
  else:
    assignedIndex = noExprIndex
    assignedSetIndex = noSetIndex
  if assignedIndex == noExprIndex:
    moveOut(ctx, map, target)
  elif targetSetIndex != assignedSetIndex:
    map.sets[targetSetIndex].excl(targetIndex.int)
    map.sets[assignedSetIndex].incl(targetIndex.int)
    map.setIndices[targetIndex] = assignedSetIndex

# proc hasKey(map: NilMap, ): bool =
#   var now = map
#   result = false
#   while not now.isNil:
#     if now.locals.hasKey(graphIndex):
#       return true
#     now = now.previous

iterator pairs(map: NilMap): (ExprIndex, Nilability) =
  for index, value in map.expressions:
    yield (index, map[index])

proc copyMap(map: NilMap): NilMap =
  if map.isNil:
    return nil
  result = newNilMap(map.parent) # no need for copy? if we change only this
  result.expressions = map.expressions
  result.history = map.history
  result.sets = map.sets
  result.setIndices = map.setIndices

using
  n: PNode
  conf: ConfigRef
  ctx: NilCheckerContext
  map: NilMap

proc typeNilability(typ: PType): Nilability

# maybe: if canRaise, return MaybeNil ?
# no, because the target might be safe already
# with or without an exception
proc checkCall(n, ctx, map): Check =
  # checks each call
  # special case for new(T) -> result is always Safe
  # for the others it depends on the return type of the call
  # check args and handle possible mutations

  var isNew = false
  result = Check(map: map)
  for i, child in n:
    discard check(child, ctx, map)

    if i > 0:
      # var args make a new map with MaybeNil for our node
      # as it might have been mutated
      # TODO similar for normal refs and fields: find dependent exprs: brackets

      if child.kind == nkHiddenAddr and not child.typ.isNil and child.typ.kind == tyVar and child.typ.elementType.kind == tyRef:
        if not isNew:
          result.map = newNilMap(map)
          isNew = true
        # result.map[$child] = MaybeNil
        var arg = child
        while arg.kind == nkHiddenAddr:
          arg = arg[0]
        let a = ctx.index(arg)
        if a != noExprIndex:
          moveOut(ctx, result.map, arg)
          moveOutDependants(ctx, result.map, arg)
          result.map.store(ctx, a, MaybeNil, TVarArg, n.info, arg)
          storeDependants(ctx, result.map, arg, MaybeNil)
      elif not child.typ.isNil and child.typ.kind == tyRef:
        if child.kind in {nkSym, nkDotExpr} or isConstBracket(child):
          let a = ctx.index(child)
          if ctx.dependants[a].len > 0:
            if not isNew:
              result.map = newNilMap(map)
              isNew = true
            moveOutDependants(ctx, result.map, child)
            storeDependants(ctx, result.map, child, MaybeNil)

  if n[0].kind == nkSym and n[0].sym.magic == mNew:
    # new hidden deref?
    var value = if n[1].kind == nkHiddenDeref: n[1][0] else: n[1]
    let b = ctx.index(value)
    result.map.store(ctx, b, Safe, TAssign, value.info, value)
    result.nilability = Safe
  else:
    # echo "n ", n, " ", n.typ.isNil
    if not n.typ.isNil:
      result.nilability = typeNilability(n.typ)
    else:
      result.nilability = Safe
  # echo result.map

template event(b: History): string =
  case b.kind:
  of TArg: "param with nilable type"
  of TNil: "it returns true for isNil"
  of TAssign: "assigns a value which might be nil"
  of TVarArg: "passes it as a var arg which might change to nil"
  of TResult: "it is nil by default"
  of TType: "it has ref type"
  of TSafe: "it is safe here as it returns false for isNil"
  of TPotentialAlias: "it might be changed directly or through an alias"
  of TDependant: "it might be changed because its base might be changed"

proc derefWarning(n, ctx, map; kind: Nilability) =
  ## a warning for potentially unsafe dereference
  if n.info in ctx.warningLocations:
    return
  ctx.warningLocations.incl(n.info)
  var a: seq[History] = @[]
  if n.kind == nkSym:
    a = history(map, ctx.index(n))
  var res = ""
  var issue = case kind:
      of Nil: "it is nil"
      of MaybeNil: "it might be nil"
      of Unreachable: "it is unreachable"
      else: ""
  res.add("can't deref " & $n & ", " & issue)
  if a.len > 0:
    res.add("\n")
  for b in a:
    res.add("  " & event(b) & " on line " & $b.info.line & ":" & $b.info.col)
  message(ctx.config, n.info, warnStrictNotNil, res)

proc handleNilability(check: Check; n, ctx, map) =
  ## handle the check:
  ##   register a warning(error?) for Nil/MaybeNil
  case check.nilability:
  of Nil:
    derefWarning(n, ctx, map, Nil)
  of MaybeNil:
    derefWarning(n, ctx, map, MaybeNil)
  of Unreachable:
    derefWarning(n, ctx, map, Unreachable)
  else:
    when defined(nilDebugInfo):
      message(ctx.config, n.info, hintUser, "can deref " & $n)

proc checkDeref(n, ctx, map): Check =
  ## check dereference: deref n should be ok only if n is Safe
  result = check(n[0], ctx, map)

  handleNilability(result, n[0], ctx, map)


proc checkRefExpr(n, ctx; check: Check): Check =
  ## check ref expressions: TODO not sure when this happens
  result = check
  if n.typ.kind != tyRef:
    result.nilability = typeNilability(n.typ)
  elif tfNotNil notin n.typ.flags:
    # echo "ref key ", n, " ", n.kind
    if n.kind in {nkSym, nkDotExpr} or isConstBracket(n):
      let key = ctx.index(n)
      result.nilability = result.map[key]
    elif n.kind == nkBracketExpr:
      # sometimes false positive
      result.nilability = MaybeNil
    else:
      # sometimes maybe false positive
      result.nilability = MaybeNil

proc checkDotExpr(n, ctx, map): Check =
  ## check dot expressions: make sure we can dereference the base
  result = check(n[0], ctx, map)
  result = checkRefExpr(n, ctx, result)

proc checkBracketExpr(n, ctx, map): Check =
  ## check bracket expressions: make sure we can dereference the base
  result = check(n[0], ctx, map)
  # if might be deref: [] == *(a + index) for cstring
  handleNilability(result, n[0], ctx, map)
  result = check(n[1], ctx, result.map)
  result = checkRefExpr(n, ctx, result)
  # echo n, " ", result.nilability


template union(l: Nilability, r: Nilability): Nilability =
  ## unify two states
  if l == r:
    l
  else:
    MaybeNil

template add(l: Nilability, r: Nilability): Nilability =
  if l == r: # Safe Safe -> Safe etc
    l
  elif l == Parent: # Parent Safe -> Safe etc
    r
  elif r == Parent:  # Safe Parent -> Safe etc
    l
  elif l == Unreachable or r == Unreachable: # Safe Unreachable -> Unreachable etc
    Unreachable
  elif l == MaybeNil: # Safe MaybeNil -> Safe etc
    r
  elif r == MaybeNil: # MaybeNil Nil -> Nil etc
    l
  else: # Safe Nil -> Unreachable etc
    Unreachable

proc findCommonParent(l: NilMap, r: NilMap): NilMap =
  result = l.parent
  while not result.isNil:
    var rparent = r.parent
    while not rparent.isNil:
      if result == rparent:
        return result
      rparent = rparent.parent
    result = result.parent

proc union(ctx: NilCheckerContext, l: NilMap, r: NilMap): NilMap =
  ## unify two maps from different branches
  ## combine their locals
  ## what if they are from different parts of the same tree
  ## e.g.
  ## a -> b -> c
  ##   -> b1
  ## common then?
  ##
  if l.isNil:
    return r
  elif r.isNil:
    return l

  let common = findCommonParent(l, r)
  result = newNilMap(common, ctx.expressions.len.int)

  for index, value in l:
    let h = history(r, index)
    let info = if h.len > 0: h[^1].info else: TLineInfo(line: 0) # assert h.len > 0
    # echo "history", name, value, r[name], h[^1].info.line
    result.store(ctx, index, union(value, r[index]), TAssign, info)

proc add(ctx: NilCheckerContext, l: NilMap, r: NilMap): NilMap =
  #echo "add "
  #echo namedMapDebugInfo(ctx, l)
  #echo " : "
  #echo namedMapDebugInfo(ctx, r)
  if l.isNil:
    return r
  elif r.isNil:
    return l

  let common = findCommonParent(l, r)
  result = newNilMap(common, ctx.expressions.len.int)

  for index, value in l:
    let h = history(r, index)
    let info = if h.len > 0: h[^1].info else: TLineInfo(line: 0)
    # TODO: refactor and also think: is TAssign a good one
    result.store(ctx, index, add(value, r[index]), TAssign, info)

  #echo "result"
  #echo namedMapDebugInfo(ctx, result)
  #echo ""
  #echo ""


proc checkAsgn(target: PNode, assigned: PNode; ctx, map): Check =
  ## check assignment
  ##   update map based on `assigned`
  if assigned.kind != nkEmpty:
    result = check(assigned, ctx, map)
  else:
    result = Check(nilability: typeNilability(target.typ), map: map)

  # we need to visit and check those, but we don't use the result for now
  # is it possible to somehow have another event happen here?
  discard check(target, ctx, map)

  if result.map.isNil:
    result.map = map
  if target.kind in {nkSym, nkDotExpr} or isConstBracket(target):
    let t = ctx.index(target)
    move(ctx, map, target, assigned)
    case assigned.kind:
    of nkNilLit:
      result.map.store(ctx, t, Nil, TAssign, target.info, target)
    else:
      result.map.store(ctx, t, result.nilability, TAssign, target.info, target)
      moveOutDependants(ctx, map, target)
      storeDependants(ctx, map, target, MaybeNil)
      if assigned.kind in {nkObjConstr, nkTupleConstr}:
        for (element, value) in result.elements:
          var elementNode = nkDotExpr.newTree(nkHiddenDeref.newTree(target), element)
          if symbol(elementNode) in ctx.symbolIndices:
            var elementIndex = ctx.index(elementNode)
            result.map.store(ctx, elementIndex, value, TAssign, target.info, elementNode)


proc checkReturn(n, ctx, map): Check =
  ## check return
  # return n same as result = n; return ?
  result = check(n[0], ctx, map)
  result.map.store(ctx, resultExprIndex, result.nilability, TAssign, n.info)


proc checkIf(n, ctx, map): Check =
  ## check branches based on condition
  result = default(Check)
  var mapIf: NilMap = map

  # first visit the condition

  # the structure is not If(Elif(Elif, Else), Else)
  # it is
  # If(Elif, Elif, Else)

  var mapCondition = checkCondition(n.sons[0].sons[0], ctx, mapIf, false, true)

  # the state of the conditions: negating conditions before the current one
  var layerHistory = newNilMap(mapIf)
  # the state after branch effects
  var afterLayer: NilMap = nil
  # the result nilability for expressions
  var nilability = Safe

  for branch in n.sons:
    var branchConditionLayer = newNilMap(layerHistory)
    var branchLayer: NilMap
    var code: PNode
    if branch.kind in {nkIfStmt, nkElifBranch}:
      var mapCondition = checkCondition(branch[0], ctx, branchConditionLayer, false, true)
      let reverseMapCondition = reverseDirect(mapCondition)
      layerHistory = ctx.add(layerHistory, reverseMapCondition)
      branchLayer = mapCondition
      code = branch[1]
    else:
      branchLayer = layerHistory
      code = branch

    let branchCheck = checkBranch(code, ctx, branchLayer)
    # handles nil afterLayer -> returns branchCheck.map
    afterLayer = ctx.union(afterLayer, branchCheck.map)
    nilability = if n.kind == nkIfStmt: Safe else: union(nilability, branchCheck.nilability)
  if n.sons.len > 1:
    result.map = afterLayer
    result.nilability = nilability
  else:
    if not hasUnstructuredControlFlowJump(n[0][1]):
      # here it matters what happend inside, because
      # we might continue in the parent branch after entering this one
      # either we enter the branch, so we get mapIf and effect of branch -> afterLayer
      # or we dont , so we get mapIf and (not condition) effect -> layerHistory
      result.map = ctx.union(layerHistory, afterLayer)
      result.nilability = Safe # no expr?
    else:
      # similar to else: because otherwise we are jumping out of
      # the branch, so no union with the mapIf (we dont continue if the condition was true)
      # here it also doesn't matter for the parent branch what happened in the branch, e.g. assigning to nil
      # as if we continue there, we haven't entered the branch probably
      # so we don't do an union with afterLayer
      # layerHistory has the effect of mapIf and (not condition)
      result.map = layerHistory
      result.nilability = Safe

proc checkFor(n, ctx, map): Check =
  ## check for loops
  ##   try to repeat the unification of the code twice
  ##   to detect what can change after a several iterations
  ##   approach based on discussions with Zahary/Araq
  ##   similar approach used for other loops
  var m = map.copyMap()
  var map0 = map.copyMap()
  #echo namedMapDebugInfo(ctx, map)
  m = check(n.sons[2], ctx, map).map.copyMap()
  if n[0].kind == nkSym:
    m.store(ctx, ctx.index(n[0]), typeNilability(n[0].typ), TAssign, n[0].info)
  # echo namedMapDebugInfo(ctx, map)
  var check2 = check(n.sons[2], ctx, m)
  var map2 = check2.map

  result = Check(map: ctx.union(map0, m))
  result.map = ctx.union(result.map, map2)
  result.nilability = Safe

# check:
# while code:
#   code2

# if code:
#   code2
# if code:
#   code2

# if code:
#   code2

# check(code), check(code2 in code's map)

proc checkWhile(n, ctx, map): Check =
  ## check while loops
  ##   try to repeat the unification of the code twice
  var m = checkCondition(n[0], ctx, map, false, false)
  var map0 = map.copyMap()
  m = check(n.sons[1], ctx, m).map
  var map1 = m.copyMap()
  var check2 = check(n.sons[1], ctx, m)
  var map2 = check2.map

  result = Check(map: ctx.union(map0, map1))
  result.map = ctx.union(result.map, map2)
  result.nilability = Safe

proc checkInfix(n, ctx, map): Check =
  ## check infix operators in condition
  ##   a and b : map is based on a; next b
  ##   a or b : map is an union of a and b's
  ##   a == b : use checkCondition
  ##   else: no change, just check args
  result = default(Check)
  if n[0].kind == nkSym:
    var mapL: NilMap = nil
    var mapR: NilMap = nil
    if n[0].sym.magic notin {mAnd, mEqRef}:
      mapL = checkCondition(n[1], ctx, map, false, false)
      mapR = checkCondition(n[2], ctx, map, false, false)
    case n[0].sym.magic:
    of mOr:
      result.map = ctx.union(mapL, mapR)
    of mAnd:
      result.map = checkCondition(n[1], ctx, map, false, false)
      result.map = checkCondition(n[2], ctx, result.map, false, false)
    of mEqRef:
      if n[2].kind == nkIntLit:
        if $n[2] == "true":
          result.map = checkCondition(n[1], ctx, map, false, false)
        elif $n[2] == "false":
          result.map = checkCondition(n[1], ctx, map, true, false)
      elif n[1].kind == nkIntLit:
        if $n[1] == "true":
          result.map = checkCondition(n[2], ctx, map, false, false)
        elif $n[1] == "false":
          result.map = checkCondition(n[2], ctx, map, true, false)

      if result.map.isNil:
        result.map = map
    else:
      result.map = map
  else:
    result.map = map
  result.nilability = Safe

proc checkIsNil(n, ctx, map; isElse: bool = false): Check =
  ## check isNil calls
  ## update the map depending on if it is not isNil or isNil
  result = Check(map: newNilMap(map))
  let value = n[1]
  result.map.store(ctx, ctx.index(n[1]), if not isElse: Nil else: Safe, TArg, n.info, n)

proc infix(ctx: NilCheckerContext, l: PNode, r: PNode, magic: TMagic): PNode =
  var name = case magic:
    of mEqRef: "=="
    of mAnd: "and"
    of mOr: "or"
    else: ""

  var cache = newIdentCache()
  var op = newSym(skVar, cache.getIdent(name), ctx.idgen, nil, r.info)

  op.magic = magic
  result = nkInfix.newTree(
    newSymNode(op, r.info),
    l,
    r)
  result.typ() = newType(tyBool, ctx.idgen, nil)

proc prefixNot(ctx: NilCheckerContext, node: PNode): PNode =
  var cache = newIdentCache()
  var op = newSym(skVar, cache.getIdent("not"), ctx.idgen, nil, node.info)

  op.magic = mNot
  result = nkPrefix.newTree(
    newSymNode(op, node.info),
    node)
  result.typ() = newType(tyBool, ctx.idgen, nil)

proc infixEq(ctx: NilCheckerContext, l: PNode, r: PNode): PNode =
  infix(ctx, l, r, mEqRef)

proc infixOr(ctx: NilCheckerContext, l: PNode, r: PNode): PNode =
  infix(ctx, l, r, mOr)

proc checkCase(n, ctx, map): Check =
  # case a:
  #   of b: c
  #   of b2: c2
  # is like
  # if a == b:
  #   c
  # elif a == b2:
  #   c2
  # also a == true is a , a == false is not a
  let base = n[0]
  result = Check(map: map.copyMap())
  result.nilability = Safe
  var a: PNode = nil
  for child in n:
    case child.kind:
    of nkOfBranch:
      if child.len < 2:
        # echo "case with of with < 2 ", n
        continue # TODO why does this happen
      let branchBase = child[0] # TODO a, b or a, b..c etc
      let code = child[^1]
      let test = infixEq(ctx, base, branchBase)
      if a.isNil:
        a = test
      else:
        a = infixOr(ctx, a, test)
      let conditionMap = checkCondition(test, ctx, map.copyMap(), false, false)
      let newCheck = checkBranch(code, ctx, conditionMap)
      result.map = ctx.union(result.map, newCheck.map)
      result.nilability = union(result.nilability, newCheck.nilability)
    of nkElifBranch:
      discard "TODO: maybe adapt to be similar to checkIf"
    of nkElse:
      let mapElse = checkCondition(prefixNot(ctx, a), ctx, map.copyMap(), false, false)
      let newCheck = checkBranch(child[0], ctx, mapElse)
      result.map = ctx.union(result.map, newCheck.map)
      result.nilability = union(result.nilability, newCheck.nilability)
    else:
      discard

# notes
# try:
#   a
#   b
# except:
#   c
# finally:
#   d
#
# if a doesnt raise, this is not an exit point:
#   so find what raises and update the map with that
# (a, b); c; d
# if nothing raises, except shouldn't happen
# .. might be a false positive tho, if canRaise is not conservative?
# so don't visit it
#
# nested nodes can raise as well: I hope nim returns canRaise for
# their parents
#
# a lot of stuff can raise
proc checkTry(n, ctx, map): Check =
  var newMap = map.copyMap()
  var currentMap = map
  # we don't analyze except if nothing canRaise in try
  var canRaise = false
  var hasFinally = false
  # var tryNodes: seq[PNode]
  # if n[0].kind == nkStmtList:
  #   tryNodes = toSeq(n[0])
  # else:
  #   tryNodes = @[n[0]]
  # for i, child in tryNodes:
  #   let (childNilability, childMap) = check(child, conf, currentMap)
  #   echo childMap
  #   currentMap = childMap
  #   # TODO what about nested
  #   if child.canRaise:
  #     newMap = union(newMap, childMap)
  #     canRaise = true
  #   else:
  #     newMap = childMap
  let tryCheck = check(n[0], ctx, currentMap)
  newMap = ctx.union(currentMap, tryCheck.map)
  canRaise = n[0].canRaise

  var afterTryMap = newMap
  for a, branch in n:
    if a > 0:
      case branch.kind:
      of nkFinally:
        newMap = ctx.union(afterTryMap, newMap)
        let childCheck = check(branch[0], ctx, newMap)
        newMap = ctx.union(newMap, childCheck.map)
        hasFinally = true
      of nkExceptBranch:
        if canRaise:
          let childCheck = check(branch[^1], ctx, newMap)
          newMap = ctx.union(newMap, childCheck.map)
      else:
        discard
  if not hasFinally:
    # we might have not hit the except branches
    newMap = ctx.union(afterTryMap, newMap)
  result = Check(nilability: Safe, map: newMap)

proc hasUnstructuredControlFlowJump(n: PNode): bool =
  ## if the node contains a direct stop
  ## as a continue/break/raise/return: then it means
  ## we should reverse some of the map in the code after the condition
  ## similar to else
  # echo "n ", n, " ", n.kind
  case n.kind:
  of nkStmtList:
    for child in n:
      if hasUnstructuredControlFlowJump(child):
        return true
  of nkReturnStmt, nkBreakStmt, nkContinueStmt, nkRaiseStmt:
    return true
  of nkIfStmt, nkIfExpr, nkElifExpr, nkElse:
    return false
  else:
    discard
  return false

proc reverse(value: Nilability): Nilability =
  case value:
  of Nil: Safe
  of MaybeNil: MaybeNil
  of Safe: Nil
  of Parent: Parent
  of Unreachable: Unreachable

proc reverse(kind: TransitionKind): TransitionKind =
  case kind:
  of TNil: TSafe
  of TSafe: TNil
  of TPotentialAlias: TPotentialAlias
  else:
    kind
    # raise newException(ValueError, "expected TNil or TSafe")

proc reverseDirect(map: NilMap): NilMap =
  # we create a new layer
  # reverse the values only in this layer:
  # because conditions should've stored their changes there
  # b: Safe (not b.isNil)
  # b: Parent Parent
  # b: Nil (b.isNil)

  # layer block
  # [ Parent ] [ Parent ]
  #   if -> if state
  #   layer -> reverse
  #   older older0 new
  #   older new
  #  [ b Nil ] [ Parent ]
  #  elif
  #  [ b Nil, c Nil] [ Parent ]
  #

  # if b.isNil:
  #   # [ b Safe]
  #   c = A() # Safe
  # elif not b.isNil:
  #   # [ b Safe ] + [b Nil] MaybeNil Unreachable
  #   # Unreachable defer can't deref b, it is unreachable
  #   discard
  # else:
  #   b


#  if



  # if: we just pass the map with a new layer for its block
  # elif: we just pass the original map but with a new layer is the reverse of the previous popped layer (?)
  # elif:
  # else: we just pass the original map but with a new layer which is initialized as the reverse of the
  #   top layer of else
  # else:
  #
  # [ b MaybeNil ] [b Parent] [b Parent] [b Safe] [b Nil] []
  # Safe
  # c == 1
  # b Parent
  # c == 2
  # b Parent
  # not b.isNil
  # b Safe
  # c == 3
  # b Nil
  # (else)
  # b Nil

  result = map.copyMap()
  for index, value in result.expressions:
    result.expressions[index] = reverse(value)
    if result.history[index].len > 0:
      result.history[index][^1].kind = reverse(result.history[index][^1].kind)
      result.history[index][^1].nilability = result.expressions[index]

proc checkCondition(n, ctx, map; reverse: bool, base: bool): NilMap =
  ## check conditions : used for if, some infix operators
  ##   isNil(a)
  ##   it returns a new map: you need to reverse all the direct elements for else

  # echo "condition ", n, " ", n.kind
  if n.kind == nkCall:
    result = newNilMap(map)
    for element in n:
      if element.kind == nkHiddenDeref and n[0].kind == nkSym and n[0].sym.magic == mIsNil:
        result = check(element[0], ctx, result).map
      else:
        result = check(element, ctx, result).map

    if n[0].kind == nkSym and n[0].sym.magic == mIsNil:
      # isNil(arg)
      var arg = n[1]
      while arg.kind == nkHiddenDeref:
        arg = arg[0]
      if arg.kind in {nkSym, nkDotExpr} or isConstBracket(arg):
        let a = ctx.index(arg)
        result.store(ctx, a, if not reverse: Nil else: Safe, if not reverse: TNil else: TSafe, n.info, arg)
      else:
        discard
    else:
      discard
  elif n.kind == nkPrefix and n[0].kind == nkSym and n[0].sym.magic == mNot:
    result = checkCondition(n[1], ctx, map, not reverse, false)
  elif n.kind == nkInfix:
    result = newNilMap(map)
    result = checkInfix(n, ctx, result).map
  else:
    result = check(n, ctx, map).map
    result = newNilMap(map)
  assert not result.isNil
  assert not result.parent.isNil

proc checkResult(n, ctx, map) =
  let resultNilability = map[resultExprIndex]
  case resultNilability:
  of Nil:
    message(ctx.config, n.info, warnStrictNotNil, "return value is nil")
  of MaybeNil:
    message(ctx.config, n.info, warnStrictNotNil, "return value might be nil")
  of Unreachable:
    message(ctx.config, n.info, warnStrictNotNil, "return value is unreachable")
  of Safe, Parent:
    discard

proc checkBranch(n: PNode, ctx: NilCheckerContext, map: NilMap): Check =
  result = check(n, ctx, map)


# Faith!

proc check(n: PNode, ctx: NilCheckerContext, map: NilMap): Check =
  assert not map.isNil

  # echo "check n ", n, " ", n.kind
  # echo "map ", namedMapDebugInfo(ctx, map)
  case n.kind:
  of nkSym:
    result = Check(nilability: map[ctx.index(n)], map: map)
  of nkCallKinds:
    if n.sons[0].kind == nkSym:
      let callSym = n.sons[0].sym
      case callSym.magic:
      of mAnd, mOr:
        result = checkInfix(n, ctx, map)
      of mIsNil:
        result = checkIsNil(n, ctx, map)
      else:
        result = checkCall(n, ctx, map)
    else:
      result = checkCall(n, ctx, map)
  of nkHiddenStdConv, nkHiddenSubConv, nkConv, nkExprColonExpr, nkExprEqExpr,
     nkCast:
    result = check(n.sons[1], ctx, map)
  of nkStmtList, nkStmtListExpr, nkChckRangeF, nkChckRange64, nkChckRange,
     nkBracket, nkCurly, nkPar, nkTupleConstr, nkClosure, nkObjConstr, nkElse:
    result = Check(map: map)
    if n.kind in {nkObjConstr, nkTupleConstr}:
      # TODO deeper nested elements?
      # A(field: B()) #
      # field: Safe ->
      var elements: seq[(PNode, Nilability)] = @[]
      for i, child in n:
        result = check(child, ctx, result.map)
        if i > 0:
          if child.kind == nkExprColonExpr:
            elements.add((child[0], result.nilability))
      result.elements = elements
      result.nilability = Safe
    else:
      for child in n:
        result = check(child, ctx, result.map)

  of nkDotExpr:
    result = checkDotExpr(n, ctx, map)
  of nkDerefExpr, nkHiddenDeref:
    result = checkDeref(n, ctx, map)
  of nkAddr, nkHiddenAddr:
    result = check(n.sons[0], ctx, map)
  of nkIfStmt, nkIfExpr:
    result = checkIf(n, ctx, map)
  of nkAsgn, nkFastAsgn, nkSinkAsgn:
    result = checkAsgn(n[0], n[1], ctx, map)
  of nkVarSection, nkLetSection:
    result = Check(map: map)
    for child in n:
      result = checkAsgn(child[0].skipPragmaExpr, child[2], ctx, result.map)
  of nkForStmt:
    result = checkFor(n, ctx, map)
  of nkCaseStmt:
    result = checkCase(n, ctx, map)
  of nkReturnStmt:
    result = checkReturn(n, ctx, map)
  of nkBracketExpr:
    result = checkBracketExpr(n, ctx, map)
  of nkTryStmt:
    result = checkTry(n, ctx, map)
  of nkWhileStmt:
    result = checkWhile(n, ctx, map)
  of nkNone..pred(nkSym), succ(nkSym)..nkNilLit, nkTypeSection, nkProcDef, nkConverterDef,
      nkMethodDef, nkIteratorDef, nkMacroDef, nkTemplateDef, nkLambda, nkDo,
      nkFuncDef, nkConstSection, nkConstDef, nkIncludeStmt, nkImportStmt,
      nkExportStmt, nkPragma, nkCommentStmt, nkBreakState,
      nkTypeOfExpr, nkMixinStmt, nkBindStmt:

    discard "don't follow this : same as varpartitions"
    result = Check(nilability: Nil, map: map)
  else:

    var elementMap = map.copyMap()
    var elementCheck = Check(map: elementMap)
    for element in n:
      elementCheck = check(element, ctx, elementCheck.map)

    result = Check(nilability: Nil, map: elementCheck.map)




proc typeNilability(typ: PType): Nilability =
  assert not typ.isNil
  # echo "typeNilability ", $typ.flags, " ", $typ.kind
  result = if tfNotNil in typ.flags:
    Safe
  elif typ.kind in {tyRef, tyCstring, tyPtr, tyPointer}:
    #
    # tyVar ? tyVarargs ? tySink ? tyLent ?
    # TODO spec? tests?
    MaybeNil
  else:
    Safe
  # echo "  result ", result

proc preVisitNode(ctx: NilCheckerContext, node: PNode, conf: ConfigRef) =
  # echo "visit node ", node
  if node.kind in {nkSym, nkDotExpr} or isConstBracket(node):
    let nodeSymbol = symbol(node)
    if not ctx.symbolIndices.hasKey(nodeSymbol):
      ctx.symbolIndices[nodeSymbol] = ctx.expressions.len
      ctx.expressions.add(node)
    if node.kind in {nkDotExpr, nkBracketExpr}:
      if node.kind == nkDotExpr and (not node.typ.isNil and node.typ.kind == tyRef and tfNotNil notin node.typ.flags) or
         node.kind == nkBracketExpr:
        let index = ctx.symbolIndices[nodeSymbol]
        var baseIndex = noExprIndex
        # deref usually?
        # ok, we hit another case
        var base = if node[0].kind notin {nkSym, nkIdent}: node[0][0] else: node[0]
        if base.kind != nkIdent:
          let baseSymbol = symbol(base)
          if not ctx.symbolIndices.hasKey(baseSymbol):
            baseIndex = ctx.expressions.len # next visit should add it
          else:
            baseIndex = ctx.symbolIndices[baseSymbol]
          if ctx.dependants.len <= baseIndex:
            ctx.dependants.setLen(baseIndex + 1.ExprIndex)
          ctx.dependants[baseIndex].incl(index.int)
  case node.kind:
  of nkSym, nkEmpty, nkNilLit, nkType, nkIdent, nkCharLit .. nkUInt64Lit, nkFloatLit .. nkFloat64Lit, nkStrLit .. nkTripleStrLit:
    discard
  of nkDotExpr:
    # visit only the base
    ctx.preVisitNode(node[0], conf)
  else:
    for element in node:
      ctx.preVisitNode(element, conf)

proc preVisit(ctx: NilCheckerContext, s: PSym, body: PNode, conf: ConfigRef) =
  ctx.symbolIndices = {resultId: resultExprIndex}.toTable()
  var cache = newIdentCache()
  ctx.expressions = SeqOfDistinct[ExprIndex, PNode](@[newIdentNode(cache.getIdent("result"), s.ast.info)])
  var emptySet: IntSet = initIntSet() # set[ExprIndex]
  ctx.dependants = SeqOfDistinct[ExprIndex, IntSet](@[emptySet])
  for i, arg in s.typ.n.sons:
    if i > 0:
      if arg.kind != nkSym:
        continue
      let argSymbol = symbol(arg)
      if not ctx.symbolIndices.hasKey(argSymbol):
        ctx.symbolIndices[argSymbol] = ctx.expressions.len
        ctx.expressions.add(arg)
  ctx.preVisitNode(body, conf)
  if ctx.dependants.len < ctx.expressions.len:
    ctx.dependants.setLen(ctx.expressions.len)
  # echo ctx.symbolIndices
  # echo ctx.expressions
  # echo ctx.dependants

proc checkNil*(s: PSym; body: PNode; conf: ConfigRef, idgen: IdGenerator) =
  let line = s.ast.info.line
  let fileIndex = s.ast.info.fileIndex.int
  var filename = conf.m.fileInfos[fileIndex].fullPath.string

  var context = NilCheckerContext(config: conf, idgen: idgen)
  context.preVisit(s, body, conf)
  var map = newNilMap(nil, context.symbolIndices.len)

  for i, child in s.typ.n.sons:
    if i > 0:
      if child.kind != nkSym:
        continue
      map.store(context, context.index(child), typeNilability(child.typ), TArg, child.info, child)

  map.store(context, resultExprIndex, if not s.typ.returnType.isNil and s.typ.returnType.kind == tyRef: Nil else: Safe, TResult, s.ast.info)

  # echo "checking ", s.name.s, " ", filename

  let res = check(body, context, map)
  var canCheck = resultExprIndex in res.map.history.low .. res.map.history.high
  if res.nilability == Safe and canCheck and res.map.history[resultExprIndex].len <= 1:
    res.map.store(context, resultExprIndex, Safe, TAssign, s.ast.info)
  else:
    if res.nilability == Safe:
      res.map.store(context, resultExprIndex, Safe, TAssign, s.ast.info)

  # TODO check for nilability result
  # (ANotNil, BNotNil) :
  # do we check on asgn nilability at all?

  if not s.typ.returnType.isNil and s.typ.returnType.kind == tyRef and tfNotNil in s.typ.returnType.flags:
    checkResult(s.ast, context, res.map)

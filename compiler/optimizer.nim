#
#
#           The Nim Compiler
#        (c) Copyright 2020 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Optimizer:
## - elide 'wasMoved(x); destroy(x)' pairs
## - recognize "all paths lead to 'wasMoved(x)'"

import
  ast, renderer, idents

from trees import exprStructuralEquivalent

import std/[strutils, intsets]

const
  nfMarkForDeletion = nfNone # faster than a lookup table

type
  BasicBlock = object
    wasMovedLocs: seq[PNode]
    kind: TNodeKind
    hasReturn, hasBreak: bool
    label: PSym # can be nil
    parent: ptr BasicBlock

  Con = object
    somethingTodo: bool
    inFinally: int

proc nestedBlock(parent: var BasicBlock; kind: TNodeKind): BasicBlock =
  BasicBlock(wasMovedLocs: @[], kind: kind, hasReturn: false, hasBreak: false,
    label: nil, parent: addr(parent))

proc breakStmt(b: var BasicBlock; n: PNode) =
  var it = addr(b)
  while it != nil:
    it.wasMovedLocs.setLen 0
    it.hasBreak = true

    if n.kind == nkSym:
      if it.label == n.sym: break
    else:
      # unnamed break leaves the block is nkWhileStmt or the like:
      if it.kind in {nkWhileStmt, nkBlockStmt, nkBlockExpr}: break

    it = it.parent

proc returnStmt(b: var BasicBlock) =
  b.hasReturn = true
  var it = addr(b)
  while it != nil:
    it.wasMovedLocs.setLen 0
    it = it.parent

proc mergeBasicBlockInfo(parent: var BasicBlock; this: BasicBlock) {.inline.} =
  if this.hasReturn:
    parent.wasMovedLocs.setLen 0
    parent.hasReturn = true

proc wasMovedTarget(matches: var IntSet; branch: seq[PNode]; moveTarget: PNode): bool =
  result = false
  for i in 0..<branch.len:
    if exprStructuralEquivalent(branch[i][1].skipHiddenAddr, moveTarget,
                                strictSymEquality = true):
      result = true
      matches.incl i

proc intersect(summary: var seq[PNode]; branch: seq[PNode]) =
  # keep all 'wasMoved(x)' calls in summary that are also in 'branch':
  var i = 0
  var matches = initIntSet()
  while i < summary.len:
    if wasMovedTarget(matches, branch, summary[i][1].skipHiddenAddr):
      inc i
    else:
      summary.del i
  for m in matches:
    summary.add branch[m]


proc invalidateWasMoved(c: var BasicBlock; x: PNode) =
  var i = 0
  while i < c.wasMovedLocs.len:
    if exprStructuralEquivalent(c.wasMovedLocs[i][1].skipHiddenAddr, x,
                                strictSymEquality = true):
      c.wasMovedLocs.del i
    else:
      inc i

proc wasMovedDestroyPair(c: var Con; b: var BasicBlock; d: PNode) =
  var i = 0
  while i < b.wasMovedLocs.len:
    if exprStructuralEquivalent(b.wasMovedLocs[i][1].skipHiddenAddr, d[1].skipHiddenAddr,
                                strictSymEquality = true):
      b.wasMovedLocs[i].flags.incl nfMarkForDeletion
      c.somethingTodo = true
      d.flags.incl nfMarkForDeletion
      b.wasMovedLocs.del i
    else:
      inc i

proc analyse(c: var Con; b: var BasicBlock; n: PNode) =
  case n.kind
  of nkCallKinds:
    var special = false
    var reverse = false
    if n[0].kind == nkSym:
      let s = n[0].sym
      let name = s.name.s.normalize
      if name == "=wasmoved":
        b.wasMovedLocs.add n
        special = true
      elif name == "=destroy":
        if c.inFinally > 0 and (b.hasReturn or b.hasBreak):
          discard "cannot optimize away the destructor"
        else:
          c.wasMovedDestroyPair b, n
        special = true
      elif name == "=sink":
        reverse = true

    if not special:
      if not reverse:
        for i in 0 ..< n.len:
          analyse(c, b, n[i])
      else:
        #[ Test destructor/tmatrix.test3:
        Prevent this from being elided. We should probably
        find a better solution...

            `=sink`(b, -
              let blitTmp = b;
              wasMoved(b);
              blitTmp + a)
            `=destroy`(b)

        ]#
        for i in countdown(n.len-1, 0):
          analyse(c, b, n[i])
      if canRaise(n[0]): returnStmt(b)

  of nkSym:
    # any usage of the location before destruction implies we
    # cannot elide the 'wasMoved(x)':
    b.invalidateWasMoved n

  of nkNone..pred(nkSym), succ(nkSym)..nkNilLit, nkTypeSection, nkProcDef, nkConverterDef,
      nkMethodDef, nkIteratorDef, nkMacroDef, nkTemplateDef, nkLambda, nkDo,
      nkFuncDef, nkConstSection, nkConstDef, nkIncludeStmt, nkImportStmt,
      nkExportStmt, nkPragma, nkCommentStmt, nkBreakState,
      nkTypeOfExpr, nkMixinStmt, nkBindStmt:
    discard "do not follow the construct"

  of nkAsgn, nkFastAsgn, nkSinkAsgn:
    # reverse order, see remark for `=sink`:
    analyse(c, b, n[1])
    analyse(c, b, n[0])

  of nkIfStmt, nkIfExpr:
    let isExhaustive = n[^1].kind in {nkElse, nkElseExpr}
    var wasMovedSet: seq[PNode] = @[]

    for i in 0 ..< n.len:
      var branch = nestedBlock(b, n[i].kind)

      analyse(c, branch, n[i])
      mergeBasicBlockInfo(b, branch)
      if isExhaustive:
        if i == 0:
          wasMovedSet = move(branch.wasMovedLocs)
        else:
          wasMovedSet.intersect(branch.wasMovedLocs)
    for i in 0..<wasMovedSet.len:
      b.wasMovedLocs.add wasMovedSet[i]

  of nkCaseStmt:
    let isExhaustive = skipTypes(n[0].typ,
      abstractVarRange-{tyTypeDesc}).kind notin {tyFloat..tyFloat128, tyString, tyCstring} or
      n[^1].kind == nkElse

    analyse(c, b, n[0])

    var wasMovedSet: seq[PNode] = @[]

    for i in 1 ..< n.len:
      var branch = nestedBlock(b, n[i].kind)

      analyse(c, branch, n[i])
      mergeBasicBlockInfo(b, branch)
      if isExhaustive:
        if i == 1:
          wasMovedSet = move(branch.wasMovedLocs)
        else:
          wasMovedSet.intersect(branch.wasMovedLocs)
    for i in 0..<wasMovedSet.len:
      b.wasMovedLocs.add wasMovedSet[i]

  of nkTryStmt:
    for i in 0 ..< n.len:
      var tryBody = nestedBlock(b, nkTryStmt)

      analyse(c, tryBody, n[i])
      mergeBasicBlockInfo(b, tryBody)

  of nkWhileStmt:
    analyse(c, b, n[0])
    var loopBody = nestedBlock(b, nkWhileStmt)
    analyse(c, loopBody, n[1])
    mergeBasicBlockInfo(b, loopBody)

  of nkBlockStmt, nkBlockExpr:
    var blockBody = nestedBlock(b, n.kind)
    if n[0].kind == nkSym:
      blockBody.label = n[0].sym
    analyse(c, blockBody, n[1])
    mergeBasicBlockInfo(b, blockBody)

  of nkBreakStmt:
    breakStmt(b, n[0])

  of nkReturnStmt, nkRaiseStmt:
    for child in n: analyse(c, b, child)
    returnStmt(b)

  of nkFinally:
    inc c.inFinally
    for child in n: analyse(c, b, child)
    dec c.inFinally

  else:
    for child in n: analyse(c, b, child)

proc opt(c: Con; n, parent: PNode; parentPos: int) =
  template recurse() =
    let x = shallowCopy(n)
    for i in 0 ..< n.len:
      opt(c, n[i], x, i)
    parent[parentPos] = x

  case n.kind
  of nkCallKinds:
    if nfMarkForDeletion in n.flags:
      parent[parentPos] = newNodeI(nkEmpty, n.info)
    else:
      recurse()

  of nkNone..nkNilLit, nkTypeSection, nkProcDef, nkConverterDef,
      nkMethodDef, nkIteratorDef, nkMacroDef, nkTemplateDef, nkLambda, nkDo,
      nkFuncDef, nkConstSection, nkConstDef, nkIncludeStmt, nkImportStmt,
      nkExportStmt, nkPragma, nkCommentStmt, nkBreakState, nkTypeOfExpr,
      nkMixinStmt, nkBindStmt:
    parent[parentPos] = n

  else:
    recurse()


proc optimize*(n: PNode): PNode =
  # optimize away simple 'wasMoved(x); destroy(x)' pairs.
  #[ Unfortunately this optimization is only really safe when no exceptions
     are possible, see for example:

  proc main(inp: string; cond: bool) =
    if cond:
      try:
        var s = ["hi", inp & "more"]
        for i in 0..4:
          use s
        consume(s)
        wasMoved(s)
      finally:
        destroy(s)

    Now assume 'use' raises, then we shouldn't do the 'wasMoved(s)'
  ]#
  var c: Con = Con()
  var b: BasicBlock = default(BasicBlock)
  analyse(c, b, n)
  if c.somethingTodo:
    result = shallowCopy(n)
    for i in 0 ..< n.safeLen:
      opt(c, n[i], result, i)
  else:
    result = n

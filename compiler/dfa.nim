#
#
#           The Nim Compiler
#        (c) Copyright 2017 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Data flow analysis for Nim.
## We transform the AST into a linear list of instructions first to
## make this easier to handle: There are only 3 different branching
## instructions: 'goto X' is an unconditional goto, 'fork X'
## is a conditional goto (either the next instruction or 'X' can be
## taken), 'loop X' is the only jump that jumps back.
##
## Exhaustive case statements are translated
## so that the last branch is transformed into an 'else' branch.
## ``return`` and ``break`` are all covered by 'goto'.
##
## The data structures and algorithms used here are inspired by
## "A Graph–Free Approach to Data–Flow Analysis" by Markus Mohnen.
## https://link.springer.com/content/pdf/10.1007/3-540-45937-5_6.pdf

import ast, lineinfos, renderer, aliasanalysis
import std/private/asciitables
import std/intsets

when defined(nimPreviewSlimSystem):
  import std/assertions

type
  InstrKind* = enum
    goto, loop, fork, def, use
  Instr* = object
    case kind*: InstrKind
    of goto, fork, loop: dest*: int
    of def, use:
      n*: PNode # contains the def/use location.

  ControlFlowGraph* = seq[Instr]

  TPosition = distinct int

  TBlock = object
    case isTryBlock: bool
    of false:
      label: PSym
      breakFixups: seq[(TPosition, seq[PNode])] # Contains the gotos for the breaks along with their pending finales
    of true:
      finale: PNode
      raiseFixups: seq[TPosition] # Contains the gotos for the raises

  Con = object
    code: ControlFlowGraph
    inTryStmt, interestingInstructions: int
    blocks: seq[TBlock]
    owner: PSym
    root: PSym

proc codeListing(c: ControlFlowGraph, start = 0; last = -1): string =
  # for debugging purposes
  # first iteration: compute all necessary labels:
  result = ""
  var jumpTargets = initIntSet()
  let last = if last < 0: c.len-1 else: min(last, c.len-1)
  for i in start..last:
    if c[i].kind in {goto, fork, loop}:
      jumpTargets.incl(i+c[i].dest)
  var i = start
  while i <= last:
    if i in jumpTargets: result.add("L" & $i & ":\n")
    result.add "\t"
    result.add ($i & " " & $c[i].kind)
    result.add "\t"
    case c[i].kind
    of def, use:
      result.add renderTree(c[i].n)
      result.add("\t#")
      result.add($c[i].n.info.line)
      result.add("\n")
    of goto, fork, loop:
      result.add "L"
      result.addInt c[i].dest+i
    inc i
  if i in jumpTargets: result.add("L" & $i & ": End\n")

proc echoCfg*(c: ControlFlowGraph; start = 0; last = -1) {.deprecated.} =
  ## echos the ControlFlowGraph for debugging purposes.
  echo codeListing(c, start, last).alignTable

proc forkI(c: var Con): TPosition =
  result = TPosition(c.code.len)
  c.code.add Instr(kind: fork, dest: 0)

proc gotoI(c: var Con): TPosition =
  result = TPosition(c.code.len)
  c.code.add Instr(kind: goto, dest: 0)

proc genLabel(c: Con): TPosition = TPosition(c.code.len)

template checkedDistance(dist): int =
  doAssert low(int) div 2 + 1 < dist and dist < high(int) div 2
  dist

proc jmpBack(c: var Con, p = TPosition(0)) =
  c.code.add Instr(kind: loop, dest: checkedDistance(p.int - c.code.len))

proc patch(c: var Con, p: TPosition) =
  # patch with current index
  c.code[p.int].dest = checkedDistance(c.code.len - p.int)

proc gen(c: var Con; n: PNode)

proc popBlock(c: var Con; oldLen: int) =
  var exits: seq[TPosition] = @[]
  exits.add c.gotoI()
  for f in c.blocks[oldLen].breakFixups:
    c.patch(f[0])
    for finale in f[1]:
      c.gen(finale)
    exits.add c.gotoI()
  for e in exits:
    c.patch e
  c.blocks.setLen(oldLen)

template withBlock(labl: PSym; body: untyped) =
  let oldLen = c.blocks.len
  c.blocks.add TBlock(isTryBlock: false, label: labl)
  body
  popBlock(c, oldLen)

template forkT(body) =
  let lab1 = c.forkI()
  body
  c.patch(lab1)

proc genWhile(c: var Con; n: PNode) =
  # lab1:
  #   cond, tmp
  #   fork tmp, lab2
  #   body
  #   jmp lab1
  # lab2:
  let lab1 = c.genLabel
  withBlock(nil):
    if isTrue(n[0]):
      c.gen(n[1])
      c.jmpBack(lab1)
    else:
      c.gen(n[0])
      forkT:
        c.gen(n[1])
        c.jmpBack(lab1)

proc genIf(c: var Con, n: PNode) =
  #[

  if cond:
    A
  elif condB:
    B
  elif condC:
    C
  else:
    D

  cond
  fork lab1
  A
  goto Lend
  lab1:
    condB
    fork lab2
    B
    goto Lend2
  lab2:
    condC
    fork L3
    C
    goto Lend3
  L3:
    D
  ]#
  var endings: seq[TPosition] = @[]
  let oldInteresting = c.interestingInstructions
  let oldLen = c.code.len

  for i in 0..<n.len:
    let it = n[i]
    c.gen(it[0])
    if it.len == 2:
      forkT:
        c.gen(it.lastSon)
        endings.add c.gotoI()

  if oldInteresting == c.interestingInstructions:
    setLen c.code, oldLen
  else:
    for i in countdown(endings.high, 0):
      c.patch(endings[i])

proc genAndOr(c: var Con; n: PNode) =
  #   asgn dest, a
  #   fork lab1
  #   asgn dest, b
  # lab1:
  c.gen(n[1])
  forkT:
    c.gen(n[2])

proc genCase(c: var Con; n: PNode) =
  #  if (!expr1) goto lab1;
  #    thenPart
  #    goto LEnd
  #  lab1:
  #  if (!expr2) goto lab2;
  #    thenPart2
  #    goto LEnd
  #  lab2:
  #    elsePart
  #  Lend:
  let isExhaustive = skipTypes(n[0].typ,
    abstractVarRange-{tyTypeDesc}).kind notin {tyFloat..tyFloat128, tyString, tyCstring}

  var endings: seq[TPosition] = @[]
  c.gen(n[0])
  let oldInteresting = c.interestingInstructions
  let oldLen = c.code.len
  for i in 1..<n.len:
    let it = n[i]
    if it.len == 1 or (i == n.len-1 and isExhaustive):
      # treat the last branch as 'else' if this is an exhaustive case statement.
      c.gen(it.lastSon)
    else:
      forkT:
        c.gen(it.lastSon)
        endings.add c.gotoI()

  if oldInteresting == c.interestingInstructions:
    setLen c.code, oldLen
  else:
    for i in countdown(endings.high, 0):
      c.patch(endings[i])

proc genBlock(c: var Con; n: PNode) =
  withBlock(n[0].sym):
    c.gen(n[1])

proc genBreakOrRaiseAux(c: var Con, i: int, n: PNode) =
  let lab1 = c.gotoI()
  if c.blocks[i].isTryBlock:
    c.blocks[i].raiseFixups.add lab1
  else:
    var trailingFinales: seq[PNode] = @[]
    if c.inTryStmt > 0:
      # Ok, we are in a try, lets see which (if any) try's we break out from:
      for b in countdown(c.blocks.high, i):
        if c.blocks[b].isTryBlock:
          trailingFinales.add c.blocks[b].finale

    c.blocks[i].breakFixups.add (lab1, trailingFinales)

proc genBreak(c: var Con; n: PNode) =
  inc c.interestingInstructions
  if n[0].kind == nkSym:
    for i in countdown(c.blocks.high, 0):
      if not c.blocks[i].isTryBlock and c.blocks[i].label == n[0].sym:
        genBreakOrRaiseAux(c, i, n)
        return
    #globalError(n.info, "VM problem: cannot find 'break' target")
  else:
    for i in countdown(c.blocks.high, 0):
      if not c.blocks[i].isTryBlock:
        genBreakOrRaiseAux(c, i, n)
        return

proc genTry(c: var Con; n: PNode) =
  var endings: seq[TPosition] = @[]

  let oldLen = c.blocks.len
  c.blocks.add TBlock(isTryBlock: true, finale: if n[^1].kind == nkFinally: n[^1] else: newNode(nkEmpty))

  inc c.inTryStmt
  c.gen(n[0])
  dec c.inTryStmt

  for f in c.blocks[oldLen].raiseFixups:
    c.patch(f)

  c.blocks.setLen oldLen

  for i in 1..<n.len:
    let it = n[i]
    if it.kind != nkFinally:
      forkT:
        c.gen(it.lastSon)
        endings.add c.gotoI()
  for i in countdown(endings.high, 0):
    c.patch(endings[i])

  let fin = lastSon(n)
  if fin.kind == nkFinally:
    c.gen(fin[0])

template genNoReturn(c: var Con) =
  # leave the graph
  c.code.add Instr(kind: goto, dest: high(int) - c.code.len)

proc genRaise(c: var Con; n: PNode) =
  inc c.interestingInstructions
  gen(c, n[0])
  if c.inTryStmt > 0:
    for i in countdown(c.blocks.high, 0):
      if c.blocks[i].isTryBlock:
        genBreakOrRaiseAux(c, i, n)
        return
    assert false # Unreachable
  else:
    genNoReturn(c)

proc genImplicitReturn(c: var Con) =
  if c.owner.kind in {skProc, skFunc, skMethod, skIterator, skConverter} and resultPos < c.owner.ast.len:
    gen(c, c.owner.ast[resultPos])

proc genReturn(c: var Con; n: PNode) =
  inc c.interestingInstructions
  if n[0].kind != nkEmpty:
    gen(c, n[0])
  else:
    genImplicitReturn(c)
  genBreakOrRaiseAux(c, 0, n)

const
  InterestingSyms = {skVar, skResult, skLet, skParam, skForVar, skTemp}

proc skipTrivials(c: var Con, n: PNode): PNode =
  result = n
  while true:
    case result.kind
    of PathKinds0 - {nkBracketExpr}:
      result = result[0]
    of nkBracketExpr:
      gen(c, result[1])
      result = result[0]
    of PathKinds1:
      result = result[1]
    else: break

proc genUse(c: var Con; orig: PNode) =
  let n = c.skipTrivials(orig)

  if n.kind == nkSym:
    if n.sym.kind in InterestingSyms and n.sym == c.root:
      c.code.add Instr(kind: use, n: orig)
      inc c.interestingInstructions
  else:
    gen(c, n)

proc genDef(c: var Con; orig: PNode) =
  let n = c.skipTrivials(orig)

  if n.kind == nkSym and n.sym.kind in InterestingSyms:
    if n.sym == c.root:
      c.code.add Instr(kind: def, n: orig)
      inc c.interestingInstructions

proc genCall(c: var Con; n: PNode) =
  gen(c, n[0])
  var t = n[0].typ
  if t != nil: t = t.skipTypes(abstractInst)
  for i in 1..<n.len:
    gen(c, n[i])
    if t != nil and i < t.signatureLen and isOutParam(t[i]):
      # Pass by 'out' is a 'must def'. Good enough for a move optimizer.
      genDef(c, n[i])
  # every call can potentially raise:
  if c.inTryStmt > 0 and canRaiseConservative(n[0]):
    inc c.interestingInstructions
    # we generate the instruction sequence:
    # fork lab1
    # goto exceptionHandler (except or finally)
    # lab1:
    forkT:
      for i in countdown(c.blocks.high, 0):
        if c.blocks[i].isTryBlock:
          genBreakOrRaiseAux(c, i, n)
          break

proc genMagic(c: var Con; n: PNode; m: TMagic) =
  case m
  of mAnd, mOr: c.genAndOr(n)
  of mNew, mNewFinalize:
    genDef(c, n[1])
    for i in 2..<n.len: gen(c, n[i])
  else:
    genCall(c, n)

proc genVarSection(c: var Con; n: PNode) =
  for a in n:
    if a.kind == nkCommentStmt:
      discard
    elif a.kind == nkVarTuple:
      gen(c, a.lastSon)
      for i in 0..<a.len-2: genDef(c, a[i])
    else:
      gen(c, a.lastSon)
      if a.lastSon.kind != nkEmpty:
        genDef(c, a[0])

proc gen(c: var Con; n: PNode) =
  case n.kind
  of nkSym: genUse(c, n)
  of nkCallKinds:
    if n[0].kind == nkSym:
      let s = n[0].sym
      if s.magic != mNone:
        genMagic(c, n, s.magic)
      else:
        genCall(c, n)
      if sfNoReturn in n[0].sym.flags:
        genNoReturn(c)
    else:
      genCall(c, n)
  of nkCharLit..nkNilLit: discard
  of nkAsgn, nkFastAsgn, nkSinkAsgn:
    gen(c, n[1])

    if n[0].kind in PathKinds0:
      let a = c.skipTrivials(n[0])
      if a.kind in nkCallKinds:
        gen(c, a)

    # watch out: 'obj[i].f2 = value' sets 'f2' but
    # "uses" 'i'. But we are only talking about builtin array indexing so
    # it doesn't matter and 'x = 34' is NOT a usage of 'x'.
    genDef(c, n[0])
  of PathKinds0 - {nkObjDownConv, nkObjUpConv}:
    genUse(c, n)
  of nkIfStmt, nkIfExpr: genIf(c, n)
  of nkWhenStmt:
    # This is "when nimvm" node. Chose the first branch.
    gen(c, n[0][1])
  of nkCaseStmt: genCase(c, n)
  of nkWhileStmt: genWhile(c, n)
  of nkBlockExpr, nkBlockStmt: genBlock(c, n)
  of nkReturnStmt: genReturn(c, n)
  of nkRaiseStmt: genRaise(c, n)
  of nkBreakStmt: genBreak(c, n)
  of nkTryStmt, nkHiddenTryStmt: genTry(c, n)
  of nkStmtList, nkStmtListExpr, nkChckRangeF, nkChckRange64, nkChckRange,
     nkBracket, nkCurly, nkPar, nkTupleConstr, nkClosure, nkObjConstr, nkYieldStmt:
    for x in n: gen(c, x)
  of nkPragmaBlock: gen(c, n.lastSon)
  of nkDiscardStmt, nkObjDownConv, nkObjUpConv, nkStringToCString, nkCStringToString:
    gen(c, n[0])
  of nkConv, nkExprColonExpr, nkExprEqExpr, nkCast, PathKinds1:
    gen(c, n[1])
  of nkVarSection, nkLetSection: genVarSection(c, n)
  of nkDefer: raiseAssert "dfa construction pass requires the elimination of 'defer'"
  else: discard

when false:
  proc optimizeJumps(c: var ControlFlowGraph) =
    for i in 0..<c.len:
      case c[i].kind
      of goto, fork:
        var pc = i + c[i].dest
        if pc < c.len and c[pc].kind == goto:
          while pc < c.len and c[pc].kind == goto:
            let newPc = pc + c[pc].dest
            if newPc > pc:
              pc = newPc
            else:
              break
          c[i].dest = pc - i
      of loop, def, use: discard

proc constructCfg*(s: PSym; body: PNode; root: PSym): ControlFlowGraph =
  ## constructs a control flow graph for ``body``.
  var c = Con(code: @[], blocks: @[], owner: s, root: root)
  withBlock(s):
    gen(c, body)
    if root.kind == skResult:
      genImplicitReturn(c)
  when defined(gcArc) or defined(gcOrc) or defined(gcAtomicArc):
    result = c.code # will move
  else:
    shallowCopy(result, c.code)
  when false:
    optimizeJumps result

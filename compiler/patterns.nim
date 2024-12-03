#
#
#           The Nim Compiler
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements the pattern matching features for term rewriting
## macro support.

import
  ast, types, semdata, sigmatch, idents, aliases, parampatterns, trees

when defined(nimPreviewSlimSystem):
  import std/assertions

type
  TPatternContext = object
    owner: PSym
    mapping: seq[PNode]  # maps formal parameters to nodes
    formals: int
    c: PContext
    subMatch: bool       # subnode matches are special
    mappingIsFull: bool
  PPatternContext = var TPatternContext

proc getLazy(c: PPatternContext, sym: PSym): PNode =
  if c.mappingIsFull:
    result = c.mapping[sym.position]
  else:
    result = nil

proc putLazy(c: PPatternContext, sym: PSym, n: PNode) =
  if not c.mappingIsFull:
    newSeq(c.mapping, c.formals)
    c.mappingIsFull = true
  c.mapping[sym.position] = n

proc matches(c: PPatternContext, p, n: PNode): bool

proc canonKind(n: PNode): TNodeKind =
  ## nodekind canonicalization for pattern matching
  result = n.kind
  case result
  of nkCallKinds: result = nkCall
  of nkStrLit..nkTripleStrLit: result = nkStrLit
  of nkFastAsgn, nkSinkAsgn: result = nkAsgn
  else: discard

proc sameKinds(a, b: PNode): bool {.inline.} =
  result = a.kind == b.kind or a.canonKind == b.canonKind

proc sameTrees*(a, b: PNode): bool =
  if sameKinds(a, b):
    case a.kind
    of nkSym: result = a.sym == b.sym
    of nkIdent: result = a.ident.id == b.ident.id
    of nkCharLit..nkInt64Lit: result = a.intVal == b.intVal
    of nkFloatLit..nkFloat64Lit: result = a.floatVal == b.floatVal
    of nkStrLit..nkTripleStrLit: result = a.strVal == b.strVal
    of nkEmpty, nkNilLit: result = true
    of nkType: result = sameTypeOrNil(a.typ, b.typ)
    else:
      if a.len == b.len:
        for i in 0..<a.len:
          if not sameTrees(a[i], b[i]): return
        result = true
      else:
        result = false
  else:
    result = false

proc inSymChoice(sc, x: PNode): bool =
  if sc.kind == nkClosedSymChoice:
    result = false
    for i in 0..<sc.len:
      if sc[i].sym == x.sym: return true
  elif sc.kind == nkOpenSymChoice:
    # same name suffices for open sym choices!
    result = sc[0].sym.name.id == x.sym.name.id
  else:
    result = false

proc checkTypes(c: PPatternContext, p: PSym, n: PNode): bool =
  # check param constraints first here as this is quite optimized:
  if p.constraint != nil:
    result = matchNodeKinds(p.constraint, n)
    if not result: return
  if isNil(n.typ):
    result = p.typ.kind in {tyVoid, tyTyped}
  else:
    result = sigmatch.argtypeMatches(c.c, p.typ, n.typ, fromHlo = true)

proc isPatternParam(c: PPatternContext, p: PNode): bool {.inline.} =
  result = p.kind == nkSym and p.sym.kind == skParam and p.sym.owner == c.owner

proc matchChoice(c: PPatternContext, p, n: PNode): bool =
  result = false
  for i in 1..<p.len:
    if matches(c, p[i], n): return true

proc bindOrCheck(c: PPatternContext, param: PSym, n: PNode): bool =
  var pp = getLazy(c, param)
  if pp != nil:
    # check if we got the same pattern (already unified):
    result = sameTrees(pp, n) #matches(c, pp, n)
  elif n.kind == nkArgList or checkTypes(c, param, n):
    putLazy(c, param, n)
    result = true
  else:
    result = false

proc gather(c: PPatternContext, param: PSym, n: PNode) =
  var pp = getLazy(c, param)
  if pp != nil and pp.kind == nkArgList:
    pp.add(n)
  else:
    pp = newNodeI(nkArgList, n.info, 1)
    pp[0] = n
    putLazy(c, param, pp)

proc matchNested(c: PPatternContext, p, n: PNode, rpn: bool): bool =
  # match ``op * param`` or ``op *| param``
  proc matchStarAux(c: PPatternContext, op, n, arglist: PNode,
                    rpn: bool): bool =
    result = true
    if n.kind in nkCallKinds and matches(c, op[1], n[0]):
      for i in 1..<n.len:
        if not matchStarAux(c, op, n[i], arglist, rpn): return false
      if rpn: arglist.add(n[0])
    elif n.kind == nkHiddenStdConv and n[1].kind == nkBracket:
      let n = n[1]
      for i in 0..<n.len:
        if not matchStarAux(c, op, n[i], arglist, rpn): return false
    elif checkTypes(c, p[2].sym, n):
      arglist.add(n)
    else:
      result = false

  if n.kind notin nkCallKinds: return false
  if matches(c, p[1], n[0]):
    var arglist = newNodeI(nkArgList, n.info)
    if matchStarAux(c, p, n, arglist, rpn):
      result = bindOrCheck(c, p[2].sym, arglist)
    else:
      result = false
  else:
    result = false

proc matches(c: PPatternContext, p, n: PNode): bool =
  let n = skipHidden(n)
  if nfNoRewrite in n.flags:
    result = false
  elif isPatternParam(c, p):
    result = bindOrCheck(c, p.sym, n)
  elif n.kind == nkSym and p.kind == nkIdent:
    result = p.ident.id == n.sym.name.id
  elif n.kind == nkSym and inSymChoice(p, n):
    result = true
  elif n.kind == nkSym and n.sym.kind == skConst:
    # try both:
    if p.kind == nkSym: result = p.sym == n.sym
    elif matches(c, p, n.sym.astdef): result = true
    else: result = false
  elif p.kind == nkPattern:
    # pattern operators: | *
    let opr = p[0].ident.s
    case opr
    of "|": result = matchChoice(c, p, n)
    of "*": result = matchNested(c, p, n, rpn=false)
    of "**": result = matchNested(c, p, n, rpn=true)
    of "~": result = not matches(c, p[1], n)
    else:
      result = false
      doAssert(false, "invalid pattern")
    # template {add(a, `&` * b)}(a: string{noalias}, b: varargs[string]) =
    #   a.add(b)
  elif p.kind == nkCurlyExpr:
    if p[1].kind == nkPrefix:
      if matches(c, p[0], n):
        gather(c, p[1][1].sym, n)
        result = true
      else:
        result = false
    else:
      assert isPatternParam(c, p[1])
      if matches(c, p[0], n):
        result = bindOrCheck(c, p[1].sym, n)
      else:
        result = false
  elif sameKinds(p, n):
    case p.kind
    of nkSym: result = p.sym == n.sym
    of nkIdent: result = p.ident.id == n.ident.id
    of nkCharLit..nkInt64Lit: result = p.intVal == n.intVal
    of nkFloatLit..nkFloat64Lit: result = p.floatVal == n.floatVal
    of nkStrLit..nkTripleStrLit: result = p.strVal == n.strVal
    of nkEmpty, nkNilLit, nkType:
      result = true
    else:
      # special rule for p(X) ~ f(...); this also works for stuff like
      # partial case statements, etc! - Not really ... :-/
      result = false
      let v = lastSon(p)
      if isPatternParam(c, v) and v.sym.typ.kind == tyVarargs:
        var arglist: PNode
        if p.len <= n.len:
          for i in 0..<p.len - 1:
            if not matches(c, p[i], n[i]): return
          if p.len == n.len and lastSon(n).kind == nkHiddenStdConv and
              lastSon(n)[1].kind == nkBracket:
            # unpack varargs:
            let n = lastSon(n)[1]
            arglist = newNodeI(nkArgList, n.info, n.len)
            for i in 0..<n.len: arglist[i] = n[i]
          else:
            arglist = newNodeI(nkArgList, n.info, n.len - p.len + 1)
            # f(1, 2, 3)
            # p(X)
            for i in 0..n.len - p.len:
              arglist[i] = n[i + p.len - 1]
          return bindOrCheck(c, v.sym, arglist)
        elif p.len-1 == n.len:
          for i in 0..<p.len - 1:
            if not matches(c, p[i], n[i]): return
          arglist = newNodeI(nkArgList, n.info)
          return bindOrCheck(c, v.sym, arglist)
      if p.len == n.len:
        for i in 0..<p.len:
          if not matches(c, p[i], n[i]): return
        result = true
  else:
    result = false

proc matchStmtList(c: PPatternContext, p, n: PNode): PNode =
  proc matchRange(c: PPatternContext, p, n: PNode, i: int): bool =
    for j in 0..<p.len:
      if not matches(c, p[j], n[i+j]):
        # we need to undo any bindings:
        c.mapping = @[]
        c.mappingIsFull = false
        return false
    result = true

  if p.kind == nkStmtList and n.kind == p.kind and p.len < n.len:
    result = nil
    let n = flattenStmts(n)
    # no need to flatten 'p' here as that has already been done
    for i in 0..n.len - p.len:
      if matchRange(c, p, n, i):
        c.subMatch = true
        result = newNodeI(nkStmtList, n.info, 3)
        result[0] = extractRange(nkStmtList, n, 0, i-1)
        result[1] = extractRange(nkStmtList, n, i, i+p.len-1)
        result[2] = extractRange(nkStmtList, n, i+p.len, n.len-1)
        break
  elif matches(c, p, n):
    result = n
  else:
    result = nil

proc aliasAnalysisRequested(params: PNode): bool =
  result = false
  if params.len >= 2:
    for i in 1..<params.len:
      let param = params[i].sym
      if whichAlias(param) != aqNone: return true

proc addToArgList(result, n: PNode) =
  if n.typ != nil and n.typ.kind != tyTyped:
    if n.kind != nkArgList: result.add(n)
    else:
      for i in 0..<n.len: result.add(n[i])

proc applyRule*(c: PContext, s: PSym, n: PNode): PNode =
  ## returns a tree to semcheck if the rule triggered; nil otherwise
  var ctx = TPatternContext(owner: s, c: c, formals: s.typ.paramsLen)
  var m = matchStmtList(ctx, s.ast[patternPos], n)
  if isNil(m): return nil
  # each parameter should have been bound; we simply setup a call and
  # let semantic checking deal with the rest :-)
  result = newNodeI(nkCall, n.info)
  result.add(newSymNode(s, n.info))
  let params = s.typ.n
  let requiresAA = aliasAnalysisRequested(params)
  var args: PNode =
    if requiresAA:
      newNodeI(nkArgList, n.info)
    else:
      nil
  for i in 1..<params.len:
    let param = params[i].sym
    let x = getLazy(ctx, param)
    # couldn't bind parameter:
    if isNil(x): return nil
    result.add(x)
    if requiresAA: addToArgList(args, x)
  # perform alias analysis here:
  if requiresAA:
    for i in 1..<params.len:
      var rs = result[i]
      let param = params[i].sym
      case whichAlias(param)
      of aqNone: discard
      of aqShouldAlias:
        # it suffices that it aliases for sure with *some* other param:
        var ok = false
        for arg in items(args):
          if arg != rs and aliases.isPartOf(rs, arg) == arYes:
            ok = true
            break
        # constraint not fulfilled:
        if not ok: return nil
      of aqNoAlias:
        # it MUST not alias with any other param:
        var ok = true
        for arg in items(args):
          if arg != rs and aliases.isPartOf(rs, arg) != arNo:
            ok = false
            break
        # constraint not fulfilled:
        if not ok: return nil

  markUsed(c, n.info, s)
  if ctx.subMatch:
    assert m.len == 3
    m[1] = result
    result = m

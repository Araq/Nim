
import
  ast, idents, renderer,
  msgs, modulegraphs, syntaxes, options, modulepaths,
  lineinfos

import std/[algorithm, strutils, intsets]

when defined(nimPreviewSlimSystem):
  import std/assertions

when defined(nimDebugReorder):
  import std/tables

type
  DepN = ref object
    pnode: PNode
    id, idx, lowLink: int
    onStack: bool
    kids: seq[DepN]
    hAQ, hIS, hB, hCmd: int
    when defined(nimDebugReorder):
      expls: seq[string]
  DepG = seq[DepN]

when defined(nimDebugReorder):
  var idNames = newTable[int, string]()

proc newDepN(id: int, pnode: PNode): DepN =
  result = DepN(id: id, pnode: pnode, idx: -1,
                lowLink: -1, onStack: false,
                kids: @[], hAQ: -1, hIS: -1,
                hB: -1, hCmd: -1
  )
  when defined(nimDebugReorder):
    result.expls = @[]

proc accQuoted(cache: IdentCache; n: PNode): PIdent =
  var id = ""
  for i in 0..<n.len:
    let ident = n[i].getPIdent
    if ident != nil: id.add(ident.s)
  result = getIdent(cache, id)

proc addDecl(cache: IdentCache; n: PNode; declares: var IntSet) =
  case n.kind
  of nkPostfix: addDecl(cache, n[1], declares)
  of nkPragmaExpr: addDecl(cache, n[0], declares)
  of nkIdent:
    declares.incl n.ident.id
    when defined(nimDebugReorder):
      idNames[n.ident.id] = n.ident.s
  of nkSym:
    declares.incl n.sym.name.id
    when defined(nimDebugReorder):
      idNames[n.sym.name.id] = n.sym.name.s
  of nkAccQuoted:
    let a = accQuoted(cache, n)
    declares.incl a.id
    when defined(nimDebugReorder):
      idNames[a.id] = a.s
  of nkEnumFieldDef:
    addDecl(cache, n[0], declares)
  else: discard

proc computeDeps(cache: IdentCache; n: PNode, declares, uses: var IntSet; topLevel: bool) =
  template deps(n) = computeDeps(cache, n, declares, uses, false)
  template decl(n) =
    if topLevel: addDecl(cache, n, declares)
  case n.kind
  of procDefs, nkMacroDef, nkTemplateDef:
    decl(n[0])
    for i in 1..bodyPos: deps(n[i])
  of nkLetSection, nkVarSection, nkUsingStmt:
    for a in n:
      if a.kind in {nkIdentDefs, nkVarTuple}:
        for j in 0..<a.len-2: decl(a[j])
        for j in a.len-2..<a.len: deps(a[j])
  of nkConstSection, nkTypeSection:
    for a in n:
      if a.len >= 3:
        decl(a[0])
        for i in 1..<a.len:
          if a[i].kind == nkEnumTy:
            # declare enum members
            for b in a[i]:
              decl(b)
          else:
            deps(a[i])
  of nkIdentDefs:
    for i in 1..<n.len: # avoid members identifiers in object definition
      deps(n[i])
  of nkIdent: uses.incl n.ident.id
  of nkSym: uses.incl n.sym.name.id
  of nkAccQuoted: uses.incl accQuoted(cache, n).id
  of nkOpenSymChoice, nkClosedSymChoice:
    uses.incl n[0].sym.name.id
  of nkStmtList, nkStmtListExpr, nkWhenStmt, nkElifBranch, nkElse, nkStaticStmt:
    for i in 0..<n.len: computeDeps(cache, n[i], declares, uses, topLevel)
  of nkPragma:
    let a = n[0]
    if a.kind == nkExprColonExpr and a[0].kind == nkIdent and a[0].ident.s == "pragma":
      # user defined pragma
      decl(a[1])
      for i in 1..<n.safeLen: deps(n[i])
    else:
      for i in 0..<n.safeLen: deps(n[i])
  of nkMixinStmt, nkBindStmt: discard
  else:
    # XXX: for callables, this technically adds the return type dep before args
    for i in 0..<n.safeLen: deps(n[i])

proc hasIncludes(n: PNode): bool =
  result = false
  for a in n:
    if a.kind == nkIncludeStmt:
      return true

proc includeModule*(graph: ModuleGraph; s: PSym, fileIdx: FileIndex): PNode =
  result = syntaxes.parseFile(fileIdx, graph.cache, graph.config)
  graph.addDep(s, fileIdx)
  graph.addIncludeDep(FileIndex s.position, fileIdx)

proc expandIncludes(graph: ModuleGraph, module: PSym, n: PNode,
                    modulePath: string, includedFiles: var IntSet): PNode =
  # Parses includes and injects them in the current tree
  if not n.hasIncludes:
    return n
  result = newNodeI(nkStmtList, n.info)
  for a in n:
    if a.kind == nkIncludeStmt:
      for i in 0..<a.len:
        var f = checkModuleName(graph.config, a[i])
        if f != InvalidFileIdx:
          if containsOrIncl(includedFiles, f.int):
            localError(graph.config, a.info, "recursive dependency: '$1'" %
              toMsgFilename(graph.config, f))
          else:
            let nn = includeModule(graph, module, f)
            let nnn = expandIncludes(graph, module, nn, modulePath,
                                      includedFiles)
            excl(includedFiles, f.int)
            for b in nnn:
              result.add b
    else:
      result.add a

proc splitSections(n: PNode): PNode =
  # Split typeSections and ConstSections into
  # sections that contain only one definition
  assert n.kind == nkStmtList
  result = newNodeI(nkStmtList, n.info)
  for a in n:
    if a.kind in {nkTypeSection, nkConstSection} and a.len > 1:
      for b in a:
        var s = newNode(a.kind)
        s.info = b.info
        s.add b
        result.add s
    else:
      result.add a

proc haveSameKind(dns: seq[DepN]): bool =
  # Check if all the nodes in a strongly connected
  # component have the same kind
  result = true
  let kind = dns[0].pnode.kind
  for dn in dns:
    if dn.pnode.kind != kind:
      return false

proc mergeSections(conf: ConfigRef; comps: seq[seq[DepN]], res: PNode) =
  # Merges typeSections and ConstSections when they form
  # a strong component (ex: circular type definition)
  for c in comps:
    assert c.len > 0
    if c.len == 1:
      res.add c[0].pnode
    else:
      let fstn = c[0].pnode
      let kind = fstn.kind
      # always return to the original order when we got circular dependencies
      let cs = c.sortedByIt(it.id)
      if kind in {nkTypeSection, nkConstSection} and haveSameKind(cs):
        # Circular dependency between type or const sections, we just
        # need to merge them
        var sn = newNode(kind)
        for dn in cs:
          sn.add dn.pnode[0]
        res.add sn
      else:
        # Problematic circular dependency, we arrange the nodes into
        # their original relative order and make sure to re-merge
        # consecutive type and const sections
        var wmsg = "Circular dependency detected. `codeReordering` pragma may not be able to" &
          " reorder some nodes properly"
        when defined(nimDebugReorder):
          wmsg &= ":\n"
          for i in 0..<cs.len-1:
            for j in i..<cs.len:
              for ci in 0..<cs[i].kids.len:
                if cs[i].kids[ci].id == cs[j].id:
                  wmsg &= "line " & $cs[i].pnode.info.line &
                    " depends on line " & $cs[j].pnode.info.line &
                    ": " & cs[i].expls[ci] & "\n"
          for j in 0..<cs.len-1:
            for ci in 0..<cs[^1].kids.len:
              if cs[^1].kids[ci].id == cs[j].id:
                wmsg &= "line " & $cs[^1].pnode.info.line &
                  " depends on line " & $cs[j].pnode.info.line &
                  ": " & cs[^1].expls[ci] & "\n"
        message(conf, cs[0].pnode.info, warnUser, wmsg)

        var i = 0
        while i < cs.len:
          if cs[i].pnode.kind in {nkTypeSection, nkConstSection}:
            let ckind = cs[i].pnode.kind
            var sn = newNode(ckind)
            sn.add cs[i].pnode[0]
            inc i
            while i < cs.len and cs[i].pnode.kind == ckind:
              sn.add cs[i].pnode[0]
              inc i
            res.add sn
          else:
            res.add cs[i].pnode
            inc i

proc hasImportStmt(n: PNode): bool =
  # Checks if the node is an import statement or
  # i it contains one
  case n.kind
  of nkImportStmt, nkFromStmt, nkImportExceptStmt:
    result = true
  of nkStmtList, nkStmtListExpr, nkWhenStmt, nkElifBranch, nkElse, nkStaticStmt:
    result = false
    for a in n:
      if a.hasImportStmt:
        return true
  else:
    result = false

proc hasImportStmt(n: DepN): bool =
  if n.hIS < 0:
    n.hIS = ord(n.pnode.hasImportStmt)
  result = bool(n.hIS)

proc hasCommand(n: PNode): bool =
  # Checks if the node is a command or a call
  # or if it contains one
  case n.kind
  of nkCommand, nkCall:
    result = true
  of nkStmtList, nkStmtListExpr, nkWhenStmt, nkElifBranch, nkElse,
      nkStaticStmt, nkLetSection, nkConstSection, nkVarSection,
      nkIdentDefs:
    result = false
    for a in n:
      if a.hasCommand:
        return true
  else:
    return false

proc hasCommand(n: DepN): bool =
  if n.hCmd < 0:
    n.hCmd = ord(n.pnode.hasCommand)
  result = bool(n.hCmd)

proc hasAccQuoted(n: PNode): bool =
  result = false
  if n.kind == nkAccQuoted:
    return true
  for a in n:
    if hasAccQuoted(a):
      return true

const extendedProcDefs = procDefs + {nkMacroDef, nkTemplateDef}

proc hasAccQuotedDef(n: PNode): bool =
  # Checks if the node is a function, macro, template ...
  # with a quoted name or if it contains one
  case n.kind
  of extendedProcDefs:
    result = n[0].hasAccQuoted
  of nkStmtList, nkStmtListExpr, nkWhenStmt, nkElifBranch, nkElse, nkStaticStmt:
    result = false
    for a in n:
      if hasAccQuotedDef(a):
        return true
  else:
    result = false

proc hasAccQuotedDef(n: DepN): bool =
  if n.hAQ < 0:
    n.hAQ = ord(n.pnode.hasAccQuotedDef)
  result = bool(n.hAQ)

proc hasBody(n: PNode): bool =
  # Checks if the node is a function, macro, template ...
  # with a body or if it contains one
  case n.kind
  of nkCommand, nkCall:
    result = true
  of extendedProcDefs:
    result = n[^1].kind == nkStmtList
  of nkStmtList, nkStmtListExpr, nkWhenStmt, nkElifBranch, nkElse, nkStaticStmt:
    result = false
    for a in n:
      if a.hasBody:
        return true
  else:
    result = false

proc hasBody(n: DepN): bool =
  if n.hB < 0:
    n.hB = ord(n.pnode.hasBody)
  result = bool(n.hB)

proc intersects(s1, s2: IntSet): bool =
  result = false
  for a in s1:
    if s2.contains(a):
      return true

proc hasPushOrPopPragma(n: DepN): bool =
  # Checks if the tree node has some pragmas that do not
  # play well with reordering, like the push/pop pragma
  # no crossing for push/pop barrier
  let a = n.pnode
  result = a.kind == nkPragma and a[0].kind == nkIdent and
      (a[0].ident.s == "push" or a[0].ident.s == "pop")

proc buildGraph(n: PNode, deps: seq[(IntSet, IntSet)]): DepG =
  # Build a dependency graph
  result = newSeqOfCap[DepN](deps.len)
  for i in 0..<deps.len:
    result.add newDepN(i, n[i])
  for i in 0..<deps.len:
    var ni = result[i]
    let uses = deps[i][1]
    let niHasBody = ni.hasBody
    let niHasCmd = ni.hasCommand
    for j in 0..<deps.len:
      if i == j: continue
      var nj = result[j]
      let declares = deps[j][0]
      if j < i and nj.hasCommand and niHasCmd:
        # Preserve order for commands and calls
        ni.kids.add nj
        when defined(nimDebugReorder):
          ni.expls.add "both have commands and one comes after the other"
      elif j < i and nj.hasImportStmt:
        # Every node that comes after an import statement must
        # depend on that import
        ni.kids.add nj
        when defined(nimDebugReorder):
          ni.expls.add "parent is, or contains, an import statement and child comes after it"
      elif j < i and niHasBody and nj.hasAccQuotedDef:
        # Every function, macro, template... with a body depends
        # on precedent function declarations that have quoted names.
        # That's because it is hard to detect the use of functions
        # like "[]=", "[]", "or" ... in their bodies.
        ni.kids.add nj
        when defined(nimDebugReorder):
          ni.expls.add "one declares a quoted identifier and the other has a body and comes after it"
      elif j < i and niHasBody and not nj.hasBody and
        intersects(deps[i][0], declares):
          # Keep function declaration before function definition
          ni.kids.add nj
          when defined(nimDebugReorder):
            for dep in deps[i][0]:
              if dep in declares:
                ni.expls.add "one declares \"" & idNames[dep] & "\" and the other defines it"
      elif hasPushOrPopPragma(nj):
        # Every node that comes after a push/pop pragma must
        # depend on it; vice versa
        if j < i:
          ni.kids.add nj
        else:
          nj.kids.add ni
      else:
        for d in declares:
          if uses.contains(d):
            ni.kids.add nj
            when defined(nimDebugReorder):
              ni.expls.add "one declares \"" & idNames[d] & "\" and the other uses it"

proc strongConnect(v: var DepN, idx: var int, s: var seq[DepN],
                   res: var seq[seq[DepN]]) =
  # Recursive part of trajan's algorithm
  v.idx = idx
  v.lowLink = idx
  inc idx
  s.add v
  v.onStack = true
  for w in v.kids.mitems:
    if w.idx < 0:
      strongConnect(w, idx, s, res)
      v.lowLink = min(v.lowLink, w.lowLink)
    elif w.onStack:
      v.lowLink = min(v.lowLink, w.idx)
  if v.lowLink == v.idx:
    var comp = newSeq[DepN]()
    while true:
      var w = s.pop
      w.onStack = false
      comp.add w
      if w.id == v.id: break
    res.add comp

proc getStrongComponents(g: var DepG): seq[seq[DepN]] =
  ## Tarjan's algorithm. Performs a topological sort
  ## and detects strongly connected components.
  result = @[]
  var s: seq[DepN] = @[]
  var idx = 0
  for v in g.mitems:
    if v.idx < 0:
      strongConnect(v, idx, s, result)

proc reorder*(graph: ModuleGraph, n: PNode, module: PSym): PNode =
  var includedFiles = initIntSet()
  let mpath = toFullPath(graph.config, module.fileIdx)
  let n = expandIncludes(graph, module, n, mpath,
                          includedFiles).splitSections
  result = newNodeI(nkStmtList, n.info)
  var deps = newSeq[(IntSet, IntSet)](n.len)
  for i in 0..<n.len:
    deps[i][0] = initIntSet()
    deps[i][1] = initIntSet()
    computeDeps(graph.cache, n[i], deps[i][0], deps[i][1], true)

  var g = buildGraph(n, deps)
  let comps = getStrongComponents(g)
  mergeSections(graph.config, comps, result)

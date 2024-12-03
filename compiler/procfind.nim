#
#
#           The Nim Compiler
#        (c) Copyright 2013 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# This module implements the searching for procs and iterators.
# This is needed for proper handling of forward declarations.

import
  ast, astalgo, msgs, semdata, types, trees, lookups

import std/strutils

proc equalGenericParams(procA, procB: PNode): bool =
  if procA.len != procB.len: return false
  for i in 0..<procA.len:
    if procA[i].kind != nkSym:
      return false
    if procB[i].kind != nkSym:
      return false
    let a = procA[i].sym
    let b = procB[i].sym
    if a.name.id != b.name.id or
        not sameTypeOrNil(a.typ, b.typ, {ExactTypeDescValues}): return
    if a.ast != nil and b.ast != nil:
      if not exprStructuralEquivalent(a.ast, b.ast): return
  result = true

proc searchForProcAux(c: PContext, scope: PScope, fn: PSym): PSym =
  const flags = {ExactGenericParams, ExactTypeDescValues,
                 ExactConstraints, IgnoreCC}
  var it: TIdentIter = default(TIdentIter)
  result = initIdentIter(it, scope.symbols, fn.name)
  while result != nil:
    if result.kind == fn.kind: #and sameType(result.typ, fn.typ, flags):
      case equalParams(result.typ.n, fn.typ.n)
      of paramsEqual:
        if (sfExported notin result.flags) and (sfExported in fn.flags):
          let message = ("public implementation '$1' has non-public " &
                         "forward declaration at $2") %
                        [getProcHeader(c.config, result, getDeclarationPath = false), c.config$result.info]
          localError(c.config, fn.info, message)
        return
      of paramsIncompatible:
        localError(c.config, fn.info, "overloaded '$1' leads to ambiguous calls" % fn.name.s)
        return
      of paramsNotEqual:
        discard
    result = nextIdentIter(it, scope.symbols)

proc searchForProc*(c: PContext, scope: PScope, fn: PSym): tuple[proto: PSym, comesFromShadowScope: bool] =
  var scope = scope
  result = (searchForProcAux(c, scope, fn), false)
  while result.proto == nil and scope.isShadowScope:
    scope = scope.parent
    result.proto = searchForProcAux(c, scope, fn)
    result.comesFromShadowScope = true

when false:
  proc paramsFitBorrow(child, parent: PNode): bool =
    result = false
    if child.len == parent.len:
      for i in 1..<child.len:
        var m = child[i].sym
        var n = parent[i].sym
        assert((m.kind == skParam) and (n.kind == skParam))
        if not compareTypes(m.typ, n.typ, dcEqOrDistinctOf): return
      if not compareTypes(child[0].typ, parent[0].typ,
                          dcEqOrDistinctOf): return
      result = true

  proc searchForBorrowProc*(c: PContext, startScope: PScope, fn: PSym): PSym =
    # Searches for the fn in the symbol table. If the parameter lists are suitable
    # for borrowing the sym in the symbol table is returned, else nil.
    var it: TIdentIter = default(TIdentIter)
    for scope in walkScopes(startScope):
      result = initIdentIter(it, scope.symbols, fn.Name)
      while result != nil:
        # watchout! result must not be the same as fn!
        if (result.Kind == fn.kind) and (result.id != fn.id):
          if equalGenericParams(result.ast[genericParamsPos],
                                fn.ast[genericParamsPos]):
            if paramsFitBorrow(fn.typ.n, result.typ.n): return
        result = NextIdentIter(it, scope.symbols)

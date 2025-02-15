#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements the '.liftLocals' pragma.

import
  options, ast, msgs,
  idents, renderer, types, lowerings, lineinfos

import std/strutils

from pragmas import getPragmaVal
from wordrecg import wLiftLocals

type
  Ctx = object
    partialParam: PSym
    objType: PType
    cache: IdentCache
    idgen: IdGenerator

proc interestingVar(s: PSym): bool {.inline.} =
  result = s.kind in {skVar, skLet, skTemp, skForVar, skResult} and
    sfGlobal notin s.flags

proc lookupOrAdd(c: var Ctx; s: PSym; info: TLineInfo): PNode =
  let field = addUniqueField(c.objType, s, c.cache, c.idgen)
  var deref = newNodeI(nkHiddenDeref, info)
  deref.typ() = c.objType
  deref.add(newSymNode(c.partialParam, info))
  result = newNodeI(nkDotExpr, info)
  result.add(deref)
  result.add(newSymNode(field))
  result.typ() = field.typ

proc liftLocals(n: PNode; i: int; c: var Ctx) =
  let it = n[i]
  case it.kind
  of nkSym:
    if interestingVar(it.sym):
      n[i] = lookupOrAdd(c, it.sym, it.info)
  of procDefs, nkTypeSection, nkMixinStmt, nkBindStmt: discard
  else:
    for i in 0..<it.safeLen:
      liftLocals(it, i, c)

proc lookupParam(params, dest: PNode): PSym =
  result = nil
  if dest.kind != nkIdent: return nil
  for i in 1..<params.len:
    if params[i].kind == nkSym and params[i].sym.name.id == dest.ident.id:
      return params[i].sym

proc liftLocalsIfRequested*(prc: PSym; n: PNode; cache: IdentCache; conf: ConfigRef;
                            idgen: IdGenerator): PNode =
  let liftDest = getPragmaVal(prc.ast, wLiftLocals)
  if liftDest == nil: return n
  let partialParam = lookupParam(prc.typ.n, liftDest)
  if partialParam.isNil:
    localError(conf, liftDest.info, "'$1' is not a parameter of '$2'" %
              [$liftDest, prc.name.s])
    return n
  let objType = partialParam.typ.skipTypes(abstractPtrs)
  if objType.kind != tyObject or tfPartial notin objType.flags:
    localError(conf, liftDest.info, "parameter '$1' is not a pointer to a partial object" % $liftDest)
    return n
  var c = Ctx(partialParam: partialParam, objType: objType, cache: cache, idgen: idgen)
  let w = newTree(nkStmtList, n)
  liftLocals(w, 0, c)
  result = w[0]

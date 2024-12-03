#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Plugin to transform an inline iterator into a data structure.

import ".." / [ast, modulegraphs, lookups, semdata, lambdalifting, msgs]

proc iterToProcImpl*(c: PContext, n: PNode): PNode =
  result = newNodeI(nkStmtList, n.info)
  let iter = n[1]
  if iter.kind != nkSym or iter.sym.kind != skIterator:
    localError(c.config, iter.info, "first argument needs to be an iterator")
    return
  if n[2].typ.isNil:
    localError(c.config, n[2].info, "second argument needs to be a type")
    return
  if n[3].kind != nkIdent:
    localError(c.config, n[3].info, "third argument needs to be an identifier")
    return

  let t = n[2].typ.skipTypes({tyTypeDesc, tyGenericInst})
  if t.kind notin {tyRef, tyPtr} or t.elementType.kind != tyObject:
    localError(c.config, n[2].info,
        "type must be a non-generic ref|ptr to object with state field")
    return
  let body = liftIterToProc(c.graph, iter.sym, getBody(c.graph, iter.sym), t, c.idgen)

  let prc = newSym(skProc, n[3].ident, c.idgen, iter.sym.owner, iter.sym.info)
  prc.typ = copyType(iter.sym.typ, c.idgen, prc)
  excl prc.typ.flags, tfCapturesEnv
  prc.typ.n.add newSymNode(getEnvParam(iter.sym))
  prc.typ.rawAddSon t
  let orig = iter.sym.ast
  prc.ast = newProcNode(nkProcDef, n.info,
              body = body, params = orig[paramsPos], name = newSymNode(prc),
              pattern = c.graph.emptyNode, genericParams = c.graph.emptyNode,
              pragmas = orig[pragmasPos], exceptions = c.graph.emptyNode)

  prc.ast.add iter.sym.ast[resultPos]
  addInterfaceDecl(c, prc)

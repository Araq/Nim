#
#
#           The Nim Compiler
#        (c) Copyright 2021 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module contains support code for new-styled error
## handling via an `nkError` node kind.

import ast, renderer, options, types
import std/strutils

when defined(nimPreviewSlimSystem):
  import std/assertions

type
  ErrorKind* = enum ## expand as you need.
    RawTypeMismatchError
    ExpressionCannotBeCalled
    CustomError
    WrongNumberOfArguments
    AmbiguousCall

proc errorSubNode*(n: PNode): PNode =
  case n.kind
  of nkEmpty..nkNilLit:
    result = nil
  of nkError:
    result = n
  else:
    result = nil
    for i in 0..<n.len:
      result = errorSubNode(n[i])
      if result != nil: break

proc newError*(wrongNode: PNode; k: ErrorKind; args: varargs[PNode]): PNode =
  assert wrongNode.kind != nkError
  let innerError = errorSubNode(wrongNode)
  if innerError != nil:
    return innerError
  var idgen = idGeneratorForPackage(-1'i32)
  result = newNodeIT(nkError, wrongNode.info, newType(tyError, idgen, nil))
  result.add wrongNode
  result.add newIntNode(nkIntLit, ord(k))
  for a in args: result.add a

proc newError*(wrongNode: PNode; msg: string): PNode =
  assert wrongNode.kind != nkError
  let innerError = errorSubNode(wrongNode)
  if innerError != nil:
    return innerError
  var idgen = idGeneratorForPackage(-1'i32)
  result = newNodeIT(nkError, wrongNode.info, newType(tyError, idgen, nil))
  result.add wrongNode
  result.add newIntNode(nkIntLit, ord(CustomError))
  result.add newStrNode(msg, wrongNode.info)

proc errorToString*(config: ConfigRef; n: PNode): string =
  assert n.kind == nkError
  assert n.len > 1
  let wrongNode = n[0]
  case ErrorKind(n[1].intVal)
  of RawTypeMismatchError:
    result = "type mismatch"
  of ExpressionCannotBeCalled:
    result = "expression '$1' cannot be called" % wrongNode[0].renderTree
  of CustomError:
    result = n[2].strVal
  of WrongNumberOfArguments:
    result = "wrong number of arguments"
  of AmbiguousCall:
    let a = n[2].sym
    let b = n[3].sym
    var args = "("
    for i in 1..<wrongNode.len:
      if i > 1: args.add(", ")
      args.add(typeToString(wrongNode[i].typ))
    args.add(")")
    result = "ambiguous call; both $1 and $2 match for: $3" % [
      getProcHeader(config, a),
      getProcHeader(config, b),
      args]

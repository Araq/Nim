# This file exists to make it overridable via
# patchFile("plugins", "customast.nim", "customast.nim")

## This also serves as a blueprint for a possible implementation.

import "$nim" / compiler / [lineinfos, idents]

when defined(nimPreviewSlimSystem):
  import std/assertions

import "$nim" / compiler / nodekinds
export nodekinds

type
  PNode* = ref TNode
  TNode*{.final, acyclic.} = object
    case kind*: TNodeKind
    of nkCharLit..nkUInt64Lit:
      intVal: BiggestInt
    of nkFloatLit..nkFloat128Lit:
      floatVal: BiggestFloat
    of nkStrLit..nkTripleStrLit:
      strVal: string
    of nkSym:
      discard
    of nkIdent:
      ident: PIdent
    else:
      son, next, last: PNode # linked structure instead of a `seq`
    info*: TLineInfo

const
  bodyPos* = 6
  paramsPos* = 3

proc comment*(n: PNode): string =
  result = ""

proc `comment=`*(n: PNode, a: string) =
  discard "XXX implement me"

proc add*(father, son: PNode) =
  assert son != nil
  if father.son == nil:
    father.son = son
    father.last = son
  else:
    father.last.next = son
    father.last = son

template firstSon*(n: PNode): PNode = n.son
template secondSon*(n: PNode): PNode = n.son.next

proc replaceFirstSon*(n, newson: PNode) {.inline.} =
  let old = n.son
  n.son = newson
  newson.next = old

proc replaceSon*(n: PNode; i: int; newson: PNode) =
  assert i > 0
  assert newson.next == nil
  var i = i
  var it = n.son
  while i > 0:
    it = it.next
    dec i
  let old = it.next
  it.next = newson
  newson.next = old

template newNodeImpl(info2) =
  result = PNode(kind: kind, info: info2)

proc newNode*(kind: TNodeKind): PNode =
  ## new node with unknown line info, no type, and no children
  newNodeImpl(unknownLineInfo)

proc newNode*(kind: TNodeKind, info: TLineInfo): PNode =
  ## new node with line info, no type, and no children
  newNodeImpl(info)

proc newTree*(kind: TNodeKind; info: TLineInfo; child: PNode): PNode =
  result = newNode(kind, info)
  result.son = child

proc newAtom*(ident: PIdent, info: TLineInfo): PNode =
  result = newNode(nkIdent)
  result.ident = ident
  result.info = info

proc newAtom*(kind: TNodeKind, intVal: BiggestInt, info: TLineInfo): PNode =
  result = newNode(kind, info)
  result.intVal = intVal

proc newAtom*(kind: TNodeKind, floatVal: BiggestFloat, info: TLineInfo): PNode =
  result = newNode(kind, info)
  result.floatVal = floatVal

proc newAtom*(kind: TNodeKind; strVal: sink string; info: TLineInfo): PNode =
  result = newNode(kind, info)
  result.strVal = strVal

proc lastSon*(n: PNode): PNode {.inline.} = n.last
proc setLastSon*(n: PNode, s: PNode) =
  assert s.next == nil
  n.last = s
  if n.son == nil: n.son = s

proc newProcNode*(kind: TNodeKind, info: TLineInfo, body: PNode,
                 params,
                 name, pattern, genericParams,
                 pragmas, exceptions: PNode): PNode =
  result = newNode(kind, info)
  result.add name
  result.add pattern
  result.add genericParams
  result.add params
  result.add pragmas
  result.add exceptions
  result.add body

template transitionNodeKindCommon(k: TNodeKind) =
  let obj {.inject.} = n[]
  n[] = TNode(kind: k, info: obj.info)
  # n.comment = obj.comment # shouldn't be needed, the address doesnt' change

proc transitionSonsKind*(n: PNode, kind: range[nkComesFrom..nkTupleConstr]) =
  transitionNodeKindCommon(kind)
  n.son = obj.son

template hasSon*(n: PNode): bool = n.son != nil
template has2Sons*(n: PNode): bool = n.son != nil and n.son.next != nil

proc isNewStyleConcept*(n: PNode): bool {.inline.} =
  assert n.kind == nkTypeClassTy
  result = n.firstSon.kind == nkEmpty

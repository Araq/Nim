discard """
  msg: '''"muhaha"
proc poo(x, y: int) =
  let y = x 
  echo ["poo"]'''
"""

import macros

const
  foo = "muhaha"

proc poo(x, y: int) =
  let y = x
  echo "poo"

macro m(x: typed): untyped =
  echo repr x.getImpl
  result = x

discard m foo
discard m poo

#------------

macro checkOwner(x: typed, check_id: static[int]): untyped = 
  let sym = case check_id:
    of 0: x
    of 1: x.getImpl.body[0][0][0]
    of 2: x.getImpl.body[0][0][^1]
    of 3: x.getImpl.body[1][0]
    else: x
  result = newStrLitNode($sym.owner.symKind)

macro isSameOwner(x, y: typed): untyped = 
  result = 
    if x.owner == y.owner: bindSym"true"
    else: bindSym"false"
    

static:
  doAssert checkOwner(foo, 0) == "nskModule"
  doAssert checkOwner(poo, 0) == "nskModule"
  doAssert checkOwner(poo, 1) == "nskProc"
  doAssert checkOwner(poo, 2) == "nskProc"
  doAssert checkOwner(poo, 3) == "nskModule"
  doAssert isSameOwner(foo, poo)
  doAssert isSameOwner(foo, echo) == false
  doAssert isSameOwner(poo, len) == false

block commmentTest:
  type Foo = object ## Foo obj comment 1
    ## Foo obj comment 2
    a1:int ## a1 field comment 2

  proc getCommentImpl(n: NimNode): string =
    case n.kind
    of nnkSym: result = n.getImpl.getCommentImpl
    of nnkTypeDef: result = n[2].getCommentImpl
    else: result = n.comment

  macro getComment(n: typed): untyped = n.getCommentImpl

  proc fun()=discard
    ## fun comment

  doAssert getComment(Foo) == "Foo obj comment 1\nFoo obj comment 2"
  doAssert getComment(fun) == "fun comment"
  # Note: Foo's fields's comments could be accessed by traversal

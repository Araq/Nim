discard """
  nimout: '''foo = "muhaha"
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

m(foo)
m(poo)

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
  proc wrappedScope() =
    proc dummyproc() = discard
    doAssert isSameOwner(foo, dummyproc) == false
    doAssert isSameOwner(poo, dummyproc) == false
  wrappedScope()

macro check_gen_proc(ex: typed): (bool, bool) =
  let lenChoice = bindsym"len"
  var is_equal = false 
  var is_instance_of = false 
  for child in lenChoice:
    if not is_equal:
      is_equal = ex[0] == child
    if not is_instance_of:
      is_instance_of = isInstantiationOf(ex[0], child)
         
  result = nnkTupleConstr.newTree(newLit(is_equal), newLit(is_instance_of))

# check that len(seq[int]) is not equal to bindSym"len", but is instance of it
let a = @[1,2,3]
assert: check_gen_proc(len(a)) == (false, true)


#---------------------------------------------------------------
# issue #16110

macro check(x: type): untyped =
  let z = getType(x)
  let y = getImpl(z[1])  
  var sym = y[0]
  if sym.kind == nnkPragmaExpr: sym = sym[0]
  if sym.kind == nnkPostfix: sym = sym[1]
  expectKind(z[1], nnkSym)
  expectKind(sym, nnkSym)
  expectKind(y[2], nnkObjectTy)
  doAssert(sym == z[1])

type
  TirePtr = ptr object
    code: int

  TireRef* = ref object
    code: int

  TireRef2* {.inheritable.} = ref object
    code: int

  TireRef3* {.inheritable.} = object
    code: int

var z1: TirePtr
check(typeof(z1[]))
var z2: TireRef
check(typeof(z2[]))
var z3: TireRef2
check(typeof(z3[]))
check(TireRef3)

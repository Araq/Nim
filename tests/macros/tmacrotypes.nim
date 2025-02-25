discard """
  nimout: '''intProc; ntyProc; proc[int, int, float]; proc (a: int; b: float): int {.nimcall.}
void; ntyVoid; void; void
int; ntyInt; int; int
proc () {.nimcall.}; ntyProc; proc[void]; proc () {.nimcall.}
voidProc; ntyProc; proc[void]; proc () {.nimcall.}
listing fields for ObjType
a: string
b: int
listing fields for ObjRef
skipping ref type
a: string
b: int
listing fields for RefType
skipping ref type
a: int
b: float
listing fields for typeof(a)
skipping ref type
a: string
b: int
listing fields for typeof(b)
skipping ref type
a: string
b: int
listing fields for typeof(c)
skipping ref type
a: int
b: float
listing fields for typeof(x)
a: string
b: int
listing fields for typeof(x)
a: int
b: float
typeDesc[range[1 .. 5]]; ntyTypeDesc; typeDesc[range[1, 5]]; typeDesc[range[1 .. 5]]
typeDesc[range]; ntyTypeDesc; typeDesc[range[T]]; typeDesc[range]'''
"""

import macros, typetraits

macro checkType(ex: typed): untyped =
  echo ex.getTypeInst.repr, "; ", ex.typeKind, "; ", ex.getType.repr, "; ", ex.getTypeImpl.repr

macro checkProcType(fn: typed): untyped =
  if fn.kind == nnkProcDef:
    result = fn
  let fn_sym = if fn.kind == nnkProcDef: fn[0] else: fn
  echo fn_sym, "; ", fn_sym.typeKind, "; ", fn_sym.getType.repr, "; ", fn_sym.getTypeImpl.repr

proc voidProc = echo "hello"
proc intProc(a: int, b: float): int {.checkProcType.} = 10

checkType(voidProc())
checkType(intProc(10, 20.0))
checkType(voidProc)
checkProcType(voidProc)

macro listFields(T: typed) =
  echo "listing fields for ", repr(T)
  let inputExprType = getType(T)

  var objType = inputExprType[1]
  if objType.kind == nnkBracketExpr and objType.len > 1:
    if ((objType[0].kind == nnkRefTy) or
        (objType[0].kind == nnkSym and eqIdent(objType[0], "ref"))):
      echo "skipping ref type"
      objType = objType[1]

  let typeAst = objType.getImpl

  var objectDef = typeAst[2]
  if objectDef.kind == nnkRefTy:
    objectDef = objectDef[0]

  let recList = objectDef[2]
  for rec in recList:
    echo $rec[0], ": ", $rec[1]

type
  ObjType* = object of RootObj
    a: string
    b: int

  ObjRef = ref ObjType

  RefType* = ref object of RootObj
    a: int
    b: float

listFields ObjType
listFields ObjRef
listFields RefType

let
  a = new ObjType
  b = new ObjRef
  c = new RefType

listFields typeOf(a)
listFields typeOf(b)
listFields typeOf(c)

proc genericProc(x: object) =
  listFields typeOf(x)

genericProc a[]
genericProc b[]
genericProc c[]

# bug #10548
block:
  var c {.compileTime.} = 0

  macro meshImpl(arg: typed): untyped =
    inc c
    result = arg

  type
    Blub = int32
    Mesh = meshImpl(Club)
    Club = Blub

  static: doAssert(c == 1)

# bug #10702
type
  VectorElementType = SomeNumber | bool
  Vec*[N : static[int], T: VectorElementType] = object
    arr*: array[N, T]

type
  Vec4*[T: VectorElementType] = Vec[4,T]
  Vec3*[T: VectorElementType] = Vec[3,T]
  Vec2*[T: VectorElementType] = Vec[2,T]

template vecGen(U:untyped,V:typed):typed=
  ## ``U`` suffix
  ## ``V`` valType
  ##
  type
    `Vec2 U`* {.inject.} = Vec2[V]
    `Vec3 U`* {.inject.} = Vec3[V]
    `Vec4 U`* {.inject.} = Vec4[V]

vecGen(f, float32)

macro foobar(arg: typed): untyped =
  let typ = arg.getTypeInst
  doAssert typ.getImpl[^1].kind == nnkCall

var x: Vec2f

foobar(x)

checkType(range[1..5])
checkType(range)


discard """
  targets: "c cpp"
  output: ""
"""

## Bugs 9698 and 9699

type
  UniquePtr*[T] = object
    ## non copyable pointer to object T, exclusive ownership of the object is assumed
    val: ptr T

  MyLen* = distinct int

  MySeq* = object
    ## Vectorized matrix
    len: MyLen  # scalar size
    data: ptr UncheckedArray[float]

proc `$`(x: MyLen): string {.borrow.}
proc `==`(x1, x2: MyLen): bool {.borrow.}


proc `=destroy`*(m: MySeq) {.inline.} =
  if m.data != nil:
    deallocShared(m.data)

proc `=copy`*(m: var MySeq, m2: MySeq) =
  if m.data == m2.data: return
  if m.data != nil:
    `=destroy`(m)

  m.len = m2.len
  let bytes = m.len.int * sizeof(float)
  if bytes > 0:
    m.data = cast[ptr UncheckedArray[float]](allocShared(bytes))
    copyMem(m.data, m2.data, bytes)

proc `=sink`*(m: var MySeq, m2: MySeq) {.inline.} =
  if m.data != m2.data:
    if m.data != nil:
      `=destroy`(m)
    m.len = m2.len
    m.data = m2.data

proc len*(m: MySeq): MyLen {.inline.} = m.len

proc lenx*(m: var MySeq): MyLen {.inline.} = m.len

proc `[]`*(m: MySeq; i: MyLen): float {.inline.} =
  m.data[i.int]

proc `[]`*(m: var MySeq; i: MyLen): var float {.inline.} =
  m.data[i.int]

proc `[]=`*(m: var MySeq; i: MyLen, val: float) {.inline.} =
  m.data[i.int] = val

proc setTo(s: var MySeq, val: float) =
  for i in 0..<s.len.int:
    s.data[i] = val

proc newMySeq*(size: int, initial_value = 0.0): MySeq =
  result.len = size.MyLen
  if size > 0:
    result.data = cast[ptr UncheckedArray[float]](createShared(float, size))

  result.setTo(initial_value)

converter literalToLen*(x: int{lit}): MyLen =
  x.MyLen


#-------------------------------------------------------------
# Unique pointer implementation
#-------------------------------------------------------------

proc `=destroy`*[T](p: UniquePtr[T]) =
  if p.val != nil:
    `=destroy`(p.val[])
    dealloc(p.val)

proc `=copy`*[T](dest: var UniquePtr[T], src: UniquePtr[T]) {.error.}

proc `=sink`*[T](dest: var UniquePtr[T], src: UniquePtr[T]) {.inline.} =
  if dest.val != nil and dest.val != src.val:
    `=destroy`(dest)
  dest.val = src.val

proc newUniquePtr*[T](val: sink T): UniquePtr[T] =
  result.val = cast[type(result.val)](alloc(sizeof(result.val[])))
  reset(result.val[])
  result.val[] = val

converter convertPtrToObj*[T](p: UniquePtr[T]): var T =
  result = p.val[]

var pu = newUniquePtr(newMySeq(5, 1.0))
let pu2 = newUniquePtr(newMySeq(5, 1.0))
doAssert: pu.len == 5
doAssert: pu2.len == 5
doAssert: pu.lenx == 5
doAssert: pu2.lenx == 5

pu[0] = 2.0
pu2[0] = 2.0
doAssert pu[0] == 2.0
doAssert: pu2[0] == 2.0

##-----------------------------------------------------------------------------------------
## Bugs #9735 and #9736
type
  ConstPtr*[T] = object
    ## This pointer makes it impossible to change underlying value
    ## as it returns only `lent T`
    val: ptr T

proc `=destroy`*[T](p: ConstPtr[T]) =
  if p.val != nil:
    `=destroy`(p.val[])
    dealloc(p.val)

proc `=copy`*[T](dest: var ConstPtr[T], src: ConstPtr[T]) {.error.}

proc `=sink`*[T](dest: var ConstPtr[T], src: ConstPtr[T]) {.inline.} =
  if dest.val != nil and dest.val != src.val:
    `=destroy`(dest)
  dest.val = src.val

proc newConstPtr*[T](val: sink T): ConstPtr[T] =
  result.val = cast[type(result.val)](alloc(sizeof(result.val[])))
  reset(result.val[])
  result.val[] = val

converter convertConstPtrToObj*[T](p: ConstPtr[T]): lent T =
  result = p.val[]

var pc = newConstPtr(newMySeq(3, 1.0))
let pc2 = newConstPtr(newMySeq(3, 1.0))
doAssert: pc.len == 3
doAssert: pc.len == 3
doAssert: compiles(pc.lenx == 2) == false
doAssert: compiles(pc2.lenx == 2) == false
doAssert: compiles(pc[0] = 2.0) == false
doAssert: compiles(pc2[0] = 2.0) == false

doAssert: pc[0] == 1.0
doAssert: pc2[0] == 1.0

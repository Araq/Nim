type
  ConstPtr*[T] = object
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

proc newConstPtr*[T](val: sink T): ConstPtr[T] {.inline.} =
  result.val = cast[type(result.val)](alloc(sizeof(result.val[])))
  reset(result.val[])
  result.val[] = val

converter convertConstPtrToObj*[T](p: ConstPtr[T]): lent T =
  result = p.val[]


#-------------------------------------------------------------

type
  MySeqNonCopyable* = object
    len: int
    data: ptr UncheckedArray[float]

proc `=destroy`*(m: MySeqNonCopyable) {.inline.} =
  if m.data != nil:
    deallocShared(m.data)

proc `=copy`*(m: var MySeqNonCopyable, m2: MySeqNonCopyable) {.error.}

proc `=sink`*(m: var MySeqNonCopyable, m2: MySeqNonCopyable) {.inline.} =
  if m.data != m2.data:
    if m.data != nil:
      `=destroy`(m)
    m.len = m2.len
    m.data = m2.data

proc len*(m: MySeqNonCopyable): int {.inline.} = m.len

proc `[]`*(m: MySeqNonCopyable; i: int): float {.inline.} =
  m.data[i.int]

proc `[]=`*(m: var MySeqNonCopyable; i: int, val: float) {.inline.} =
  m.data[i.int] = val

proc setTo(s: var MySeqNonCopyable, val: float) =
  for i in 0..<s.len.int:
    s.data[i] = val

proc newMySeq*(size: int, initial_value = 0.0): MySeqNonCopyable =
  result.len = size
  if size > 0:
    result.data = cast[ptr UncheckedArray[float]](createShared(float, size))
  result.setTo(initial_value)

#----------------------------------------------------------------------


proc test*(x1: int): ConstPtr[MySeqNonCopyable] {.inline.} = # remove inline here to make it work as expected
  if x1 == 0:
    let x = newMySeq(1, 0.0)
    result = newConstPtr(x)
  else:
    let y = newMySeq(x1, 0.0)
    result = newConstPtr(y)

discard test(10)

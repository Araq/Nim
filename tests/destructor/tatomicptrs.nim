discard """
  output: '''allocating
allocating
allocating
55
60
99
deallocating
deallocating
deallocating
allocating
deallocating
'''
joinable: false
"""

type
  SharedPtr*[T] = object
    x: ptr T

#proc isNil[T](s: SharedPtr[T]): bool {.inline.} = s.x.isNil

template incRef(x) =
  atomicInc(x.refcount)

template decRef(x): untyped = atomicDec(x.refcount)

proc makeShared*[T](x: sink T): SharedPtr[T] =
  # XXX could benefit from a macro that generates it.
  result = cast[SharedPtr[T]](allocShared0(sizeof(x)))
  result.x[] = x
  echo "allocating"

proc `=destroy`*[T](dest: var SharedPtr[T]) =
  var s = dest.x
  if s != nil and decRef(s) == 0:
    `=destroy`(s[])
    deallocShared(s)
    echo "deallocating"
    dest.x = nil

proc `=copy`*[T](dest: var SharedPtr[T]; src: SharedPtr[T]) =
  var s = src.x
  if s != nil: incRef(s)
  #atomicSwap(dest, s)
  # XXX use an atomic store here:
  swap(dest.x, s)
  if s != nil and decRef(s) == 0:
    `=destroy`(s[])
    deallocShared(s)
    echo "deallocating"

proc `=dup`*[T](src: SharedPtr[T]): SharedPtr[T] =
  `=copy`(result, src)

proc `=sink`*[T](dest: var SharedPtr[T]; src: SharedPtr[T]) =
  ## XXX make this an atomic store:
  if dest.x != src.x:
    let s = dest.x
    if s != nil:
      `=destroy`(s[])
      deallocShared(s)
      echo "deallocating"
    dest.x = src.x

proc get*[T](s: SharedPtr[T]): lent T =
  s.x[]

template `.`*[T](s: SharedPtr[T]; field: untyped): untyped =
  s.x.field

template `.=`*[T](s: SharedPtr[T]; field, value: untyped) =
  s.x.field = value

from macros import unpackVarargs

template `.()`*[T](s: SharedPtr[T]; field: untyped, args: varargs[untyped]): untyped =
  # xxx this isn't used, the test should be improved
  unpackVarargs(s.x.field, args)


type
  Tree = SharedPtr[TreeObj]
  TreeObj = object
    refcount: int
    le, ri: Tree
    data: int

proc takesTree(a: Tree) =
  if not a.isNil:
    takesTree(a.le)
    echo a.data
    takesTree(a.ri)

proc createTree(data: int): Tree =
  result = makeShared(TreeObj(refcount: 1, data: data))

proc createTree(data: int; le, ri: Tree): Tree =
  result = makeShared(TreeObj(refcount: 1, le: le, ri: ri, data: data))


proc main =
  let le = createTree(55)
  let ri = createTree(99)
  let t = createTree(60, le, ri)
  takesTree(t)

main()



#-------------------------------------------------------
#bug #9781

type
  MySeq* [T] = object
    refcount: int
    len: int
    data: ptr UncheckedArray[T]

proc `=destroy`*[T](m: var MySeq[T]) {.inline.} =
  if m.data != nil:
    deallocShared(m.data)
    m.data = nil

proc `=copy`*[T](m: var MySeq[T], m2: MySeq[T]) =
  if m.data == m2.data: return
  if m.data != nil:
    `=destroy`(m)

  m.len = m2.len
  let bytes = m.len.int * sizeof(float)
  if bytes > 0:
    m.data = cast[ptr UncheckedArray[T]](allocShared(bytes))
    copyMem(m.data, m2.data, bytes)

proc `=dup`*[T](m: MySeq[T]): MySeq[T] =
  `=copy`[T](result, m)

proc `=sink`*[T](m: var MySeq[T], m2: MySeq[T]) {.inline.} =
  if m.data != m2.data:
    if m.data != nil:
      `=destroy`(m)
    m.len = m2.len
    m.data = m2.data
    m.refcount = m2.refcount

proc len*[T](m: MySeq[T]): int {.inline.} = m.len

proc newMySeq*[T](size: int, initial_value: T): MySeq[T] =
  result.len = size
  result.refcount = 1
  if size > 0:
    result.data = cast[ptr UncheckedArray[T]](allocShared(sizeof(T) * size))


let x = makeShared(newMySeq(10, 1.0))
doAssert: x.get().len == 10



#-------------------------------------------------------
#bug #12882

type
  ValueObject = object
    v: MySeq[int]
    name: string

  TopObject = object
    internal: seq[ValueObject]

var zz = new(TopObject)




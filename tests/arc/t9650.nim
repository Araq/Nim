discard """
  matrix: "--gc:arc"
"""

import typetraits

# bug #9650
type
  SharedPtr*[T] = object
    val: ptr tuple[atomicCounter: int, value: T]

  Node*[T] = object
    value: T
    next: SharedPtr[Node[T]]

  ForwardList*[T] = object
    first: SharedPtr[Node[T]]

proc `=destroy`*[T](p: var SharedPtr[T]) =
  if p.val != nil:
    let c = atomicDec(p.val[].atomicCounter)
    if c == 0:
      when not supportsCopyMem(T):
         `=destroy`(p.val[])
      dealloc(p.val)
    p.val = nil

proc `=`*[T](dest: var SharedPtr[T], src: SharedPtr[T]) =
  if dest.val != src.val:
    if dest.val != nil:
      `=destroy`(dest)
    if src.val != nil:
      discard atomicInc(src.val[].atomicCounter)
      dest.val = src.val

proc `=sink`*[T](dest: var SharedPtr[T], src: SharedPtr[T]) =
  if dest.val != nil and dest.val != src.val:
    `=destroy`(dest)
  dest.val = src.val

 
proc newSharedPtr*[T](val: sink T): SharedPtr[T] =
  result = default(SharedPtr[T])
  result.val = cast[type(result.val)](alloc(sizeof(result.val[])))
  reset(result.val[])
  result.val.atomicCounter = 1
  result.val.value = val

proc isNil*[T](p: SharedPtr[T]): bool =
  p.val == nil

template `->`*[T](p: SharedPtr[T], name: untyped): untyped =
  p.val.value.name

proc createNode[T](val: T): SharedPtr[ Node[T] ]=
  result = newSharedPtr(Node[T](value: val))

proc push_front*[T](list: var ForwardList[T], val: T) =
  var newElem = createNode(val)
  newElem->next = list.first
  list.first = newElem

proc pop_front*[T](list: var ForwardList[T]) =
  let head = list.first
  list.first = head->next

proc toString*[T](list: ForwardList[T]): string =
  result = "["
  var head = list.first
  while not head.isNil:
    result &= $(head->value) & ", "
    head = head->next
  result &= ']'

block:
  var x: ForwardList[int]
  x.push_front(1)
  x.push_front(2)
  x.push_front(3)

  doAssert toString(x) == "[3, 2, 1, ]"

  x.pop_front()
  x.pop_front()
  doAssert toString(x) == "[1, ]"

  x.pop_front()
  doAssert toString(x) == "[]"

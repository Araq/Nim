discard """
  cmd: "nim c --threads:on --gc:arc $file"
  action: compile
"""

# bug #17893

type
  SharedPtr*[T] = object
    val: ptr tuple[value: T, atomicCounter: int]

proc `=destroy`*[T](p: var SharedPtr[T]) =
  mixin `=destroy`
  if p.val != nil:
    if atomicLoadN(addr p.val[].atomicCounter, AtomicConsume) == 0:
      `=destroy`(p.val[])
      deallocShared(p.val)
    else:
      discard atomicDec(p.val[].atomicCounter)

proc `=copy`*[T](dest: var SharedPtr[T], src: SharedPtr[T]) =
  if src.val != nil:
    discard atomicInc(src.val[].atomicCounter)
  if dest.val != nil:
    `=destroy`(dest)
  dest.val = src.val

proc newSharedPtr*[T](val: sink T): SharedPtr[T] {.nodestroy.} =
  result = SharedPtr[T]()
  result.val = cast[typeof(result.val)](allocShared(sizeof(result.val[])))
  result.val.atomicCounter = 0
  result.val.value = val

proc isNil*[T](p: SharedPtr[T]): bool {.inline.} =
  p.val == nil

proc `[]`*[T](p: SharedPtr[T]): var T {.inline.} =
  when compileOption("boundChecks"):
    doAssert(p.val != nil, "deferencing nil shared pointer")
  result = p.val.value

type
  Sender*[T] = object
    queue: SharedPtr[seq[T]]

proc newSender*[T](queue: sink SharedPtr[seq[T]]): Sender[T] =
  result = Sender[T](queue: queue)

proc send*[T](self: Sender[T]; t: sink T) =
  self.queue[].add t

proc newChannel*(): Sender[int] =
  let queue = newSharedPtr(newSeq[int]())
  result = newSender(queue)


var
  p: Thread[Sender[int]]

proc threadFn(tx: Sender[int]) =
  send tx, 0

proc multiThreadedChannel =
  let tx = newChannel()
  createThread(p, threadFn, tx)
  joinThread(p)

multiThreadedChannel()

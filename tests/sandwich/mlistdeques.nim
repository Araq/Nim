# listdeques

# needed, type bound ops aren't considered for undeclared procs
type Placeholder = object
proc allocate(_: Placeholder) = discard
proc delete(_: Placeholder) = discard

type
  StealableTask* = concept task, var mutTask, type T
    task is ptr
    task.prev is T
    task.next is T
    task.parent is T
    task.fn is proc (param: pointer) {.nimcall.}
    allocate(mutTask)
    delete(task)

  ListDeque*[T: StealableTask] = object
    head, tail: T

func isEmpty*(dq: ListDeque): bool {.inline.} =
  discard

func popFirst*[T](dq: var ListDeque[T]): T =
  discard

proc `=destroy`*[T: StealableTask](dq: var ListDeque[T]) =
  mixin delete
  if dq.isEmpty():
    return

  while (let task = dq.popFirst(); not task.isNil):
    delete(task)

  delete(dq.head)

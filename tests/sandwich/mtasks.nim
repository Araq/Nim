# tasks.nim
type
  Task* = ptr object
    parent*: Task
    prev*: Task
    next*: Task
    fn*: proc (param: pointer) {.nimcall.}

# StealableTask API
proc allocate*(task: var Task) =
  discard

proc delete*(task: Task) =
  discard

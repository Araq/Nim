import locks
import std/assertions

type MyType* [T] = object
  lock: Lock

proc createMyType*[T]: MyType[T] =
  result = default(MyType[T])
  initLock(result.lock)

proc use* (m: var MyType): int =
  withLock m.lock:
    result = 3

block:
  var l: Lock
  doAssert $l == "()"

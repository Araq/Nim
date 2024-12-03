import std/macros

type A[T, H] = object

proc `%*`(a: A): bool = true
proc `%*`[T](a: A[int, T]): bool = false

macro collapse(s: untyped) =
  result = newStmtList()
  result.add quote do:
    doAssert(`s`(A[float, int]()) == true)

macro startHere(n: untyped): untyped =
  result = newStmtList()
  let s = n[0]
  result.add quote do:
    `s`.collapse()

startHere(`a` %* `b`)

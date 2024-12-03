discard """
  action: "reject"
  errormsg: "ambiguous identifier: '%*'"
"""
import std/macros

type A[T, H] = object

proc `%*`[T](a: A) = discard
proc `%*`[T](a: A[int, T]) = discard

macro collapse(s: typed) = discard

macro startHere(n: untyped): untyped =
  result = newStmtList()
  let s = n[0]
  result.add quote do:
    collapse(`s`.typeof())

startHere(`a` %* `b`)

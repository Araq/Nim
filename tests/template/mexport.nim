import macros

type
  Storage[N: static[int]] = array[N, float32]
  Quat* = object
    data*: Storage[4]
  
proc `[]`(q: Quat, index: int): float32 = q.data[index]
proc `[]=`(q: var Quat, index: int, value: float32) = q.data[index] = value

template genAccessor(t, a, i): untyped =
  template a*(q: t): float32 {.inject.} = q[i]
  template `a=`*(q: var t, value: float32) {.inject.} = q[i] = value

genAccessor Quat, w, 0
genAccessor Quat, x, 1
genAccessor Quat, y, 2
expandMacros:
  genAccessor Quat, z, 3

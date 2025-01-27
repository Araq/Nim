block: # issue #19019
  proc start(draw:proc=(proc()=echo "default"), init:proc=(proc()=echo "default"), reshape:proc=(proc()=echo "default"))=discard
  start()

block: # issue #14067
  type
    Result[T, E] = object

    DataProc = proc(val: openArray[byte])
    GetProc = proc (onData: DataProc): Result[bool, cstring]

  func get[T, E](self: Result[T, E]): T =
    discard

  template `[]`[T, E](self: Result[T, E]): T =
    self.get()

  proc testKVStore() =
    var v: seq[byte]
    var p: GetProc

    discard p(proc(data: openArray[byte]) =
        v = @data
      )[]

  if false: testKVStore()

import std/macros

block: # issue #15004
  macro fn(fun:untyped):untyped =
    newTree(nnkTupleConstr, newLit"first", fun)

  macro fn(key:string, fun:untyped):untyped =
    newTree(nnkTupleConstr, newLit"second", fun)

  let c = fn(proc(count:int):string =
    return "x = " & $count
  )
  doAssert c[0] == "first"
  doAssert c[1](123) == "x = 123"

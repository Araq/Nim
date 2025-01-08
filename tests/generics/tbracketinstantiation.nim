discard """
  nimout: '''
type
  Bob = object
type
  Another = object
'''
"""

block: # issue #22645
  type
    Opt[T] = object
    FutureBase = ref object of RootObj
    Future[T] = ref object of FutureBase ## Typed future.
      internalValue: T ## Stored value
  template err[T](E: type Opt[T]): E = E()
  proc works(): Future[Opt[int]] {.stackTrace: off, gcsafe, raises: [].} =
    var chronosInternalRetFuture: FutureBase
    template result(): untyped {.used.} =
      Future[Opt[int]](chronosInternalRetFuture).internalValue
    result = err(type(result))
  proc breaks(): Future[Opt[int]] {.stackTrace: off, gcsafe, raises: [].} =
    var chronosInternalRetFuture: FutureBase
    template result(): untyped {.used.} =
      cast[Future[Opt[int]]](chronosInternalRetFuture).internalValue
    result = err(type(result))

import macros

block: # issue #16118
  macro thing(name: static[string]) =
    result = newStmtList(
      nnkTypeSection.newTree(
        nnkTypeDef.newTree(
          ident(name),
          newEmptyNode(),
          nnkObjectTy.newTree(
            newEmptyNode(),
            newEmptyNode(),
            nnkRecList.newTree()))))
  template foo(name: string): untyped =
    thing(name)
  expandMacros:
    foo("Bob")
  block:
    expandMacros:
      foo("Another")

block: # issue #19670
  type
    Past[Z] = object
    OpenObject = object

  macro rewriter(prc: untyped): untyped =
    prc.body.add(nnkCall.newTree(
      prc.params[0]
    ))
    prc
    
  macro macroAsync(name, restype: untyped): untyped =
    quote do:
      proc `name`(): Past[seq[`restype`]] {.rewriter.} = discard
      
  macroAsync(testMacro, OpenObject)

import asyncdispatch

block: # issue #11838 long
  type
    R[P] = object
      updates: seq[P]
    D[T, P] = ref object
      ps: seq[P]
      t: T
  proc newD[T, P](ps: seq[P], t: T): D[T, P] =
    D[T, P](ps: ps, t: t)
  proc loop[T, P](d: D[T, P]) =
    var results = newSeq[Future[R[P]]](10)
  let d = newD[string, int](@[1], "")
  d.loop()

block: # issue #11838 minimal
  type R[T] = object
  proc loop[T]() =
    discard newSeq[R[R[T]]]()
  loop[int]()

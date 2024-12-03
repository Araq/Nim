discard """
  outputsub: "true"
  disabled: "32bit"
  retries: 2
"""

type
  TFoo* = object
    id: int
    fn: proc() {.closure.}
var foo_counter = 0
var alive_foos = newseq[int](0)

when defined(gcDestructors):
  proc `=destroy`(some: TFoo) =
    alive_foos.del alive_foos.find(some.id)
    # TODO: fixme: investigate why `=destroy` requires `some.fn` to be `gcsafe`
    # the debugging info below came from `symPrototype` in the liftdestructors
    # proc (){.closure, gcsafe.}, {tfThread, tfHasAsgn, tfCheckedForDestructor, tfExplicitCallConv}
    # var proc (){.closure, gcsafe.}, {tfHasGCedMem}
    # it worked by accident with var T destructors because in the sempass2
    #
    # let argtype = skipTypes(a.typ, abstractInst) # !!! it does't skip `tyVar`
    # if argtype.kind == tyProc and notGcSafe(argtype) and not tracked.inEnforcedGcSafe:
    #   localError(tracked.config, n.info, $n & " is not GC safe")
    {.cast(gcsafe).}:
      `=destroy`(some.fn)

else:
  proc free*(some: ref TFoo) =
    #echo "Tfoo #", some.id, " freed"
    alive_foos.del alive_foos.find(some.id)

proc newFoo*(): ref TFoo =
  when defined(gcDestructors):
    new result
  else:
    new result, free

  result.id = foo_counter
  alive_foos.add result.id
  inc foo_counter

for i in 0 ..< 10:
  discard newFoo()

for i in 0 ..< 10:
  let f = newFoo()
  f.fn = proc =
    echo f.id

GC_fullcollect()
echo alive_foos.len <= 3

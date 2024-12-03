# bug #22619

when false: # todo fixme
  block:
    type
      Resource = object
        value: int
  
      Object = object
        r {.cursor.}: Resource
        s {.cursor.}: seq[Resource]
  
    var numDestroy = 0
  
    proc `=copy`(x: var Resource, y: Resource) {.error.} # disallow full copies
    proc `=destroy`(x: Resource) =
      inc numDestroy
  
    proc test() =
      # perform the test in procedure so that globals aren't used (their different
      # semantics with regards to destruction would interfere)
      var
        r = Resource(value: 1) # initialize a resource
        s = @[Resource(value: 2)]
  
      # make sure no copy is required in the initializer expression:
      var o = Object(r: r, s: s)
  
      # copying the object doesn't perform a full copy of the cursor fields:
      var o2 = o
      discard addr(o2) # prevent `o2` from being turned into a cursor
  
      # check that the fields were shallow-copied:
      doAssert o2.r.value == 1
      doAssert o2.s[0].value == 2
  
      # make sure no copy is required with normal field assignments:
      o.r = r
      o.s = s
  
  
      # when `o` and `o2` are destroyed, their destructor must not be called on
      # their fields
  
    test()
  
    # one call for the `r` local and one for the object in `s`
    doAssert numDestroy == 2

block:
  type Value = distinct int

  var numDestroy = 0

  when defined(gcRefc):
    proc `=destroy`(x: var Value) =
      inc numDestroy
  else:
    proc `=destroy`(x: Value) =
      inc numDestroy

  iterator iter(s: seq[Value]): int {.closure.} =
    # because it is used across yields, `s2` is lifted into the iterator's
    # environment. Since non-ref cursors in object didn't have their hooks
    # disabled inside the environments lifted hooks, this led to double
    # frees
    var s2 {.cursor.} = s
    var i = 0
    let L = s2.len
    while i < L:
      yield s2[i].int
      inc i

  proc test() =
    var s = @[Value(1), Value(2)]
    let cl = iter
    # make sure resuming the iterator works:
    doAssert cl(s) == 1
    doAssert cl(s) == 2
    doAssert cl(s) == 0

  test()
  doAssert numDestroy == 2

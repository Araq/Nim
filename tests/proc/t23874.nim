block:
  type Head[T] = object
    wasc: bool

  proc `=destroy`[T](x: var Head[T]) =
    discard

  proc `=copy`[T](x: var Head[T], y: Head[T]) =
    x.wasc = true

  proc `=dup`[T](x: Head[T]): Head[T] =
    result.wasc = true

  proc update(h: var Head) =
    discard

  proc digest(h: sink Head) =
    assert h.wasc

  var h = Head[int](wasc: false)
  h.digest() # sink h
  h.update() # use after sink

block:
  proc two(a: sink auto) =discard
  assert typeof(two[int]) is proc(a: sink int) {.nimcall.}

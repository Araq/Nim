block: # issue #22775
  proc h(c: int) = discard
  template k(v: int) =
    template p() = v.h()
    p()
  let a = @[0]
  k(0 and not a[0])

block: # issue #22775 case 2
  proc h(c: int, q: int) = discard
  template k(v: int) =
    template p() = h(v, v)
    p()
  let a = [0]
  k(0 and not a[0])

block: # issue #22775 minimal cases
  proc h(c: int) = discard
  template k(v: int) =
    template p() = h(v)
    p()
  let a = [0]
  k(not a[0])
  block:
    k(-a[0])
  block:
    proc f(x: int): int = x
    k(f a[0])

block: # bracket assignment case of above tests
  proc h(c: int) = discard
  template k(v: int) =
    template p() = h(v)
    p()
  var a = [0]
  k(not (block:
    a[0] = 1
    1))

# issue #23020

proc n[T: bool](k: int | int) =
  #static:
  #  doAssert T is bool
  #  doAssert T isnot int

  # And runtime
  block:
    doAssert T is bool
    doAssert T isnot int

n[int](0) #[tt.Error
      ^ type mismatch: got <int literal(0)>]#

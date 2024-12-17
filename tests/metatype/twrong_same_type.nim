# bug #23418

template mapIt*(x: untyped): untyped =
  type OutType {.gensym.} = typeof(x) #typeof(x, typeOfProc)
  newSeq[OutType](5)

type F[E] = object

proc start(v: int): F[(ValueError,)] = discard
proc stop(v: int): F[tuple[]] = discard

assert $typeof(mapIt(start(9))) == "seq[F[(ValueError,)]]"
assert $typeof(mapIt(stop(9))) == "seq[F[tuple[]]]"

# bug #23445

type F2[T; I: static int] = distinct int

proc start2(v: int): F2[void, 22] = discard
proc stop2(v: int): F2[void, 33] = discard

var a = mapIt(start2(5))

assert $type(a) == "seq[F2[system.void, 22]]", $type(a)

var b = mapIt(stop2(5))

assert $type(b) == "seq[F2[system.void, 33]]", $type(b)

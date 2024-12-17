# issue #23010

type
  Result[T, E] = object
    case oResult: bool
    of false:
      discard
    of true:
      vResult: T

  Opt[T] = Result[T, void]

template ok[T, E](R: type Result[T, E], x: untyped): R =
  R(oResult: true, vResult: x)

template c[T](v: T): Opt[T] = Opt[T].ok(v)

type
  FixedBytes[N: static[int]] = distinct array[N, byte]

  H = object
    d: FixedBytes[2]

const b = default(H)
template g(): untyped =
  const t = default(H)
  b

discard c(g())

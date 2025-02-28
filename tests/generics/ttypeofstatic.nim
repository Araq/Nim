# issue #24715

type H[c: static[float64]] = object
  value: typeof(c)

proc u[T: H](_: typedesc[T]) =
  discard default(T)

u(H[1'f64])

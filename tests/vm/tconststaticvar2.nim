# issue #24634

type J = object

template m(u: J): int =
  let v = u
  0

proc g() =
  const x = J()
  const _ = m(x)

g()

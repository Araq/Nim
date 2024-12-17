block: # issue #13799
  type
    X[A, B] = object
      a: A
      b: B

    Y[A] = X[A, int]
  template s(T: type X): X = T()
  template t[A, B](T: type X[A, B]): X[A, B] = T()
  proc works1(): Y[int] = s(X[int, int])
  proc works2(): Y[int] = t(X[int, int])
  proc works3(): Y[int] = t(Y[int])
  proc broken(): Y[int] = s(Y[int])

block: # issue #24415
  type GVec2[T] = object
    x, y: T
  type Uniform[T] = T
  proc foo(v: Uniform[GVec2[float32]]): float32 =
    result = v.x
  let f = GVec2[float32](x: 1.0f, y: 2.0f)
  doAssert foo(f) == 1.0f

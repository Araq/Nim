block: # issue #23594
  type
    Gen[T] = object
      a: T = 1.0

    Spec32 = Gen[float32]
    Spec64 = Gen[float64]

  var
    a: Spec32
    b: Spec64
  doAssert sizeof(a) == 4
  doAssert sizeof(b) == 8
  doAssert a.a is float32
  doAssert b.a is float64

block: # issue #21941
  func what[T](): T =
    123

  type MyObject[T] = object
      f: T = what[T]()

  var m: MyObject[float] = MyObject[float]()
  doAssert m.f is float
  doAssert m.f == 123.0

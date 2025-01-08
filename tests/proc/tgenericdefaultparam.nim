block: # issue #16700
  type MyObject[T] = object
    x: T
  proc initMyObject[T](value = T.default): MyObject[T] =
    MyObject[T](x: value)
  var obj = initMyObject[int]()

block: # issue #20916
  type
    SomeX = object
      v: int
  var val = 0
  proc f(_: type int, x: SomeX, v = x.v) =
    doAssert v == 42
    val = v
  proc a(): proc() =
    let v = SomeX(v: 42)
    var tmp = proc() =
      int.f(v)
    tmp
  a()()
  doAssert val == 42

import std/typetraits

block: # issue #24099, original example
  type
    ColorRGBU = distinct array[3, uint8] ## RGB range 0..255
    ColorRGBAU = distinct array[4, uint8] ## RGB range 0..255
    ColorRGBUAny = ColorRGBU | ColorRGBAU
  template componentType(t: typedesc[ColorRGBUAny]): typedesc =
    ## Returns component type of a given color type.
    arrayType distinctBase t
  func `~=`[T: ColorRGBUAny](a, b: T, e = componentType(T)(1.0e-11)): bool =
    ## Compares colors with given accuracy.
    abs(a[0] - b[0]) < e and abs(a[1] - b[1]) < e and abs(a[2] - b[2]) < e

block: # issue #24099, modified to actually work
  type
    ColorRGBU = distinct array[3, uint8] ## RGB range 0..255
    ColorRGBAU = distinct array[4, uint8] ## RGB range 0..255
    ColorRGBUAny = ColorRGBU | ColorRGBAU
  template arrayType[I, T](t: typedesc[array[I, T]]): typedesc =
    T
  template `[]`(a: ColorRGBUAny, i: untyped): untyped = distinctBase(a)[i]
  proc abs(a: uint8): uint8 = a
  template componentType(t: typedesc[ColorRGBUAny]): typedesc =
    ## Returns component type of a given color type.
    arrayType distinctBase t
  func `~=`[T: ColorRGBUAny](a, b: T, e = componentType(T)(1.0e-11)): bool =
    ## Compares colors with given accuracy.
    abs(a[0] - b[0]) <= e and abs(a[1] - b[1]) <= e and abs(a[2] - b[2]) <= e
  doAssert ColorRGBU([1.uint8, 1, 1]) ~= ColorRGBU([1.uint8, 1, 1])

block: # issue #24099, modified to work but using float32
  type
    ColorRGBU = distinct array[3, float32] ## RGB range 0..255
    ColorRGBAU = distinct array[4, float32] ## RGB range 0..255
    ColorRGBUAny = ColorRGBU | ColorRGBAU
  template arrayType[I, T](t: typedesc[array[I, T]]): typedesc =
    T
  template `[]`(a: ColorRGBUAny, i: untyped): untyped = distinctBase(a)[i]
  template componentType(t: typedesc[ColorRGBUAny]): typedesc =
    ## Returns component type of a given color type.
    arrayType distinctBase t
  func `~=`[T: ColorRGBUAny](a, b: T, e = componentType(T)(1.0e-11)): bool =
    ## Compares colors with given accuracy.
    abs(a[0] - b[0]) < e and abs(a[1] - b[1]) < e and abs(a[2] - b[2]) < e
  doAssert ColorRGBU([1.float32, 1, 1]) ~= ColorRGBU([1.float32, 1, 1])

block: # issue #13270
  type
    A = object
    B = object
  proc f(a: A) = discard
  proc g[T](value: T, cb: (proc(a: T)) = f) =
    cb value
  g A()
  # This should fail because there is no f(a: B) overload available
  doAssert not compiles(g B())

block: # issue #24121
  type
    Foo = distinct int
    Bar = distinct int
    FooBar = Foo | Bar

  proc foo[T: distinct](x: T): string = "a"
  proc foo(x: Foo): string = "b"
  proc foo(x: Bar): string = "c"

  proc bar(x: FooBar, y = foo(x)): string = y
  doAssert bar(Foo(123)) == "b"
  doAssert bar(Bar(123)) == "c"

  proc baz[T: FooBar](x: T, y = foo(x)): string = y
  doAssert baz(Foo(123)) == "b"
  doAssert baz(Bar(123)) == "c"

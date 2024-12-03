
{.experimental: "inferGenericTypes".}

import std/tables

block:
  type
    MyOption[T, Z] = object
      x: T
      y: Z

  proc none[T, Z](): MyOption[T, Z] =
    when T is int:
      result.x = 22
    when Z is float:
      result.y = 12.0

  proc myGenericProc[T, Z](): MyOption[T, Z] =
    none() # implied by return type

  let a = myGenericProc[int, float]()
  doAssert a.x == 22
  doAssert a.y == 12.0

  let b: MyOption[int, float] = none() # implied by type of b
  doAssert b.x == 22
  doAssert b.y == 12.0

# Simple template based result with inferred type for errors
block:
  type
    ResultKind {.pure.} = enum
      Ok
      Err

    Result[T] = object
      case kind: ResultKind
      of Ok:
        data: T
      of Err:
        errmsg: cstring

  template err[T](msg: static cstring): Result[T] =
    Result[T](kind : ResultKind.Err, errmsg : msg)

  proc testproc(): Result[int] =
    err("Inferred error!") # implied by proc return
  let r = testproc()
  doAssert r.kind == ResultKind.Err
  doAssert r.errmsg == "Inferred error!"

# Builtin seq
block:
  let x: seq[int] = newSeq(1)
  doAssert x is seq[int]
  doAssert x.len() == 1

  type
    MyType[T, Z] = object
      x: T
      y: Z

  let y: seq[MyType[int, float]] = newSeq(2)
  doAssert y is seq[MyType[int, float]]
  doAssert y.len() == 2

  let z = MyType[seq[float], string](
    x : newSeq(3),
    y : "test"
  )
  doAssert z.x is seq[float]
  doAssert z.x.len() == 3
  doAssert z.y is string
  doAssert z.y == "test"

# array
block:
  proc giveArray[N, T](): array[N, T] =
    for i in 0 .. N.high:
      result[i] = i
  var x: array[2, int] = giveArray()
  doAssert x == [0, 1]

# tuples
block:
  proc giveTuple[T, Z]: (T, Z, T) = discard
  let x: (int, float, int) = giveTuple()
  doAssert x is (int, float, int)
  doAssert x == (0, 0.0, 0)

  proc giveNamedTuple[T, Z]: tuple[a: T, b: Z] = discard
  let y: tuple[a: int, b: float] = giveNamedTuple()
  doAssert y is (int, float)
  doAssert y is tuple[a: int, b: float]
  doAssert y == (0, 0.0)

  proc giveNestedTuple[T, Z]: ((T, Z), Z) = discard
  let z: ((int, float), float) = giveNestedTuple()
  doAssert z is ((int, float), float)
  doAssert z == ((0, 0.0), 0.0)

  # nesting inside a generic type
  type MyType[T] = object
    x: T
  let a = MyType[(int, MyType[float])](x : giveNamedTuple())
  doAssert a.x is (int, MyType[float])


# basic constructors
block:
  type MyType[T] = object
    x: T

  proc giveValue[T](): T =
    when T is int:
      12
    else:
      default(T)

  let x = MyType[int](x : giveValue())
  doAssert x.x is int
  doAssert x.x == 12

  let y = MyType[MyType[float]](x : MyType[float](x : giveValue()))
  doAssert y.x is MyType[float]
  doAssert y.x.x is float
  doAssert y.x.x == 0.0

  # 'MyType[float]' is bound to 'T' directly
  #  instead of mapping 'T' to 'float'
  let z = MyType[MyType[float]](x : giveValue())
  doAssert z.x is MyType[float]
  doAssert z.x.x == 0.0

  type Foo = object
    x: Table[int, float]

  let a = Foo(x: initTable())
  doAssert a.x is Table[int, float]

# partial binding
block:
  type
    ResultKind = enum
      Ok, Error

    Result[T, E] = object
      case kind: ResultKind
      of Ok:
        okVal: T
      of Error:
        errVal: E

  proc err[T, E](myParam: E): Result[T, E] =
    Result[T, E](kind : Error, errVal : myParam)

  proc doStuff(): Result[int, string] = 
    err("Error")

  let res = doStuff()
  doAssert res.kind == Error
  doAssert res.errVal == "Error"

# ufcs
block:
  proc getValue[T](_: string): T =
    doAssert T is int
    44
  
  proc `'test`[T](_: string): T =
    55

  let a: int = getValue("")
  let b: int = "".getValue()
  let c: int = "".getValue
  let d: int = getValue ""
  let e: int = getValue""
  let f: int = 12345'test
  doAssert a == 44
  doAssert b == 44
  doAssert c == 44
  doAssert d == 44
  doAssert e == 44
  doAssert f == 55

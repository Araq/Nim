discard """
  cmd: "nim check --hints:off --warnings:off $file"
  action: "reject"
  nimout:'''
tstatic_constrained.nim(44, 22) Error: cannot instantiate MyOtherType [type declared in tstatic_constrained.nim(30, 5)]
got: <typedesc[int], int literal(10)>
but expected: <T: float or string, Y>
tstatic_constrained.nim(44, 22) Error: cannot instantiate MyOtherType [type declared in tstatic_constrained.nim(30, 5)]
got: <typedesc[int], int literal(10)>
but expected: <T: float or string, Y>
tstatic_constrained.nim(44, 31) Error: object constructor needs an object type [error]
tstatic_constrained.nim(44, 31) Error: expression '' has no type (or is ambiguous)
tstatic_constrained.nim(45, 22) Error: cannot instantiate MyOtherType [type declared in tstatic_constrained.nim(30, 5)]
got: <typedesc[byte], uint8>
but expected: <T: float or string, Y>
tstatic_constrained.nim(45, 22) Error: cannot instantiate MyOtherType [type declared in tstatic_constrained.nim(30, 5)]
got: <typedesc[byte], uint8>
but expected: <T: float or string, Y>
tstatic_constrained.nim(45, 34) Error: object constructor needs an object type [error]
tstatic_constrained.nim(45, 34) Error: expression '' has no type (or is ambiguous)
tstatic_constrained.nim(77, 14) Error: cannot instantiate MyType [type declared in tstatic_constrained.nim(71, 5)]
got: <typedesc[float], float64>
but expected: <T: MyConstraint, Y>
'''
"""
block:
  type 
    MyType[T; X: static T] = object
      data: T
    MyOtherType[T: float or string, Y: static T] = object

  func f[T,X](a: MyType[T,X]): MyType[T,X] =
    when T is string:
      MyType[T,X](data: a.data & X)
    else:
      MyType[T,X](data: a.data + X)

  discard MyType[int, 2](data: 1)
  discard MyType[string, "Helelello"](data: "Hmmm")
  discard MyType[int, 2](data: 1).f()
  discard MyType[string, "Helelello"](data: "Hmmm").f()
  discard MyOtherType[float, 1.3]()
  discard MyOtherType[string, "Hello"]()
  discard MyOtherType[int, 10]()
  discard MyOtherType[byte, 10u8]()

block:
  type
    Moduloable = concept m, type M
      m mod m is M
    Addable = concept a, type A
      a + a is A
    Modulo[T: Moduloable; Mod: static T] = distinct T
    ModuloAdd[T: Moduloable or Addable; Mod: static T] = distinct T
    ModuAddable = Addable or Moduloable
    ModdAddClass[T: ModuAddable; Mod: static T] = distinct T

  proc toMod[T](val: T, modVal: static T): Modulo[T, modVal] =
    mixin `mod`
    Modulo[T, modVal](val mod modVal)
  var
    a = 3231.toMod(10)
    b = 5483.toMod(10)
  discard ModuloAdd[int, 3](0)
  discard ModdAddClass[int, 3](0)

block:
  type
    MyConstraint = int or string
    MyOtherConstraint[T] = object
    MyType[T: MyConstraint; Y: static T] = object
    MyOtherType[T: MyOtherConstraint; Y: static T] = object

  var 
    a: MyType[int, 10]
    b: MyType[string, "hello"]
    c: MyType[float, 10d]
    d: MyOtherType[MyOtherConstraint[float],MyOtherConstraint[float]()]
    e: MyOtherType[MyOtherConstraint[int], MyOtherConstraint[int]()]

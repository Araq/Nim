discard """
  targets: "c"
  matrix: "--debugger:native"
  ccodecheck: "'_ZN14titaniummangle8testFuncE'"
  ccodecheck: "'_ZN14titaniummangle8testFuncE6stringN14titaniummangle3FooE'"
  ccodecheck: "'_ZN14titaniummangle8testFuncE3int7varargsI6stringE'"
  ccodecheck: "'_ZN14titaniummangle8testFuncEN14titaniummangle3BooE'"
  ccodecheck: "'_ZN14titaniummangle8testFuncE8typeDescIN14titaniummangle17EnumAnotherSampleEE'"
  ccodecheck: "'_ZN14titaniummangle8testFuncE3ptrI14uncheckedArrayI3intEE'"
  ccodecheck: "'_ZN14titaniummangle8testFuncE3setIN14titaniummangle10EnumSampleEE'"
  ccodecheck: "'_ZN14titaniummangle8testFuncE4procI6string6stringE'"
  ccodecheck: "'_ZN14titaniummangle8testFuncE3intN10Comparable10ComparableE'"
  ccodecheck: "'_ZN14titaniummangle8testFuncE3int3int'"
  ccodecheck: "'_ZN14titaniummangle8testFuncEN14titaniummangle10EnumSampleE'"
  ccodecheck: "'_ZN14titaniummangle8testFuncEN14titaniummangle17EnumAnotherSampleE'"
  ccodecheck: "'_ZN14titaniummangle8testFuncE3int3int'"
  ccodecheck: "'_ZN14titaniummangle8testFuncEN14titaniummangle10EnumSampleE'"
  ccodecheck: "'_ZN14titaniummangle8testFuncEN14titaniummangle17EnumAnotherSampleE'"
  ccodecheck: "'_ZN14titaniummangle8testFuncE5tupleI3int3intE7cstring'"
  ccodecheck: "'_ZN14titaniummangle8testFuncE5tupleI5float5floatE'"
  ccodecheck: "'_ZN14titaniummangle8testFuncE3ptrI3intE'"
  ccodecheck: "'_ZN14titaniummangle8testFuncE3ptrIN14titaniummangle3FooEE'"
  ccodecheck: "'_ZN14titaniummangle8testFuncE3ptrI3ptrI3intEE'"
  ccodecheck: "'_ZN14titaniummangle8testFuncE3refIN14titaniummangle3FooEE'"
  ccodecheck: "'_ZN14titaniummangle8testFuncE3varIN14titaniummangle3FooEE5int325int323refIN14titaniummangle3FooEE'"
  ccodecheck: "'_ZN14titaniummangle8testFuncE3varI3intE'"
  ccodecheck: "'_ZN14titaniummangle8testFuncE9openArrayI6stringE'"
  ccodecheck: "'_ZN14titaniummangle8testFuncE5arrayI7range013intE'"
  ccodecheck: "'_ZN14titaniummangle8testFuncE9ContainerI3intE'"
  ccodecheck: "'_ZN14titaniummangle8testFuncE10Container2I5int325int32E'"
  ccodecheck: "'_ZN14titaniummangle8testFuncE9ContainerI10Container2I5int325int32EE'"
"""

#When debugging this notice that if one check fails, it can be due to any of the above.

type
  Comparable = concept x, y
    (x < y) is bool

  Foo = object
    a: int32
    b: int32

  FooTuple = tuple
    a: int
    b: int

  Container[T] = object
    data: T
      
  Container2[T, T2] = object
    data: T
    data2: T2

  Boo = distinct Foo

  Coo = Foo

  Doo = Boo | Foo 

  TestProc = proc(a:string): string

type EnumSample = enum
  a, b, c

type EnumAnotherSample = enum
  a, b, c

proc testFunc(a: set[EnumSample]) = 
  echo $a

proc testFunc(a: typedesc) = 
  echo $a

proc testFunc(a: ptr Foo) = 
  echo repr a

proc testFunc(s: string, a: Coo) = 
  echo repr a

proc testFunc(s: int, a: Comparable) = 
  echo repr a

proc testFunc(a: TestProc) = 
  let b = ""
  echo repr a("")

proc testFunc(a: ref Foo) = 
  echo repr a

proc testFunc(b: Boo) = 
  echo repr b

proc testFunc(a: ptr UncheckedArray[int]) = 
  echo repr a

proc testFunc(a: ptr int) = 
  echo repr a

proc testFunc(a: ptr ptr int) = 
  echo repr a

proc testFunc(e: FooTuple, str: cstring) = 
  echo e

proc testFunc(e: (float, float)) = 
  echo e

proc testFunc(e: EnumSample) = 
  echo e

proc testFunc(e: var int) = 
  echo e

proc testFunc(e: var Foo, a, b: int32, refFoo: ref Foo) = 
  echo e

proc testFunc(xs: Container[int]) = 
  let a = 2
  echo xs

proc testFunc(xs: Container2[int32, int32]) = 
  let a = 2
  echo xs

proc testFunc(xs: Container[Container2[int32, int32]]) = 
  let a = 2
  echo xs

proc testFunc(xs: seq[int]) = 
  let a = 2
  echo xs

proc testFunc(xs: openArray[string]) = 
  let a = 2
  echo xs

proc testFunc(xs: array[2, int]) = 
  let a = 2
  echo xs

proc testFunc(e: EnumAnotherSample) = 
  echo e

proc testFunc(a, b: int) = 
  echo "hola"
  discard

proc testFunc(a: int, xs: varargs[string]) = 
  let a = 10
  for x in xs:
    echo x

proc testFunc() = 
  var a = 2
  var aPtr = a.addr
  var foo = Foo()
  let refFoo : ref Foo = new(Foo)
  let b = Foo().Boo()
  let d: Doo = Foo()
  testFunc("", Coo())
  testFunc(1, )
  testFunc(b)
  testFunc(EnumAnotherSample)
  var t = [1, 2]
  let uArr = cast[ptr UncheckedArray[int]](t.addr)
  testFunc(uArr)
  testFunc({})
  testFunc(proc(s:string): string = "test")
  testFunc(20, a.int32)
  testFunc(20, 2)
  testFunc(EnumSample.c)
  testFunc(EnumAnotherSample.c)
  testFunc((2, 1), "adios")
  testFunc((22.1, 1.2))
  testFunc(a.addr)
  testFunc(foo.addr)
  testFunc(aPtr.addr)
  testFunc(refFoo)
  testFunc(foo, 2, 1, refFoo)
  testFunc(a)
  testFunc(@[2, 1, 2])
  testFunc(@["hola"])
  testFunc(2, "hola", "adios")
  let arr: array[2, int] = [2, 1]
  testFunc(arr)
  testFunc(Container[int](data: 10))
  let c2 = Container2[int32, int32](data: 10, data2: 20)
  testFunc(c2)
  testFunc(Container[Container2[int32, int32]](data: c2))
  

testFunc()
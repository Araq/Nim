# issue #23689

type
  MyEnum {.pure.} = enum
    A, B, C, D

  B = object
    field: int

let x: MyEnum = B
doAssert $x == "B"
doAssert typeof(x) is MyEnum
doAssert x in {A, B}

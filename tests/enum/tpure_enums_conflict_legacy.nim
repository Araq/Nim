# bug #8066

when true:
  type
    MyEnum {.pure.} = enum
      valueA, valueB, valueC, valueD, amb

    OtherEnum {.pure.} = enum
      valueX, valueY, valueZ, amb


  echo valueA # MyEnum.valueA
  echo MyEnum.amb # OK.
  echo amb #[tt.Error
  ^ type mismatch: got <MyEnum | OtherEnum>
but expected one of:
proc echo(x: varargs[typed, `$$`])
  first type mismatch at position: 1
  required type for x: varargs[typed]
  but expression 'amb' is of type: None
  ambiguous identifier: 'amb' -- use one of the following:
    MyEnum.amb: MyEnum
    OtherEnum.amb: OtherEnum

expression: echo amb]#

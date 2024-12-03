discard """
  matrix: "-d:testsConciseTypeMismatch"
"""

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
  ^ type mismatch
Expression: echo amb
  [1] amb: MyEnum | OtherEnum

Expected one of (first mismatch at [position]):
[1] proc echo(x: varargs[typed, `$$`])
  ambiguous identifier: 'amb' -- use one of the following:
    MyEnum.amb: MyEnum
    OtherEnum.amb: OtherEnum]#

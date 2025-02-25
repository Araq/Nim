discard """
  cmd: "nim check --hints:off --warnings:off $file"
  action: "reject"
  nimout:'''
tinheritgenericparameter.nim(36, 15) Error: Cannot inherit from: 'MyObject'
tinheritgenericparameter.nim(36, 15) Error: Cannot inherit from: 'MyObject'
tinheritgenericparameter.nim(36, 23) Error: object constructor needs an object type [error]
tinheritgenericparameter.nim(36, 23) Error: expression '' has no type (or is ambiguous)
tinheritgenericparameter.nim(37, 15) Error: Cannot inherit from: 'int'
tinheritgenericparameter.nim(37, 15) Error: Cannot inherit from: 'int'
tinheritgenericparameter.nim(37, 23) Error: object constructor needs an object type [error]
tinheritgenericparameter.nim(37, 23) Error: expression '' has no type (or is ambiguous)
'''
"""

type
  MyObject = object
  HorzLayout[Base, T] = ref object of Base
    data: seq[T]
  VertLayout[T, Base] = ref object of Base
    data: seq[T]
  UiElement = ref object of RootObj
    a: int
  MyType[T] = ref object of RootObj
    data: seq[T]
  OtherElement[T] = ref object of T
  Child[T] = ref object of HorzLayout[UiElement, T]
  Child2[T] = ref object of VertLayout[T, UiElement]
  Child3[T] = ref object of HorzLayout[MyObject, T]
  Child4[T] = ref object of HorzLayout[int, T]
static:
  var a = Child[int](a: 300, data: @[100, 200, 300])
  assert a.a == 300
  assert a.data == @[100, 200, 300]
discard Child2[string]()
discard Child3[string]()
discard Child4[string]()
discard OtherElement[MyType[int]]()


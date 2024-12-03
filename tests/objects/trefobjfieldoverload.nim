type MyType = ref object
  a: int

proc a(val: MyType, i: int) = discard
MyType().a(100)

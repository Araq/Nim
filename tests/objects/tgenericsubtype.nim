block: # has generic field
  type
    Foo[T] = object of RootObj
      x: T
    Bar = object of Foo[int]

  proc foo(x: typedesc[Foo]) = discard

  foo(Bar)

block: # no generic field
  type
    Foo[T] = object of RootObj
    Bar = object of Foo[int]

  proc foo(x: typedesc[Foo]) = discard

  foo(Bar)

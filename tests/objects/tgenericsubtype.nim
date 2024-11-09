discard """
  disabled: true
"""

# currently broken

block:
  type
    Foo[T] = object of RootObj
      x: T
    Bar = object of Foo[int]

  proc foo(x: typedesc[Foo]) = discard

  foo(Bar)

block:
  type
    Foo[T] = object of RootObj
    Bar = object of Foo[int]

  proc foo(x: typedesc[Foo]) = discard

  foo(Bar)

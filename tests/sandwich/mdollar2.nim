import mdollar1

proc makeFoo*(x, y: int): Foo =
  Foo(x: x, y: y)

proc useFoo*(f: Foo) =
  echo "used: ", f # directly calls `foo.$` from scope

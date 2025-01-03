# issue #14729

import sets, hashes

type
  Iterable[T] = concept x
    for value in items(x):
      type(value) is T

  Foo[T] = object
    t: T

proc myToSet[T](keys: Iterable[T]): HashSet[T] =
  for x in items(keys): result.incl(x)

proc hash[T](foo: Foo[T]): Hash =
  echo "specific hash"

proc `==`[T](lhs, rhs: Foo[T]): bool =
  echo "specific equals"

let
  f = Foo[string](t: "test")
  hs = [f, f].myToSet()

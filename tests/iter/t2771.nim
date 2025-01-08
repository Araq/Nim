discard """
  targets: "c js"
"""

template t1(i: int): int=
  i+1
template t2(i: int): int=
  i+1

doAssert t1(10).t2() == 12


template it1(i: int): iterator(): int =
  iterator result(): int {.closure, gensym.} =
    yield i+1
  result

template it2(iter: iterator(): int): iterator(): int =
  iterator result(): int {.closure, gensym.} =
    yield iter()+1
  result

let x2 = it1(10).it2()

doAssert x2() == 12

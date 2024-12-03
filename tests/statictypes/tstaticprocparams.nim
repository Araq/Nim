proc consumer[T: static proc(i: int): int{.nimcall.}](i: int): int = T(i)
proc consumer(T: static proc(i: int): int{.nimcall.}, i: int): int = T(i)

proc addIt(i: int): int = i + i
proc add(i: int): int = i + i # Checks if we can use overloads
proc squareIt(i: int): int = i * i

assert consumer[addIt](10) == 20
assert consumer[add](10) == 20
assert consumer[squareIt](30) == 900
assert consumer[proc(i: int): int{.nimcall.} = i * i + i](10) == 110

assert consumer(addIt, 10) == 20
assert consumer(add, 10) == 20
assert consumer(squareIt, 30) == 900
assert consumer(proc(i: int): int{.nimcall.} = i * i + i, 10) == 110

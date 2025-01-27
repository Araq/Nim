import std/sets
template foo*[T](a: T) =
# proc foo*[T](a: T) = # works
  var s: HashSet[T]
  # echo contains(s, a) # works
  let x = a in s # BUG
  doAssert not x
  doAssert not (a in s)
  doAssert a notin s
when isMainModule: foo(1) # works

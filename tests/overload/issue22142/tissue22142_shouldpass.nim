type
  A[T] = object of RootObj
  B[T] = object
  C = object
    x:int

# change (previously true)
block:
  proc test[J;H: A[J];T: B[H]](param: T): bool = false
  proc test[T](param: B[T]): bool = true
  doAssert test(B[A[int]]()) == false
block:  # object is more specific then `T`
  proc p[H:object;T:ptr[H]](param:T):bool = false
  proc p[T](param:ptr[T]):bool= true
  var l: ptr[C]
  doAssert p(l) == false
block:
  proc p[T:A[object]](param:T):bool = false
  proc p[T](param: A[T]):bool= true
  doAssert p(A[C]()) == false
block:
  proc test[H;T: A[H]](param: T): bool = false
  proc test(param: A): bool = true
  doAssert test(A[C]()) == false

# change (previously ambiguous)
block:
  proc p[T](a: A[T]): bool = false
  proc p[T: object](a: T): bool = true
  doAssert p(A[int]()) == false
block:  # A is more specific than `object`
  proc test[T: A](param: T): bool = false
  proc test[T: object](param: T): bool = true
  doAssert test(A[int]()) == false
block:
  proc test[T: A](param: T): bool = false
  proc test(param: object): bool = true
  doAssert test(A[int]()) == false
block:
  proc test[H;T: A[H]](param: T): bool = false
  proc test(param: object): bool = true
  doAssert test(A[C]()) == false
block:
  proc test[H;T: A[B[H]]](param: T): bool = false
  proc test[T: object](param: T): bool = true
  doAssert test(A[B[int]]()) == false
block:
  #[
  This was referenced in the nim compiler source (`sumGeneric`) as a case
  that was supposed to not be ambiguous, yet it was
  ]#
  proc test[J;H:A[J]; T: A[H]](param: T): bool = false
  proc test[H;T: A[H]](param: T): bool = true
  doAssert test(A[A[C]]()) == false
block:
  proc test[J;T:A[J]](param: A[T]): bool = false
  proc test[T](param: A[T]): bool = true
  doAssert test(A[A[C]]()) == false
block:
  proc test[T](param: A[T]): bool = false
  proc test[T: object](param: A[T]): bool = true
  doAssert test(A[C]()) == true


block: #anti-regression (object is more specific then `T`)
  proc test[J;T:A[J]](param: A[T]): bool = false
  proc test(param: A[A[object]]): bool = true
  doAssert test(A[A[C]]()) == true
block: # issue #18314
  type
    A = ref object of RootObj
    B = ref object of A
    C = ref object of B

  proc foo[T: A](a: T): string = "got A"
  proc foo[T: B](b: T): string = "got B"

  var c = C()
  doAssert foo(c) == "got B"

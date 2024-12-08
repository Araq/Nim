block: # issue #18314, case 1
  type
    A = ref object of RootObj
    B = ref object of A
    C = ref object of B

  proc foo[T: A](a: T) = echo "got A"
  proc foo[T: B](b: T) = echo "got B"

  var c = C()
  foo(c)

block: # issue #18314, case 2
  type
    A = ref object of RootObj
    B = ref object of A
    C = ref object of B
    
  proc foo[T: A](a: T) = echo "got A"
  proc foo(b: B) = echo "got B"

  var c = C()
  foo(c)

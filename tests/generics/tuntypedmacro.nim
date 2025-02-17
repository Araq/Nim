block: # issue #22740
  macro foo(n: untyped): untyped = discard
  # Remove this macro to fix the problem
  macro foo(n, n2: untyped): untyped = discard

  # This one is fine
  proc test1(v: string) =
    foo >"test1"

  # This one fails to compile
  proc test2[T](v: T) = 
    foo >"test2"

  test1("hello")
  test2("hello")

block: # above simplified (yes this errored)
  proc foo[T]() =
    when false:
      >1
  foo[int]()

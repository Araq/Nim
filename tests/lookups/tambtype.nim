import ./mambtype2

block: # issue #23893
  discard default(K(0))       # works
  discard default(mambtype2.B(0))     # works
  discard default(mambtype2.K(0))     # doesn't work

block: # issue #23898, in template
  template r() =
    discard default(B(0))     # compiles
    discard default(mambtype2.B(0))   # compiles
    discard default(K(0))     # does not compile
  r()

block: # in generics
  proc foo[T]() =
    discard default(B(0))     # compiles
    discard default(mambtype2.B(0))   # compiles
    discard default(K(0))     # does not compile
  foo[int]()

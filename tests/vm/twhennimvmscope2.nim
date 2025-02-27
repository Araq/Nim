# issue #23688

when nimvm:
  proc mytest(a: int) =
    echo a
else:
  template mytest(a: untyped) =
    echo a + 42


proc xxx() =
  mytest(100) #[tt.Error
  ^ undeclared identifier: 'mytest']#
xxx()

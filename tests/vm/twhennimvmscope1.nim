# issue #23687

when nimvm:
  proc mytest(a: int) =
    echo a
else:
  template mytest(a: int) =
    echo a + 42


proc xxx() =
  mytest(100) #[tt.Error
  ^ undeclared identifier: 'mytest']#

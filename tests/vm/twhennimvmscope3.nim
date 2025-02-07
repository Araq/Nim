# issue #13450 example 3

proc bar() =
  when nimvm:
    let y = 1
  else:
    let y = 2
  discard y #[tt.Error
          ^ undeclared identifier: 'y']#
bar()

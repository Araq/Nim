const
  a = (var x = 3; x)
  # should we allow this?
  b = x #[tt.Error
      ^ undeclared identifier: 'x']#

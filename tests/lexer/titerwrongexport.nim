# issue #19063

iterator items[T]*(s: seq[T]): T = #[tt.Error
                 ^ invalid indentation; an export marker '*' follows the declared identifier]#
  for i in  system.items(s):
    yield i

proc `++`(n: var int) =
  n += 1

var a: int32 = 15

++a #[tt.Error
^ type mismatch: got <int32>]#

echo a

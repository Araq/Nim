template v[T](c: SomeOrdinal): T = T(c)
discard v[int, char]('A') #[tt.Error
                    ^ type mismatch: got <char>
but expected one of:
template v[T](c: SomeOrdinal): T
  first type mismatch at position: 2 in generic parameters
  required type for SomeOrdinal: SomeOrdinal
  but expression 'char' is of type: char

expression: v[int, char]('A')]#

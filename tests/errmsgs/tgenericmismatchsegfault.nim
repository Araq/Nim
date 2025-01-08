discard """
  matrix: "-d:testsConciseTypeMismatch"
"""

template v[T](c: SomeOrdinal): T = T(c)
discard v[int, char]('A') #[tt.Error
                    ^ type mismatch
Expression: v[int, char]('A')
  [1] 'A': char

Expected one of (first mismatch at [position]):
[2] template v[T](c: SomeOrdinal): T
  generic parameter mismatch, expected SomeOrdinal but got 'char' of type: char]#

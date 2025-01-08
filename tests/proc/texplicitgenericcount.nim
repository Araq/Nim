discard """
  cmd: "nim check -d:testsConciseTypeMismatch $file"
"""

proc foo[T, U](x: T, y: U): (T, U) = (x, y)

let x = foo[int](1, 2) #[tt.Error
                ^ type mismatch
Expression: foo[int](1, 2)
  [1] 1: int literal(1)
  [2] 2: int literal(2)

Expected one of (first mismatch at [position]):
[2] proc foo[T, U](x: T; y: U): (T, U)
  missing generic parameter: U]#
let y = foo[int, float, string](1, 2) #[tt.Error
                               ^ type mismatch
Expression: foo[int, float, string](1, 2)
  [1] 1: int literal(1)
  [2] 2: int literal(2)

Expected one of (first mismatch at [position]):
[3] proc foo[T, U](x: T; y: U): (T, U)
  extra generic param given]#

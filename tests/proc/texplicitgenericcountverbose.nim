discard """
  cmd: "nim check $file"
"""

proc foo[T, U](x: T, y: U): (T, U) = (x, y)

let x = foo[int](1, 2) #[tt.Error
                ^ type mismatch: got <int literal(1), int literal(2)>
but expected one of:
proc foo[T, U](x: T; y: U): (T, U)
  first type mismatch at position: 2 in generic parameters
  missing generic parameter: U

expression: foo[int](1, 2)]#
let y = foo[int, float, string](1, 2) #[tt.Error
                               ^ type mismatch: got <int literal(1), int literal(2)>
but expected one of:
proc foo[T, U](x: T; y: U): (T, U)
  first type mismatch at position: 3 in generic parameters
  extra generic param given

expression: foo[int, float, string](1, 2)]#

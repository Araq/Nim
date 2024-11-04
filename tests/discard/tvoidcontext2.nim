proc foo(x: var string) =
  x = "hello"

proc bar(): string =
  foo(result)
  "invalid" #[tt.Error
  ^ cannot use implicit return, the `result` symbol was used in 'bar']#

echo bar()

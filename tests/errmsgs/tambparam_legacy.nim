import mambparam2, mambparam3

echo test #[tt.Error
^ type mismatch: got <string | string>
but expected one of:
proc echo(x: varargs[typed, `$$`])
  first type mismatch at position: 1
  required type for x: varargs[typed]
  but expression 'test' is of type: None
  ambiguous identifier: 'test' -- use one of the following:
    mambparam1.test: string
    mambparam3.test: string

expression: echo test]#

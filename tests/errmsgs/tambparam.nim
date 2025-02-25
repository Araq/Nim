discard """
  matrix: "-d:testsConciseTypeMismatch"
"""

import mambparam2, mambparam3

echo test #[tt.Error
^ type mismatch
Expression: echo test
  [1] test: string | string

Expected one of (first mismatch at [position]):
[1] proc echo(x: varargs[typed, `$$`])
  ambiguous identifier: 'test' -- use one of the following:
    mambparam1.test: string
    mambparam3.test: string]#

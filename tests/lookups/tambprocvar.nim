discard """
  action: reject
  cmd: "nim check $file"
  nimout: '''
tambprocvar.nim(15, 11) Error: ambiguous identifier: 'foo' -- use one of the following:
  tambprocvar.foo: proc (x: int){.noSideEffect, gcsafe.}
  tambprocvar.foo: proc (x: float){.noSideEffect, gcsafe.}
'''
"""

block:
  proc foo(x: int) = discard
  proc foo(x: float) = discard

  let x = foo

block:
  let x = `+` #[tt.Error
          ^ ambiguous identifier: '+' -- use one of the following:]#

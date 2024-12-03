discard """
  cmd: "nim check $options $file" # use check to assure error is pre-codegen
  matrix: "; --backend:js" # backend shouldn't matter but at least check js
"""

proc foo(x: int) = discard
proc foo(x: float) = discard

{.emit: ["// ", foo].} #[tt.Error
                ^ ambiguous identifier: 'foo' -- use one of the following:
  tambiguousemit.foo: proc (x: int){.noSideEffect, gcsafe.}
  tambiguousemit.foo: proc (x: float){.noSideEffect, gcsafe.}]#

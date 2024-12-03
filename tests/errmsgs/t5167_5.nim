discard """
cmd: "nim check --mm:refc $file"
"""
# issue #11942
discard newSeq[system]() #[tt.Error
               ^ expression 'system' has no type (or is ambiguous)]#

# issue #5167
template t[B]() =
  echo "foo1"

macro m[T]: untyped = nil

proc bar(x: proc (x: int)) =
  echo "bar"

let x = t #[tt.Error
        ^ 't' has unspecified generic parameters]#
bar t #[tt.Error
^ type mismatch: got <template [*missing parameters*]()>]#

let y = m #[tt.Error
        ^ 'm' has unspecified generic parameters]#
bar m #[tt.Error
^ type mismatch: got <macro [*missing parameters*](): untyped{.noSideEffect, gcsafe.}>]#

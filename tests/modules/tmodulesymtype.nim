discard """
cmd: "nim check $file"
"""

# bug #19225
import std/sequtils
sequtils #[tt.Error
^ expression has no type: sequtils]#
proc foo() =
  block: #[tt.Error
  ^ expression has no type: block:
  sequtils]#
    sequtils

foo()

# issue #23399
when isMainModule:
  sequtils #[tt.Error
  ^ expression has no type: sequtils]#

discard

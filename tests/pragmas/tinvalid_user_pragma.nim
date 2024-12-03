discard """
cmd: "nim check $file"
"""

{.pragma test: foo.} #[tt.Error
^ invalid pragma:  {.pragma, test: foo.} ]#

{.pragma: 1.} #[tt.Error
^ invalid pragma:  {.pragma: 1.} ]#

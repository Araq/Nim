discard """
cmd: "nim check $file"
"""

type
  Test = enum
    A = 9.0 #[tt.Error
        ^ ordinal type expected; given: float]#

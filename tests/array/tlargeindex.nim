discard """
  cmd: "nim check --hints:off $file"
"""

# issue #17163
var e: array[int32, byte] #[tt.Error
             ^ index type 'int32' for array is too large]#
var f: array[uint32, byte] #[tt.Error
             ^ index type 'uint32' for array is too large]#
var g: array[int64, byte] #[tt.Error
             ^ index type 'int64' for array is too large]#
var h: array[uint64, byte] #[tt.Error
             ^ index type 'uint64' for array is too large]#

# crash in issue #23204
proc y[N](): array[N, int] = default(array[N, int]) #[tt.Error
                                           ^ index type 'int' for array is too large]#
discard y[int]()

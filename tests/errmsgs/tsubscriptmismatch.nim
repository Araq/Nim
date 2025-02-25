discard """
  matrix: "-d:testsConciseTypeMismatch"
  nimout: '''
[1] proc `[]`[T; U, V: Ordinal](s: openArray[T]; x: HSlice[U, V]): seq[T]
'''
"""

type Foo = object
let x = Foo()
discard x[1] #[tt.Error
         ^ type mismatch]#

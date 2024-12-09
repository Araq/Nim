block: # issue #13184
  type
    TypeClass = uint | enum | int
    ArrayAlias[I: TypeClass] = array[I, int]

  proc test[I: TypeClass](points: ArrayAlias[I]) =
    discard

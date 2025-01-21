# issue #24631

type
  V[d: static bool] = object
    l: int

template y(): V[false] = V[false](l: 0)
discard y()

discard """
  matrix: "--skipParentCfg"
"""

# issue #24631

type
  V[d: static bool] = object
    l: int

template y(): V[false] = V[false](l: 0)
discard y()

template z(): V[false] = cast[V[false]](V[false](l: 0))
discard z()

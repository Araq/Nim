import sets

proc initH*[V]: HashSet[V] =
  result = initHashSet[V]()

proc foo*[V](h: var HashSet[V], c: seq[V]) =
  h = h + c.toHashSet()

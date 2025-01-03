import sets, sequtils

proc dedupe*[T](arr: openArray[T]): seq[T] =
  arr.toHashSet.toSeq

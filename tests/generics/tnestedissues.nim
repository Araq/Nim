block: # issue #23568
  type G[T] = object
    j: T
  proc s[T](u: int) = discard
  proc s[T]() = discard
  proc c(e: int | int): G[G[G[int]]] = s[G[G[int]]]()
  discard c(0)

import std/options

block: # issue #23310
  type
    BID = string or uint64
    Future[T] = ref object of RootObj
      internalValue: T
    InternalRaisesFuture[T] = ref object of Future[T]
  proc newInternalRaisesFutureImpl[T](): InternalRaisesFuture[T] =
    let fut = InternalRaisesFuture[T]()
  template newFuture[T](): auto =
    newInternalRaisesFutureImpl[T]()
  proc problematic(blockId: BID): Future[Option[seq[int]]] =
    let resultFuture = newFuture[Option[seq[int]]]()
    return resultFuture
  let x = problematic("latest")

# original example used queues
import deques

type
  QueueContainer*[T] = object
    q: ref Deque[T]

proc init*[T](c: var QueueContainer[T]) =
  new(c.q)
  c.q[] = initDeque[T](64)

proc addToQ*[T](c: var QueueContainer[T], item: T) =
  c.q[].addLast(item)

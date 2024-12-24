discard """
  matrix: "--mm:orc"
"""

# bug #20993

type
  Dual[int] = object # must be generic (even if fully specified)
    p: int
proc D(p: int): Dual[int] = Dual[int](p: p)
proc `+`(x: Dual[int], y: Dual[int]): Dual[int] = D(x.p + y.p)

type
  Tensor[T] = object
    buf: seq[T]
proc newTensor*[T](s: int): Tensor[T] = Tensor[T](buf: newSeq[T](s))
proc `[]`*[T](t: Tensor[T], idx: int): T = t.buf[idx]
proc `[]=`*[T](t: var Tensor[T], idx: int, val: T) = t.buf[idx] = val

proc `+.`[T](t1, t2: Tensor[T]): Tensor[T] =
  let n = t1.buf.len
  result = newTensor[T](n)
  for i in 0 ..< n:
    result[i] = t1[i] + t2[i]

proc toTensor*[T](a: sink seq[T]): Tensor[T] =
  ## This breaks it: Using `T` instead makes it work
  type U = typeof(a[0])
  var t: Tensor[U] = default(Tensor[U]) # Tensor[T] works
  t.buf = a
  result = t

proc loss() =
  var B = toTensor(@[D(123)])
  let a = toTensor(@[D(-10)])
  B = B +. a
  doAssert B[0].p == 113, "I want to be 113, but I am " & $B[0].p

loss()



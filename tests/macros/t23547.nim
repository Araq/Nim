# https://github.com/nim-lang/Nim/issues/23547

type
  A[T] = object
    x: T

proc mulCheckSparse[F](dummy: var A[F], xmulchecksparse: static A[F]) =
  static:
    echo "mulCheckSparse: ", typeof(dummy), ", ", typeof(xmulchecksparse) # when generic params not specified: A[system.int], A

template sumImpl(xsumimpl: typed) =
  static:
    echo "sumImpl: ", typeof(xsumimpl) # A
  var a = A[int](x: 55)
  mulCheckSparse(a, xsumimpl) # fails here

proc sum[T](xsum: static T) =
  static:
    echo "sum: ", typeof(xsum) # A[system.int]
  sumImpl(xsum)

const constA = A[int](x : 100)
sum[A[int]](constA)

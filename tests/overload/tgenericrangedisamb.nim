# issue #24708

type Matrix[m, n: static int] = array[m * n, float]

func `[]`(A: Matrix, i, j: int): float =
  A[A.n * i + j]

func `[]`(A: var Matrix, i, j: int): var float =
  A[A.n * i + j]

func `*`[m, n, p: static int](A: Matrix[m, n], B: Matrix[n, p]): Matrix[m, p] =
  for i in 0 ..< m:
    for k in 0 ..< p:
      for j in 0 ..< n:
        result[i, k] += A[i, j] * B[j, k]

func square[n: static int](A: Matrix[n, n]): Matrix[n, n] =
  A * A

let A: Matrix[2, 2] = [-1, 1, 0, -1]
doAssert square(A) == [1.0, -2.0, 0.0, 1.0]

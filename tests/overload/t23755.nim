type
  BigInt[bits: static int] = object
    limbs: array[8, uint64]

block:
  proc view[N](a: array[N, uint64]) =
    discard

  proc view[N](a: var array[N, uint64]) =
    discard

  var r: BigInt[64]
  r.limbs.view()


type Limbs[N: static int] = array[N, uint64]

block:
  proc view(a: Limbs) =
    discard

  proc view(a: var Limbs) =
    discard

  var r: BigInt[64]
  r.limbs.view()


block:
  type IntArray[N: static[int]] = array[N, int]

  proc p[T](a: IntArray[T]): bool= true
  proc p(a: IntArray[5]): bool= false

  var s: IntArray[5]
  doAssert s.p == false

block:
  type IntArray[N: static[int]] = array[N, int]

  proc `$`(a: IntArray): string =
    return "test"

  var s: IntArray[5] = [1,1,1,1,1]
  doAssert `$`(s) == "test"

block: 
  proc p[n:static[int]](a: array[n, char]):bool=true
  proc p[T, IDX](a: array[IDX, T]):bool=false

  var g: array[32, char]
  doAssert p(g)

block:  # issue #23823
  func p[N,T](a, b: array[N,T]) =
    discard

  func p[N: static int; T](x, y: array[N, T]) =
    discard

  var a: array[5, int]
  p(a,a)

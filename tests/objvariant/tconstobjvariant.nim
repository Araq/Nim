# This is a sample code, the first echo statement prints out the error
type
  A = object
    case w: uint8
    of 1:
      n: int
    else:
      other: string

const
  a = A(w: 1, n: 5)

proc foo =

  let c = [a]
  doAssert c[0].n == 5

foo()
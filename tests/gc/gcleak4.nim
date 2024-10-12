discard """
  outputsub: "no leak: "
  retries: 2
"""

type
  TExpr {.inheritable.} = object ## abstract base class for an expression
  PLiteral = ref TLiteral
  TLiteral = object of TExpr
    x: int
    op1: string
  TPlusExpr = object of TExpr
    a, b: ref TExpr
    op2: string

method eval(e: ref TExpr): int {.base.} =
  # override this base method
  quit "to override!"

method eval(e: ref TLiteral): int = return e.x

method eval(e: ref TPlusExpr): int =
  # watch out: relies on dynamic binding
  return eval(e.a) + eval(e.b)

proc newLit(x: int): ref TLiteral =
  new(result)
  result.x = x
  result.op1 = $getOccupiedMem()

proc newPlus(a, b: sink(ref TExpr)): ref TPlusExpr =
  new(result)
  result.a = a
  result.b = b
  result.op2 = $getOccupiedMem()

const Limit = when compileOption("gc", "markAndSweep") or compileOption("gc", "boehm"): 5*1024*1024 else: 500_000

for i in 0..50_000:
  var s: array[0..11, ref TExpr]
  for j in 0..high(s):
    s[j] = newPlus(newPlus(newLit(j), newLit(2)), newLit(4))
    if eval(s[j]) != j+6:
      quit "error: wrong result"
  if getOccupiedMem() > Limit: quit("still a leak!")

echo "no leak: ", getOccupiedMem()

discard """
  output: '''
L
L
L
L
B
B
B
B
'''
"""

# issue #18202

type
  R = object
  S = object
  U = R | S

  L = object
  B = object
  C = B | L

proc f(n: L, q: R | S) = echo "L"
proc f(n: B, q: R | S) = echo "B"

proc g(n: C, q: R | S) = echo (when n is L: "L" else: "B")

proc h(n: L, q: U) = echo "L"
proc h(n: B, q: U) = echo "B"

proc j(n: C, q: U) = echo (when n is L: "L" else: "B")

proc e(n: B | L, a: R) =
  template t(operations: untyped, fn: untyped) = fn(n, operations)

  # Work as expected
  t(a, f)
  t(a, g)
  t(a, j)

  # Error: type mismatch: got <R, proc [*missing parameters*](n: B, q: U) | proc [*missing parameters*](n: L, q: U)>
  t(a, h)

e(L(), R())
e(B(), R())

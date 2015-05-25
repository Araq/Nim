discard """
  output: "10\N10\N1\N2\N3\N15"
"""

proc test(x: proc (a, b: int): int) =
  echo x(5, 5)

test(proc (a, b): auto = a + b)

test do (a, b) -> auto: a + b

proc foreach[T](s: seq[T], body: proc(x: T)) =
  for e in s:
    body(e)

foreach(@[1,2,3]) do (x):
  echo x

proc foo =
  let x = proc (a, b: int): auto = a + b
  echo x(5, 10)

foo()

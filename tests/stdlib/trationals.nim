discard """
  matrix: "--mm:refc; --mm:orc"
"""

import std/[rationals, math]
import std/assertions

template main() =
  var
    z = Rational[int](num: 0, den: 1)
    o = initRational(num = 1, den = 1)
    a = initRational(1, 2)
    u = 3u // 2
    b = -1 // -2
    m1 = -1 // 1
    tt = 10 // 2

  doAssert a == a
  doAssert a - a == z
  doAssert a + b == o
  doAssert a / b == o
  doAssert a * b == 1 // 4
  doAssert 3 / a == 6 // 1
  doAssert a / 3 == 1 // 6
  doAssert tt * z == z
  doAssert 10 * a == tt
  doAssert a * 10 == tt
  doAssert tt / 10 == a
  doAssert a - m1 == 3 // 2
  doAssert a + m1 == -1 // 2
  doAssert m1 + tt == 16 // 4
  doAssert m1 - tt == 6 // -1

  doAssert z < o
  doAssert z <= o
  doAssert z == z
  doAssert cmp(z, o) < 0
  doAssert cmp(o, z) > 0

  doAssert o == o
  doAssert o >= o
  doAssert not(o > o)
  doAssert cmp(o, o) == 0
  doAssert cmp(z, z) == 0
  doAssert hash(o) == hash(o)

  doAssert a == b
  doAssert a >= b
  doAssert not(b > a)
  doAssert cmp(a, b) == 0
  doAssert hash(a) == hash(b)

  var x = 1 // 3

  x *= 5 // 1
  doAssert x == 5 // 3
  x += 2 // 9
  doAssert x == 17 // 9
  x -= 9 // 18
  doAssert x == 25 // 18
  x /= 1 // 2
  doAssert x == 50 // 18

  var y = 1 // 3

  y *= 4
  doAssert y == 4 // 3
  y += 5
  doAssert y == 19 // 3
  y -= 2
  doAssert y == 13 // 3
  y /= 9
  doAssert y == 13 // 27

  doAssert toRational(5) == 5 // 1
  doAssert abs(toFloat(y) - 0.4814814814814815) < 1.0e-7
  doAssert toInt(z) == 0

  when sizeof(int) == 8:
    doAssert toRational(0.98765432) == 2111111029 // 2137499919
    doAssert toRational(PI) == 817696623 // 260280919
  when sizeof(int) == 4:
    doAssert toRational(0.98765432) == 80 // 81
    doAssert toRational(PI) == 355 // 113

  doAssert toRational(0.1) == 1 // 10
  doAssert toRational(0.9) == 9 // 10

  doAssert toRational(0.0) == 0 // 1
  doAssert toRational(-0.25) == 1 // -4
  doAssert toRational(3.2) == 16 // 5
  doAssert toRational(0.33) == 33 // 100
  doAssert toRational(0.22) == 11 // 50
  doAssert toRational(10.0) == 10 // 1

  doAssert (1 // 1) div (3 // 10) == 3
  doAssert (-1 // 1) div (3 // 10) == -3
  doAssert (3 // 10) mod (1 // 1) == 3 // 10
  doAssert (-3 // 10) mod (1 // 1) == -3 // 10
  doAssert floorDiv(1 // 1, 3 // 10) == 3
  doAssert floorDiv(-1 // 1, 3 // 10) == -4
  doAssert floorMod(3 // 10, 1 // 1) == 3 // 10
  doAssert floorMod(-3 // 10, 1 // 1) == 7 // 10

  when sizeof(int) == 8:
    doAssert almostEqual(PI.toRational.toFloat, PI)

  # unsigned
  doAssert u == u
  doAssert u + u == 3u // 1
  doAssert 3u.toRational - u == u
  doAssert u * 2 == 3u // 1



static: main()
main()

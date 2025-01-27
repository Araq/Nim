discard """
  output: '''
3
30
true
'''
"""


# bug #798
template t012{(0|1|2){x}}(x: untyped): untyped = x+1
let z = 1
# outputs 3 thanks to fixpoint iteration:
echo z


template arithOps: untyped = (`+` | `-` | `*`)
template testOr{ (arithOps{f})(a, b) }(a, b, f: untyped): untyped =
  {.noRewrite.}:
    f(a mod 10, b)

let xx = 10
echo 10*xx

template t{x = (~x){y} and (~x){z}}(x, y, z: bool): typed =
  x = y
  if x: x = z

var
  a = true
  b = true
  c = false
a = b and a
echo a

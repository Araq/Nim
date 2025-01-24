discard """
$nimsuggest --tester $file
>outline $file
outline;;skProc;;t21923.foo;;proc (x: int){.gcsafe, raises: <inferred> [].};;/home/blue/Nim/nimsuggest/tests/t21923.nim;;8;;5;;"";;100
outline;;skTemplate;;t21923.foo2;;;;/home/blue/Nim/nimsuggest/tests/t21923.nim;;11;;9;;"";;100
"""

proc foo(x: int) =
  echo "foo"

template foo2(x: int) =
  echo "foo2"

foo(12)
foo2(12)

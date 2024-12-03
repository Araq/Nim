discard """
  output: '''
-1
8
'''
  ccodecheck: "'console.log(-1); function fac__tcodegendeclproc_u1(n_p0)'"
"""
proc fac(n: int): int {.codegenDecl: "console.log(-1); function $2($3)".} =
  return n

echo fac(8)

discard """
  outputsub: '''Error: expression expected, but found '[EOF]' 45'''
"""

# feature request #1473
import macros

macro test(text: string): untyped =
  try:
    result = parseExpr(text.strVal)
  except ValueError:
    result = newLit getCurrentExceptionMsg()

const
  valid = 45
  a = test("foo&&")
  b = test("valid")
  c = test("\"") # bug #2504

echo a, " ", b

static:
  # Issue #9918
  discard parseStmt("echo(1+1);")

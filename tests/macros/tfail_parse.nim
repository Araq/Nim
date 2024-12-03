discard """
action: "reject"
cmd: "nim check $file"
errormsg: "expected expression, but got multiple statements [ValueError]"
file: "macros.nim"
"""

import macros
static:
  discard parseStmt("'")
  discard parseExpr("'")
  discard parseExpr("""
proc foo()
proc foo() = discard
""")

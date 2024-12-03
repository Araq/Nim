discard """
  matrix: "--warningAsError:UnreachableCode"
"""

proc test(): bool =
  block okay:
    if true: break okay
    return false

  return true # Line 7 is here

doAssert test()

discard """
  errormsg: "type mismatch: got <proc (x: int){.nimcall, raises: <inferred> [], gcsafe.}>"
  line: 12
"""

proc ugh[T](x: T) {.nimcall.} =
  echo "ugha"


proc takeCdecl(p: proc (x: int) {.cdecl.}) = discard

takeCDecl(ugh[int])

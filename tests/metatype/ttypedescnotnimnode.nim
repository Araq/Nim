discard """
  errormsg: "type mismatch: got <NimNode> but expected 'typedesc'"
  line: 14
"""

import macros

# This is the same example as ttypeselectors but using a proc instead of a macro
# Instead of type mismatch for macro, proc just failed with internal error: getTypeDescAux(tyNone)
# https://github.com/nim-lang/Nim/issues/7231

proc getBase2*(bits: static[int]): typedesc =
  if bits == 128:
    result = newTree(nnkBracketExpr, ident("MpUintBase"), ident("uint64"))
  else:
    result = newTree(nnkBracketExpr, ident("MpUintBase"), ident("uint32"))

type
  MpUint2*[bits: static[int]] = getbase2(bits)
# technically shouldn't error until instantiation, so instantiate it
var x: MpUint2[123]

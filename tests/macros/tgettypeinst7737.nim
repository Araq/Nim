discard """
  nimout: '''
seq[int]
CustomSeq[int]
'''
"""

import macros, typetraits, sequtils

block: # issue #7737 original
  type
    CustomSeq[T] = object
      data: seq[T]

  proc getSubType(T: NimNode): NimNode =
    echo getTypeInst(T).repr
    result = getTypeInst(T)[1]

  macro typed_helper(x: varargs[typed]): untyped =
    let foo = getSubType(x[0])
    result = quote do: discard

  macro untyped_heavylifting(x: varargs[untyped]): untyped =
    var containers = nnkArgList.newTree()
    for arg in x:
      case arg.kind:
      of nnkInfix:
        if eqIdent(arg[0], "in"):
          containers.add arg[2]
      else:
        discard
    result = quote do:
      typed_helper(`containers`)
  var a, b, c: seq[int]
  untyped_heavylifting z in c, x in a, y in b:
    discard
  ## The following gives me CustomSeq instead
  ## of CustomSeq[int] in getTypeInst
  var u, v, w: CustomSeq[int]
  untyped_heavylifting z in u, x in v, y in w:
    discard

block: # issue #7737 comment
  type
    CustomSeq[T] = object
      data: seq[T]
  # when using just one argument, `foo` and `bar` should be exactly
  # identical.
  macro foo(arg: typed): string =
    result = newLit(arg.getTypeInst.repr)
  macro bar(args: varargs[typed]): untyped =
    result = newTree(nnkBracket)
    for arg in args:
      result.add newLit(arg.getTypeInst.repr)
  var
    a: seq[int]
    b: CustomSeq[int]
  doAssert foo(a) == "seq[int]"
  doAssert bar(a) == ["seq[int]"]
  doAssert foo(b) == "CustomSeq[int]"
  doAssert bar(b) == ["CustomSeq[int]"]

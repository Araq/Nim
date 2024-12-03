discard """
  matrix: "--mm:arc; --mm:refc"
  output: '''
HELLO WORLD!
'''
"""




type
  TNode* {.inheritable.} = object
  PNode* = ref TNode

  PNodeFoo* = ref object of TNode

  TSomethingElse = object
  PSomethingElse = ref TSomethingElse

method foo(a: PNode, b: PSomethingElse) {.base.} = discard
method foo(a: PNodeFoo, b: PSomethingElse) = discard




# tmproto
type
  Obj1 {.inheritable.} = ref object
  Obj2 = ref object of Obj1

method beta(x: Obj1): int {.base.}

proc delta(x: Obj2): int =
  beta(x)

method beta(x: Obj2): int

proc alpha(x: Obj1): int =
  beta(x)

method beta(x: Obj1): int = 1
method beta(x: Obj2): int = 2

proc gamma(x: Obj1): int =
  beta(x)

doAssert alpha(Obj1()) == 1
doAssert gamma(Obj1()) == 1
doAssert alpha(Obj2()) == 2
doAssert gamma(Obj2()) == 2
doAssert delta(Obj2()) == 2



# tsimmeth
import strutils
var x = "hello world!".toLowerAscii.toUpperAscii
x.echo()



# trecmeth
# Note: We only compile this to verify that code generation
# for recursive methods works, no code is being executed
type Obj = ref object of RootObj

# Mutual recursion
method alpha(x: Obj) {.base.}
method beta(x: Obj) {.base.}

method alpha(x: Obj) =
  beta(x)

method beta(x: Obj) =
  alpha(x)

# Simple recursion
method gamma(x: Obj) {.base.} =
  gamma(x)

discard """
  matrix: "--mm:arc; --mm:refc"
  output: '''
newDNode base
'''
"""

type
  SNodeAny = ref object of RootObj
  SNode[T] = ref object of SNodeAny
    m: T
  DNode[T] = ref object

method getStr(s: SNode[float]): string {.base.} = "blahblah"

method newDNode(s: SNodeAny) {.base.} =
  echo "newDNode base"

method newDNode[T](s: SNode[T]) =
  echo "newDNode generic"

let m = SNode[float]()
let s = SNodeAny(m)
newDnode(s)
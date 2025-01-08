discard """
  matrix: "--mm:refc; --mm:orc"
"""

# test a simple yet highly efficient set of strings

type
  TRadixNodeKind = enum rnLinear, rnFull, rnLeaf
  PRadixNode = ref TRadixNode
  TRadixNode {.inheritable.} = object
    kind: TRadixNodeKind
  TRadixNodeLinear = object of TRadixNode
    len: uint8
    keys: array[0..31, char]
    vals: array[0..31, PRadixNode]
  TRadixNodeFull = object of TRadixNode
    b: array[char, PRadixNode]
  TRadixNodeLeaf = object of TRadixNode
    s: string
  PRadixNodeLinear = ref TRadixNodeLinear
  PRadixNodeFull = ref TRadixNodeFull
  PRadixNodeLeaf = ref TRadixNodeLeaf

proc search(r: PRadixNode, s: string): PRadixNode =
  result = default(PRadixNode)
  var r = r
  var i = 0
  while r != nil:
    case r.kind
    of rnLinear:
      var x = PRadixNodeLinear(r)
      for j in 0..int(x.len)-1:
        if x.keys[j] == s[i]:
          if s[i] == '\0': return r
          r = x.vals[j]
          inc(i)
          break
      break # character not found
    of rnFull:
      var x = PRadixNodeFull(r)
      var y = x.b[s[i]]
      if s[i] == '\0':
        return if y != nil: r else: nil
      r = y
      inc(i)
    of rnLeaf:
      var x = PRadixNodeLeaf(r)
      var j = 0
      while true:
        if x.s[j] != s[i]: return nil
        if s[i] == '\0': return r
        inc(j)
        inc(i)

proc contains*(r: PRadixNode, s: string): bool =
  return search(r, s) != nil

proc testOrIncl*(r: var PRadixNode, s: string): bool =
  result = false

proc incl*(r: var PRadixNode, s: string) = discard testOrIncl(r, s)

proc excl*(r: var PRadixNode, s: string) =
  var x = search(r, s)
  if x == nil: return
  case x.kind
  of rnLeaf: PRadixNodeLeaf(x).s = ""
  of rnFull: PRadixNodeFull(x).b['\0'] = nil
  of rnLinear:
    var x = PRadixNodeLinear(x)
    for i in 0..int(x.len)-1:
      if x.keys[i] == '\0':
        swap(x.keys[i], x.keys[int(x.len)-1])
        dec(x.len)
        break

var
  root: PRadixNode


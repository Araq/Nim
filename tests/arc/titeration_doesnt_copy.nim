discard """
  output: "true"
"""

type
  Idx = object
    i: int
  Node = object
    n: int
    next: seq[Idx]
  FooBar = object
    s: seq[Node]

proc `=copy`(dest: var Idx; source: Idx) {.error.}
proc `=copy`(dest: var Node; source: Node) {.error.}
proc `=copy`(dest: var FooBar; source: FooBar) {.error.}

proc doSomething(ss: var seq[int], s: FooBar) =
  for i in 0 .. s.s.len-1:
    for elm in items s.s[i].next:
      ss.add s.s[elm.i].n

when isMainModule:
  const foo = FooBar(s: @[Node(n: 1, next: @[Idx(i: 0)])])
  var ss: seq[int]
  doSomething(ss, foo)
  echo ss == @[1]

from sequtils import mapIt
from strutils import join

proc toBinSeq*(b: uint8): seq[uint8] =
  ## Return binary sequence from each bits of uint8.
  runnableExamples:
    from sequtils import repeat
    doAssert 0'u8.toBinSeq == 0'u8.repeat(8)
    doAssert 0b1010_1010.toBinSeq == @[1'u8, 0, 1, 0, 1, 0, 1, 0]
  result = @[]
  var c = b
  for i in 1..8:
    result.add (uint8(c and 0b1000_0000) shr 7)
    c = c shl 1

proc toBinString*(data: openArray[uint8], col: int): string =
  ## Return binary string from each bits of uint8.
  runnableExamples:
    doAssert @[0b0000_1111'u8, 0b1010_1010].toBinString(8) == "0000111110101010"
    doAssert @[0b1000_0000'u8, 0b0000_0000].toBinString(1) == "10"
  result = ""
  for b in items data.mapIt(it.toBinSeq.mapIt(it.`$`[0].char)):
    for i, c in b:
      if i < col:
        result.add c

doAssert @[0b0000_1111'u8, 0b1010_1010].toBinString(8) == "0000111110101010"
doAssert @[0b1000_0000'u8, 0b0000_0000].toBinString(1) == "10"

block: # bug #23982
  iterator `..`(a, b: ptr int16): ptr int16 = discard
  var a: seq[int16] #; let p = a[0].addr
  var b: seq[ptr int16]

  try:
    for x in a[0].addr .. b[1]: # `p .. b[1]` works
      discard
  except IndexDefect:
    discard

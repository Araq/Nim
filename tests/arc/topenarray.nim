discard """
  input: "hi"
  output: '''
hi
Nim
'''
  matrix: "--gc:arc -d:useMalloc; --gc:arc"
"""
{.experimental: "views".}

block: # bug 18627
  proc setPosition(params: openArray[string]) =
    for i in params.toOpenArray(0, params.len - 1):
      echo i

  proc uciLoop() =
    let params = @[readLine(stdin)]
    setPosition(params)

  uciLoop()

  proc uciLoop2() =
    let params = @["Nim"]
    for i in params.toOpenArray(0, params.len - 1):
      echo i
  uciLoop2()

when defined(nimPreviewSlimSystem):
  import std/assertions

block: # bug #20954
  block:
    doAssertRaises(IndexDefect):
      var v: array[10, int]

      echo len(toOpenArray(v, 20, 30))

  block:
    doAssertRaises(IndexDefect):
      var v: seq[int]

      echo len(toOpenArray(v, 20, 30))

# bug #20422

proc f(a: var string) =
  var v = a.toOpenArray(1, 3)
  v[0] = 'a'

var a = "Hello"
f(a)
doAssert a == "Hallo"

# bug #22132
block:
  func foo[T](arr: openArray[T], idx: int = arr.low): string =
    doAssert idx == 0
    return $arr

  let bug = ["0", "c", "a"]

  let str = foo(bug)

  const expected = """["0", "c", "a"]"""
  doAssert str == expected

  const noBugConst = ["0", "c", "a"]
  doAssert foo(noBugConst) == expected
  let noBugSeq = @["0", "c", "a"]
  doAssert foo(noBugSeq) == expected

block: # bug #20865
  var p: pointer
  var x: array[0, int]
  # echo toOpenArray(x, 0, 1)[0] # Raises IndexDefect
  doAssertRaises(IndexDefect):
    echo toOpenArray(cast[ptr array[0, int]](p)[], 0, 1)[0] # Does not raise IndexDefect

block: # bug #20987
  var v: array[1, byte]

  var p = cast[ptr array[0, byte]](addr v)

  doAssertRaises(IndexDefect):
    echo toOpenArray(p[], 1, 2)


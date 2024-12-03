discard """
  targets: "c js"
  matrix: "--cursorinference:on; --cursorinference:off"
"""

block:
  type
    X = object
      s: string

  proc `=copy`(x: var X, y: X) =
    x.s = "copied " & y.s

  proc `=sink`(x: var X, y: X) =
    `=destroy`(x)
    wasMoved(x)
    x.s = "moved " & y.s

  proc consume(x: sink X) =
    discard x.s

  proc main =
    let m = "abcdefg"
    var x = X(s: ensureMove m)
    consume(ensureMove x)

  static: main()
  main()

block:
  type
    String = object
      id: string

  proc hello =
    var s = String(id: "1")
    var m = ensureMove s
    doAssert m.id == "1"

  hello()

block:
  type
    String = object
      id: string

  proc hello =
    var n = "1"
    var s = String(id: ensureMove n)
    var m = ensureMove s
    doAssert m.id == "1"

  hello()

block:
  type
    String = object
      id: string

  proc hello =
    var n = "1"
    var s = [ensureMove n]
    var m = ensureMove s
    doAssert m[0] == "1"

  hello()

block:
  type
    String = object
      id: string

  proc hello =
    var n = "1"
    var s = @[ensureMove n]
    var m = ensureMove s
    doAssert m[0] == "1"

  hello()

block:
  type
    String = object
      id: string

  proc hello =
    var s = String(id: "1")
    var m = ensureMove s.id
    doAssert m == "1"

  hello()

block:
  proc foo =
    var x = 1
    let y = ensureMove x # move
    when not defined(js):
      doAssert (y, x) == (1, 0) # (1, 0)
  foo()

block:
  proc foo =
    var x = 1
    let y = ensureMove x # move
    doAssert y == 1
  foo()

block:
  proc foo =
    var x = @[1, 2, 3]
    let y = ensureMove x[0] # move
    doAssert y == 1
    when not defined(js):
      doAssert x == @[0, 2, 3]
  foo()

block:
  proc foo =
    var x = [1, 2, 3]
    let y = ensureMove x[0] # move
    doAssert y == 1
    when not defined(js):
      doAssert x == @[0, 2, 3]
  foo()

block:
  proc foo =
    var x = @["1", "2", "3"]
    let y = ensureMove x[0] # move
    doAssert y == "1"
  foo()

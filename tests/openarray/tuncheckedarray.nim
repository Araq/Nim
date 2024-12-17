discard """
  exitcode: 0
  targets: "c cpp"
"""

proc main =
  block: # issue 19171
    var a = ['A']
    proc mutB(x: var openArray[char]) =
      x[0] = 'B'
    mutB(toOpenArray(cast[ptr UncheckedArray[char]](addr a), 0, 0))
    doAssert a[0] == 'B'
    proc mutC(x: var openArray[char]; c: char) =
      x[0] = c
    let p = cast[ptr UncheckedArray[char]](addr a)
    mutC(toOpenArray(p, 0, 0), 'C')
    doAssert p[0] == 'C'

main()

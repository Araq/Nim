block: # issue #17527
  iterator items2[IX, T](a: array[IX, T]): lent T {.inline.} =
    var i = low(IX)
    if i <= high(IX):
      while true:
        yield a[i]
        if i >= high(IX): break
        inc(i)

  proc main() =
    var s: seq[string] = @[]
    for i in 0..<3:
      for (key, val) in items2([("any", "bar")]):
        s.add $(i, key, val)
    doAssert s == @[
      "(0, \"any\", \"bar\")",
      "(1, \"any\", \"bar\")",
      "(2, \"any\", \"bar\")"
    ]

  static: main()

import mpragma1
proc p*[T]() =
  proc inner() {.aMacro.} =
    discard
  inner()
  discard

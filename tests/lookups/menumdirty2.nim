type
  U* = enum
    errNone
  V* = object
    err: U

template x*(lex: V) {.dirty.} =
  lex.err = errNone

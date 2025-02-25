block: # issue #23998
  type
    Enum {.pure.} = enum
      a
    Obj = object
      a: Enum
  proc test(a: Enum) = discard Obj(a: a)

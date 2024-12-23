import std/[json, jsonutils]

type
  Kind* = enum kind1
  Foo* = ref object
    bleh: string
    case kind*: Kind  # Remove these lines and everything works 🤡
    of kind1: discard # Remove these lines and everything works 🤡

proc unserialize*[T](s: string) =
  discard jsonTo(parseJson(s), T)

type Foo* = object
  x*, y*: int

proc `$`*(x: static Foo): string =
  "static Foo(" & $x.x & ", " & $x.y & ")"

proc `$`*(x: Foo): string =
  "runtime Foo(" & $x.x & ", " & $x.y & ")"

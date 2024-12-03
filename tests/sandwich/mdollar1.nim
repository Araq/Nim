type Foo* = object
  x*, y*: int

proc `$`*(f: Foo): string =
  "Foo(" & $f.x & ", " & $f.y & ")"

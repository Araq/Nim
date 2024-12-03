type
  Foo* = object
  Bar* = object

func `$`*(x: Foo | Bar): string =
  "X"

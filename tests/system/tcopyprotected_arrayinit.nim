type
  Bar = object
    b: int = 1

  Foo = object
    f: array[1, Bar]

proc `=copy`(dest: var Bar, source: Bar) {.error.}

discard Foo()

# issue #23565

func foo: bool =
  true

const bar = block:
  type T = int
  not foo()

doAssert not bar

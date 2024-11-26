{.experimental: "strictDefs".}

proc bar(x: out string) =
  x = "abc"

template moe = # bug #21043
  try:
    discard
  except ValueError as e:
    echo(e.msg)

template moe0 {.dirty.} = # bug #21043
  try:
    discard
  except ValueError as e:
    echo(e.msg)

proc foo() =
  block:
    let x: string
    if true:
      x = "abc"
    else:
      x = "def"
    doAssert x == "abc"
  block:
    let y: string
    bar(y)
    doAssert y == "abc"
  block:
    let x: string
    if true:
      x = "abc"
      discard "abc"
    else:
      x = "def"
      discard "def"
    doAssert x == "abc"
  block: #
    let x {.used.} : int
  block: #
    let x: float
    x = 1.234
    doAssert x == 1.234

  block:
    try:
      discard
    except ValueError as e:
      echo(e.msg)
  moe()
  moe0()

static: foo()
foo()

# bug #24472
template bar1314(): bool =
  let hello = true
  hello

template foo1314*(val: bool): bool =
  when nimvm:
    val
  else:
    val

proc test() = # Doesn't fail when top level
  # Original code is calling `unlikely` which has a `nimvm` branch
  let s = foo1314(bar1314())
  doAssert s

test()

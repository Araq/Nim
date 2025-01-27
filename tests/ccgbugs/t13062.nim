discard """
  matrix: "--mm:refc; --mm:orc"
  targets: "c cpp"
"""

import atomics

type
  Pledge* {.exportc.} = object
    p: PledgePtr

  PledgeKind {.exportc.} = enum
    Single
    Iteration

  PledgePtr {.exportc.} = ptr object
    case kind: PledgeKind
    of Single:
      impl: PledgeImpl
    of Iteration:
      discard

  PledgeImpl {.exportc.} = object
    fulfilled: Atomic[bool]

var x: Pledge
when defined(cpp):
  # TODO: fixme
  discard "it doesn't work for refc/orc because of contrived `Atomic` in cpp"
elif defined(gcRefc):
  doAssert x.repr == "[p = nil]"
else: # fixme # bug #20081
  doAssert x.repr == "Pledge(p: nil)"

block:
  block: # bug #18081
    type
      Foo = object
        discard

      Bar = object
        x: Foo

    proc baz(state: var Bar) =
      state.x = Foo()

    baz((ref Bar)(x: (new Foo)[])[])

  block: # bug #18079
    type
      Foo = object
        discard

      Bar = object
        x: Foo

    proc baz(state: var Bar) = discard
    baz((ref Bar)(x: (new Foo)[])[])

  block: # bug #18080
    type
      Foo = object
        discard

      Bar = object
        x: Foo

    proc baz(state: var Bar) = discard
    baz((ref Bar)(x: Foo())[])

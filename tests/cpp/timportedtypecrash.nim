discard """
  action: compile
  targets: "cpp"
  matrix: "--compileOnly"
"""

# issue #20065

type
  Foo* {.importC, nodecl.} = object # doesn't matter if this is importC or importCpp
    value*: int64
  Bar* {.importCpp, nodecl.} = object # no segfault with importC
    foo*: Foo

discard @[Bar()]

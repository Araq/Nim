discard """
  # just tests that this doesn't crash the compiler
  errormsg: "cannot instantiate: 'a:type'"
"""

# bug #8545

template bar(a: static[bool]): untyped = int

proc main() =
  proc foo1(a: static[bool]): auto = 1
  doAssert foo1(true) == 1

  proc foo2(a: static[bool]): bar(a) = 1
  doAssert foo2(true) == 1

  proc foo3(a: static[bool]): bar(cast[static[bool]](a)) = 1
  doAssert foo3(true) == 1

  proc foo4(a: static[bool]): bar(static(a)) = 1
  doAssert foo4(true) == 1

static: main()
main()

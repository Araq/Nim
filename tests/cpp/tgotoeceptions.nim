discard """
  matrix: "--exceptions:goto"
  targets: "cpp"
"""

# bug #22101
import std/pegs
doAssert "test" =~ peg"s <- {{\ident}}"

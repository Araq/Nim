discard """
  matrix: "--warningAsError:Effect"
"""

import std/isolation

# bug #23129
type
  Thing = object
    x: string

proc send(x: string) =
  let wrapper = Thing(x: x)
  discard isolate(wrapper)

send("la")
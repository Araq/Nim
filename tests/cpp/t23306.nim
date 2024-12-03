discard """
targets: "cpp"
"""

type K = object
  h: iterator(f: K): K

iterator d(g: K): K {.closure.} =
  defer:
    discard

discard K(h: d)
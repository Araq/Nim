discard """
  targets: "c cpp"
"""

# bug #19585

type
  X* {.exportc.} = object
    v: int

{.emit:"""
X x = { 1234 };
""".}
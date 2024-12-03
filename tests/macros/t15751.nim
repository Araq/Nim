discard """
  cmd: "nim c --hints:off $file"
  nimout: "out"
"""

# bug #15751
macro print(n: untyped): untyped =
  echo n.repr

print:
  out

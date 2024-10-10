discard """
  errormsg: "cannot instantiate: 'T'"
  file: "system.nim"
"""

# issue #24091

type M[V] = object
echo default(M)

discard """
  errormsg: "type mismatch: got <int>"
  nimout: '''tprevent_forloopvar_mutations.nim(16, 3) Error: type mismatch: got <int>
but expected one of:
proc inc[T, V: Ordinal](x: var T; y: V = 1)
  first type mismatch at position: 1
  required type for x: var T: Ordinal
  but expression 'i' is immutable, not 'var'

expression: inc i
'''
"""

for i in 0..10:
  echo i
  inc i

discard """
  errormsg: "expression '0' is of type 'int literal(0)' and has to be used (or discarded); start of expression here: t23677.nim(1, 1)"
  line: 10
  column: 3
"""

# issue #23677

if true:
  0
else: 
  raise newException(ValueError, "err") 

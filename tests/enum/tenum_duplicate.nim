discard """
  errormsg: "duplicate value in enum 'd'"
"""

type
  unordered_enum = enum
    a = 1
    b = 0
    c
    d = 2

discard """
  cmd: "nim check --hints:off $file"
  errormsg: ""
  nimout:
'''
tdefaultfieldscheck.nim(14, 17) Error: type mismatch: got <string> but expected 'int'
'''
"""


type
  Date* = object
    goal: float = 7
    name: int = "string"

echo default(Date)

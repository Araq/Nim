discard """
  targets: "c js"
"""

block: # bug #24031
  case 0
  else: discard
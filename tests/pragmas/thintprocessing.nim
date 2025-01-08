discard """
  disabled: windows
  matrix: "--hint:processing"
  nimout: '''
compile start
...
warn_module.nim(6, 6) Hint: 'test' is declared but not used [XDeclaredButNotUsed]
compile end
'''
"""

static:
  echo "compile start"

import warn_module

static:
  echo "compile end"

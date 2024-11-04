discard """
  output: '''
true
'''
"""

proc f(): int =
  echo (result = 1; result > 0)

doAssert f() == 1

discard """
  exitcode: 1
  outputsub: '''
Error: unhandled exception: value out of range: -2 notin 0 .. 9223372036854775807 [RangeDefect]
'''
"""

# bug #22852
echo [0][2..^2]

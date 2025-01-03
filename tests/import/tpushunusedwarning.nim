discard """
  action: compile
  matrix: "--hints:off"
  nimoutFull: true
  nimout: '''
'''
"""

# issue #24552

{.push warning[UnusedImport]: off.}
import tables
{.pop.}

proc test*(a: float): float =
  a

discard """
  matrix: "--warningAsError:HoleEnumConv"
"""

type
  e = enum
    a = 0
    b = 2

var i: int
{.push warning[HoleEnumConv]:off.}
discard i.e
{.pop.}

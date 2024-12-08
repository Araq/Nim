discard """
  errormsg: "undeclared identifier: 'something'"
"""

proc p[T](x: T) =
  echo something

var something = 5

p(5)
discard """
  errormsg: '''expression '"invalid"' is of type 'string' and has to be used (or discarded)'''
  line: 12
"""

proc valid*(): string =
  let x = 317
  "valid"

proc invalid*(): string =
  result = "foo"
  "invalid"

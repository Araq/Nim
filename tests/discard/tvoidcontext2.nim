discard """
  errormsg: '''expression '"invalid"' is of type 'string' and has to be used (or discarded)'''
  line: 11
"""

proc foo(x: var string) =
  x = "hello"

proc bar(): string =
  foo(result)
  "invalid"

echo bar()

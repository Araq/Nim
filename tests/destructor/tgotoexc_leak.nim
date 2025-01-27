discard """
  output: '''0
true'''
  cmd: "nim c --gc:arc $file"
"""

# bug #22398

for i in 0 ..< 10_000:
  try:
    try:
      raise newException(ValueError, "")
    except CatchableError:
      discard
      raise newException(ValueError, "") # or raise getCurrentException(), just raise works ok
  except ValueError:
    discard
echo getOccupiedMem()
echo getCurrentException() == nil

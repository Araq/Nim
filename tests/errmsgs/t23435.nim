discard """
  outputsub: "Error: unhandled exception: value out of range: -15 notin 0 .. 9223372036854775807 [RangeDefect]"
  exitcode: "1"
"""

# bug #23435
proc foo() =
  for _ in @[1, 3, 5]:
    discard "abcde"[25..<10]
    break

foo()

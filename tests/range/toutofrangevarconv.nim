discard """
  outputsub: "value out of range: 5 notin 0 .. 3 [RangeDefect]"
  exitcode: "1"
"""

# make sure out of bounds range conversion is detected for `var` conversions

type R = range[0..3]

proc foo(x: var R) =
  doAssert x in 0..3

var x = 5
foo(R(x))

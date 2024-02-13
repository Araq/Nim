discard """
  output: "44"
"""
# Test the new variable declaration syntax
import std/sequtils

var
  x = 0
  s = "Hallo"
  a, b: int = 4

write(stdout, a)
writeLine(stdout, b) #OUT 44

proc p() = # bug #18104
  var x, y = newSeqWith(10, newString(3))
  discard (x, y)

p()

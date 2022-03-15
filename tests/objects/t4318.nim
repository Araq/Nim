type
  A = object of RootObj
  B = object of A

method identify(a:A) {.base.} = echo "A"
method identify(b:B) = echo "B"

var b: B
import std/assertions
doAssertRaises(ObjectAssignmentDefect):
  var a: A = b
  discard a

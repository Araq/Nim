discard """
  matrix: "--mm:arc; --mm:orc"
"""

block: # issue #24080
  var a = (s: "a")
  var b = "a"
  a.s.setLen 0
  b = a.s
  doAssert b == ""

block: # issue #24080, longer string
  var a = (s: "abc")
  var b = "abc"
  a.s.setLen 2
  b = a.s
  doAssert b == "ab"

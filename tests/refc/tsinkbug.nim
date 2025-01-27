discard """
  matrix: "--mm:refc; --mm:arc"
  output: '''
Value is: 42
Value is: 42'''
"""

type AnObject* = object of RootObj
  value*: int

proc mutate(a: sink AnObject) =
  a.value = 1

var obj = AnObject(value: 42)
echo "Value is: ", obj.value
mutate(obj)
echo "Value is: ", obj.value

proc p(x: sink string) = 
  var y = move(x)
  doAssert x.len == 0
  doAssert y.len == 4

p("1234")
var s = "oooo"
p(s)

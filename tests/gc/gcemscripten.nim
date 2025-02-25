discard """
  outputsub: "77\n77"
  retries: 2
"""

## Check how GC/Alloc works in Emscripten
import strutils

type
  X = ref XObj
  XObj = object
    name: string
    value: int
when defined(allow_print):
  const print = true
else:
  const print = false

proc myResult3*(i:int): X {.exportc.} =
  if print: echo "3"
  new(result)
  if print: echo "3-2"
  result.value = i

proc myResult5*(i:int, x:X):X {.exportc.} =
  if print: echo "5"
  system.GC_fullCollect()
  new(result)
  if print: echo "5-2"
  result.value = i
  x.value = i+1
  if result.value == x.value:
    echo "This should not happen. Just allocated variable points to parameter"

proc myResult2*(val: string, i: int): X {.exportc.} =
  if print: echo "2-1"
  result = myResult3(i)
  if print: echo "2-2"
  system.GC_fullCollect()
  if print: echo "2-3"
  var t = new(X)
  if print: echo "2-4"
  result.name = val
  if t.name == "qwe":
    echo "This should not happen. Variable is GC collected and new one on same place are allocated."
  if print: echo "2-5"

proc myResult4*(val: string, i: int): X {.exportc.} =
  if print: echo "4-1"
  result = myResult5(i, X())
  if print: echo "4-2"

var x = myResult2("qwe", 77)
echo intToStr(x.value)

var x2 = myResult4("qwe", 77)
echo intToStr(x2.value)




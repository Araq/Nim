discard """
  output: '''is
finally
nice!'''
"""

import tables

const
  foo = {"ah": "finally", "this": "is", "possible.": "nice!"}.toTable()

# protect against overly smart compiler:
var x = "this"

echo foo[x]
x = "ah"
echo foo[x]
x = "possible."
echo foo[x]

block: # bug #19840
  const testBytes = [byte 0xD8, 0x08, 0xDF, 0x45, 0x00, 0x3D, 0x00, 0x52, 0x00, 0x61]
  var tempStr = "__________________"

  tempStr.prepareMutation
  copyMem(addr tempStr[0], addr testBytes[0], testBytes.len)

block: # bug #22389
  func foo(): ptr UncheckedArray[byte] =
    const bar = [77.byte]
    cast[ptr UncheckedArray[byte]](addr bar[0])

  doAssert foo()[0] == 77


discard """
  errormsg: "type mismatch: got <uint8>"
"""

proc toUInt16(x: var uint16) =
  discard

var x = uint8(1)
toUInt16 x

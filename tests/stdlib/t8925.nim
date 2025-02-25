discard """
  errormsg: "type mismatch between pattern '$$i' (position: 1) and HourRange var 'hour'"
  file: "t8925.nim"
"""

import strscans

type
  HourRange = range[0..23]

var
  hour: HourRange
  timeStr: string

if scanf(timeStr, "$i", hour):
  discard

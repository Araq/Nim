discard """
  cmd: "nim check $file"
"""

import std/strscans


block:
  var strVar: string
  discard "123".scanf("$i", strVar) #[tt.Error
                            ^ type mismatch between pattern '$$i' (position: 1) and string var 'strVar']#

discard """
  errormsg: "type mismatch: got <Option[system.int]> but expected 'Option[var int]'"
  cmd: "nim check $file"
  line: 12
"""

# bug #15533

{.experimental: "views".}
import options
var a = [1, 2, 3, 4]
let o: Option[var int] = some(a[0])

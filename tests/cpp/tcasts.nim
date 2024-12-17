discard """
  cmd: "nim cpp $file"
  targets: "cpp"
"""

block: #5979
  var a = 'a'
  var p: pointer = cast[pointer](a)
  var c = cast[char](p)
  doAssert(c == 'a')


#----------------------------------------------------
# bug #9739
import tables

var t = initTable[string, string]()
discard t.hasKeyOrPut("123", "123")
discard t.mgetOrPut("vas", "kas")
doAssert t.len == 2

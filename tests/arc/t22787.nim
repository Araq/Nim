discard """
  joinable: false
"""

import std/assertions

proc foo =
  var s:seq[string] = @[]
  var res = ""

  for i in 0..3:
    s.add ("test" & $i)
    s.add ("test" & $i)

  var lastname:string = ""

  for i in s:
    var name = i[0..4]

    if name != lastname:
      res.add "NEW:" & name & "\n"
    else:
      res.add name & ">" & lastname & "\n"

    lastname = name

  doAssert res == """
NEW:test0
test0>test0
NEW:test1
test1>test1
NEW:test2
test2>test2
NEW:test3
test3>test3
"""
foo()
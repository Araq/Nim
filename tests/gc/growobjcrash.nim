discard """
  retries: 2
"""

import std/[cgi, strtabs]

proc handleRequest(query: string): StringTableRef =
  iterator foo(): StringTableRef {.closure.} =
    var params = {:}.newStringTable()
    for key, val in cgi.decodeData(query):
      params[key] = val
    yield params

  let x = foo
  result = x()

const Limit = 5*1024*1024

proc main =
  var counter = 0
  for i in 0 .. 10_000:
    for k, v in handleRequest("nick=Elina2&type=activate"):
      inc counter
      if counter mod 100 == 0:
        if getOccupiedMem() > Limit:
          quit "but now a leak"

main()

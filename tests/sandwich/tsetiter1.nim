# comment on issue #11167

import hashes

import msetiter1

type
  Choice = object
    i: int

proc hash(c: Choice): Hash =
  result = Hash(c.i)

var h = initH[Choice]()
let c = @[Choice(i: 1)]

foo(h, c)

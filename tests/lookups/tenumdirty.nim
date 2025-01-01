# issue #23611

import menumdirty1

type
  B = object
  L = object

template F(T: type B): type = F(Json, B)
var j = F(B).init()
var f: L
s(j, f)

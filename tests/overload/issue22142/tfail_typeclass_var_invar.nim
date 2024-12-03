discard """
  errormsg: "ambiguous call"
"""

type C = object
proc test[T: ptr](param: var T): bool = false
proc test(param: var ptr): bool = true
var d: ptr[C]
doAssert test(d) == true  # previously would pass

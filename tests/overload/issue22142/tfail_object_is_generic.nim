discard """
  errormsg: "ambiguous call"
"""

#[
As of the time of writing `object` needs some special
treament in order to be considered "generic" in the right
context when used implicitly
]#

type
  C = object

proc test[T: object](param: T): bool = false
proc test(param: object): bool = true  
doAssert test(C()) == true  # previously would pass

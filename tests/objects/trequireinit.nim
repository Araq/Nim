discard """
  errormsg: "The MPlayerObj type doesn't have a default value. The following fields must be initialized: foo."
"""

type
  MPlayerObj* {.requiresInit.} = object
    foo: range[5..10] = 5

var a: MPlayerObj
echo a.foo
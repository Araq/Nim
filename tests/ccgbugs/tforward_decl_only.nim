discard """
ccodecheck: "\\i !@('struct tyObject_MyRefObject'[0-z]+' _')"
output: "hello"
"""

# issue #7339 
# Test that MyRefObject is only forward declared as it used only by reference

import mymodule
type AnotherType = object
  f: MyRefObject 

let x = AnotherType(f: newMyRefObject("hello"))
echo $x.f


# bug #7363

type 
  Foo = object
    a: cint
  Foo2 = object
    b: cint

proc f(foo: ptr Foo, foo2: ptr Foo2): cint =
  if foo  != nil:  {.emit: "`result` = `foo`->a;".}
  if foo2 != nil: {.emit: [result, " = ", foo2[], ".b;"].}

discard f(nil, nil)


# bug #7392
var x1: BaseObj
var x2 = ChildObj(x1)

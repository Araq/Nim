discard """
matrix: "--legacy:jsnolambdalifting;"
output: '''
3
2
12
Event { name: 'click: test' }
Event { name: 'reloaded: test' }
Event { name: 'updates: test' }
'''
"""

import jsffi, jsconsole

# Tests for JsObject
block: # Test JsObject []= and []
  let obj = newJsObject()
  obj["a"] = 11
  obj["b"] = "test"
  obj["c"] = "test".cstring
  doAssert obj["a"].to(int) == 11
  doAssert obj["c"].to(cstring) == "test".cstring

block: # Test JsObject .= and .
  let obj = newJsObject()
  obj.a = 11
  obj.b = "test"
  obj.c = "test".cstring
  obj.`$!&` = 42
  obj.`while` = 99
  doAssert obj.a.to(int) == 11
  doAssert obj.b.to(string) == "test"
  doAssert obj.c.to(cstring) == "test".cstring
  doAssert obj.`$!&`.to(int) == 42
  doAssert obj.`while`.to(int) == 99

block: # Test JsObject .()
  let obj = newJsObject()
  obj.`?!$` = proc(x, y, z: int, t: cstring): cstring = t & $(x + y + z)
  doAssert obj.`?!$`(1, 2, 3, "Result is: ").to(cstring) == cstring"Result is: 6"

block: # Test JsObject []()
  let obj = newJsObject()
  obj.a = proc(x, y, z: int, t: string): string = t & $(x + y + z)
  let call = obj["a"].to(proc(x, y, z: int, t: string): string)
  doAssert call(1, 2, 3, "Result is: ") == "Result is: 6"

# Test JsObject Iterators
block: # testPairs
  let obj = newJsObject()
  obj.a = 10
  obj.b = 20
  obj.c = 30
  for k, v in obj.pairs:
    case $k
    of "a":
      doAssert v.to(int) == 10
    of "b":
      doAssert v.to(int) == 20
    of "c":
      doAssert v.to(int) == 30
    else:
      doAssert false
block: # testItems
  let obj = newJsObject()
  obj.a = 10
  obj.b = 20
  obj.c = 30
  for v in obj.items:
    doAssert v.to(int) in [10, 20, 30]
block: # testKeys
  let obj = newJsObject()
  obj.a = 10
  obj.b = 20
  obj.c = 30
  for v in obj.keys:
    doAssert $v in ["a", "b", "c"]

block: # Test JsObject equality
  {. emit: "var comparison = {a: 22, b: 'test'};" .}
  var comparison {. importjs, nodecl .}: JsObject
  let obj = newJsObject()
  obj.a = 22
  obj.b = "test".cstring
  doAssert obj.a == comparison.a and obj.b == comparison.b

block: # Test JsObject literal
  {. emit: "var comparison = {a: 22, b: 'test'};" .}
  var comparison {. importjs, nodecl .}: JsObject
  let obj = JsObject{ a: 22, b: "test".cstring }
  doAssert obj.a == comparison.a and obj.b == comparison.b

# Tests for JsAssoc
block: # Test JsAssoc []= and []
  let obj = newJsAssoc[int, int]()
  obj[1] = 11
  doAssert not compiles(obj["a"] = 11)
  doAssert not compiles(obj["a"])
  doAssert not compiles(obj[2] = "test")
  doAssert not compiles(obj[3] = "test".cstring)
  doAssert obj[1] == 11

block: # Test JsAssoc .= and .
  let obj = newJsAssoc[cstring, int]()
  var working = true
  obj.a = 11
  obj.`$!&` = 42
  doAssert not compiles(obj.b = "test")
  doAssert not compiles(obj.c = "test".cstring)
  doAssert obj.a == 11
  doAssert obj.`$!&` == 42

block: # Test JsAssoc .()
  let obj = newJsAssoc[cstring, proc(e: int): int]()
  obj.a = proc(e: int): int = e * e
  doAssert obj.a(10) == 100

block: # Test JsAssoc []()
  let obj = newJsAssoc[cstring, proc(e: int): int]()
  obj.a = proc(e: int): int = e * e
  let call = obj["a"]
  doAssert call(10) == 100

# Test JsAssoc Iterators
block: # testPairs
  let obj = newJsAssoc[cstring, int]()
  obj.a = 10
  obj.b = 20
  obj.c = 30
  for k, v in obj.pairs:
    case $k
    of "a":
      doAssert v == 10
    of "b":
      doAssert v == 20
    of "c":
      doAssert v == 30
    else:
      doAssert false
block: # testItems
  let obj = newJsAssoc[cstring, int]()
  obj.a = 10
  obj.b = 20
  obj.c = 30
  for v in obj.items:
    doAssert v in [10, 20, 30]
block: # testKeys
  let obj = newJsAssoc[cstring, int]()
  obj.a = 10
  obj.b = 20
  obj.c = 30
  for v in obj.keys:
    doAssert v in [cstring"a", cstring"b", cstring"c"]

block: # Test JsAssoc equality
  {. emit: "var comparison = {a: 22, b: 55};" .}
  var comparison {. importjs, nodecl .}: JsAssoc[cstring, int]
  let obj = newJsAssoc[cstring, int]()
  obj.a = 22
  obj.b = 55
  doAssert obj.a == comparison.a and obj.b == comparison.b

block: # Test JsAssoc literal
  {. emit: "var comparison = {a: 22, b: 55};" .}
  var comparison {. importjs, nodecl .}: JsAssoc[cstring, int]
  let obj = JsAssoc[cstring, int]{ a: 22, b: 55 }
  doAssert compiles(JsAssoc[int, int]{ 1: 22, 2: 55 })
  doAssert comparison.a == obj.a and comparison.b == obj.b
  doAssert not compiles(JsAssoc[cstring, int]{ a: "test" })

# Tests for macros on non-JsRoot objects
block: # Test lit
  type TestObject = object
    a: int
    b: cstring
  {. emit: "var comparison = {a: 1};" .}
  var comparison {. importjs, nodecl .}: TestObject
  let obj = TestObject{ a: 1 }
  doAssert obj == comparison

block: # Test bindMethod
  type TestObject = object
    a: int
    onWhatever: proc(e: int): int {.nimcall.}
  proc handleWhatever(this: TestObject, e: int): int =
    e + this.a
  block:
    let obj = TestObject(a: 9, onWhatever: bindMethod(handleWhatever))
    doAssert obj.onWhatever(1) == 10

block:
  {.emit: "function jsProc(n) { return n; }" .}
  proc jsProc(x: int32): JsObject {.importjs: "jsProc(#)".}
  block:
    var x = jsProc(1)
    var y = jsProc(2)
    console.log x + y
    console.log ++x

    x += jsProc(10)
    console.log x

block:
  {.emit:
  """
  function Event(name) { this.name = name; }
  function on(eventName, eventHandler) { eventHandler(new Event(eventName + ": test")); }
  var jslib = { "on": on, "subscribe": on };
  """
  .}

  type Event = object
    name: cstring

  proc on(event: cstring, handler: proc) {.importjs: "on(#,#)".}
  var jslib {.importjs: "jslib", nodecl.}: JsObject

  on("click") do (e: Event):
    console.log e

  jslib.on("reloaded") do ():
    console.log jsarguments[0]

  # this test case is different from the above, because
  # `subscribe` is not overloaded in the current scope
  jslib.subscribe("updates"):
    console.log jsarguments[0]

block:
  doAssert jsUndefined == jsNull
  doAssert jsUndefined == nil
  doAssert jsNull == nil
  doAssert jsUndefined.isNil
  doAssert jsNull.isNil
  doAssert jsNull.isNull
  doAssert jsUndefined.isUndefined

block: # test **
  var a = toJs(0)
  var b = toJs(0)
  doAssert to(a ** b, int) == 1
  a = toJs(1)
  b = toJs(1)
  doAssert to(a ** b, int) == 1
  a = toJs(-1)
  b = toJs(-1)
  doAssert to(a ** b, int) == -1
  a = toJs(6)
  b = toJs(6)
  doAssert to(a ** b, int) == 46656
  a = toJs(5.5)
  b = toJs(3)
  doAssert to(a ** b, float) == 166.375
  a = toJs(5)
  b = toJs(3.0)
  doAssert to(a ** b, float) == 125.0
  a = toJs(7.0)
  b = toJS(6.0)
  doAssert to(a ** b, float) == 117649.0
  a = toJs(8)
  b = toJS(-2)
  doAssert to(a ** b, float) == 0.015625

  a = toJs(1)
  b = toJs(1)
  doAssert to(`**`(a + a, b), int) == 2

  doAssert to(`**`(toJs(1) + toJs(1), toJs(2)), int) == 4

block: # issue #21208
  type MyEnum = enum baz
  var obj: JsObject
  {.emit: "`obj` = {bar: {baz: 123}};".}
  discard obj.bar.baz

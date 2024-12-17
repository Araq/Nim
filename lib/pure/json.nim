#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Andreas Rumpf, Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements a simple high performance `JSON`:idx:
## parser. JSON (JavaScript Object Notation) is a lightweight
## data-interchange format that is easy for humans to read and write
## (unlike XML). It is easy for machines to parse and generate.
## JSON is based on a subset of the JavaScript Programming Language,
## Standard ECMA-262 3rd Edition - December 1999.
##
## See also
## ========
## * `std/parsejson <parsejson.html>`_
## * `std/jsonutils <jsonutils.html>`_
## * `std/marshal <marshal.html>`_
## * `std/jscore <jscore.html>`_
##
##
## Overview
## ========
##
## Parsing JSON
## ------------
##
## JSON often arrives into your program (via an API or a file) as a `string`.
## The first step is to change it from its serialized form into a nested object
## structure called a `JsonNode`.
##
## The `parseJson` procedure takes a string containing JSON and returns a
## `JsonNode` object. This is an object variant and it is either a
## `JObject`, `JArray`, `JString`, `JInt`, `JFloat`, `JBool` or
## `JNull`. You check the kind of this object variant by using the `kind`
## accessor.
##
## For a `JsonNode` who's kind is `JObject`, you can access its fields using
## the `[]` operator. The following example shows how to do this:
##
##   ```Nim
##   import std/json
##
##   let jsonNode = parseJson("""{"key": 3.14}""")
##
##   doAssert jsonNode.kind == JObject
##   doAssert jsonNode["key"].kind == JFloat
##   ```
##
## Reading values
## --------------
##
## Once you have a `JsonNode`, retrieving the values can then be achieved
## by using one of the helper procedures, which include:
##
## * `getInt`
## * `getFloat`
## * `getStr`
## * `getBool`
##
## To retrieve the value of `"key"` you can do the following:
##
##   ```Nim
##   import std/json
##
##   let jsonNode = parseJson("""{"key": 3.14}""")
##
##   doAssert jsonNode["key"].getFloat() == 3.14
##   ```
##
## **Important:** The `[]` operator will raise an exception when the
## specified field does not exist.
##
## Handling optional keys
## ----------------------
##
## By using the `{}` operator instead of `[]`, it will return `nil`
## when the field is not found. The `get`-family of procedures will return a
## type's default value when called on `nil`.
##
##   ```Nim
##   import std/json
##
##   let jsonNode = parseJson("{}")
##
##   doAssert jsonNode{"nope"}.getInt() == 0
##   doAssert jsonNode{"nope"}.getFloat() == 0
##   doAssert jsonNode{"nope"}.getStr() == ""
##   doAssert jsonNode{"nope"}.getBool() == false
##   ```
##
## Using default values
## --------------------
##
## The `get`-family helpers also accept an additional parameter which allow
## you to fallback to a default value should the key's values be `null`:
##
##   ```Nim
##   import std/json
##
##   let jsonNode = parseJson("""{"key": 3.14, "key2": null}""")
##
##   doAssert jsonNode["key"].getFloat(6.28) == 3.14
##   doAssert jsonNode["key2"].getFloat(3.14) == 3.14
##   doAssert jsonNode{"nope"}.getFloat(3.14) == 3.14 # note the {}
##   ```
##
## Unmarshalling
## -------------
##
## In addition to reading dynamic data, Nim can also unmarshal JSON directly
## into a type with the `to` macro.
##
## Note: Use `Option <options.html#Option>`_ for keys sometimes missing in json
## responses, and backticks around keys with a reserved keyword as name.
##
##   ```Nim
##   import std/json
##   import std/options
##
##   type
##     User = object
##       name: string
##       age: int
##       `type`: Option[string]
##
##   let userJson = parseJson("""{ "name": "Nim", "age": 12 }""")
##   let user = to(userJson, User)
##   if user.`type`.isSome():
##     assert user.`type`.get() != "robot"
##   ```
##
## Creating JSON
## =============
##
## This module can also be used to comfortably create JSON using the `%*`
## operator:
##
##   ```nim
##   import std/json
##
##   var hisName = "John"
##   let herAge = 31
##   var j = %*
##     [
##       { "name": hisName, "age": 30 },
##       { "name": "Susan", "age": herAge }
##     ]
##
##   var j2 = %* {"name": "Isaac", "books": ["Robot Dreams"]}
##   j2["details"] = %* {"age":35, "pi":3.1415}
##   echo j2
##   ```
##
## See also: std/jsonutils for hookable json serialization/deserialization
## of arbitrary types.

runnableExamples:
  ## Note: for JObject, key ordering is preserved, unlike in some languages,
  ## this is convenient for some use cases. Example:
  type Foo = object
    a1, a2, a0, a3, a4: int
  doAssert $(%* Foo()) == """{"a1":0,"a2":0,"a0":0,"a3":0,"a4":0}"""

import std/[hashes, tables, strutils, lexbase, streams, macros, parsejson]

import std/options # xxx remove this dependency using same approach as https://github.com/nim-lang/Nim/pull/14563
import std/private/since

when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions, formatfloat]

export
  tables.`$`

export
  parsejson.JsonEventKind, parsejson.JsonError, JsonParser, JsonKindError,
  open, close, str, getInt, getFloat, kind, getColumn, getLine, getFilename,
  errorMsg, errorMsgExpected, next, JsonParsingError, raiseParseErr, nimIdentNormalize

type
  JsonNodeKind* = enum ## possible JSON node types
    JNull,
    JBool,
    JInt,
    JFloat,
    JString,
    JObject,
    JArray

  JsonNode* = ref JsonNodeObj ## JSON node
  JsonNodeObj* {.acyclic.} = object
    isUnquoted: bool # the JString was a number-like token and
                     # so shouldn't be quoted
    case kind*: JsonNodeKind
    of JString:
      str*: string
    of JInt:
      num*: BiggestInt
    of JFloat:
      fnum*: float
    of JBool:
      bval*: bool
    of JNull:
      nil
    of JObject:
      fields*: OrderedTable[string, JsonNode]
    of JArray:
      elems*: seq[JsonNode]

const DepthLimit = 1000

proc newJString*(s: string): JsonNode =
  ## Creates a new `JString JsonNode`.
  result = JsonNode(kind: JString, str: s)

proc newJRawNumber(s: string): JsonNode =
  ## Creates a "raw JS number", that is a number that does not
  ## fit into Nim's `BiggestInt` field. This is really a `JString`
  ## with the additional information that it should be converted back
  ## to the string representation without the quotes.
  result = JsonNode(kind: JString, str: s, isUnquoted: true)

proc newJInt*(n: BiggestInt): JsonNode =
  ## Creates a new `JInt JsonNode`.
  result = JsonNode(kind: JInt, num: n)

proc newJFloat*(n: float): JsonNode =
  ## Creates a new `JFloat JsonNode`.
  result = JsonNode(kind: JFloat, fnum: n)

proc newJBool*(b: bool): JsonNode =
  ## Creates a new `JBool JsonNode`.
  result = JsonNode(kind: JBool, bval: b)

proc newJNull*(): JsonNode =
  ## Creates a new `JNull JsonNode`.
  result = JsonNode(kind: JNull)

proc newJObject*(): JsonNode =
  ## Creates a new `JObject JsonNode`
  result = JsonNode(kind: JObject, fields: initOrderedTable[string, JsonNode](2))

proc newJArray*(): JsonNode =
  ## Creates a new `JArray JsonNode`
  result = JsonNode(kind: JArray, elems: @[])

proc getStr*(n: JsonNode, default: string = ""): string =
  ## Retrieves the string value of a `JString JsonNode`.
  ##
  ## Returns `default` if `n` is not a `JString`, or if `n` is nil.
  if n.isNil or n.kind != JString: return default
  else: return n.str

proc getInt*(n: JsonNode, default: int = 0): int =
  ## Retrieves the int value of a `JInt JsonNode`.
  ##
  ## Returns `default` if `n` is not a `JInt`, or if `n` is nil.
  if n.isNil or n.kind != JInt: return default
  else: return int(n.num)

proc getBiggestInt*(n: JsonNode, default: BiggestInt = 0): BiggestInt =
  ## Retrieves the BiggestInt value of a `JInt JsonNode`.
  ##
  ## Returns `default` if `n` is not a `JInt`, or if `n` is nil.
  if n.isNil or n.kind != JInt: return default
  else: return n.num

proc getFloat*(n: JsonNode, default: float = 0.0): float =
  ## Retrieves the float value of a `JFloat JsonNode`.
  ##
  ## Returns `default` if `n` is not a `JFloat` or `JInt`, or if `n` is nil.
  if n.isNil: return default
  case n.kind
  of JFloat: return n.fnum
  of JInt: return float(n.num)
  else: return default

proc getBool*(n: JsonNode, default: bool = false): bool =
  ## Retrieves the bool value of a `JBool JsonNode`.
  ##
  ## Returns `default` if `n` is not a `JBool`, or if `n` is nil.
  if n.isNil or n.kind != JBool: return default
  else: return n.bval

proc getFields*(n: JsonNode,
    default = initOrderedTable[string, JsonNode](2)):
        OrderedTable[string, JsonNode] =
  ## Retrieves the key, value pairs of a `JObject JsonNode`.
  ##
  ## Returns `default` if `n` is not a `JObject`, or if `n` is nil.
  if n.isNil or n.kind != JObject: return default
  else: return n.fields

proc getElems*(n: JsonNode, default: seq[JsonNode] = @[]): seq[JsonNode] =
  ## Retrieves the array of a `JArray JsonNode`.
  ##
  ## Returns `default` if `n` is not a `JArray`, or if `n` is nil.
  if n.isNil or n.kind != JArray: return default
  else: return n.elems

proc add*(father, child: JsonNode) =
  ## Adds `child` to a JArray node `father`.
  assert father.kind == JArray
  father.elems.add(child)

proc add*(obj: JsonNode, key: string, val: JsonNode) =
  ## Sets a field from a `JObject`.
  assert obj.kind == JObject
  obj.fields[key] = val

proc `%`*(s: string): JsonNode =
  ## Generic constructor for JSON data. Creates a new `JString JsonNode`.
  result = JsonNode(kind: JString, str: s)

proc `%`*(n: uint): JsonNode =
  ## Generic constructor for JSON data. Creates a new `JInt JsonNode`.
  if n > cast[uint](int.high):
    result = newJRawNumber($n)
  else:
    result = JsonNode(kind: JInt, num: BiggestInt(n))

proc `%`*(n: int): JsonNode =
  ## Generic constructor for JSON data. Creates a new `JInt JsonNode`.
  result = JsonNode(kind: JInt, num: n)

proc `%`*(n: BiggestUInt): JsonNode =
  ## Generic constructor for JSON data. Creates a new `JInt JsonNode`.
  if n > cast[BiggestUInt](BiggestInt.high):
    result = newJRawNumber($n)
  else:
    result = JsonNode(kind: JInt, num: BiggestInt(n))

proc `%`*(n: BiggestInt): JsonNode =
  ## Generic constructor for JSON data. Creates a new `JInt JsonNode`.
  result = JsonNode(kind: JInt, num: n)

proc `%`*(n: float): JsonNode =
  ## Generic constructor for JSON data. Creates a new `JFloat JsonNode`.
  runnableExamples:
    assert $(%[NaN, Inf, -Inf, 0.0, -0.0, 1.0, 1e-2]) == """["nan","inf","-inf",0.0,-0.0,1.0,0.01]"""
    assert (%NaN).kind == JString
    assert (%0.0).kind == JFloat
  # for those special cases, we could also have used `newJRawNumber` but then
  # it would've been inconsisten with the case of `parseJson` vs `%` for representing them.
  if n != n: newJString("nan")
  elif n == Inf: newJString("inf")
  elif n == -Inf: newJString("-inf")
  else: JsonNode(kind: JFloat, fnum: n)

proc `%`*(b: bool): JsonNode =
  ## Generic constructor for JSON data. Creates a new `JBool JsonNode`.
  result = JsonNode(kind: JBool, bval: b)

proc `%`*(keyVals: openArray[tuple[key: string, val: JsonNode]]): JsonNode =
  ## Generic constructor for JSON data. Creates a new `JObject JsonNode`
  if keyVals.len == 0: return newJArray()
  result = newJObject()
  for key, val in items(keyVals): result.fields[key] = val

template `%`*(j: JsonNode): JsonNode = j

proc `%`*[T](elements: openArray[T]): JsonNode =
  ## Generic constructor for JSON data. Creates a new `JArray JsonNode`
  result = newJArray()
  for elem in elements: result.add(%elem)

proc `%`*[T](table: Table[string, T]|OrderedTable[string, T]): JsonNode =
  ## Generic constructor for JSON data. Creates a new `JObject JsonNode`.
  result = newJObject()
  for k, v in table: result[k] = %v

proc `%`*[T](opt: Option[T]): JsonNode =
  ## Generic constructor for JSON data. Creates a new `JNull JsonNode`
  ## if `opt` is empty, otherwise it delegates to the underlying value.
  if opt.isSome: %opt.get else: newJNull()

when false:
  # For 'consistency' we could do this, but that only pushes people further
  # into that evil comfort zone where they can use Nim without understanding it
  # causing problems later on.
  proc `%`*(elements: set[bool]): JsonNode =
    ## Generic constructor for JSON data. Creates a new `JObject JsonNode`.
    ## This can only be used with the empty set `{}` and is supported
    ## to prevent the gotcha `%*{}` which used to produce an empty
    ## JSON array.
    result = newJObject()
    assert false notin elements, "usage error: only empty sets allowed"
    assert true notin elements, "usage error: only empty sets allowed"

proc `[]=`*(obj: JsonNode, key: string, val: JsonNode) {.inline.} =
  ## Sets a field from a `JObject`.
  assert(obj.kind == JObject)
  obj.fields[key] = val

proc `%`*[T: object](o: T): JsonNode =
  ## Construct JsonNode from tuples and objects.
  result = newJObject()
  for k, v in o.fieldPairs: result[k] = %v

proc `%`*(o: ref object): JsonNode =
  ## Generic constructor for JSON data. Creates a new `JObject JsonNode`
  if o.isNil:
    result = newJNull()
  else:
    result = %(o[])

proc `%`*(o: enum): JsonNode =
  ## Construct a JsonNode that represents the specified enum value as a
  ## string. Creates a new `JString JsonNode`.
  result = %($o)

proc toJsonImpl(x: NimNode): NimNode =
  case x.kind
  of nnkBracket: # array
    if x.len == 0: return newCall(bindSym"newJArray")
    result = newNimNode(nnkBracket)
    for i in 0 ..< x.len:
      result.add(toJsonImpl(x[i]))
    result = newCall(bindSym("%", brOpen), result)
  of nnkTableConstr: # object
    if x.len == 0: return newCall(bindSym"newJObject")
    result = newNimNode(nnkTableConstr)
    for i in 0 ..< x.len:
      x[i].expectKind nnkExprColonExpr
      result.add newTree(nnkExprColonExpr, x[i][0], toJsonImpl(x[i][1]))
    result = newCall(bindSym("%", brOpen), result)
  of nnkCurly: # empty object
    x.expectLen(0)
    result = newCall(bindSym"newJObject")
  of nnkNilLit:
    result = newCall(bindSym"newJNull")
  of nnkPar:
    if x.len == 1: result = toJsonImpl(x[0])
    else: result = newCall(bindSym("%", brOpen), x)
  else:
    result = newCall(bindSym("%", brOpen), x)

macro `%*`*(x: untyped): untyped =
  ## Convert an expression to a JsonNode directly, without having to specify
  ## `%` for every element.
  result = toJsonImpl(x)

proc `==`*(a, b: JsonNode): bool {.noSideEffect, raises: [].} =
  ## Check two nodes for equality
  if a.isNil:
    if b.isNil: return true
    return false
  elif b.isNil or a.kind != b.kind:
    return false
  else:
    case a.kind
    of JString:
      result = a.str == b.str
    of JInt:
      result = a.num == b.num
    of JFloat:
      result = a.fnum == b.fnum
    of JBool:
      result = a.bval == b.bval
    of JNull:
      result = true
    of JArray:
      {.cast(raises: []).}: # bug #19303
        result = a.elems == b.elems
    of JObject:
      # we cannot use OrderedTable's equality here as
      # the order does not matter for equality here.
      if a.fields.len != b.fields.len: return false
      for key, val in a.fields:
        if not b.fields.hasKey(key): return false
        {.cast(raises: []).}:
          when defined(nimHasEffectsOf):
            {.noSideEffect.}:
              if b.fields[key] != val: return false
          else:
            if b.fields[key] != val: return false
      result = true

proc hash*(n: OrderedTable[string, JsonNode]): Hash {.noSideEffect.}

proc hash*(n: JsonNode): Hash {.noSideEffect.} =
  ## Compute the hash for a JSON node
  case n.kind
  of JArray:
    result = hash(n.elems)
  of JObject:
    result = hash(n.fields)
  of JInt:
    result = hash(n.num)
  of JFloat:
    result = hash(n.fnum)
  of JBool:
    result = hash(n.bval.int)
  of JString:
    result = hash(n.str)
  of JNull:
    result = Hash(0)

proc hash*(n: OrderedTable[string, JsonNode]): Hash =
  result = default(Hash)
  for key, val in n:
    result = result xor (hash(key) !& hash(val))
  result = !$result

proc len*(n: JsonNode): int =
  ## If `n` is a `JArray`, it returns the number of elements.
  ## If `n` is a `JObject`, it returns the number of pairs.
  ## Else it returns 0.
  case n.kind
  of JArray: result = n.elems.len
  of JObject: result = n.fields.len
  else: result = 0

proc `[]`*(node: JsonNode, name: string): JsonNode {.inline.} =
  ## Gets a field from a `JObject`, which must not be nil.
  ## If the value at `name` does not exist, raises KeyError.
  assert(not isNil(node))
  assert(node.kind == JObject)
  when defined(nimJsonGet):
    if not node.fields.hasKey(name): return nil
  result = node.fields[name]

proc `[]`*(node: JsonNode, index: int): JsonNode {.inline.} =
  ## Gets the node at `index` in an Array. Result is undefined if `index`
  ## is out of bounds, but as long as array bound checks are enabled it will
  ## result in an exception.
  assert(not isNil(node))
  assert(node.kind == JArray)
  return node.elems[index]

proc `[]`*(node: JsonNode, index: BackwardsIndex): JsonNode {.inline, since: (1, 5, 1).} =
  ## Gets the node at `array.len-i` in an array through the `^` operator.
  ##
  ## i.e. `j[^i]` is a shortcut for `j[j.len-i]`.
  runnableExamples:
    let
      j = parseJson("[1,2,3,4,5]")

    doAssert j[^1].getInt == 5
    doAssert j[^2].getInt == 4

  `[]`(node, node.len - int(index))

proc `[]`*[U, V](a: JsonNode, x: HSlice[U, V]): JsonNode =
  ## Slice operation for JArray.
  ##
  ## Returns the inclusive range `[a[x.a], a[x.b]]`:
  runnableExamples:
    import std/json
    let arr = %[0,1,2,3,4,5]
    doAssert arr[2..4] == %[2,3,4]
    doAssert arr[2..^2] == %[2,3,4]
    doAssert arr[^4..^2] == %[2,3,4]

  assert(a.kind == JArray)
  result = newJArray()
  let xa = (when x.a is BackwardsIndex: a.len - int(x.a) else: int(x.a))
  let L = (when x.b is BackwardsIndex: a.len - int(x.b) else: int(x.b)) - xa + 1
  for i in 0..<L:
    result.add(a[i + xa])

proc hasKey*(node: JsonNode, key: string): bool =
  ## Checks if `key` exists in `node`.
  assert(node.kind == JObject)
  result = node.fields.hasKey(key)

proc contains*(node: JsonNode, key: string): bool =
  ## Checks if `key` exists in `node`.
  assert(node.kind == JObject)
  node.fields.hasKey(key)

proc contains*(node: JsonNode, val: JsonNode): bool =
  ## Checks if `val` exists in array `node`.
  assert(node.kind == JArray)
  find(node.elems, val) >= 0

proc `{}`*(node: JsonNode, keys: varargs[string]): JsonNode =
  ## Traverses the node and gets the given value. If any of the
  ## keys do not exist, returns `nil`. Also returns `nil` if one of the
  ## intermediate data structures is not an object.
  ##
  ## This proc can be used to create tree structures on the
  ## fly (sometimes called `autovivification`:idx:):
  ##
  runnableExamples:
    var myjson = %* {"parent": {"child": {"grandchild": 1}}}
    doAssert myjson{"parent", "child", "grandchild"} == newJInt(1)

  result = node
  for key in keys:
    if isNil(result) or result.kind != JObject:
      return nil
    result = result.fields.getOrDefault(key)

proc `{}`*(node: JsonNode, index: varargs[int]): JsonNode =
  ## Traverses the node and gets the given value. If any of the
  ## indexes do not exist, returns `nil`. Also returns `nil` if one of the
  ## intermediate data structures is not an array.
  result = node
  for i in index:
    if isNil(result) or result.kind != JArray or i >= node.len:
      return nil
    result = result.elems[i]

proc getOrDefault*(node: JsonNode, key: string): JsonNode =
  ## Gets a field from a `node`. If `node` is nil or not an object or
  ## value at `key` does not exist, returns nil
  if not isNil(node) and node.kind == JObject:
    result = node.fields.getOrDefault(key)
  else:
    result = nil

proc `{}`*(node: JsonNode, key: string): JsonNode =
  ## Gets a field from a `node`. If `node` is nil or not an object or
  ## value at `key` does not exist, returns nil
  node.getOrDefault(key)

proc `{}=`*(node: JsonNode, keys: varargs[string], value: JsonNode) =
  ## Traverses the node and tries to set the value at the given location
  ## to `value`. If any of the keys are missing, they are added.
  var node = node
  for i in 0..(keys.len-2):
    if not node.hasKey(keys[i]):
      node[keys[i]] = newJObject()
    node = node[keys[i]]
  node[keys[keys.len-1]] = value

proc delete*(obj: JsonNode, key: string) =
  ## Deletes `obj[key]`.
  assert(obj.kind == JObject)
  if not obj.fields.hasKey(key):
    raise newException(KeyError, "key not in object")
  obj.fields.del(key)

proc copy*(p: JsonNode): JsonNode =
  ## Performs a deep copy of `p`.
  case p.kind
  of JString:
    result = newJString(p.str)
    result.isUnquoted = p.isUnquoted
  of JInt:
    result = newJInt(p.num)
  of JFloat:
    result = newJFloat(p.fnum)
  of JBool:
    result = newJBool(p.bval)
  of JNull:
    result = newJNull()
  of JObject:
    result = newJObject()
    for key, val in pairs(p.fields):
      result.fields[key] = copy(val)
  of JArray:
    result = newJArray()
    for i in items(p.elems):
      result.elems.add(copy(i))

# ------------- pretty printing ----------------------------------------------

proc indent(s: var string, i: int) =
  s.add(spaces(i))

proc newIndent(curr, indent: int, ml: bool): int =
  if ml: return curr + indent
  else: return indent

proc nl(s: var string, ml: bool) =
  s.add(if ml: "\n" else: " ")

proc escapeJsonUnquoted*(s: string; result: var string) =
  ## Converts a string `s` to its JSON representation without quotes.
  ## Appends to `result`.
  for c in s:
    case c
    of '\L': result.add("\\n")
    of '\b': result.add("\\b")
    of '\f': result.add("\\f")
    of '\t': result.add("\\t")
    of '\v': result.add("\\u000b")
    of '\r': result.add("\\r")
    of '"': result.add("\\\"")
    of '\0'..'\7': result.add("\\u000" & $ord(c))
    of '\14'..'\31': result.add("\\u00" & toHex(ord(c), 2))
    of '\\': result.add("\\\\")
    else: result.add(c)

proc escapeJsonUnquoted*(s: string): string =
  ## Converts a string `s` to its JSON representation without quotes.
  result = newStringOfCap(s.len + s.len shr 3)
  escapeJsonUnquoted(s, result)

proc escapeJson*(s: string; result: var string) =
  ## Converts a string `s` to its JSON representation with quotes.
  ## Appends to `result`.
  result.add("\"")
  escapeJsonUnquoted(s, result)
  result.add("\"")

proc escapeJson*(s: string): string =
  ## Converts a string `s` to its JSON representation with quotes.
  result = newStringOfCap(s.len + s.len shr 3)
  escapeJson(s, result)

proc toUgly*(result: var string, node: JsonNode) =
  ## Converts `node` to its JSON Representation, without
  ## regard for human readability. Meant to improve `$` string
  ## conversion performance.
  ##
  ## JSON representation is stored in the passed `result`
  ##
  ## This provides higher efficiency than the `pretty` procedure as it
  ## does **not** attempt to format the resulting JSON to make it human readable.
  var comma = false
  case node.kind:
  of JArray:
    result.add "["
    for child in node.elems:
      if comma: result.add ","
      else: comma = true
      result.toUgly child
    result.add "]"
  of JObject:
    result.add "{"
    for key, value in pairs(node.fields):
      if comma: result.add ","
      else: comma = true
      key.escapeJson(result)
      result.add ":"
      result.toUgly value
    result.add "}"
  of JString:
    if node.isUnquoted:
      result.add node.str
    else:
      escapeJson(node.str, result)
  of JInt:
    result.addInt(node.num)
  of JFloat:
    result.addFloat(node.fnum)
  of JBool:
    result.add(if node.bval: "true" else: "false")
  of JNull:
    result.add "null"

proc toPretty(result: var string, node: JsonNode, indent = 2, ml = true,
              lstArr = false, currIndent = 0) =
  case node.kind
  of JObject:
    if lstArr: result.indent(currIndent) # Indentation
    if node.fields.len > 0:
      result.add("{")
      result.nl(ml) # New line
      var i = 0
      for key, val in pairs(node.fields):
        if i > 0:
          result.add(",")
          result.nl(ml) # New Line
        inc i
        # Need to indent more than {
        result.indent(newIndent(currIndent, indent, ml))
        escapeJson(key, result)
        result.add(": ")
        toPretty(result, val, indent, ml, false,
                 newIndent(currIndent, indent, ml))
      result.nl(ml)
      result.indent(currIndent) # indent the same as {
      result.add("}")
    else:
      result.add("{}")
  of JString:
    if lstArr: result.indent(currIndent)
    toUgly(result, node)
  of JInt:
    if lstArr: result.indent(currIndent)
    result.addInt(node.num)
  of JFloat:
    if lstArr: result.indent(currIndent)
    result.addFloat(node.fnum)
  of JBool:
    if lstArr: result.indent(currIndent)
    result.add(if node.bval: "true" else: "false")
  of JArray:
    if lstArr: result.indent(currIndent)
    if len(node.elems) != 0:
      result.add("[")
      result.nl(ml)
      for i in 0..len(node.elems)-1:
        if i > 0:
          result.add(",")
          result.nl(ml) # New Line
        toPretty(result, node.elems[i], indent, ml,
            true, newIndent(currIndent, indent, ml))
      result.nl(ml)
      result.indent(currIndent)
      result.add("]")
    else: result.add("[]")
  of JNull:
    if lstArr: result.indent(currIndent)
    result.add("null")

proc pretty*(node: JsonNode, indent = 2): string =
  ## Returns a JSON Representation of `node`, with indentation and
  ## on multiple lines.
  ##
  ## Similar to prettyprint in Python.
  runnableExamples:
    let j = %* {"name": "Isaac", "books": ["Robot Dreams"],
                "details": {"age": 35, "pi": 3.1415}}
    doAssert pretty(j) == """
{
  "name": "Isaac",
  "books": [
    "Robot Dreams"
  ],
  "details": {
    "age": 35,
    "pi": 3.1415
  }
}"""
  result = ""
  toPretty(result, node, indent)

proc `$`*(node: JsonNode): string =
  ## Converts `node` to its JSON Representation on one line.
  result = newStringOfCap(node.len shl 1)
  toUgly(result, node)

iterator items*(node: JsonNode): JsonNode =
  ## Iterator for the items of `node`. `node` has to be a JArray.
  assert node.kind == JArray, ": items() can not iterate a JsonNode of kind " & $node.kind
  for i in items(node.elems):
    yield i

iterator mitems*(node: var JsonNode): var JsonNode =
  ## Iterator for the items of `node`. `node` has to be a JArray. Items can be
  ## modified.
  assert node.kind == JArray, ": mitems() can not iterate a JsonNode of kind " & $node.kind
  for i in mitems(node.elems):
    yield i

iterator pairs*(node: JsonNode): tuple[key: string, val: JsonNode] =
  ## Iterator for the child elements of `node`. `node` has to be a JObject.
  assert node.kind == JObject, ": pairs() can not iterate a JsonNode of kind " & $node.kind
  for key, val in pairs(node.fields):
    yield (key, val)

iterator keys*(node: JsonNode): string =
  ## Iterator for the keys in `node`. `node` has to be a JObject.
  assert node.kind == JObject, ": keys() can not iterate a JsonNode of kind " & $node.kind
  for key in node.fields.keys:
    yield key

iterator mpairs*(node: var JsonNode): tuple[key: string, val: var JsonNode] =
  ## Iterator for the child elements of `node`. `node` has to be a JObject.
  ## Values can be modified
  assert node.kind == JObject, ": mpairs() can not iterate a JsonNode of kind " & $node.kind
  for key, val in mpairs(node.fields):
    yield (key, val)

proc parseJson(p: var JsonParser; rawIntegers, rawFloats: bool, depth = 0): JsonNode =
  ## Parses JSON from a JSON Parser `p`.
  case p.tok
  of tkString:
    # we capture 'p.a' here, so we need to give it a fresh buffer afterwards:
    when defined(gcArc) or defined(gcOrc) or defined(gcAtomicArc):
      result = JsonNode(kind: JString, str: move p.a)
    else:
      result = JsonNode(kind: JString)
      shallowCopy(result.str, p.a)
      p.a = ""
    discard getTok(p)
  of tkInt:
    if rawIntegers:
      result = newJRawNumber(p.a)
    else:
      try:
        result = newJInt(parseBiggestInt(p.a))
      except ValueError:
        result = newJRawNumber(p.a)
    discard getTok(p)
  of tkFloat:
    if rawFloats:
      result = newJRawNumber(p.a)
    else:
      try:
        result = newJFloat(parseFloat(p.a))
      except ValueError:
        result = newJRawNumber(p.a)
    discard getTok(p)
  of tkTrue:
    result = newJBool(true)
    discard getTok(p)
  of tkFalse:
    result = newJBool(false)
    discard getTok(p)
  of tkNull:
    result = newJNull()
    discard getTok(p)
  of tkCurlyLe:
    if depth > DepthLimit:
      raiseParseErr(p, "}")
    result = newJObject()
    discard getTok(p)
    while p.tok != tkCurlyRi:
      if p.tok != tkString:
        raiseParseErr(p, "string literal as key")
      var key = p.a
      discard getTok(p)
      eat(p, tkColon)
      var val = parseJson(p, rawIntegers, rawFloats, depth+1)
      result[key] = val
      if p.tok != tkComma: break
      discard getTok(p)
    eat(p, tkCurlyRi)
  of tkBracketLe:
    if depth > DepthLimit:
      raiseParseErr(p, "]")
    result = newJArray()
    discard getTok(p)
    while p.tok != tkBracketRi:
      result.add(parseJson(p, rawIntegers, rawFloats, depth+1))
      if p.tok != tkComma: break
      discard getTok(p)
    eat(p, tkBracketRi)
  of tkError, tkCurlyRi, tkBracketRi, tkColon, tkComma, tkEof:
    raiseParseErr(p, "{")

iterator parseJsonFragments*(s: Stream, filename: string = ""; rawIntegers = false, rawFloats = false): JsonNode =
  ## Parses from a stream `s` into `JsonNodes`. `filename` is only needed
  ## for nice error messages.
  ## The JSON fragments are separated by whitespace. This can be substantially
  ## faster than the comparable loop
  ## `for x in splitWhitespace(s): yield parseJson(x)`.
  ## This closes the stream `s` after it's done.
  ## If `rawIntegers` is true, integer literals will not be converted to a `JInt`
  ## field but kept as raw numbers via `JString`.
  ## If `rawFloats` is true, floating point literals will not be converted to a `JFloat`
  ## field but kept as raw numbers via `JString`.
  var p: JsonParser = default(JsonParser)
  p.open(s, filename)
  try:
    discard getTok(p) # read first token
    while p.tok != tkEof:
      yield p.parseJson(rawIntegers, rawFloats)
  finally:
    p.close()

proc parseJson*(s: Stream, filename: string = ""; rawIntegers = false, rawFloats = false): JsonNode =
  ## Parses from a stream `s` into a `JsonNode`. `filename` is only needed
  ## for nice error messages.
  ## If `s` contains extra data, it will raise `JsonParsingError`.
  ## This closes the stream `s` after it's done.
  ## If `rawIntegers` is true, integer literals will not be converted to a `JInt`
  ## field but kept as raw numbers via `JString`.
  ## If `rawFloats` is true, floating point literals will not be converted to a `JFloat`
  ## field but kept as raw numbers via `JString`.
  var p: JsonParser = default(JsonParser)
  p.open(s, filename)
  try:
    discard getTok(p) # read first token
    result = p.parseJson(rawIntegers, rawFloats)
    eat(p, tkEof) # check if there is no extra data
  finally:
    p.close()

when defined(js):
  from std/math import `mod`
  from std/jsffi import JsObject, `[]`, to
  from std/private/jsutils import getProtoName, isInteger, isSafeInteger

  proc parseNativeJson(x: cstring): JsObject {.importjs: "JSON.parse(#)".}

  proc getVarType(x: JsObject, isRawNumber: var bool): JsonNodeKind =
    result = JNull
    case $getProtoName(x) # TODO: Implicit returns fail here.
    of "[object Array]": return JArray
    of "[object Object]": return JObject
    of "[object Number]":
      if isInteger(x) and 1.0 / cast[float](x) != -Inf: # preserve -0.0 as float
        if isSafeInteger(x):
          return JInt
        else:
          isRawNumber = true
          return JString
      else:
        return JFloat
    of "[object Boolean]": return JBool
    of "[object Null]": return JNull
    of "[object String]": return JString
    else: assert false

  proc len(x: JsObject): int =
    {.emit: """
      `result` = `x`.length;
    """.}

  proc convertObject(x: JsObject): JsonNode =
    var isRawNumber = false
    case getVarType(x, isRawNumber)
    of JArray:
      result = newJArray()
      for i in 0 ..< x.len:
        result.add(x[i].convertObject())
    of JObject:
      result = newJObject()
      {.emit: """for (var property in `x`) {
        if (`x`.hasOwnProperty(property)) {
      """.}

      var nimProperty: cstring
      var nimValue: JsObject
      {.emit: "`nimProperty` = property; `nimValue` = `x`[property];".}
      result[$nimProperty] = nimValue.convertObject()
      {.emit: "}}".}
    of JInt:
      result = newJInt(x.to(int))
    of JFloat:
      result = newJFloat(x.to(float))
    of JString:
      # Dunno what to do with isUnquoted here
      if isRawNumber:
        var value: cstring
        {.emit: "`value` = `x`.toString();".}
        result = newJRawNumber($value)
      else:
        result = newJString($x.to(cstring))
    of JBool:
      result = newJBool(x.to(bool))
    of JNull:
      result = newJNull()

  proc parseJson*(buffer: string): JsonNode =
    when nimvm:
      return parseJson(newStringStream(buffer), "input")
    else:
      return parseNativeJson(buffer).convertObject()

else:
  proc parseJson*(buffer: string; rawIntegers = false, rawFloats = false): JsonNode =
    ## Parses JSON from `buffer`.
    ## If `buffer` contains extra data, it will raise `JsonParsingError`.
    ## If `rawIntegers` is true, integer literals will not be converted to a `JInt`
    ## field but kept as raw numbers via `JString`.
    ## If `rawFloats` is true, floating point literals will not be converted to a `JFloat`
    ## field but kept as raw numbers via `JString`.
    result = parseJson(newStringStream(buffer), "input", rawIntegers, rawFloats)

  proc parseFile*(filename: string): JsonNode =
    ## Parses `file` into a `JsonNode`.
    ## If `file` contains extra data, it will raise `JsonParsingError`.
    var stream = newFileStream(filename, fmRead)
    if stream == nil:
      raise newException(IOError, "cannot read from file: " & filename)
    result = parseJson(stream, filename, rawIntegers=false, rawFloats=false)

# -- Json deserialiser. --

template verifyJsonKind(node: JsonNode, kinds: set[JsonNodeKind],
                        ast: string) =
  if node == nil:
    raise newException(KeyError, "key not found: " & ast)
  elif  node.kind notin kinds:
    let msg = "Incorrect JSON kind. Wanted '$1' in '$2' but got '$3'." % [
      $kinds,
      ast,
      $node.kind
    ]
    raise newException(JsonKindError, msg)

macro isRefSkipDistinct*(arg: typed): untyped =
  ## internal only, do not use
  var impl = getTypeImpl(arg)
  if impl.kind == nnkBracketExpr and impl[0].eqIdent("typeDesc"):
    impl = getTypeImpl(impl[1])
  while impl.kind == nnkDistinctTy:
    impl = getTypeImpl(impl[0])
  result = newLit(impl.kind == nnkRefTy)

# The following forward declarations don't work in older versions of Nim

# forward declare all initFromJson

proc initFromJson(dst: var string; jsonNode: JsonNode; jsonPath: var string)
proc initFromJson(dst: var bool; jsonNode: JsonNode; jsonPath: var string)
proc initFromJson(dst: var JsonNode; jsonNode: JsonNode; jsonPath: var string)
proc initFromJson[T: SomeInteger](dst: var T; jsonNode: JsonNode, jsonPath: var string)
proc initFromJson[T: SomeFloat](dst: var T; jsonNode: JsonNode; jsonPath: var string)
proc initFromJson[T: enum](dst: var T; jsonNode: JsonNode; jsonPath: var string)
proc initFromJson[T](dst: var seq[T]; jsonNode: JsonNode; jsonPath: var string)
proc initFromJson[S, T](dst: var array[S, T]; jsonNode: JsonNode; jsonPath: var string)
proc initFromJson[T](dst: var Table[string, T]; jsonNode: JsonNode; jsonPath: var string)
proc initFromJson[T](dst: var OrderedTable[string, T]; jsonNode: JsonNode; jsonPath: var string)
proc initFromJson[T](dst: var ref T; jsonNode: JsonNode; jsonPath: var string)
proc initFromJson[T](dst: var Option[T]; jsonNode: JsonNode; jsonPath: var string)
proc initFromJson[T: distinct](dst: var T; jsonNode: JsonNode; jsonPath: var string)
proc initFromJson[T: object|tuple](dst: var T; jsonNode: JsonNode; jsonPath: var string)

# initFromJson definitions

proc initFromJson(dst: var string; jsonNode: JsonNode; jsonPath: var string) =
  verifyJsonKind(jsonNode, {JString, JNull}, jsonPath)
  # since strings don't have a nil state anymore, this mapping of
  # JNull to the default string is questionable. `none(string)` and
  # `some("")` have the same potentional json value `JNull`.
  if jsonNode.kind == JNull:
    dst = ""
  else:
    dst = jsonNode.str

proc initFromJson(dst: var bool; jsonNode: JsonNode; jsonPath: var string) =
  verifyJsonKind(jsonNode, {JBool}, jsonPath)
  dst = jsonNode.bval

proc initFromJson(dst: var JsonNode; jsonNode: JsonNode; jsonPath: var string) =
  if jsonNode == nil:
    raise newException(KeyError, "key not found: " & jsonPath)
  dst = jsonNode.copy

proc initFromJson[T: SomeInteger](dst: var T; jsonNode: JsonNode, jsonPath: var string) =
  when T is uint|uint64 or int.sizeof == 4:
    verifyJsonKind(jsonNode, {JInt, JString}, jsonPath)
    case jsonNode.kind
    of JString:
      let x = parseBiggestUInt(jsonNode.str)
      dst = cast[T](x)
    else:
      dst = T(jsonNode.num)
  else:
    verifyJsonKind(jsonNode, {JInt}, jsonPath)
    dst = cast[T](jsonNode.num)

proc initFromJson[T: SomeFloat](dst: var T; jsonNode: JsonNode; jsonPath: var string) =
  verifyJsonKind(jsonNode, {JInt, JFloat, JString}, jsonPath)
  if jsonNode.kind == JString:
    case jsonNode.str
    of "nan":
      let b = NaN
      dst = T(b)
      # dst = NaN # would fail some tests because range conversions would cause CT error
      # in some cases; but this is not a hot-spot inside this branch and backend can optimize this.
    of "inf":
      let b = Inf
      dst = T(b)
    of "-inf":
      let b = -Inf
      dst = T(b)
    else: raise newException(JsonKindError, "expected 'nan|inf|-inf', got " & jsonNode.str)
  else:
    if jsonNode.kind == JFloat:
      dst = T(jsonNode.fnum)
    else:
      dst = T(jsonNode.num)

proc initFromJson[T: enum](dst: var T; jsonNode: JsonNode; jsonPath: var string) =
  verifyJsonKind(jsonNode, {JString}, jsonPath)
  dst = parseEnum[T](jsonNode.getStr)

proc initFromJson[T](dst: var seq[T]; jsonNode: JsonNode; jsonPath: var string) =
  verifyJsonKind(jsonNode, {JArray}, jsonPath)
  dst.setLen jsonNode.len
  let orignalJsonPathLen = jsonPath.len
  for i in 0 ..< jsonNode.len:
    jsonPath.add '['
    jsonPath.addInt i
    jsonPath.add ']'
    initFromJson(dst[i], jsonNode[i], jsonPath)
    jsonPath.setLen orignalJsonPathLen

proc initFromJson[S,T](dst: var array[S,T]; jsonNode: JsonNode; jsonPath: var string) =
  verifyJsonKind(jsonNode, {JArray}, jsonPath)
  let originalJsonPathLen = jsonPath.len
  for i in 0 ..< jsonNode.len:
    jsonPath.add '['
    jsonPath.addInt i
    jsonPath.add ']'
    initFromJson(dst[i.S], jsonNode[i], jsonPath) # `.S` for enum indexed arrays
    jsonPath.setLen originalJsonPathLen

proc initFromJson[T](dst: var Table[string,T]; jsonNode: JsonNode; jsonPath: var string) =
  dst = initTable[string, T]()
  verifyJsonKind(jsonNode, {JObject}, jsonPath)
  let originalJsonPathLen = jsonPath.len
  for key in keys(jsonNode.fields):
    jsonPath.add '.'
    jsonPath.add key
    initFromJson(mgetOrPut(dst, key, default(T)), jsonNode[key], jsonPath)
    jsonPath.setLen originalJsonPathLen

proc initFromJson[T](dst: var OrderedTable[string,T]; jsonNode: JsonNode; jsonPath: var string) =
  dst = initOrderedTable[string,T]()
  verifyJsonKind(jsonNode, {JObject}, jsonPath)
  let originalJsonPathLen = jsonPath.len
  for key in keys(jsonNode.fields):
    jsonPath.add '.'
    jsonPath.add key
    initFromJson(mgetOrPut(dst, key, default(T)), jsonNode[key], jsonPath)
    jsonPath.setLen originalJsonPathLen

proc initFromJson[T](dst: var ref T; jsonNode: JsonNode; jsonPath: var string) =
  verifyJsonKind(jsonNode, {JObject, JNull}, jsonPath)
  if jsonNode.kind == JNull:
    dst = nil
  else:
    dst = new(T)
    initFromJson(dst[], jsonNode, jsonPath)

proc initFromJson[T](dst: var Option[T]; jsonNode: JsonNode; jsonPath: var string) =
  if jsonNode != nil and jsonNode.kind != JNull:
    when T is ref:
      dst = some(new(T))
    else:
      dst = some(default(T))
    initFromJson(dst.get, jsonNode, jsonPath)

macro assignDistinctImpl[T: distinct](dst: var T;jsonNode: JsonNode; jsonPath: var string) =
  let typInst = getTypeInst(dst)
  let typImpl = getTypeImpl(dst)
  let baseTyp = typImpl[0]

  result = quote do:
    initFromJson(`baseTyp`(`dst`), `jsonNode`, `jsonPath`)

proc initFromJson[T: distinct](dst: var T; jsonNode: JsonNode; jsonPath: var string) =
  assignDistinctImpl(dst, jsonNode, jsonPath)

proc detectIncompatibleType(typeExpr, lineinfoNode: NimNode) =
  if typeExpr.kind == nnkTupleConstr:
    error("Use a named tuple instead of: " & typeExpr.repr, lineinfoNode)

proc foldObjectBody(dst, typeNode, tmpSym, jsonNode, jsonPath, originalJsonPathLen: NimNode) =
  case typeNode.kind
  of nnkEmpty:
    discard
  of nnkRecList, nnkTupleTy:
    for it in typeNode:
      foldObjectBody(dst, it, tmpSym, jsonNode, jsonPath, originalJsonPathLen)

  of nnkIdentDefs:
    typeNode.expectLen 3
    let fieldSym = typeNode[0]
    let fieldNameLit = newLit(fieldSym.strVal)
    let fieldPathLit = newLit("." & fieldSym.strVal)
    let fieldType = typeNode[1]

    # Detecting incompatiple tuple types in `assignObjectImpl` only
    # would be much cleaner, but the ast for tuple types does not
    # contain usable type information.
    detectIncompatibleType(fieldType, fieldSym)

    dst.add quote do:
      jsonPath.add `fieldPathLit`
      when nimvm:
        when isRefSkipDistinct(`tmpSym`.`fieldSym`):
          # workaround #12489
          var tmp: `fieldType` = default(typeof(`fieldType`))
          initFromJson(tmp, getOrDefault(`jsonNode`,`fieldNameLit`), `jsonPath`)
          `tmpSym`.`fieldSym` = tmp
        else:
          initFromJson(`tmpSym`.`fieldSym`, getOrDefault(`jsonNode`,`fieldNameLit`), `jsonPath`)
      else:
        initFromJson(`tmpSym`.`fieldSym`, getOrDefault(`jsonNode`,`fieldNameLit`), `jsonPath`)
      jsonPath.setLen `originalJsonPathLen`

  of nnkRecCase:
    let kindSym = typeNode[0][0]
    let kindNameLit = newLit(kindSym.strVal)
    let kindPathLit = newLit("." & kindSym.strVal)
    let kindType = typeNode[0][1]
    let kindOffsetLit = newLit(uint(getOffset(kindSym)))
    dst.add quote do:
      var kindTmp: `kindType` = default(typeof(`kindType`))
      jsonPath.add `kindPathLit`
      initFromJson(kindTmp, `jsonNode`[`kindNameLit`], `jsonPath`)
      jsonPath.setLen `originalJsonPathLen`
      when defined js:
        `tmpSym`.`kindSym` = kindTmp
      else:
        when nimvm:
          `tmpSym`.`kindSym` = kindTmp
        else:
          # fuck it, assign kind field anyway
          ((cast[ptr `kindType`](cast[uint](`tmpSym`.addr) + `kindOffsetLit`))[]) = kindTmp
    dst.add nnkCaseStmt.newTree(nnkDotExpr.newTree(tmpSym, kindSym))
    for i in 1 ..< typeNode.len:
      foldObjectBody(dst, typeNode[i], tmpSym, jsonNode, jsonPath, originalJsonPathLen)

  of nnkOfBranch, nnkElse:
    let ofBranch = newNimNode(typeNode.kind)
    for i in 0 ..< typeNode.len-1:
      ofBranch.add copyNimTree(typeNode[i])
    let dstInner = newNimNode(nnkStmtListExpr)
    foldObjectBody(dstInner, typeNode[^1], tmpSym, jsonNode, jsonPath, originalJsonPathLen)
    # resOuter now contains the inner stmtList
    ofBranch.add dstInner
    dst[^1].expectKind nnkCaseStmt
    dst[^1].add ofBranch

  of nnkObjectTy:
    typeNode[0].expectKind nnkEmpty
    typeNode[1].expectKind {nnkEmpty, nnkOfInherit}
    if typeNode[1].kind == nnkOfInherit:
      let base = typeNode[1][0]
      var impl = getTypeImpl(base)
      while impl.kind in {nnkRefTy, nnkPtrTy}:
        impl = getTypeImpl(impl[0])
      foldObjectBody(dst, impl, tmpSym, jsonNode, jsonPath, originalJsonPathLen)
    let body = typeNode[2]
    foldObjectBody(dst, body, tmpSym, jsonNode, jsonPath, originalJsonPathLen)

  else:
    error("unhandled kind: " & $typeNode.kind, typeNode)

macro assignObjectImpl[T](dst: var T; jsonNode: JsonNode; jsonPath: var string) =
  let typeSym = getTypeInst(dst)
  let originalJsonPathLen = genSym(nskLet, "originalJsonPathLen")
  result = newStmtList()
  result.add quote do:
    let `originalJsonPathLen` = len(`jsonPath`)
  if typeSym.kind in {nnkTupleTy, nnkTupleConstr}:
    # both, `dst` and `typeSym` don't have good lineinfo. But nothing
    # else is available here.
    detectIncompatibleType(typeSym, dst)
    foldObjectBody(result, typeSym, dst, jsonNode, jsonPath, originalJsonPathLen)
  else:
    foldObjectBody(result, typeSym.getTypeImpl, dst, jsonNode, jsonPath, originalJsonPathLen)

proc initFromJson[T: object|tuple](dst: var T; jsonNode: JsonNode; jsonPath: var string) =
  assignObjectImpl(dst, jsonNode, jsonPath)

proc to*[T](node: JsonNode, t: typedesc[T]): T =
  ## `Unmarshals`:idx: the specified node into the object type specified.
  ##
  ## Known limitations:
  ##
  ##   * Heterogeneous arrays are not supported.
  ##   * Sets in object variants are not supported.
  ##   * Not nil annotations are not supported.
  ##
  runnableExamples:
    let jsonNode = parseJson("""
      {
        "person": {
          "name": "Nimmer",
          "age": 21
        },
        "list": [1, 2, 3, 4]
      }
    """)

    type
      Person = object
        name: string
        age: int

      Data = object
        person: Person
        list: seq[int]

    var data = to(jsonNode, Data)
    doAssert data.person.name == "Nimmer"
    doAssert data.person.age == 21
    doAssert data.list == @[1, 2, 3, 4]

  var jsonPath = ""
  result = default(T)
  initFromJson(result, node, jsonPath)

when false:
  import std/os
  var s = newFileStream(paramStr(1), fmRead)
  if s == nil: quit("cannot open the file" & paramStr(1))
  var x: JsonParser
  open(x, s, paramStr(1))
  while true:
    next(x)
    case x.kind
    of jsonError:
      Echo(x.errorMsg())
      break
    of jsonEof: break
    of jsonString, jsonInt, jsonFloat: echo(x.str)
    of jsonTrue: echo("!TRUE")
    of jsonFalse: echo("!FALSE")
    of jsonNull: echo("!NULL")
    of jsonObjectStart: echo("{")
    of jsonObjectEnd: echo("}")
    of jsonArrayStart: echo("[")
    of jsonArrayEnd: echo("]")

  close(x)

# { "json": 5 }
# To get that we shall use, obj["json"]

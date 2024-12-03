##[
This module implements a hookable (de)serialization for arbitrary types using JSON.
Design goal: avoid importing modules where a custom serialization is needed;
see strtabs.fromJsonHook,toJsonHook for an example.
]##

runnableExamples:
  import std/[strtabs,json]
  type Foo = ref object
    t: bool
    z1: int8
  let a = (1.5'f32, (b: "b2", a: "a2"), 'x', @[Foo(t: true, z1: -3), nil], [{"name": "John"}.newStringTable])
  let j = a.toJson
  assert j.jsonTo(typeof(a)).toJson == j
  assert $[NaN, Inf, -Inf, 0.0, -0.0, 1.0, 1e-2].toJson == """["nan","inf","-inf",0.0,-0.0,1.0,0.01]"""
  assert 0.0.toJson.kind == JFloat
  assert Inf.toJson.kind == JString

import std/[json, strutils, tables, sets, strtabs, options, strformat]

#[
Future directions:
add a way to customize serialization, for e.g.:
* field renaming
* allow serializing `enum` and `char` as `string` instead of `int`
  (enum is more compact/efficient, and robust to enum renamings, but string
  is more human readable)
* handle cyclic references, using a cache of already visited addresses
* implement support for serialization and de-serialization of nested variant
  objects.
]#

import std/macros
from std/enumutils import symbolName
from std/typetraits import OrdinalEnum, tupleLen

when defined(nimPreviewSlimSystem):
  import std/assertions


proc isNamedTuple(T: typedesc): bool {.magic: "TypeTrait".}

type
  Joptions* = object # xxx rename FromJsonOptions
    ## Options controlling the behavior of `fromJson`.
    allowExtraKeys*: bool
      ## If `true` Nim's object to which the JSON is parsed is not required to
      ## have a field for every JSON key.
    allowMissingKeys*: bool
      ## If `true` Nim's object to which JSON is parsed is allowed to have
      ## fields without corresponding JSON keys.
    # in future work: a key rename could be added
  EnumMode* = enum
    joptEnumOrd
    joptEnumSymbol
    joptEnumString
  JsonNodeMode* = enum ## controls `toJson` for JsonNode types
    joptJsonNodeAsRef ## returns the ref as is
    joptJsonNodeAsCopy ## returns a deep copy of the JsonNode
    joptJsonNodeAsObject ## treats JsonNode as a regular ref object
  ToJsonOptions* = object
    enumMode*: EnumMode
    jsonNodeMode*: JsonNodeMode
    # xxx charMode, etc

proc initToJsonOptions*(): ToJsonOptions =
  ## initializes `ToJsonOptions` with sane options.
  ToJsonOptions(enumMode: joptEnumOrd, jsonNodeMode: joptJsonNodeAsRef)

proc distinctBase(T: typedesc, recursive: static bool = true): typedesc {.magic: "TypeTrait".}
template distinctBase[T](a: T, recursive: static bool = true): untyped = distinctBase(typeof(a), recursive)(a)

macro getDiscriminants(a: typedesc): seq[string] =
  ## return the discriminant keys
  # candidate for std/typetraits
  var a = a.getTypeImpl
  doAssert a.kind == nnkBracketExpr
  let sym = a[1]
  let t = sym.getTypeImpl
  let t2 = t[2]
  case t2.kind
  of nnkEmpty: # allow empty objects
    result = quote do:
        seq[string].default
  of nnkRecList:
    result = newTree(nnkBracket)
    for ti in t2:
      if ti.kind == nnkRecCase:
        let key = ti[0][0]
        result.add newLit key.strVal
    if result.len > 0:
      result = quote do:
        @`result`
    else:
      result = quote do:
        seq[string].default
  else:
    raiseAssert "unexpected kind: " & $t2.kind

macro initCaseObject(T: typedesc, fun: untyped): untyped =
  ## does the minimum to construct a valid case object, only initializing
  ## the discriminant fields; see also `getDiscriminants`
  # maybe candidate for std/typetraits
  var a = T.getTypeImpl
  doAssert a.kind == nnkBracketExpr
  let sym = a[1]
  let t = sym.getTypeImpl
  var t2: NimNode
  case t.kind
  of nnkObjectTy: t2 = t[2]
  of nnkRefTy: t2 = t[0].getTypeImpl[2]
  else: raiseAssert $t.kind # xxx `nnkPtrTy` could be handled too
  doAssert t2.kind == nnkRecList
  result = newTree(nnkObjConstr)
  result.add T
  for ti in t2:
    if ti.kind == nnkRecCase:
      let key = ti[0][0]
      let typ = ti[0][1]
      let key2 = key.strVal
      let val = quote do:
        `fun`(`key2`, typedesc[`typ`])
      result.add newTree(nnkExprColonExpr, key, val)

proc raiseJsonException(condStr: string, msg: string) {.noinline.} =
  # just pick 1 exception type for simplicity; other choices would be:
  # JsonError, JsonParser, JsonKindError
  raise newException(ValueError, condStr & " failed: " & msg)

template checkJson(cond: untyped, msg = "") =
  if not cond:
    raiseJsonException(astToStr(cond), msg)

proc hasField[T](obj: T, field: string): bool =
  for k, _ in fieldPairs(obj):
    if k == field:
      return true
  return false

macro accessField(obj: typed, name: static string): untyped =
  newDotExpr(obj, ident(name))

template fromJsonFields(newObj, oldObj, json, discKeys, opt) =
  type T = typeof(newObj)
  # we could customize whether to allow JNull
  checkJson json.kind == JObject, $json.kind
  var num, numMatched = 0
  for key, val in fieldPairs(newObj):
    num.inc
    when key notin discKeys:
      if json.hasKey key:
        numMatched.inc
        fromJson(val, json[key], opt)
      elif opt.allowMissingKeys:
        # if there are no discriminant keys the `oldObj` must always have the
        # same keys as the new one. Otherwise we must check, because they could
        # be set to different branches.
        when typeof(oldObj) isnot typeof(nil):
          if discKeys.len == 0 or hasField(oldObj, key):
            val = accessField(oldObj, key)
      else:
        checkJson false, "key '$1' for $2 not in $3" % [key, $T, json.pretty()]
    else:
      if json.hasKey key:
        numMatched.inc

  let ok =
    if opt.allowExtraKeys and opt.allowMissingKeys:
      true
    elif opt.allowExtraKeys:
      # This check is redundant because if here missing keys are not allowed,
      # and if `num != numMatched` it will fail in the loop above but it is left
      # for clarity.
      assert num == numMatched
      num == numMatched
    elif opt.allowMissingKeys:
      json.len == numMatched
    else:
      json.len == num and num == numMatched

  checkJson ok, "There were $1 keys (expecting $2) for $3 with $4" % [$json.len, $num, $T, json.pretty()]

proc fromJson*[T](a: var T, b: JsonNode, opt = Joptions())

proc discKeyMatch[T](obj: T, json: JsonNode, key: static string): bool =
  if not json.hasKey key:
    return true
  let field = accessField(obj, key)
  var jsonVal: typeof(field) = default(typeof(field))
  fromJson(jsonVal, json[key])
  if jsonVal != field:
    return false
  return true

macro discKeysMatchBodyGen(obj: typed, json: JsonNode,
                           keys: static seq[string]): untyped =
  result = newStmtList()
  let r = ident("result")
  for key in keys:
    let keyLit = newLit key
    result.add quote do:
      `r` = `r` and discKeyMatch(`obj`, `json`, `keyLit`)

proc discKeysMatch[T](obj: T, json: JsonNode, keys: static seq[string]): bool =
  result = true
  discKeysMatchBodyGen(obj, json, keys)

proc fromJson*[T](a: var T, b: JsonNode, opt = Joptions()) =
  ## inplace version of `jsonTo`
  #[
  adding "json path" leading to `b` can be added in future work.
  ]#
  checkJson b != nil, $($T, b)
  when compiles(fromJsonHook(a, b, opt)): fromJsonHook(a, b, opt)
  elif compiles(fromJsonHook(a, b)): fromJsonHook(a, b)
  elif T is bool: a = to(b,T)
  elif T is enum:
    case b.kind
    of JInt: a = T(b.getBiggestInt())
    of JString: a = parseEnum[T](b.getStr())
    else: checkJson false, fmt"Expecting int/string for {$T} got {b.pretty()}"
  elif T is uint|uint64: a = T(to(b, uint64))
  elif T is Ordinal: a = cast[T](to(b, int))
  elif T is pointer: a = cast[pointer](to(b, int))
  elif T is distinct: a.distinctBase.fromJson(b)
  elif T is string|SomeNumber: a = to(b,T)
  elif T is cstring:
    case b.kind
    of JNull: a = nil
    of JString: a = b.str
    else: checkJson false, fmt"Expecting null/string for {$T} got {b.pretty()}"
  elif T is JsonNode: a = b
  elif T is ref | ptr:
    if b.kind == JNull: a = nil
    else:
      a = T()
      fromJson(a[], b, opt)
  elif T is array:
    checkJson a.len == b.len, fmt"Json array size doesn't match for {$T}"
    var i = 0
    for ai in mitems(a):
      fromJson(ai, b[i], opt)
      i.inc
  elif T is set:
    type E = typeof(for ai in a: ai)
    for val in b.getElems:
      incl a, jsonTo(val, E)
  elif T is seq:
    a.setLen b.len
    for i, val in b.getElems:
      fromJson(a[i], val, opt)
  elif T is object:
    template fun(key, typ): untyped {.used.} =
      if b.hasKey key:
        jsonTo(b[key], typ)
      elif hasField(a, key):
        accessField(a, key)
      else:
        default(typ)
    const keys = getDiscriminants(T)
    when keys.len == 0:
      fromJsonFields(a, nil, b, keys, opt)
    else:
      if discKeysMatch(a, b, keys):
        fromJsonFields(a, nil, b, keys, opt)
      else:
        var newObj = initCaseObject(T, fun)
        fromJsonFields(newObj, a, b, keys, opt)
        a = newObj
  elif T is tuple:
    when isNamedTuple(T):
      fromJsonFields(a, nil, b, seq[string].default, opt)
    else:
      checkJson b.kind == JArray, $(b.kind) # we could customize whether to allow JNull

      when compiles(tupleLen(T)):
        let tupleSize = tupleLen(T)
      else:
        # Tuple len isn't in csources_v1 so using tupleLen would fail.
        # Else branch basically never runs (tupleLen added in 1.1 and jsonutils in 1.4), but here for consistency
        var tupleSize = 0
        for val in fields(a):
          tupleSize.inc

      checkJson b.len == tupleSize, fmt"Json doesn't match expected length of {tupleSize}, got {b.pretty()}"
      var i = 0
      for val in fields(a):
        fromJson(val, b[i], opt)
        i.inc
  else:
    # checkJson not appropriate here
    static: raiseAssert "not yet implemented: " & $T

proc jsonTo*(b: JsonNode, T: typedesc, opt = Joptions()): T =
  ## reverse of `toJson`
  result = default(T)
  fromJson(result, b, opt)

proc toJson*[T](a: T, opt = initToJsonOptions()): JsonNode =
  ## serializes `a` to json; uses `toJsonHook(a: T)` if it's in scope to
  ## customize serialization, see strtabs.toJsonHook for an example.
  ##
  ## .. note:: With `-d:nimPreviewJsonutilsHoleyEnum`, `toJson` now can 
  ##    serialize/deserialize holey enums as regular enums (via `ord`) instead of as strings.
  ##    It is expected that this behavior becomes the new default in upcoming versions.
  when compiles(toJsonHook(a, opt)): result = toJsonHook(a, opt)
  elif compiles(toJsonHook(a)): result = toJsonHook(a)
  elif T is object | tuple:
    when T is object or isNamedTuple(T):
      result = newJObject()
      for k, v in a.fieldPairs: result[k] = toJson(v, opt)
    else:
      result = newJArray()
      for v in a.fields: result.add toJson(v, opt)
  elif T is ref | ptr:
    template impl =
      if system.`==`(a, nil): result = newJNull()
      else: result = toJson(a[], opt)
    when T is JsonNode:
      case opt.jsonNodeMode
      of joptJsonNodeAsRef: result = a
      of joptJsonNodeAsCopy: result = copy(a)
      of joptJsonNodeAsObject: impl()
    else: impl()
  elif T is array | seq | set:
    result = newJArray()
    for ai in a: result.add toJson(ai, opt)
  elif T is pointer: result = toJson(cast[int](a), opt)
    # edge case: `a == nil` could've also led to `newJNull()`, but this results
    # in simpler code for `toJson` and `fromJson`.
  elif T is distinct: result = toJson(a.distinctBase, opt)
  elif T is bool: result = %(a)
  elif T is SomeInteger: result = %a
  elif T is enum:
    case opt.enumMode
    of joptEnumOrd:
      when T is Ordinal or defined(nimPreviewJsonutilsHoleyEnum): %(a.ord)
      else: toJson($a, opt)
    of joptEnumSymbol:
      when T is OrdinalEnum:
        toJson(symbolName(a), opt)
      else:
        toJson($a, opt)
    of joptEnumString: toJson($a, opt)
  elif T is Ordinal: result = %(a.ord)
  elif T is cstring: (if a == nil: result = newJNull() else: result = % $a)
  else: result = %a

proc fromJsonHook*[K: string|cstring, V](t: var (Table[K, V] | OrderedTable[K, V]),
                         jsonNode: JsonNode, opt = Joptions()) =
  ## Enables `fromJson` for `Table` and `OrderedTable` types.
  ##
  ## See also:
  ## * `toJsonHook proc<#toJsonHook>`_
  runnableExamples:
    import std/[tables, json]
    var foo: tuple[t: Table[string, int], ot: OrderedTable[string, int]]
    fromJson(foo, parseJson("""
      {"t":{"two":2,"one":1},"ot":{"one":1,"three":3}}"""))
    assert foo.t == [("one", 1), ("two", 2)].toTable
    assert foo.ot == [("one", 1), ("three", 3)].toOrderedTable

  assert jsonNode.kind == JObject,
          "The kind of the `jsonNode` must be `JObject`, but its actual " &
          "type is `" & $jsonNode.kind & "`."
  clear(t)
  for k, v in jsonNode:
    t[k] = jsonTo(v, V, opt)

proc toJsonHook*[K: string|cstring, V](t: (Table[K, V] | OrderedTable[K, V]), opt = initToJsonOptions()): JsonNode =
  ## Enables `toJson` for `Table` and `OrderedTable` types.
  ##
  ## See also:
  ## * `fromJsonHook proc<#fromJsonHook,,JsonNode>`_
  runnableExamples:
    import std/[tables, json, sugar]
    let foo = (
      t: [("two", 2)].toTable,
      ot: [("one", 1), ("three", 3)].toOrderedTable)
    assert $toJson(foo) == """{"t":{"two":2},"ot":{"one":1,"three":3}}"""
    # if keys are not string|cstring, you can use this:
    let a = {10: "foo", 11: "bar"}.newOrderedTable
    let a2 = collect: (for k,v in a: (k,v))
    assert $toJson(a2) == """[[10,"foo"],[11,"bar"]]"""

  result = newJObject()
  for k, v in pairs(t):
    # not sure if $k has overhead for string
    result[(when K is string: k else: $k)] = toJson(v, opt)

proc fromJsonHook*[A](s: var SomeSet[A], jsonNode: JsonNode, opt = Joptions()) =
  ## Enables `fromJson` for `HashSet` and `OrderedSet` types.
  ##
  ## See also:
  ## * `toJsonHook proc<#toJsonHook,SomeSet[A]>`_
  runnableExamples:
    import std/[sets, json]
    var foo: tuple[hs: HashSet[string], os: OrderedSet[string]]
    fromJson(foo, parseJson("""
      {"hs": ["hash", "set"], "os": ["ordered", "set"]}"""))
    assert foo.hs == ["hash", "set"].toHashSet
    assert foo.os == ["ordered", "set"].toOrderedSet

  assert jsonNode.kind == JArray,
          "The kind of the `jsonNode` must be `JArray`, but its actual " &
          "type is `" & $jsonNode.kind & "`."
  clear(s)
  for v in jsonNode:
    incl(s, jsonTo(v, A, opt))

proc toJsonHook*[A](s: SomeSet[A], opt = initToJsonOptions()): JsonNode =
  ## Enables `toJson` for `HashSet` and `OrderedSet` types.
  ##
  ## See also:
  ## * `fromJsonHook proc<#fromJsonHook,SomeSet[A],JsonNode>`_
  runnableExamples:
    import std/[sets, json]
    let foo = (hs: ["hash"].toHashSet, os: ["ordered", "set"].toOrderedSet)
    assert $toJson(foo) == """{"hs":["hash"],"os":["ordered","set"]}"""

  result = newJArray()
  for k in s:
    add(result, toJson(k, opt))

proc fromJsonHook*[T](self: var Option[T], jsonNode: JsonNode, opt = Joptions()) =
  ## Enables `fromJson` for `Option` types.
  ##
  ## See also:
  ## * `toJsonHook proc<#toJsonHook,Option[T]>`_
  runnableExamples:
    import std/[options, json]
    var opt: Option[string]
    fromJsonHook(opt, parseJson("\"test\""))
    assert get(opt) == "test"
    fromJson(opt, parseJson("null"))
    assert isNone(opt)

  if jsonNode.kind != JNull:
    self = some(jsonTo(jsonNode, T, opt))
  else:
    self = none[T]()

proc toJsonHook*[T](self: Option[T], opt = initToJsonOptions()): JsonNode =
  ## Enables `toJson` for `Option` types.
  ##
  ## See also:
  ## * `fromJsonHook proc<#fromJsonHook,Option[T],JsonNode>`_
  runnableExamples:
    import std/[options, json]
    let optSome = some("test")
    assert $toJson(optSome) == "\"test\""
    let optNone = none[string]()
    assert $toJson(optNone) == "null"

  if isSome(self):
    toJson(get(self), opt)
  else:
    newJNull()

proc fromJsonHook*(a: var StringTableRef, b: JsonNode) =
  ## Enables `fromJson` for `StringTableRef` type.
  ##
  ## See also:
  ## * `toJsonHook proc<#toJsonHook,StringTableRef>`_
  runnableExamples:
    import std/[strtabs, json]
    var t = newStringTable(modeCaseSensitive)
    let jsonStr = """{"mode": 0, "table": {"name": "John", "surname": "Doe"}}"""
    fromJsonHook(t, parseJson(jsonStr))
    assert t[] == newStringTable("name", "John", "surname", "Doe",
                                 modeCaseSensitive)[]

  var mode = jsonTo(b["mode"], StringTableMode)
  a = newStringTable(mode)
  let b2 = b["table"]
  for k,v in b2: a[k] = jsonTo(v, string)

proc toJsonHook*(a: StringTableRef): JsonNode =
  ## Enables `toJson` for `StringTableRef` type.
  ##
  ## See also:
  ## * `fromJsonHook proc<#fromJsonHook,StringTableRef,JsonNode>`_
  runnableExamples:
    import std/[strtabs, json]
    let t = newStringTable("name", "John", "surname", "Doe", modeCaseSensitive)
    let jsonStr = """{"mode": "modeCaseSensitive",
                      "table": {"name": "John", "surname": "Doe"}}"""
    assert toJson(t) == parseJson(jsonStr)

  result = newJObject()
  result["mode"] = toJson($a.mode)
  let t = newJObject()
  for k,v in a: t[k] = toJson(v)
  result["table"] = t

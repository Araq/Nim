#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module contains procs for `serialization`:idx: and `deserialization`:idx:
## of arbitrary Nim data structures. The serialization format uses `JSON`:idx:.
##
## **Restriction:** For objects, their type is **not** serialized. This means
## essentially that it does not work if the object has some other runtime
## type than its compiletime type.
##
##
## Basic usage
## ===========
##
runnableExamples:
  type
    A = object of RootObj
    B = object of A
      f: int

  let a: ref A = new(B)
  assert $$a[] == "{}" # not "{f: 0}"

  # unmarshal
  let c = to[B]("""{"f": 2}""")
  assert typeof(c) is B
  assert c.f == 2

  # marshal
  assert $$c == """{"f": 2}"""

## **Note:** The `to` and `$$` operations are available at compile-time!
##
##
## See also
## ========
## * `streams module <streams.html>`_
## * `json module <json.html>`_

const unsupportedPlatform =
  when defined(js): "javascript"
  elif defined(nimscript): "nimscript"
  else: ""

when unsupportedPlatform != "":
  {.error: "marshal module is not supported in " & unsupportedPlatform & """.
Please use alternative packages for serialization.
It is possible to reimplement this module using generics and type traits.
Please contribute a new implementation.""".}

import std/[streams, typeinfo, json, intsets, tables, unicode]

when defined(nimPreviewSlimSystem):
  import std/[assertions, formatfloat]

proc ptrToInt(x: pointer): int {.inline.} =
  result = cast[int](x) # don't skip alignment

proc storeAny(s: Stream, a: Any, stored: var IntSet) =
  case a.kind
  of akNone: assert false
  of akBool: s.write($getBool(a))
  of akChar:
    let ch = getChar(a)
    if ch < '\128':
      s.write(escapeJson($ch))
    else:
      s.write($int(ch))
  of akArray, akSequence:
    s.write("[")
    for i in 0 .. a.len-1:
      if i > 0: s.write(", ")
      storeAny(s, a[i], stored)
    s.write("]")
  of akObject, akTuple:
    s.write("{")
    var i = 0
    for key, val in fields(a):
      if i > 0: s.write(", ")
      s.write(escapeJson(key))
      s.write(": ")
      storeAny(s, val, stored)
      inc(i)
    s.write("}")
  of akSet:
    s.write("[")
    var i = 0
    for e in elements(a):
      if i > 0: s.write(", ")
      s.write($e)
      inc(i)
    s.write("]")
  of akRange: storeAny(s, skipRange(a), stored)
  of akEnum: s.write(getEnumField(a).escapeJson)
  of akPtr, akRef:
    var x = a.getPointer
    if isNil(x): s.write("null")
    elif stored.containsOrIncl(x.ptrToInt):
      # already stored, so we simply write out the pointer as an int:
      s.write($x.ptrToInt)
    else:
      # else as a [value, key] pair:
      # (reversed order for convenient x[0] access!)
      s.write("[")
      s.write($x.ptrToInt)
      s.write(", ")
      storeAny(s, a[], stored)
      s.write("]")
  of akProc, akPointer, akCString: s.write($a.getPointer.ptrToInt)
  of akString:
    var x = getString(a)
    if x.validateUtf8() == -1: s.write(escapeJson(x))
    else:
      s.write("[")
      var i = 0
      for c in x:
        if i > 0: s.write(", ")
        s.write($ord(c))
        inc(i)
      s.write("]")
  of akInt..akInt64, akUInt..akUInt64: s.write($getBiggestInt(a))
  of akFloat..akFloat128: s.write($getBiggestFloat(a))

proc loadAny(p: var JsonParser, a: Any, t: var Table[BiggestInt, pointer]) =
  case a.kind
  of akNone: assert false
  of akBool:
    case p.kind
    of jsonFalse: setBiggestInt(a, 0)
    of jsonTrue: setBiggestInt(a, 1)
    else: raiseParseErr(p, "'true' or 'false' expected for a bool")
    next(p)
  of akChar:
    if p.kind == jsonString:
      var x = p.str
      if x.len == 1:
        setBiggestInt(a, ord(x[0]))
        next(p)
        return
    elif p.kind == jsonInt:
      setBiggestInt(a, getInt(p))
      next(p)
      return
    raiseParseErr(p, "string of length 1 expected for a char")
  of akEnum:
    if p.kind == jsonString:
      setBiggestInt(a, getEnumOrdinal(a, p.str))
      next(p)
      return
    raiseParseErr(p, "string expected for an enum")
  of akArray:
    if p.kind != jsonArrayStart: raiseParseErr(p, "'[' expected for an array")
    next(p)
    var i = 0
    while p.kind != jsonArrayEnd and p.kind != jsonEof:
      loadAny(p, a[i], t)
      inc(i)
    if p.kind == jsonArrayEnd: next(p)
    else: raiseParseErr(p, "']' end of array expected")
  of akSequence:
    case p.kind
    of jsonNull:
      when defined(nimSeqsV2):
        invokeNewSeq(a, 0)
      else:
        setPointer(a, nil)
      next(p)
    of jsonArrayStart:
      next(p)
      invokeNewSeq(a, 0)
      var i = 0
      while p.kind != jsonArrayEnd and p.kind != jsonEof:
        extendSeq(a)
        loadAny(p, a[i], t)
        inc(i)
      if p.kind == jsonArrayEnd: next(p)
      else: raiseParseErr(p, "")
    else:
      raiseParseErr(p, "'[' expected for a seq")
  of akObject, akTuple:
    if a.kind == akObject: setObjectRuntimeType(a)
    if p.kind != jsonObjectStart: raiseParseErr(p, "'{' expected for an object")
    next(p)
    while p.kind != jsonObjectEnd and p.kind != jsonEof:
      if p.kind != jsonString:
        raiseParseErr(p, "string expected for a field name")
      var fieldName = p.str
      next(p)
      loadAny(p, a[fieldName], t)
    if p.kind == jsonObjectEnd: next(p)
    else: raiseParseErr(p, "'}' end of object expected")
  of akSet:
    if p.kind != jsonArrayStart: raiseParseErr(p, "'[' expected for a set")
    next(p)
    while p.kind != jsonArrayEnd and p.kind != jsonEof:
      if p.kind != jsonInt: raiseParseErr(p, "int expected for a set")
      inclSetElement(a, p.getInt.int)
      next(p)
    if p.kind == jsonArrayEnd: next(p)
    else: raiseParseErr(p, "']' end of array expected")
  of akPtr, akRef:
    case p.kind
    of jsonNull:
      setPointer(a, nil)
      next(p)
    of jsonInt:
      var raw = t.getOrDefault(p.getInt)
      setPointer(a, addr raw)
      next(p)
    of jsonArrayStart:
      next(p)
      if a.kind == akRef: invokeNew(a)
      else: setPointer(a, alloc0(a.baseTypeSize))
      if p.kind == jsonInt:
        t[p.getInt] = getPointer(a)
        next(p)
      else: raiseParseErr(p, "index for ref type expected")
      loadAny(p, a[], t)
      if p.kind == jsonArrayEnd: next(p)
      else: raiseParseErr(p, "']' end of ref-address pair expected")
    else: raiseParseErr(p, "int for pointer type expected")
  of akProc, akPointer, akCString:
    case p.kind
    of jsonNull:
      setPointer(a, nil)
      next(p)
    of jsonInt:
      setPointer(a, cast[pointer](p.getInt.int))
      next(p)
    else: raiseParseErr(p, "int for pointer type expected")
  of akString:
    case p.kind
    of jsonNull:
      when defined(nimSeqsV2):
        setString(a, "")
      else:
        setPointer(a, nil)
      next(p)
    of jsonString:
      setString(a, p.str)
      next(p)
    of jsonArrayStart:
      next(p)
      var str = ""
      while p.kind == jsonInt:
        let code = p.getInt()
        if code < 0 or code > 255:
          raiseParseErr(p, "invalid charcode: " & $code)
        str.add(chr(code))
        next(p)
      if p.kind == jsonArrayEnd: next(p)
      else: raiseParseErr(p, "an array of charcodes expected for string")
      setString(a, str)
    else: raiseParseErr(p, "string expected")
  of akInt..akInt64, akUInt..akUInt64:
    if p.kind == jsonInt:
      setBiggestInt(a, getInt(p))
      next(p)
      return
    raiseParseErr(p, "int expected")
  of akFloat..akFloat128:
    if p.kind == jsonFloat:
      setBiggestFloat(a, getFloat(p))
      next(p)
      return
    raiseParseErr(p, "float expected")
  of akRange: loadAny(p, a.skipRange, t)

proc loadAny(s: Stream, a: Any, t: var Table[BiggestInt, pointer]) =
  var p: JsonParser
  open(p, s, "unknown file")
  next(p)
  loadAny(p, a, t)
  close(p)

proc load*[T](s: Stream, data: var T) =
  ## Loads `data` from the stream `s`. Raises `IOError` in case of an error.
  runnableExamples:
    import std/streams

    var s = newStringStream("[1, 3, 5]")
    var a: array[3, int]
    load(s, a)
    assert a == [1, 3, 5]

  var tab = initTable[BiggestInt, pointer]()
  loadAny(s, toAny(data), tab)

proc store*[T](s: Stream, data: sink T) =
  ## Stores `data` into the stream `s`. Raises `IOError` in case of an error.
  runnableExamples:
    import std/streams

    var s = newStringStream("")
    var a = [1, 3, 5]
    store(s, a)
    s.setPosition(0)
    assert s.readAll() == "[1, 3, 5]"

  var stored = initIntSet()
  var d: T
  when defined(gcArc) or defined(gcOrc)or defined(gcAtomicArc):
    d = data
  else:
    shallowCopy(d, data)
  storeAny(s, toAny(d), stored)

proc loadVM[T](typ: typedesc[T], x: T): string =
  raiseAssert "the implementation is in the compiler/vmops"

proc `$$`*[T](x: sink T): string =
  ## Returns a string representation of `x` (serialization, marshalling).
  ##
  ## **Note:** to serialize `x` to JSON use `%x` from the `json` module
  ## or `jsonutils.toJson(x)`.
  runnableExamples:
    type
      Foo = object
        id: int
        bar: string
    let x = Foo(id: 1, bar: "baz")
    ## serialize:
    let y = $$x
    assert y == """{"id": 1, "bar": "baz"}"""

  when nimvm:
    result = loadVM(T, x)
  else:
    var stored = initIntSet()
    var d: T
    when defined(gcArc) or defined(gcOrc) or defined(gcAtomicArc):
      d = x
    else:
      shallowCopy(d, x)
    var s = newStringStream()
    storeAny(s, toAny(d), stored)
    result = s.data

proc toVM[T](typ: typedesc[T], data: string): T =
  raiseAssert "the implementation is in the compiler/vmops"

proc to*[T](data: string): T =
  ## Reads data and transforms it to a type `T` (deserialization, unmarshalling).
  runnableExamples:
    type
      Foo = object
        id: int
        bar: string
    let y = """{"id": 1, "bar": "baz"}"""
    assert typeof(y) is string
    ## deserialize to type 'Foo':
    let z = y.to[:Foo]
    assert typeof(z) is Foo
    assert z.id == 1
    assert z.bar == "baz"

  when nimvm:
    result = toVM(T, data)
  else:
    result = default(T)
    var tab = initTable[BiggestInt, pointer]()
    loadAny(newStringStream(data), toAny(result), tab)

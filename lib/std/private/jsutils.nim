when defined(js):
  import std/jsbigints

  type
    ArrayBuffer* = ref object of JsRoot
    Float64Array* = ref object of JsRoot
    Uint32Array* = ref object of JsRoot
    Uint8Array* = ref object of JsRoot
    BigUint64Array* = ref object of JsRoot


  func newArrayBuffer*(n: int): ArrayBuffer {.importjs: "new ArrayBuffer(#)".}
  func newFloat64Array*(buffer: ArrayBuffer): Float64Array {.importjs: "new Float64Array(#)".}
  func newUint32Array*(buffer: ArrayBuffer): Uint32Array {.importjs: "new Uint32Array(#)".}
  func newBigUint64Array*(buffer: ArrayBuffer): BigUint64Array {.importjs: "new BigUint64Array(#)".}

  func newUint8Array*(n: int): Uint8Array {.importjs: "new Uint8Array(#)".}

  func `[]`*(arr: Uint32Array, i: int): uint32 {.importjs: "#[#]".}
  func `[]`*(arr: Uint8Array, i: int): uint8 {.importjs: "#[#]".}
  func `[]`*(arr: BigUint64Array, i: int): JsBigInt {.importjs: "#[#]".}
  func `[]=`*(arr: Float64Array, i: int, v: float) {.importjs: "#[#] = #".}

  proc jsTypeOf*[T](x: T): cstring {.importjs: "typeof(#)".} =
    ## Returns the name of the JsObject's JavaScript type as a cstring.
    # xxx replace jsffi.jsTypeOf with this definition and add tests
    runnableExamples:
      import std/[jsffi, jsbigints]
      assert jsTypeOf(1.toJs) == "number"
      assert jsTypeOf(false.toJs) == "boolean"
      assert [1].toJs.jsTypeOf == "object" # note the difference with `getProtoName`
      assert big"1".toJs.jsTypeOf == "bigint"

  proc jsConstructorName*[T](a: T): cstring =
    runnableExamples:
      import std/jsffi
      let a = array[2, float64].default
      assert jsConstructorName(a) == "Float64Array"
      assert jsConstructorName(a.toJs) == "Float64Array"
    {.emit: """`result` = `a`.constructor.name;""".}

  proc hasJsBigInt*(): bool =
    {.emit: """`result` = typeof BigInt != 'undefined';""".}

  proc hasBigUint64Array*(): bool =
    {.emit: """`result` = typeof BigUint64Array != 'undefined';""".}

  proc getProtoName*[T](a: T): cstring {.importjs: "Object.prototype.toString.call(#)".} =
    runnableExamples:
      import std/[jsffi, jsbigints]
      type A = ref object
      assert 1.toJs.getProtoName == "[object Number]"
      assert "a".toJs.getProtoName == "[object String]"
      assert big"1".toJs.getProtoName == "[object BigInt]"
      assert false.toJs.getProtoName == "[object Boolean]"
      assert (a: 1).toJs.getProtoName == "[object Object]"
      assert A.default.toJs.getProtoName == "[object Null]"
      assert [1].toJs.getProtoName == "[object Int32Array]" # implementation defined
      assert @[1].toJs.getProtoName == "[object Array]" # ditto

  const maxSafeInteger* = 9007199254740991
    ## The same as `Number.MAX_SAFE_INTEGER` or `2^53 - 1`.
    ## See https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Number/MAX_SAFE_INTEGER
  runnableExamples:
    let a {.importjs: "Number.MAX_SAFE_INTEGER".}: int64
    assert a == maxSafeInteger

  proc isInteger*[T](x: T): bool {.importjs: "Number.isInteger(#)".} =
    runnableExamples:
      import std/jsffi
      assert 1.isInteger
      assert not 1.5.isInteger
      assert 1.toJs.isInteger
      assert not 1.5.toJs.isInteger

  proc isSafeInteger*[T](x: T): bool {.importjs: "Number.isSafeInteger(#)".} =
    runnableExamples:
      import std/jsffi
      assert not "123".toJs.isSafeInteger
      assert 123.isSafeInteger
      assert 123.toJs.isSafeInteger
      when false:
        assert 9007199254740991.toJs.isSafeInteger
        assert not 9007199254740992.toJs.isSafeInteger

const jsNoBigInt64* =
  when defined(js):
    when compiles(compileOption("jsbigint64")):
      not compileOption("jsbigint64")
    else:
      true
  else:
    false

const hasWorkingInt64* =
  # equal to `not jsNoBigInt64`, but define it by itself anyway
  when defined(js):
    when compiles(compileOption("jsbigint64")):
      compileOption("jsbigint64")
    else:
      false
  else:
    true

#
#
#            Nim's Runtime Library
#        (c) Copyright 2017 Nim Authors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This Module implements types and macros to facilitate the wrapping of, and
## interaction with JavaScript libraries. Using the provided types `JsObject`
## and `JsAssoc` together with the provided macros allows for smoother
## interfacing with JavaScript, allowing for example quick and easy imports of
## JavaScript variables:

runnableExamples:
  # Here, we are using jQuery for just a few calls and do not want to wrap the
  # whole library:

  # import the document object and the console
  var document {.importc, nodecl.}: JsObject
  var console {.importc, nodecl.}: JsObject
  # import the "$" function
  proc jq(selector: JsObject): JsObject {.importjs: "$$(#)".}

  # Use jQuery to make the following code run, after the document is ready.
  # This uses an experimental `.()` operator for `JsObject`, to emit
  # JavaScript calls, when no corresponding proc exists for `JsObject`.
  proc main =
    jq(document).ready(proc() =
      console.log("Hello JavaScript!")
    )


when not defined(js) and not defined(nimsuggest):
  {.fatal: "Module jsFFI is designed to be used with the JavaScript backend.".}

import std/[macros, tables]

const
  setImpl = "#[#] = #"
  getImpl = "#[#]"

var
  mangledNames {.compileTime.} = initTable[string, string]()
  nameCounter {.compileTime.} = 0

proc validJsName(name: string): bool =
  result = true
  const reservedWords = ["break", "case", "catch", "class", "const", "continue",
    "debugger", "default", "delete", "do", "else", "export", "extends",
    "finally", "for", "function", "if", "import", "in", "instanceof", "new",
    "return", "super", "switch", "this", "throw", "try", "typeof", "var",
    "void", "while", "with", "yield", "enum", "implements", "interface",
    "let", "package", "private", "protected", "public", "static", "await",
    "abstract", "boolean", "byte", "char", "double", "final", "float", "goto",
    "int", "long", "native", "short", "synchronized", "throws", "transient",
    "volatile", "null", "true", "false"]
  case name
  of reservedWords: return false
  else: discard
  if name[0] notin {'A'..'Z','a'..'z','_','$'}: return false
  for chr in name:
    if chr notin {'A'..'Z','a'..'z','_','$','0'..'9'}:
      return false

template mangleJsName(name: string): string =
  inc nameCounter
  "mangledName" & $nameCounter

# only values that can be mapped 1 to 1 with cstring should be keys: they have an injective function with cstring

proc toJsKey*[T: SomeInteger](text: cstring, t: type T): T {.importjs: "parseInt(#)".}

proc toJsKey*[T: enum](text: cstring, t: type T): T =
  T(text.toJsKey(int))

proc toJsKey*(text: cstring, t: type cstring): cstring =
  text

proc toJsKey*[T: SomeFloat](text: cstring, t: type T): T {.importjs: "parseFloat(#)".}

type
  JsKey* = concept a, type T
    cstring.toJsKey(T) is T

  JsObject* = ref object of JsRoot
    ## Dynamically typed wrapper around a JavaScript object.
  JsAssoc*[K: JsKey, V] = ref object of JsRoot
    ## Statically typed wrapper around a JavaScript object.

  js* = JsObject

var
  jsArguments* {.importc: "arguments", nodecl}: JsObject
    ## JavaScript's arguments pseudo-variable.
  jsNull* {.importc: "null", nodecl.}: JsObject
    ## JavaScript's null literal.
  jsUndefined* {.importc: "undefined", nodecl.}: JsObject
    ## JavaScript's undefined literal.
  jsDirname* {.importc: "__dirname", nodecl.}: cstring
    ## JavaScript's __dirname pseudo-variable.
  jsFilename* {.importc: "__filename", nodecl.}: cstring
    ## JavaScript's __filename pseudo-variable.

proc isNull*[T](x: T): bool {.noSideEffect, importjs: "(# === null)".}
  ## Checks if a value is exactly null.

proc isUndefined*[T](x: T): bool {.noSideEffect, importjs: "(# === undefined)".}
  ## Checks if a value is exactly undefined.

# Exceptions
type
  JsError* {.importc: "Error".} = object of JsRoot
    message*: cstring
  JsEvalError* {.importc: "EvalError".} = object of JsError
  JsRangeError* {.importc: "RangeError".} = object of JsError
  JsReferenceError* {.importc: "ReferenceError".} = object of JsError
  JsSyntaxError* {.importc: "SyntaxError".} = object of JsError
  JsTypeError* {.importc: "TypeError".} = object of JsError
  JsURIError* {.importc: "URIError".} = object of JsError

# New
proc newJsObject*: JsObject {.importjs: "{@}".}
  ## Creates a new empty JsObject.

proc newJsAssoc*[K: JsKey, V]: JsAssoc[K, V] {.importjs: "{@}".}
  ## Creates a new empty JsAssoc with key type `K` and value type `V`.

# Checks
proc hasOwnProperty*(x: JsObject, prop: cstring): bool
  {.importjs: "#.hasOwnProperty(#)".}
  ## Checks, whether `x` has a property of name `prop`.

proc jsTypeOf*(x: JsObject): cstring {.importjs: "typeof(#)".}
  ## Returns the name of the JsObject's JavaScript type as a cstring.

proc jsNew*(x: auto): JsObject {.importjs: "(new #)".}
  ## Turns a regular function call into an invocation of the
  ## JavaScript's `new` operator.

proc jsDelete*(x: auto): JsObject {.importjs: "(delete #)".}
  ## JavaScript's `delete` operator.

proc require*(module: cstring): JsObject {.importc.}
  ## JavaScript's `require` function.

# Conversion to and from JsObject
proc to*(x: JsObject, T: typedesc): T {.importjs: "(#)".}
  ## Converts a JsObject `x` to type `T`.

proc toJs*[T](val: T): JsObject {.importjs: "(#)".}
  ## Converts a value of any type to type JsObject.

template toJs*(s: string): JsObject = cstring(s).toJs

macro jsFromAst*(n: untyped): untyped =
  result = n
  if n.kind == nnkStmtList:
    result = newProc(procType = nnkDo, body = result)
  return quote: toJs(`result`)

proc `&`*(a, b: cstring): cstring {.importjs: "(# + #)".}
  ## Concatenation operator for JavaScript strings.

proc `+`*(x, y: JsObject): JsObject {.importjs: "(# + #)".}
proc `-`*(x, y: JsObject): JsObject {.importjs: "(# - #)".}
proc `*`*(x, y: JsObject): JsObject {.importjs: "(# * #)".}
proc `/`*(x, y: JsObject): JsObject {.importjs: "(# / #)".}
proc `%`*(x, y: JsObject): JsObject {.importjs: "(# % #)".}
proc `+=`*(x, y: JsObject): JsObject {.importjs: "(# += #)", discardable.}
proc `-=`*(x, y: JsObject): JsObject {.importjs: "(# -= #)", discardable.}
proc `*=`*(x, y: JsObject): JsObject {.importjs: "(# *= #)", discardable.}
proc `/=`*(x, y: JsObject): JsObject {.importjs: "(# /= #)", discardable.}
proc `%=`*(x, y: JsObject): JsObject {.importjs: "(# %= #)", discardable.}
proc `++`*(x:    JsObject): JsObject {.importjs: "(++#)".}
proc `--`*(x:    JsObject): JsObject {.importjs: "(--#)".}
proc `>`*(x, y: JsObject): JsObject {.importjs: "(# > #)".}
proc `<`*(x, y: JsObject): JsObject {.importjs: "(# < #)".}
proc `>=`*(x, y: JsObject): JsObject {.importjs: "(# >= #)".}
proc `<=`*(x, y: JsObject): JsObject {.importjs: "(# <= #)".}
proc `**`*(x, y: JsObject): JsObject {.importjs: "((#) ** #)".}
  # (#) needed, refs https://github.com/nim-lang/Nim/pull/16409#issuecomment-760550812
proc `and`*(x, y: JsObject): JsObject {.importjs: "(# && #)".}
proc `or`*(x, y: JsObject): JsObject {.importjs: "(# || #)".}
proc `not`*(x:    JsObject): JsObject {.importjs: "(!#)".}
proc `in`*(x, y: JsObject): JsObject {.importjs: "(# in #)".}

proc `[]`*(obj: JsObject, field: cstring): JsObject {.importjs: getImpl.}
  ## Returns the value of a property of name `field` from a JsObject `obj`.

proc `[]`*(obj: JsObject, field: int): JsObject {.importjs: getImpl.}
  ## Returns the value of a property of name `field` from a JsObject `obj`.

proc `[]=`*[T](obj: JsObject, field: cstring, val: T) {.importjs: setImpl.}
  ## Sets the value of a property of name `field` in a JsObject `obj` to `v`.

proc `[]=`*[T](obj: JsObject, field: int, val: T) {.importjs: setImpl.}
  ## Sets the value of a property of name `field` in a JsObject `obj` to `v`.

proc `[]`*[K: JsKey, V](obj: JsAssoc[K, V], field: K): V
  {.importjs: getImpl.}
  ## Returns the value of a property of name `field` from a JsAssoc `obj`.

proc `[]=`*[K: JsKey, V](obj: JsAssoc[K, V], field: K, val: V)
  {.importjs: setImpl.}
  ## Sets the value of a property of name `field` in a JsAssoc `obj` to `v`.

proc `[]`*[V](obj: JsAssoc[cstring, V], field: string): V =
  obj[cstring(field)]

proc `[]=`*[V](obj: JsAssoc[cstring, V], field: string, val: V) =
  obj[cstring(field)] = val

proc `==`*(x, y: JsRoot): bool {.importjs: "(# === #)".}
  ## Compares two JsObjects or JsAssocs. Be careful though, as this is comparison
  ## like in JavaScript, so if your JsObjects are in fact JavaScript Objects,
  ## and not strings or numbers, this is a *comparison of references*.

{.experimental.}
macro `.`*(obj: JsObject, field: untyped): JsObject =
  ## Experimental dot accessor (get) for type JsObject.
  ## Returns the value of a property of name `field` from a JsObject `x`.
  runnableExamples:
    let obj = newJsObject()
    obj.a = 20
    assert obj.a.to(int) == 20
  if validJsName($field):
    let importString = "#." & $field
    let helperName = genSym(nskProc, "helper")
    result = quote do:
      proc `helperName`(o: JsObject): JsObject
        {.importjs: `importString`.}
      `helperName`(`obj`)
  else:
    if not mangledNames.hasKey($field):
      mangledNames[$field] = mangleJsName($field)
    let importString = "#." & mangledNames[$field]
    let helperName = genSym(nskProc, "helper")
    result = quote do:
      proc `helperName`(o: JsObject): JsObject
        {.importjs: `importString`.}
      `helperName`(`obj`)

macro `.=`*(obj: JsObject, field, value: untyped): untyped =
  ## Experimental dot accessor (set) for type JsObject.
  ## Sets the value of a property of name `field` in a JsObject `x` to `value`.
  if validJsName($field):
    let importString = "#." & $field & " = #"
    let helperName = genSym(nskProc, "helper")
    result = quote do:
      proc `helperName`(o: JsObject, v: auto)
        {.importjs: `importString`.}
      `helperName`(`obj`, `value`)
  else:
    if not mangledNames.hasKey($field):
      mangledNames[$field] = mangleJsName($field)
    let importString = "#." & mangledNames[$field] & " = #"
    let helperName = genSym(nskProc, "helper")
    result = quote do:
      proc `helperName`(o: JsObject, v: auto)
        {.importjs: `importString`.}
      `helperName`(`obj`, `value`)

macro `.()`*(obj: JsObject,
             field: untyped,
             args: varargs[JsObject, jsFromAst]): JsObject =
  ## Experimental "method call" operator for type JsObject.
  ## Takes the name of a method of the JavaScript object (`field`) and calls
  ## it with `args` as arguments, returning a JsObject (which may be discarded,
  ## and may be `undefined`, if the method does not return anything,
  ## so be careful when using this.)
  ##
  ## Example:
  ##   ```nim
  ##   # Let's get back to the console example:
  ##   var console {.importc, nodecl.}: JsObject
  ##   let res = console.log("I return undefined!")
  ##   console.log(res) # This prints undefined, as console.log always returns
  ##                    # undefined. Thus one has to be careful, when using
  ##                    # JsObject calls.
  ##   ```
  var importString: string
  if validJsName($field):
    importString = "#." & $field & "(@)"
  else:
    if not mangledNames.hasKey($field):
      mangledNames[$field] = mangleJsName($field)
    importString = "#." & mangledNames[$field] & "(@)"
  let helperName = genSym(nskProc, "helper")
  result = quote do:
    proc `helperName`(o: JsObject): JsObject
      {.importjs: `importString`, discardable.}
    `helperName`(`obj`)
  for idx in 0 ..< args.len:
    let paramName = newIdentNode("param" & $idx)
    result[0][3].add newIdentDefs(paramName, newIdentNode("JsObject"))
    result[1].add args[idx].copyNimTree

macro `.`*[K: cstring, V](obj: JsAssoc[K, V],
                                   field: untyped): V =
  ## Experimental dot accessor (get) for type JsAssoc.
  ## Returns the value of a property of name `field` from a JsObject `x`.
  var importString: string
  if validJsName($field):
    importString = "#." & $field
  else:
    if not mangledNames.hasKey($field):
      mangledNames[$field] = mangleJsName($field)
    importString = "#." & mangledNames[$field]
  let helperName = genSym(nskProc, "helper")
  result = quote do:
    proc `helperName`(o: type(`obj`)): `obj`.V
      {.importjs: `importString`.}
    `helperName`(`obj`)

macro `.=`*[K: cstring, V](obj: JsAssoc[K, V],
                                    field: untyped,
                                    value: V): untyped =
  ## Experimental dot accessor (set) for type JsAssoc.
  ## Sets the value of a property of name `field` in a JsObject `x` to `value`.
  var importString: string
  if validJsName($field):
    importString = "#." & $field & " = #"
  else:
    if not mangledNames.hasKey($field):
      mangledNames[$field] = mangleJsName($field)
    importString = "#." & mangledNames[$field] & " = #"
  let helperName = genSym(nskProc, "helper")
  result = quote do:
    proc `helperName`(o: type(`obj`), v: `obj`.V)
      {.importjs: `importString`.}
    `helperName`(`obj`, `value`)

macro `.()`*[K: cstring, V: proc](obj: JsAssoc[K, V],
                                           field: untyped,
                                           args: varargs[untyped]): auto =
  ## Experimental "method call" operator for type JsAssoc.
  ## Takes the name of a method of the JavaScript object (`field`) and calls
  ## it with `args` as arguments. Here, everything is typechecked, so you do not
  ## have to worry about `undefined` return values.
  let dotOp = bindSym"."
  result = quote do:
    (`dotOp`(`obj`, `field`))()
  for elem in args:
    result.add elem

# Iterators:

iterator pairs*(obj: JsObject): (cstring, JsObject) =
  ## Yields tuples of type `(cstring, JsObject)`, with the first entry
  ## being the `name` of a fields in the JsObject and the second being its
  ## value wrapped into a JsObject.
  var k: cstring
  var v: JsObject
  {.emit: "for (var `k` in `obj`) {".}
  {.emit: "  if (!`obj`.hasOwnProperty(`k`)) { continue; }".}
  {.emit: "  `v` = `obj`[`k`];".}
  yield (k, v)
  {.emit: "}".}

iterator items*(obj: JsObject): JsObject =
  ## Yields the `values` of each field in a JsObject, wrapped into a JsObject.
  var v: JsObject
  {.emit: "for (var k in `obj`) {".}
  {.emit: "  if (!`obj`.hasOwnProperty(k)) { continue; }".}
  {.emit: "  `v` = `obj`[k];".}
  yield v
  {.emit: "}".}

iterator keys*(obj: JsObject): cstring =
  ## Yields the `names` of each field in a JsObject.
  var k: cstring
  {.emit: "for (var `k` in `obj`) {".}
  {.emit: "  if (!`obj`.hasOwnProperty(`k`)) { continue; }".}
  yield k
  {.emit: "}".}

iterator pairs*[K: JsKey, V](assoc: JsAssoc[K, V]): (K,V) =
  ## Yields tuples of type `(K, V)`, with the first entry
  ## being a `key` in the JsAssoc and the second being its corresponding value.
  var k: cstring
  var v: V
  {.emit: "for (var `k` in `assoc`) {".}
  {.emit: "  if (!`assoc`.hasOwnProperty(`k`)) { continue; }".}
  {.emit: "  `v` = `assoc`[`k`];".}
  yield (k.toJsKey(K), v)
  {.emit: "}".}

iterator items*[K, V](assoc: JsAssoc[K, V]): V =
  ## Yields the `values` in a JsAssoc.
  var v: V
  {.emit: "for (var k in `assoc`) {".}
  {.emit: "  if (!`assoc`.hasOwnProperty(k)) { continue; }".}
  {.emit: "  `v` = `assoc`[k];".}
  yield v
  {.emit: "}".}

iterator keys*[K: JsKey, V](assoc: JsAssoc[K, V]): K =
  ## Yields the `keys` in a JsAssoc.
  var k: cstring
  {.emit: "for (var `k` in `assoc`) {".}
  {.emit: "  if (!`assoc`.hasOwnProperty(`k`)) { continue; }".}
  yield k.toJsKey(K)
  {.emit: "}".}

# Literal generation

macro `{}`*(typ: typedesc, xs: varargs[untyped]): auto =
  ## Takes a `typedesc` as its first argument, and a series of expressions of
  ## type `key: value`, and returns a value of the specified type with each
  ## field `key` set to `value`, as specified in the arguments of `{}`.
  ##
  ## Example:
  ##
  ##   ```nim
  ##   # Let's say we have a type with a ton of fields, where some fields do not
  ##   # need to be set, and we do not want those fields to be set to `nil`:
  ##   type
  ##     ExtremelyHugeType = ref object
  ##       a, b, c, d, e, f, g: int
  ##       h, i, j, k, l: cstring
  ##       # And even more fields ...
  ##
  ##   let obj = ExtremelyHugeType{ a: 1, k: "foo".cstring, d: 42 }
  ##
  ##   # This generates roughly the same JavaScript as:
  ##   {.emit: "var obj = {a: 1, k: "foo", d: 42};".}
  ##   ```
  let a = ident"a"
  var body = quote do:
    var `a` {.noinit.}: `typ`
    {.emit: "`a` = {};".}
  for x in xs.children:
    if x.kind == nnkExprColonExpr:
      let
        k = x[0]
        kString = quote do:
          when compiles($`k`): $`k` else: "invalid"
        v = x[1]
      body.add quote do:
        when compiles(`a`.`k`):
          `a`.`k` = `v`
        elif compiles(`a`[`k`]):
          `a`[`k`] = `v`
        else:
          `a`[`kString`] = `v`

    else:
      error("Expression `" & $x.toStrLit & "` not allowed in `{}` macro")

  body.add quote do:
    return `a`

  result = quote do:
    proc inner(): `typ` {.gensym.} =
      `body`
    inner()

# Macro to build a lambda using JavaScript's `this`
# from a proc, `this` being the first argument.

proc replaceSyms(n: NimNode): NimNode =
  if n.kind == nnkSym:
    result = newIdentNode($n)
  else:
    result = n
    for i in 0..<n.len:
      result[i] = replaceSyms(n[i])

macro bindMethod*(procedure: typed): auto {.deprecated: "Don't use it with closures".} =
  ## Takes the name of a procedure and wraps it into a lambda missing the first
  ## argument, which passes the JavaScript builtin `this` as the first
  ## argument to the procedure. Returns the resulting lambda.
  ##
  ## Example:
  ##
  ## We want to generate roughly this JavaScript:
  ##   ```js
  ##   var obj = {a: 10};
  ##   obj.someMethod = function() {
  ##     return this.a + 42;
  ##   };
  ##   ```
  ##
  ## We can achieve this using the `bindMethod` macro:
  ##
  ##   ```nim
  ##   let obj = JsObject{ a: 10 }
  ##   proc someMethodImpl(that: JsObject): int =
  ##     that.a.to(int) + 42
  ##   obj.someMethod = bindMethod someMethodImpl
  ##
  ##   # Alternatively:
  ##   obj.someMethod = bindMethod
  ##     proc(that: JsObject): int = that.a.to(int) + 42
  ##   ```
  if not (procedure.kind == nnkSym or procedure.kind == nnkLambda):
    error("Argument has to be a proc or a symbol corresponding to a proc.")
  var
    rawProc = if procedure.kind == nnkSym:
        getImpl(procedure)
      else:
        procedure
    args = rawProc[3].copyNimTree.replaceSyms
    thisType = args[1][1]
    params = newNimNode(nnkFormalParams).add(args[0])
    body = newNimNode(nnkLambda)
    this = newIdentNode("this")
    # construct the `this` parameter:
    thisQuote = quote do:
      var `this` {.nodecl, importc: "this".}: `thisType`
    call = newNimNode(nnkCall).add(rawProc[0], thisQuote[0][0][0])
  # construct the procedure call inside the method
  if args.len > 2:
    for idx in 2..args.len-1:
      params.add(args[idx])
      call.add(args[idx][0])
  body.add(newNimNode(nnkEmpty),
      rawProc[1],
      rawProc[2],
      params,
      rawProc[4],
      rawProc[5],
      newTree(nnkStmtList, thisQuote, call)
  )
  result = body

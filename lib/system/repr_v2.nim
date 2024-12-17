include system/inclrtl

when defined(nimPreviewSlimSystem):
  import std/formatfloat

proc isNamedTuple(T: typedesc): bool {.magic: "TypeTrait".}
  ## imported from typetraits

proc distinctBase(T: typedesc, recursive: static bool = true): typedesc {.magic: "TypeTrait".}
  ## imported from typetraits

proc rangeBase(T: typedesc): typedesc {.magic: "TypeTrait".}
  # skip one level of range; return the base type of a range type

proc repr*(x: NimNode): string {.magic: "Repr", noSideEffect.}

proc repr*(x: int): string =
  ## Same as $x
  $x

proc repr*(x: int64): string =
  ## Same as $x
  $x

proc repr*(x: uint64): string {.noSideEffect.} =
  ## Same as $x
  $x

proc repr*(x: float): string =
  ## Same as $x
  $x

proc repr*(x: bool): string {.magic: "BoolToStr", noSideEffect.}
  ## repr for a boolean argument. Returns `x`
  ## converted to the string "false" or "true".

proc repr*(x: char): string {.noSideEffect, raises: [].} =
  ## repr for a character argument. Returns `x`
  ## converted to an escaped string.
  ##
  ##   ```Nim
  ##   assert repr('c') == "'c'"
  ##   ```
  result = "'"
  # Elides string creations if not needed
  if x in {'\\', '\0'..'\31', '\127'..'\255'}:
    result.add '\\'
  if x in {'\0'..'\31', '\127'..'\255'}:
    result.add $x.uint8
  else:
    result.add x
  result.add '\''

proc repr*(x: string | cstring): string {.noSideEffect, raises: [].} =
  ## repr for a string argument. Returns `x`
  ## converted to a quoted and escaped string.
  result = "\""
  for i in 0..<x.len:
    if x[i] in {'"', '\\', '\0'..'\31', '\127'..'\255'}:
      result.add '\\'
    case x[i]:
    of '\n':
      result.add "n\n"
    of '\0'..'\9', '\11'..'\31', '\127'..'\255':
      result.add $x[i].uint8
    else:
      result.add x[i]
  result.add '\"'

proc repr*[Enum: enum](x: Enum): string {.magic: "EnumToStr", noSideEffect, raises: [].}
  ## repr for an enumeration argument. This works for
  ## any enumeration type thanks to compiler magic.
  ##
  ## If a `repr` operator for a concrete enumeration is provided, this is
  ## used instead. (In other words: *Overwriting* is possible.)

proc reprDiscriminant*(e: int): string {.compilerproc.} =
  # repr and reprjs can use `PNimType` to symbolize `e`; making this work here
  # would require a way to pass the set of enum stringified values to cgen.
  $e

proc repr*(p: pointer): string =
  ## repr of pointer as its hexadecimal value
  if p == nil:
    result = "nil"
  else:
    when nimvm:
      result = "ptr"
    else:
      const HexChars = "0123456789ABCDEF"
      const len = sizeof(pointer) * 2
      var n = cast[uint](p)
      result = newString(len)
      for j in countdown(len-1, 0):
        result[j] = HexChars[n and 0xF]
        n = n shr 4

proc repr*(p: proc | iterator {.closure.}): string =
  ## repr of a proc as its address
  repr(cast[ptr pointer](unsafeAddr p)[])

template repr*[T: distinct|(range and not enum)](x: T): string =
  when T is range: # add a branch to handle range
    repr(rangeBase(typeof(x))(x))
  elif T is distinct:
    repr(distinctBase(typeof(x))(x))
  else:
    {.error: "cannot happen".}

template repr*(t: typedesc): string = $t

proc reprObject[T: tuple|object](res: var string, x: T) {.noSideEffect, raises: [].} =
  res.add '('
  var firstElement = true
  const isNamed = T is object or isNamedTuple(T)
  when not isNamed:
    var count = 0
  for name, value in fieldPairs(x):
    if not firstElement: res.add(", ")
    when isNamed:
      res.add(name)
      res.add(": ")
    else:
      count.inc
    res.add repr(value)
    firstElement = false
  when not isNamed:
    if count == 1:
      res.add(',') # $(1,) should print as the semantically legal (1,)
  res.add(')')


proc repr*[T: tuple|object](x: T): string {.noSideEffect, raises: [].} =
  ## Generic `repr` operator for tuples that is lifted from the components
  ## of `x`. Example:
  ##   ```Nim
  ##   $(23, 45) == "(23, 45)"
  ##   $(a: 23, b: 45) == "(a: 23, b: 45)"
  ##   $() == "()"
  ##   ```
  when T is object:
    result = $typeof(x)
  else:
    result = ""
  reprObject(result, x)

proc repr*[T](x: ref T | ptr T): string {.noSideEffect, raises: [].} =
  if isNil(x): return "nil"
  when T is object:
    result = $typeof(x)
    reprObject(result, x[])
  else:
    result = when typeof(x) is ref: "ref " else: "ptr "
    result.add repr(x[])

proc collectionToRepr[T](x: T, prefix, separator, suffix: string): string {.noSideEffect, raises: [].} =
  result = prefix
  var firstElement = true
  for value in items(x):
    if firstElement:
      firstElement = false
    else:
      result.add(separator)
    result.add repr(value)
  result.add(suffix)

proc repr*[T](x: set[T]): string =
  ## Generic `repr` operator for sets that is lifted from the components
  ## of `x`. Example:
  ##   ```Nim
  ##   ${23, 45} == "{23, 45}"
  ##   ```
  collectionToRepr(x, "{", ", ", "}")

proc repr*[T](x: seq[T]): string =
  ## Generic `repr` operator for seqs that is lifted from the components
  ## of `x`. Example:
  ##   ```Nim
  ##   $(@[23, 45]) == "@[23, 45]"
  ##   ```
  collectionToRepr(x, "@[", ", ", "]")

proc repr*[T, IDX](x: array[IDX, T]): string =
  ## Generic `repr` operator for arrays that is lifted from the components.
  collectionToRepr(x, "[", ", ", "]")

proc repr*[T](x: openArray[T]): string =
  ## Generic `repr` operator for openarrays that is lifted from the components
  ## of `x`. Example:
  ##   ```Nim
  ##   $(@[23, 45].toOpenArray(0, 1)) == "[23, 45]"
  ##   ```
  collectionToRepr(x, "[", ", ", "]")

proc repr*[T](x: UncheckedArray[T]): string =
  "[...]"

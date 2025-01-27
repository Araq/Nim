# comparison operators:
proc `==`*[Enum: enum](x, y: Enum): bool {.magic: "EqEnum", noSideEffect.} =
  ## Checks whether values within the *same enum* have the same underlying value.
  runnableExamples:
    type
      Enum1 = enum
        field1 = 3, field2
      Enum2 = enum
        place1, place2 = 3
    var
      e1 = field1
      e2 = place2.ord.Enum1
    assert e1 == e2
    assert not compiles(e1 == place2) # raises error
proc `==`*(x, y: pointer): bool {.magic: "EqRef", noSideEffect.} =
  ## Checks for equality between two `pointer` variables.
  runnableExamples:
    var # this is a wildly dangerous example
      a = cast[pointer](0)
      b = cast[pointer](nil)
    assert a == b # true due to the special meaning of `nil`/0 as a pointer
proc `==`*(x, y: string): bool {.magic: "EqStr", noSideEffect.}
  ## Checks for equality between two `string` variables.

proc `==`*(x, y: char): bool {.magic: "EqCh", noSideEffect.}
  ## Checks for equality between two `char` variables.
proc `==`*(x, y: bool): bool {.magic: "EqB", noSideEffect.}
  ## Checks for equality between two `bool` variables.
proc `==`*[T](x, y: set[T]): bool {.magic: "EqSet", noSideEffect.} =
  ## Checks for equality between two variables of type `set`.
  runnableExamples:
    assert {1, 2, 2, 3} == {1, 2, 3} # duplication in sets is ignored

proc `==`*[T](x, y: ref T): bool {.magic: "EqRef", noSideEffect.}
  ## Checks that two `ref` variables refer to the same item.
proc `==`*[T](x, y: ptr T): bool {.magic: "EqRef", noSideEffect.}
  ## Checks that two `ptr` variables refer to the same item.
proc `==`*[T: proc | iterator](x, y: T): bool {.magic: "EqProc", noSideEffect.}
  ## Checks that two `proc` variables refer to the same procedure.

proc `<=`*[Enum: enum](x, y: Enum): bool {.magic: "LeEnum", noSideEffect.}
proc `<=`*(x, y: string): bool {.magic: "LeStr", noSideEffect.} =
  ## Compares two strings and returns true if `x` is lexicographically
  ## before `y` (uppercase letters come before lowercase letters).
  runnableExamples:
    let
      a = "abc"
      b = "abd"
      c = "ZZZ"
    assert a <= b
    assert a <= a
    assert not (a <= c)

proc `<=`*(x, y: char): bool {.magic: "LeCh", noSideEffect.} =
  ## Compares two chars and returns true if `x` is lexicographically
  ## before `y` (uppercase letters come before lowercase letters).
  runnableExamples:
    let
      a = 'a'
      b = 'b'
      c = 'Z'
    assert a <= b
    assert a <= a
    assert not (a <= c)

proc `<=`*[T](x, y: set[T]): bool {.magic: "LeSet", noSideEffect.} =
  ## Returns true if `x` is a subset of `y`.
  ##
  ## A subset `x` has all of its members in `y` and `y` doesn't necessarily
  ## have more members than `x`. That is, `x` can be equal to `y`.
  runnableExamples:
    let
      a = {3, 5}
      b = {1, 3, 5, 7}
      c = {2}
    assert a <= b
    assert a <= a
    assert not (a <= c)

proc `<=`*(x, y: bool): bool {.magic: "LeB", noSideEffect.}
proc `<=`*[T](x, y: ref T): bool {.magic: "LePtr", noSideEffect.}
proc `<=`*(x, y: pointer): bool {.magic: "LePtr", noSideEffect.}

proc `<`*[Enum: enum](x, y: Enum): bool {.magic: "LtEnum", noSideEffect.}
proc `<`*(x, y: string): bool {.magic: "LtStr", noSideEffect.} =
  ## Compares two strings and returns true if `x` is lexicographically
  ## before `y` (uppercase letters come before lowercase letters).
  runnableExamples:
    let
      a = "abc"
      b = "abd"
      c = "ZZZ"
    assert a < b
    assert not (a < a)
    assert not (a < c)

proc `<`*(x, y: char): bool {.magic: "LtCh", noSideEffect.} =
  ## Compares two chars and returns true if `x` is lexicographically
  ## before `y` (uppercase letters come before lowercase letters).
  runnableExamples:
    let
      a = 'a'
      b = 'b'
      c = 'Z'
    assert a < b
    assert not (a < a)
    assert not (a < c)

proc `<`*[T](x, y: set[T]): bool {.magic: "LtSet", noSideEffect.} =
  ## Returns true if `x` is a strict or proper subset of `y`.
  ##
  ## A strict or proper subset `x` has all of its members in `y` but `y` has
  ## more elements than `y`.
  runnableExamples:
    let
      a = {3, 5}
      b = {1, 3, 5, 7}
      c = {2}
    assert a < b
    assert not (a < a)
    assert not (a < c)

proc `<`*(x, y: bool): bool {.magic: "LtB", noSideEffect.}
proc `<`*[T](x, y: ref T): bool {.magic: "LtPtr", noSideEffect.}
proc `<`*[T](x, y: ptr T): bool {.magic: "LtPtr", noSideEffect.}
proc `<`*(x, y: pointer): bool {.magic: "LtPtr", noSideEffect.}

when not defined(nimHasCallsitePragma):
  {.pragma: callsite.}

template `!=`*(x, y: untyped): untyped {.callsite.} =
  ## Unequals operator. This is a shorthand for `not (x == y)`.
  not (x == y)

template `>=`*(x, y: untyped): untyped {.callsite.} =
  ## "is greater or equals" operator. This is the same as `y <= x`.
  y <= x

template `>`*(x, y: untyped): untyped {.callsite.} =
  ## "is greater" operator. This is the same as `y < x`.
  y < x


proc `==`*(x, y: int): bool {.magic: "EqI", noSideEffect.}
  ## Compares two integers for equality.
proc `==`*(x, y: int8): bool {.magic: "EqI", noSideEffect.}
proc `==`*(x, y: int16): bool {.magic: "EqI", noSideEffect.}
proc `==`*(x, y: int32): bool {.magic: "EqI", noSideEffect.}
proc `==`*(x, y: int64): bool {.magic: "EqI", noSideEffect.}

proc `<=`*(x, y: int): bool {.magic: "LeI", noSideEffect.}
  ## Returns true if `x` is less than or equal to `y`.
proc `<=`*(x, y: int8): bool {.magic: "LeI", noSideEffect.}
proc `<=`*(x, y: int16): bool {.magic: "LeI", noSideEffect.}
proc `<=`*(x, y: int32): bool {.magic: "LeI", noSideEffect.}
proc `<=`*(x, y: int64): bool {.magic: "LeI", noSideEffect.}

proc `<`*(x, y: int): bool {.magic: "LtI", noSideEffect.}
  ## Returns true if `x` is less than `y`.
proc `<`*(x, y: int8): bool {.magic: "LtI", noSideEffect.}
proc `<`*(x, y: int16): bool {.magic: "LtI", noSideEffect.}
proc `<`*(x, y: int32): bool {.magic: "LtI", noSideEffect.}
proc `<`*(x, y: int64): bool {.magic: "LtI", noSideEffect.}

proc `<=`*(x, y: uint): bool {.magic: "LeU", noSideEffect.}
  ## Returns true if `x <= y`.
proc `<=`*(x, y: uint8): bool {.magic: "LeU", noSideEffect.}
proc `<=`*(x, y: uint16): bool {.magic: "LeU", noSideEffect.}
proc `<=`*(x, y: uint32): bool {.magic: "LeU", noSideEffect.}
proc `<=`*(x, y: uint64): bool {.magic: "LeU", noSideEffect.}

proc `<`*(x, y: uint): bool {.magic: "LtU", noSideEffect.}
  ## Returns true if `x < y`.
proc `<`*(x, y: uint8): bool {.magic: "LtU", noSideEffect.}
proc `<`*(x, y: uint16): bool {.magic: "LtU", noSideEffect.}
proc `<`*(x, y: uint32): bool {.magic: "LtU", noSideEffect.}
proc `<`*(x, y: uint64): bool {.magic: "LtU", noSideEffect.}

proc `<=%`*(x, y: int): bool {.inline.} =
  ## Treats `x` and `y` as unsigned and compares them.
  ## Returns true if `unsigned(x) <= unsigned(y)`.
  cast[uint](x) <= cast[uint](y)
proc `<=%`*(x, y: int8): bool {.inline.} = cast[uint8](x) <= cast[uint8](y)
proc `<=%`*(x, y: int16): bool {.inline.} = cast[uint16](x) <= cast[uint16](y)
proc `<=%`*(x, y: int32): bool {.inline.} = cast[uint32](x) <= cast[uint32](y)
proc `<=%`*(x, y: int64): bool {.inline.} = cast[uint64](x) <= cast[uint64](y)

proc `<%`*(x, y: int): bool {.inline.} =
  ## Treats `x` and `y` as unsigned and compares them.
  ## Returns true if `unsigned(x) < unsigned(y)`.
  cast[uint](x) < cast[uint](y)
proc `<%`*(x, y: int8): bool {.inline.} = cast[uint8](x) < cast[uint8](y)
proc `<%`*(x, y: int16): bool {.inline.} = cast[uint16](x) < cast[uint16](y)
proc `<%`*(x, y: int32): bool {.inline.} = cast[uint32](x) < cast[uint32](y)
proc `<%`*(x, y: int64): bool {.inline.} = cast[uint64](x) < cast[uint64](y)

template `>=%`*(x, y: untyped): untyped = y <=% x
  ## Treats `x` and `y` as unsigned and compares them.
  ## Returns true if `unsigned(x) >= unsigned(y)`.

template `>%`*(x, y: untyped): untyped = y <% x
  ## Treats `x` and `y` as unsigned and compares them.
  ## Returns true if `unsigned(x) > unsigned(y)`.

proc `==`*(x, y: uint): bool {.magic: "EqI", noSideEffect.}
  ## Compares two unsigned integers for equality.
proc `==`*(x, y: uint8): bool {.magic: "EqI", noSideEffect.}
proc `==`*(x, y: uint16): bool {.magic: "EqI", noSideEffect.}
proc `==`*(x, y: uint32): bool {.magic: "EqI", noSideEffect.}
proc `==`*(x, y: uint64): bool {.magic: "EqI", noSideEffect.}

proc `<=`*(x, y: float32): bool {.magic: "LeF64", noSideEffect.}
proc `<=`*(x, y: float): bool {.magic: "LeF64", noSideEffect.}

proc `<`*(x, y: float32): bool {.magic: "LtF64", noSideEffect.}
proc `<`*(x, y: float): bool {.magic: "LtF64", noSideEffect.}

proc `==`*(x, y: float32): bool {.magic: "EqF64", noSideEffect.}
proc `==`*(x, y: float): bool {.magic: "EqF64", noSideEffect.}

{.push stackTrace: off.}

proc min*(x, y: int): int {.magic: "MinI", noSideEffect.} =
  if x <= y: x else: y
proc min*(x, y: int8): int8 {.magic: "MinI", noSideEffect.} =
  if x <= y: x else: y
proc min*(x, y: int16): int16 {.magic: "MinI", noSideEffect.} =
  if x <= y: x else: y
proc min*(x, y: int32): int32 {.magic: "MinI", noSideEffect.} =
  if x <= y: x else: y
proc min*(x, y: int64): int64 {.magic: "MinI", noSideEffect.} =
  ## The minimum value of two integers.
  if x <= y: x else: y
proc min*(x, y: float32): float32 {.noSideEffect, inline.} =
  if x <= y or y != y: x else: y
proc min*(x, y: float64): float64 {.noSideEffect, inline.} =
  if x <= y or y != y: x else: y
proc min*[T: not SomeFloat](x, y: T): T {.inline.} =
  ## Generic minimum operator of 2 values based on `<=`.
  if x <= y: x else: y

proc max*(x, y: int): int {.magic: "MaxI", noSideEffect.} =
  if y <= x: x else: y
proc max*(x, y: int8): int8 {.magic: "MaxI", noSideEffect.} =
  if y <= x: x else: y
proc max*(x, y: int16): int16 {.magic: "MaxI", noSideEffect.} =
  if y <= x: x else: y
proc max*(x, y: int32): int32 {.magic: "MaxI", noSideEffect.} =
  if y <= x: x else: y
proc max*(x, y: int64): int64 {.magic: "MaxI", noSideEffect.} =
  ## The maximum value of two integers.
  if y <= x: x else: y
proc max*(x, y: float32): float32 {.noSideEffect, inline.} =
  if y <= x or y != y: x else: y
proc max*(x, y: float64): float64 {.noSideEffect, inline.} =
  if y <= x or y != y: x else: y
proc max*[T: not SomeFloat](x, y: T): T {.inline.} =
  ## Generic maximum operator of 2 values based on `<=`.
  if y <= x: x else: y


proc min*[T](x: openArray[T]): T =
  ## The minimum value of `x`. `T` needs to have a `<` operator.
  result = x[0]
  for i in 1..high(x):
    if x[i] < result: result = x[i]

proc max*[T](x: openArray[T]): T =
  ## The maximum value of `x`. `T` needs to have a `<` operator.
  result = x[0]
  for i in 1..high(x):
    if result < x[i]: result = x[i]

{.pop.} # stackTrace: off


proc clamp*[T](x, a, b: T): T =
  ## Limits the value `x` within the interval \[a, b].
  ## This proc is equivalent to but faster than `max(a, min(b, x))`.
  ## 
  ## .. warning:: `a <= b` is assumed and will not be checked (currently).
  ##
  ## **See also:**
  ## `math.clamp` for a version that takes a `Slice[T]` instead.
  runnableExamples:
    assert (1.4).clamp(0.0, 1.0) == 1.0
    assert (0.5).clamp(0.0, 1.0) == 0.5
    assert 4.clamp(1, 3) == max(1, min(3, 4))
  if x < a: return a
  if x > b: return b
  return x


proc `==`*[I, T](x, y: array[I, T]): bool =
  for f in low(x)..high(x):
    if x[f] != y[f]:
      return
  result = true

proc `==`*[T](x, y: openArray[T]): bool =
  if x.len != y.len:
    return false
  for f in low(x)..high(x):
    if x[f] != y[f]:
      return false
  result = true


proc `==`*[T](x, y: seq[T]): bool {.noSideEffect.} =
  ## Generic equals operator for sequences: relies on a equals operator for
  ## the element type `T`.
  when nimvm:
    if x.len == 0 and y.len == 0:
      return true
  else:
    when not defined(js):
      proc seqToPtr[T](x: seq[T]): pointer {.inline, noSideEffect.} =
        when defined(nimSeqsV2):
          result = cast[NimSeqV2[T]](x).p
        else:
          result = cast[pointer](x)

      if seqToPtr(x) == seqToPtr(y):
        return true
    else:
      var sameObject = false
      {.emit: """`sameObject` = `x` === `y`;""".}
      if sameObject: return true

  if x.len != y.len:
    return false

  for i in 0..x.len-1:
    if x[i] != y[i]:
      return false

  return true

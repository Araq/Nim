{.experimental: "openSym".}

block: # issue #24002
  type Result[T, E] = object
  func value[T, E](self: Result[T, E]): T {.inline.} =
    discard
  func value[T: not void, E](self: var Result[T, E]): var T {.inline.} =
    discard
  template unrecognizedFieldWarning =
    doAssert value == 123
    let x = value
    doAssert value == x
  proc readValue(value: var int) =
    unrecognizedFieldWarning()
  var foo: int = 123
  readValue(foo)

block: # issue #22605 for templates, normal call syntax
  const error = "bad"

  template valueOr(self: int, def: untyped): untyped =
    case false
    of true: ""
    of false:
      template error: untyped {.used, inject.} = "good"
      def

  template g(T: type): string =
    var res = "ok"
    let x = valueOr 123:
      res = $error
      "dummy"
    res

  doAssert g(int) == "good"

  template g2(T: type): string =
    bind error # use the bad version on purpose
    var res = "ok"
    let x = valueOr 123:
      res = $error
      "dummy"
    res

  doAssert g2(int) == "bad"

block: # issue #22605 for templates, method call syntax
  const error = "bad"

  template valueOr(self: int, def: untyped): untyped =
    case false
    of true: ""
    of false:
      template error: untyped {.used, inject.} = "good"
      def

  template g(T: type): string =
    var res = "ok"
    let x = 123.valueOr:
      res = $error
      "dummy"
    res

  doAssert g(int) == "good"

  template g2(T: type): string =
    bind error # use the bad version on purpose
    var res = "ok"
    let x = 123.valueOr:
      res = $error
      "dummy"
    res

  doAssert g2(int) == "bad"

block: # issue #22605 for templates, original complex example
  type Xxx = enum
    error
    value

  type
    Result[T, E] = object
      when T is void:
        when E is void:
          oResultPrivate*: bool
        else:
          case oResultPrivate*: bool
          of false:
            eResultPrivate*: E
          of true:
            discard
      else:
        when E is void:
          case oResultPrivate*: bool
          of false:
            discard
          of true:
            vResultPrivate*: T
        else:
          case oResultPrivate*: bool
          of false:
            eResultPrivate*: E
          of true:
            vResultPrivate*: T

  template valueOr[T: not void, E](self: Result[T, E], def: untyped): untyped =
    let s = (self) # TODO avoid copy
    case s.oResultPrivate
    of true:
      s.vResultPrivate
    of false:
      when E isnot void:
        template error: untyped {.used, inject.} = s.eResultPrivate
      def

  proc f(): Result[int, cstring] =
    Result[int, cstring](oResultPrivate: false, eResultPrivate: "f")

  template g(T: type): string =
    var res = "ok"
    let x = f().valueOr:
      res = $error
      123
    res

  doAssert g(int) == "f"

  template g2(T: type): string =
    bind error # use the bad version on purpose
    var res = "ok"
    let x = f().valueOr:
      res = $error
      123
    res

  doAssert g2(int) == "error"

block: # issue #23865 for templates
  type Xxx = enum
    error
    value

  type
    Result[T, E] = object
      when T is void:
        when E is void:
          oResultPrivate: bool
        else:
          case oResultPrivate: bool
          of false:
            eResultPrivate: E
          of true:
            discard
      else:
        when E is void:
          case oResultPrivate: bool
          of false:
            discard
          of true:
            vResultPrivate: T
        else:
          case oResultPrivate: bool
          of false:
            eResultPrivate: E
          of true:
            vResultPrivate: T

  func error[T, E](self: Result[T, E]): E =
    ## Fetch error of result if set, or raise Defect
    case self.oResultPrivate
    of true:
      when T isnot void:
        raiseResultDefect("Trying to access error when value is set", self.vResultPrivate)
      else:
        raiseResultDefect("Trying to access error when value is set")
    of false:
      when E isnot void:
        self.eResultPrivate

  template valueOr[T: not void, E](self: Result[T, E], def: untyped): untyped =
    let s = (self) # TODO avoid copy
    case s.oResultPrivate
    of true:
      s.vResultPrivate
    of false:
      when E isnot void:
        template error: untyped {.used, inject.} = s.eResultPrivate
      def
  proc f(): Result[int, cstring] =
    Result[int, cstring](oResultPrivate: false, eResultPrivate: "f")
  template g(T: type): string =
    var res = "ok"
    let x = f().valueOr:
      res = $error
      123
    res
  doAssert g(int) == "f"

import std/sequtils

block: # issue #15314
  var it: string
  var nums = @[1,2,3]

  template doubleNums() =
    nums.applyIt(it * 2)

  doubleNums()
  doAssert nums == @[2, 4, 6]

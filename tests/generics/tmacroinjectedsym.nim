{.experimental: "openSym".}

block: # issue #22605, normal call syntax
  const error = "bad"

  template valueOr(self: int, def: untyped): untyped =
    case false
    of true: ""
    of false:
      template error: untyped {.used, inject.} = "good"
      def

  proc g(T: type): string =
    let x = valueOr 123:
      return $error

    "ok"

  doAssert g(int) == "good"

  proc g2(T: type): string =
    bind error # use the bad version on purpose
    let x = valueOr 123:
      return $error

    "ok"

  doAssert g2(int) == "bad"

block: # issue #22605, method call syntax
  const error = "bad"

  template valueOr(self: int, def: untyped): untyped =
    case false
    of true: ""
    of false:
      template error: untyped {.used, inject.} = "good"
      def

  proc g(T: type): string =
    let x = 123.valueOr:
      return $error

    "ok"

  doAssert g(int) == "good"

  proc g2(T: type): string =
    bind error # use the bad version on purpose
    let x = 123.valueOr:
      return $error

    "ok"

  doAssert g2(int) == "bad"

block: # issue #22605, original complex example
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

  proc g(T: type): string =
    let x = f().valueOr:
      return $error

    "ok"

  doAssert g(int) == "f"

  proc g2(T: type): string =
    bind error # use the bad version on purpose
    let x = f().valueOr:
      return $error

    "ok"

  doAssert g2(int) == "error"

block: # issue #23865
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
  proc g(T: type): string =
    let x = f().valueOr:
      return $error
    "ok"
  doAssert g(int) == "f"

import sequtils

block: # issue #12283
  var b = 5
  type Foo[T] = object
    h, w: int
  proc bar[T](foos: seq[Foo[T]]): T =
    let w = foldl(foos, a + b.w, 0)
    w
  let foos = @[Foo[int](h: 3, w: 5), Foo[int](h: 4, w: 6)]
  doAssert bar(foos) == 11

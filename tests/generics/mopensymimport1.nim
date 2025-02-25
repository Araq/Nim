type
  Result*[T, E] = object
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

template valueOr*[T: not void, E](self: Result[T, E], def: untyped): untyped =
  let s = (self) # TODO avoid copy
  case s.oResultPrivate
  of true:
    s.vResultPrivate
  of false:
    when E isnot void:
      template error: untyped {.used, inject.} = s.eResultPrivate
    def

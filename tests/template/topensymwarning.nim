discard """
  matrix: "--skipParentCfg --filenames:legacyRelProj"
"""

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
    {.push warningAsError[IgnoredSymbolInjection]: on.}
    # test spurious error
    discard true
    let _ = f
    {.pop.}
    res = $error #[tt.Warning
           ^ a new symbol 'error' has been injected during template or generic instantiation, however 'error' [enumField declared in topensymwarning.nim(6, 3)] captured at the proc declaration will be used instead; either enable --experimental:openSym to use the injected symbol, or `bind` this captured symbol explicitly [IgnoredSymbolInjection]]#
    123
  res

discard g(int)

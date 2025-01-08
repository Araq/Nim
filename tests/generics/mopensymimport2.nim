{.experimental: "openSym".}

import mopensymimport1

type Xxx = enum
  error
  value

proc f(): Result[int, cstring] =
  Result[int, cstring](oResultPrivate: false, eResultPrivate: "f")

proc g*(T: type): string =
  let x = f().valueOr:
    return $error

  "ok"

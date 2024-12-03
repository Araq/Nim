import macros

macro myMacro(n) =
  let x = if true: newLit"test" else: error "error", n

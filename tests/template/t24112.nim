discard """
  matrix: "--skipParentCfg --filenames:legacyRelProj --hints:off"
  action: reject
"""

# issue #24112, needs --experimental:openSym disabled

block: # simplified
  type
    SomeObj = ref object # Doesn't error if you make SomeObj be non-ref
  template foo = yield SomeObj()
  when compiles(foo): discard

import std/asyncdispatch
block:
  proc someProc(): Future[void] {.async.} = discard
  proc foo() =
    await someProc() #[tt.Error
                  ^ Can only 'await' inside a proc marked as 'async'. Use 'waitFor' when calling an 'async' proc in a non-async scope instead]#

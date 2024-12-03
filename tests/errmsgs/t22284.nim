discard """
  errormsg: "j(uRef, proc (config: F; sources: auto) {.raises: [].} = discard ) can raise an unlisted exception: Exception"
"""

import std/macros

macro h(): untyped =
  result = newTree(nnkStmtList)
  result.add quote do:
    new int

type F = object

proc j[SecondarySources](
    uRef: ref SecondarySources,
    u: proc (config: F, sources: ref SecondarySources)): F =
  u(result, uRef)

template programMain(body: untyped) =
  proc main {.raises: [].} = body  # doesn't SIGSEGV without this {.raises: [].}
  main()

programMain:
  var uRef = h()
  discard j(uRef, u = proc(config: F, sources: auto) {.raises: [].} = discard)
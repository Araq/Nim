# issue #23249

type Control* = object
proc onAction*(c: Control, handler: proc(e: int) {.gcsafe.}) = discard
proc onAction*(c: Control, handler: proc() {.gcsafe.}) = discard

template setControlHandlerBlock(c: Control, p: untyped, a: untyped) =
    when compiles(c.p(nil)):
        c.p() do() {.gcsafe.}: a
    else:
        c.p = proc() {.gcsafe.} =
            a

proc mkLayout() =
  var b: Control
  setControlHandlerBlock(b, onAction):
    echo "hi"

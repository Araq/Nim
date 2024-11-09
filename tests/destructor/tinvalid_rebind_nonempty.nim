discard """
disabled: true
joinable: false
cmd: "nim check $file"
errormsg: "cannot bind another '=destroy' to: Foo; previous declaration was constructed here implicitly: tinvalid_rebind.nim(12, 7)"
line: 14
"""

type
  Foo[T] = object
    x: T

proc main =
  var f: Foo[int]

proc `=destroy`[T](f: var Foo[T]) =
  discard

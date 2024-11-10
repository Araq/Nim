discard """
joinable: false
cmd: "nim check $file"
errormsg: "cannot bind another '=destroy' to: Foo; previous declaration was constructed implicitly"
line: 14
"""

type
  Foo[T] = object

proc main =
  var f: Foo[int]

proc `=destroy`[T](f: var Foo[T]) =
  discard

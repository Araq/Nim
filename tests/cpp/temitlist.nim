discard """
  targets: "cpp"
  output: '''
6.0
0'''
"""

# bug #4730

type Vector*[T] {.importcpp: "std::vector", header: "<vector>".} = object

template `[]=`*[T](v: var Vector[T], key: int, val: T) =
  {.emit: [v, "[", key, "] = ", val, ";"].}

proc setLen*[T](v: var Vector[T]; size: int) {.importcpp: "resize", nodecl.}
proc `[]`*[T](v: var Vector[T], key: int): T {.importcpp: "(#[#])", nodecl.}

proc main =
  var v: Vector[float]
  v.setLen 1
  v[0] = 6.0
  echo v[0]

main()

#------------

#bug #6837
type StdString {.importCpp: "std::string", header: "<string>", byref.} = object
proc initString(): StdString {.constructor, importCpp: "std::string(@)", header: "<string>".}
proc size(this: var StdString): csize_t {.importCpp: "size", header: "<string>".}

proc f(): csize_t =
  var myString: StdString = initString()
  return myString.size()

echo f()
